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

  test "gửi và mở thư có đồ thường +3 và đồ hiếm" do
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
    plain = Enum.find(bag, &(&1.rarity == 0))
    assert p2.upgrades[plain.uid] == 3
    assert Enum.count(bag, &(&1.rarity == 2)) == 2
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
end
