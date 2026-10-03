# Bản release của MU Web chạy trong Docker.
#   docker compose up -d --build
ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=25.3.2.21
ARG DEBIAN_VERSION=bookworm-20260918-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ---------- Client (TypeScript → ES module, priv/static/js) ----------
FROM node:22-bookworm-slim AS client
WORKDIR /app/client
COPY client/package.json client/tsconfig.json client/build.mjs ./
# Chưa có package-lock.json (registry npm bị chặn trong môi trường cloud lúc viết: E7)
RUN npm install --no-audit --no-fund
COPY client/src src
RUN npm run build

# ---------- Biên dịch ----------
FROM ${BUILDER_IMAGE} AS build

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app
ENV MIX_ENV=prod LANG=C.UTF-8

RUN mix local.hex --force && mix local.rebar --force

# thư viện trước (đổi code game không phải tải lại thư viện)
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# priv/game_data/*.json đọc lúc biên dịch. Asset MU-derived bị .dockerignore chặn (KB_ASSETS §2.2).
COPY priv priv
COPY --from=client /app/priv/static/js priv/static/js
COPY --from=client /app/priv/static/vendor priv/static/vendor
COPY lib lib
RUN mix compile
# icon_map.json (gitignore): image không có icon MU-derived → mọi item dùng placeholder
RUN mix mu.icons.index

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# ---------- Chạy ----------
FROM ${RUNNER_IMAGE}

RUN apt-get update -y \
    && apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app
ENV MIX_ENV=prod

COPY --from=build --chown=nobody:root /app/_build/prod/rel/mu ./
USER nobody

EXPOSE 4000
CMD ["/app/bin/start"]
