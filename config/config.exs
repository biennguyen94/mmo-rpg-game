# Cấu hình chung. Số gameplay KHÔNG nằm ở đây: xem priv/game_data/*.json (KB_CONFIG).
import Config

config :mu,
  ecto_repos: [Mu.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :mu, MuWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: MuWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Mu.PubSub

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# Không ghi bí mật vào log: ticket WebSocket đi qua query string (KB_TECHNICAL §4),
# Phoenix.Logger in tham số của socket/request qua bộ lọc này.
config :phoenix, :filter_parameters, ["password", "ticket", "token"]

import_config "#{config_env()}.exs"
