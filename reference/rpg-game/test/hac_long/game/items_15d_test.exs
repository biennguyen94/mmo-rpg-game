defmodule HacLong.Game.Items15dTest do
  @moduledoc """
  Phase 15d (docs/ITEMS_PHASE15B.md §7): dòng phụ May mắn / Kỹ năng trên đồ rơi.
  """
  use ExUnit.Case, async: true

  alias HacLong.Game.{Engine, Gear, Rng}

  setup do
    on_exit(&Rng.clear/0)
    :ok
  end

  @ls Gear.luck_skill_rules()

  defp player(cls, attrs) do
    {:ok, p} = Engine.new_player("Thử", cls)
    Map.merge(p, attrs)
  end

  defp wear(p, g) do
    {p, :kept} = Gear.add(p, g)
    {%{ok: true}, p} = Engine.equip(p, g.uid)
    p
  end

  defp gear(base, extra), do: Map.merge(Gear.new(base, 1, %{}), extra)

  test "đồ rơi: May mắn theo loại quái, Kỹ năng chỉ ở vũ khí; đấu trường / trùm thế giới không bốc" do
    sword = Gear.new("item_0_3", 1, %{})
    armor = Gear.new("item_8_5", 1, %{})

    # bốc 0.0 (< mọi tỉ lệ) thì có cả hai dòng
    Rng.put_sequence([0.0, 0.0])
    assert %{luck: true, skill: true} = Gear.luck_skill(sword, %{boss: false})

    # giáp chỉ bốc một lần (May mắn), không bao giờ có Kỹ năng
    Rng.put_sequence([0.0, 0.0])
    g = Gear.luck_skill(armor, %{boss: false})
    assert g.luck and not Map.has_key?(g, :skill)

    # bốc cao hơn tỉ lệ thì không có gì
    Rng.put_sequence([0.99, 0.99])
    assert Gear.luck_skill(sword, %{boss: false}) == sword

    assert Gear.luck_chance(%{boss: true}) == @ls.luck_chance.boss
    assert Gear.luck_chance(%{elite: true, boss: false}) == @ls.luck_chance.elite
    assert Gear.luck_skill(sword, %{pvp: true}) == sword
    assert Gear.luck_skill(sword, %{world: true}) == sword
    assert Gear.luck_skill(nil, %{}) == nil
  end

  test "vũ khí May mắn cộng chí mạng; giáp May mắn không cộng" do
    p = player("dk", %{level: 20})
    plain = Engine.derived(wear(p, gear("item_0_3", %{})))
    lucky = Engine.derived(wear(p, gear("item_0_3", %{luck: true})))
    assert_in_delta lucky.crit, plain.crit + @ls.luck_crit, 1.0e-9

    armored = Engine.derived(wear(p, gear("item_8_5", %{luck: true})))
    base = Engine.derived(p)
    assert_in_delta armored.crit, base.crit, 1.0e-9
  end

  test "Kỹ năng: chiêu gây thêm sát thương, đánh thường thì không" do
    p = player("dk", %{level: 20})
    assert Engine.derived(wear(p, gear("item_0_3", %{}))).skillDmg == 0
    assert Engine.derived(wear(p, gear("item_0_3", %{skill: true}))).skillDmg == @ls.skill_dmg
  end

  test "ép ngọc: May mắn cộng tỉ lệ +7..+11, tối đa luck_max_rate; +6 vẫn 100%" do
    it = %{price: 1000, level: 10, luck: true}
    plain = Map.delete(it, :luck)

    for lv <- 6..10 do
      base = Engine.upgrade_cost(plain, lv).rate
      lucky = Engine.upgrade_cost(it, lv).rate

      if base >= 1,
        do: assert(lucky == 1.0),
        else: assert(lucky == min(@ls.luck_max_rate, Float.round(base + @ls.luck_upgrade, 3)))
    end

    # hiện ở tooltip / thợ rèn qua Gear.item (resolve mang theo luck)
    p = player("dk", %{level: 20}) |> wear(gear("item_0_3", %{luck: true}))
    assert Gear.item(p, p.equip.weapon).luck
  end

  test "giá bán nhân price_mult mỗi dòng; lưu / nạp giữ dòng" do
    plain = Gear.new("item_0_3", 1, %{})
    both = Map.merge(plain, %{luck: true, skill: true})
    assert Gear.price(both) == round(Gear.price(plain) * @ls.price_mult * @ls.price_mult)

    [loaded] = both |> Jason.encode!() |> Jason.decode!() |> List.wrap() |> Gear.load()
    assert loaded.luck and loaded.skill

    [none] = plain |> Jason.encode!() |> Jason.decode!() |> List.wrap() |> Gear.load()
    refute Map.has_key?(none, :luck) or Map.has_key?(none, :skill)
  end
end
