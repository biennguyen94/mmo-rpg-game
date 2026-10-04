defmodule Mu.Game.ItemsTest do
  use Mu.DataCase, async: false

  alias Mu.Game.{Character, ItemAudit, Items}
  alias Mu.Ulid

  @npc "lorencia_potion_merchant"

  setup do
    {_, c} = create_character()
    %{c: c}
  end

  defp give_zen(c, zen),
    do: Repo.update_all(from(x in Character, where: x.id == ^c.id), set: [zen: zen])

  defp ground(tid), do: %{serial: Ulid.generate(), template_id: tid}

  # món vừa nhặt (tìm theo serial; potion gộp stack thì trả stack đó)
  defp pick(c, tid) do
    g = ground(tid)
    {:ok, %{items: items}} = Items.pickup(c.id, g, "ground:lorencia")
    Enum.find(items, &(&1.serial == g.serial)) || Enum.find(items, &(&1.template_id == tid))
  end

  defp audits(item_id),
    do:
      Repo.all(
        from a in ItemAudit, where: a.item_id == ^item_id, order_by: a.id, select: a.action
      )

  test "nhặt: serial dưới đất thành serial của item, ghi audit PICKUP", %{c: c} do
    g = ground("sword_t0")
    {:ok, %{items: [it]}} = Items.pickup(c.id, g, "ground:lorencia")

    assert {it.serial, it.template_id, it.location, it.slot, it.durability} ==
             {g.serial, "sword_t0", "INVENTORY", 0, 22}

    assert audits(it.id) == ["PICKUP"]
    # nhặt lại cùng serial (dupe) bị chặn bởi unique serial
    assert {:error, "NOT_OWNER"} = Items.pickup(c.id, g, "ground:lorencia")
  end

  test "nhặt potion gộp vào stack có sẵn (G20)", %{c: c} do
    a = pick(c, "hp_potion_small")
    {:ok, %{items: items}} = Items.pickup(c.id, ground("hp_potion_small"), "ground:lorencia")
    assert [%{id: id, quantity: 2}] = items
    assert id == a.id
    assert audits(a.id) == ["PICKUP", "PICKUP_MERGE"]
  end

  test "mua: trừ Zen, gộp stack, thiếu Zen, túi đầy", %{c: c} do
    give_zen(c, 1000)

    assert {:ok, %{zen: 700, items: [%{quantity: 3}], version: v1}} =
             Items.buy(c.id, "hp_potion_small", 3, 100, @npc)

    assert {:ok, %{zen: 0, items: [%{quantity: 10}], version: v2}} =
             Items.buy(c.id, "hp_potion_small", 7, 100, @npc)

    assert v2 == v1 + 1
    assert {:error, "NOT_ENOUGH_ZEN"} = Items.buy(c.id, "hp_potion_small", 1, 100, @npc)
    assert Repo.get!(Character, c.id).zen == 0

    give_zen(c, 1_000_000)
    for _ <- 1..63, do: pick(c, "sword_t0")

    # 64 ô đã đủ (1 stack potion + 63 kiếm): potion vẫn gộp được, kiếm thì không
    assert {:ok, _} = Items.buy(c.id, "hp_potion_small", 1, 100, @npc)
    assert {:error, "INVENTORY_FULL"} = Items.buy(c.id, "hp_potion_small", 99, 100, @npc)
    assert {:error, "INVENTORY_FULL"} = Items.pickup(c.id, ground("sword_t0"), "ground:lorencia")
  end

  test "mặc / tháo / đổi chỗ", %{c: c} do
    s1 = pick(c, "sword_t0")
    s2 = pick(c, "sword_t0")
    {:ok, %{items: items}} = Items.equip(c, s1.id, 5)

    assert Enum.find(items, &(&1.id == s1.id)) |> Map.take([:location, :slot]) == %{
             location: "EQUIPMENT",
             slot: 5
           }

    # mặc kiếm 2 vào ô 5: kiếm 1 về ô túi của kiếm 2
    {:ok, %{items: items}} = Items.equip(c, s2.id, 5)

    assert Enum.find(items, &(&1.id == s1.id)) |> Map.take([:location, :slot]) == %{
             location: "INVENTORY",
             slot: s2.slot
           }

    assert Enum.find(items, &(&1.id == s2.id)).location == "EQUIPMENT"

    assert {:error, "INVALID_SLOT"} = Items.equip(c, s1.id, 6)
    assert {:error, "INVALID_SLOT"} = Items.equip(c, s2.id, 5)
    assert {:error, "INVALID_SLOT"} = Items.equip(c, s1.id, "5")
    assert {:error, "NOT_OWNER"} = Items.equip(c, Ecto.UUID.generate(), 5)
    weak = %{c | strength: 20}
    assert {:error, "REQUIREMENT_NOT_MET"} = Items.equip(weak, s1.id, 5)

    {:ok, %{items: items}} = Items.unequip(c.id, 5, 7)

    assert Enum.find(items, &(&1.id == s2.id)) |> Map.take([:location, :slot]) == %{
             location: "INVENTORY",
             slot: 7
           }

    assert {:error, "INVALID_SLOT"} = Items.unequip(c.id, 5, nil)
    assert audits(s2.id) == ["PICKUP", "EQUIP", "UNEQUIP"]
  end

  test "tháo: ô đích đang có đồ/ngoài túi → INVALID_SLOT; túi đầy → INVENTORY_FULL", %{c: c} do
    s = pick(c, "sword_t0")
    {:ok, _} = Items.equip(c, s.id, 5)
    other = pick(c, "shield_t0")
    assert {:error, "INVALID_SLOT"} = Items.unequip(c.id, 5, other.slot)
    assert {:error, "INVALID_SLOT"} = Items.unequip(c.id, 5, 64)
    for _ <- 1..63, do: pick(c, "helm_t0")
    assert {:error, "INVENTORY_FULL"} = Items.unequip(c.id, 5, nil)
  end

  test "dùng: trừ 1, hết thì xóa stack; đồ đang mặc không dùng được", %{c: c} do
    give_zen(c, 200)
    {:ok, %{items: [p]}} = Items.buy(c.id, "hp_potion_small", 2, 100, @npc)
    assert {:ok, %{items: [%{quantity: 1}]}} = Items.consume(c.id, p.id)
    assert {:ok, %{items: []}} = Items.consume(c.id, p.id)
    assert {:error, "NOT_OWNER"} = Items.consume(c.id, p.id)
    assert Repo.get(Mu.Game.Item, p.id) == nil
    assert audits(p.id) == ["BUY", "USE", "USE"]
  end

  test "bán: cộng Zen, cả stack hoặc một phần; đồ đang mặc/không phải của mình bị chặn", %{c: c} do
    give_zen(c, 500)
    {:ok, %{items: [p]}} = Items.buy(c.id, "hp_potion_small", 5, 100, @npc)
    assert {:ok, %{zen: 100, items: [%{quantity: 3}]}} = Items.sell(c.id, p.id, 2, 50, @npc)
    assert {:ok, %{zen: 250, items: []}} = Items.sell(c.id, p.id, nil, 50, @npc)

    s = pick(c, "sword_t0")
    {:ok, _} = Items.equip(c, s.id, 5)
    assert {:error, "INVALID_SLOT"} = Items.sell(c.id, s.id, nil, 500, @npc)
    {_, other} = create_character()
    assert {:error, "NOT_OWNER"} = Items.sell(other.id, s.id, nil, 500, @npc)

    assert {:error, "INVALID_TARGET"} =
             Items.unequip(c.id, 5, nil) |> then(fn _ -> Items.sell(c.id, s.id, 2, 500, @npc) end)
  end

  describe "chống nhân đôi khi hai tiến trình thao tác cùng một item" do
    test "10 tiến trình cùng bán một món: chỉ 1 thành công, Zen cộng 1 lần", %{c: c} do
      s = pick(c, "sword_t0")

      results =
        1..10
        |> Enum.map(fn _ -> Task.async(fn -> Items.sell(c.id, s.id, nil, 500, @npc) end) end)
        |> Enum.map(&Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1

      assert Enum.all?(
               results -- Enum.filter(results, &match?({:ok, _}, &1)),
               &(&1 == {:error, "NOT_OWNER"})
             )

      assert Repo.get!(Character, c.id).zen == 500
      assert audits(s.id) == ["PICKUP", "SELL"]
    end

    test "mặc và bán cùng lúc: không bao giờ vừa mặc vừa nhận Zen", %{c: c} do
      for _ <- 1..10 do
        s = pick(c, "sword_t0")
        give_zen(c, 0)
        t1 = Task.async(fn -> Items.equip(c, s.id, 5) end)
        t2 = Task.async(fn -> Items.sell(c.id, s.id, nil, 500, @npc) end)
        [r1, r2] = Enum.map([t1, t2], &Task.await(&1, 10_000))
        sold? = match?({:ok, _}, r2)
        equipped? = match?({:ok, _}, r1) and Repo.get(Mu.Game.Item, s.id) != nil
        assert sold? != equipped?
        assert Repo.get!(Character, c.id).zen == if(sold?, do: 500, else: 0)
        if equipped?, do: Items.unequip(c.id, 5, nil) && Items.sell(c.id, s.id, nil, 0, @npc)
      end
    end

    test "hai nhân vật cùng nhặt một serial: chỉ một người có", %{c: c} do
      {_, c2} = create_character()
      g = ground("ring_hp_t0")

      results =
        [c, c2]
        |> Enum.map(fn ch -> Task.async(fn -> Items.pickup(ch.id, g, "ground:lorencia") end) end)
        |> Enum.map(&Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Repo.aggregate(from(i in Mu.Game.Item, where: i.serial == ^g.serial), :count) == 1
    end

    test "nhiều tiến trình cùng mua: không vượt Zen, không trùng ô", %{c: c} do
      give_zen(c, 500)

      results =
        1..10
        |> Enum.map(fn _ -> Task.async(fn -> Items.buy(c.id, "sword_t0", 1, 100, @npc) end) end)
        |> Enum.map(&Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, _}, &1)) == 5
      assert Repo.get!(Character, c.id).zen == 0
      slots = Items.load(c.id) |> Enum.map(& &1.slot)
      assert Enum.sort(slots) == [0, 1, 2, 3, 4]
    end
  end

  test "dọn orphan: item không có location bị xóa và ghi audit" do
    orphan = Repo.insert!(%Mu.Game.Item{serial: Ulid.generate(), template_id: "sword_t0"})
    assert {:ok, n} = Items.delete_orphans()
    assert n >= 1
    assert Repo.get(Mu.Game.Item, orphan.id) == nil
    assert audits(orphan.id) == ["ORPHAN_DELETE"]
  end

  describe "P2-M1" do
    test "move_item: chuyển, hoán đổi (không vướng unique slot), gộp stack", %{c: c} do
      sword = pick(c, "sword_t0")
      armor = pick(c, "armor_t0")
      assert {sword.slot, armor.slot} == {0, 1}

      {:ok, %{items: items}} = Items.move_item(c.id, sword.id, 7)
      assert Enum.find(items, &(&1.id == sword.id)).slot == 7

      {:ok, %{items: items}} = Items.move_item(c.id, sword.id, 1)

      assert {Enum.find(items, &(&1.id == sword.id)).slot,
              Enum.find(items, &(&1.id == armor.id)).slot} == {1, 7}

      assert audits(sword.id) == ["PICKUP", "MOVE", "MOVE"]

      {:ok, _} = give_zen(c, 10_000) && Items.buy(c.id, "hp_potion_small", 5, 1, @npc)
      {:ok, %{items: items}} = Items.split(c.id, potion_id(c), 2, 20)
      assert [%{quantity: 3, slot: 0}, %{quantity: 2, slot: 20}] = potions(items)

      [a, b] = potions(items)
      {:ok, %{items: items}} = Items.move_item(c.id, b.id, a.slot)
      assert [%{id: id, quantity: 5, slot: 0}] = potions(items)
      assert id == a.id
      assert audits(b.id) == ["SPLIT", "MERGE"]
    end

    test "drop: xóa khỏi DB, trả dropped giữ serial/thuộc tính; nhặt lại nhận y nguyên", %{c: c} do
      sword = pick(c, "sword_t0")

      Repo.update_all(from(i in Mu.Game.Item, where: i.id == ^sword.id),
        set: [item_level: 3, luck: true]
      )

      assert {:ok, %{items: [], dropped: d}} = Items.drop(c.id, sword.id, "ground:lorencia")

      assert %{
               serial: serial,
               template_id: "sword_t0",
               quantity: 1,
               attrs: %{item_level: 3, luck: true}
             } = d

      assert serial == sword.serial
      assert audits(sword.id) == ["PICKUP", "DROP"]
      assert {:error, "NOT_OWNER"} = Items.drop(c.id, sword.id, "ground:lorencia")

      {:ok, %{items: [it]}} = Items.pickup(c.id, d, "ground:lorencia")
      assert {it.serial, it.item_level, it.luck} == {serial, 3, true}
    end

    test "drop stack potion rồi nhặt lại đủ số lượng", %{c: c} do
      {:ok, _} = give_zen(c, 10_000) && Items.buy(c.id, "hp_potion_small", 7, 1, @npc)
      {:ok, %{dropped: d}} = Items.drop(c.id, potion_id(c), "ground:lorencia")
      assert d.quantity == 7
      {:ok, %{items: [%{quantity: 7}]}} = Items.pickup(c.id, d, "ground:lorencia")
    end
  end

  defp potions(items),
    do: items |> Enum.filter(&(&1.template_id == "hp_potion_small")) |> Enum.sort_by(& &1.slot)

  defp potion_id(c), do: hd(potions(Items.load(c.id))).id

  describe "P2-M2" do
    test "cung hai tay: không mặc cung khi có khiên, không mặc khiên khi cầm cung" do
      {_, elf} = create_character(nil, "ELF")
      elf = %{elf | strength: 30}
      [bow] = Items.load(elf.id)
      {:ok, _} = Items.unequip(elf.id, 5, nil)
      shield = pick(elf, "shield_t0")
      {:ok, _} = Items.equip(elf, shield.id, 6)
      assert {:error, "INVALID_SLOT"} = Items.equip(elf, bow.id, 5)
      {:ok, _} = Items.unequip(elf.id, 6, nil)
      {:ok, _} = Items.equip(elf, bow.id, 5)
      assert {:error, "INVALID_SLOT"} = Items.equip(elf, shield.id, 6)
      # kiếm một tay + khiên vẫn được
      sword = pick(elf, "sword_t0")
      {:ok, _} = Items.equip(elf, sword.id, 5)
      assert {:ok, _} = Items.equip(elf, shield.id, 6)
    end

    test "đồ khởi đầu có audit STARTER; class sai không mặc được đồ class khác", %{c: dk} do
      {_, dw} = create_character(nil, "DW")
      [staff] = Items.load(dw.id)
      assert audits(staff.id) == ["STARTER"]
      pad = pick(dk, "pad_armor_t0")
      assert {:error, "REQUIREMENT_NOT_MET"} = Items.equip(dk, pad.id, 1)
      vine = pick(dw, "vine_armor_t0")
      assert {:error, "REQUIREMENT_NOT_MET"} = Items.equip(dw, vine.id, 1)
      pad2 = pick(dw, "pad_armor_t0")
      assert {:ok, _} = Items.equip(dw, pad2.id, 1)
    end
  end
end
