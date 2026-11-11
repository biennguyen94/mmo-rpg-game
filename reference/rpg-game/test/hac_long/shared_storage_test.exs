defmodule HacLong.SharedStorageTest do
  # DECISIONS "Nhiều nhân vật": Thủ Kho giữ thùng đồ chung của tài khoản (đồ thường, đồ hiếm kèm cấp ép, vàng, mở rộng)
  use HacLong.DataCase, async: false

  alias HacLong.{Accounts, AccountStorage, Audit}
  alias HacLong.Game.{Characters, Commands, Gear, Session}

  @wardrobe %{map: "village", x: 11, y: 13}

  defp account(name) do
    {:ok, u} = Accounts.register(%{"username" => name, "password" => "matkhau1"})
    u
  end

  # nhân vật mới ở chỗ `cid`, đứng cạnh Thủ Kho
  defp hero(cid, name, attrs) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})

    Characters.save!(
      cid,
      p |> Map.put(:tutorial, nil) |> Map.put(:pos, @wardrobe) |> Map.merge(attrs),
      "TEST"
    )
  end

  test "nhân vật A cất, nhân vật B cùng tài khoản lấy; tài khoản khác không thấy; nhật ký đúng, audit sạch" do
    acct = account("thungchung")
    {:ok, a} = Accounts.character_slot(acct)
    g = Gear.new("dagger", 2)
    hero(a, "Nguoi Cat", %{gear: [g], upgrades: %{g.uid => 5}, inv: %{"herb" => 3}, gold: 1000})
    {:ok, b} = Accounts.character_slot(acct)
    assert a != b
    hero(b, "Nguoi Lay", %{gold: 0})

    {%{ok: true}, _} = Session.command(a, %{"act" => "store", "id" => g.uid})
    {%{ok: true}, _} = Session.command(a, %{"act" => "store", "id" => "herb", "n" => 3})
    {%{ok: true}, _} = Session.command(a, %{"act" => "gold_store", "n" => 600})
    refute Gear.find(Session.get(a), g.uid)

    # B vào (mỗi tài khoản một nhân vật online: Session của A tắt khi B vào bằng WebSocket; ở đây tắt tay)
    Session.stop(a)
    pb = Session.get(b)
    assert Enum.map(pb.storage.gear, & &1.uid) == [g.uid] and pb.storage.gold == 600

    {%{ok: true}, _} = Session.command(b, %{"act" => "unstore", "id" => g.uid})
    {%{ok: true}, _} = Session.command(b, %{"act" => "unstore", "id" => "herb", "n" => 3})
    {%{ok: true}, pb} = Session.command(b, %{"act" => "gold_take", "n" => 600})
    assert pb.upgrades[g.uid] == 5 and pb.inv["herb"] == 3 and pb.gold == 600
    assert Gear.find(pb, g.uid)
    assert AccountStorage.get(acct.id) == %{AccountStorage.empty() | gold: 0}

    # tài khoản khác: thùng riêng
    other = account("thungkhac")
    hero(other.id, "Nguoi Khac", %{})
    assert Session.get(other.id).storage == AccountStorage.empty()

    Session.stop(b)
    assert Enum.filter(Audit.run().problems, &(&1[:user_id] in [a, b, acct.id])) == []
  end

  test "Tủ Đồ kiểu cũ (riêng của nhân vật) chuyển vào thùng chung lúc vào game" do
    acct = account("tucu")
    g = Gear.new("dagger", 1)

    # dữ liệu cũ: món cất mang cờ `stored` trong `gear`, đồ thường / vàng ở cột `storage`
    hero(acct.id, "Nguoi Cu", %{
      gear: [Map.put(g, :stored, true)],
      upgrades: %{g.uid => 3},
      storage: %{inv: %{"ore" => 2}, gold: 50, extra: 1}
    })

    p = Session.get(acct.id)
    refute Gear.find(p, g.uid)
    assert [%{up: 3}] = p.storage.gear
    assert p.storage.inv == %{"ore" => 2} and p.storage.gold == 50 and p.storage.extra == 1
    Session.stop(acct.id)

    # đã chuyển hẳn: nạp lại không gộp lần nữa
    assert Characters.load(acct.id).storage == HacLong.Game.Storage.load(%{})
    assert AccountStorage.get(acct.id).gold == 50
    assert Session.get(acct.id).storage.gold == 50
    Session.stop(acct.id)
    assert Enum.filter(Audit.run().problems, &(&1[:user_id] == acct.id)) == []
  end

  test "Rương Gia Truyền và quà gửi mọi người: mỗi tài khoản một phần" do
    acct = account("motphan")
    {:ok, a} = Accounts.character_slot(acct)
    hero(a, "Mo Ruong", %{pos: %{map: "village", x: 13, y: 13}})
    {:ok, b} = Accounts.character_slot(acct)
    hero(b, "Mo Lai", %{pos: %{map: "village", x: 13, y: 13}})

    # Rương Gia Truyền đã bỏ (DECISIONS "Bỏ Rương Gia Truyền, Đài Phúc Lành")
    assert {%{ok: false, msg: "Rương Gia Truyền đã bỏ."}, _} =
             Session.command(a, %{"act" => "chest_open"})

    Session.stop(a)
    assert {%{ok: true}, _} = Session.command(b, %{"act" => "move", "dir" => "up"})
    Session.stop(b)

    # quà mọi người: một thư cho tài khoản, vào nhân vật chơi gần nhất (b vừa lưu sau a)
    solo = account("motminh")
    hero(solo.id, "Mot Minh", %{})
    ids = HacLong.Mailbox.recipients()
    assert solo.id in ids
    assert Enum.count(ids, &(&1 in [a, b])) == 1
  end
end
