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
