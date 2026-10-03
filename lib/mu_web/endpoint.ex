defmodule MuWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :mu

  # Client mở socket với `?ticket=...` (KB_TECHNICAL §4). Không log query string:
  # Phoenix.Logger chỉ in đường dẫn, tham số đi qua `:filter_parameters` (config.exs).
  socket "/socket", MuWeb.UserSocket,
    websocket: [connect_info: [:peer_data]],
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :mu,
    gzip: false,
    only: MuWeb.static_paths()

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :mu
  end

  # IP thật khi chạy sau proxy (dùng cho giới hạn đăng nhập theo IP)
  plug MuWeb.RemoteIp

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.Head
  plug MuWeb.Router
end
