defmodule Mu.Game.Drops do
  @moduledoc """
  Rơi đồ khi quái chết (`KB_GAME_DESIGN §10`, bảng ở `drops.json` = `KB_CONFIG §4`). Hàm thuần.

  Zen: `random(min, max) × zenMultiplier`. Mỗi group roll `chance × dropMultiplier ×
  itemDropMultiplier`; trúng thì chọn một entry theo weight. Phase 1: đồ +0, không option (G17).
  """

  alias Mu.Game.{Config, Data, Rng}

  @doc "`{%{zen: n, items: [template_id]}, rng}`."
  def roll(rng, monster_id) do
    drop = Config.get(["drop"])
    table = Data.drops(monster_id) || %{"zen" => %{"min" => 0, "max" => 0}, "groups" => []}

    {zen, rng} = Rng.int(rng, table["zen"]["min"], table["zen"]["max"])
    mult = drop["dropMultiplier"] * drop["itemDropMultiplier"]

    {items, rng} =
      Enum.reduce(table["groups"], {[], rng}, fn g, {acc, rng} ->
        {hit?, rng} = Rng.chance(rng, g["chance"] * mult)

        if hit? do
          {item, rng} = Rng.weighted(rng, Enum.map(g["entries"], &{&1["item"], &1["weight"]}))
          {[item | acc], rng}
        else
          {acc, rng}
        end
      end)

    {%{zen: floor(zen * drop["zenMultiplier"]), items: Enum.reverse(items)}, rng}
  end
end
