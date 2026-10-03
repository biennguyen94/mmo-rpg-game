# DECISIONS — Quyết định nhỏ (KB không nói tới)

> Theo `CLAUDE.md` §9: quyết định nhỏ, thuần kỹ thuật, em tự quyết và ghi ở đây. Quyết định đụng gameplay/schema/protocol nằm ở `docs/OPEN_QUESTIONS.md` chờ anh.

| # | Ngày | Quyết định | Lý do |
|---|---|---|---|
| DEC-1 | 2026-10-02 | Client TypeScript build bằng **esbuild qua npm** (`client/` → `priv/static/js/app.js`). Không dùng gói `tailwind`/`esbuild` của Phoenix (tải binary từ GitHub Releases) | Proxy cloud chặn tải binary từ GitHub Releases; `npm install esbuild` (kèm `@esbuild/linux-x64` từ registry.npmjs.org) đã thử chạy được trong phiên này. esbuild nhẹ hơn Vite và đủ cho một bundle |
| DEC-2 | 2026-10-02 | Mã nguồn client đặt ở `client/` (không dùng `assets/` kiểu Phoenix) | `assets_src/` của KB dành cho asset nguồn (Tiled/Aseprite/private); tách tên tránh nhầm |
| DEC-3 | 2026-10-02 | Ghim `phaser@3.90.0` và `phoenix@1.7.24` (npm) | Prompt chốt Phaser 3 nhưng npm mặc định đã là 4.x; client JS Phoenix cùng bản với server |
| DEC-4 | 2026-10-02 | Không dùng generator `mix phx.new`; dựng khung bằng cách chép + đổi tên từ repo nền | Repo nền đã là Phoenix 1.7 đúng cấu hình (JSON + Channels); không cần archive `phx_new` |
| DEC-5 | 2026-10-02 | ULID tự viết (thuần Elixir, ~30 dòng, có test) thay vì gói `ecto_ulid` | Gói `ecto_ulid` lâu không cập nhật; cột `serial CHAR(26)` chỉ cần chuỗi Crockford base32 |
| DEC-6 | 2026-10-02 | Hash commit repo nền đọc từ `reference/COMMIT` | Prompt nhắc `reference/rpg-game/COMMIT` nhưng file nằm ở `reference/COMMIT`; không sửa `reference/` |
| DEC-7 | 2026-10-02 | Commit hook SessionStart (`.claude/settings.json`, `scripts/cloud_session_start.sh`) đúng nội dung `PROMPT_PHASE1_CLOUD §A3` | E4: Postgres tắt mỗi lần vào phiên; file nằm trong repo, không đổi cấu hình môi trường |
| DEC-8 | 2026-10-02 | Thêm `scripts/cloud_env_setup.sh`: bản setup script để anh dán vào môi trường cloud (em không chạy) | Gom E1–E4 thành một script: OTP 25 từ apt + Elixir 1.17.3 từ builds.hex.pm + mật khẩu Postgres |
| DEC-9 | 2026-10-03 | `mix.exs`: `elixir: "~> 1.15"`; bỏ `dns_cluster` | `mix.lock` (ecto_sql 3.14, postgrex 0.22, plug 1.20) cần ≥ 1.15; Phase 1 chạy 1 node |
| DEC-10 | 2026-10-03 | Lỗi HTTP dạng `{error: MÃ, message: "tiếng Việt"}`. Mã chỉ dùng cho HTTP: `VALIDATION`, `INVALID_CREDENTIALS`, `UNAUTHORIZED`, `RATE_LIMITED`, `INVALID_NAME`, `INVALID_CLASS`, `NAME_TAKEN`, `CHARACTER_LIMIT` | KB §5 chỉ định nghĩa mã lỗi của WebSocket; HTTP (P1) cần mã để client hiển thị. Không đổi protocol WebSocket |
| DEC-11 | 2026-10-03 | Join `"game"` thất bại trả `{error: "FORBIDDEN", reason: "clientVersion" \| "character" \| "params"}` | §5 không định nghĩa lỗi join; dùng mã có sẵn `FORBIDDEN` (P7), thêm `reason` để client báo đúng (cập nhật bản / chọn lại nhân vật) |
| DEC-12 | 2026-10-03 | Thêm `POST /logout` (thu hồi access token đang dùng) | §4 yêu cầu token "thu hồi được"; endpoint là cách tối thiểu để client dùng |
| DEC-13 | 2026-10-03 | Rate-limit `POST /ws-ticket` 20/phút/tài khoản, `POST /characters` 10/phút/tài khoản (trong `config.json` `rateLimit`) | Chống spam, không phải số gameplay; P8 không nói tới hai endpoint này |
| DEC-14 | 2026-10-03 | Single login: tab cũ nhận event `error {rid: null, error: "FORBIDDEN"}` rồi kênh đóng (`{:shutdown, :kicked}`) | §4 "login mới kick session cũ"; §5 không có event riêng cho kick. Kick ở mức kênh (không ngắt socket theo tài khoản vì sẽ ngắt cả tab mới) |
| DEC-15 | 2026-10-03 | "Vượt rate-limit liên tục" = chuỗi vi phạm, hai vi phạm cách nhau ≤ cửa sổ của nhóm act; chuỗi ≥ `rateLimit.cmd.kickAfterMs` (5s) → đóng kênh | Diễn giải P8; hàm thuần `Mu.Game.Commands.violation/3`, có test |
| DEC-16 | 2026-10-03 | Act hợp lệ (§5) nhưng chưa làm ở milestone hiện tại → `FORBIDDEN` ("feature tắt") | Mã có sẵn trong §5; M2–M4 thay dần |
| DEC-17 | 2026-10-03 | Toạ độ xuất phát tạm `newCharacter {mapId: lorencia, x: 32, y: 32}` trong `config.json` | Map Lorencia làm ở M2; M2 chuyển sang spawn của map JSON và test nằm trong safe zone |
| DEC-18 | 2026-10-03 | Thêm index `characters_account_id` (ngoài §9) | Chỉ là index tra theo tài khoản, không đổi dữ liệu/ràng buộc |
| DEC-19 | 2026-10-03 | Migration viết bằng SQL thô đúng như §9 | Giữ nguyên từng CHECK, partial index, kiểu cột (`CHAR(26)`, `TIMESTAMPTZ`) |
| DEC-20 | 2026-10-03 | Session tự tắt sau 1 phút không còn tab | M1 chưa có trạng thái chưa lưu; M2 xem lại cùng `logoutInCombatSeconds` (G21) |
