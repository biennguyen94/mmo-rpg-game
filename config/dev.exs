import Config

config :mu, Mu.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mu_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :mu, MuWeb.Endpoint,
  # chỉ nghe loopback; đổi thành {0, 0, 0, 0} để máy khác vào được
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dlv5n0vJ4bJ2m3Qq6yTt0pG7w8d1kq9uE2fL3sV0hC4xR7aB1nM5zY8iO6jW2cKe",
  watchers: []

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
