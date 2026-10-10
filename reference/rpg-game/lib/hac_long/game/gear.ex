defmodule HacLong.Game.Gear do
  @moduledoc """
  Đồ có chỉ số ngẫu nhiên (rơi từ quái). Hàm thuần, như `Engine`.

  Khác đồ thường (đếm theo loại trong `inv`), mỗi món ở đây là một bản riêng, lưu trong
  `gear: [%{uid, base, rarity, bonus}]` của nhân vật:

  - `uid`: bắt đầu bằng `#`, dùng thay id đồ ở `equip`, `sell`, `upgrades`...
  - `base`: đồ gốc trong `ITEMS` (`priv/game_data/items.json`) (quyết định chỗ mặc, tấn công/phòng thủ, cấp cần).
  - `rarity`: 1 Tốt, 2 Hiếm, 3 Sử Thi, bằng số dòng chỉ số cộng thêm. `0`: đồ thường đã tách
    thành bản riêng (`plain/1`) để có cấp nâng / khóa riêng từng món (đồ đã nâng cấp, đồ đã khóa, cánh).
  - `bonus`: `%{str | agi | vit | ene => điểm}` cộng vào chỉ số khi mặc.
  - `locked: true` (không bắt buộc): đã khóa, không bán / rao chợ / giao dịch / bỏ vào máy ghép được.
  - `stored: true`: đang cất trong Tủ Đồ ở Nhà (`HacLong.Game.Storage`), không nằm trong túi.
  - `opt`: số dòng Ngọc Sinh Mệnh (0–4, `Engine.life/2`).

  Đồ đang mặc vẫn nằm trong `gear` (`equip` chỉ trỏ tới `uid`).
  """

  alias HacLong.Game.{Data, Rng}

  @max_bag 20
  # số ở `RULES.loot`, `RULES.shop` (`priv/game_data/rules.json`)
  @loot Data.rules().loot
  @shop Data.rules().shop
  @weights Enum.map(@loot.gear_weights, &List.to_tuple/1)
  @slots Enum.map(@loot.gear_slots, &List.to_tuple/1)
  @stats ~w(str agi vit ene)a
  @set_pieces ~w(helm armor pants gloves boots)
  @rarity_names %{1 => "Tốt", 2 => "Hiếm", 3 => "Sử Thi"}
  @suffix %{str: "Sức Mạnh", agi: "Nhanh Nhẹn", vit: "Bền Bỉ", ene: "Linh Lực"}

  def max_bag, do: @max_bag
  @doc "Tỉ lệ độ hiếm mặc định của đồ rơi (`RULES.loot.gear_weights`)."
  def weights, do: @weights
  def rarity_names, do: @rarity_names

  def instance?(id), do: is_binary(id) and String.starts_with?(id, "#")

  def list(p), do: Map.get(p, :gear) || []

  def find(p, uid), do: Enum.find(list(p), &(&1.uid == uid))

  def equipped?(p, uid), do: uid in Map.values(p.equip)

  @doc "Món trong túi (không đang mặc, không cất trong Tủ Đồ)."
  def bag(p), do: Enum.reject(list(p), &(equipped?(p, &1.uid) or &1[:stored]))

  @doc """
  Thông tin món đồ `id` như `Data.item/1`: đồ thường lấy thẳng; đồ ngẫu nhiên thì lấy đồ
  gốc, đổi tên và thêm `uid`, `rarity`, `bonus`, `sell`.
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
    main = g.bonus |> Enum.max_by(fn {_, v} -> v end, fn -> {nil, 0} end) |> elem(0)

    base
    |> Map.merge(%{
      uid: g.uid,
      base: g.base,
      name: if(main, do: "#{base.name} #{@suffix[main]}", else: base.name),
      rarity: g.rarity,
      bonus: g.bonus,
      locked: g[:locked] == true,
      stored: g[:stored] == true,
      opt: g[:opt] || 0,
      sell: price(g)
    })
  end

  @doc "Giá bán: giá đồ gốc tăng theo độ hiếm và số điểm cộng thêm."
  def price(g) do
    # đồ không bán ở cửa hàng (giá 0) tính như giá 200, như `Engine.sell_price/1`
    base = with 0 <- Data.item(g.base).price, do: @shop.unpriced_value

    round(
      base * @shop.sell_ratio * (1 + @shop.gear_rarity_value * g.rarity) +
        @shop.gear_bonus_value * Enum.sum(Map.values(g.bonus))
    )
  end

  @doc "Tổng điểm chỉ số cộng thêm từ các món đang mặc."
  def bonus_stats(p) do
    p.equip
    |> Map.values()
    |> Enum.filter(&instance?/1)
    |> Enum.map(&find(p, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{}, fn g, acc -> Map.merge(acc, g.bonus, fn _, a, b -> a + b end) end)
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
  `weights`: tỉ lệ các độ hiếm `[{độ_hiếm, tỉ_lệ}]` (mặc định 5% Sử Thi, 25% Hiếm, 70% Tốt).
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
        rarity = pick_weighted(weights)

        stats = shuffle(@stats) |> Enum.take(rarity)

        bonus =
          Map.new(
            stats,
            &{&1, 1 + floor(Rng.uniform() * (1 + level / @loot.gear_bonus_per_level))}
          )

        %{uid: new_uid(), base: base, rarity: rarity, bonus: bonus}
    end
  end

  # "set": một món bất kỳ của bộ giáp (mũ, giáp, quần, găng, giày) có đồ hợp cấp / lớp
  defp slot_bases("set", level, cls) do
    case @set_pieces |> Enum.map(&bases(&1, level, cls)) |> Enum.reject(&(&1 == [])) do
      [] -> []
      groups -> Enum.at(groups, floor(Rng.uniform() * length(groups)))
    end
  end

  defp slot_bases(slot, level, cls), do: bases(slot, level, cls)

  # 2 đồ gốc cấp cao nhất (≤ `level`) của ô `slot`: có giá, không phải đồ trùm, không phải đồ cũ đã
  # thay (Phase 15b), hợp lớp `cls` (nil: lớp nào cũng được)
  defp bases(slot, level, cls) do
    Data.items()
    |> Enum.filter(fn {id, it} ->
      it.slot == slot and it.price > 0 and !it[:drop] and !Data.legacy?(id) and
        (it[:level] || 1) <= level and (cls == nil or HacLong.Game.Engine.class_ok?(it, cls))
    end)
    |> Enum.sort_by(fn {_, it} -> it.level end, :desc)
    |> Enum.take(2)
  end

  defp pick_weighted(weights) do
    r = Rng.uniform() * (weights |> Enum.map(&elem(&1, 1)) |> Enum.sum())

    Enum.reduce_while(weights, 0, fn {v, w}, acc ->
      if r < acc + w, do: {:halt, v}, else: {:cont, acc + w}
    end)
  end

  defp shuffle(list),
    do: list |> Enum.map(&{Rng.uniform(), &1}) |> Enum.sort() |> Enum.map(&elem(&1, 1))

  @doc "Món đồ với độ hiếm và chỉ số cho sẵn (quản trị viên tặng, `HacLong.Admin`)."
  def new(base, rarity, bonus), do: %{uid: new_uid(), base: base, rarity: rarity, bonus: bonus}

  def stats, do: @stats

  @doc "Bản riêng của một món đồ thường (độ hiếm 0, không chỉ số cộng thêm)."
  def plain(base), do: new(base, 0, %{})

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
  Thêm món `g` vào túi. Túi đầy (#{@max_bag} món chưa mặc) thì bán luôn.
  Trả về `{nhân_vật, :kept | {:sold, vàng}}`.
  """
  def add(p, g) do
    if length(bag(p)) >= @max_bag do
      {%{p | gold: p.gold + price(g)}, {:sold, price(g)}}
    else
      {Map.put(p, :gear, list(p) ++ [g]), :kept}
    end
  end

  def remove(p, uid), do: Map.put(p, :gear, Enum.reject(list(p), &(&1.uid == uid)))

  @doc "Đọc từ database (khóa chuỗi) về dạng engine dùng."
  def load(list) when is_list(list) do
    for g <- list, Data.item(g["base"]) do
      m = %{
        uid: g["uid"],
        base: g["base"],
        rarity: g["rarity"],
        bonus: Map.new(g["bonus"], fn {k, v} -> {String.to_existing_atom(k), v} end)
      }

      m = if g["locked"] == true, do: Map.put(m, :locked, true), else: m
      m = if g["stored"] == true, do: Map.put(m, :stored, true), else: m
      opt = g["opt"]
      if is_integer(opt) and opt > 0, do: Map.put(m, :opt, opt), else: m
    end
  end

  def load(_), do: []
end
