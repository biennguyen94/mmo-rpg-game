defmodule Mu.Game.InventoryTest do
  use ExUnit.Case, async: true

  alias Mu.Game.{Data, Inventory}

  @dk %{class: "DK", level: 1, strength: 28, agility: 20, vitality: 25, energy: 10}

  defp it(id, tid, qty, slot, loc \\ "INVENTORY"),
    do: %{id: id, template_id: tid, quantity: qty, slot: slot, location: loc}

  test "plan_add: gộp vào stack slot thấp nhất còn chỗ, thừa tạo stack mới ở ô trống thấp nhất (G20)" do
    items = [
      it("a", "hp_potion_small", 98, 3),
      it("b", "hp_potion_small", 50, 1),
      it("s", "sword_t0", 1, 0)
    ]

    assert {:ok, [{:merge, "b", 49}, {:merge, "a", 1}, {:new, 2, 5}]} =
             Inventory.plan_add(items, "hp_potion_small", 55)

    assert {:ok, [{:new, 1, 1}]} = Inventory.plan_add([it("s", "sword_t0", 1, 0)], "sword_t0", 1)
    assert {:ok, [{:new, 0, 99}, {:new, 1, 1}]} = Inventory.plan_add([], "hp_potion_small", 100)
  end

  test "túi 64 ô: đầy thì INVENTORY_FULL; đồ stack vẫn gộp được khi đầy" do
    full = for s <- 0..63, do: it("i#{s}", "sword_t0", 1, s)
    assert {:error, "INVENTORY_FULL"} = Inventory.plan_add(full, "sword_t0", 1)
    full = List.replace_at(full, 10, it("p", "hp_potion_small", 10, 10))
    assert {:ok, [{:merge, "p", 5}]} = Inventory.plan_add(full, "hp_potion_small", 5)
    assert {:error, "INVENTORY_FULL"} = Inventory.plan_add(full, "hp_potion_small", 90)
    assert Inventory.first_free_slot(full) == nil
  end

  test "KB §6: DK cấp 1 (STR 28 / AGI 20) mặc được ít nhất 1 template mỗi slot" do
    templates = Map.values(Data.items())

    for slot <- [0, 1, 2, 3, 4, 5, 6, 8, 9] do
      assert Enum.any?(templates, &(Inventory.can_equip(@dk, &1, slot) == :ok)), "slot #{slot}"
    end
  end

  test "equip: sai slot, WING khóa, class, level, stat" do
    sword = Data.item("sword_t0")
    ring = Data.item("ring_hp_t0")
    assert :ok = Inventory.can_equip(@dk, sword, 5)
    assert {:error, "INVALID_SLOT"} = Inventory.can_equip(@dk, sword, 6)
    assert {:error, "INVALID_SLOT"} = Inventory.can_equip(@dk, Data.item("hp_potion_small"), 5)
    assert :ok = Inventory.can_equip(@dk, ring, 8)
    assert :ok = Inventory.can_equip(@dk, ring, 9)
    assert Inventory.equip_slots(%{"slot" => "WING"}) == []

    assert {:error, "REQUIREMENT_NOT_MET"} =
             Inventory.can_equip(%{@dk | strength: 27}, Data.item("armor_t0"), 1)

    assert {:error, "REQUIREMENT_NOT_MET"} = Inventory.can_equip(%{@dk | class: "XX"}, sword, 5)
    assert {:error, "REQUIREMENT_NOT_MET"} = Inventory.can_equip(%{@dk | level: 0}, ring, 8)
  end

  test "đếm potion theo potionType trên mọi stack" do
    items = [
      it("a", "hp_potion_small", 3, 0),
      it("b", "hp_potion_small", 4, 5),
      it("c", "mp_potion_small", 2, 1),
      it("d", "sword_t0", 1, 2)
    ]

    assert Inventory.potion_counts(items) == %{"HP" => 7, "MP" => 2}
    assert Inventory.potion_counts([]) == %{"HP" => 0, "MP" => 0}
  end
end
