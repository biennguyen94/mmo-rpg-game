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
