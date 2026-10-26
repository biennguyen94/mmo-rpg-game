defmodule HacLong.Game.TwoHandTest do
  @moduledoc "Vũ khí 1 tay / 2 tay (DECISIONS B-41): dữ liệu từ Item.txt, 2 tay không cầm khiên."
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Gear, ItemBuild}

  defp player(cls, attrs \\ %{}) do
    {:ok, p} = Engine.new_player("Thử", cls)
    # đủ chỉ số mặc mọi món bậc thấp
    Map.merge(%{p | stats: Map.new(p.stats, fn {k, _} -> {k, 999} end)}, attrs)
  end

  defp uid(p, base), do: Enum.find(Gear.bag(p), &(&1.base == base)).uid
  defp worn(p, slot), do: p.equip[slot] && Gear.find(p, p.equip[slot]).base

  # một vũ khí 1 tay / 2 tay bậc thấp nhất của lớp
  defp weapon(cls, hands) do
    Data.items()
    |> Enum.filter(fn {_, it} ->
      it.slot == "weapon" and it[:hands] == hands and cls in (it[:classes] || []) and
        (it[:level] || 1) <= 30
    end)
    |> Enum.min_by(fn {_, it} -> it[:tier] end)
    |> elem(0)
  end

  defp shield,
    do:
      Data.items()
      |> Enum.find(fn {_, it} -> it.slot == "shield" and it[:tier] == 1 end)
      |> elem(0)

  test "dữ liệu: cung / nỏ và món rộng 2 ô là 2 tay; 2 tay công không thấp hơn 1 tay cùng bậc" do
    assert Data.item("item_4_24").hands == 2
    assert Data.item("item_0_9").hands == 2
    assert Data.item("item_0_19").hands == 1
    assert Data.item("item_5_11").hands == 1

    for {_, it} <- Data.items(),
        it.slot == "weapon",
        it[:sourceType] == "MU_ITEM_TXT",
        do: assert(it.hands in [1, 2])

    # công của bậc là công 1 tay: món 2 tay cùng bậc, cùng lớp không yếu hơn món 1 tay
    for {_, a} <- Data.items(),
        a.slot == "weapon" and a[:hands] == 2,
        {_, b} <- Data.items(),
        b.slot == "weapon" and b[:hands] == 1 and b[:tier] == a[:tier] and !b[:alt],
        Enum.any?(a.classes, &(&1 in b.classes)) do
      assert a.atk >= b.atk, "#{a.name} (2 tay) yếu hơn #{b.name}"
    end
  end

  test "mặc vũ khí 2 tay: khiên đang cầm về túi; 2 tay thì không cầm khiên; 1 tay cầm lại được" do
    two = weapon("dk", 2)
    one = weapon("dk", 1)

    p =
      player("dk", %{level: 30})
      |> Engine.add_item(shield())
      |> Engine.add_item(two)
      |> Engine.add_item(one)

    {%{ok: true}, p} = Engine.equip(p, uid(p, shield()))
    assert worn(p, :shield) == shield()

    {r, p} = Engine.equip(p, uid(p, two))
    assert r.ok and r.msg =~ "Khiên về túi"
    assert worn(p, :weapon) == two and p.equip.shield == nil
    assert Enum.any?(Gear.bag(p), &(&1.base == shield()))

    {r, p} = Engine.equip(p, uid(p, shield()))
    refute r.ok
    assert r.msg =~ "2 tay"
    assert p.equip.shield == nil

    {%{ok: true}, p} = Engine.equip(p, uid(p, one))
    {%{ok: true}, p} = Engine.equip(p, uid(p, shield()))
    assert worn(p, :weapon) == one and worn(p, :shield) == shield()
  end

  test "Tiên Nữ cầm cung không cầm khiên" do
    p = player("elf") |> Engine.add_item(shield())
    assert Data.item(worn(p, :weapon)).hands == 2
    {r, p} = Engine.equip(p, uid(p, shield()))
    refute r.ok
    assert p.equip.shield == nil
  end

  test "nạp nhân vật cũ đang cầm 2 tay + khiên: khiên về túi" do
    two = weapon("dk", 2)
    p = player("dk", %{level: 30}) |> Engine.add_item(shield()) |> Engine.add_item(two)
    p = %{p | equip: %{p.equip | weapon: uid(p, two), shield: uid(p, shield())}}
    p = Engine.two_hand_fix(p)
    assert p.equip.shield == nil and Enum.any?(Gear.bag(p), &(&1.base == shield()))
    assert Engine.two_hand_fix(p) == p
  end

  test "cầm 2 vũ khí (B-42): Kiếm Sĩ / Phù Thủy / Đấu Sĩ cầm vũ khí 1 tay ở tay trái, công cộng thêm × mult" do
    one = weapon("dk", 1)

    p =
      player("dk", %{level: 30})
      |> Engine.add_item(one)
      |> Engine.add_item(one)
      |> Engine.add_item(shield())

    [a, b] = for g <- Gear.bag(p), g.base == one, do: g.uid
    {%{ok: true}, p} = Engine.equip(p, a)
    {%{ok: true}, p} = Engine.equip(p, uid(p, shield()))
    with_shield = Engine.derived(p)

    {r, p} = Engine.equip(p, b, "left")
    assert r.ok
    assert worn(p, :weapon) == one and worn(p, :shield) == one
    assert Engine.left_weapon(p).name == Data.item(one).name
    d = Engine.derived(p)
    k = Engine.dual_rules().mult

    # tay trái là vũ khí: không còn phòng thủ khiên, công cộng thêm công vũ khí × k (trước nhân phần trăm)
    assert d.def < with_shield.def
    assert d.atk > with_shield.atk
    assert_in_delta d.atk - with_shield.atk, k * Data.item(one).atk, 2

    # mặc vũ khí 2 tay: vũ khí tay trái về túi
    two = weapon("dk", 2)
    p = Engine.add_item(p, two)
    {r, p} = Engine.equip(p, uid(p, two))
    assert r.ok and r.msg =~ "Vũ khí tay trái về túi"
    assert p.equip.shield == nil
  end

  test "cầm 2 vũ khí: Tiên Nữ không được; vũ khí 2 tay không vào tay trái; chưa cầm tay phải thì không được" do
    p = player("elf", %{level: 30}) |> Engine.add_item(weapon("elf", 1))
    {r, _} = Engine.equip(p, uid(p, weapon("elf", 1)), "left")
    refute r.ok

    two = weapon("dk", 2)
    p = player("dk", %{level: 30}) |> Engine.add_item(two)
    {r, _} = Engine.equip(p, uid(p, two), "left")
    refute r.ok and r.msg =~ "2 tay"

    one = weapon("dk", 1)
    p = player("dk", %{level: 30}) |> Engine.add_item(one)
    p = %{p | equip: %{p.equip | weapon: nil}}
    {r, _} = Engine.equip(p, uid(p, one), "left")
    refute r.ok

    assert Engine.dual_class?("dw") and Engine.dual_class?("mg") and not Engine.dual_class?("elf")
  end

  test "cầm 2 vũ khí: gậy chỉ cặp với gậy; kiếm cặp rìu được; đổi tay phải sang loại khác thì tay trái về túi" do
    staff = "item_5_11"
    sword = "item_0_28"

    axe =
      Data.items()
      |> Enum.find(fn {_, it} ->
        it.slot == "weapon" and String.starts_with?(it[:ref] || "", "1/") and it[:hands] == 1 and
          "mg" in (it[:classes] || [])
      end)
      |> elem(0)

    p =
      player("mg", %{level: 50})
      |> Engine.add_item(staff)
      |> Engine.add_item(sword)
      |> Engine.add_item(axe)

    {%{ok: true}, p} = Engine.equip(p, uid(p, sword))

    {r, p} = Engine.equip(p, uid(p, staff), "left")
    refute r.ok
    assert r.msg =~ "Gậy chỉ cầm cùng gậy"

    {r, p} = Engine.equip(p, uid(p, axe), "left")
    assert r.ok and worn(p, :shield) == axe

    # tay phải đổi sang gậy: rìu tay trái về túi
    {r, p} = Engine.equip(p, uid(p, staff))
    assert r.ok and r.msg =~ "gậy chỉ cầm cùng gậy"
    assert worn(p, :weapon) == staff and p.equip.shield == nil
  end

  test "cầm 2 vũ khí: dòng Excellent % của vũ khí tay trái không cộng" do
    one = weapon("mg", 1)
    p = player("mg", %{level: 30})
    p = Engine.add_item(p, one) |> Engine.add_item(one)
    [a, b] = for g <- Gear.bag(p), g.base == one, do: g.uid

    p = %{
      p
      | gear:
          Enum.map(
            Gear.list(p),
            &if(&1.uid == b, do: Map.put(&1, :exc, ~w(atk_pct heal_kill)), else: &1)
          )
    }

    {%{ok: true}, p} = Engine.equip(p, a)
    {%{ok: true}, p} = Engine.equip(p, b, "left")
    exc = Gear.exc_stats(p)
    assert exc.atk_pct == 0 and exc.heal_kill > 0
  end

  test "sách phép Summoner đã bỏ (B-43): không còn trong đồ; dữ liệu cũ đổi sang gậy 1 tay của Phù Thủy" do
    for id <- ~w(item_5_21 item_5_22 item_5_23), do: refute(Map.has_key?(Data.items(), id))
    assert Data.item("item_5_22").name == Data.item("item_5_5").name
    assert Data.legacy?("item_5_21") and Data.replacement("item_5_23", "dw") == "item_5_6"

    p = player("dw", %{level: 30})
    g = %{uid: "#BOOK0001", base: "item_5_22"}
    p = %{p | gear: Gear.list(p) ++ [g], equip: %{p.equip | shield: "#BOOK0001"}}
    p = Engine.migrate_items(p)
    assert Gear.find(p, "#BOOK0001").base == "item_5_5"
    assert p.equip.shield == "#BOOK0001"
  end

  test "ItemBuild: hệ số 2 tay so với 1 tay cùng cấp; gậy theo sức mạnh phép; kẹp min / max, nhân scale" do
    d = fn ref, x, lvl, atk, magic ->
      {ref, %{"ref" => ref, "cells" => [x, 3], "itemLvl" => lvl, "atk" => atk, "magic" => magic}}
    end

    drafts =
      Map.new([
        d.("0/1", 1, 30, 30, 0),
        d.("1/1", 1, 34, 34, 0),
        d.("0/9", 2, 32, 48, 0),
        d.("4/1", 2, 30, 20, 0),
        d.("5/1", 1, 30, 15, 40),
        d.("5/2", 2, 30, 15, 50)
      ])

    pick = fn cfg -> %{"stats" => %{"two_hand" => cfg}} end
    base = pick.(%{"window" => 12})
    assert ItemBuild.hands(drafts["0/1"]) == 1
    assert ItemBuild.hands(drafts["4/1"]) == 2
    assert ItemBuild.two_hand_mult(drafts["0/1"], drafts, base) == 1.0
    # 48 / trung bình(30, 34) = 1.5
    assert ItemBuild.two_hand_mult(drafts["0/9"], drafts, base) == 1.5

    assert ItemBuild.two_hand_mult(drafts["0/9"], drafts, pick.(%{"window" => 12, "max" => 1.3})) ==
             1.3

    assert ItemBuild.two_hand_mult(
             drafts["0/9"],
             drafts,
             pick.(%{"window" => 12, "scale" => 1.1})
           ) == 1.65

    # cung yếu hơn 1 tay cùng cấp: không dưới `min` (mặc định 1)
    assert ItemBuild.two_hand_mult(drafts["4/1"], drafts, base) == 1.0
    # gậy: 50 / 40 sức mạnh phép
    assert ItemBuild.two_hand_mult(drafts["5/2"], drafts, base) == 1.25
    # không có `two_hand` trong bảng chọn: không nhân
    assert ItemBuild.two_hand_mult(drafts["0/9"], drafts, %{}) == 1.0
  end
end
