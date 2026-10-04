# E2E và soak test — Hắc Long

Chạy trên **server thật** (database thật), mỗi kịch bản dùng tài khoản ngẫu nhiên nên chạy lại bao nhiêu lần cũng được.

## Chuẩn bị (một lần)

```bash
cd reference/rpg-game
mix ecto.setup                       # nếu chưa có database
mix run scripts/e2e_seed.exs         # tài khoản quản trị e2e_admin (dùng để tặng vàng / đồ cho nhân vật test)
TRUSTED_PROXIES=127.0.0.1 mix phx.server
```

`TRUSTED_PROXIES=127.0.0.1`: mỗi người chơi test gửi `X-Forwarded-For` riêng, không chạm giới hạn đăng ký 5 tài khoản / giờ / IP.

Playwright: máy đã có sẵn (`/opt/node-tools`, Chromium `/opt/pw-browsers/chromium`) thì không cần cài. Máy khác:
`cd e2e && npm install && npx playwright install chromium`.

## Chạy

```bash
node e2e/run.mjs                     # cả 5 kịch bản, in PASS / FAIL từng bước
node e2e/smoke.mjs                   # từng kịch bản
HL_SHOTS_DOCS=1 node e2e/run.mjs     # chạy xong chép ảnh chọn lọc sang docs/screenshots (ảnh trong tài liệu)
SOAK_BOTS=30 SOAK_MINUTES=10 node e2e/soak.mjs   # soak
mix hac_long.audit                   # sau soak: vàng khớp nhật ký, không trùng đồ hiếm
```

Tham số: `node e2e/<kịch bản>.mjs [url] [thư_mục_ảnh]` (mặc định `http://localhost:4000`, `e2e/screenshots/`, thư mục ảnh
không vào git).

## Kịch bản

| File | Kiểm |
|---|---|
| `smoke.mjs` | tạo 4 lớp (chỉ số gốc, máu / MP), ra Làng → Rừng Mê, đánh quái, mua / bán ở Bà Lang, nghỉ trọ, cộng điểm (gom lệnh), các tab |
| `social.mjs` | 2 người: tổ đội (bấm Vào tổ đội), bạn bè + tin riêng, chat thế giới, giao dịch (bấm trên bảng giao dịch: vàng + đồ), chợ (rao, mua, nhận tiền qua thư) |
| `progress.mjs` | nhiệm vụ Trưởng Làng (nhận → hạ 5 Dơi Hang → trả), Bảng Tin, ép đồ +1, mua rương, Máy Hỗn Nguyên |
| `admin.mjs` | tab Quản trị: tra cứu, cấm / bỏ cấm chat, gửi quà qua thư, cộng vàng, nhật ký vàng, kiểm tra vàng |
| `mobile.mjs` | 360 × 740: các tab, NPC, trận đánh không tràn ngang; nút đủ lớn để chạm |
| `soak.mjs` | N bot WebSocket (không cần trình duyệt): đi, đánh, chat, xem chợ; đo p50 / p95 / max, lỗi, mất kết nối, bộ nhớ |

Mọi kịch bản Playwright còn kiểm **không có lỗi JS** trên trang.

## Hook test `window.__hl`

Chỉ có khi mở trang với `?test=1` (`ui.js`, `testHook`). Kịch bản đọc trạng thái thay vì đoán chữ trên màn hình:

- `__hl.player()` trạng thái nhân vật (bản sao), `__hl.ui()` tab, NPC đang mở, hộp thoại, đang chờ server, tổ đội, giao dịch;
- `__hl.world()` quái / người trên bản đồ, `__hl.npcs(map)`;
- `__hl.walkTo(x, y)` đi như chạm vào bản đồ (tìm đường của client), `__hl.step(dir)`, `__hl.send(cmd)` gửi lệnh như bấm nút.

Hook không mở thêm quyền gì: server vẫn kiểm mọi lệnh như với người chơi thật.

## Viết kịch bản mới

Dùng `lib.mjs`: `newPlayer`, `adminSession` (`admin(op, tênNhânVật, payload)`), `travel(page, map)`, `meetNpc`, `engage`,
`fight`, `act(page, 'data-act' | selector)`, `send`, `shot`, `overflowX`, `reporter(tên)` (`check` / `done`).
