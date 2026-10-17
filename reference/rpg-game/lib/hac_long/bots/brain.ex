defmodule HacLong.Bots.Brain do
  @moduledoc """
  Bộ não người chơi AI (Phase 16): hàm thuần, từ nhân vật `p` và trạng thái bản đồ đang đứng `snap`
  (`MapServer.snapshot/1`, nil ở bản đồ riêng) trả về **một lệnh** như client gửi (`%{"act" => ...}`)
  hoặc nil (đứng chờ). Bot gửi lệnh qua `Session` nên theo đúng luật, giới hạn tốc độ như người thật.

  Thứ tự ưu tiên:
  1. Chưa có nhân vật → tạo (`name`, `cls` do tiến trình bot chọn).
  2. Trong trận: xong → rời; máu < 35 % và có bình → uống; MP thiếu và có bình mana → uống mana;
     kỹ năng mạnh nhất đang sẵn → dùng; còn lại đánh thường.
  3. Còn điểm tiềm năng → cộng hết vào chỉ số chính của lớp.
  4. Trong túi có vũ khí / giáp / khiên tốt hơn đồ đang mặc → mặc.
  5. Máu < 45 % và có bình → uống.
  6. Sắp hết bình (Phase 5, `RULES.bots.potion_min` / `mana_min`) mà đủ vàng → về Làng mua ở Bà Lang (`restock/1`).
  7. Máu < 45 %, hết bình: đủ vàng thì nghỉ ở Quán Trọ Làng, không thì về Nhà (miễn phí) uống nước giếng.
  8. Chưa ở bản đồ hợp cấp → dịch chuyển (nếu được và đủ vàng) hoặc đi bộ qua cổng theo đường ngắn nhất.
  9. Ở bản đồ hợp cấp → đi tới con quái gần nhất không ai đánh, cấp không quá cấp mình + 1.
  10. Đủ cấp (cấp trùm + 1) mà trùm vùng kế tiếp chưa hạ → vào phòng trùm đánh để mở vùng mới.

  Vừa gục (số lần chết tăng) thì nghỉ ngẫu nhiên `RULES.bots.rest_after_death_s` giây ([ít nhất, nhiều nhất]) trước
  khi đi luyện tiếp (`rest_until/4`, `resting?/3`); không thì bot dịch chuyển về chỗ cũ ngay sau vài giây, trông như
  chưa chết.
  """
  alias HacLong.Game.{Data, Engine, Gear, Rng}
  alias HacLong.World
  alias HacLong.World.Maps

  @main %{"dk" => "str", "dw" => "ene", "elf" => "agi", "mg" => "str"}
  @dirs %{"up" => {0, -1}, "down" => {0, 1}, "left" => {-1, 0}, "right" => {1, 0}}

  @rest Data.rules().bots.rest_after_death_s
  @shop Data.rules().bots
  @hp_ids ~w(potion_s potion_m potion_l)
  @mp_ids ~w(mana_s mana_m mana_l)
  @opt_line Data.rules().upgrade.life.per_line

  @doc """
  Mốc (ms) bot được đi luyện tiếp: số lần chết của `p` tăng so với `prev_deaths` (lần trước bot nhìn) thì nghỉ
  ngẫu nhiên trong `RULES.bots.rest_after_death_s` giây tính từ `now`; không thì giữ `until`.
  """
  def rest_until(until, prev_deaths, p, now) do
    if is_integer(prev_deaths) and p != nil and (p[:deaths] || 0) > prev_deaths do
      [lo, hi] = @rest
      now + round((lo + Rng.uniform() * (hi - lo)) * 1000)
    else
      until
    end
  end

  @doc "Đang nghỉ sau khi gục: chưa tới mốc và không ở trong trận (trận đã xong thì vẫn rời trận như thường)."
  def resting?(p, until, now), do: p != nil and p.battle == nil and now < until

  def decide(p, snap, opts \\ %{})

  def decide(nil, _snap, opts),
    do: %{"act" => "create", "name" => opts[:name] || "Lữ Khách", "cls" => opts[:cls] || "dk"}

  def decide(%{battle: %{over: true}}, _snap, _opts), do: %{"act" => "leave"}
  # đồ sát: chưa tới lượt thì chờ (không gửi lệnh)
  def decide(%{battle: %{live: true, encounter: %{mine: false}}}, _snap, _opts), do: nil
  def decide(%{battle: %{}} = p, _snap, _opts), do: fight(p)

  def decide(p, snap, opts) do
    d = Engine.derived(p)

    cond do
      p.points > 0 ->
        %{"act" => "alloc", "stat" => @main[p.cls] || "str", "n" => min(p.points, 99)}

      g = better_gear(p) ->
        %{"act" => "equip", "id" => g}

      p.hp < d.maxHp * 0.45 and Engine.best_potion(p, d.maxHp - p.hp) ->
        %{"act" => "use", "id" => Engine.best_potion(p, d.maxHp - p.hp)}

      (need = restock(p)) != [] ->
        shop(p, need, snap)

      p.hp < d.maxHp * 0.45 ->
        heal(p, d, snap)

      true ->
        roam(p, snap, opts[:seed] || 0)
    end
  end

  # ---------- Trận đánh ----------

  @doc """
  Lệnh trong trận: máu < `hp` (tỉ lệ máu tối đa) và có bình → uống; chưa có kỹ năng dùng được và MP < `mp` → uống
  mana; kỹ năng mạnh nhất (cuối bộ kỹ năng) đang sẵn → dùng; còn lại đánh thường. Tự đánh (Phase 4) dùng chung.
  """
  def fight(p, hp \\ 0.35, mp_pct \\ 0.3) do
    d = Engine.derived(p)
    mp = Map.get(p, :mp) || 0

    skill =
      p
      |> Engine.skills()
      |> Enum.reverse()
      |> Enum.find(&(Engine.cooldown(p, &1.id) == 0 and mp >= Engine.skill_mp(p, &1)))

    cond do
      p.hp < d.maxHp * hp and Engine.best_potion(p, d.maxHp - p.hp) ->
        %{"act" => "potion"}

      skill == nil and mp < d.maxMp * mp_pct and Engine.best_mana(p, d.maxMp - mp) ->
        %{"act" => "mana"}

      skill ->
        %{"act" => "skill", "skill" => skill.id}

      true ->
        %{"act" => "attack"}
    end
  end

  # ---------- Đồ đạc, hồi máu ----------

  # món trong túi đồ hiếm mạnh hơn món đang mặc cùng loại (vũ khí theo tấn công, giáp / khiên theo phòng thủ)
  defp better_gear(p) do
    p
    |> Gear.bag()
    |> Enum.map(&Gear.resolve/1)
    |> Enum.filter(&(&1.slot in Engine.gear_slots() and Engine.can_wear?(p, &1)))
    |> Enum.find_value(fn it ->
      slot = Engine.equip_slot(p, it)
      cur = Gear.item(p, p.equip[slot])
      if power(it) > power(cur), do: it.uid
    end)
  end

  @doc "Sức mạnh thô một món đồ (tấn công + phòng thủ + dòng cộng thêm), để so với món đang mặc."
  def power(nil), do: 0

  def power(it),
    do: (it[:atk] || 0) + (it[:def] || 0) + (it[:opt] || 0) * @opt_line

  # hết bình: đủ vàng thì nghỉ trọ ở Làng, không thì về Nhà uống giếng (miễn phí)
  defp heal(p, _d, snap) do
    if p.gold >= Engine.rest_cost(p) * @shop.inn_gold_mult and village_npc("inn"),
      do: at_village_npc(p, "inn", snap, fn -> %{"act" => "rest"} end),
      else: go_home_fountain(p)
  end

  # ---------- Mua bình (Phase 5, B-32) ----------

  @doc """
  Bình cần mua: `[{id, số}]`. Còn ít hơn `RULES.bots.potion_min` bình máu thì mua tới `potion_buy` (bình mana tương
  tự, chỉ lớp có MP); chỉ tính khi mua được ít nhất mức tối thiểu với số vàng đang có.
  """
  def restock(p) do
    d = Engine.derived(p)

    kinds =
      [{@hp_ids, d.maxHp, @shop.potion_min, @shop.potion_buy}] ++
        if d.maxMp > 0, do: [{@mp_ids, d.maxMp, @shop.mana_min, @shop.mana_buy}], else: []

    {need, _gold} =
      Enum.reduce(kinds, {[], p.gold}, fn {ids, max, min, buy}, {acc, gold} ->
        have = Enum.sum(Enum.map(ids, &Map.get(p.inv, &1, 0)))

        with true <- have < min,
             id when id != nil <- pick_potion(p, ids, max, gold, min),
             n = min(buy - have, div(gold, Engine.price(p, id))),
             true <- n >= min - have do
          {acc ++ [{id, n}], gold - n * Engine.price(p, id)}
        else
          _ -> {acc, gold}
        end
      end)

    need
  end

  # rẻ nhất mà hồi được ≥ `potion_heal_min` máu (MP) tối đa; không có thì loại mạnh nhất mua được `min` bình
  defp pick_potion(p, ids, max, gold, min) do
    ok =
      Enum.filter(ids, fn id ->
        it = Data.item(id)
        (it[:level] || 0) <= p.level and gold >= Engine.price(p, id) * min
      end)

    Enum.find(ok, &(elem(Engine.potion_amount(p, &1), 1) >= max * @shop.potion_heal_min)) ||
      List.last(ok)
  end

  defp shop(p, [{id, n} | _], snap),
    do: at_village_npc(p, "herbalist", snap, fn -> %{"act" => "buy", "id" => id, "n" => n} end)

  defp village_npc(role), do: Enum.find(Maps.get("village").npcs, &(&1.role == role))

  # tới NPC `role` ở Làng; đứng cạnh rồi thì ra lệnh `then`
  defp at_village_npc(%{pos: %{map: "village", x: x, y: y}} = p, role, snap, then) do
    %{at: {nx, ny}} = village_npc(role)

    if abs(nx - x) + abs(ny - y) == 1,
      do: then.(),
      else: walk(p, Maps.get("village"), [{nx, ny}], snap)
  end

  defp at_village_npc(p, _role, _snap, _then), do: go_to(p, "village")

  defp go_home_fountain(%{pos: %{map: "home"}} = p) do
    map = Maps.get("home")

    fountain =
      for {row, y} <- Enum.with_index(rows(map)), {"F", x} <- Enum.with_index(row), do: {x, y}

    walk(p, map, fountain, nil)
  end

  defp go_home_fountain(_p), do: %{"act" => "travel", "to" => "home"}

  # ---------- Chọn nơi luyện, di chuyển ----------

  @doc """
  Bản đồ luyện cho `p`: có quái, cấp quái thấp nhất ≤ cấp mình, cao nhất ≤ cấp mình + 1; trong 3 bản đồ
  cấp cao nhất thì mỗi bot (`seed`) chọn một cái để các bot không dồn về một chỗ.
  """
  def target_map(p, seed \\ 0) do
    candidates =
      for id <- Maps.ids(),
          m = Maps.get(id),
          not m.private and id != "tower" and m.spawns != [],
          reachable?(p, m),
          lo = World.min_level(m),
          lo != nil and lo <= p.level,
          hi = max_level(m),
          hi <= p.level + 1,
          do: {hi, lo, id}

    case Enum.sort(candidates, :desc) do
      [] -> "forest_1"
      best -> best |> Enum.at(rem(seed, min(3, length(best)))) |> elem(2)
    end
  end

  defp max_level(%{side: true} = m),
    do: m.spawns |> Enum.map(&Data.side_monster(&1.monster).level) |> Enum.max()

  defp max_level(m) do
    z = Data.zone(m.zone)
    kinds = Enum.map(m.spawns, & &1.monster)
    z.monsters |> Enum.filter(&(&1.id in kinds)) |> Enum.map(& &1.level) |> Enum.max(fn -> 99 end)
  end

  # tới được: bản đồ vùng đã mở, bản đồ phụ đã tới hoặc có đường cổng từ Làng qua các vùng đã mở
  defp reachable?(p, %{side: true, id: id}) do
    id in (Map.get(p, :visited) || []) or next_portal(p, "village", id) != nil
  end

  defp reachable?(p, %{zone: zi}) when is_integer(zi), do: Engine.zone_unlocked?(p, zi)
  defp reachable?(_p, _m), do: true

  defp roam(p, snap, seed) do
    here = p.pos.map
    target = boss_room(p) || target_map(p, seed)

    cond do
      here == "home" and target != "home" ->
        go_to(p, target)

      here != target ->
        go_to(p, target)

      true ->
        hunt(p, snap)
    end
  end

  # tới bản đồ `target`: dịch chuyển nếu được và đủ vàng (giữ lại ít nhất gấp đôi giá), không thì đi bộ qua cổng
  defp go_to(p, target) do
    map = Maps.get(target)
    cost = World.travel_cost(map)

    if World.can_travel?(p, map) and p.gold >= cost * 2,
      do: %{"act" => "travel", "to" => target},
      else: walk_route(p, target)
  end

  defp walk_route(p, target) do
    here = Maps.get(p.pos.map)

    case next_portal(p, here.id, target) do
      nil -> if(here.id != "village", do: %{"act" => "travel", "to" => "village"})
      portal -> walk(p, here, [portal.at], nil)
    end
  end

  @doc "Cổng đầu tiên trên đường ngắn nhất (theo số lần qua cổng) từ bản đồ `from` tới `to`, hoặc nil."
  def next_portal(p, from, to) do
    bfs_maps(p, [{from, nil}], MapSet.new([from]), to)
  end

  defp bfs_maps(_p, [], _seen, _to), do: nil

  defp bfs_maps(p, [{id, first} | rest], seen, to) do
    if id == to do
      first
    else
      next =
        for pt <- Maps.get(id).portals,
            not MapSet.member?(seen, pt.to),
            m = Maps.get(pt.to),
            not m.private,
            open?(p, m),
            do: {pt.to, first || pt}

      seen = Enum.reduce(next, seen, fn {mid, _}, s -> MapSet.put(s, mid) end)
      bfs_maps(p, rest ++ next, seen, to)
    end
  end

  defp open?(p, %{zone: zi}) when is_integer(zi), do: Engine.zone_unlocked?(p, zi)
  defp open?(_p, _m), do: true

  @doc "Phòng trùm nên vào: trùm của vùng cuối đã mở chưa hạ và cấp mình ≥ cấp trùm + 1 (nil nếu không)."
  def boss_room(p) do
    zones = Data.zones()

    zones
    |> Enum.with_index()
    |> Enum.find(fn {z, i} -> Engine.zone_unlocked?(p, i) and z.boss.id not in p.bosses end)
    |> case do
      {z, _} when p.level >= z.boss.level + 1 ->
        if(Maps.get(z.id <> "_boss"), do: z.id <> "_boss")

      _ ->
        nil
    end
  end

  @doc """
  Đi tới con quái gần nhất không ai đánh (trùm thường của bản đồ có quái hồi sinh thì bỏ qua) thỏa `keep`
  (`fn quái, bản_đồ -> bool`, mặc định cấp không quá cấp mình + 1); không có con nào thì đi lang thang.
  """
  def hunt(p, snap, keep \\ nil)
  def hunt(p, nil, _keep), do: wander(p)

  def hunt(p, snap, keep) do
    me = {p.pos.x, p.pos.y}
    map = Maps.get(p.pos.map)
    keep = keep || fn m, map -> monster_level(map, m.kind) <= p.level + 1 end

    targets =
      snap.monsters
      |> Enum.reject(&(&1.busy or (&1.boss and map.spawns != [])))
      |> Enum.filter(&keep.(&1, map))
      |> Enum.sort_by(&dist(me, {&1.x, &1.y}))
      |> Enum.map(&{&1.x, &1.y})

    case targets do
      [] -> wander(p)
      _ -> walk(p, map, Enum.take(targets, 3), snap) || wander(p)
    end
  end

  @doc "Cấp loại quái `kind` trên bản đồ `map` (99 nếu không biết)."
  def monster_level(%{side: true}, kind), do: (Data.side_monster(kind) || %{level: 99}).level

  def monster_level(%{zone: zi}, kind) when is_integer(zi) do
    z = Data.zone(zi)
    Enum.find_value(z.monsters ++ [z.boss], 99, &(&1.id == kind && &1.level))
  end

  def monster_level(_, _), do: 99

  defp wander(p) do
    map = Maps.get(p.pos.map)
    {x, y} = {p.pos.x, p.pos.y}

    @dirs
    |> Enum.shuffle()
    |> Enum.find_value(fn {dir, {dx, dy}} ->
      if Maps.walkable?(map, x + dx, y + dy) and Maps.portal_at(map, x + dx, y + dy) == nil,
        do: %{"act" => "move", "dir" => dir}
    end)
  end

  # ---------- Tìm đường trên ô ----------

  @doc """
  Bước đi đầu tiên (`%{"act" => "move", "dir" => ...}`) tới ô gần nhất trong `goals`, hoặc nil. Ô đi được theo
  `Maps.walkable?/3`; cổng, giếng, quái chỉ được bước vào nếu là đích.
  """
  def walk(p, map, goals, snap) do
    goals = MapSet.new(goals)
    start = {p.pos.x, p.pos.y}
    blocked = monsters_at(snap) |> MapSet.difference(goals)

    case first_step(map, start, goals, blocked) do
      nil -> nil
      # gặp trùm vào trận luôn (như client, Phase 11)
      dir -> %{"act" => "move", "dir" => dir, "confirm" => true}
    end
  end

  defp monsters_at(nil), do: MapSet.new()
  defp monsters_at(snap), do: MapSet.new(snap.monsters, &{&1.x, &1.y})

  defp first_step(map, start, goals, blocked) do
    queue = :queue.from_list([{start, nil}])
    search(map, queue, MapSet.new([start]), goals, blocked)
  end

  defp search(map, queue, seen, goals, blocked) do
    case :queue.out(queue) do
      {:empty, _} ->
        nil

      {{:value, {pos, first}}, queue} ->
        if MapSet.member?(goals, pos) and first != nil do
          first
        else
          {queue, seen} =
            Enum.reduce(@dirs, {queue, seen}, fn {dir, {dx, dy}}, {q, s} ->
              {x, y} = pos
              nxt = {x + dx, y + dy}
              goal? = MapSet.member?(goals, nxt)

              if MapSet.member?(s, nxt) or MapSet.member?(blocked, nxt) or
                   not (goal? or plain?(map, nxt)) do
                {q, s}
              else
                {:queue.in({nxt, first || dir}, q), MapSet.put(s, nxt)}
              end
            end)

          search(map, queue, seen, goals, blocked)
        end
    end
  end

  defp plain?(map, {x, y}),
    do: Maps.walkable?(map, x, y) and Maps.portal_at(map, x, y) == nil

  defp rows(map),
    do:
      Enum.map(0..(map.height - 1), fn y ->
        Enum.map(0..(map.width - 1), &Maps.tile(map, &1, y))
      end)

  defp dist({a, b}, {c, d}), do: abs(a - c) + abs(b - d)
end
