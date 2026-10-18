alias HacLong.Game.{Data, Engine}
items = Map.new(Data.items(), fn {id, it} -> {id, Map.merge(it, %{id: id, sell: Engine.sell_price(id), buy: (id in Data.shop() && it[:price]) || nil})} end)
out = %{
  items: items,
  shop: Data.shop(),
  upgrade: Data.upgrade(),
  classes: Data.classes(),
  realm_monsters: Data.side_monsters() |> Enum.filter(&String.starts_with?(&1.id, "r")) |> Enum.filter(&Map.has_key?(&1, :stat_level)),
  rules: Data.rules(),
  chaos: Data.chaos(),
  recipes: Data.recipes(),
  # Hồ Long Vương: cấp vào (DECISIONS "Long Vương")
  lake: Map.take(HacLong.World.Maps.get("long_vuong_lake"), [:name, :min_level]),
  library: HacLong.Library.get(),
  # lịch mặc định trong config/config.exs (máy chủ có thể đổi bằng biến môi trường WORLD_BOSS_*)
  world_boss: Map.new(Config.Reader.read!("config/config.exs", env: :prod)[:hac_long][:world_boss]),
  tower_rows: for(f <- [1, 5, 10, 20, 30, 40, 50, 60, 80, 100, 150], do: Map.put(HacLong.Game.Tower.floor_reward(f), :floor, f)),
  jewels: Data.jewels(),
  pets: Data.pets(),
  festivals: Data.events(),
  maps: HacLong.World.Maps.ids() |> Enum.map(&HacLong.World.Maps.get/1) |> Enum.filter(&(&1[:realm])) |> Enum.map(&(&1 |> Map.take([:id, :name, :realm, :min_rebirths, :min_level]) |> Map.put(:monsters, Enum.map(&1.spawns, fn s -> s.monster end))))
}
File.write!(System.argv() |> hd, Jason.encode!(out, pretty: false))
