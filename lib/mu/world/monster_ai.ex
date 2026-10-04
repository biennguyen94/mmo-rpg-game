defmodule Mu.World.MonsterAi do
  @moduledoc """
  AI quái (`KB_GAME_DESIGN §9`), hàm thuần: `think/2` nhận quái + bối cảnh, trả quái mới và
  danh sách hành động (`{:attack, character_id}`) để `MapServer` thực hiện (roll sát thương).

  Trạng thái: `"idle"` → `"chase"` → `"attack"` → `"return"`; `"dead"` do MapServer xử lý
  (hồi sinh cần RNG). Quy ước Phase 1 (OPEN_QUESTIONS G14, G15, G5):

  - Aggro: người chơi còn sống, không đứng trong safe zone, gần nhất trong `aggroRange`
    (Chebyshev). Bị đánh thì đổi mục tiêu sang người gây nhiều sát thương nhất (`hit/3`).
  - Đuổi bằng A* giới hạn `@max_nodes` ô (KB_TECHNICAL §7); không ra đường thì bước thẳng
    nếu ô kề gần hơn đi được. Quái không bước vào ô safe zone (`ctx.walkable?` đã loại).
  - Mục tiêu mất/chết/vào safe zone, hoặc quái cách chỗ sinh quá `leashRange` → RETURN:
    hồi đầy HP, bỏ aggro, đi về chỗ sinh; tới nơi → IDLE. Kẹt đường về thì đặt thẳng về
    chỗ sinh (DEC-31).
  - Trong `attackRange`: đứng lại, mỗi `combat.baseCooldownMs` đánh một đòn (G5).

  `ctx`: `%{now, players: %{id => %{x, y, alive?, safe?}}, walkable?: fn x, y -> bool end,
  cooldown_ms}`.
  """

  alias Mu.World.Pathfinding

  @max_nodes 32

  def max_nodes, do: @max_nodes

  @doc "Một nhịp AI (10 Hz)."
  def think(%{state: "dead"} = m, _ctx), do: {m, []}

  def think(%{state: "idle"} = m, ctx) do
    case nearest(m, ctx) do
      nil -> {m, []}
      id -> think(%{m | state: "chase", target: id}, ctx)
    end
  end

  def think(%{state: "return"} = m, ctx) do
    cond do
      {m.x, m.y} == m.home ->
        {%{m | state: "idle", path: []}, []}

      # đang đi dở bước: giữ đường cũ
      m.path != [] ->
        {m, []}

      true ->
        case path_to(m, m.home, ctx) do
          # kẹt (A* giới hạn không ra đường, không bước thẳng được): về thẳng chỗ sinh
          [] -> {%{m | x: elem(m.home, 0), y: elem(m.home, 1), state: "idle"}, []}
          path -> {%{m | path: path}, []}
        end
    end
  end

  def think(%{state: s} = m, ctx) when s in ["chase", "attack"] do
    target = valid_target(m, ctx)

    cond do
      target == nil or Pathfinding.chebyshev({m.x, m.y}, m.home) > m.tpl["leashRange"] ->
        think(start_return(m), ctx)

      Pathfinding.chebyshev({m.x, m.y}, {target.x, target.y}) <= m.tpl["attackRange"] ->
        m = %{m | state: "attack", path: []}

        if ctx.now >= m.next_attack_at,
          # boss (P6-M5): nhịp đánh riêng `attackCooldownMs`
          do:
            {%{m | next_attack_at: ctx.now + (m.tpl["attackCooldownMs"] || ctx.cooldown_ms)},
             [{:attack, m.target}]},
          else: {m, []}

      true ->
        {%{m | state: "chase", path: path_to(m, {target.x, target.y}, ctx)}, []}
    end
  end

  @doc "Quái bị `character_id` đánh `dmg`: cộng dồn sát thương, đổi mục tiêu (G15)."
  def hit(%{state: "dead"} = m, _id, _dmg), do: m

  def hit(m, character_id, dmg) do
    damage_by = Map.update(m.damage_by, character_id, dmg, &(&1 + dmg))
    top = top_damager(%{m | damage_by: damage_by})

    case m.state do
      # đang về chỗ sinh: không nhận aggro mới
      "return" -> %{m | damage_by: damage_by}
      "idle" -> %{m | damage_by: damage_by, target: top, state: "chase"}
      _ -> %{m | damage_by: damage_by, target: top}
    end
  end

  @doc "Người gây nhiều sát thương nhất (chủ đồ rơi khi loot protect, G13)."
  def top_damager(%{damage_by: d}) when map_size(d) == 0, do: nil
  def top_damager(%{damage_by: d}), do: d |> Enum.max_by(fn {_, v} -> v end) |> elem(0)

  @doc "Bắt đầu về chỗ sinh: hồi đầy HP, bỏ aggro (§9)."
  def start_return(m),
    do: %{m | state: "return", target: nil, damage_by: %{}, hp: m.hp_max, path: []}

  defp valid_target(%{target: nil}, _ctx), do: nil

  defp valid_target(m, ctx) do
    case ctx.players[m.target] do
      %{alive?: true, safe?: false} = p -> p
      _ -> nil
    end
  end

  defp nearest(m, ctx) do
    ctx.players
    |> Enum.filter(fn {_, p} -> p.alive? and not p.safe? end)
    |> Enum.map(fn {id, p} -> {id, Pathfinding.chebyshev({m.x, m.y}, {p.x, p.y})} end)
    |> Enum.filter(fn {_, d} -> d <= m.tpl["aggroRange"] end)
    |> Enum.min_by(fn {id, d} -> {d, id} end, fn -> nil end)
    |> case do
      nil -> nil
      {id, _} -> id
    end
  end

  # A* giới hạn; không ra đường thì bước thẳng một ô nếu gần đích hơn
  defp path_to(m, to, ctx) do
    case Pathfinding.find(ctx.walkable?, {m.x, m.y}, to, @max_nodes) do
      {:ok, path} -> path
      :error -> direct_step(m, to, ctx)
    end
  end

  defp direct_step(%{x: x, y: y}, {tx, ty} = to, ctx) do
    step = {x + sign(tx - x), y + sign(ty - y)}
    {sx, sy} = step
    closer? = Pathfinding.chebyshev(step, to) < Pathfinding.chebyshev({x, y}, to)
    corner_ok? = sx == x or sy == y or (ctx.walkable?.(sx, y) and ctx.walkable?.(x, sy))
    if closer? and ctx.walkable?.(sx, sy) and corner_ok?, do: [step], else: []
  end

  defp sign(0), do: 0
  defp sign(n) when n > 0, do: 1
  defp sign(_), do: -1
end
