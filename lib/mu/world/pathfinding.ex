defmodule Mu.World.Pathfinding do
  @moduledoc """
  A* 8 hướng, heuristic octile (`KB_TECHNICAL §7`). Hàm thuần.

  Chi phí: thẳng 10, chéo 14 (≈ 10·√2, số nguyên để so sánh chính xác). Không đi chéo
  cắt góc: bước chéo cần cả hai ô kề thẳng đi được. `max_nodes` giới hạn số ô mở rộng
  (quái dùng giới hạn nhỏ, KB §7 ví dụ 32).
  """

  @straight 10
  @diagonal 14
  @dirs for dx <- -1..1, dy <- -1..1, {dx, dy} != {0, 0}, do: {dx, dy}

  @doc """
  Đường từ `from` tới `to` (không gồm `from`). `walkable?` là `fn x, y -> boolean end`.
  `{:ok, [{x, y}, ...]}` (rỗng nếu `from == to`) hoặc `:error`.
  """
  def find(walkable?, from, to, max_nodes) do
    cond do
      from == to ->
        {:ok, []}

      not walkable?.(elem(to, 0), elem(to, 1)) ->
        :error

      true ->
        search(
          walkable?,
          to,
          :gb_sets.singleton({h(from, to), 0, from}),
          %{from => 0},
          %{},
          MapSet.new(),
          max_nodes
        )
    end
  end

  defp search(_w, _to, _open, _g, _came, _closed, 0), do: :error

  defp search(walkable?, to, open, g, came, closed, budget) do
    if :gb_sets.is_empty(open) do
      :error
    else
      {{_f, cost, cur}, open} = :gb_sets.take_smallest(open)

      cond do
        cur == to ->
          {:ok, rebuild(came, to, [])}

        MapSet.member?(closed, cur) ->
          search(walkable?, to, open, g, came, closed, budget)

        true ->
          closed = MapSet.put(closed, cur)

          {open, g, came} =
            for {nx, ny} = n <- neighbors(walkable?, cur),
                not MapSet.member?(closed, n),
                step = step_cost(cur, n),
                cost + step < Map.get(g, n, :infinity),
                reduce: {open, g, came} do
              {open, g, came} ->
                c = cost + step

                {:gb_sets.add({c + h({nx, ny}, to), c, n}, open), Map.put(g, n, c),
                 Map.put(came, n, cur)}
            end

          search(walkable?, to, open, g, came, closed, budget - 1)
      end
    end
  end

  defp neighbors(walkable?, {x, y}) do
    for {dx, dy} <- @dirs,
        walkable?.(x + dx, y + dy),
        dx == 0 or dy == 0 or (walkable?.(x + dx, y) and walkable?.(x, y + dy)),
        do: {x + dx, y + dy}
  end

  defp step_cost({x1, y1}, {x2, y2}) when x1 != x2 and y1 != y2, do: @diagonal
  defp step_cost(_, _), do: @straight

  defp h({x1, y1}, {x2, y2}) do
    dx = abs(x1 - x2)
    dy = abs(y1 - y2)
    @straight * max(dx, dy) + (@diagonal - @straight) * min(dx, dy)
  end

  defp rebuild(came, node, acc) do
    case Map.fetch(came, node) do
      {:ok, prev} -> rebuild(came, prev, [node | acc])
      :error -> acc
    end
  end

  @doc "Bước `a → b` có phải bước chéo không."
  def diagonal?({x1, y1}, {x2, y2}), do: x1 != x2 and y1 != y2

  @doc "Khoảng cách Chebyshev (G4)."
  def chebyshev({x1, y1}, {x2, y2}), do: max(abs(x1 - x2), abs(y1 - y2))
end
