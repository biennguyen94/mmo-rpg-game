# CLOUD_CHECK — Kiểm tra môi trường cloud (M0)

> Thời điểm kiểm tra: 2026-10-02 (UTC), phiên Claude Code cloud.
> Loại môi trường thấy được: `CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE=cloud_default` → **không phải** môi trường `mu-web-phase1` mô tả trong `docs/PROMPT_PHASE1_CLOUD.md §A2` (setup script chưa chạy).
> Kết luận nhanh: **Chưa đủ để bắt đầu M1.** Thiếu Elixir/Erlang, Hex bị chặn, Postgres chưa có mật khẩu. Chi tiết và việc cần làm ở `docs/OPEN_QUESTIONS.md` (mục E).

## 1. Hệ điều hành & tài nguyên

| Mục | Giá trị |
|---|---|
| OS | Ubuntu 24.04.4 LTS |
| CPU | 4 vCPU |
| RAM | 15 GiB |
| Đĩa | còn ~30 GB khả dụng trên `/` |
| Repo | clone nông (`--depth 1`), nhánh `main`, commit `604820f` |

## 2. Công cụ

| Lệnh | Kết quả |
|---|---|
| `elixir --version` | ❌ `bash: elixir: command not found` |
| `mix --version` | ❌ `bash: mix: command not found` |
| `erl` (OTP) | ❌ `bash: erl: command not found` |
| `rebar3` | ❌ không có |
| `apt-cache policy elixir erlang-base` | Có trong apt (archive.ubuntu.com truy cập được): **Elixir 1.14.0** (`1.14.0.dfsg-2`), **Erlang/OTP 25.3.2.8** — chưa cài |
| `psql --version` | ✅ PostgreSQL 16.14 |
| `node --version` / `npm --version` | ✅ v22.22.0 / 10.9.4 |
| `gcc`, `make` | ✅ gcc 13.3.0 (cần cho NIF của `argon2_elixir`) |
| `docker --version` | ✅ 29.6.2 (chưa thử build; Docker Hub chưa kiểm tra được) |
| `python3` | ✅ 3.11.15 |
| `git` | ✅ 2.43.0 |

## 3. PostgreSQL

| Kiểm tra | Kết quả |
|---|---|
| Trạng thái lúc vào phiên | ❌ `16/main (port 5432): down` — hook SessionStart **chưa có** trong repo (`.claude/settings.json`, `scripts/cloud_session_start.sh` không tồn tại) |
| `service postgresql start` | ✅ chạy được, `pg_isready` → accepting connections |
| Đăng nhập `postgres/postgres` qua TCP (như config dev/test của repo nền) | ❌ `FATAL: password authentication failed for user "postgres"` — user `postgres` chưa có mật khẩu (`rolpassword` null); `pg_hba` dùng `scram-sha-256` cho 127.0.0.1 |

## 4. Mạng (qua proxy của phiên)

| Đích | Kết quả | Ảnh hưởng |
|---|---|---|
| `hex.pm` (API) | ✅ 200 | Chỉ đọc metadata gói |
| `repo.hex.pm` | ❌ 403 (CONNECT tunnel failed) | **`mix deps.get`, `mix local.hex` không chạy được** |
| `builds.hex.pm` | ❌ 403 | Không tải được Hex/Elixir build sẵn |
| `registry.npmjs.org` | ✅ 200 — đã thử `npm install esbuild` (cả binary `@esbuild/linux-x64`) thành công | Client build qua npm OK |
| `archive.ubuntu.com` | ✅ 200 | `apt-get install elixir erlang` khả thi |
| `ppa.launchpadcontent.net`, `binaries2.erlang-solutions.com` | ❌ 403 | Không lấy được Elixir mới hơn qua PPA/Erlang Solutions |
| `github.com/crawl/tiles`, `codeload.github.com` | ❌ 403 | Không clone/tải zip repo tile DCSS |
| `raw.githubusercontent.com/crawl/tiles/...` | ✅ 200 (đọc được `README.md`, `TILES_UNDER_UNKNOWN_LICENSE.md`) | Đối chiếu license tile DCSS được; tải từng file PNG có thể được |
| `cdn.jsdelivr.net`, `kenney.nl`, `game-icons.net` | ❌ 403 | Không cần (dùng npm + asset có sẵn) |

Ghi chú: sprite DCSS (CC0) **đã có sẵn** trong `reference/rpg-game/priv/static/assets/` (vd `monsters/spider.png`, `monsters/hero.png`, `npcs/merchant.png`, `tiles/grass.png`, `doll/…`) và `reference/rpg-game/CREDITS.md` ghi đã đối chiếu với `TILES_UNDER_UNKNOWN_LICENSE.md`. Không cần tải thêm cho Phase 1.

## 5. Phiên bản gói so với Elixir từ apt

Đã tra `hex.pm/api/packages/<gói>/releases/<bản>` cho các bản khóa trong `reference/rpg-game/mix.lock`:

| Gói (bản trong mix.lock) | Yêu cầu Elixir |
|---|---|
| phoenix 1.7.24 | ~> 1.11 |
| bandit 1.12.5 | ~> 1.13 |
| ecto 3.14.2 | ~> 1.14 |
| **ecto_sql 3.14.0** | **~> 1.15** |
| **postgrex 0.22.4** | **~> 1.15** |
| **plug 1.20.3** | **~> 1.15** |
| argon2_elixir 4.1.3 (thêm mới) | ~> 1.7 |

→ Elixir 1.14 từ apt **không dùng được với mix.lock của repo nền** (CI của repo nền chạy Elixir 1.17 / OTP 25, Dockerfile `hexpm/elixir:1.17.3-erlang-25.3.2.21`). Phương án ở `OPEN_QUESTIONS.md` E3.

## 6. Trình duyệt headless

| Kiểm tra | Kết quả |
|---|---|
| `/opt/pw-browsers/chromium` | ✅ Chromium 141.0.7390.37 (Playwright 1.56.1 cài global) |
| `chrome --headless=new --screenshot` trang `data:` | ✅ ghi được PNG 400×300 |

→ M5/M6 **có thể** chụp ảnh màn hình bằng Playwright + Chromium headless (desktop 1280px, mobile 360px) làm bằng chứng phụ. Vẫn đánh dấu mục giao diện là "cần anh kiểm tra local".

## 7. Git / GitHub

| Kiểm tra | Kết quả |
|---|---|
| Clone | ✅ |
| Quyền push của phiên | ⚠️ Công cụ gắn repo báo: đọc được nhưng **push sẽ bị từ chối** (Claude GitHub App chưa có quyền ghi vào `biennguyen94/mmo-rpg-game`). Kết quả push thật của M0 ghi trong báo cáo thread |

## 8. File được nhắc trong prompt nhưng không có trong repo

| File | Trạng thái |
|---|---|
| `priv/reference/items_raw.json` | ❌ không có (KB_ITEM_REFERENCE §1 gọi là `priv_reference/items_raw.json`) |
| `reference/rpg-game/COMMIT` | ❌ không có; hash nằm ở `reference/COMMIT` = `5c514b7512183d714afb1d35ad310fa4a62f2a5d` |
| `.claude/settings.json`, `scripts/cloud_session_start.sh` | ❌ không có (PROMPT_PHASE1_CLOUD §A3) |
| `Item.txt` | ❌ không có (chỉ cần nếu chạy lại `scripts/parse_items.py`) |

## 9. Kiểm lại ở M1 (2026-10-03)

| Mục | Kết quả |
|---|---|
| `elixir --version` | ✅ Elixir 1.17.3 (OTP 25, erts 13.2.2.5) — `/usr/local/bin/elixir` |
| Hex | ✅ `mix local.hex --force` (hex 2.5.1), `mix deps.get` tải đủ gói; `argon2_elixir` biên dịch NIF bằng gcc OK |
| Postgres | ✅ `service postgresql start`, đăng nhập `postgres/postgres` qua TCP OK |
| Locale | ⚠️ VM chạy `latin1` → Elixir cảnh báo; chạy lệnh với `LANG=C.UTF-8` (hook SessionStart đã export) |
| Docker | ⚠️ `registry-1.docker.io` bị proxy chặn → không build image trong cloud; đã kiểm `MIX_ENV=prod mix release` + `bin/mu eval "Mu.Release.migrate()"` |
| Server thật | ✅ `mix phx.server` + curl + client WebSocket Node 22: register → tạo DK → ws-ticket → join → `cmd`; ticket dùng lại bị từ chối; log ghi `"ticket" => "[FILTERED]"` |
