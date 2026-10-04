defmodule MuWeb.MailChannelTest do
  @moduledoc "P2-M6 qua kênh thật: badge hộp thư, mail_list / mail_claim / mail_delete, mail mới khi online."
  use MuWeb.ChannelCase

  alias Mu.Mail
  alias MuWeb.GameChannel

  defp join_game(account, character) do
    {:ok, socket} = connect_account(account)

    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => client_version(),
      "characterId" => character.id
    })
  end

  defp cmd(socket, payload) do
    Mu.RateLimit.reset()
    ref = push(socket, "cmd", payload)
    assert_reply ref, status, reply
    {status, reply}
  end

  test "vào game: badge 1 (mail chào mừng); list → đọc hết; quà: nhận (idempotent rid), xóa đã đọc" do
    {a, c} = create_character()
    {:ok, _, socket} = join_game(a, c)
    assert_push "mail", %{unread: 1}

    assert {:ok, _} = cmd(socket, %{"act" => "mail_list", "rid" => "l1"})
    assert_push "mail", %{unread: 0, items: [%{kind: "WELCOME", read: false}]}

    # quản trị gửi khi đang online → badge cập nhật ngay
    {:ok, m} =
      Mail.deliver(c.id, %{
        kind: "GIFT",
        title: "Quà",
        zen: 500,
        item: "hp_potion_small",
        quantity: 2
      })

    assert_push "mail", %{unread: 1}

    assert {:ok, _} = cmd(socket, %{"act" => "mail_claim", "rid" => "c1", "mailId" => m.id})
    assert_push "player", %{zen: 500, inventory: [%{templateId: "hp_potion_small", quantity: 2}]}
    assert_push "mail", %{items: [%{claimed: true} | _]}
    # gửi lại cùng rid: không nhận lần hai
    assert {:ok, _} = cmd(socket, %{"act" => "mail_claim", "rid" => "c1", "mailId" => m.id})

    assert {:error, %{error: "INVALID_TARGET"}} =
             cmd(socket, %{"act" => "mail_claim", "rid" => "c2", "mailId" => m.id})

    assert Mu.Repo.get!(Mu.Game.Character, c.id).zen == 500

    assert {:ok, _} = cmd(socket, %{"act" => "mail_delete", "rid" => "d1", "read" => true})
    assert_push "mail", %{items: []}

    assert {:error, %{error: "INVALID_TARGET"}} =
             cmd(socket, %{"act" => "mail_delete", "rid" => "d2", "mailId" => m.id})
  end
end
