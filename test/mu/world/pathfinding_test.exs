defmodule Mu.World.PathfindingTest do
  use ExUnit.Case, async: true

  alias Mu.World.{Maps, Pathfinding}

  # lưới từ chuỗi: "#" chặn
  defp grid(rows) do
    cells =
      for {row, y} <- Enum.with_index(rows),
          {ch, x} <- Enum.with_index(String.graphemes(row)),
          into: %{},
          do: {{x, y}, ch != "#"}

    fn x, y -> Map.get(cells, {x, y}, false) end
  end

  defp cost(from, path) do
    {_, c} =
      Enum.reduce(path, {from, 0}, fn n, {p, c} ->
        {n, c + if(Pathfinding.diagonal?(p, n), do: 14, else: 10)}
      end)

    c
  end

  # Dijkstra đơn giản làm chuẩn so sánh
  defp best_cost(w, from, to) do
    dirs = for dx <- -1..1, dy <- -1..1, {dx, dy} != {0, 0}, do: {dx, dy}

    loop = fn loop, open, dist ->
      case Enum.min_by(open, fn {_, d} -> d end, fn -> nil end) do
        nil ->
          nil

        {^to, d} ->
          d

        {{x, y} = cur, d} ->
          open = Map.delete(open, cur)

          {open, dist} =
            for {dx, dy} <- dirs,
                w.(x + dx, y + dy),
                dx == 0 or dy == 0 or (w.(x + dx, y) and w.(x, y + dy)),
                n = {x + dx, y + dy},
                nd = d + if(dx != 0 and dy != 0, do: 14, else: 10),
                nd < Map.get(dist, n, :infinity),
                reduce: {open, dist} do
              {o, di} -> {Map.put(o, n, nd), Map.put(di, n, nd)}
            end

          loop.(loop, open, dist)
      end
    end

    loop.(loop, %{from => 0}, %{from => 0})
  end

  test "đường thẳng và đường chéo" do
    w = grid([".....", ".....", "....."])
    assert {:ok, [{1, 0}, {2, 0}, {3, 0}]} = Pathfinding.find(w, {0, 0}, {3, 0}, 100)
    assert {:ok, [{1, 1}, {2, 2}]} = Pathfinding.find(w, {0, 0}, {2, 2}, 100)
    assert {:ok, []} = Pathfinding.find(w, {1, 1}, {1, 1}, 100)
  end

  test "không đi chéo cắt góc tường" do
    w = grid([".#", ".."])
    assert {:ok, path} = Pathfinding.find(w, {0, 0}, {1, 1}, 100)
    assert path == [{0, 1}, {1, 1}]
  end

  test "đích bị chặn / không tới được / hết ngân sách node → :error" do
    w = grid(["..#..", "..#..", "..#.."])
    assert :error = Pathfinding.find(w, {0, 0}, {2, 0}, 100)
    assert :error = Pathfinding.find(w, {0, 0}, {4, 0}, 100)
    assert :error = Pathfinding.find(w, {0, 0}, {9, 9}, 100)
    open = grid([String.duplicate(".", 30)])
    assert {:ok, _} = Pathfinding.find(open, {0, 0}, {29, 0}, 100)
    assert :error = Pathfinding.find(open, {0, 0}, {29, 0}, 5)
  end

  test "trên Lorencia: đường hợp lệ và ngắn nhất (so với Dijkstra)" do
    map = Maps.get("lorencia")
    w = &Maps.walkable?(map, &1, &2)
    from = map.player_spawn

    # ra cổng đông, qua hồ, tới vùng Spider, lên phía bắc qua cổng bắc
    for to <- [{40, 31}, {38, 11}, {50, 35}, {16, 5}, {10, 60}] do
      assert {:ok, path} = Pathfinding.find(w, from, to, 4096), inspect(to)
      assert List.last(path) == to

      Enum.reduce(path, from, fn {nx, ny} = n, {px, py} = p ->
        assert Pathfinding.chebyshev(p, n) == 1
        assert w.(nx, ny)
        if Pathfinding.diagonal?(p, n), do: assert(w.(nx, py) and w.(px, ny))
        n
      end)

      assert cost(from, path) == best_cost(w, from, to)
    end
  end
end
