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
    assert msg =~ "(+8)"
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
