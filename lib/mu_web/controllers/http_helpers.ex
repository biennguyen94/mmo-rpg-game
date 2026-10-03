defmodule MuWeb.HttpHelpers do
  @moduledoc """
  Tiện ích chung cho controller: rate-limit (đọc ngưỡng từ `rateLimit` trong config) và lỗi
  JSON dạng `{error: MÃ, message: "..."}` (docs/DECISIONS.md).
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Mu.Game.Config

  @doc "`:ok` hoặc conn đã trả 429 (dùng trong `with`)."
  def limit(conn, key, config_path) do
    %{"limit" => n, "windowMs" => window} = Config.get(["rateLimit" | config_path])

    case Mu.RateLimit.hit(key, n, window) do
      :ok ->
        :ok

      {:error, secs} ->
        wait = if secs >= 60, do: "#{div(secs + 59, 60)} phút", else: "#{secs} giây"

        conn
        |> put_resp_header("retry-after", Integer.to_string(secs))
        |> error(
          :too_many_requests,
          "RATE_LIMITED",
          "Thử quá nhiều lần. Đợi #{wait} rồi thử lại."
        )
    end
  end

  def error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: code, message: message})
  end

  @doc "IP người gọi (đã tính X-Forwarded-For nếu có proxy tin cậy, xem `MuWeb.RemoteIp`)."
  def ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
