defmodule MuWeb.ConnCase do
  @moduledoc "Test HTTP (Phoenix.ConnTest) có database."
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint MuWeb.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest
      import MuWeb.ConnCase
      import Mu.DataCase, only: [create_account: 0, create_account: 1, unique_name: 1]
    end
  end

  setup tags do
    Mu.DataCase.setup_sandbox(tags)
    Mu.RateLimit.reset()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "conn có header `Authorization: Bearer` của tài khoản."
  def authed(conn, account) do
    Plug.Conn.put_req_header(
      conn,
      "authorization",
      "Bearer " <> Mu.Accounts.create_access_token(account)
    )
  end
end
