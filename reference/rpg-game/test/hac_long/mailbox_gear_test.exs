defmodule HacLong.MailboxGearTest do
  # Phase 11 (V10): quà đồ riêng từng món qua hộp thư ("gear:<mẫu>:<độ hiếm>:<+N>")
  use HacLong.DataCase, async: false

  alias HacLong.{Accounts, Mailbox}
  alias HacLong.Game.{Commands, Data, Gear}

  defp user(name) do
    {:ok, u} = Accounts.register(%{"username" => name, "password" => "matkhau1"})
    u
  end

  defp base(slot), do: Data.items() |> Enum.find(fn {_, it} -> it.slot == slot end) |> elem(0)

  test "gửi và mở thư có đồ thường +3 và đồ có dòng cộng thêm" do
    w = base("weapon")
    user = user("mgift")
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "mgift", "cls" => "dk"})
    p = Map.put(p, :level, 12)

    items = %{Mailbox.gear_key(w, 0, 3) => 1, Mailbox.gear_key(w, 2, 0) => 2}
    assert :ok = Mailbox.send(user.id, %{subject: "Quà", items: items})
    [m] = Mailbox.list(user.id)

    assert {:ok, msg, p2} = Mailbox.claim(user.id, m.id, p, fn _ -> :ok end)
    assert msg =~ "+3"
    bag = Gear.bag(p2)
    assert length(bag) == length(Gear.bag(p)) + 3
    plain = Enum.find(bag, &(&1[:opt] == nil))
    assert p2.upgrades[plain.uid] == 3
    assert Enum.count(bag, &(&1[:opt] == 2)) == 2
    assert msg =~ "(cộng thêm 8)"
  end

  test "túi đồ hiếm đầy: đồ rơi vào Hộp thư đủ dòng; hộp thư đầy thì bán" do
    user = user("mfull")
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "mfull", "cls" => "dk"})
    p = Map.merge(p, %{level: 50, gear: for(_ <- 1..Gear.max_bag(), do: Gear.new(base("armor")))})

    g =
      Gear.new("item_0_26", 2)
      |> Map.merge(%{luck: true, skill: true, exc: ["crit", "atk_pct"]})

    assert {p, :mailed} = Gear.add(p, g)
    assert length(Gear.list(p)) == Gear.max_bag() and p.mail_out == [g]

    p = Mailbox.send_overflow(user.id, p)
    refute Map.has_key?(p, :mail_out)
    [m] = Mailbox.list(user.id)
    assert m.subject =~ "Túi đồ hiếm đầy"

    # chưa dọn túi: không mở được; dọn một món rồi mở thì có đủ dòng
    assert {:error, _} = Mailbox.claim(user.id, m.id, p, fn _ -> :ok end)
    p = %{p | gear: tl(p.gear)}
    assert {:ok, _msg, p2} = Mailbox.claim(user.id, m.id, p, fn _ -> :ok end)
    got = List.last(Gear.list(p2))

    assert %{base: "item_0_26", opt: 2, luck: true, skill: true} = got
    assert Enum.sort(got.exc) == ["atk_pct", "crit"]

    # hộp thư đủ RULES.mail.keep thư chưa mở: bán lấy vàng
    keep = Data.rules().mail.keep
    for i <- 1..keep, do: Mailbox.send(user.id, %{subject: "đầy #{i}"})
    gold = p.gold
    p3 = Mailbox.send_overflow(user.id, Map.put(p, :mail_out, [g]))
    assert p3.gold == gold + Gear.price(g)
    assert Mailbox.unread(user.id) == keep
  end

  test "từ chối khóa đồ không hợp lệ" do
    user = user("mbad")

    assert {:error, _} =
             Mailbox.send(user.id, %{subject: "x", items: %{"gear:khong_co:0:0" => 1}})

    assert {:error, _} =
             Mailbox.send(user.id, %{
               subject: "x",
               items: %{Mailbox.gear_key(base("weapon"), 0, 99) => 1}
             })
  end

  test "quà nhẫn / dây chuyền có dòng cộng thêm (nhẫn là loại \"ring\", ô mặc ring1 / ring2)" do
    user = user("mring")
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "mring", "cls" => "dk"})

    items = %{
      Mailbox.gear_key(base("ring"), 2, 1) => 1,
      Mailbox.gear_key(base("pendant"), 1, 0) => 1
    }

    assert :ok = Mailbox.send(user.id, %{subject: "Trang sức", items: items})
    [m] = Mailbox.list(user.id)
    assert {:ok, _msg, p2} = Mailbox.claim(user.id, m.id, p, fn _ -> :ok end)
    slots = p2 |> Gear.bag() |> Enum.map(&{Data.item(&1.base).slot, &1[:opt]}) |> Enum.sort()
    assert {"pendant", 1} in slots and {"ring", 2} in slots
  end
end
