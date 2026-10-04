defmodule HacLong.Game.ItemDataTest do
  @moduledoc "Công cụ dữ liệu đồ: đọc Item.txt (`ItemTxt`) và bộ hình theo cấp +N (`ItemIcons`)."
  use ExUnit.Case, async: true

  alias HacLong.Game.{ItemIcons, ItemTxt}

  @sample Path.expand("../../fixtures/Item.sample.txt", __DIR__)

  test "đọc Item.txt: tab đệm không cố định, dấu cách, chú thích cuối dòng, cảnh báo dòng hỏng" do
    {items, warns} = @sample |> File.read!() |> ItemTxt.parse()
    assert Enum.map(items, &{&1.group, &1.index}) == [{0, 0}, {0, 1}, {7, 5}, {12, 0}, {14, 1}]
    assert [{_, msg, "Hong"}] = warns
    assert msg =~ "không phải số"

    [kiem, kiem2, mu, canh, binh] = items
    assert kiem.values["dmgMin"] == 4 and kiem.values["dmgMax"] == 9 and kiem.values["str"] == 60
    assert kiem.x == 1 and kiem.y == 2
    assert kiem.classTier == %{"DW" => 1, "DK" => 1, "ELF" => 1, "MG" => 1, "DL" => 1, "SUM" => 0}
    assert canh.values["def"] == 10 and canh.values["reqLvl"] == 180 and canh.classTier == nil
    assert binh.values == %{"valor" => 10, "itemLvl" => 10}

    # sang dạng đồ Hắc Long
    k = ItemTxt.to_item(kiem)

    assert %{id: "item_0_0", ref: "0/0", slot: "weapon", atkMin: 4, atkMax: 9, atk: 7, level: 3} =
             k

    assert k.req == %{"str" => 60} and Enum.sort(k.classes) == ~w(dk dw elf mg)
    # cờ 2 (bậc tiến hóa) không tính
    assert ItemTxt.to_item(kiem2).classes == ["dk"]
    m = ItemTxt.to_item(mu)
    assert %{slot: "helm", def: 5} = m
    assert Enum.sort(m.classes) == ~w(dk elf)
    assert %{slot: "wing", def: 10, level: 180} = ItemTxt.to_item(canh)
    assert ItemTxt.to_item(binh) == nil
  end

  test "bảng hình theo cấp: chọn mức lớn nhất ≤ cấp nâng; file có số cấp ưu tiên hơn file trơn" do
    files = ~w(item_0_1.png item_0_1_0.png item_0_1_5.png item_0_1_10.png item_0_1_9_e.png
               broadsword_7.png potion_s.png ghi_chu.txt)

    {map, skipped} = ItemIcons.build(files)
    assert skipped == ["ghi_chu.txt"]
    assert map["0/1"]["0"] == "items/item_0_1_0.png"
    assert map["0/1"]["9e"] == "items/item_0_1_9_e.png"
    assert ItemIcons.pick(map, "0/1", 0) == "items/item_0_1_0.png"
    assert ItemIcons.pick(map, "0/1", 7) == "items/item_0_1_5.png"
    assert ItemIcons.pick(map, "0/1", 11) == "items/item_0_1_10.png"
    # chỉ có hình từ +7: dưới +7 dùng icon cũ
    assert ItemIcons.pick(map, "custom/broadsword", 3) == nil
    assert ItemIcons.pick(map, "custom/broadsword", 9) == "items/broadsword_7.png"
    assert ItemIcons.pick(map, "custom/potion_s", 0) == "items/potion_s.png"
    assert ItemIcons.pick(map, "9/9", 0) == nil
  end
end
