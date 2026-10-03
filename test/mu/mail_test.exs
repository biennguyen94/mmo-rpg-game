defmodule Mu.MailTest do
  use Mu.DataCase, async: false

  alias Mu.Mail
  alias Mu.Game.{Character, ItemAudit, Items}

  setup do
    {_, c} = create_character()
    %{c: c}
  end

  test "tạo nhân vật có mail chào mừng (WELCOME, không quà), chưa đọc", %{c: c} do
    assert Mail.unread(c.id) == 1

    assert [%{kind: "WELCOME", title: "Chào mừng bạn đến MU Web", zen: 0, item: nil, read: false}] =
             Mail.list(c.id)

    # mở danh sách = đã đọc
    assert Mail.unread(c.id) == 0
    assert [%{read: true}] = Mail.list(c.id)
  end

  test "gửi kiểm hợp lệ; mail hết hạn không hiện, không nhận được", %{c: c} do
    assert {:error, :unknown_item} =
             Mail.deliver(c.id, %{kind: "GIFT", title: "x", item: "khong_co"})

    assert {:error, :bad_mail} = Mail.deliver(c.id, %{kind: "XX", title: "x"})

    assert {:error, :title_too_long} =
             Mail.deliver(c.id, %{kind: "SYSTEM", title: String.duplicate("a", 81)})

    assert {:error, :no_character} =
             Mail.deliver_to_name("KhongCo99", %{kind: "SYSTEM", title: "x"})

    {:ok, m} = Mail.deliver(c.id, %{kind: "GIFT", title: "Quà", zen: 100})

    Repo.update_all(from(x in Mail.Message, where: x.id == ^m.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1)]
    )

    refute Enum.any?(Mail.list(c.id), &(&1.id == m.id))
    assert {:error, "INVALID_TARGET"} = Items.claim_mail(c.id, m.id)
  end

  test "nhận quà: Zen + item vào túi trong 1 transaction, audit MAIL_CLAIM; nhận lại / người khác → lỗi",
       %{c: c} do
    {:ok, m} =
      Mail.deliver_to_name(c.name, %{
        kind: "GIFT",
        title: "Quà Tết",
        body: "Tặng",
        zen: 1000,
        item: "hp_potion_small",
        quantity: 3
      })

    assert {:ok, %{zen: 1000, items: [it]}} = Items.claim_mail(c.id, m.id)
    assert {it.template_id, it.quantity} == {"hp_potion_small", 3}
    assert Repo.get!(Character, c.id).zen == 1000

    assert [%{action: "MAIL_CLAIM", from_owner: from}] =
             Repo.all(
               from a in ItemAudit,
                 where: a.item_id == ^it.id,
                 select: %{action: a.action, from_owner: a.from_owner}
             )

    assert from == "mail:" <> m.id
    assert {:error, "INVALID_TARGET"} = Items.claim_mail(c.id, m.id)
    {_, other} = create_character()
    {:ok, m2} = Mail.deliver(c.id, %{kind: "GIFT", title: "x", zen: 5})
    assert {:error, "INVALID_TARGET"} = Items.claim_mail(other.id, m2.id)
    assert {:error, "INVALID_TARGET"} = Items.claim_mail(c.id, "khong-phai-uuid")
    assert %{claimed: true, read: true} = Enum.find(Mail.list(c.id), &(&1.id == m.id))
  end

  test "túi đầy: INVENTORY_FULL, không nhận gì (cả Zen)", %{c: c} do
    for _ <- 1..64,
        do: Items.pickup(c.id, %{serial: Mu.Ulid.generate(), template_id: "sword_t0"}, "test")

    {:ok, m} = Mail.deliver(c.id, %{kind: "GIFT", title: "x", zen: 50, item: "shield_t0"})
    assert {:error, "INVENTORY_FULL"} = Items.claim_mail(c.id, m.id)
    assert Repo.get!(Character, c.id).zen == 0
    assert %{claimed: false} = Enum.find(Mail.list(c.id), &(&1.id == m.id))
  end

  test "xóa: chỉ mail đã đọc và không còn quà chưa nhận; xóa hết đã đọc", %{c: c} do
    {:ok, gift} = Mail.deliver(c.id, %{kind: "GIFT", title: "g", zen: 10})
    {:ok, sys} = Mail.deliver(c.id, %{kind: "SYSTEM", title: "s"})
    # chưa đọc → không xóa được
    assert {:error, "INVALID_TARGET"} = Mail.delete(c.id, sys.id)
    Mail.list(c.id)
    assert {:ok, 1} = Mail.delete(c.id, sys.id)
    assert {:error, "INVALID_TARGET"} = Mail.delete(c.id, gift.id)
    # xóa hết đã đọc: còn lại quà chưa nhận
    assert {:ok, 1} = Mail.delete(c.id, :read)
    assert [%{id: id}] = Mail.list(c.id)
    assert id == gift.id
  end
end
