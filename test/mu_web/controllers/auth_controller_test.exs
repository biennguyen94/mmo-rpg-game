defmodule MuWeb.AuthControllerTest do
  use MuWeb.ConnCase, async: false

  describe "POST /register" do
    test "tạo tài khoản và trả access token", %{conn: conn} do
      conn = post(conn, "/register", %{username: "NewUser", password: "matkhau123"})

      assert %{"token" => token, "username" => "NewUser", "expiresIn" => 86_400} =
               json_response(conn, 201)

      assert {:ok, _} = Mu.Accounts.verify_access_token(token)
    end

    test "dữ liệu sai trả 422 VALIDATION", %{conn: conn} do
      conn = post(conn, "/register", %{username: "x", password: "matkhau123"})
      assert %{"error" => "VALIDATION", "message" => msg} = json_response(conn, 422)
      assert msg =~ "Tên đăng nhập"
    end

    test "giới hạn theo IP (rateLimit.register.perIp)", %{conn: conn} do
      n = Mu.Game.Config.get(["rateLimit", "register", "perIp", "limit"])

      for i <- 1..n do
        assert post(conn, "/register", %{username: "reg#{i}x", password: "matkhau123"}).status ==
                 201
      end

      conn = post(conn, "/register", %{username: "regmore", password: "matkhau123"})
      assert %{"error" => "RATE_LIMITED"} = json_response(conn, 429)
      assert get_resp_header(conn, "retry-after") != []
    end
  end

  describe "POST /login" do
    setup do
      %{account: create_account("LoginMe")}
    end

    test "đúng mật khẩu", %{conn: conn} do
      conn = post(conn, "/login", %{username: "loginme", password: "matkhau123"})
      assert %{"token" => token} = json_response(conn, 200)
      assert {:ok, %{username: "LoginMe"}} = Mu.Accounts.verify_access_token(token)
    end

    test "sai mật khẩu và tên không có trả cùng một lỗi", %{conn: conn} do
      a = post(conn, "/login", %{username: "loginme", password: "saimatkhau"})
      b = post(conn, "/login", %{username: "khongco", password: "saimatkhau"})
      assert json_response(a, 401) == json_response(b, 401)
      assert %{"error" => "INVALID_CREDENTIALS"} = json_response(a, 401)
    end

    test "chống dò mật khẩu: rateLimit.login.perName", %{conn: conn} do
      n = Mu.Game.Config.get(["rateLimit", "login", "perName", "limit"])

      for _ <- 1..n do
        assert post(conn, "/login", %{username: "LOGINME", password: "sai"}).status == 401
      end

      conn = post(conn, "/login", %{username: "loginme", password: "matkhau123"})
      assert %{"error" => "RATE_LIMITED"} = json_response(conn, 429)
    end
  end

  describe "cần access token" do
    test "thiếu/sai token → 401", %{conn: conn} do
      for {method, path} <- [
            {:post, "/ws-ticket"},
            {:get, "/characters"},
            {:post, "/characters"},
            {:post, "/logout"}
          ] do
        assert %{"error" => "UNAUTHORIZED"} = json_response(dispatch_req(conn, method, path), 401)

        bad = put_req_header(conn, "authorization", "Bearer abc")
        assert json_response(dispatch_req(bad, method, path), 401)
      end
    end

    test "POST /ws-ticket trả ticket dùng được một lần", %{conn: conn} do
      account = create_account()
      conn = conn |> authed(account) |> post("/ws-ticket")
      assert %{"ticket" => ticket} = json_response(conn, 200)
      assert {:ok, %{id: id}} = Mu.Accounts.consume_ws_ticket(ticket)
      assert id == account.id
      assert :error = Mu.Accounts.consume_ws_ticket(ticket)
    end

    test "POST /logout thu hồi token", %{conn: conn} do
      account = create_account()
      token = Mu.Accounts.create_access_token(account)
      conn = put_req_header(conn, "authorization", "Bearer " <> token)
      assert json_response(post(conn, "/logout"), 200) == %{"ok" => true}
      assert json_response(post(conn, "/ws-ticket"), 401)
    end
  end

  defp dispatch_req(conn, :get, path), do: get(conn, path)
  defp dispatch_req(conn, :post, path), do: post(conn, path)
end
