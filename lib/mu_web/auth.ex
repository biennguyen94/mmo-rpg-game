defmodule MuWeb.Auth do
  @moduledoc """
  Plug: đọc `Authorization: Bearer <access token>`, gán `:current_account` và `:access_token`.
  Sai/hết hạn → 401 `UNAUTHORIZED`.
  """
  @behaviour Plug
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Mu.Accounts

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, account} <- Accounts.verify_access_token(token) do
      conn |> assign(:current_account, account) |> assign(:access_token, token)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "UNAUTHORIZED", message: "Phiên đăng nhập đã hết hạn."})
        |> halt()
    end
  end
end
