defmodule HacLong.Game.Gear do
  @moduledoc """
  Đồ rơi / rèn / mở rương, từng món một bản riêng (kiểu MU, DECISIONS B-15). Hàm thuần, như `Engine`.

  Khác đồ thường (đếm theo loại trong `inv`), mỗi món ở đây là một bản riêng, lưu trong
  `gear: [%{uid, base, rarity, bonus}]` của nhân vật:

  - `uid`: bắt đầu bằng `#`, dùng thay id đồ ở `equip`, `sell`, `upgrades`...
  - `base`: đồ gốc trong `ITEMS` (`priv/game_data/items.json`) (quyết định chỗ mặc, tấn công/phòng thủ, cấp cần).
  - `rarity`, `bonus`: hệ độ hiếm cũ (Tốt / Hiếm / Sử Thi, chỉ số cộng ngẫu nhiên), đã bỏ theo kiểu MU
    (B-15). Đồ mới luôn `rarity: 0, bonus: %{}`; giữ hai trường để không đổi schema / nhật ký đồ. Đồ cũ
    khi nạp (`load/1`) đổi `rarity` N thành N dòng cộng thêm (`opt`) và bỏ `bonus`.
  - `locked: true` (không bắt buộc): đã khóa, không bán / rao chợ / giao dịch / bỏ vào máy ghép được.
  - `stored: true`: đang cất trong Tủ Đồ ở Nhà (`HacLong.Game.Storage`), không nằm trong túi.
  - `opt`: số dòng cộng thêm kiểu MU (0–4, mỗi dòng `RULES.upgrade.life.per_line` tấn công / phòng thủ): rơi kèm
    theo trọng số (`roll/4`) hoặc thêm bằng Ngọc Sinh Mệnh (`Engine.life/2`).
  - `exc`: dòng Excellent (Phase 15c); `luck: true` / `skill: true`: dòng May mắn / Kỹ năng (Phase 15d,
    `RULES.luck_skill`); `anc: true`: đồ Bộ Thần (Phase 15g, `RULES.ancient`); `wopt`: dòng phụ của cánh `"hp" | "mp" | "ignore_def"` (Phase 15e, `RULES.wing_options`).

  Đồ đang mặc vẫn nằm trong `gear` (`equip` chỉ trỏ tới `uid`).
  """

  alias HacLong.Game.{Data, Rng}

  @max_bag 20
  # số ở `RULES.loot`, `RULES.shop` (`priv/game_data/rules.json`)
  @loot Data.rules().loot
  @shop Data.rules().shop
  @weights Enum.map(@loot.gear_weights, &List.to_tuple/1)
  @slots Enum.map(@loot.gear_slots, &List.to_tuple/1)
  # Phase 15c: đồ Excellent (`RULES.excellent`)
  @exc Data.rules().excellent
  @exc_lines Enum.map(@exc.lines, &List.to_tuple/1)
  @exc_zero %{
    atk_pct: 0,
    crit: 0,
    heal_kill: 0,
    mp_kill: 0,
    atk_lvl: 0,
    ar_pct: 0,
    hp_pct: 0,
    dmg_red: 0,
    gold_pct: 0,
    mp_pct: 0,
    reflect: 0,
    def_rate: 0
  }
  # Phase 15d: May mắn / Kỹ năng (`RULES.luck_skill`)
  @ls Data.rules().luck_skill
  # Phase 15g: đồ Bộ Thần (`RULES.ancient`)
  @anc Data.rules().ancient
  # Phase 15e: dòng phụ của cánh (`RULES.wing_options`), theo bậc cánh
  @wopt Map.new(Data.rules().wing_options.by_tier, &{&1.tier, Map.delete(&1, :tier)})
  @wopt_ids ~w(hp mp ignore_def)
  @set_pieces ~w(helm armor pants gloves boots)
  @life Data.rules().upgrade.life

  def max_bag, do: @max_bag

  @doc "Tỉ lệ số dòng cộng thêm mặc định của đồ rơi (`RULES.loot.gear_weights`, `[{số_dòng, tỉ_lệ}]`)."
  def weights, do: @weights

  @doc "Số dòng cộng thêm tối đa của một món (`RULES.upgrade.life.max_lines`)."
  def max_opt, do: @life.max_lines

  @doc """
  Loại món kiểu MU để ghi trong tin nhắn và tô màu ở client: `"anc"` đồ Thần, `"exc"` đồ hoàn hảo,
  `"opt"` đồ thường có May mắn / Kỹ năng / dòng cộng thêm, `""` đồ thường.
  """
  def kind(g) do
    cond do
      g[:anc] == true -> "anc"
      (g[:exc] || []) != [] -> "exc"
      g[:luck] == true or g[:skill] == true or (g[:opt] || 0) > 0 -> "opt"
      true -> ""
    end
  end

  @doc "Tên món kèm loại cho tin nhắn: `Kiếm Rồng (Hoàn hảo)`, `Mũ Đồng (cộng thêm 8)`, `Giáp Da`."
  def label(g) do
    name = resolve(g).name

    tag =
      case kind(g) do
        "anc" -> "Đồ Thần"
        "exc" -> "Hoàn hảo"
        _ -> if (g[:opt] || 0) > 0, do: "cộng thêm #{g.opt * @life.per_line}", else: nil
      end

    if tag, do: "#{name} (#{tag})", else: name
  end

  def instance?(id), do: is_binary(id) and String.starts_with?(id, "#")

  def list(p), do: Map.get(p, :gear) || []

  def find(p, uid), do: Enum.find(list(p), &(&1.uid == uid))

  def equipped?(p, uid), do: uid in Map.values(p.equip)

  @doc "Món trong túi (không đang mặc, không cất trong Tủ Đồ)."
  def bag(p), do: Enum.reject(list(p), &(equipped?(p, &1.uid) or &1[:stored]))

  @doc """
  Thông tin món đồ `id` như `Data.item/1`: đồ thường lấy thẳng; đồ ngẫu nhiên thì lấy đồ
  gốc và thêm `uid`, `kind`, các dòng (`opt`, `exc`, `luck`…), `sell`.
  """
  def item(_p, nil), do: nil

  def item(p, id) do
    if instance?(id) do
      case find(p, id) do
        nil -> nil
        g -> resolve(g)
      end
    else
      Data.item(id)
    end
  end

  def resolve(g) do
    base = Data.item(g.base)

    base
    |> Map.merge(%{
      uid: g.uid,
      base: g.base,
      kind: kind(g),
      locked: g[:locked] == true,
      stored: g[:stored] == true,
      opt: g[:opt] || 0,
      exc: g[:exc] || [],
      excellent: (g[:exc] || []) != [],
      # dòng Excellent kèm giá trị, cho client hiện chữ
      exc_lines: for(e <- g[:exc] || [], do: %{id: e, value: exc_value(base.slot, e)}),
      luck: g[:luck] == true,
      skill: g[:skill] == true,
      wopt: g[:wopt],
      anc: g[:anc] == true,
      wopt_value: g[:wopt] && wopt_value(base[:tier], g[:wopt]),
      sell: price(g)
    })
    |> anc_def(base, g)
  end

  @doc "Giá bán: giá đồ gốc tăng theo số dòng cộng thêm, Excellent, May mắn / Kỹ năng, đồ Thần."
  def price(g) do
    # đồ không bán ở cửa hàng (giá 0) tính như giá 200, như `Engine.sell_price/1`
    base = with 0 <- Data.item(g.base).price, do: @shop.unpriced_value

    exc = if (g[:exc] || []) != [], do: @exc.price_mult, else: 1
    ls = Enum.count([g[:luck], g[:skill]], &(&1 == true))
    exc = if g[:anc] == true, do: exc * @anc.price_mult, else: exc

    round(
      base * @shop.sell_ratio * (1 + @shop.gear_opt_value * (g[:opt] || 0)) * exc *
        @ls.price_mult ** ls
    )
  end

  # ---------- Rơi đồ ----------

  @doc "Tỉ lệ rơi đồ ngẫu nhiên khi hạ quái `m`."
  def drop_chance(m) do
    cond do
      m[:world] || m[:pvp] -> 0
      m[:elite] -> @loot.gear_chance.elite
      m[:night] -> @loot.gear_chance.night
      m.boss -> @loot.gear_chance.boss
      true -> @loot.gear_chance.normal
    end
  end

  @doc """
  Tạo một món ngẫu nhiên hợp với quái cấp `level` (nil nếu không có đồ gốc phù hợp);
  `slot` chọn loại đồ (mặc định ngẫu nhiên).
  `weights`: tỉ lệ số dòng cộng thêm `[{số_dòng, tỉ_lệ}]` (mặc định `RULES.loot.gear_weights`; tối đa
  `RULES.upgrade.life.max_lines` dòng).
  """
  def roll(level, weights \\ @weights, slot \\ nil, cls \\ nil) do
    bases =
      case slot do
        nil ->
          r = Rng.uniform()

          first =
            Enum.find_value(@slots, fn {t, s} -> if r < t, do: s end) ||
              @slots |> List.last() |> elem(1)

          # ô bốc được chưa có đồ hợp cấp / lớp (vd khiên dưới cấp 4): thử các ô còn lại
          Enum.find_value([first | Enum.map(@slots, &elem(&1, 1))], [], fn s ->
            case slot_bases(s, level, cls) do
              [] -> nil
              b -> b
            end
          end)

        s ->
          slot_bases(s, level, cls)
      end

    case bases do
      [] ->
        nil

      _ ->
        {base, _} = Enum.at(bases, floor(Rng.uniform() * length(bases)))
        new(base, pick_weighted(weights))
    end
  end

  # "set": một món bất kỳ của bộ giáp (mũ, giáp, quần, găng, giày) có đồ hợp cấp / lớp
  defp slot_bases("set", level, cls) do
    case @set_pieces |> Enum.map(&bases(&1, level, cls)) |> Enum.reject(&(&1 == [])) do
      [] -> []
      groups -> Enum.at(groups, floor(Rng.uniform() * length(groups)))
    end
  end

  # "jewelry": nhẫn hoặc dây chuyền (Phase 15c)
  defp slot_bases("jewelry", level, cls) do
    case ~w(ring pendant) |> Enum.map(&bases(&1, level, cls)) |> Enum.reject(&(&1 == [])) do
      [] -> []
      groups -> Enum.at(groups, floor(Rng.uniform() * length(groups)))
    end
  end

  defp slot_bases(slot, level, cls), do: bases(slot, level, cls)

  @doc "Id đồ gốc có thể rơi ở ô `slot` từ quái cấp `level` (mọi lớp), cho Thư viện."
  def drop_ids(slot, level), do: bases(slot, level, nil) |> Enum.map(&elem(&1, 0))

  # Đồ gốc thuộc 2 mức cấp cao nhất (≤ `level`) của ô `slot`: có giá, không phải đồ trùm, không phải đồ cũ
  # đã thay (Phase 15b), hợp lớp `cls` (nil: lớp nào cũng được). Lấy theo mức cấp chứ không theo số món để
  # món phụ (`alt`, Phase 19) cùng bậc không đẩy bậc dưới ra khỏi danh sách rơi.
  defp bases(slot, level, cls) do
    Data.items()
    |> Enum.filter(fn {id, it} ->
      it.slot == slot and it.price > 0 and !it[:drop] and !Data.legacy?(id) and
        (it[:level] || 1) <= level and (cls == nil or HacLong.Game.Engine.class_ok?(it, cls))
    end)
    |> top_levels(2)
  end

  defp top_levels(items, n) do
    keep =
      items
      |> Enum.map(fn {_, it} -> it.level end)
      |> Enum.uniq()
      |> Enum.sort(:desc)
      |> Enum.take(n)

    items
    |> Enum.filter(fn {_, it} -> it.level in keep end)
    |> Enum.sort_by(fn {id, it} -> {-it.level, id} end)
  end

  defp pick_weighted(weights) do
    r = Rng.uniform() * (weights |> Enum.map(&elem(&1, 1)) |> Enum.sum())

    Enum.reduce_while(weights, 0, fn {v, w}, acc ->
      if r < acc + w, do: {:halt, v}, else: {:cont, acc + w}
    end)
  end

  defp shuffle(list),
    do: list |> Enum.map(&{Rng.uniform(), &1}) |> Enum.sort() |> Enum.map(&elem(&1, 1))

  # ---------- Excellent (Phase 15c) ----------
  @exc_ids (Map.keys(@exc.options.weapon) ++ Map.keys(@exc.options.armor))
           |> Enum.map(&Atom.to_string/1)

  @doc "Tỉ lệ một món rơi từ quái `m` là Excellent (`RULES.excellent.chance`)."
  def exc_chance(m) do
    c = @exc.chance

    cond do
      m[:world] || m[:pvp] -> 0
      m[:elite] -> c.elite
      m[:night] -> c.night
      m[:boss] -> c.boss
      true -> c.normal
    end
  end

  @doc """
  Làm món `g` thành Excellent với xác suất `chance`: số dòng theo `excellent.lines`, dòng chọn ngẫu nhiên (không
  trùng) trong `options.weapon` (vũ khí, dây chuyền) hoặc `options.armor` (còn lại). Cánh không có Excellent.
  """
  def excellent(nil, _chance), do: nil

  def excellent(g, chance) do
    it = Data.item(g.base)

    if it && it.slot != "wing" && Rng.uniform() < chance do
      pool =
        it.slot |> exc_type() |> then(&Map.keys(@exc.options[&1])) |> Enum.map(&Atom.to_string/1)

      n = min(pick_weighted(@exc_lines), length(pool))
      Map.put(g, :exc, pool |> Enum.sort() |> shuffle() |> Enum.take(n))
    else
      g
    end
  end

  @doc "Các dòng Excellent có thể có của món loại `slot`."
  def exc_pool(slot),
    do: slot |> exc_type() |> then(&Map.keys(@exc.options[&1])) |> Enum.map(&Atom.to_string/1)

  @doc "Thêm một dòng Excellent chưa có (ngẫu nhiên) cho món `g` (Máy Hỗn Nguyên, Phase 15f)."
  def add_exc_line(g) do
    have = g[:exc] || []

    case (exc_pool(Data.item(g.base).slot) -- have) |> Enum.sort() do
      [] -> g
      free -> Map.put(g, :exc, have ++ [Enum.at(free, floor(Rng.uniform() * length(free)))])
    end
  end

  defp exc_type(slot) when slot in ~w(weapon pendant), do: :weapon
  defp exc_type(_), do: :armor

  @doc "Giá trị một dòng Excellent `id` của món loại `slot`."
  def exc_value(slot, id) when is_binary(id) do
    if id in @exc_ids, do: @exc.options[exc_type(slot)][String.to_existing_atom(id)] || 0, else: 0
  end

  @doc """
  Tổng dòng Excellent của các món đang mặc: `%{atk_pct, crit, heal_kill, mp_kill, atk_lvl, ar_pct, hp_pct, dmg_red,
  gold_pct, mp_pct, reflect, def_rate}` (giảm sát thương tối đa `excellent.max_dmg_red`, phản sát thương tối đa
  `excellent.max_reflect`).
  """
  def exc_stats(p) do
    p.equip
    |> Map.values()
    |> Enum.filter(&instance?/1)
    |> Enum.map(&find(p, &1))
    |> Enum.reject(&(is_nil(&1) or (&1[:exc] || []) == []))
    |> Enum.reduce(@exc_zero, fn g, acc ->
      slot = Data.item(g.base).slot

      Enum.reduce(g.exc, acc, fn id, acc ->
        Map.update!(acc, String.to_existing_atom(id), &(&1 + exc_value(slot, id)))
      end)
    end)
    |> Map.update!(:dmg_red, &min(&1, @exc.max_dmg_red))
    |> Map.update!(:reflect, &min(&1, @exc.max_reflect))
  end

  # ---------- May mắn / Kỹ năng (Phase 15d) ----------

  @doc "Tỉ lệ một món rơi từ quái `m` có May mắn (`RULES.luck_skill.luck_chance`)."
  def luck_chance(m) do
    c = @ls.luck_chance

    cond do
      m[:world] || m[:pvp] -> 0
      m[:elite] -> c.elite
      m[:night] -> c.night
      m[:boss] -> c.boss
      true -> c.normal
    end
  end

  @doc """
  Thêm dòng May mắn (xác suất `luck_chance`, mọi món trừ cánh) và Kỹ năng (xác suất `skill_chance`, chỉ vũ khí)
  cho món `g` rơi từ quái `m`. Quái không rơi đồ thường (đấu trường, trùm thế giới) thì không bốc.
  """
  def luck_skill(nil, _m), do: nil

  def luck_skill(g, m) do
    case {Data.item(g.base), luck_chance(m)} do
      {%{slot: slot}, lc} when slot != "wing" and lc > 0 ->
        g = if Rng.uniform() < lc, do: Map.put(g, :luck, true), else: g

        if slot == "weapon" and Rng.uniform() < @ls.skill_chance,
          do: Map.put(g, :skill, true),
          else: g

      _ ->
        g
    end
  end

  @doc """
  May mắn / Kỹ năng của vũ khí đang cầm: `%{crit, skill_dmg}` (chí mạng, sát thương chiêu cộng thêm).
  Giáp / trang sức May mắn chỉ giúp ép ngọc (`luck_rate/2`).
  """
  def luck_skill_stats(p) do
    w = (p.equip[:weapon] && instance?(p.equip.weapon) && find(p, p.equip.weapon)) || %{}

    %{
      crit: if(w[:luck] == true, do: @ls.luck_crit, else: 0),
      skill_dmg: if(w[:skill] == true, do: @ls.skill_dmg, else: 0)
    }
  end

  @doc "Tỉ lệ ép ngọc `rate` của món `it` (thông tin món, `resolve/1`): May mắn cộng `luck_upgrade`, tối đa `luck_max_rate`."
  def luck_rate(it, rate) do
    if is_map(it) and it[:luck] == true and rate < 1,
      do: max(rate, min(@ls.luck_max_rate, Float.round(rate + @ls.luck_upgrade, 3))),
      else: rate
  end

  def luck_skill_rules, do: @ls

  # ---------- Bộ Thần (Phase 15g) ----------

  # phòng thủ của món Thần tăng `piece_def_pct`; đồ không có phòng thủ (nhẫn, dây chuyền…) giữ nguyên, không thêm
  # khóa `def` (khóa `def: nil` làm `Engine.derived` cộng nil)
  defp anc_def(r, base, g) do
    if g[:anc] == true and is_number(base[:def]),
      do: Map.put(r, :def, round(base.def * (1 + @anc.piece_def_pct))),
      else: r
  end

  @doc "Tỉ lệ một món bộ giáp rơi từ quái `m` là đồ Thần (`RULES.ancient.chance`)."
  def anc_chance(m) do
    c = @anc.chance

    cond do
      m[:world] || m[:pvp] -> 0
      m[:elite] -> c.elite
      m[:night] -> c.night
      m[:boss] -> c.boss
      true -> c.normal
    end
  end

  @doc "Món bộ giáp `g` rơi từ quái `m` thành đồ Thần với xác suất `anc_chance/1` (món khác không bốc)."
  def ancient(nil, _m), do: nil

  def ancient(g, m) do
    case Data.item(g.base) do
      %{set: s, slot: slot} when is_binary(s) and slot in @set_pieces ->
        c = anc_chance(m)
        if c > 0 and Rng.uniform() < c, do: Map.put(g, :anc, true), else: g

      _ ->
        g
    end
  end

  def ancient_rules, do: @anc

  # ---------- Dòng phụ của cánh (Phase 15e) ----------

  @doc "Giá trị dòng cánh `id` (`hp` / `mp` / `ignore_def`) của cánh bậc `tier` (0 nếu bậc đó không có dòng)."
  def wopt_value(tier, id) when id in @wopt_ids,
    do: get_in(@wopt, [tier, String.to_existing_atom(id)]) || 0

  def wopt_value(_tier, _id), do: 0

  @doc "Bậc cánh `tier` có dòng phụ không (`RULES.wing_options.by_tier`)."
  def wopt_tier?(tier), do: Map.has_key?(@wopt, tier)

  def wopt_ids, do: @wopt_ids

  @doc "Bốc một dòng phụ (đều nhau) cho cánh `g` nếu bậc cánh có dòng; không thì trả nguyên."
  def wing_option(g) do
    case Data.item(g.base) do
      %{slot: "wing", tier: tier} ->
        if wopt_tier?(tier),
          do: Map.put(g, :wopt, Enum.at(@wopt_ids, floor(Rng.uniform() * length(@wopt_ids)))),
          else: g

      _ ->
        g
    end
  end

  @doc "Dòng phụ của cánh đang mặc: `%{hp, mp, ignore_def}`."
  def wing_stats(p) do
    zero = %{hp: 0, mp: 0, ignore_def: 0}
    id = p.equip[:wing]
    g = id && instance?(id) && find(p, id)

    case g && g[:wopt] do
      w when w in @wopt_ids ->
        Map.put(zero, String.to_existing_atom(w), wopt_value(Data.item(g.base)[:tier], w))

      _ ->
        zero
    end
  end

  @doc "Món đồ `base` với `opt` dòng cộng thêm (0..`RULES.upgrade.life.max_lines`)."
  def new(base, opt \\ 0) do
    g = %{uid: new_uid(), base: base, rarity: 0, bonus: %{}}
    opt = min(opt, @life.max_lines)
    if opt > 0, do: Map.put(g, :opt, opt), else: g
  end

  @doc "Bản riêng của một món đồ thường (không dòng nào), để có cấp nâng / khóa riêng từng món."
  def plain(base), do: new(base)

  def locked?(p, uid), do: match?(%{locked: true}, find(p, uid))

  @doc "Món `uid` đang cất trong Tủ Đồ ở Nhà (`HacLong.Game.Storage`): không mặc / bán / đổi được."
  def stored?(p, uid), do: match?(%{stored: true}, find(p, uid))

  @doc "Đặt một trường của món `uid` (`nil` là bỏ trường đó)."
  def put(p, uid, key, value) do
    Map.put(
      p,
      :gear,
      Enum.map(list(p), fn
        %{uid: ^uid} = g ->
          if value in [nil, false, 0], do: Map.delete(g, key), else: Map.put(g, key, value)

        g ->
          g
      end)
    )
  end

  @doc "Khóa / mở khóa món `uid`."
  def set_locked(p, uid, on?) do
    Map.put(
      p,
      :gear,
      Enum.map(list(p), fn
        %{uid: ^uid} = g -> if on?, do: Map.put(g, :locked, true), else: Map.delete(g, :locked)
        g -> g
      end)
    )
  end

  defp new_uid, do: "#" <> Base.encode32(:crypto.strong_rand_bytes(5), padding: false)

  @doc """
  Thêm món `g` vào túi. Túi đầy (#{@max_bag} món chưa mặc) thì xếp vào hàng gửi Hộp thư (`:mail_out`,
  `Session` gửi khi lưu nhân vật; hộp thư đầy mới bán, `HacLong.Mailbox.send_overflow/2`).
  Trả về `{nhân_vật, :kept | :mailed}`.
  """
  def add(p, g) do
    if length(bag(p)) >= @max_bag do
      {Map.update(p, :mail_out, [g], &(&1 ++ [g])), :mailed}
    else
      {Map.put(p, :gear, list(p) ++ [g]), :kept}
    end
  end

  def remove(p, uid), do: Map.put(p, :gear, Enum.reject(list(p), &(&1.uid == uid)))

  @doc "Đọc từ database (khóa chuỗi) về dạng engine dùng."
  def load(list) when is_list(list) do
    for g <- list, Data.item(g["base"]) do
      # B-15: độ hiếm cũ (Tốt / Hiếm / Sử Thi) thành dòng cộng thêm, bỏ chỉ số cộng ngẫu nhiên
      m = %{uid: g["uid"], base: g["base"], rarity: 0, bonus: %{}}

      m = if g["locked"] == true, do: Map.put(m, :locked, true), else: m
      m = if g["stored"] == true, do: Map.put(m, :stored, true), else: m
      m = if g["luck"] == true, do: Map.put(m, :luck, true), else: m
      m = if g["skill"] == true, do: Map.put(m, :skill, true), else: m
      m = if g["anc"] == true, do: Map.put(m, :anc, true), else: m
      m = if g["wopt"] in @wopt_ids, do: Map.put(m, :wopt, g["wopt"]), else: m
      opt = max(int(g["opt"]), int(g["rarity"])) |> min(@life.max_lines)
      m = if opt > 0, do: Map.put(m, :opt, opt), else: m
      exc = for e <- g["exc"] || [], e in @exc_ids, do: e
      if exc == [], do: m, else: Map.put(m, :exc, exc)
    end
  end

  def load(_), do: []

  defp int(n) when is_integer(n), do: n
  defp int(_), do: 0
end
