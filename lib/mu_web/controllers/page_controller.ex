defmodule MuWeb.PageController do
  @moduledoc "Trang chủ: `priv/static/index.html` (client Phaser build ở M5)."
  use MuWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Application.app_dir(:mu, "priv/static/index.html"))
  end
end
