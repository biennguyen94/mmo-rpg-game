defmodule Mu.World.MapsTest do
  @moduledoc "Kiểm map (KB_TECH_STACK §8): collision khớp JSON, spawn hợp lệ, safe zone đúng."
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mu.World.{Collision, Maps, Pathfinding}

  @json Path.expand("../../../priv/maps/lorencia.json", __DIR__)
        |> File.read!()
        |> Jason.decode!()

  setup_all do
    %{map: Maps.get("lorencia")}
  end

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

  test "Phase 1 chỉ có Lorencia, 64×64, có nguồn gốc", %{map: map} do
    assert Maps.ids() == ["lorencia"]
    assert {map.width, map.height} == {64, 64}
    assert length(map.tiles) == 64 and Enum.all?(map.tiles, &(String.length(&1) == 64))
    assert @json["sourceType"] == "IMPLEMENTATION" and @json["verified"] == false
  end

  test "collision.bin khớp tiles (D4) và mix mu.maps.build --check sạch", %{map: map} do
    assert map.collision == Collision.from_map(@json)
    assert byte_size(map.collision) == 64 * 64
    out = capture_io(fn -> Mix.Tasks.Mu.Maps.Build.run(["--check"]) end)
    assert out =~ "không đổi"
  end

  test "map khép kín: viền không đi được, ngoài biên không đi được", %{map: map} do
    for i <- 0..63, {x, y} <- [{i, 0}, {i, 63}, {0, i}, {63, i}] do
      refute Maps.walkable?(map, x, y)
    end

    refute Maps.walkable?(map, -1, 5)
    refute Maps.walkable?(map, 64, 5)
    refute Maps.walkable?(map, 5, nil)
  end

  test "safe zone 'town' (KB_CONFIG §3) nằm trong map, toàn ô đi được hoặc NPC", %{map: map} do
    assert [%{id: "town"} = z] = map.safe_zones

    for x <- z.x..(z.x + z.w - 1), y <- z.y..(z.y + z.h - 1) do
      assert Collision.walkable?(map.collision, 64, 64, x, y), "ô #{x},#{y}"
      assert Maps.safe?(map, x, y)
    end

    refute Maps.safe?(map, z.x - 1, z.y)
    refute Maps.safe?(map, z.x + z.w, z.y)
  end

  test "playerSpawn đi được và trong safe zone", %{map: map} do
    {x, y} = map.player_spawn
    assert Maps.walkable?(map, x, y)
    assert %{id: "town"} = Maps.safe_zone_at(map, x, y)
  end

  test "NPC Phase 1 đứng trong safe zone, trên ô địa hình đi được, chặn ô của mình", %{map: map} do
    assert [%{id: "lorencia_potion_merchant", x: x, y: y}] = map.npcs
    assert Collision.walkable?(map.collision, 64, 64, x, y)
    refute Maps.walkable?(map, x, y)
    assert Maps.safe?(map, x, y)
  end

  test "vùng sinh Spider (G16): trong map, ngoài safe zone, đủ ô đi được", %{map: map} do
    assert [%{monster: "spider", count: 10, area: a}] = map.spawns
    cells = for x <- a.x..(a.x + a.w - 1), y <- a.y..(a.y + a.h - 1), do: {x, y}
    assert Enum.all?(cells, fn {x, y} -> x in 0..63 and y in 0..63 end)
    refute Enum.any?(cells, fn {x, y} -> Maps.safe?(map, x, y) end)
    assert Enum.count(cells, fn {x, y} -> Maps.walkable?(map, x, y) end) >= 10 * 10
  end

  test "từ playerSpawn đi tới NPC (ô kề), vùng Spider và mọi ô đi được", %{map: map} do
    seen = reachable(map, map.player_spawn)
    [npc] = map.npcs
    assert MapSet.member?(seen, {npc.x + 1, npc.y})
    %{area: a} = hd(map.spawns)
    assert MapSet.member?(seen, {a.x + 1, a.y + 1})

    all =
      for x <- 0..63, y <- 0..63, Maps.walkable?(map, x, y), into: MapSet.new(), do: {x, y}

    assert MapSet.equal?(seen, all), "có vùng đi được bị cô lập"
  end

  test "client_data không có collision/công thức", %{map: map} do
    data = Maps.client_data(map)
    assert data.id == "lorencia" and data.tiles == map.tiles
    refute Map.has_key?(data, :collision)
  end
end
