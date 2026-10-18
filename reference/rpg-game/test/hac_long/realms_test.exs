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

  test "10 vùng × 5 bản đồ: cần chuyển sinh 1…10, quái mạnh dần theo bản đồ, chúa tể ở bản đồ cuối" do
    n = @r.maps_per_realm

    for k <- 1..10 do
      id = "realm_" <> String.pad_leading("#{k}", 2, "0")
      maps = Enum.map(1..n, &Maps.get(if &1 == 1, do: id, else: "#{id}_#{&1}"))

      assert Enum.all?(
               maps,
               &(&1.realm == k and &1.min_rebirths == k and &1.min_level == @r.min_level)
             )

      assert hd(maps).waystone

      # bản đồ 1 nối bản đồ 2, …, bản đồ n−1 nối bản đồ n
      for {a, b} <- Enum.zip(maps, tl(maps)) do
        assert Enum.any?(a.portals, &(&1.to == b.id))
        assert Enum.any?(b.portals, &(&1.to == a.id))
      end

      specs = Enum.map(maps, fn m -> Enum.map(m.spawns, &Data.side_monster(&1.monster)) end)
      assert Enum.map(specs, &length/1) == List.duplicate(3, n - 1) ++ [4]
      lord = Enum.find(List.last(specs), & &1[:lord])
      assert lord.level == 50 + 10 * k and Engine.realm_lord(k).id == lord.id
      normal = Enum.map(specs, &Enum.reject(&1, fn s -> s[:lord] end))

      # càng sâu càng mạnh, nhưng bản đồ cuối vẫn yếu hơn bản đồ 1 vùng sau
      mults = Enum.map(normal, &hd(&1).mult)
      assert mults == Enum.sort(Enum.uniq(mults))
      assert List.last(mults) < 1 + @r.mult_per_realm * (k + 1)
      assert Enum.all?(List.flatten(specs), &(&1.stat_level == @r.stat_level and &1.rich >= k))
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

    # kinh nghiệm ở cấp 50 × xp_mult (không theo cấp hiện 150)
    assert m.xp == round(Engine.base_xp(@r.stat_level) * spec.xp_mult)
    normal = Data.side_monster("r1_fire_elemental")
    assert normal.xp_mult == 1 + @r.xp_mult_per_realm
    assert Engine.make_monster(normal, false).xp < 2 * base.xp

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
