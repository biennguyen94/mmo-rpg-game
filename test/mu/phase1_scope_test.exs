defmodule Mu.Phase1ScopeTest do
  @moduledoc """
  Dữ liệu/config khớp đúng scope đang mở (KB_00_RULES §7). Phase 1 theo JSON scope; Phase 2
  thêm dần theo milestone (P2-M2: DW, ELF, item t0 của hai class, maxLevel 30; P2-M3: skill theo class; P2-M4: Noria, 13 quái, 4 NPC, đồ t1).
  """
  use ExUnit.Case, async: true

  alias Mu.Game.{Config, Data}
  alias Mu.World.Maps

  @scope %{
    classes: ["DK", "DW", "ELF", "MG"],
    maps: ["lorencia", "noria"],
    monsters:
      ~w(spider budge_dragon bull_fighter hound lich elite_bull_fighter goblin chain_scorpion beetle_monster hunter forest_monster agon stone_golem),
    npcs:
      ~w(lorencia_potion_merchant lorencia_weapon_merchant noria_potion_merchant noria_weapon_merchant) ++
        ~w(lorencia_warehouse noria_warehouse) ++
        ~w(lorencia_quest_master noria_quest_master noria_chaos_goblin),
    items:
      ~w(hp_potion_small mp_potion_small sword_t0 shield_t0 helm_t0 armor_t0 pants_t0 gloves_t0 boots_t0 ring_hp_t0) ++
        ~w(staff_t0 bow_t0) ++
        for(
          set <- ~w(pad vine),
          part <- ~w(helm armor pants gloves boots),
          do: "#{set}_#{part}_t0"
        ) ++
        ~w(sword_t1 staff_t1 bow_t1 shield_t1 hp_potion_medium mp_potion_medium) ++
        for(
          set <- ~w(bronze bone silk),
          part <- ~w(helm armor pants gloves boots),
          do: "#{set}_#{part}_t1"
        ) ++
        ~w(jewel_bless jewel_soul jewel_life) ++
        ~w(jewel_chaos wing_elf wing_heaven wing_satan),
    skills:
      ~w(basic_attack falling_slash twisting_slash death_stab energy_ball fire_ball lightning teleport flame heal triple_shot greater_defense greater_damage)
      |> Enum.sort(),
    maxLevel: 30
  }

  test "class, map, quái, NPC, item, skill đúng danh sách scope (không thừa, không thiếu)" do
    assert Enum.sort(Map.keys(Data.classes())) == @scope.classes
    assert Enum.sort(Maps.ids()) == @scope.maps
    assert Enum.sort(Map.keys(Data.monsters())) == Enum.sort(@scope.monsters)

    assert Enum.sort(for(id <- Maps.ids(), n <- Maps.get(id).npcs, do: n.id)) ==
             Enum.sort(@scope.npcs)

    assert Enum.sort(Map.keys(Data.items())) == Enum.sort(@scope.items)
    assert Enum.sort(Map.keys(Data.skills())) == @scope.skills
    assert Config.get(["game", "maxLevel"]) == @scope.maxLevel
  end

  test "chỉ mail + mapPanel (P2-M6) + party (P3-M4) + magicGladiator (P3-M5) + pvp (P4-M1) + guild (P4-M3) + quest (P6-M2) + chaosMachine / wings (P6-M3/M4) bật; mọi feature khác tắt (LATER_VERSION / phase sau)" do
    on = for {flag, true} <- Config.get(["features"]), do: flag

    assert Enum.sort(on) ==
             ~w(chaosMachine guild magicGladiator mail mapPanel party pvp quest wings)

    for f <- ~w(harmonyJewel guardianJewel) do
      assert Config.get(["features", f]) == false
    end
  end
end
