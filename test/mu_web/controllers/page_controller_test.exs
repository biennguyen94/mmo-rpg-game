defmodule MuWeb.PageControllerTest do
  use MuWeb.ConnCase, async: true

  test "GET / trả trang client", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "MU Web"
  end
end
