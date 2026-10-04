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
    # P6-M4: features.wings bật → slot 7 mở
    assert Inventory.equip_slots(%{"slot" => "WING"}) == [7]

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

  describe "P2-M1: move_item / split / drop" do
    test "plan_move: ô trống = chuyển, món khác = hoán đổi, cùng stack = gộp, cùng ô = noop" do
      items = [
        it("s", "sword_t0", 1, 0),
        it("p", "hp_potion_small", 30, 1),
        it("q", "hp_potion_small", 90, 2),
        it("f", "hp_potion_small", 99, 3),
        it("e", "armor_t0", 1, 1, "EQUIPMENT")
      ]

      assert {:ok, {:move, "s", 10}} = Inventory.plan_move(items, "s", 10)
      assert {:ok, {:swap, "s", 1, "p", 0}} = Inventory.plan_move(items, "s", 1)
      # gộp tối đa maxStack (99): 9 cái sang, 21 ở lại
      assert {:ok, {:merge, "p", "q", 9}} = Inventory.plan_move(items, "p", 2)
      # stack đích đầy: hoán đổi
      assert {:ok, {:swap, "p", 3, "f", 1}} = Inventory.plan_move(items, "p", 3)
      assert {:ok, :noop} = Inventory.plan_move(items, "s", 0)
    end

    test "plan_move: lỗi" do
      items = [it("s", "sword_t0", 1, 0), it("e", "armor_t0", 1, 1, "EQUIPMENT")]
      assert {:error, "NOT_OWNER"} = Inventory.plan_move(items, "x", 1)
      assert {:error, "INVALID_SLOT"} = Inventory.plan_move(items, "e", 2)
      assert {:error, "INVALID_SLOT"} = Inventory.plan_move(items, "s", 64)
      assert {:error, "INVALID_SLOT"} = Inventory.plan_move(items, "s", -1)
      assert {:error, "INVALID_SLOT"} = Inventory.plan_move(items, "s", "1")
    end

    test "plan_split: chỉ stack, 1 <= số < đang có, ô đích trống" do
      items = [it("p", "hp_potion_small", 10, 0), it("s", "sword_t0", 1, 1)]
      assert {:ok, 5} = Inventory.plan_split(items, "p", 4, 5)
      assert {:ok, 2} = Inventory.plan_split(items, "p", 9, nil)
      assert {:error, "INVALID_TARGET"} = Inventory.plan_split(items, "p", 10, 5)
      assert {:error, "INVALID_TARGET"} = Inventory.plan_split(items, "p", 0, 5)
      assert {:error, "INVALID_TARGET"} = Inventory.plan_split(items, "p", "2", 5)
      assert {:error, "INVALID_TARGET"} = Inventory.plan_split(items, "s", 1, 5)
      assert {:error, "INVALID_SLOT"} = Inventory.plan_split(items, "p", 2, 1)

      full = [
        it("p", "hp_potion_small", 10, 0) | for(n <- 1..63, do: it("i#{n}", "sword_t0", 1, n))
      ]

      assert {:error, "INVENTORY_FULL"} = Inventory.plan_split(full, "p", 2, nil)
    end

    test "droppable: chỉ đồ trong túi" do
      items = [it("s", "sword_t0", 1, 0), it("e", "armor_t0", 1, 1, "EQUIPMENT")]
      assert {:ok, %{id: "s"}} = Inventory.droppable(items, "s")
      assert {:error, "INVALID_SLOT"} = Inventory.droppable(items, "e")
      assert {:error, "NOT_OWNER"} = Inventory.droppable(items, "x")
    end
  end
end
