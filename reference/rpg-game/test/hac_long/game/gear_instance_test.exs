defmodule HacLong.Game.GearInstanceTest do
  @moduledoc "Mọi trang bị là món riêng trong túi trang bị (DECISIONS \"Trang bị luôn là món riêng\")."
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Gear}

  defp hero(cls \\ "dk") do
    {:ok, p} = Engine.new_player("Riêng", cls)
    %{p | gold: 1_000_000, level: 20}
  end

  test "nhân vật mới: đồ khởi đầu đang mặc là món riêng, túi trang bị trống" do
    p = hero()
    worn = p.equip |> Map.values() |> Enum.reject(&is_nil/1)
    assert worn != [] and Enum.all?(worn, &Gear.instance?/1)
    assert Gear.bag(p) == [] and Enum.all?(Map.keys(p.inv), &(not Engine.gear_item?(&1)))
  end

  test "mua / nhận trang bị: mỗi món một món riêng 0 dòng, không xếp chồng; bình vẫn xếp chồng" do
    id =
      Enum.find(Data.shop(), &(Engine.gear_item?(&1) and Engine.class_ok?(Data.item(&1), "dk")))

    {%{ok: true}, p} = Engine.buy(hero(), id, 2)
    assert [%{base: ^id}, %{base: ^id}] = Gear.bag(p)
    assert Enum.all?(Gear.bag(p), &(Gear.resolve(&1).kind in [nil, ""]))
    refute Map.has_key?(p.inv, id)

    p = Engine.add_item(p, "potion_s", 4)
    assert p.inv["potion_s"] == 7
  end

  test "túi trang bị đầy thì không mua được; quà / phần thưởng dư gửi Hộp thư" do
    id =
      Enum.find(Data.shop(), &(Engine.gear_item?(&1) and Engine.class_ok?(Data.item(&1), "dk")))

    p = Engine.add_item(hero(), id, Gear.max_bag())
    assert length(Gear.bag(p)) == Gear.max_bag()

    assert {%{ok: false, msg: "Túi trang bị đầy" <> _}, ^p} = Engine.buy(p, id)

    q = Engine.add_item(p, id)
    assert length(Gear.bag(q)) == Gear.max_bag()
    assert [%{base: ^id}] = q.mail_out
  end

  test "dữ liệu cũ: trang bị xếp chồng (đang mặc, túi, Tủ Đồ) thành món riêng, dư gửi Hộp thư, không mất món" do
    p = hero()
    weapon = Data.starters("dk").weapon

    old =
      %{p | gear: [], equip: Map.merge(Engine.empty_equip(), Data.starters("dk"))}
      |> Map.put(:inv, %{"potion_s" => 3, weapon => Gear.max_bag() + 2})
      |> Map.put(:storage, %{inv: %{weapon => 2, "herb" => 1}, extra: 0})

    q = Engine.instance_gear(old)
    assert Enum.all?(Map.values(q.equip), &(is_nil(&1) or Gear.instance?(&1)))
    assert q.inv == %{"potion_s" => 3}
    assert length(Gear.bag(q)) == Gear.max_bag() and length(q.mail_out) == 2
    assert q.storage.inv == %{"herb" => 1}
    assert Enum.count(Gear.list(q), & &1[:stored]) == 2
    assert Engine.derived(q).atk == Engine.derived(old).atk
    # chạy lại không đổi gì
    assert Engine.instance_gear(q) == q
  end

  test "lệnh gửi mã loại (công cụ cũ) dùng món riêng cùng loại trong túi" do
    p = Engine.add_item(hero(), "item_1_1")
    {%{ok: true}, p} = Engine.equip(p, "item_1_1")
    assert Gear.find(p, p.equip.weapon).base == "item_1_1"
    {%{ok: true}, p} = Engine.sell(p, Data.starters("dk").weapon)
    assert Gear.bag(p) == []
  end
end
