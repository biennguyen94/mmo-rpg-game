defmodule HacLong.Game.Kalima do
  @moduledoc """
  Kalima kiểu MU (DECISIONS B-21; số ở `RULES.kalima`). Hàm thuần.

  Như Lâu Đài Máu (`HacLong.Game.BloodCastle`), chạy trên bản đồ riêng `tower` với trạng thái
  `p.tower.kal: %{n, level, ends_at, stage, guards, killed, done}` (cột `tower` sẵn có, không đổi schema).

  - **Vào** ở Người Gác Tháp, lúc nào cũng được: từ `min_level`, tốn 1 **Bản Đồ Thất Lạc** (`ticket`, ghép 5 Dấu Ấn
    Kundun ở Máy Hỗn Nguyên; dấu ấn rơi từ quái thường, `mark_chance/1`). Kalima 1–7 theo cấp nhân vật (`tiers`).
  - Hai bước (`stage`): `"guards"` hạ `guards` quái Kalima → `"boss"` **Kundun** hiện gần cầu thang lên. Hạ Kundun thì
    thắng: `reward.success` (vàng, kinh nghiệm, ngọc, một món đồ có thể Excellent / Thần), lượt `done`, bước tiếp là về Làng.
  - Hết giờ (`run_minutes`), gục ngã hoặc tự ra trước khi hạ Kundun: `reward.partial` theo số quái đã hạ.
  """

  alias HacLong.Game.{Data, Engine, Gear, Rng, Tower}

  @rules Data.rules().kalima
  @door %{map: "village", x: 21, y: 9}

  def rules, do: @rules
  def ticket, do: @rules.ticket
  def mark, do: @rules.mark

  @doc "Kalima theo cấp nhân vật: `%{n, level}` hoặc nil (chưa đủ cấp)."
  def tier(level) do
    @rules.tiers
    |> Enum.filter(&(level >= &1.from))
    |> List.last()
    |> then(&(&1 && Map.take(&1, [:n, :level])))
  end

  @doc "Tỉ lệ quái `m` rơi Dấu Ấn Kundun (quái thường cấp ≥ `mark_drop.min_level`)."
  def mark_chance(m) do
    d = @rules.mark_drop
    if m[:world] || m[:pvp] || m[:tower] || m.level < d.min_level, do: 0, else: d.chance
  end

  @doc "Thông tin cho giao diện (thẻ ở Người Gác Tháp)."
  def view(p) do
    t = tier(p.level)

    %{
      min_level: @rules.min_level,
      run_minutes: @rules.run_minutes,
      guards: @rules.guards,
      n: t && t.n,
      maps: Map.get(p.inv, @rules.ticket, 0),
      marks: Map.get(p.inv, @rules.mark, 0)
    }
  end

  # ---------- Vào ----------

  def enter(p, now \\ DateTime.utc_now()) do
    cond do
      p.battle ->
        {%{ok: false, msg: "Đang trong trận đấu."}, p}

      p[:tower] ->
        {%{ok: false, msg: "Đang ở trong Tháp."}, p}

      p.hp <= 0 ->
        {%{ok: false, msg: "Bạn cần hồi máu trước."}, p}

      p.level < @rules.min_level ->
        {%{ok: false, msg: "Cần cấp #{@rules.min_level}."}, p}

      Map.get(p.inv, @rules.ticket, 0) < 1 ->
        {%{ok: false, msg: "Cần 1 #{Data.item(@rules.ticket).name}."}, p}

      true ->
        start(p, now)
    end
  end

  defp start(p, now) do
    %{n: n, level: level} = tier(p.level)
    t = Tower.build(1, "kal|#{p.name}|#{System.unique_integer([:positive])}")
    [ex, ey] = t.exit

    kal = %{
      n: n,
      level: level,
      ends_at: DateTime.to_unix(now) + @rules.run_minutes * 60,
      stage: "guards",
      guards: @rules.guards,
      killed: 0,
      done: false
    }

    t = Map.merge(t, %{monsters: guards(level, t), kal: kal})

    p =
      p
      |> Engine.take_item(@rules.ticket)
      |> Map.put(:pos, %{map: Tower.map_id(), x: ex, y: ey - 1})
      |> Map.put(:tower, t)

    {%{ok: true, msg: "Vào Kalima #{n}! Hạ #{@rules.guards} quái để gọi Kundun."}, p}
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
    spots =
      free_spots(t) |> Enum.map(&{Rng.uniform(), &1}) |> Enum.sort() |> Enum.map(&elem(&1, 1))

    kinds = Enum.zip(@rules.guard_kinds, @rules.guard_names)

    for i <- 0..(min(@rules.guards, length(spots)) - 1) do
      {x, y} = Enum.at(spots, i)
      {kind, name} = Enum.at(kinds, rem(i, length(kinds)))
      %{id: i + 1, kind: kind, name: name, level: level, x: x, y: y, elite: false, role: "guard"}
    end
  end

  # Kundun hiện ở ô trống gần cầu thang lên, không trùng ô người chơi đang đứng
  defp boss_at(t, pos) do
    [sx, sy] = t.stairs
    here = pos && {pos.x, pos.y}

    {x, y} =
      t
      |> free_spots()
      |> Enum.reject(&(&1 == here))
      |> Enum.min_by(fn {x, y} -> abs(x - sx) + abs(y - sy) end)

    b = @rules.boss

    %{
      id: 100,
      kind: b.kind,
      name: b.name,
      level: t.kal.level + b.add_level,
      x: x,
      y: y,
      elite: true,
      role: "boss"
    }
  end

  @doc "Quái dùng trong trận ở Kalima."
  def battle_monster(m) do
    boss? = m[:role] == "boss"
    mult = if boss?, do: @rules.boss.mult, else: @rules.guard_mult
    q = Engine.make_monster(%{id: m.kind, name: m.name, level: m.level, mult: mult}, false)
    q = if boss?, do: %{q | maxHp: q.maxHp * @rules.boss.hp}, else: q
    Map.merge(q, %{hp: q.maxHp, tower: true, elite: m.elite, kal: true})
  end

  # ---------- Trong lượt ----------

  def expired?(%{tower: %{kal: %{ends_at: e}}}, now \\ DateTime.utc_now()),
    do: DateTime.to_unix(now) >= e

  @doc "Trận ở Kalima vừa kết thúc: hạ hết quái thì gọi Kundun; hạ Kundun thì thắng (thưởng ngay); gục ngã thì kết thúc."
  def after_battle(
        %{tower: %{kal: kal} = t, battle: %{over: true, result: r, encounter: %{tower: id}}} = p
      ) do
    case r do
      "win" ->
        m = Enum.find(t.monsters, &(&1.id == id))
        left = Enum.reject(t.monsters, &(&1.id == id))
        killed = if m && m[:role] == "guard", do: kal.killed + 1, else: kal.killed
        kal = %{kal | killed: killed}

        case {m && m[:role], left} do
          {"guard", []} ->
            t = %{t | monsters: [], kal: %{kal | stage: "boss"}}

            %{p | tower: %{t | monsters: [boss_at(t, p[:pos])]}}
            |> log("👹 Đã hạ hết quái Kalima! #{@rules.boss.name} xuất hiện gần cầu thang.")

          {"boss", _} ->
            {r, p} = finish(%{p | tower: %{t | monsters: [], kal: kal}}, true)
            log(p, r.msg)

          _ ->
            %{p | tower: %{t | monsters: left, kal: kal}}
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

  @doc "Thưởng ở cấp quái `level`: thắng (`success?`, `%{gold, xp, items, gear}`) hay theo số quái đã hạ."
  def reward(level, killed, success?) do
    if success? do
      s = @rules.reward.success

      jewels =
        Enum.reduce(1..s.jewels//1, %{}, fn _, acc ->
          Map.update(acc, Engine.pick_jewel(), 1, &(&1 + 1))
        end)

      gear =
        if Rng.uniform() < s.gear_chance do
          g = Gear.roll(level, [{2, 60}, {3, 40}])
          g = g && Gear.excellent(g, s.exc_chance)

          g &&
            if(Data.item(g.base)[:set] && Rng.uniform() < s.anc_chance,
              do: Map.put(g, :anc, true),
              else: g
            )
        end

      %{
        gold: round(Engine.base_gold(level) * s.gold_mult),
        xp: round(Engine.base_xp(level) * s.xp_mult),
        items: jewels,
        gear: gear
      }
    else
      pt = @rules.reward.partial

      %{
        gold: round(Engine.base_gold(level) * pt.gold_per_guard * killed),
        xp: round(Engine.base_xp(level) * pt.xp_per_guard * killed),
        items: %{},
        gear: nil
      }
    end
  end

  @doc "Trả thưởng. Thắng: lượt `done` (bước tiếp là về Làng). Không thắng: rời Kalima về Làng."
  def finish(%{tower: %{kal: kal} = t} = p, success?) do
    r = reward(kal.level, kal.killed, success?)
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

    items =
      Enum.map_join(r.items, "", fn {id, n} ->
        ", #{Data.item(id).name}#{if n > 1, do: " ×#{n}", else: ""}"
      end)

    msg =
      if success?,
        do:
          "🏆 Hạ #{@rules.boss.name}! Kalima #{kal.n} hoàn thành: +#{r.gold} vàng, +#{r.xp} kinh nghiệm#{items}#{gear_txt}.",
        else:
          "Kalima #{kal.n} kết thúc: hạ #{kal.killed} quái, +#{r.gold} vàng, +#{r.xp} kinh nghiệm."

    p =
      if success?,
        do: %{p | tower: %{t | kal: %{kal | done: true, stage: "done"}}},
        else: p |> Map.put(:tower, nil) |> Map.put(:pos, @door)

    {%{ok: true, msg: msg}, p}
  end

  @doc "Bước đi trong Kalima đã xong / hết giờ / tự ra: về Làng (thưởng nếu chưa trả)."
  def leave(%{tower: %{kal: %{done: true}}} = p),
    do: {%{ok: true, msg: "Rời Kalima."}, p |> Map.put(:tower, nil) |> Map.put(:pos, @door)}

  def leave(p), do: finish(p, false)
end
