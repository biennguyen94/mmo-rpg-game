defmodule Mu.Phase1ScopeTest do
  @moduledoc "Dữ liệu/config khớp đúng scope Phase 1 (KB_00_RULES §7, JSON scope)."
  use ExUnit.Case, async: true

  alias Mu.Game.{Config, Data}
  alias Mu.World.Maps

  @scope %{
    classes: ["DK"],
    maps: ["lorencia"],
    monsters: ["spider"],
    npcs: ["lorencia_potion_merchant"],
    items:
      ~w(hp_potion_small mp_potion_small sword_t0 shield_t0 helm_t0 armor_t0 pants_t0 gloves_t0 boots_t0 ring_hp_t0),
    skills: ["basic_attack", "twisting_slash"],
    maxLevel: 10
  }

  test "class, map, quái, NPC, item, skill đúng danh sách scope (không thừa, không thiếu)" do
    assert Enum.sort(Map.keys(Data.classes())) == @scope.classes
    assert Maps.ids() == @scope.maps
    assert Map.keys(Data.monsters()) == @scope.monsters
    assert Enum.map(Maps.get("lorencia").npcs, & &1.id) == @scope.npcs
    assert Enum.sort(Map.keys(Data.items())) == Enum.sort(@scope.items)
    assert Enum.sort(Map.keys(Data.skills())) == @scope.skills
    assert Config.get(["game", "maxLevel"]) == @scope.maxLevel
  end

  test "mọi feature ngoài Phase 1 tắt (LATER_VERSION / phase sau)" do
    for {flag, on?} <- Config.get(["features"]) do
      refute on?, "features.#{flag} phải tắt ở Phase 1"
    end

    for f <- ~w(party pvp guild quest wings chaosMachine magicGladiator mail mapPanel) do
      assert Config.get(["features", f]) == false
    end
  end
end
