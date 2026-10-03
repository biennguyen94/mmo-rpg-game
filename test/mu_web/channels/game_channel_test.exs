defmodule MuWeb.GameChannelTest do
  use MuWeb.ChannelCase

  import ExUnit.CaptureLog

  alias MuWeb.{GameChannel, UserSocket}

  setup do
    {account, character} = create_character()
    %{account: account, character: character}
  end

  defp join_game(socket, character, version \\ client_version()) do
    subscribe_and_join(socket, GameChannel, "game", %{
      "clientVersion" => version,
      "characterId" => character.id
    })
  end

  describe "UserSocket" do
    test "vào bằng ticket; ticket dùng một lần", %{account: account} do
      ticket = Mu.Accounts.issue_ws_ticket(account)
      assert {:ok, socket} = connect(UserSocket, %{"ticket" => ticket})
      assert socket.assigns.account_id == account.id
      assert :error = connect(UserSocket, %{"ticket" => ticket})
    end

    test "không có/sai ticket, hoặc dùng access token thay ticket", %{account: account} do
      assert :error = connect(UserSocket, %{})
      assert :error = connect(UserSocket, %{"ticket" => "sai"})
      token = Mu.Accounts.create_access_token(account)
      assert :error = connect(UserSocket, %{"token" => token})
      assert :error = connect(UserSocket, %{"ticket" => token})
    end

    test "ticket không xuất hiện trong log", %{account: account} do
      ticket = Mu.Accounts.issue_ws_ticket(account)
      level = Logger.level()
      Logger.configure(level: :debug)

      log =
        try do
          capture_log(fn -> {:ok, _} = connect(UserSocket, %{"ticket" => ticket}) end)
        after
          Logger.configure(level: level)
        end

      assert log =~ "CONNECTED TO MuWeb.UserSocket"
      refute log =~ ticket
    end
  end

  describe "join" do
    test "trả trạng thái nhân vật kèm view", %{account: a, character: c} do
      {:ok, socket} = connect_account(a)
      assert {:ok, reply, _} = join_game(socket, c)

      assert %{id: id, class: "DK", hp: 185, mp: 30, view: %{hpMax: 185, mpMax: 30}} =
               reply.player

      assert id == c.id
      assert reply.config.clientVersion == client_version()
    end

    test "clientVersion không khớp → FORBIDDEN", %{account: a, character: c} do
      {:ok, socket} = connect_account(a)

      assert {:error, %{error: "FORBIDDEN", reason: "clientVersion"}} =
               join_game(socket, c, "0.0.1")

      assert {:error, %{error: "FORBIDDEN"}} =
               subscribe_and_join(socket, GameChannel, "game", %{"characterId" => c.id})
    end

    test "nhân vật của tài khoản khác → FORBIDDEN", %{account: a} do
      {_, other} = create_character()
      {:ok, socket} = connect_account(a)
      assert {:error, %{error: "FORBIDDEN", reason: "character"}} = join_game(socket, other)

      assert {:error, %{error: "FORBIDDEN"}} =
               join_game(socket, %{id: "khong-phai-uuid"})
    end

    test "một tài khoản một phiên: vào lần hai đá kênh cũ", %{account: a, character: c} do
      {:ok, s1} = connect_account(a)
      {:ok, _, ch1} = join_game(s1, c)
      Process.unlink(ch1.channel_pid)
      ref = Process.monitor(ch1.channel_pid)

      {:ok, s2} = connect_account(a)
      {:ok, _, ch2} = join_game(s2, c)

      assert_push "error", %{error: "FORBIDDEN", rid: nil}
      assert_receive {:DOWN, ^ref, :process, _, {:shutdown, :kicked}}
      assert Process.alive?(ch2.channel_pid)
    end
  end

  describe "cmd" do
    setup %{account: a, character: c} do
      {:ok, socket} = connect_account(a)
      {:ok, _, socket} = join_game(socket, c)
      %{socket: socket}
    end

    test "phong bì sai → FORBIDDEN (reply + event error)", %{socket: socket} do
      ref = push(socket, "cmd", %{"act" => "fly", "rid" => "r1"})
      assert_reply ref, :error, %{rid: "r1", error: "FORBIDDEN"}
      assert_push "error", %{rid: "r1", error: "FORBIDDEN"}

      ref = push(socket, "cmd", %{"act" => "move_to"})
      assert_reply ref, :error, %{rid: nil, error: "FORBIDDEN"}
    end

    test "act hợp lệ nhưng chưa làm (M3–M4) → FORBIDDEN", %{socket: socket} do
      ref = push(socket, "cmd", %{"act" => "attack", "rid" => "a1", "target" => "m_1"})
      assert_reply ref, :error, %{rid: "a1", error: "FORBIDDEN"}
    end

    test "gửi quá nhanh → RATE_LIMITED, nhóm khác không bị ảnh hưởng", %{socket: socket} do
      # 25 lệnh trong < 1 giây chạm tối đa 2 cửa sổ 1 giây × 10 lệnh
      replies =
        for i <- 1..25 do
          # (1, 1) là cây ở viền map: lệnh hợp lệ nhưng bị từ chối INVALID_TARGET
          ref = push(socket, "cmd", %{"act" => "move_to", "rid" => "r#{i}", "x" => 1, "y" => 1})
          assert_reply ref, :error, %{error: code}
          code
        end

      assert "RATE_LIMITED" in replies
      assert Enum.count(replies, &(&1 == "INVALID_TARGET")) <= 20

      ref = push(socket, "cmd", %{"act" => "alloc", "rid" => "a1"})
      assert_reply ref, :error, %{error: "FORBIDDEN"}
    end
  end
end
