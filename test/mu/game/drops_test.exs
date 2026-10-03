defmodule Mu.Game.DropsTest do
  use ExUnit.Case, async: true

  alias Mu.Game.{Drops, Rng}

  test "Spider: zen 5–15, tỉ lệ nhóm ≈ 15% potion, 6% trang bị (KB_CONFIG §4), lặp lại theo seed" do
    {rolls, _} = Enum.map_reduce(1..20_000, Rng.new(123), fn _, r -> Drops.roll(r, "spider") end)
    {again, _} = Enum.map_reduce(1..50, Rng.new(123), fn _, r -> Drops.roll(r, "spider") end)
    assert Enum.take(rolls, 50) == again

    assert Enum.all?(rolls, &(&1.zen in 5..15))
    items = Enum.flat_map(rolls, & &1.items)
    potions = Enum.count(items, &(&1 in ["hp_potion_small", "mp_potion_small"]))
    equip = length(items) - potions
    assert_in_delta potions / 20_000, 0.15, 0.01
    assert_in_delta equip / 20_000, 0.06, 0.006
    hp = Enum.count(items, &(&1 == "hp_potion_small"))
    assert_in_delta hp / potions, 0.8, 0.03
    # P2-M4: thêm đồ t0 của DW/ELF → 2 potion + 20 món
    assert items |> Enum.uniq() |> length() == 22
  end

  test "P2-M4: mọi quái có bảng drop, Zen đúng bảng quái, đồ t1 chỉ rơi từ quái cấp ≥ 10" do
    for {id, m} <- Mu.Game.Data.monsters() do
      d = Mu.Game.Data.drops(id)
      assert d, id
      assert {d["zen"]["min"], d["zen"]["max"]} == {m["zenMin"], m["zenMax"]}
      items = for g <- d["groups"], e <- g["entries"], do: e["item"]
      assert Enum.any?(items, &String.ends_with?(&1, "_t1")) == m["level"] >= 10, id
    end

    {rolls, _} = Enum.map_reduce(1..5_000, Rng.new(9), fn _, r -> Drops.roll(r, "goblin") end)
    items = Enum.flat_map(rolls, & &1.items)
    assert "hp_potion_medium" in items
    assert Enum.all?(rolls, &(&1.zen in 30..90))
  end

  test "quái không có bảng: không rơi gì" do
    assert {%{zen: 0, items: []}, _} = Drops.roll(Rng.new(1), "khong_co")
  end
end
