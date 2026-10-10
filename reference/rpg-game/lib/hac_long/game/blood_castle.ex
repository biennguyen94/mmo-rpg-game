defmodule HacLong.Game.BloodCastle do
  @moduledoc """
  Lâu Đài Máu (Phase 18 M2, `docs/EVENTS_PHASE18.md`; số ở `RULES.blood_castle`). Hàm thuần.

  Như Quảng Trường Quỷ (`HacLong.Game.DevilSquare`), chạy trên bản đồ riêng `tower` với trạng thái
  `p.tower.bc: %{level, ends_at, stage, guards, killed, done}` (cột `tower` sẵn có, không đổi schema).

  - Lịch: mỗi `every_hours` giờ (giờ Việt Nam) lệch `offset_minutes` phút, cho vào `entry_minutes` phút; mỗi đợt mở vào
    một lần (`daily.bc_slot`). Từ `min_level`, tốn 1 vé `ticket` (mua `ticket_price`).
  - Ba bước (`stage`): `"guards"` hạ `guards` quái canh → `"gate"` phá Cổng Thành (không đánh trả, nhiều máu) →
    `"boss"` hạ Hiệp Sĩ Máu. Hạ trùm thì thắng: thưởng `reward.success` (có Lông Vũ Kền Kền, nguyên liệu cánh cấp 3),
    lượt đánh dấu `done`, bước đi tiếp là về Làng.
  - Hết giờ (`run_minutes`), gục ngã hoặc tự ra trước khi hạ trùm: thưởng `reward.partial` theo số quái canh đã hạ.
  """

  alias HacLong.Game.{Data, Engine, Tower}

  @rules Data.rules().blood_castle
  @utc_offset 7 * 3600

  def rules, do: @rules
  def ticket, do: @rules.ticket

  # ---------- Lịch ----------

  @doc "Đợt mở chứa `now`: `%{slot, opens_at, closes_at}` (unix) hoặc nil."
  def window(now \\ DateTime.utc_now()) do
    local = DateTime.to_unix(now) + @utc_offset - @rules.offset_minutes * 60
    step = @rules.every_hours * 3600
    slot = div(local, step)
    start = slot * step

    if always_open?() or local - start < @rules.entry_minutes * 60 do
      opens = start - @utc_offset + @rules.offset_minutes * 60
      %{slot: slot, opens_at: opens, closes_at: opens + @rules.entry_minutes * 60}
    end
  end

  def open?(now \\ DateTime.utc_now()), do: window(now) != nil

  def next_open(now \\ DateTime.utc_now()) do
    local = DateTime.to_unix(now) + @utc_offset - @rules.offset_minutes * 60
    step = @rules.every_hours * 3600
    (div(local, step) + 1) * step - @utc_offset + @rules.offset_minutes * 60
  end

  # cùng cờ với Quảng Trường Quỷ (HL_DS_OPEN=1 mở luôn cả hai)
  defp always_open?, do: Application.get_env(:hac_long, :devil_square_always_open, false) == true

  @doc "Thông tin cho giao diện."
  def view(p, now \\ DateTime.utc_now()) do
    w = window(now)
    daily = p[:daily] || %{}

    %{
      open: w != nil,
      closes_at: w && w.closes_at,
      next_at: next_open(now),
      used: w != nil and daily[:bc_slot] == w.slot,
      price: @rules.ticket_price,
      min_level: @rules.min_level,
      run_minutes: @rules.run_minutes,
      guards: @rules.guards,
      tickets: Map.get(p.inv, @rules.ticket, 0)
    }
  end

  # ---------- Vé ----------

  def buy_ticket(p) do
    price = @rules.ticket_price

    if p.gold < price,
      do: {%{ok: false, msg: "Cần #{price} vàng để mua vé."}, p},
      else:
        {%{ok: true, msg: "Đã mua #{Data.item(@rules.ticket).name} (−#{price} vàng)."},
         %{p | gold: p.gold - price} |> Engine.add_item(@rules.ticket)}
  end

  def ticket_chance(m) do
    d = @rules.ticket_drop
    if m[:world] || m[:pvp] || m[:tower] || m.level < d.min_level, do: 0, else: d.chance
  end

  # ---------- Vào ----------

  def tier_level(level) do
    @rules.tiers |> Enum.filter(&(level >= &1.from)) |> List.last() |> then(&(&1 && &1.level))
  end

  def enter(p, now \\ DateTime.utc_now()) do
    w = window(now)
    daily = p[:daily] || %{}

    cond do
      p.battle ->
        {%{ok: false, msg: "Đang trong trận đấu."}, p}

      p[:tower] ->
        {%{ok: false, msg: "Đang ở trong Tháp."}, p}

      p.hp <= 0 ->
        {%{ok: false, msg: "Bạn cần hồi máu trước."}, p}

      p.level < @rules.min_level ->
        {%{ok: false, msg: "Cần cấp #{@rules.min_level}."}, p}

      w == nil ->
        {%{ok: false, msg: "Lâu Đài Máu chưa mở cửa."}, p}

      daily[:bc_slot] == w.slot ->
        {%{ok: false, msg: "Bạn đã vào đợt này rồi."}, p}

      Map.get(p.inv, @rules.ticket, 0) < 1 ->
        {%{ok: false, msg: "Cần 1 Vé Lâu Đài."}, p}

      true ->
        {%{ok: true, msg: "Vào Lâu Đài Máu! Hạ quái canh, phá cổng, hạ Hiệp Sĩ Máu."},
         start(p, w, now)}
    end
  end

  defp start(p, w, now) do
    level = tier_level(p.level)
    t = Tower.build(1, "bc|#{p.name}|#{System.unique_integer([:positive])}")
    [ex, ey] = t.exit

    bc = %{
      level: level,
      ends_at: DateTime.to_unix(now) + @rules.run_minutes * 60,
      stage: "guards",
      guards: @rules.guards,
      killed: 0,
      done: false
    }

    t = Map.merge(t, %{monsters: guards(level, t), bc: bc})

    inv =
      if p.inv[@rules.ticket] > 1,
        do: Map.update!(p.inv, @rules.ticket, &(&1 - 1)),
        else: Map.delete(p.inv, @rules.ticket)

    %{p | inv: inv}
    |> Map.put(:daily, Map.put(p[:daily] || %{}, :bc_slot, w.slot))
    |> Map.put(:pos, %{map: Tower.map_id(), x: ex, y: ey - 1})
    |> Map.put(:tower, t)
  end

  defp free_spots(t) do
    {ex, ey} = List.to_tuple(t.exit)
    avoid = [List.to_tuple(t.stairs), {ex, ey}, {ex, ey - 1}]

    for {row, y} <- Enum.with_index(t.tiles),
        {c, x} <- Enum.with_index(String.graphemes(row)),
        c == ".",
        {x, y} not in avoid,
        do: {x, y}
  end

  defp guards(level, t) do
    zone = List.last(Data.zones())

    spots =
      free_spots(t)
      |> Enum.map(&{HacLong.Game.Rng.uniform(), &1})
      |> Enum.sort()
      |> Enum.map(&elem(&1, 1))

    for i <- 0..(min(@rules.guards, length(spots)) - 1) do
      {x, y} = Enum.at(spots, i)
      m = Enum.at(zone.monsters, rem(i, length(zone.monsters)))

      %{
        id: i + 1,
        kind: m.id,
        name: m.name,
        level: level,
        x: x,
        y: y,
        elite: false,
        role: "guard"
      }
    end
  end

  # cổng / trùm hiện ở ô trống gần cầu thang lên (cuối lâu đài), không trùng ô người chơi đang đứng
  # (đứng sẵn trên ô quái thì không bước vào đánh được)
  defp near_stairs(t, pos) do
    [sx, sy] = t.stairs
    here = pos && {pos.x, pos.y}

    t
    |> free_spots()
    |> Enum.reject(&(&1 == here))
    |> Enum.min_by(fn {x, y} -> abs(x - sx) + abs(y - sy) end)
  end

  defp spawn_at(t, role, pos) do
    {x, y} = near_stairs(t, pos)
    lvl = t.bc.level

    m =
      case role do
        "gate" ->
          %{kind: @rules.gate.kind, name: @rules.gate.name, level: lvl}

        "boss" ->
          %{kind: @rules.boss.kind, name: @rules.boss.name, level: lvl + @rules.boss.add_level}
      end

    Map.merge(m, %{
      id: 100 + if(role == "gate", do: 1, else: 2),
      x: x,
      y: y,
      elite: role == "boss",
      role: role
    })
  end

  @doc "Quái dùng trong trận ở Lâu Đài."
  def battle_monster(m) do
    {mult, on_hit} =
      case m[:role] do
        "boss" -> {@rules.boss.mult, nil}
        "gate" -> {1, nil}
        _ -> {@rules.guard_mult, (Data.monster(m.kind) || %{})[:on_hit]}
      end

    q =
      Engine.make_monster(
        %{id: m.kind, name: m.name, level: m.level, mult: mult, on_hit: on_hit},
        false
      )

    q =
      case m[:role] do
        # cổng không đánh trả
        "gate" -> %{q | maxHp: q.maxHp * @rules.gate.hp_mult, atk: 0, xp: 0, gold: 0}
        "boss" -> %{q | maxHp: q.maxHp * @rules.boss.hp}
        _ -> q
      end

    Map.merge(q, %{hp: q.maxHp, tower: true, elite: m.elite, bc: true})
  end

  # ---------- Trong lượt ----------

  def expired?(%{tower: %{bc: %{ends_at: e}}}, now \\ DateTime.utc_now()),
    do: DateTime.to_unix(now) >= e

  @doc "Trận ở Lâu Đài vừa kết thúc: thắng thì qua bước; hạ trùm thì xong (thưởng ngay); gục ngã thì kết thúc."
  def after_battle(
        %{tower: %{bc: bc} = t, battle: %{over: true, result: r, encounter: %{tower: id}}} = p
      ) do
    case r do
      "win" ->
        m = Enum.find(t.monsters, &(&1.id == id))
        left = Enum.reject(t.monsters, &(&1.id == id))
        killed = if m && m[:role] == "guard", do: bc.killed + 1, else: bc.killed

        case {m && m[:role], left} do
          {"guard", []} ->
            t = %{t | monsters: [], bc: %{bc | killed: killed, stage: "gate"}}

            %{p | tower: %{t | monsters: [spawn_at(t, "gate", p[:pos])]}}
            |> log("🏰 Đã hạ hết quân canh! Cổng Thành hiện ra, phá nó đi.")

          {"gate", _} ->
            t = %{t | monsters: [], bc: %{bc | stage: "boss"}}

            %{p | tower: %{t | monsters: [spawn_at(t, "boss", p[:pos])]}}
            |> log("💥 Cổng Thành đã vỡ! #{@rules.boss.name} xuất hiện.")

          {"boss", _} ->
            p = %{p | tower: %{t | monsters: [], bc: %{bc | killed: killed}}}
            {r, p} = finish(p, true)
            log(p, r.msg)

          _ ->
            %{p | tower: %{t | monsters: left, bc: %{bc | killed: killed}}}
        end

      "lose" ->
        {r, q} = finish(p, false)
        q |> Map.put(:pos, p[:pos]) |> Map.put(:tower, nil) |> log(r.msg)

      _ ->
        p
    end
  end

  def after_battle(p), do: p

  defp log(%{battle: %{log: _}} = p, text),
    do: update_in(p.battle.log, &(&1 ++ [%{kind: "win", text: text}]))

  defp log(p, _text), do: p

  @doc "Thưởng: thắng (`success?`) hay theo số quái canh đã hạ."
  def reward(level, killed, success?) do
    if success? do
      s = @rules.reward.success
      # khóa đồ trong rules.json bị đọc thành atom: đổi lại thành id chuỗi
      base = Map.new(s.items, fn {k, v} -> {to_string(k), v} end)

      jewels =
        Enum.reduce(1..s.jewels//1, base, fn _, acc ->
          Map.update(acc, Engine.pick_jewel(), 1, &(&1 + 1))
        end)

      %{
        gold: round(Engine.base_gold(level) * s.gold_mult),
        xp: round(Engine.base_xp(level) * s.xp_mult),
        items: jewels
      }
    else
      pt = @rules.reward.partial

      %{
        gold: round(Engine.base_gold(level) * pt.gold_per_guard * killed),
        xp: round(Engine.base_xp(level) * pt.xp_per_guard * killed),
        items: %{}
      }
    end
  end

  @doc """
  Trả thưởng. Thắng: lượt đánh dấu `done` (còn ở lâu đài, bước tiếp là về Làng). Không thắng: rời lâu đài về Làng.
  """
  def finish(%{tower: %{bc: bc} = t} = p, success?) do
    r = reward(bc.level, bc.killed, success?)
    p = %{p | gold: p.gold + r.gold}
    p = Enum.reduce(r.items, p, fn {id, n}, p -> Engine.add_item(p, id, n) end)
    {_levels, p} = Engine.gain_xp(p, r.xp)

    items =
      Enum.map_join(r.items, "", fn {id, n} ->
        ", #{Data.item(id).name}#{if n > 1, do: " ×#{n}", else: ""}"
      end)

    msg =
      if success?,
        do:
          "🏆 Hạ #{@rules.boss.name}! Lâu Đài Máu hoàn thành: +#{r.gold} vàng, +#{r.xp} kinh nghiệm#{items}.",
        else:
          "Lâu Đài Máu kết thúc: hạ #{bc.killed} quân canh, +#{r.gold} vàng, +#{r.xp} kinh nghiệm."

    p =
      if success?,
        do: %{p | tower: %{t | bc: %{bc | done: true, stage: "done"}}},
        else: p |> Map.put(:tower, nil) |> Map.put(:pos, %{map: "village", x: 21, y: 9})

    {%{ok: true, msg: msg}, p}
  end

  @doc "Bước đi trong lâu đài đã xong / hết giờ / tự ra: về Làng (thưởng nếu chưa trả)."
  def leave(%{tower: %{bc: %{done: true}}} = p) do
    {%{ok: true, msg: "Rời Lâu Đài Máu."},
     p |> Map.put(:tower, nil) |> Map.put(:pos, %{map: "village", x: 21, y: 9})}
  end

  def leave(p), do: finish(p, false)
end
