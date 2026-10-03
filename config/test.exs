import Config

config :mu, Mu.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mu_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :mu, MuWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Wq1nB8vXo3Lk5Jd2Hs9Gf4Ra7Te0Yu6Ip3Oz8Mx1Cv5Bn2Al7Sk4Dj9Fh6Gq0Wr3E",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime

# Argon2 nhanh trong test (production dùng mặc định của thư viện)
config :argon2_elixir, t_cost: 1, m_cost: 8

# MapServer không tự tick trong test: test gọi Mu.World.MapServer.tick/2 (kết quả không phụ
# thuộc thời gian thực). Test đo nhịp tick tự chạy MapServer riêng ở chế độ :auto.
config :mu, :map_tick, :manual

# Lịch event (P6-M5) không tự chạy trong test: test gọi Mu.WorldEvents.check/1 với đồng hồ giả
# hoặc start/stop bằng tay.
config :mu, :world_events_auto, false
