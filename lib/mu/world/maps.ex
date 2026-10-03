defmodule Mu.World.Maps do
  @moduledoc """
  Bản đồ ô vuông (`KB_TECHNICAL §8`), đọc lúc biên dịch từ `priv/maps/<id>.json` và
  `priv/maps/<id>.collision.bin`. Học từ `HacLong.World.Maps` (đọc lúc biên dịch, grid,
  `walkable?`); định dạng mới: `safeZones`, `spawns`, `npcs`, `playerSpawn`, collision riêng.

  Map JSON: `id, name, width, height, collision, legend, walkable, safeZones [{id,x,y,w,h}],
  pvpZones, playerSpawn {x,y}, spawns [{monster, count, area {x,y,w,h}}], portals,
  npcs [{id,x,y}], tiles` (+ `sourceType/version/verified`).

  NPC đứng yên và chặn ô của mình. Người chơi không chặn nhau.
  """

  alias Mu.World.Collision

  @dir Path.expand("../../../priv/maps", __DIR__)
  @files Path.wildcard(Path.join(@dir, "*.json"))
  for f <- @files, do: @external_resource(f)

  rect = fn r -> %{x: r["x"], y: r["y"], w: r["w"], h: r["h"]} end

  @maps (for f <- @files, into: %{} do
           m = f |> File.read!() |> Jason.decode!()

           for key <- ~w(sourceType version verified),
               not Map.has_key?(m, key),
               do: raise("#{f}: thiếu #{key} (KB_00_RULES §2)")

           bin_path = Path.join(@dir, m["collision"])
           @external_resource bin_path

           collision =
             if File.exists?(bin_path) do
               File.read!(bin_path)
             else
               IO.warn("#{bin_path} chưa có: chạy `mix mu.maps.build`")
               Collision.from_map(m)
             end

           byte_size(collision) == m["width"] * m["height"] ||
             raise "#{bin_path}: kích thước khác #{m["width"]}×#{m["height"]}"

           map = %{
             id: m["id"],
             name: m["name"],
             width: m["width"],
             height: m["height"],
             collision: collision,
             tiles: m["tiles"],
             legend: m["legend"],
             safe_zones: Enum.map(m["safeZones"], &Map.put(rect.(&1), :id, &1["id"])),
             player_spawn: {m["playerSpawn"]["x"], m["playerSpawn"]["y"]},
             spawns:
               Enum.map(
                 m["spawns"],
                 &%{monster: &1["monster"], count: &1["count"], area: rect.(&1["area"])}
               ),
             npcs: Enum.map(m["npcs"], &%{id: &1["id"], x: &1["x"], y: &1["y"]})
           }

           {map.id, map}
         end)

  def ids, do: Map.keys(@maps)
  def get(id), do: Map.get(@maps, id)

  @doc "Ô có đi được không: trong biên, địa hình đi được, không có NPC đứng."
  def walkable?(map, x, y) do
    Collision.walkable?(map.collision, map.width, map.height, x, y) and npc_at(map, x, y) == nil
  end

  def npc_at(map, x, y), do: Enum.find(map.npcs, &(&1.x == x and &1.y == y))

  @doc "Ô thuộc safe zone nào (`nil` nếu không)."
  def safe_zone_at(map, x, y) do
    Enum.find(map.safe_zones, fn z ->
      x >= z.x and x < z.x + z.w and y >= z.y and y < z.y + z.h
    end)
  end

  def safe?(map, x, y), do: safe_zone_at(map, x, y) != nil

  @doc "Dữ liệu gửi client lúc join để vẽ (không có công thức gameplay)."
  def client_data(map) do
    %{
      id: map.id,
      name: map.name,
      width: map.width,
      height: map.height,
      tiles: map.tiles,
      legend: map.legend,
      safeZones: Enum.map(map.safe_zones, &Map.take(&1, [:id, :x, :y, :w, :h])),
      npcs: map.npcs
    }
  end
end
