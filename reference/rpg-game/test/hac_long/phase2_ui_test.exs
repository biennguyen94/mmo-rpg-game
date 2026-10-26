defmodule HacLong.Phase2UiTest do
  @moduledoc "Phase 2 (giao diện): vứt đồ trên bảng kết quả, hồ sơ có chi tiết đồ, lọc người nhận quà, Đài Phúc Lành lưu / nạp."
  use HacLong.DataCase, async: false

  alias HacLong.{Accounts, Mailbox, Profile}
  alias HacLong.Game.{Blessing, Characters, Commands, Engine, Gear}

  defp user(name) do
    {:ok, u} = Accounts.register(%{"username" => name, "password" => "matkhau1"})
    u
  end

  defp player(name, attrs \\ %{}) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    Map.merge(p, attrs)
  end

  test "vứt đồ vừa nhặt khi trận đã xong; trận chưa xong thì không" do
    g = Gear.new("item_0_26", 2)
    p = player("Vut") |> Map.put(:gear, [g])
    assert {%{ok: false}, _} = Engine.discard(%{p | battle: %{over: false}}, g.uid)
    assert {%{ok: true}, p2} = Engine.discard(%{p | battle: %{over: true}}, g.uid)
    assert Gear.list(p2) == []
  end

  test "hồ sơ gửi đủ thông tin món đang mặc (dòng cộng thêm, May mắn, Excellent)" do
    g = Gear.new("item_0_26", 3) |> Map.merge(%{luck: true, exc: ["crit"]})
    p = player("Hoso", %{level: 50, gear: [g]})
    p = put_in(p.equip.weapon, g.uid)
    w = Enum.find(Profile.build(1, p, false).equip, &(&1.slot == :weapon))
    assert %{opt: 3, luck: true, exc_lines: [%{id: "crit"}]} = w.item
    refute Map.has_key?(w.item, :uid)
  end

  test "quà cho mọi người: lọc theo cấp, chuyển sinh; không gửi bot" do
    a = user("qua_a")
    b = user("qua_b")
    bot = user("qua_bot")

    HacLong.Repo.update_all(Ecto.Query.from(u in "users", where: u.id == ^bot.id),
      set: [role: "bot"]
    )

    Characters.save!(a.id, player("QuaA", %{level: 10}))
    Characters.save!(b.id, player("QuaB", %{level: 40, rebirths: 2}))
    Characters.save!(bot.id, player("QuaBot", %{level: 40}))

    mine = fn ids -> Enum.filter(ids, &(&1 in [a.id, b.id, bot.id])) |> Enum.sort() end
    assert mine.(Mailbox.recipients(%{})) == Enum.sort([a.id, b.id])
    assert mine.(Mailbox.recipients(%{"min_level" => 20})) == [b.id]
    assert mine.(Mailbox.recipients(%{"max_level" => 20})) == [a.id]
    assert mine.(Mailbox.recipients(%{"min_rebirths" => 1})) == [b.id]
    assert mine.(Mailbox.recipients(%{"online" => true})) == []

    {:ok, _} =
      Mailbox.send_all(%{subject: "Quà", items: %{"potion_l" => 2}}, %{"min_level" => 20})

    assert [%{subject: "Quà"}] = Mailbox.list(b.id)
    assert Mailbox.list(a.id) == []
  end

  test "Đài Phúc Lành lưu và nạp lại từ database" do
    u = user("phuc")
    map = HacLong.World.Maps.get("forest_2")
    {_, p} = Blessing.touch(player("Phuc"), map)
    Characters.save!(u.id, p)
    assert Characters.load(u.id).blessing == p.blessing
    assert Blessing.load(%{"map" => "khong_co"}) == nil
  end

  test "người khác trên bản đồ thấy số lần chuyển sinh (Quanh đây)" do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Chuyen Sinh", "cls" => "dk"})
    assert HacLong.World.info(p).rebirths == 0
    assert HacLong.World.info(Map.put(p, :rebirths, 7)).rebirths == 7
  end
end
