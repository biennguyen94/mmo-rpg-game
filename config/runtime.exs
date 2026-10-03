import Config

# Bản release: PHX_SERVER=true bin/mu start (rel/overlays/bin/start đã đặt sẵn).
if System.get_env("PHX_SERVER") do
  config :mu, MuWeb.Endpoint, server: true
end

# Proxy tin cậy (Caddy, load balancer) để đọc IP thật từ X-Forwarded-For:
#   TRUSTED_PROXIES="172.16.0.0/12,127.0.0.1"
if proxies = System.get_env("TRUSTED_PROXIES") do
  config :mu, :trusted_proxies, String.split(proxies, ",", trim: true)
end

if config_env() == :prod do
  # biến đặt nhưng để trống (docker compose) coi như không đặt
  env = fn name ->
    case System.get_env(name) do
      nil -> nil
      v -> if String.trim(v) == "", do: nil, else: String.trim(v)
    end
  end

  database_url =
    env.("DATABASE_URL") ||
      raise "environment variable DATABASE_URL is missing (ecto://USER:PASS@HOST/DATABASE)"

  maybe_ipv6 = if env.("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :mu, Mu.Repo,
    url: database_url,
    pool_size: String.to_integer(env.("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    env.("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing (openssl rand -base64 48)"

  host = env.("PHX_HOST") || "example.com"
  port = String.to_integer(env.("PORT") || "4000")
  scheme = env.("PHX_SCHEME") || "https"

  url_port =
    String.to_integer(env.("PHX_URL_PORT") || if(scheme == "https", do: "443", else: "80"))

  check_origin =
    case env.("CHECK_ORIGIN") do
      nil -> true
      list -> String.split(list, ",", trim: true) |> Enum.map(&String.trim/1)
    end

  config :mu, MuWeb.Endpoint,
    url: [host: host, port: url_port, scheme: scheme],
    check_origin: check_origin,
    http: [
      ip: if(env.("PHX_IPV6") in ~w(true 1), do: {0, 0, 0, 0, 0, 0, 0, 0}, else: {0, 0, 0, 0}),
      port: port
    ],
    secret_key_base: secret_key_base
end
