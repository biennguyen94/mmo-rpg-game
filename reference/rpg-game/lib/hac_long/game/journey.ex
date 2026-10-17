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
    +10 / +11 ở Máy Hỗn Nguyên chỉ khi `chaos_up` (có thể vỡ đồ);
  - cánh: ghép cánh 1 → 2 → 3 ở Máy Hỗn Nguyên khi đủ nguyên liệu (`wings`);
  - nghỉ trọ khi máu < 60 % (hết vàng thì về Nhà uống giếng, miễn phí), mua bình như bot (`Brain.restock/1`);
  - chuyển sinh ngay khi đạt cấp tối đa (nếu `boss_first`: sau khi hạ Hắc Long).

  Không mô phỏng: việc hằng ngày, sự kiện, tháp, thú cưng / nhà / nấu ăn, chợ, tổ đội, PK, trùm thế giới.
  Hàm thuần; số ngẫu nhiên theo `:rand` (đặt seed ở mix task để chạy lại ra đúng kết quả).
  """

  alias HacLong.Bots.Brain
  alias HacLong.Game.{Chaos, Data, Engine, Gear, Quests}
  alias HacLong.World
  alias HacLong.World.Maps

  @defaults %{
    rebirths: 3,
    max_fights: 150_000,
    quests: true,
    soul: true,
    wings: true,
    chaos_up: false,
    boss_first: true,
    ban_window: 8,
    ban_losses: 2,
    ban_fights: 150,
    lord_every: 40,
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
      map: nil,
      seen_maps: MapSet.new(),
      gear_key: nil,
      fountain: 0,
      rest_gold: 0,
      upgrades: %{tries: 0, ok: 0, reset: 0, destroy: 0},
      lines: %{tries: 0, ok: 0},
      wing_tries: 0,
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

  defp heal(p, st) do
    d = Engine.derived(p)

    cond do
      p.hp >= d.maxHp * 0.6 ->
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
    case boss_target(p, st) do
      nil -> map_target(p, st)
      t -> t
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
          do: {xp_score(p, specs), m, specs}

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

  # chúa tể vùng chuyển sinh: con có hệ số máu cao nhất, cao hơn hẳn các con khác
  defp lord(%{realm: k}, specs) when is_integer(k) do
    top = Enum.max_by(specs, &Map.get(&1, :mult, 1))
    rest = specs -- [top]

    if rest != [] and
         Map.get(top, :mult, 1) > 1.5 * Enum.max(Enum.map(rest, &Map.get(&1, :mult, 1))),
       do: top
  end

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

    if lord != nil and
         st.fights - Map.get(st.lord_at, m.id, -st.opts.lord_every) >= st.opts.lord_every and
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
        {p, st} = forge(p, st)
        {p, st} = wings(p, st)
        {p, st} = gear_up(p, st)
        {sell_junk(p, st), %{st | gear_key: key}}
      else
        {p, st}
      end

    {potions(p), st}
  end

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
        (cost.fail != "reset" or st.opts.soul) and (cost.at == "smith" or st.opts.chaos_up)

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
