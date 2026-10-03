defmodule Mu.World.MapsTest do
  @moduledoc """
  Kiểm map (KB_TECH_STACK §8) cho **mọi** map: collision khớp JSON, spawn hợp lệ, safe zone đúng,
  NPC có shop, cổng hai chiều (P2-M4).
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mu.Game.Data
  alias Mu.World.{Collision, Maps, Pathfinding}

  @maps ~w(lorencia noria)

  defp json(id),
    do: Path.expand("../../../priv/maps/#{id}.json", __DIR__) |> File.read!() |> Jason.decode!()

  # tất cả ô đi được nối từ `from` (BFS 8 hướng, không cắt góc như Pathfinding)
  defp reachable(map, from) do
    Stream.unfold({[from], MapSet.new([from])}, fn
      {[], _} ->
        nil

      {[{x, y} | rest], seen} ->
        next =
          for dx <- -1..1,
              dy <- -1..1,
              {dx, dy} != {0, 0},
              n = {x + dx, y + dy},
              not MapSet.member?(seen, n),
              Pathfinding.find(&Maps.walkable?(map, &1, &2), {x, y}, n, 4) == {:ok, [n]},
              do: n

        seen = Enum.reduce(next, seen, &MapSet.put(&2, &1))
        {seen, {rest ++ next, seen}}
    end)
    |> Enum.at(-1)
  end

  test "Phase 2 (P2-M4): Lorencia + Noria, 64×64, có nguồn gốc" do
    assert Enum.sort(Maps.ids()) == @maps

    for id <- @maps, map = Maps.get(id), j = json(id) do
      assert {map.width, map.height} == {64, 64}
      assert length(map.tiles) == 64 and Enum.all?(map.tiles, &(String.length(&1) == 64))
      assert j["sourceType"] == "IMPLEMENTATION" and j["verified"] == false
      assert map.collision == Collision.from_map(j)
    end

    out = capture_io(fn -> Mix.Tasks.Mu.Maps.Build.run(["--check"]) end)
    refute out =~ "lệch"
  end

  for id <- ~w(lorencia noria) do
    @id id

    test "#{id}: khép kín, safe zone đi được, playerSpawn trong thị trấn" do
      map = Maps.get(@id)

      for i <- 0..63,
          {x, y} <- [{i, 0}, {i, 63}, {0, i}, {63, i}],
          do: refute(Maps.walkable?(map, x, y))

      refute Maps.walkable?(map, -1, 5)

      for z <- map.safe_zones, x <- z.x..(z.x + z.w - 1), y <- z.y..(z.y + z.h - 1) do
        assert Collision.walkable?(map.collision, 64, 64, x, y), "#{@id} ô #{x},#{y}"
        assert Maps.safe?(map, x, y)
      end

      {x, y} = map.player_spawn
      assert Maps.walkable?(map, x, y)
      assert %{id: "town"} = Maps.safe_zone_at(map, x, y)
    end

    test "#{id}: NPC trong safe zone, chặn ô, có shop đúng map" do
      map = Maps.get(@id)
      assert map.npcs != []

      for n <- map.npcs do
        assert Collision.walkable?(map.collision, 64, 64, n.x, n.y)
        refute Maps.walkable?(map, n.x, n.y)
        assert Maps.safe?(map, n.x, n.y)
        assert %{"mapId" => @id} = Data.shop(n.id)
      end
    end

    test "#{id}: vùng sinh quái trong map, ngoài safe zone, đủ ô, quái đúng map" do
      map = Maps.get(@id)

      for %{monster: mon, count: n, area: a} <- map.spawns do
        assert %{"mapId" => @id} = Data.monster(mon)
        cells = for x <- a.x..(a.x + a.w - 1), y <- a.y..(a.y + a.h - 1), do: {x, y}
        assert Enum.all?(cells, fn {x, y} -> x in 0..63 and y in 0..63 end)
        refute Enum.any?(cells, fn {x, y} -> Maps.safe?(map, x, y) end), mon
        assert Enum.count(cells, fn {x, y} -> Maps.walkable?(map, x, y) end) >= n * 5, mon
      end
    end

    test "#{id}: từ playerSpawn đi tới mọi ô đi được (NPC, vùng quái, cổng)" do
      map = Maps.get(@id)
      seen = reachable(map, map.player_spawn)

      all =
        for x <- 0..63, y <- 0..63, Maps.walkable?(map, x, y), into: MapSet.new(), do: {x, y}

      assert MapSet.equal?(seen, all), "có vùng đi được bị cô lập"

      for n <- map.npcs,
          do:
            assert(
              Enum.any?([{1, 0}, {-1, 0}, {0, 1}, {0, -1}], fn {dx, dy} ->
                MapSet.member?(seen, {n.x + dx, n.y + dy})
              end)
            )
    end
  end

  test "cổng hai chiều: ô cổng đi được; ô đích đi được, không phải cổng; map đích có cổng về" do
    for id <- @maps, map = Maps.get(id), p <- map.portals do
      for x <- p.x..(p.x + p.w - 1), y <- p.y..(p.y + p.h - 1) do
        assert Maps.walkable?(map, x, y)
        assert Maps.portal_at(map, x, y) == p
      end

      dest = Maps.get(p.to)
      assert dest, "#{id} → #{p.to}"
      assert Maps.walkable?(dest, p.to_x, p.to_y)
      assert Maps.portal_at(dest, p.to_x, p.to_y) == nil
      assert Enum.any?(dest.portals, &(&1.to == id))
    end

    assert %{to: "noria", level_required: 10} = Maps.portal_at(Maps.get("lorencia"), 15, 8)
    assert %{to: "lorencia", level_required: 0} = Maps.portal_at(Maps.get("noria"), 32, 61)
  end

  test "B-1 (a): vùng quái mạnh cách vùng Spider ≥ 7 ô (> aggroRange 5 + tầm đánh xa 4 không chồng)" do
    map = Maps.get("lorencia")
    spider = Enum.find(map.spawns, &(&1.monster == "spider")).area

    for %{monster: mon, area: a} <- map.spawns,
        mon != "spider",
        Mu.Game.Data.monster(mon)["level"] >= 6 do
      # khoảng cách Chebyshev giữa hai hình chữ nhật
      dx = max(0, max(a.x - (spider.x + spider.w - 1), spider.x - (a.x + a.w - 1)))
      dy = max(0, max(a.y - (spider.y + spider.h - 1), spider.y - (a.y + a.h - 1)))
      assert max(dx, dy) >= 7, mon
    end
  end

  test "client_data không có collision/công thức, có cổng" do
    data = Maps.client_data(Maps.get("lorencia"))
    assert data.id == "lorencia"
    refute Map.has_key?(data, :collision)

    assert [%{to: "noria", levelRequired: 10, x: 15, y: 8, w: 2, h: 1}] =
             Enum.map(data.portals, &Map.delete(&1, :id))
  end
end
