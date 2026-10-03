# RUN_LOCAL — Chạy MU Web trên máy anh

> Phase 1 (vertical slice). Game view vẽ bằng **Canvas 2D** (sprite/tile DCSS CC0); Phaser 3 để phase
> sau (`docs/BACKLOG.md`, DEC-53).

## 1. Cần có

| Công cụ | Bản đã kiểm |
|---|---|
| Elixir / Erlang | 1.17.3 / OTP 25 (≥ 1.15 do `mix.lock`) |
| PostgreSQL | 16 — user `postgres` / mật khẩu `postgres` trên `localhost` (đổi ở `config/dev.exs`) |
| Node.js | 22 (npm 10) |

## 2. Lần đầu

```bash
mix deps.get
mix setup                      # tạo DB, chạy migration, sinh icon_map.json (placeholder nếu chưa có icon)
cd client && npm install && npm run build && cd ..   # TypeScript → priv/static/js
mix phx.server
```

Mở http://localhost:4000 → **Đăng ký** → tạo nhân vật (4–10 chữ/số) → **Vào game**.

Sửa code client: `mix phx.server` tự biên dịch lại TypeScript (`client/watch.mjs`), chỉ cần tải lại trang.

## 3. Icon item thật (tùy chọn, KHÔNG commit)

Đặt icon MU-derived vào `assets_src/private/item_icons/` (tên `item_{group}_{index}[_{bucket}].png`,
xem `KB_ASSETS §2.2`) hoặc đặt `ITEM_ICONS_DIR=/đường/dẫn`, rồi:

```bash
mix mu.icons.index             # chép icon dùng được + sinh icon_map.json, ghi docs/ICON_REPORT.md
```

Thư mục input và output đều nằm trong `.gitignore`/`.dockerignore`. Thiếu icon → placeholder, không lỗi.

## 4. Thao tác trong game (KB_GAME_DESIGN §19)

| Việc | Desktop | Mobile |
|---|---|---|
| Đi | click ô đất | tap ô đất |
| Đánh quái | click Spider → `Tấn công thường` (tự đánh tới khi chết) / `Twisting Slash` (cấp 10) | tap Spider → menu |
| Shop | click NPC vàng `Potion Merchant` trong thị trấn (tự đi tới) | tap NPC |
| Nhặt đồ | click đồ dưới đất hoặc `Space` (trong 1 ô) | nút ✋ |
| Potion | `Q` (HP) / `W` (MP) | nút 🧪 / 💧 |
| Panel | `C` Nhân vật, `I` Túi đồ, tab 🔔 Thông báo, ☰ Menu; `Esc` đóng | dock dưới; bấm lại tab để đóng |

Nhân vật mới có 0 Zen (G8): giết Spider lấy Zen rồi mua potion (100 Zen). Cẩn thận vùng Spider phía
đông: nhiều con cùng lao vào (G26).

## 5. Kiểm tra bằng mắt (cần anh làm — M6 đánh dấu "cần kiểm tra local")

- [ ] Desktop ≥ 1280px: HUD (tên map + tọa độ, HP/MP, `Q ×n`/`W ×n`), thanh EXP, dock 4 tab
- [ ] Mobile ≥ 360px (DevTools → thiết bị 360×740, hoặc điện thoại cùng mạng: sửa `ip` trong `config/dev.exs` thành `{0, 0, 0, 0}`): 3 nút nổi, panel full-screen, không tràn ngang
- [ ] 2 người chơi: mở 2 trình duyệt (một cửa sổ ẩn danh), 2 tài khoản → thấy nhau đi
- [ ] Reload trang giữa chừng → cấp, EXP, Zen, đồ, vị trí còn nguyên
- [ ] Mở cùng tài khoản ở 2 tab → tab cũ bị đá về màn nhân vật

## 6. Test

```bash
mix test                                   # server (ExUnit), cần Postgres
cd client && npm test                      # logic client (node --test)
node client/e2e/smoke.mjs http://localhost:4000 docs/screenshots   # E2E (server phải đang chạy)
```

E2E dùng Playwright + Chromium. Máy anh: `npm i -g playwright && npx playwright install chromium`, rồi
`PLAYWRIGHT_MODULE=$(npm root -g)/playwright/index.mjs CHROMIUM_PATH= node client/e2e/smoke.mjs`.

Soak 1 giờ (M6 — cloud chỉ chạy 10 phút, xem `docs/ACCEPTANCE.md §2`):

```bash
epmd -daemon
TRUSTED_PROXIES=127.0.0.1 elixir --sname mu -S mix phx.server &      # bot giả lập IP khác nhau
node client/e2e/soak.mjs http://localhost:4000 20 60 > soak_bots.log &   # 20 bot × 60 phút
elixir --sname probe scripts/soak_probe.exs mu@$(hostname -s) 61 60 > soak_probe.log
```

Đạt nếu: tick ~1 200/phút, `max_drift` không tăng dần, hàng đợi MapServer ~0, RAM không tăng dần,
không có `[error]` trong log server, bot không bị đóng WebSocket.

Mô phỏng cân bằng: `mix mu.simulate --runs 100` (thêm `--gear full` để so khi mặc đủ đồ).

## 7. Docker

```bash
cp .env.example .env    # sửa mật khẩu, SECRET_KEY_BASE, PHX_HOST
docker compose up -d --build
```

Image không chứa icon MU-derived (mọi item dùng placeholder).
