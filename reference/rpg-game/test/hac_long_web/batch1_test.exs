defmodule HacLongWeb.Batch1Test do
  @moduledoc """
  Đợt 1 tích hợp từ MU Web (docs/INTEGRATION_PLAN.md, FEATURE_CATALOG E6 / E14 / I1 / I2 / I3 / I17):
  vé WebSocket, phiên bản giao diện, `rid` chống lặp lệnh, `Market.commit` báo đúng kết quả,
  vàng `bigint` không âm, lọc tham số nhạy cảm khỏi log.
  """
  use HacLongWeb.ChannelCase

  import Plug.Conn, only: [put_req_header: 3]
  import Phoenix.ConnTest, except: [connect: 2, connect: 3]

  alias HacLong.{Accounts, Market, Moderation}
  alias HacLong.Accounts.WsTicket
  alias HacLong.Game.{Characters, Commands}
  alias HacLongWeb.{ClientVersion, UserSocket}

  @endpoint HacLongWeb.Endpoint

  defp version, do: ClientVersion.current()

  defp with_character(user, attrs \\ %{}) do
    name = "Dot #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "dk"})
    p = p |> Map.put(:tutorial, nil) |> Map.merge(attrs)
    Characters.save!(user.id, p)
    p
  end

  defp join(user) do
    {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
    subscribe_and_join(socket, "game", %{"v" => version()})
  end

  describe "I1 vé WebSocket" do
    test "vé dùng một lần, hết hạn thì bỏ, tài khoản bị khóa thì không dùng được" do
      user = create_user()
      t = Accounts.issue_ws_ticket(user)
      assert {:ok, socket} = connect(UserSocket, %{"ticket" => t})
      assert socket.assigns.user_id == user.id
      assert :error = connect(UserSocket, %{"ticket" => t})

      old = WsTicket.issue(user.id, System.monotonic_time(:millisecond) - WsTicket.ttl_ms() - 1)
      assert :error = connect(UserSocket, %{"ticket" => old})

      t2 = Accounts.issue_ws_ticket(user)
      Moderation.ban(user.id, 60, "test")
      assert :error = connect(UserSocket, %{"ticket" => t2})
    end

    test "POST /api/ws-ticket cần token ở header, trả vé dùng được" do
      user = create_user()
      token = Accounts.sign_token(user)

      assert %{"error" => _} = build_conn() |> post("/api/ws-ticket") |> json_response(401)

      %{"ticket" => t} =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> token)
        |> post("/api/ws-ticket")
        |> json_response(200)

      assert {:ok, _} = connect(UserSocket, %{"ticket" => t})
    end
  end

  describe "I3 phiên bản giao diện" do
    test "trang chủ có mã phiên bản; vào kênh sai / thiếu mã thì bị từ chối" do
      html = build_conn() |> get("/") |> html_response(200)
      assert html =~ ~s(window.CLIENT_VERSION = "#{version()}")

      user = create_user()

      for params <- [%{"v" => "cu"}, %{}] do
        {:ok, socket} = connect(UserSocket, %{"ticket" => Accounts.issue_ws_ticket(user)})
        assert {:error, %{reason: "version"}} = subscribe_and_join(socket, "game", params)
      end

      assert {:ok, _, _} = join(user)
    end
  end

  describe "I2 rid" do
    test "gửi lại cùng rid không chạy lần hai, rid khác thì chạy" do
      user = create_user()
      with_character(user, %{points: 5})
      {:ok, _, socket} = join(user)

      cmd = %{"act" => "alloc", "stat" => "str", "n" => 2, "rid" => "abc-1"}
      ref = push(socket, "cmd", cmd)
      assert_reply ref, :ok, %{ok: true, player: %{points: 3}}
      Process.sleep(100)
      ref = push(socket, "cmd", cmd)
      assert_reply ref, :ok, %{ok: true, player: %{points: 3}}
      Process.sleep(100)
      ref = push(socket, "cmd", %{cmd | "rid" => "abc-2"})
      assert_reply ref, :ok, %{ok: true, player: %{points: 1}}
    end
  end

  describe "E6 Market.commit" do
    test "transaction lưu nhân vật thất bại thì báo lỗi, không báo đã rao bán" do
      user = create_user()
      p = with_character(user, %{inv: %{"ore" => 3}})
      save = fn _ -> HacLong.Repo.rollback(:that_bai) end
      assert {:error, msg} = Market.list(user.id, p, "ore", 1, 50, save)
      assert msg =~ "Không rao bán được"
      assert HacLong.Repo.aggregate("market_listings", :count) == 0
    end
  end

  describe "E14 vàng" do
    test "vàng lớn hơn int32 lưu được; vàng âm bị DB từ chối" do
      user = create_user()
      p = with_character(user)
      Characters.save!(user.id, %{p | gold: 5_000_000_000})
      assert Characters.load(user.id).gold == 5_000_000_000

      assert_raise Ecto.ConstraintError, ~r/gold_non_negative/, fn ->
        Characters.save!(user.id, %{p | gold: -1})
      end
    end
  end

  test "I17 không ghi token / vé / mật khẩu ra log" do
    filters = Application.get_env(:phoenix, :filter_parameters)
    for k <- ~w(password current token ticket), do: assert(k in filters)
  end
end
