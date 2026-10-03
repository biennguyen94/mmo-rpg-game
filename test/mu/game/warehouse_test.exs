defmodule Mu.Game.WarehouseTest do
  @moduledoc "P3-M3: kho 120 ô dùng chung tài khoản — luật thuần + transaction DB, audit."
  use Mu.DataCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Mu.Game.{Character, Inventory, ItemAudit, ItemLocation, Items}

  defp it(id, tid, loc, slot, q \\ 1),
    do: %{id: id, template_id: tid, location: loc, slot: slot, quantity: q}

  describe "plan_transfer/4 (thuần)" do
    setup do
      items = [it("s", "sword_t0", "INVENTORY", 0), it("p", "hp_potion_small", "INVENTORY", 1, 5)]
      items = items ++ [it("e", "helm_t0", "EQUIPMENT", 0)]
      wh = [it("w", "shield_t0", "WAREHOUSE", 3), it("wp", "hp_potion_small", "WAREHOUSE", 7, 98)]
      %{items: items, wh: wh}
    end

    test "gửi / rút / hoán đổi / gộp / cùng ô", %{items: i, wh: w} do
      assert {:ok, {:move, "s", {"WAREHOUSE", 0}}} =
               Inventory.plan_transfer(i, w, "s", {"WAREHOUSE", 0})

      assert {:ok, {:move, "w", {"INVENTORY", 9}}} =
               Inventory.plan_transfer(i, w, "w", {"INVENTORY", 9})

      assert {:ok, {:swap, "s", {"WAREHOUSE", 3}, "w", {"INVENTORY", 0}}} =
               Inventory.plan_transfer(i, w, "s", {"WAREHOUSE", 3})

      # stack kho còn 1 chỗ (maxStack 99): chuyển 1, 4 ở lại túi
      assert {:ok, {:merge, "p", "wp", 1}} = Inventory.plan_transfer(i, w, "p", {"WAREHOUSE", 7})
      assert {:ok, :noop} = Inventory.plan_transfer(i, w, "w", {"WAREHOUSE", 3})

      assert {:ok, {:move, "w", {"WAREHOUSE", 119}}} =
               Inventory.plan_transfer(i, w, "w", {"WAREHOUSE", 119})
    end

    test "sai: đồ đang mặc, ô ngoài 0–119, không phải của mình", %{items: i, wh: w} do
      assert {:error, "INVALID_SLOT"} = Inventory.plan_transfer(i, w, "e", {"WAREHOUSE", 0})
      assert {:error, "INVALID_SLOT"} = Inventory.plan_transfer(i, w, "s", {"WAREHOUSE", 120})
      assert {:error, "INVALID_SLOT"} = Inventory.plan_transfer(i, w, "w", {"INVENTORY", 64})
      assert {:error, "INVALID_SLOT"} = Inventory.plan_transfer(i, w, "w", {"EQUIPMENT", 0})
      assert {:error, "NOT_OWNER"} = Inventory.plan_transfer(i, w, "x", {"WAREHOUSE", 0})
      assert Inventory.warehouse_slots() == 120
    end
  end

  describe "transfer/4 (DB)" do
    setup do
      {a, c} = create_character()

      {:ok, _} =
        Items.pickup(c.id, %{serial: Mu.Ulid.generate(), template_id: "sword_t0"}, "test")

      {:ok, _} = Items.buy(c.id, "hp_potion_small", 0 + 10, 0, "test")
      items = Items.load(c.id)
      sword = Enum.find(items, &(&1.template_id == "sword_t0"))
      pot = Enum.find(items, &(&1.template_id == "hp_potion_small"))
      %{a: a, c: c, sword: sword, pot: pot}
    end

    test "gửi vào kho: row thuộc tài khoản (không thuộc nhân vật), audit WAREHOUSE_IN", ctx do
      %{a: a, c: c, sword: sword} = ctx
      assert {:ok, res} = Items.transfer(c.id, a.id, sword.id, {"WAREHOUSE", 5})
      assert [%{id: id, slot: 5, location: "WAREHOUSE"}] = res.warehouse
      assert id == sword.id
      refute Enum.any?(res.items, &(&1.id == sword.id))

      loc = Repo.get!(ItemLocation, sword.id)
      assert {loc.account_id, loc.character_id} == {a.id, nil}

      assert %{action: "WAREHOUSE_IN", from_owner: "char:" <> _, to_owner: "acc:" <> aid} =
               Repo.one(
                 from(x in ItemAudit,
                   where: x.item_id == ^sword.id,
                   order_by: [desc: x.id],
                   limit: 1
                 )
               )

      assert aid == a.id

      # rút ra ô 20
      assert {:ok, res} = Items.transfer(c.id, a.id, sword.id, {"INVENTORY", 20})
      assert res.warehouse == []
      assert %{slot: 20, location: "INVENTORY"} = Enum.find(res.items, &(&1.id == sword.id))
    end

    test "gộp potion vào stack trong kho; hoán đổi túi ↔ kho", ctx do
      %{a: a, c: c, sword: sword, pot: pot} = ctx
      {:ok, _} = Items.split(c.id, pot.id, 4, nil)
      [p1, p2] = Items.load(c.id) |> Enum.filter(&(&1.template_id == "hp_potion_small"))
      {:ok, _} = Items.transfer(c.id, a.id, p1.id, {"WAREHOUSE", 0})
      {:ok, res} = Items.transfer(c.id, a.id, p2.id, {"WAREHOUSE", 0})
      assert [%{quantity: 10, slot: 0}] = res.warehouse

      # kiếm (túi) thả lên ô potion trong kho → hoán đổi: potion về ô cũ của kiếm
      {:ok, res} = Items.transfer(c.id, a.id, sword.id, {"WAREHOUSE", 0})
      assert [%{template_id: "sword_t0", slot: 0}] = res.warehouse

      assert %{template_id: "hp_potion_small", quantity: 10} =
               Enum.find(res.items, &(&1.slot == sword.slot))
    end

    test "kho dùng chung mọi nhân vật của tài khoản", %{a: a, c: c, sword: sword} do
      {:ok, _} = Items.transfer(c.id, a.id, sword.id, {"WAREHOUSE", 1})
      # nhân vật thứ hai của cùng tài khoản (Phase 3 cho tối đa 4 — P3-M5)
      name = "Kho#{rem(System.unique_integer([:positive]), 99_999)}"

      c2 =
        Repo.insert!(%Character{
          account_id: a.id,
          name: name,
          class: c.class,
          map_id: c.map_id,
          position_x: c.position_x,
          position_y: c.position_y,
          strength: c.strength,
          agility: c.agility,
          vitality: c.vitality,
          energy: c.energy,
          hp_current: c.hp_current,
          mana_current: c.mana_current
        })

      assert [%{id: id}] = Items.load_warehouse(a.id)
      assert {:ok, res} = Items.transfer(c2.id, a.id, id, {"INVENTORY", 0})

      assert [%{template_id: "sword_t0"}] =
               res.items |> Enum.filter(&(&1.location == "INVENTORY"))

      assert Items.load(c.id) |> Enum.all?(&(&1.id != id))
    end

    test "tài khoản khác không lấy được đồ trong kho", %{a: a, c: c, sword: sword} do
      {:ok, _} = Items.transfer(c.id, a.id, sword.id, {"WAREHOUSE", 1})
      {a2, c2} = create_character()
      assert {:error, "NOT_OWNER"} = Items.transfer(c2.id, a2.id, sword.id, {"INVENTORY", 0})
    end
  end
end
