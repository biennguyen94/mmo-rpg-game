defmodule HacLong.RealmsTest do
  @moduledoc "Phase 6 (B-30): 10 vùng đất chuyển sinh, quái cấp 52–150, khóa theo số lần chuyển sinh, rơi quý hơn, tháp 61+."
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Gear, Tower}
  alias HacLong.World
  alias HacLong.World.Maps

  @r Data.rules().realms

  defp hero(level, cs) do
    {:ok, p} = Engine.new_player("Cs", "dk")

    Map.merge(p, %{
      level: level,
      rebirths: cs,
      gold: 1_000_000,
      pos: %{map: "village", x: 1, y: 1}
    })
  end

  test "10 vùng: cần chuyển sinh 1…10, 3 quái + 1 chúa tể, cấp quái 52…150" do
    for k <- 1..10 do
      m = Maps.get("realm_" <> String.pad_leading("#{k}", 2, "0"))
      assert m.realm == k and m.min_rebirths == k and m.min_level == @r.min_level
      assert m.waystone
      specs = Enum.map(m.spawns, &Data.side_monster(&1.monster))
      assert length(specs) == 4
      assert Enum.max_by(specs, & &1.level).level == 50 + 10 * k
      assert Enum.all?(specs, &(&1.stat_level == @r.stat_level and &1.rich >= k))
    end
  end

  test "vào được khi đủ chuyển sinh và cấp" do
    r1 = Maps.get("realm_01")
    r3 = Maps.get("realm_03")
    refute World.can_travel?(hero(50, 0), r1)
    refute World.can_travel?(hero(@r.min_level - 1, 1), r1)
    assert World.can_travel?(hero(@r.min_level, 1), r1)
    refute World.can_travel?(hero(50, 2), r3)
    assert World.can_travel?(hero(50, 3), r3)
    assert {%{ok: false, msg: msg}, _} = World.travel(hero(50, 0), 1, "realm_01")
    assert msg =~ "chuyển sinh 1 lần"
  end

  test "chỉ số quái tính ở cấp 50 × hệ số; cấp hiện cao cho vàng; rơi đồ quý hơn" do
    spec = Data.side_monster("r10_ancient_lich")
    m = Engine.make_monster(spec, false)
    base = Engine.make_monster(%{id: "x", name: "x", level: @r.stat_level}, false)
    assert m.level == 150
    assert m.maxHp == round(base.maxHp * spec.mult)
    # công nhân hệ số riêng, nhẹ hơn máu (phòng thủ người chơi còn ý nghĩa)
    assert m.atk == round(base.atk * spec.atk_mult) and spec.atk_mult < spec.mult
    assert m.element == "light"

    plain = %{boss: false}
    rich = %{boss: false, rich: 5}
    assert Gear.drop_chance(rich) > Gear.drop_chance(plain)

    # chỉ nhân tỉ lệ ra đồ, chất lượng món đã rơi giữ tỉ lệ gốc (không nhân hai tầng)
    assert Gear.exc_chance(rich) == Gear.exc_chance(plain)
    assert Gear.luck_chance(rich) == Gear.luck_chance(plain)
  end

  test "tháp: tầng 1–60 vùng cũ, 61–160 vùng chuyển sinh, sau đó quay vòng có tiền tố" do
    f61 = Tower.build(61, 1)
    assert Enum.all?(f61.monsters, &String.starts_with?(&1.kind, "r1_"))
    assert f61.theme == Maps.get("realm_01").floor

    f160 = Tower.build(160, 1)
    boss = Enum.find(f160.monsters, & &1.elite)
    assert boss.kind == "r10_ancient_lich"
    assert Tower.battle_monster(boss).element == "light"

    f161 = Tower.build(161, 1)
    assert Enum.all?(f161.monsters, &(&1.name =~ "Cổ Đại"))
  end
end
