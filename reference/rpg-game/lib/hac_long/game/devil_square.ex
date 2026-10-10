defmodule HacLong.Game.DevilSquare do
  @moduledoc """
  Quảng Trường Quỷ (Phase 18 M1, `docs/EVENTS_PHASE18.md`; số ở `RULES.devil_square`). Hàm thuần, như `Tower`.

  Là một **chế độ của Tháp Vô Tận**: chạy trên bản đồ riêng `tower` của từng người, trạng thái nằm trong
  `p.tower` (cột `tower` sẵn có, không đổi schema) với thêm `ds: %{level, ends_at, score, waves}`; `floor` là số đợt.

  - Mở theo lịch (`open?/1`): mỗi `every_hours` giờ (giờ Việt Nam) lệch `offset_hours`, vào trong `entry_minutes`
    phút; mỗi đợt mở chỉ vào một lần (`daily.ds_slot`).
  - Vào (`enter/2`): từ `min_level`, tốn 1 vé `ticket` (mua `buy_ticket/1` giá `ticket_price`).
  - Mỗi đợt (`waves`) là một bãi quái; hạ hết thì cầu thang `>` mở sang đợt sau; đợt cuối có trùm. Lượt dài
    `run_minutes` phút: hết giờ, gục ngã, qua hết đợt hoặc tự ra (`<`) thì kết thúc và **tính thưởng theo điểm**
    (`finish/2`).
  - Điểm cao nhất trong ngày lưu ở `daily.ds_best`; bảng xếp hạng ngày + thưởng top 3 ở `HacLong.DevilSquareBoard`.
  """

  alias HacLong.Game.{Data, Engine, Gear, Rng, Tower}

  @rules Data.rules().devil_square
  # giờ Việt Nam
  @utc_offset 7 * 3600

  def rules, do: @rules
  def ticket, do: @rules.ticket

  # ---------- Lịch ----------

  @doc """
  Đợt mở chứa thời điểm `now` (DateTime UTC): `%{slot, opens_at, closes_at}` (unix) nếu đang cho vào, `nil` nếu không.
  `slot` là số thứ tự đợt (để chặn vào lại cùng đợt).
  """
  def window(now \\ DateTime.utc_now()) do
    local = DateTime.to_unix(now) + @utc_offset - @rules.offset_hours * 3600
    step = @rules.every_hours * 3600
    slot = div(local, step)
    start = slot * step

    if always_open?() or local - start < @rules.entry_minutes * 60 do
      opens = start - @utc_offset + @rules.offset_hours * 3600
      %{slot: slot, opens_at: opens, closes_at: opens + @rules.entry_minutes * 60}
    end
  end

  def open?(now \\ DateTime.utc_now()), do: window(now) != nil

  @doc "Lần mở tiếp theo (unix) sau `now`."
  def next_open(now \\ DateTime.utc_now()) do
    local = DateTime.to_unix(now) + @utc_offset - @rules.offset_hours * 3600
    step = @rules.every_hours * 3600
    (div(local, step) + 1) * step - @utc_offset + @rules.offset_hours * 3600
  end

  # `config :hac_long, :devil_square_always_open, true` (biến môi trường HL_DS_OPEN=1): luôn mở (thử, e2e)
  defp always_open?, do: Application.get_env(:hac_long, :devil_square_always_open, false) == true

  @doc "Thông tin cho giao diện (bảng Người Gác Tháp)."
  def view(p, now \\ DateTime.utc_now()) do
    w = window(now)
    daily = p[:daily] || %{}

    %{
      open: w != nil,
      closes_at: w && w.closes_at,
      next_at: next_open(now),
      used: w != nil and daily[:ds_slot] == w.slot,
      best: daily[:ds_best] || 0,
      price: @rules.ticket_price,
      min_level: @rules.min_level,
      run_minutes: @rules.run_minutes,
      waves: length(@rules.waves),
      tickets: Map.get(p.inv, @rules.ticket, 0)
    }
  end

  # ---------- Vé ----------

  @doc "Mua 1 vé bằng vàng."
  def buy_ticket(p) do
    price = @rules.ticket_price

    if p.gold < price,
      do: {%{ok: false, msg: "Cần #{price} vàng để mua vé."}, p},
      else:
        {%{ok: true, msg: "Đã mua #{Data.item(@rules.ticket).name} (−#{price} vàng)."},
         %{p | gold: p.gold - price} |> Engine.add_item(@rules.ticket)}
  end

  @doc "Tỉ lệ quái `m` rơi vé (quái thường cấp ≥ `ticket_drop.min_level`)."
  def ticket_chance(m) do
    d = @rules.ticket_drop
    if m[:world] || m[:pvp] || m[:tower] || m.level < d.min_level, do: 0, else: d.chance
  end

  # ---------- Vào ----------

  @doc "Cấp quái của lượt theo cấp người chơi (`tiers`)."
  def tier_level(level) do
    @rules.tiers |> Enum.filter(&(level >= &1.from)) |> List.last() |> then(&(&1 && &1.level))
  end

  @doc "Vào Quảng Trường (đang mở, đủ cấp, có vé, chưa vào đợt này). `now` để test."
  def enter(p, now \\ DateTime.utc_now()) do
    w = window(now)
    daily = p[:daily] || %{}

    cond do
      p.battle -> {%{ok: false, msg: "Đang trong trận đấu."}, p}
      p[:tower] -> {%{ok: false, msg: "Đang ở trong Tháp."}, p}
      p.hp <= 0 -> {%{ok: false, msg: "Bạn cần hồi máu trước."}, p}
      p.level < @rules.min_level -> {%{ok: false, msg: "Cần cấp #{@rules.min_level}."}, p}
      w == nil -> {%{ok: false, msg: "Quảng Trường Quỷ chưa mở cửa."}, p}
      daily[:ds_slot] == w.slot -> {%{ok: false, msg: "Bạn đã vào đợt này rồi."}, p}
      Map.get(p.inv, @rules.ticket, 0) < 1 -> {%{ok: false, msg: "Cần 1 Vé Quảng Trường."}, p}
      true -> {%{ok: true, msg: "Vào Quảng Trường Quỷ! Hạ quái thật nhanh."}, start(p, w, now)}
    end
  end

  defp start(p, w, now) do
    level = tier_level(p.level)

    ds = %{
      level: level,
      ends_at: DateTime.to_unix(now) + @rules.run_minutes * 60,
      score: 0,
      waves: length(@rules.waves)
    }

    p = %{p | inv: take(p.inv, @rules.ticket)}
    p = Map.put(p, :daily, Map.put(p[:daily] || %{}, :ds_slot, w.slot))
    go_wave(p, 1, ds)
  end

  defp take(inv, id) do
    if inv[id] > 1, do: Map.put(inv, id, inv[id] - 1), else: Map.delete(inv, id)
  end

  @doc "Đợt `n` (1…): bãi quái mới; `floor` của trạng thái tháp là số đợt."
  def go_wave(p, n, ds) do
    t = Tower.build(n, "ds|#{p.name}|#{System.unique_integer([:positive])}")
    [ex, ey] = t.exit
    t = Map.merge(t, %{monsters: wave_monsters(n, ds.level, t), ds: ds})
    p |> Map.put(:pos, %{map: Tower.map_id(), x: ex, y: ey - 1}) |> Map.put(:tower, t)
  end

  defp wave_monsters(n, level, t) do
    w = Enum.at(@rules.waves, n - 1)
    zones = Data.zones()
    zone = List.last(zones)
    lvl = level + w.add_level
    avoid = [List.to_tuple(t.stairs), List.to_tuple(t.exit)]
    {ex, ey} = List.to_tuple(t.exit)
    avoid = [{ex, ey - 1} | avoid]

    free =
      for {row, y} <- Enum.with_index(t.tiles),
          {c, x} <- Enum.with_index(String.graphemes(row)),
          c == ".",
          {x, y} not in avoid,
          do: {x, y}

    spots = free |> Enum.map(&{Rng.uniform(), &1}) |> Enum.sort() |> Enum.map(&elem(&1, 1))
    # trùm: trùm các vùng (trừ Hắc Long cuối game)
    bosses = zones |> Enum.map(& &1.boss) |> Enum.reject(&(&1[:final] == true))

    for i <- 0..(min(w.count, length(spots)) - 1) do
      {x, y} = Enum.at(spots, i)

      {kind, name} =
        if w.boss do
          b = Enum.at(bosses, floor(Rng.uniform() * length(bosses)))
          {b.id, b.name}
        else
          m = Enum.at(zone.monsters, floor(Rng.uniform() * length(zone.monsters)))
          {m.id, m.name}
        end

      %{id: i + 1, kind: kind, name: name, level: lvl, x: x, y: y, elite: w.boss}
    end
  end

  @doc "Quái dùng trong trận với con `m` ở Quảng Trường."
  def battle_monster(m) do
    base = if m.elite, do: Enum.find(Data.zones(), &(&1.boss.id == m.kind)).boss, else: %{}

    spec = %{
      id: m.kind,
      name: m.name,
      level: m.level,
      mult: if(m.elite, do: @rules.boss_mult, else: @rules.monster_mult),
      special: base[:special],
      on_hit: if(m.elite, do: nil, else: Data.monster(m.kind)[:on_hit])
    }

    q = Engine.make_monster(spec, false)
    q = if m.elite, do: %{q | maxHp: q.maxHp * @rules.boss_hp}, else: q
    Map.merge(q, %{hp: q.maxHp, tower: true, elite: m.elite, ds: true})
  end

  # ---------- Trong lượt ----------

  def active?(%{tower: %{ds: %{}}}), do: true
  def active?(_), do: false

  @doc "Hết giờ chưa."
  def expired?(%{tower: %{ds: %{ends_at: e}}}, now \\ DateTime.utc_now()),
    do: DateTime.to_unix(now) >= e

  @doc "Trận ở Quảng Trường vừa kết thúc: thắng thì cộng điểm, bỏ quái; gục ngã thì kết thúc lượt."
  def after_battle(
        %{tower: %{ds: ds} = t, battle: %{over: true, result: r, encounter: %{tower: id}}} = p
      ) do
    case r do
      "win" ->
        m = Enum.find(t.monsters, &(&1.id == id))
        pts = if m && m.elite, do: @rules.score.boss, else: @rules.score.monster

        t = %{
          t
          | monsters: Enum.reject(t.monsters, &(&1.id == id)),
            ds: %{ds | score: ds.score + pts}
        }

        %{p | tower: t}

      "lose" ->
        # gục ngã: Session / World xử lý chỗ hồi sinh như mọi trận thua, chỉ trả thưởng + ghi thông báo vào nhật ký
        {r, q} = finish(p, "gục ngã")
        q = Map.put(q, :pos, p[:pos])
        update_in(q.battle.log, &(&1 ++ [%{kind: "good", text: r.msg}]))

      _ ->
        p
    end
  end

  def after_battle(p), do: p

  @doc "Bước lên `>`: hết quái thì sang đợt sau (đợt cuối: kết thúc, thưởng thêm món đồ)."
  def climb(%{tower: %{ds: ds} = t} = p) do
    left = length(t.monsters)

    cond do
      expired?(p) -> finish(p, "hết giờ")
      left > 0 -> {%{ok: false, msg: "Hạ hết quái để sang đợt sau (còn #{left})."}, p}
      t.floor >= ds.waves -> finish(p, "qua hết #{ds.waves} đợt", true)
      true -> {%{ok: true, msg: "Đợt #{t.floor + 1}/#{ds.waves}!"}, go_wave(p, t.floor + 1, ds)}
    end
  end

  @doc "Thưởng theo điểm: `%{gold, xp, items, gear}` (`gear`: món đồ khi qua hết đợt hoặc nil)."
  def reward(level, score, cleared?) do
    r = @rules.reward

    jewels =
      Enum.reduce(1..div(score, r.jewel_every)//1, %{}, fn _, acc ->
        Map.update(acc, Engine.pick_jewel(), 1, &(&1 + 1))
      end)

    gear =
      if cleared? do
        g = Gear.roll(level, [{2, 60}, {3, 40}])
        g = g && Gear.excellent(g, r.clear_exc_chance)

        g &&
          if Data.item(g.base)[:set] && Rng.uniform() < r.clear_anc_chance,
            do: Map.put(g, :anc, true),
            else: g
      end

    %{
      gold: round(Engine.base_gold(level) * r.gold_per_point * score),
      xp: round(Engine.base_xp(level) * r.xp_per_point * score),
      items: jewels,
      gear: gear
    }
  end

  @doc """
  Kết thúc lượt (`why`: lý do cho thông báo): trả thưởng, ghi điểm cao nhất trong ngày (`daily.ds_best`), về Làng
  (cạnh Người Gác Tháp). Đặt `p.ds_result = %{score, level}` để Session ghi bảng xếp hạng.
  """
  def finish(%{tower: %{ds: ds}} = p, why, cleared? \\ false) do
    r = reward(ds.level, ds.score, cleared?)
    p = %{p | gold: p.gold + r.gold}
    p = Enum.reduce(r.items, p, fn {id, n}, p -> Engine.add_item(p, id, n) end)
    {_levels, p} = Engine.gain_xp(p, r.xp)

    {p, gear_txt} =
      case r.gear do
        nil ->
          {p, ""}

        g ->
          {p, _} = Gear.add(p, g)
          {p, ", #{Gear.resolve(g).name}"}
      end

    daily = p[:daily] || %{}
    best = max(daily[:ds_best] || 0, ds.score)

    p =
      p
      |> Map.put(:daily, Map.put(daily, :ds_best, best))
      |> Map.put(:tower, nil)
      |> Map.put(:pos, %{map: "village", x: 21, y: 9})
      |> Map.put(:ds_result, %{score: ds.score, level: ds.level})

    items =
      Enum.map_join(r.items, "", fn {id, n} ->
        ", #{Data.item(id).name}#{if n > 1, do: " ×#{n}", else: ""}"
      end)

    {%{
       ok: true,
       msg:
         "Quảng Trường Quỷ kết thúc (#{why}): #{ds.score} điểm, +#{r.gold} vàng, +#{r.xp} kinh nghiệm#{items}#{gear_txt}."
     }, p}
  end
end
