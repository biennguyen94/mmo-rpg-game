#!/bin/bash
# Setup script cho môi trường cloud `mu-web-phase1` (dán vào ô "Setup script" của môi trường,
# KHÔNG chạy trong phiên). Xem docs/OPEN_QUESTIONS.md E1–E4.
# Cần allowlist: repo.hex.pm, builds.hex.pm (+ danh sách package manager mặc định).
# Elixir 1.17.3 vì mix.lock của repo nền cần Elixir >= 1.15 (apt Ubuntu 24.04 chỉ có 1.14).
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
apt-get install -y erlang erlang-dev inotify-tools unzip build-essential || true
if ! command -v elixir >/dev/null 2>&1; then
  curl -fsSL https://builds.hex.pm/builds/elixir/v1.17.3-otp-25.zip -o /tmp/elixir.zip \
    && mkdir -p /opt/elixir && unzip -qo /tmp/elixir.zip -d /opt/elixir \
    && ln -sf /opt/elixir/bin/* /usr/local/bin/ || true
fi
mix local.hex --force || true
mix local.rebar --force || true
# Mật khẩu postgres/postgres khớp config dev/test
service postgresql start || true
su postgres -c "psql -c \"ALTER USER postgres PASSWORD 'postgres';\"" || true
service postgresql stop || true
elixir --version || echo "WARN: elixir chua cai duoc"
exit 0
