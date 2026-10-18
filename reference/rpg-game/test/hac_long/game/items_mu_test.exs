defmodule HacLong.Game.ItemsMuTest do
  @moduledoc """
  Phase 15b M2 (docs/ITEMS_PHASE15B.md): đồ Item.txt trong game — 8 ô, đồ theo lớp, yêu cầu chỉ số,
  đồ khởi đầu, rơi đồ, cửa hàng, đổi đồ cũ của nhân vật khi nạp.
  """
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Gear, Rng}

  setup do
    on_exit(&Rng.clear/0)
    :ok
  end

  defp player(cls, attrs \\ %{}) do
    {:ok, p} = Engine.new_player("Thử", cls)
    Map.merge(p, attrs)
  end

  defp worn(p), do: Map.new(p.equip, fn {s, id} -> {s, id && Gear.find(p, id).base} end)

  test "nhân vật mới mặc đồ khởi đầu đúng lớp; Đấu Sĩ không có mũ" do
    # đồ khởi đầu là món riêng (`uid`), so theo loại đồ
    assert %{weapon: "item_1_0", helm: "item_7_5", armor: "item_8_5", shield: nil} =
             worn(player("dk"))

    assert worn(player("dw")).weapon == "item_5_0"
    assert worn(player("elf")).weapon == "item_4_0"
    mg = worn(player("mg"))
    assert mg.weapon == "item_1_0" and mg.armor == "item_8_5" and mg.helm == nil

    # 11 ô (thêm 2 nhẫn, dây chuyền ở Phase 15c); thủ = tổng mọi ô phòng thủ (5 món bậc 1, mỗi món 1)
    assert map_size(player("dk").equip) == 11
    bare = %{player("dk") | equip: Engine.empty_equip() |> Map.put(:weapon, "item_1_0")}
    assert Engine.derived(player("dk")).def - Engine.derived(bare).def == 5
  end

  test "mặc đồ: đúng lớp, đủ cấp, đủ chỉ số (× req_mult); tháo được mũ / quần / găng / giày" do
    p = player("dw", %{level: 30}) |> Engine.add_item("item_0_3") |> Engine.add_item("item_5_3")

    assert {%{ok: false, msg: "Đao Katana không dành cho Phù Thủy."}, _} =
             Engine.equip(p, "item_0_3")

    assert {%{ok: true}, p} = Engine.equip(p, "item_5_3")
    assert worn(p).weapon == "item_5_3"

    # Cung Bạc (bậc 7): AGI 35 > 25 của Tiên Nữ mới tạo
    e = player("elf", %{level: 30}) |> Engine.add_item("item_4_5")
    assert {%{ok: false, msg: "Cung Bạc cần Nhanh nhẹn 35."}, _} = Engine.equip(e, "item_4_5")
    e = %{e | stats: %{e.stats | agi: 35}}
    assert {%{ok: true}, _} = Engine.equip(e, "item_4_5")

    assert {%{ok: false, msg: "Cần cấp 27."}, _} =
             Engine.equip(%{e | level: 10}, "item_4_5")

    {%{ok: true}, q} = Engine.unequip(player("dk"), "helm")
    assert q.equip.helm == nil and Enum.map(Gear.bag(q), & &1.base) == ["item_7_5"]

    # B-11: vũ khí, giáp cũng tháo được; tay không / không giáp thì chỉ còn phần theo chỉ số
    p = player("dk")
    {%{ok: true}, q} = Engine.unequip(p, "armor")
    assert q.equip.armor == nil and Enum.any?(Gear.bag(q), &(&1.uid == p.equip.armor))
    assert Engine.derived(q).def < Engine.derived(p).def
    {%{ok: true}, q} = Engine.unequip(q, "weapon")
    assert q.equip.weapon == nil and Enum.any?(Gear.bag(q), &(&1.uid == p.equip.weapon))
    assert Engine.derived(q).atk < Engine.derived(p).atk and Engine.derived(q).atk > 0
    assert %{weapon: nil, armor: nil} = Engine.look(q)
    assert {%{ok: false}, _} = Engine.unequip(q, "weapon")
    {%{ok: true}, q} = Engine.equip(q, p.equip.weapon)
    assert q.equip.weapon == p.equip.weapon
  end

  test "cửa hàng: đồ cũ thôi bán, đồ mới có giá theo ô / bậc; mua đồ lớp khác bị từ chối" do
    shop = Data.shop()
    refute "dagger" in shop or "breastplate" in shop
    assert "item_1_1" in shop and "item_8_1" in shop
    # bậc 1 (giá 0) là đồ khởi đầu, không bán
    refute "item_1_0" in shop
    assert Data.stock(["dagger", "leather"]) -- shop == []

    p = player("elf", %{gold: 10_000, level: 30})
    assert {%{ok: false, msg: "Rìu Tay không dành cho Tiên Nữ."}, _} = Engine.buy(p, "item_1_1")
    assert {%{ok: true}, _} = Engine.buy(p, "item_4_8")
  end

  test "rơi đồ: không ra đồ cũ; theo lớp thì chỉ ra đồ lớp đó; \"set\" ra một món của bộ giáp" do
    for _ <- 1..40 do
      g = Gear.roll(30)
      refute Data.legacy?(g.base)
      g = Gear.roll(30, Gear.weights(), nil, "elf")
      assert Engine.class_ok?(Data.item(g.base), "elf")
      g = Gear.roll(30, Gear.weights(), "set", "mg")
      it = Data.item(g.base)
      assert it.slot in ~w(armor pants gloves boots) and "mg" in it.classes
    end
  end

  test "nạp nhân vật cũ: đồ cũ đổi sang đồ mới cùng ô / bậc / đúng lớp, giữ +N, khóa, chỉ số cộng" do
    old =
      player("elf", %{
        equip: %{weapon: "#A", armor: "chain", shield: "round", wing: nil},
        gear: [
          %{uid: "#A", base: "greatsword", rarity: 2, bonus: %{agi: 3}, locked: true},
          %{uid: "#B", base: "waraxe", rarity: 0, bonus: %{}}
        ],
        inv: %{"dagger" => 2, "potion_s" => 1},
        upgrades: %{"#A" => 7, "chain" => 3},
        storage: %{inv: %{"lamellar" => 1, "herb" => 2}, extra: 0}
      })

    p = Engine.migrate_items(old)
    # Đại Kiếm (vũ khí bậc 6) → Cung Hổ; Rìu Song Nhận (bậc 7) → Cung Bạc
    assert [%{uid: "#A", base: "item_4_4", locked: true, bonus: %{agi: 3}}, %{base: "item_4_5"}] =
             p.gear

    # Giáp Xích (bậc 3) → Giáp Gió; Khiên Tròn → Khiên Nhỏ; ô trống nhận đồ khởi đầu
    assert %{weapon: "#A", armor: "item_8_12", shield: "item_6_0", helm: "item_7_10"} = p.equip
    assert p.inv == %{"item_4_8" => 2, "potion_s" => 1}
    assert p.upgrades == %{"#A" => 7, "item_8_12" => 3}
    # Giáp Lá (bậc 5) trong Tủ Đồ → Giáp Hộ Vệ
    assert p.storage.inv == %{"item_8_14" => 1, "herb" => 2}
    # chạy lại không đổi gì; nhân vật mới không bị đụng
    assert Engine.migrate_items(p) == p
    fresh = player("dk")
    assert Engine.migrate_items(fresh) == fresh
  end

  test "vỡ đồ khi ép: vũ khí / giáp về đồ khởi đầu của lớp" do
    assert Data.starters("dw") == %{
             weapon: "item_5_0",
             helm: "item_7_2",
             armor: "item_8_2",
             pants: "item_9_2",
             gloves: "item_10_2",
             boots: "item_11_2"
           }
  end

  test "mọi vũ khí / giáp / khiên đều có hình trên nhân vật (bậc cao mượn hình bậc cao nhất của đồ cũ)" do
    items = Data.items() |> then(&if(is_map(&1), do: Map.values(&1), else: &1))

    missing =
      for it <- items,
          it[:slot] in ~w(weapon armor shield),
          !it[:legacy],
          !is_binary(it[:doll]),
          do: it.name

    assert missing == []

    p = %{elem(Engine.new_player("Thử", "dk"), 1) | level: 50}

    {id, armor} =
      Enum.find(Data.items(), fn {_, it} ->
        it[:slot] == "armor" and it[:tier] == 8 and "dk" in (it[:classes] || [])
      end)

    assert armor[:doll] == "body/bplate_metal1"
    assert Engine.look(%{p | equip: %{p.equip | armor: id}}).armor == "body/bplate_metal1"
  end
end
