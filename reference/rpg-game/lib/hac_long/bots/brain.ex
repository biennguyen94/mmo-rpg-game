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
  5. Máu < 45 %: có bình thì uống, không thì về Nhà (miễn phí) uống nước giếng.
  6. Chưa ở bản đồ hợp cấp → dịch chuyển (nếu được và đủ vàng) hoặc đi bộ qua cổng theo đường ngắn nhất.
  7. Ở bản đồ hợp cấp → đi tới con quái gần nhất không ai đánh, cấp không quá cấp mình + 1.
  """
  alias HacLong.Game.{Data, Engine, Gear}
  alias HacLong.World
  alias HacLong.World.Maps

  @main %{"dk" => "str", "dw" => "ene", "elf" => "agi", "mg" => "str"}
  @dirs %{"up" => {0, -1}, "down" => {0, 1}, "left" => {-1, 0}, "right" => {1, 0}}

  def decide(p, snap, opts \\ %{})

  def decide(nil, _snap, opts),
    do: %{"act" => "create", "name" => opts[:name] || "Lữ Khách", "cls" => opts[:cls] || "dk"}

  def decide(%{battle: %{over: true}}, _snap, _opts), do: %{"act" => "leave"}
  def decide(%{battle: %{} = b} = p, _snap, _opts), do: fight(p, b)

  def decide(p, snap, opts) do
    d = Engine.derived(p)

    cond do
      p.points > 0 ->
        %{"act" => "alloc", "stat" => @main[p.cls] || "str", "n" => min(p.points, 99)}

      g = better_gear(p) ->
        %{"act" => "equip", "id" => g}

      p.hp < d.maxHp * 0.45 ->
        heal(p, d)

      true ->
        roam(p, snap, opts[:seed] || 0)
    end
  end

  # ---------- Trận đánh ----------

  defp fight(p, _b) do
    d = Engine.derived(p)
    mp = Map.get(p, :mp) || 0

    skill =
      p
      |> Engine.skills()
      |> Enum.reverse()
      |> Enum.find(&(Engine.cooldown(p, &1.id) == 0 and mp >= Engine.skill_mp(p, &1)))

    cond do
      p.hp < d.maxHp * 0.35 and Engine.best_potion(p, d.maxHp - p.hp) ->
        %{"act" => "potion"}

      skill == nil and mp < d.maxMp * 0.3 and Engine.best_mana(p, d.maxMp - mp) ->
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
    |> Enum.filter(&(&1.slot in ~w(weapon armor shield) and (&1[:level] || 0) <= p.level))
    |> Enum.filter(&(&1[:cls] in [nil, p.cls]))
    |> Enum.find_value(fn it ->
      slot = String.to_existing_atom(it.slot)
      cur = Gear.item(p, p.equip[slot])
      if power(it) > power(cur), do: it.uid
    end)
  end

  defp power(nil), do: 0

  defp power(it),
    do: (it[:atk] || 0) + (it[:def] || 0) + Enum.sum(Map.values(it[:bonus] || %{}))

  defp heal(p, d) do
    case Engine.best_potion(p, d.maxHp - p.hp) do
      nil -> go_home_fountain(p)
      id -> %{"act" => "use", "id" => id}
    end
  end

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
    target = target_map(p, seed)

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

  defp hunt(p, nil), do: wander(p)

  defp hunt(p, snap) do
    me = {p.pos.x, p.pos.y}
    map = Maps.get(p.pos.map)

    targets =
      snap.monsters
      |> Enum.reject(&(&1.busy or &1.boss))
      |> Enum.filter(&(monster_level(map, &1.kind) <= p.level + 1))
      |> Enum.sort_by(&dist(me, {&1.x, &1.y}))
      |> Enum.map(&{&1.x, &1.y})

    case targets do
      [] -> wander(p)
      _ -> walk(p, map, Enum.take(targets, 3), snap) || wander(p)
    end
  end

  defp monster_level(%{side: true}, kind), do: Data.side_monster(kind).level

  defp monster_level(%{zone: zi}, kind) when is_integer(zi) do
    z = Data.zone(zi)
    Enum.find_value(z.monsters ++ [z.boss], 99, &(&1.id == kind && &1.level))
  end

  defp monster_level(_, _), do: 99

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
      dir -> %{"act" => "move", "dir" => dir}
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
