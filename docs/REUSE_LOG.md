# REUSE_LOG — Nguồn gốc code lấy từ repo nền

> Repo nền: Hắc Long RPG (`reference/rpg-game/`), commit **`5c514b7512183d714afb1d35ad310fa4a62f2a5d`** (`reference/COMMIT`). Chủ repo cho phép toàn quyền dùng lại code (KB_BASE_REPO §0.1).
> Mức: REUSE (gần như nguyên) / ADAPT (giữ khung, sửa) / REWRITE (chỉ học ý tưởng) / SKIP.
> **Trạng thái M1:** đã copy/sửa các dòng ghi `đã làm (M1)`. **Trạng thái M0:** chưa copy file nào. Bảng dưới là kế hoạch đã chốt sau khi đọc source + test; cột "Trạng thái" đổi thành `đã copy (M#)` kèm commit của dự án khi làm thật.

| File nguồn (`reference/rpg-game/…`) | Đích | Mức | Lý do | Trạng thái |
|---|---|---|---|---|
| `mix.exs` | `mix.exs` | ADAPT | Đổi `:hac_long`→`:mu`; `pbkdf2_elixir`→`argon2_elixir`; bỏ alias seeds; giữ alias `test` tạo DB | đã làm (M1): `elixir ~> 1.15` (mix.lock cần ≥ 1.15), bỏ `dns_cluster` (1 node), bỏ alias seeds |
| `.formatter.exs` | `.formatter.exs` | REUSE | Không đổi | đã làm (M1): nguyên bản |
| `.gitignore`, `.dockerignore` | cùng tên | ADAPT | Thêm `assets_src/private/`, `priv/static/assets/icons/items/`, `priv/static/assets/icon_map.json`, `client/node_modules`, bundle JS | đã làm (M1, commit 2157c92) |
| `config/{config,dev,test,runtime}.exs` | cùng tên | ADAPT | Đổi namespace/DB name; bỏ world_boss/wander/event; thêm config game, Argon2 nhanh trong test | đã làm (M1): thêm `filter_parameters` (ticket/token/password), Argon2 nhanh trong test; bỏ world_boss/time_of_day/LiveView salt |
| `test/support/{conn_case,data_case,channel_case}.ex` | `test/support/` | ADAPT | Đổi namespace; `create_user` → tạo account + DK | đã làm (M1): `create_account`/`create_character`, `connect_account` bằng ticket thật |
| `lib/hac_long/application.ex` | `lib/mu/application.ex` | ADAPT | Giữ Repo/PubSub/RateLimit/Registry/DynamicSupervisor; thêm WsTicket, MapServer Lorencia; bỏ Chat/WorldBoss/Party/Trade | đã làm (M1): Repo, PubSub, RateLimit, WsTicket, Registry + SessionSupervisor. MapServer thêm ở M2 |
| `lib/hac_long/repo.ex` | `lib/mu/repo.ex` | REUSE | Đổi namespace | đã làm (M1) |
| `lib/hac_long/rate_limit.ex` | `lib/mu/rate_limit.ex` | REUSE | ETS cửa sổ cố định, đủ dùng | đã làm (M1): nguyên bản, đổi namespace; khóa theo act ở `Mu.Game.Commands` |
| `lib/hac_long_web/remote_ip.ex` + `test/hac_long_web/remote_ip_test.exs` | `lib/mu_web/remote_ip.ex` + test | REUSE | Không cần đổi | đã làm (M1): nguyên bản, đổi namespace |
| `lib/hac_long_web/{endpoint,router,telemetry}.ex`, `lib/hac_long_web.ex`, `controllers/error_json.ex` (+ test) | `lib/mu_web/…` | ADAPT | Route theo KB_TECHNICAL §4; không log query string | đã làm (M1): bỏ session cookie/MethodOverride/LiveView; route §4 + plug `MuWeb.Auth` |
| `lib/hac_long/accounts.ex`, `accounts/{user,user_token}.ex` + `test/hac_long/accounts_test.exs` | `lib/mu/accounts.ex`, `accounts/{account,access_token}.ex` | ADAPT | Bảng `accounts` UUID (§9), Argon2id, token băm TTL ngắn; bỏ ban/mute | đã làm (M1): `accounts` UUID + Argon2id; `access_tokens` có `expires_at` (TTL config) |
| `controllers/auth_controller.ex` + test | `lib/mu_web/controllers/auth_controller.ex` | ADAPT | Giữ rate-limit login/register; thêm `/ws-ticket`; bỏ đổi mật khẩu, đăng xuất mọi thiết bị | đã làm (M1): register/login/logout/ws-ticket; ngưỡng đọc từ config |
| `channels/user_socket.ex` | `lib/mu_web/channels/user_socket.ex` | ADAPT | Vào bằng WS ticket 1 lần | đã làm (M1): `connect` bằng `ticket` |
| `channels/game_channel.ex` + test | `lib/mu_web/channels/game_channel.ex` | ADAPT | Giữ khung join/attach/subscribe/push; protocol §5 (`cmd` + `rid`, mã lỗi); bỏ kênh phụ | M1: khung join (clientVersion, characterId, single login) + phong bì `cmd`/rate-limit; act xử lý ở M2–M4 |
| `lib/hac_long/release.ex`, `rel/overlays/bin/start` | `lib/mu/release.ex`, `rel/overlays/bin/start` | ADAPT | Giữ `migrate/0`; bỏ `admin/2` | đã làm (M1): bỏ `admin/2` |
| `Dockerfile`, `docker-compose.yml`, `docker-compose.caddy.yml`, `deploy/Caddyfile`, `.env.example` | gốc repo | ADAPT | Đổi tên app; build client bằng npm; dockerignore asset MU-derived | đã làm (M1): đổi tên; Caddy không bật access log (ticket). Tầng build client thêm ở M5. Chưa build image được trong cloud (Docker Hub bị chặn); đã kiểm `mix release` + migrate |
| `.github/workflows/ci.yml` | `.github/workflows/ci.yml` | ADAPT | Thêm job client + kiểm `git ls-files` đường dẫn MU-derived | đã làm (M1): thêm job `private-assets` (`git ls-files`), `mix test --warnings-as-errors`. Job client thêm ở M5 |
| `lib/hac_long/game/data.ex` | `lib/mu/game/data.ex` | ADAPT | Giữ đọc JSON lúc biên dịch; tách file theo loại | đã làm (M1): `Mu.Game.Data` (classes) + `Mu.Game.Config`; kiểm `sourceType/version/verified` lúc biên dịch |
| `lib/hac_long/game/names.ex` | `lib/mu/game/names.ex` | ADAPT | Luật tên ASCII 4–10 | đã làm (M1): luật §18 + từ cấm từ config |
| `lib/hac_long/game/rng.ex` | `lib/mu/game/rng.ex` | ADAPT | Thêm seed | kế hoạch M3 |
| `lib/hac_long/game/session.ex` | `lib/mu/game/session.ex` | ADAPT | Giữ khung process/account, token bucket, flush khi tắt; thêm `rid`, single login, ghi debounce | M1: khung (Registry, call thử lại, monitor tab, idle stop) + single login. Phần còn lại M2–M4 |
| `lib/hac_long/game/commands.ex` + test | `lib/mu/game/commands.ex` | REWRITE | Act §5 khác hoàn toàn; giữ ý validate→engine, ép kiểu `int/1` | kế hoạch M2–M4 |
| `lib/hac_long/game/{characters,character}.ex` | `lib/mu/game/{characters,character}.ex` | REWRITE | Schema §9, không blob | đã làm (M1): viết lại theo §9 (tạo DK, đọc, view) |
| `lib/hac_long/game/engine.ex` + `test/hac_long/game/engine_test.exs` | `lib/mu/game/engine.ex`, `inventory.ex` | REWRITE | Real-time, công thức KB; giữ phong cách hàm thuần + Rng | kế hoạch M3–M4 |
| `lib/hac_long/world/map_server.ex` | `lib/mu/world/map_server.ex` | REWRITE | Tick 20 Hz, AI, snapshot delta; giữ khung Registry/monitor/PubSub | kế hoạch M2–M3 |
| `lib/hac_long/world/maps.ex` + `test/hac_long/world_test.exs` (test bản đồ) | `lib/mu/world/maps.ex` + test | ADAPT | Định dạng KB_TECHNICAL §8; giữ test spawn hợp lệ | kế hoạch M2 |
| `lib/hac_long/world.ex` | `lib/mu/world/movement.ex` | REWRITE | `move_to` + A* thay bước 4 hướng | kế hoạch M2 |
| `lib/hac_long/game/simulator.ex`, `lib/mix/tasks/hac_long.simulate.ex` + test | `lib/mu/game/simulator.ex`, `lib/mix/tasks/mu.simulate.ex` | ADAPT | Giữ khung báo cáo, viết lại vòng mô phỏng | kế hoạch M3 |
| `priv/static/js/net.js` | `client/src/net/` (TS) | ADAPT | Ticket + `rid`; giữ tự kết nối lại | kế hoạch M5 |
| `priv/static/js/sound.js` | `client/src/audio/sound.ts` | REUSE | Web Audio tổng hợp | kế hoạch M5 |
| `priv/static/assets/{monsters/spider,monsters/hero,npcs/merchant}.png`, `tiles/*.png` (DCSS, CC0) | `priv/static/assets/{sprites,tiles}/` | REUSE (asset bên thứ ba) | CC0; ghi `CREDITS.md` + `mapping.json`; đối chiếu danh sách license không rõ trước khi copy | kế hoạch M5 |
