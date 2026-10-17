defmodule HacLong.Game.Journey do
  @moduledoc """
  Mô phỏng **cả hành trình** một nhân vật để kiểm tra cân bằng: từ cấp 1, lên cấp 50, hạ trùm vùng, chuyển sinh,
  rồi vào các vùng chuyển sinh, tới khi đủ số lần chuyển sinh muốn xem (`mix hac_long.journey`).

  Khác `HacLong.Game.Simulator` (chỉ tới Hắc Long, đánh quái theo vùng): ở đây bot chọn **bản đồ** như người chơi
  (bản đồ vùng, bản đồ phụ, vùng chuyển sinh) và dùng đúng hàm của game:

  - đánh: `Engine.start_encounter/4`, `Engine.start_side_encounter/4`, mỗi lượt `HacLong.Bots.Brain.fight/1`
    (bot thật: kỹ năng mạnh nhất, uống bình khi máu < 35 %);
  - chọn bản đồ: trong các bản đồ dịch chuyển tới được (`World.can_travel?/2`), cái cho nhiều kinh nghiệm nhất mỗi con
    (đã tính phạt EXP khi cao cấp hơn quái); bản đồ thường bỏ qua nếu quái cao hơn mình quá 2 cấp. Thua
    `ban_losses` trong `ban_window` trận gần nhất ở một bản đồ thì tránh nó `ban_fights` trận (lùi về bản đồ dễ hơn);
  - trùm vùng: đánh khi cấp ≥ cấp trùm + 1, thua thì chờ 20 trận rồi thử lại; chúa tể vùng chuyển sinh: thử mỗi
    `lord_every` trận ở vùng đó;
  - đồ: mỗi khi lên cấp / nhặt đồ, thử mặc từng món trong túi và đồ cửa hàng mua được, giữ món làm tăng
    `score/1` (công × độ trâu); đồ thừa bán, giữ một món đã ép cao nhất làm nguyên liệu cánh;
  - ép: Ước Nguyện lên +6, Tâm Linh +7 → +9 (có thể về +0), Ngọc Sinh Mệnh thêm dòng, theo thứ tự vũ khí → giáp → …;
    +10 / +11 ở Máy Hỗn Nguyên khi `chaos_up` hoặc từ lần chuyển sinh `chaos_from` (thất bại về +0, mất hết +9);
  - cánh: ghép cánh 1 → 2 → 3 ở Máy Hỗn Nguyên khi đủ nguyên liệu (`wings`);
  - thú cưng (`pets`): mua / thuần phục con mạnh hơn hẳn khi giá ≤ 30 % vàng dư, dắt con mạnh nhất, dư nhiều vàng thì
    cho ăn (`feed`);
  - tháp (`tower`): mỗi `tower_every` trận (từ cấp `tower_level`) leo Tháp Vô Tận từ tầng bắt đầu cao nhất đã mở,
    đánh hết quái từng tầng bằng `Tower.build/2` + `Tower.battle_monster/1`, lên cầu thang bằng `Tower.climb/1` (thưởng
    vàng, kinh nghiệm, ngọc mỗi 10 tầng, kỷ lục `tower_best` mở kỹ năng tháp); dừng khi máu < 50 % sau một tầng,
    đã leo `tower_floors` tầng, hoặc thua (chết như ngoài bản đồ). Kỹ năng mang vào trận: bộ mạnh nhất mặc định;
  - nghỉ trọ khi máu < 60 % (hết vàng thì về Nhà uống giếng, miễn phí), mua bình như bot (`Brain.restock/1`);
  - chuyển sinh ngay khi đạt cấp tối đa (nếu `boss_first`: sau khi hạ Hắc Long).

  Không mô phỏng: việc hằng ngày, sự kiện, nhà / nấu ăn, chợ, tổ đội, PK, trùm thế giới.
  Hàm thuần; số ngẫu nhiên theo `:rand` (đặt seed ở mix task để chạy lại ra đúng kết quả).
  """

  alias HacLong.Bots.Brain
  alias HacLong.Game.{Chaos, Data, Engine, Gear, Pets, Quests, Tower}
  alias HacLong.World
  alias HacLong.World.Maps

  @defaults %{
    rebirths: 3,
    max_fights: 150_000,
    quests: true,
    soul: true,
    wings: true,
    chaos_up: false,
    chaos_from: 5,
    tower: true,
    tower_every: 300,
    tower_level: 30,
    tower_floors: 30,
    boss_first: true,
    ban_window: 8,
    ban_losses: 2,
    ban_fights: 150,
    lord_every: 40,
    pets: true,
    feed: true,
    farm: 0,
    rows: false
  }

  # cách cộng điểm theo lớp (lặp vòng), như `Simulator`
  @alloc %{
    "dk" => ~w(str str str vit vit),
    "dw" => ~w(ene ene ene vit vit),
    "elf" => ~w(agi agi agi str vit),
    "mg" => ~w(str str str ene ene vit vit)
  }

  # thứ tự ép đồ đang mặc
  @forge_order ~w(weapon armor shield wing helm pants gloves boots pendant ring1 ring2)
  @spare_slots ~w(weapon armor shield)

  @doc "Các tùy chọn mặc định của `run/2`."
  def defaults, do: @defaults

  @doc """
  Chạy một hành trình cho lớp `cls`. Trả về `%{cls, done, fights, turns, deaths, events, cycles, bands,
  snapshots, rows}` (xem `HacLong.Game.JourneyReport` để in).
  """
  def run(cls, opts \\ []) do
    opts = Map.merge(@defaults, Map.new(opts))
    {:ok, p} = Engine.new_player("Hành Giả", cls)
    p = Map.put(p, :quests, Quests.empty())

    st = %{
      opts: opts,
      fights: 0,
      turns: 0,
      events: [],
      cycles: %{},
      bands: %{},
      mons: %{},
      snapshots: [],
      rows: [],
      hist: %{},
      ban: %{},
      boss_cd: 0,
      lord_at: %{},
      tower_at: 0,
      tower: %{runs: 0, floors: 0, fights: 0, losses: 0},
      map: nil,
      seen_maps: MapSet.new(),
      gear_key: nil,
      fountain: 0,
      rest_gold: 0,
      upgrades: %{tries: 0, ok: 0, reset: 0, destroy: 0},
      lines: %{tries: 0, ok: 0},
      wing_tries: 0,
      exchanges: 0,
      pet_gold: 0,
      pet_marks: MapSet.new(),
      farm: nil,
      done: false
    }

    st = event(st, p, "Tạo nhân vật #{Data.class(cls).name}.")
    loop(p, st) |> finish()
  end

  # ---------- Vòng chính ----------

  defp loop(p, %{done: true} = st), do: {p, st}

  defp loop(p, %{fights: f, opts: %{max_fights: max}} = st) when f >= max do
    {p, event(st, p, "Dừng: đã đánh #{max} trận (max_fights).")}
  end

  defp loop(p, st) do
    {p, st} = p |> allocate() |> maintain(st)

    cond do
      rebirth?(p, st) ->
        p |> rebirth(st) |> then(fn {p, st} -> loop(p, st) end)

      finished?(p, st) and st.farm == nil and st.opts.farm > 0 ->
        st =
          event(st, p, "Đủ chuyển sinh #{rb(p)}, cấp #{p.level}: cày thêm #{st.opts.farm} trận.")

        loop(p, %{st | farm: st.opts.farm})

      finished?(p, st) and (st.farm || 0) <= 0 ->
        {p, %{event(st, p, "Hoàn thành: chuyển sinh #{rb(p)}, cấp #{p.level}.") | done: true}}

      tower?(p, st) ->
        p
        |> heal(st, 1.0)
        |> then(fn {p, st} -> tower_run(p, st) end)
        |> then(fn {p, st} -> loop(p, st) end)

      true ->
        p
        |> heal(st)
        |> then(fn {p, st} ->
          {p, st} = battle(p, st)
          loop(p, if(st.farm, do: %{st | farm: st.farm - 1}, else: st))
        end)
    end
  end

  defp rb(p), do: Map.get(p, :rebirths) || 0

  defp final_boss, do: Data.zone(Data.zone_count() - 1).boss

  defp rebirth?(p, st) do
    p.level >= Engine.max_level() and rb(p) < min(st.opts.rebirths, Engine.max_rebirths()) and
      Engine.rebirth_need(p) == nil and
      (not st.opts.boss_first or final_boss().id in p.bosses or st.boss_cd > st.fights + 1000)
  end

  defp finished?(p, st),
    do: rb(p) >= min(st.opts.rebirths, Engine.max_rebirths()) and p.level >= Engine.max_level()

  defp rebirth(p, st) do
    st = snapshot(st, p, "Trước chuyển sinh #{rb(p) + 1}")
    {r, p} = Engine.rebirth(p)
    st = event(st, p, if(r.ok, do: r.msg, else: "Không chuyển sinh được: #{r.msg}"))
    {p, %{st | gear_key: nil, ban: %{}, hist: %{}}}
  end

  # ---------- Hồi máu ----------

  defp heal(p, st, at \\ 0.6) do
    d = Engine.derived(p)

    cond do
      p.hp >= d.maxHp * at ->
        {p, st}

      p.gold >= Engine.rest_cost(p) ->
        cost = Engine.rest_cost(p)
        {_, p} = Engine.rest(p)
        {p, %{st | rest_gold: st.rest_gold + cost}}

      true ->
        # hết vàng: về Nhà uống giếng (miễn phí)
        {Map.merge(p, %{hp: d.maxHp, mp: d.maxMp}), %{st | fountain: st.fountain + 1}}
    end
  end

  # ---------- Tháp Vô Tận ----------

  defp tower?(p, st),
    do:
      st.opts.tower and p.level >= st.opts.tower_level and
        st.fights - st.tower_at >= st.opts.tower_every

  @tower_map %{id: "tower", name: "Tháp Vô Tận"}

  defp tower_run(p, st) do
    best0 = Map.get(p, :tower_best) || 0
    skills0 = Engine.available_skills(p) |> Enum.map(& &1.id)
    start = List.last(Tower.starts(best0))

    # nhân vật mô phỏng không có vị trí; tháp cần (`Tower.climb/1` đặt chỗ đứng tầng mới)
    pos = p[:pos]
    p = Map.put(p, :pos, pos || %{map: "village", x: 1, y: 1})
    st = %{st | tower_at: st.fights, tower: %{st.tower | runs: st.tower.runs + 1}}

    {p, st, top} =
      tower_floor(Map.put(p, :tower, tower_build(st, start)), st, start, start, start - 1)

    p =
      p
      |> Map.put(:tower, nil)
      |> then(&if(pos, do: %{&1 | pos: pos}, else: Map.delete(&1, :pos)))

    best = Map.get(p, :tower_best) || 0
    new = Engine.available_skills(p) |> Enum.map(& &1.id) |> Kernel.--(skills0)

    st =
      event(
        st,
        p,
        "Leo tháp từ tầng #{start}: vượt tới tầng #{top}" <>
          if(best > best0, do: " (kỷ lục mới #{best})", else: " (kỷ lục #{best})") <>
          if(new != [],
            do: " · mở kỹ năng tháp #{Enum.map_join(new, ", ", &skill_name(p, &1))}",
            else: ""
          ) <> "."
      )

    {p, st}
  end

  defp skill_name(p, id),
    do: Enum.find_value(Engine.available_skills(p), id, &(&1.id == id && &1.name))

  # tầng riêng dựng theo số trận (chạy lại cùng seed ra cùng tầng)
  defp tower_build(st, floor), do: Tower.build(floor, "journey|#{st.fights}")

  # đánh hết quái tầng `floor` rồi lên cầu thang; trả {nhân vật, st, tầng cao nhất đã vượt}
  defp tower_floor(p, st, start, floor, top) do
    case p.tower.monsters do
      [m | _] ->
        case tower_fight(p, st, floor, m) do
          {p, st, "win"} -> tower_floor(p, st, start, floor, top)
          {p, st, _lost} -> {p, st, top}
        end

      [] ->
        {_, p} = Tower.climb(p)
        p = Map.put(p, :tower, tower_build(st, floor + 1))
        d = Engine.derived(p)
        p = potions(p)

        if p.hp < d.maxHp * 0.5 or floor - start + 1 >= st.opts.tower_floors,
          do: {p, st, floor},
          else: tower_floor(p, st, start, floor + 1, floor)
    end
  end

  defp tower_fight(p, st, floor, m) do
    lv0 = p.level
    max0 = Engine.derived(p).maxHp
    zi = min(div(floor - 1, 10), Data.zone_count() - 1)

    case Engine.start_with_monster(p, zi, Tower.battle_monster(m)) do
      {%{ok: true}, p} ->
        p = put_in(p, [:battle, :encounter], %{tower: m.id})
        {p, taken} = fight(p, 0)
        b = p.battle
        res = b.result
        reward = b.reward || %{xp: 0, gold: 0}
        p = Tower.after_battle(p)
        {_, p} = Engine.leave_battle(p)
        lost = if res == "win", do: taken / max0, else: 1.0
        t = st.tower

        st =
          %{
            st
            | fights: st.fights + 1,
              turns: st.turns + b.turn,
              tower: %{
                t
                | fights: t.fights + 1,
                  losses: t.losses + if(res == "win", do: 0, else: 1),
                  floors: t.floors + if(p[:tower] && p.tower.monsters == [], do: 1, else: 0)
              }
          }
          |> record(p, @tower_map, b.monster, res, b.turn, lost, reward, lv0)

        st =
          if res == "win",
            do: st,
            else: event(st, p, "💀 Thua #{b.monster.name} ở tháp tầng #{floor}.")

        {p, st, res}

      _ ->
        {p, st, "skip"}
    end
  end

  # ---------- Một trận ----------

  defp battle(p, st) do
    {kind, map, spec} = pick_target(p, st)
    st = enter_map(st, p, map)
    lv0 = p.level
    max0 = Engine.derived(p).maxHp

    {r, p} =
      case kind do
        :boss -> Engine.start_battle(p, map.zone, true)
        :zone -> Engine.start_encounter(p, map.zone, spec, false)
        :side -> Engine.start_side_encounter(p, spec, map.name, map.theme)
      end

    if r.ok do
      {p, taken} = fight(p, 0)
      b = p.battle
      res = b.result
      reward = b.reward || %{xp: 0, gold: 0}
      m = b.monster
      p = if res == "win" and st.opts.quests, do: Quests.on_kill(p, m.id), else: p
      {_, p} = Engine.leave_battle(p)

      # máu mất cả trận (cộng từng đòn bị đánh; uống bình / lên cấp hồi máu không trừ vào)
      lost = if res == "win", do: taken / max0, else: 1.0

      st =
        %{st | fights: st.fights + 1, turns: st.turns + b.turn}
        |> record(p, map, m, res, b.turn, lost, reward, lv0)
        |> boss_result(p, kind, m, res)
        |> lord_result(p, map, m, res)
        |> then(&if(spec[:lord], do: &1, else: track(&1, map.id, res)))

      st = if p.level > lv0 and rem(p.level, 10) == 0, do: level_event(st, p, map), else: st
      {p, st}
    else
      # không vào được trận (hiếm): coi như một trận trống để không lặp mãi
      {p,
       %{st | fights: st.fights + 1, ban: Map.put(st.ban, map.id, st.fights + st.opts.ban_fights)}}
    end
  end

  # trả về {nhân vật, tổng máu bị mất trong trận}
  defp fight(%{battle: %{over: true}} = p, taken), do: {p, taken}

  defp fight(%{battle: %{turn: t}} = p, taken) when t >= 300 do
    {_, p} = Engine.act(p, "flee")
    {if(p.battle.over, do: p, else: elem(Engine.finish_lose(p), 1)), taken}
  end

  defp fight(p, taken) do
    cmd = Brain.fight(p)
    {_, q} = Engine.act(p, cmd["act"], cmd["skill"])

    fight(
      q,
      taken + if(q.battle.over and q.battle.result == "win", do: 0, else: max(0, p.hp - q.hp))
    )
  end

  # ---------- Chọn nơi đánh ----------

  defp pick_target(p, st) do
    boss_target(p, st) || lord_target(p, st) || map_target(p, st)
  end

  # cần hạ chúa tể để chuyển sinh tiếp và đã ở cấp tối đa: tới bản đồ của chúa tể thử mỗi `lord_every / 4` trận
  defp lord_target(p, st) do
    with %{id: id} <- Engine.rebirth_need(p),
         true <- p.level >= Engine.max_level(),
         %{} = m <- Enum.find(all_maps(), &Enum.any?(&1.spawns, fn s -> s.monster == id end)),
         true <- World.can_travel?(p, m),
         every = max(1, div(st.opts.lord_every, 4)),
         true <- st.fights - Map.get(st.lord_at, m.id, -every) >= every do
      {:side, m, Map.put(Data.side_monster(id), :lord, true)}
    else
      _ -> nil
    end
  end

  # trùm vùng đầu tiên chưa hạ mà cấp mình ≥ cấp trùm + 1
  defp boss_target(p, st) do
    if st.fights >= st.boss_cd do
      Data.zones()
      |> Enum.with_index()
      |> Enum.find_value(fn {z, zi} ->
        if z.boss.id not in p.bosses and p.level >= z.boss.level + 1 and
             Engine.zone_unlocked?(p, zi),
           do: {:boss, boss_map(zi), z.boss}
      end)
    end
  end

  defp boss_map(zi),
    do: Enum.find(all_maps(), &(&1.zone == zi and &1[:boss] != nil)) || hd(zone_maps(zi))

  defp zone_maps(zi), do: Enum.filter(all_maps(), &(&1.zone == zi))

  defp all_maps, do: Enum.map(Maps.ids(), &Maps.get/1)

  # bản đồ cho nhiều EXP nhất mỗi con mà chưa bị tránh; quái chọn theo số lượng xuất hiện (chúa tể vùng: theo lượt)
  defp map_target(p, st) do
    maps =
      for m <- all_maps(),
          not m.private and m.event == nil and m.id != "tower" and m.spawns != [],
          World.can_travel?(p, m),
          Map.get(st.ban, m.id, 0) <= st.fights,
          specs = map_specs(m),
          specs != [],
          m.realm != nil or Enum.max(Enum.map(specs, & &1.level)) <= p.level + 2,
          do: {xp_score(p, normal_specs(m, specs)), m, specs}

    case Enum.max_by(maps, &elem(&1, 0), fn -> nil end) do
      nil ->
        m = Maps.get("forest_1")
        {:zone, m, hd(map_specs(m))}

      {_, m, specs} ->
        {kind, spec} = pick_spec(p, st, m, specs)
        {kind, m, spec}
    end
  end

  defp map_specs(%{side: true} = m),
    do: m.spawns |> Enum.map(&Data.side_monster(&1.monster)) |> Enum.reject(&is_nil/1)

  defp map_specs(%{zone: zi} = m) when is_integer(zi) do
    z = Data.zone(zi)
    ids = Enum.map(m.spawns, & &1.monster)
    Enum.filter(z.monsters, &(&1.id in ids))
  end

  defp map_specs(_), do: []

  # chúa tể vùng chuyển sinh (`lord: true`, ở bản đồ cuối của vùng, scripts/gen_realms.py)
  defp lord(%{realm: k}, specs) when is_integer(k), do: Enum.find(specs, & &1[:lord])

  defp lord(_m, _specs), do: nil

  defp normal_specs(m, specs), do: specs -- [lord(m, specs)]

  defp xp_score(p, specs) do
    specs
    |> Enum.map(fn s ->
      Engine.base_xp(s.level) * Map.get(s, :mult, 1) * Engine.xp_factor(p.level, s.level)
    end)
    |> then(&(Enum.sum(&1) / length(&1)))
  end

  defp pick_spec(p, st, m, specs) do
    kind = if m.side, do: :side, else: :zone
    lord = lord(m, specs)

    every = st.opts.lord_every

    if lord != nil and st.fights - Map.get(st.lord_at, m.id, -every) >= every and
         p.level >= 40 do
      {kind, Map.put(lord, :lord, true)}
    else
      {kind, Enum.random(normal_specs(m, specs))}
    end
  end

  defp enter_map(st, p, m) do
    st = %{st | map: m.id}

    if MapSet.member?(st.seen_maps, m.id) do
      st
    else
      st = %{st | seen_maps: MapSet.put(st.seen_maps, m.id)}

      if m.realm,
        do: event(st, p, "Lần đầu vào #{m.name} (vùng chuyển sinh #{m.realm})."),
        else: st
    end
  end

  # thua nhiều ở một bản đồ thì tránh một thời gian
  defp track(st, map_id, res) do
    h = Enum.take([res | Map.get(st.hist, map_id, [])], st.opts.ban_window)
    losses = Enum.count(h, &(&1 == "lose"))

    if losses >= st.opts.ban_losses do
      %{
        st
        | hist: Map.put(st.hist, map_id, []),
          ban: Map.put(st.ban, map_id, st.fights + st.opts.ban_fights)
      }
      |> Map.update!(:events, fn evs ->
        name = Maps.get(map_id).name

        [
          {st.fights, nil, nil,
           "Tránh #{name} #{st.opts.ban_fights} trận (thua #{losses}/#{length(h)} trận gần nhất)."}
          | evs
        ]
      end)
    else
      %{st | hist: Map.put(st.hist, map_id, h)}
    end
  end

  defp boss_result(st, p, :boss, m, "win"),
    do: event(st, p, "🏆 Hạ trùm #{m.name} (cấp #{m.level}).")

  defp boss_result(st, p, :boss, m, _),
    do: %{event(st, p, "💀 Thua trùm #{m.name}, thử lại sau 20 trận.") | boss_cd: st.fights + 20}

  defp boss_result(st, _p, _kind, _m, _res), do: st

  defp lord_result(st, p, map, m, res) do
    specs = map_specs(map)
    l = lord(map, specs)

    if l && l.id == m.id do
      st = %{st | lord_at: Map.put(st.lord_at, map.id, st.fights)}
      word = if res == "win", do: "🏆 Hạ", else: "💀 Thua"
      event(st, p, "#{word} chúa tể #{m.name} (#{map.name}).")
    else
      st
    end
  end

  # ---------- Ghi số liệu ----------

  defp record(st, p, map, m, res, turns, lost, reward, lv0) do
    key = {rb(p), if(st.farm, do: 5, else: div(lv0 - 1, 10))}
    win? = res == "win"

    add = fn acc ->
      acc =
        acc || %{fights: 0, wins: 0, losses: 0, turns: 0, lost: 0.0, gold: 0, xp: 0, maps: %{}}

      %{
        acc
        | fights: acc.fights + 1,
          wins: acc.wins + if(win?, do: 1, else: 0),
          losses: acc.losses + if(res == "lose", do: 1, else: 0),
          turns: acc.turns + turns,
          lost: acc.lost + if(win?, do: lost, else: 0),
          gold: acc.gold + (reward[:gold] || 0),
          xp: acc.xp + (reward[:xp] || 0),
          maps: Map.update(acc.maps, map.name, 1, &(&1 + 1))
      }
    end

    st = %{
      st
      | bands: Map.update(st.bands, key, add.(nil), add),
        cycles: Map.update(st.cycles, rb(p), add.(nil), add),
        mons: Map.update(st.mons, {m.name, m.level, map.name}, add.(nil), add)
    }

    if st.opts.rows do
      row = %{
        fight: st.fights,
        rebirths: rb(p),
        level: lv0,
        map: map.name,
        monster: m.name,
        monster_level: m.level,
        result: res,
        turns: turns,
        hp_lost_pct: round(lost * 100),
        gold: reward[:gold] || 0,
        xp: reward[:xp] || 0
      }

      %{st | rows: [row | st.rows]}
    else
      st
    end
  end

  defp level_event(st, p, map) do
    d = Engine.derived(p)

    event(
      st,
      p,
      "Lên cấp #{p.level} ở #{map.name} · máu #{d.maxHp}, công #{d.atkMin}–#{d.atkMax}, thủ #{d.def} · vũ khí #{gear_name(p, :weapon)}"
    )
  end

  defp event(st, p, text), do: %{st | events: [{st.fights, rb(p), p.level, text} | st.events]}

  @doc "Ảnh chụp nhân vật: cấp, chỉ số, vàng, đồ đang mặc, ngọc trong túi."
  def snapshot_of(p) do
    d = Engine.derived(p)

    %{
      level: p.level,
      rebirths: rb(p),
      stats: p.stats,
      gold: p.gold,
      deaths: p.deaths,
      derived:
        Map.take(d, [:maxHp, :maxMp, :atkMin, :atkMax, :def, :crit, :critMult, :dodge, :hitRate]),
      gear:
        for slot <- Engine.equip_slots(),
            id = p.equip[String.to_existing_atom(slot)],
            id != nil do
          {slot, gear_name(p, String.to_existing_atom(slot))}
        end,
      jewels:
        for(
          {id, n} <- p.inv,
          String.starts_with?(id, "jewel_"),
          n > 0,
          into: %{},
          do: {Data.item(id).name, n}
        ),
      pet: if(p[:pet], do: "#{Pets.name(p)} cấp #{Pets.level(p, p.pet)}", else: "—"),
      potions:
        for(
          {id, n} <- p.inv,
          Data.item(id)[:slot] == "potion",
          n > 0,
          into: %{},
          do: {Data.item(id).name, n}
        )
    }
  end

  defp snapshot(st, p, label),
    do: %{st | snapshots: st.snapshots ++ [{label, st.fights, snapshot_of(p)}]}

  @doc "Tên món đồ ở ô `slot` kèm +N, số dòng, Excellent."
  def gear_name(p, slot) do
    case p.equip[slot] do
      nil ->
        "—"

      id ->
        it = Gear.item(p, id)
        up = Engine.upgrade_level(p, id)
        g = if Gear.instance?(id), do: Gear.find(p, id), else: %{}
        opt = g[:opt] || 0
        exc = length(g[:exc] || [])

        "#{it.name}#{if up > 0, do: " +#{up}"}#{if opt > 0, do: " (#{opt} dòng)"}#{if exc > 0, do: " [Exc #{exc}]"}#{if g[:ancient], do: " [Thần]"}"
    end
  end

  defp finish({p, st}) do
    st = snapshot(st, p, "Kết thúc")

    %{
      cls: p.cls,
      player: p,
      done: st.done,
      fights: st.fights,
      turns: st.turns,
      deaths: p.deaths,
      rebirths: rb(p),
      level: p.level,
      bosses: length(p.bosses),
      rest_gold: st.rest_gold,
      fountain: st.fountain,
      upgrades: st.upgrades,
      lines: st.lines,
      wing_tries: st.wing_tries,
      exchanges: st.exchanges,
      pet_gold: st.pet_gold,
      tower: Map.put(st.tower, :best, Map.get(p, :tower_best) || 0),
      events: Enum.reverse(st.events),
      cycles: st.cycles,
      bands: st.bands,
      mons: st.mons,
      snapshots: st.snapshots,
      rows: Enum.reverse(st.rows),
      opts: st.opts
    }
  end

  # ---------- Chăm sóc nhân vật giữa các trận ----------

  defp allocate(%{points: 0} = p), do: p

  defp allocate(p) do
    order = @alloc[p.cls]
    {_, p} = Engine.allocate(p, Enum.at(order, rem(p.points, length(order))), 1)
    allocate(p)
  end

  defp maintain(p, st) do
    {p, st} = quests(p, st)
    key = {p.level, rb(p), length(Gear.list(p)), Map.keys(p.inv) |> length(), div(p.gold, 5000)}

    {p, st} =
      if key != st.gear_key do
        {p, st} = p |> gear_up(st)
        {p, st} = exchange(p, st)
        {p, st} = forge(p, st)
        {p, st} = wings(p, st)
        {p, st} = gear_up(p, st)
        {p, st} = pets(p, st)
        {sell_junk(p, st), %{st | gear_key: key}}
      else
        {p, st}
      end

    {p |> skills() |> potions(), st}
  end

  # bộ kỹ năng mang vào trận như người chơi tự chọn (`Brain.loadout/2`: giữ kỹ năng hồi máu, còn lại mạnh nhất)
  defp skills(p) do
    ids = Brain.loadout(p, Data.rules().tower_skills.loadout)

    if ids != [] and ids != Map.get(p, :skill_set),
      do: elem(Engine.set_skills(p, ids), 1),
      else: p
  end

  # Ngọc Tâm Linh thừa (ngoài phần giữ cho +7..+9 và cánh) đổi lấy Ước Nguyện ở Máy Hỗn Nguyên khi thiếu Ước Nguyện
  @soul_keep 6
  @bless_want 6
  defp exchange(p, st) do
    r = Data.chaos("soul_to_bless")
    keep = if st.opts.wings, do: wing_keep(p), else: %{}
    soul = Map.get(p.inv, "jewel_soul", 0) - Map.get(keep, "jewel_soul", 0) - @soul_keep
    bless = Map.get(p.inv, "jewel_bless", 0) - Map.get(keep, "jewel_bless", 0)

    with %{} <- r,
         true <- bless < @bless_want and soul >= r.items["jewel_soul"],
         true <- p.gold >= r.gold + reserve(p),
         {%{ok: true}, p} <- Chaos.combine(p, r.id, nil) do
      exchange(p, %{st | exchanges: st.exchanges + 1})
    else
      _ -> {p, st}
    end
  end

  # ---------- Thú cưng ----------

  # sức của thú `id` ở cấp `lv` với bot: phần đòn cắn trung bình mỗi lượt (Cắn Xé đã học thì × rend_mult)
  # + công cộng thêm + nửa thủ / máu cộng thêm
  defp pet_power(_p, nil, _lv), do: 0

  defp pet_power(_p, id, lv) do
    pt = Pets.data(id)
    r = Data.rules().pets

    rend? =
      Enum.zip(Pets.skills(id), [r.skill_level, r.skill2_level])
      |> Enum.any?(fn {k, at} -> k.id == "rend" and lv >= at end)

    b = pt.bonus
    mult = 1 + (lv - 1) * r.bonus_per_level

    Pets.bite_chance(lv) * Pets.bite_power(id, lv) * if(rend?, do: r.skills.rend_mult, else: 1) +
      ((b[:atk] || 0) + 0.5 * ((b[:def] || 0) + (b[:hp] || 0))) * mult
  end

  defp pet_power(p, id), do: pet_power(p, id, if(id, do: Pets.level(p, id), else: 1))

  # mua thú cửa hàng / thuần phục khi mạnh hơn hẳn thú đang có và giá ≤ 30 % vàng dư; dắt con mạnh nhất; dư vàng thì cho ăn
  defp pets(p, %{opts: %{pets: false}} = st), do: {p, st}

  defp pets(p, st) do
    budget = (p.gold - reserve(p)) * 0.3
    owned = Map.get(p, :pets) || []
    cur = pet_power(p, Enum.max_by(owned, &pet_power(p, &1), fn -> nil end))

    shop =
      for pt <- Data.pets(), pt.id not in owned, pt.price <= budget, do: {:buy, pt.id, pt.price}

    tame = for t <- Pets.tameable(p), t.price <= budget, do: {:tame, t.id, t.price}

    cand =
      (shop ++ tame)
      |> Enum.map(fn {k, id, price} ->
        {k, id, price, pet_power(p, if(k == :tame, do: "tame:" <> id, else: id), 1)}
      end)
      |> Enum.max_by(&elem(&1, 3), fn -> nil end)

    {p, st} =
      case cand do
        {k, id, price, pw} when pw > cur * 1.1 ->
          {r, p} = if k == :tame, do: Pets.tame(p, id), else: Pets.buy(p, id)
          verb = if k == :tame, do: "Thuần phục", else: "Mua"

          if r.ok,
            do:
              {p,
               %{
                 event(st, p, "🐾 #{verb} #{Pets.name(p)} (#{price} vàng).")
                 | pet_gold: st.pet_gold + price
               }},
            else: {p, st}

        _ ->
          {p, st}
      end

    best = Enum.max_by(Map.get(p, :pets) || [], &pet_power(p, &1), fn -> nil end)
    p = if best && best != p.pet, do: elem(Pets.choose(p, best), 1), else: p
    {p, st} = feed(p, st, 5)
    pet_mark(p, st)
  end

  defp feed(p, st, 0), do: {p, st}

  defp feed(p, %{opts: %{feed: true}} = st, n) do
    cost = Pets.feed_cost(p)

    if cost && p.gold - reserve(p) > 20 * cost do
      {_, p} = Pets.feed(p)
      feed(p, %{st | pet_gold: st.pet_gold + cost}, n - 1)
    else
      {p, st}
    end
  end

  defp feed(p, st, _n), do: {p, st}

  # ghi diễn biến khi thú đang dắt đạt cấp 5, 10, 15, 20
  defp pet_mark(%{pet: id} = p, st) when is_binary(id) do
    lv = Pets.level(p, id)
    mark = {id, div(lv, 5) * 5}

    if lv >= 5 and not MapSet.member?(st.pet_marks, mark) do
      {p,
       %{
         event(st, p, "🐾 #{Pets.name(p)} đạt cấp #{elem(mark, 1)}.")
         | pet_marks: MapSet.put(st.pet_marks, mark)
       }}
    else
      {p, st}
    end
  end

  defp pet_mark(p, st), do: {p, st}

  defp quests(p, %{opts: %{quests: false}} = st), do: {p, st}

  defp quests(p, st) do
    p = Enum.reduce(Quests.available(p), p, fn q, p -> elem(Quests.accept(p, q.id), 1) end)

    Enum.reduce(Map.keys(p.quests.active), {p, st}, fn id, {p, st} ->
      if Quests.complete?(p, Data.quest(id)),
        do: {elem(Quests.turn_in(p, id), 1), st},
        else: {p, st}
    end)
  end

  defp potions(p) do
    Enum.reduce(Brain.restock(p), p, fn {id, n}, p -> elem(Engine.buy(p, id, n), 1) end)
  end

  # vàng giữ lại cho bình máu / nghỉ trọ
  defp reserve(p), do: 10 * Engine.price(p, Data.potion_for(p.level)) + 4 * Engine.rest_cost(p)

  @doc """
  Điểm sức mạnh dùng để so đồ: sát thương trung bình (kể cả chí mạng, trúng, % cánh) × máu hiệu dụng
  (thủ so với công quái cùng cấp, né, hấp thụ). Chỉ để bot chọn đồ, không phải công thức game.
  """
  def score(p) do
    d = Engine.derived(p)
    mon_atk = 40 + 8 * p.level

    off =
      (d.atkMin + d.atkMax) / 2 * (1 + d.crit * (d.critMult - 1)) * d.hitRate * (1 + d.wingDmg)

    absorb = min(0.8, d.wingAbsorb + d.excAbsorb)
    ehp = d.maxHp * (1 + d.def / mon_atk) / max(0.15, 1 - d.dodge) / (1 - absorb)
    off * ehp
  end

  # mặc thử từng món (túi đồ hiếm, đồ thường trong túi, cửa hàng) — giữ món tăng điểm nhiều nhất, lặp tới khi hết
  defp gear_up(p, st), do: gear_up(p, st, 12)

  defp gear_up(p, st, 0), do: {p, st}

  defp gear_up(p, st, n) do
    base = score(p)
    budget = p.gold - reserve(p)

    owned =
      Enum.map(Gear.bag(p), &{&1.uid, nil}) ++
        for {id, c} <- p.inv,
            c > 0,
            it = Data.item(id),
            it[:slot] in Engine.item_slots(),
            do: {id, nil}

    shop =
      for id <- Data.shop(),
          it = Data.item(id),
          it[:slot] in Engine.item_slots(),
          it.price <= budget,
          Engine.can_wear?(p, it),
          do: {id, it.price}

    best =
      (owned ++ shop)
      |> Enum.flat_map(fn {id, price} ->
        it = Gear.item(p, id)

        if it && Engine.can_wear?(p, it) do
          q = if price, do: elem(Engine.buy(p, id), 1), else: p

          case Engine.equip(q, id) do
            {%{ok: true}, q} -> [{score(q) / base, id, price}]
            _ -> []
          end
        else
          []
        end
      end)
      |> Enum.max_by(&elem(&1, 0), fn -> nil end)

    case best do
      {gain, id, price} when gain > 1.005 ->
        p = if price, do: elem(Engine.buy(p, id), 1), else: p
        {_, p} = Engine.equip(p, id)
        it = Gear.item(p, id)

        st =
          if it.slot in ~w(weapon wing),
            do:
              event(
                st,
                p,
                "Mặc #{gear_name(p, Engine.equip_slot(p, it))}#{if price, do: " (mua #{price} vàng)"}."
              ),
            else: st

        gear_up(p, st, n - 1)

      _ ->
        {p, st}
    end
  end

  # bán đồ thừa trong túi; giữ một món đã ép cao nhất (vũ khí / giáp / khiên) làm nguyên liệu cánh
  defp sell_junk(p, st) do
    spare = if st.opts.wings, do: spare(p)

    p =
      Enum.reduce(Gear.bag(p), p, fn g, p ->
        if g.uid == spare or g[:locked], do: p, else: elem(Engine.sell(p, g.uid), 1)
      end)

    Enum.reduce(p.inv, p, fn {id, c}, p ->
      it = Data.item(id)

      if c > 0 and it[:slot] in Engine.item_slots(),
        do: Enum.reduce(1..c, p, fn _, p -> elem(Engine.sell(p, id), 1) end),
        else: p
    end)
  end

  defp spare(p) do
    p
    |> Gear.bag()
    |> Enum.filter(&(Gear.resolve(&1).slot in @spare_slots))
    |> Enum.max_by(&{Engine.upgrade_level(p, &1.uid), Brain.power(Gear.resolve(&1))}, fn ->
      nil
    end)
    |> case do
      nil -> nil
      g -> g.uid
    end
  end

  # ---------- Ép đồ ----------

  defp forge(p, st) do
    Enum.reduce(@forge_order, {p, st}, fn slot, {p, st} ->
      {p, st} = forge_slot(p, st, slot, 30)
      lines(p, st, slot)
    end)
  end

  defp forge_slot(p, st, _slot, 0), do: {p, st}

  defp forge_slot(p, st, slot, n) do
    id = p.equip[String.to_existing_atom(slot)]
    lvl = id && Engine.upgrade_level(p, id)
    cost = id && Engine.upgrade_cost(Gear.item(p, id), lvl)

    ok? =
      cost != nil and p.gold >= cost.gold + reserve(p) and spendable?(p, st, cost.items) and
        (cost.fail != "reset" or st.opts.soul) and
        (cost.at == "smith" or st.opts.chaos_up or rb(p) >= st.opts.chaos_from)

    if ok? do
      {r, p} = Engine.upgrade(p, slot, true, cost.at)

      if r.ok do
        res = r[:upgrade][:result]
        u = st.upgrades

        u = %{
          u
          | tries: u.tries + 1,
            ok: u.ok + if(res == "success", do: 1, else: 0),
            reset: u.reset + if(res == "reset", do: 1, else: 0),
            destroy: u.destroy + if(res == "destroy", do: 1, else: 0)
        }

        st = %{st | upgrades: u}

        st =
          if lvl + 1 >= 7,
            do:
              event(
                st,
                p,
                "Ép #{Gear.item(p, r[:uid] || id)[:name] || slot} +#{lvl + 1}: #{res_word(res)}."
              ),
            else: st

        forge_slot(p, st, slot, n - 1)
      else
        {p, st}
      end
    else
      {p, st}
    end
  end

  defp res_word("success"), do: "thành công"
  defp res_word("reset"), do: "thất bại, về +0"
  defp res_word("destroy"), do: "thất bại, VỠ đồ"
  defp res_word(other), do: other || "?"

  defp lines(p, st, slot) do
    id = p.equip[String.to_existing_atom(slot)]
    life = Data.rules().upgrade.life
    have = Map.get(p.inv, life.jewel, 0)

    if id && have > 0 && spendable?(p, st, %{life.jewel => 1}) do
      {r, p2} = Engine.life(p, slot)

      if r.ok do
        st = %{
          st
          | lines: %{
              tries: st.lines.tries + 1,
              ok: st.lines.ok + if(r.msg =~ "thêm dòng", do: 1, else: 0)
            }
        }

        lines(p2, st, slot)
      else
        {p, st}
      end
    else
      {p, st}
    end
  end

  # ngọc giữ lại cho bậc cánh tiếp theo (khi đã đủ Hỗn Nguyên cho bậc đó)
  defp spendable?(p, st, items) do
    keep = if st.opts.wings, do: wing_keep(p), else: %{}
    Enum.all?(items, fn {m, n} -> Map.get(p.inv, m, 0) - Map.get(keep, m, 0) >= n end)
  end

  defp wing_keep(p) do
    case next_wing(p) do
      %{items: items} = r ->
        cond do
          Map.get(p.inv, "jewel_chaos", 0) < Map.get(r.items, "jewel_chaos", 0) ->
            %{}

          # cánh 1: giữ Ước Nguyện để ép món dự phòng tới min_up
          r.id == "wing1" ->
            up = if uid = spare(p), do: Engine.upgrade_level(p, uid), else: 0
            %{"jewel_bless" => max(0, r.gear.min_up - up)}

          true ->
            items
        end

      _ ->
        %{}
    end
  end

  # ---------- Cánh ----------

  defp wing_tier(p) do
    case Gear.item(p, p.equip[:wing]) do
      nil -> 0
      it -> it[:tier] || 0
    end
  end

  defp next_wing(p) do
    case wing_tier(p) do
      0 -> Data.chaos("wing1")
      1 -> Data.chaos("wing2")
      2 -> Data.chaos("wing3")
      _ -> nil
    end
  end

  defp wings(p, %{opts: %{wings: false}} = st), do: {p, st}

  defp wings(p, st) do
    r = next_wing(p)

    with %{} <- r,
         true <- Enum.all?(r.items, fn {m, n} -> Map.get(p.inv, m, 0) >= n end),
         true <- p.gold >= r.gold + reserve(p),
         {p, uid} when uid != nil <- wing_input(p, st, r),
         # ép món dự phòng có thể đã tốn vàng
         true <- p.gold >= r.gold,
         {%{ok: true} = res, p} <- Chaos.combine(p, r.id, uid) do
      st = %{st | wing_tries: st.wing_tries + 1}
      out = res[:chaos][:result]

      st =
        event(
          st,
          p,
          "Máy Hỗn Nguyên — #{r.name}: #{if out == "success", do: "thành công", else: res.msg}"
        )

      {p, st}
    else
      _ -> {p, st}
    end
  end

  # món đặt vào công thức: cánh 1: món dự phòng ép tới min_up bằng Ước Nguyện; cánh 2, 3: cánh đang mặc (tháo ra)
  defp wing_input(p, _st, %{gear: %{slots: ["wing"], min_up: min}}) do
    id = p.equip[:wing]

    if id && Engine.upgrade_level(p, id) >= min do
      {_, p} = Engine.unequip(p, "wing")
      {p, id}
    else
      {p, nil}
    end
  end

  defp wing_input(p, st, %{gear: %{min_up: min}}) do
    case spare(p) do
      nil -> {p, nil}
      uid -> raise_spare(p, st, uid, min, 10)
    end
  end

  defp raise_spare(p, _st, uid, _min, 0), do: {p, if(Engine.upgrade_level(p, uid) > 0, do: uid)}

  defp raise_spare(p, st, uid, min, n) do
    lvl = Engine.upgrade_level(p, uid)
    cost = Engine.upgrade_cost(Gear.item(p, uid), lvl)

    cond do
      lvl >= min ->
        {p, uid}

      cost && cost.fail == nil && p.gold >= cost.gold + reserve(p) &&
          Enum.all?(cost.items, fn {m, k} -> Map.get(p.inv, m, 0) >= k end) ->
        {r, p} = Engine.upgrade(p, uid, true)
        if r.ok, do: raise_spare(p, st, r[:uid] || uid, min, n - 1), else: {p, nil}

      true ->
        {p, nil}
    end
  end
end
