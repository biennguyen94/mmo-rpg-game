defmodule Mu.Game.MgTest do
  @moduledoc "P3-M5 (P3-4): Magic Gladiator — skill DK + DW, đòn phép dùng chỉ số phép, không đội mũ."
  use ExUnit.Case, async: true

  alias Mu.Game.{Data, Engine, Inventory}

  defp mg(attrs \\ %{}) do
    Map.merge(
      %{
        class: "MG",
        level: 1,
        experience: 0,
        strength: 26,
        agility: 26,
        vitality: 26,
        energy: 26,
        free_stat_points: 0
      },
      attrs
    )
  end

  test "MG học skill DK (Falling/Twisting Slash, Death Stab) + DW (Energy Ball, Fire Ball, Lightning) theo cấp; không Teleport / Flame / skill Elf" do
    assert Enum.sort(Engine.skills(mg(%{level: 30}))) ==
             Enum.sort(
               ~w(basic_attack falling_slash twisting_slash death_stab energy_ball fire_ball lightning)
             )

    assert Enum.sort(Engine.skills(mg())) == ["basic_attack", "energy_ball"]
    assert :ok = Engine.can_use_skill(mg(%{level: 5}), "falling_slash")
    assert {:error, "REQUIREMENT_NOT_MET"} = Engine.can_use_skill(mg(%{level: 30}), "teleport")
    assert {:error, "REQUIREMENT_NOT_MET"} = Engine.can_use_skill(mg(%{level: 30}), "heal")
    # DK / DW không học được skill của nhau
    refute "energy_ball" in Engine.skills(%{mg(%{level: 30}) | class: "DK"})
    refute "falling_slash" in Engine.skills(%{mg(%{level: 30}) | class: "DW"})
  end

  test "skill phép (magic: true) của MG dùng attackPowerMagic / attackSpeedMagic; skill vật lý dùng số thường" do
    d = Engine.derived(mg(%{strength: 40, energy: 80, agility: 60}), [])
    assert d.attack_max == div(40, 4)
    assert d.attack_max_magic == div(80, 4)
    assert d.attack_speed == div(60, 15)
    assert d.attack_speed_magic == div(60, 20)

    ball = Engine.for_skill(d, Data.skill("energy_ball"))

    assert {ball.attack_max, ball.attack_speed, ball.cooldown_ms} ==
             {d.attack_max_magic, d.attack_speed_magic, d.cooldown_ms_magic}

    assert Engine.for_skill(d, Data.skill("falling_slash")) == d
    # energy_ball cooldownMs null → cooldown theo tốc độ phép
    assert Engine.skill_cooldown_ms(Data.skill("energy_ball"), ball) == d.cooldown_ms_magic

    # DW: không có công thức phép riêng → như cũ
    dw = Engine.derived(%{mg() | class: "DW"}, [])

    assert Engine.for_skill(dw, Data.skill("energy_ball"))
           |> Map.take([:attack_max, :cooldown_ms]) ==
             Map.take(dw, [:attack_max, :cooldown_ms])
  end

  test "MG không đội mũ (INVALID_SLOT); mặc giáp DK / DW (không mũ), cầm kiếm / gậy" do
    c = mg(%{level: 30, strength: 200, agility: 200, vitality: 200, energy: 200})

    for helm <- ~w(helm_t0 pad_helm_t0 bronze_helm_t1 bone_helm_t1) do
      assert {:error, _} = Inventory.can_equip(c, Data.item(helm), 0), helm
    end

    # mũ giả có MG trong classes vẫn bị chặn theo forbiddenSlots
    fake = Map.put(Data.item("helm_t0"), "classes", ["DK", "MG"])
    assert {:error, "INVALID_SLOT"} = Inventory.can_equip(c, fake, 0)

    for {t, slot} <- [
          {"armor_t0", 1},
          {"pad_armor_t0", 1},
          {"bronze_armor_t1", 1},
          {"sword_t0", 5},
          {"staff_t0", 5}
        ] do
      assert :ok = Inventory.can_equip(c, Data.item(t), slot), t
    end

    refute Inventory.can_equip(c, Data.item("bow_t0"), 5) == :ok
  end
end
