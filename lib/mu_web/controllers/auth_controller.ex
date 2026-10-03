defmodule MuWeb.AuthController do
  @moduledoc """
  `POST /register`, `POST /login`, `POST /logout`, `POST /ws-ticket` (`KB_TECHNICAL §4`).
  Khung và ngưỡng rate-limit lấy từ `HacLongWeb.AuthController` của repo nền.
  """
  use MuWeb, :controller

  import MuWeb.HttpHelpers

  alias Mu.Accounts

  def register(conn, params) do
    with :ok <- limit(conn, {:register, ip(conn)}, ["register", "perIp"]) do
      case Accounts.register(Map.take(params, ["username", "password", "email"])) do
        {:ok, account} ->
          conn |> put_status(:created) |> json(session(account))

        {:error, cs} ->
          error(conn, :unprocessable_entity, "VALIDATION", first_error(cs))
      end
    end
  end

  def login(conn, params) do
    name = params["username"] |> to_string() |> String.trim() |> String.downcase()

    with :ok <- limit(conn, {:login_ip, ip(conn)}, ["login", "perIp"]),
         :ok <- limit(conn, {:login_name, name}, ["login", "perName"]) do
      case Accounts.authenticate(params["username"], params["password"]) do
        {:ok, account} ->
          json(conn, session(account))

        {:error, _} ->
          error(conn, :unauthorized, "INVALID_CREDENTIALS", "Sai tên đăng nhập hoặc mật khẩu.")
      end
    end
  end

  @doc "Thu hồi access token đang dùng."
  def logout(conn, _params) do
    Accounts.revoke_access_token(conn.assigns.access_token)
    json(conn, %{ok: true})
  end

  @doc "Ticket một lần (TTL ngắn) để mở WebSocket `/socket?ticket=...`."
  def ws_ticket(conn, _params) do
    account = conn.assigns.current_account

    with :ok <- limit(conn, {:ws_ticket, account.id}, ["wsTicket", "perAccount"]) do
      json(conn, %{ticket: Accounts.issue_ws_ticket(account)})
    end
  end

  defp session(account) do
    %{
      token: Accounts.create_access_token(account),
      expiresIn: Mu.Game.Config.get(["auth", "accessTokenTtlSeconds"]),
      username: account.username
    }
  end

  @labels %{username: "Tên đăng nhập", password: "Mật khẩu", email: "Email"}

  defp first_error(cs) do
    {field, {msg, _}} = hd(cs.errors)
    "#{Map.get(@labels, field, field)} #{msg}."
  end
end
