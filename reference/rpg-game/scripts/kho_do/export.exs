alias HacLong.Game.{Data, Engine}
items = Map.new(Data.items(), fn {id, it} -> {id, Map.merge(it, %{id: id, sell: Engine.sell_price(id), buy: (id in Data.shop() && it[:price]) || nil})} end)
out = %{
  items: items,
  shop: Data.shop(),
  upgrade: Data.upgrade(),
  classes: Data.classes(),
  realm_monsters: Data.side_monsters() |> Enum.filter(&String.starts_with?(&1.id, "r")) |> Enum.filter(&Map.has_key?(&1, :stat_level)),
  rules: Data.rules(),
  maps: HacLong.World.Maps.ids() |> Enum.map(&HacLong.World.Maps.get/1) |> Enum.filter(&(&1[:realm])) |> Enum.map(&Map.take(&1, [:id, :name, :realm, :min_rebirths, :min_level]))
}
File.write!(System.argv() |> hd, Jason.encode!(out, pretty: false))
