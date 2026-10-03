# ACCEPTANCE — Nghiệm thu Phase 1 (M6)

> Danh sách mục: `docs/kb/KB_00_RULES.md §7` (`acceptance`). Ngày chạy: 2026-10-03, môi trường
> Claude Code cloud (Ubuntu 24.04, 4 vCPU, Elixir 1.17.3 / OTP 25, Postgres 16, Chromium 141).
> Bằng chứng có 3 lớp: **ExUnit** (server, `mix test`), **E2E** trình duyệt thật
> (`client/e2e/acceptance.mjs`, `client/e2e/smoke.mjs`: Playwright + Chromium headless trên
> server thật), **soak** (`client/e2e/soak.mjs`). Ảnh: `docs/screenshots/`.

## 1. Bảng nghiệm thu

| # | Mục (KB_00 §7) | Kết quả | Bằng chứng |
|---|---|---|---|
| 1 | login OK | ✅ PASS | ExUnit `auth_controller_test.exs` (đúng/sai mật khẩu, rate-limit, token hết hạn/thu hồi), `ws_ticket_test.exs`; E2E acceptance [1], smoke (đăng ký → đăng nhập lại ở mobile) |
| 2 | tạo DK OK | ✅ PASS | ExUnit `characters_test.exs` "tạo DK đúng chỉ số" (STR 28/AGI 20/VIT 25/ENE 10, HP 185, MP 30), luật tên §18, 1 nhân vật/tài khoản; E2E acceptance [2] (qua UI); ảnh `desktop-01-create.png` |
| 3 | vào Lorencia OK | ✅ PASS | ExUnit `world_channel_test.exs` "join: trả map, entityId…", `maps_test.exs` (spawn trong safe zone); E2E [3]; ảnh `desktop-02-world.png` |
| 4 | click-to-move OK | ✅ PASS | ExUnit `map_server_test.exs` (A*, 5 ô/s, chéo ×1.414, tường/nước/NPC bị từ chối), `pathfinding_test.exs` (so Dijkstra); E2E [4] (bấm ô → đi qua cổng thị trấn) |
| 5 | click-to-attack Spider OK | ✅ PASS | ExUnit `combat_test.exs` "đánh thường…cooldown; tầm", `combat_channel_test.exs` "attack qua kênh"; E2E [5] (bấm Spider → context menu → tự đánh); ảnh `desktop-09-ctxmenu.png`, `desktop-10-fight.png` |
| 6 | Spider chết + respawn OK | ✅ PASS | ExUnit `combat_test.exs` "Spider chết…hồi sinh sau 8s" (đúng 160 tick); E2E [6] |
| 7 | nhận EXP + lên level OK | ✅ PASS | ExUnit `engine_test.exs` (EXP/level số tính tay, maxLevel 10), `combat_channel_test.exs` "10 con → lên cấp 2"; E2E [7] (lên cấp 3→4 + thông báo "Level 3 → 4"); ảnh `accept-notices.png` |
| 8 | cộng stat OK | ✅ PASS | ExUnit `engine_test.exs` alloc, `combat_channel_test.exs` alloc (DB + chặn vượt điểm); E2E [8] (bấm [+] 3 lần → một `alloc` 3 điểm); ảnh `accept-character.png` |
| 9 | nhặt item OK | ✅ PASS | ExUnit `items_test.exs` (serial ULID, gộp stack, dupe bị chặn), `item_channel_test.exs` (tầm 1, loot protect, túi đầy trả về đất, 2 người nhặt 1 món); E2E [9] (Space) |
| 10 | equip item OK | ✅ PASS | ExUnit `inventory_test.exs` (DK cấp 1 mặc được mỗi slot), `items_test.exs` (đổi chỗ, yêu cầu), `item_channel_test.exs` (chỉ số mới vào combat); E2E [10] (kiếm/giáp/nhẫn qua UI, tháo qua tooltip); ảnh `accept-equip.png` |
| 11 | mỗi item hiển thị một icon (thật nếu có trong `icon_map.json`, chưa có thì placeholder + cảnh báo build) | ✅ PASS (placeholder) | ExUnit `icon_index_test.exs` (fallback §4.3, input rỗng exit 0); `docs/ICON_REPORT.md` (10/10 placeholder, cảnh báo); E2E [11] (ảnh tải được). **Icon thật: cần anh đặt file local** (Q11) |
| 12 | mua potion từ NPC OK | ✅ PASS | ExUnit `items_test.exs` mua/thiếu Zen/túi đầy, `item_channel_test.exs` (tầm NPC 3 ô, `rid` lặp không mua 2 lần); E2E [12] (mua −100 Zen, bán +750); ảnh `accept-shop.png`, `desktop-06-shop.png` |
| 13 | dùng potion OK | ✅ PASS | ExUnit `item_channel_test.exs` (hồi 50, cooldown 1 s, không vượt max); E2E [13] (**trước khi mặc áo**, Q14: HP 100 → 150) |
| 14 | UI dock + panel Character / Inventory / Thông báo / Shop trên desktop (≥1280px) và mobile (≥360px) | ⚠️ PASS tự động, **cần anh kiểm tra local** | E2E smoke 24/24 (1280×800 và 360×740: panel, dock, submenu, nút mobile, không tràn ngang); 13 ảnh `desktop-*.png`, `mobile-*.png`. Game view: **Canvas 2D** (chính thức cho Phase 1, DEC-53) với sprite/tile DCSS CC0 |
| 15 | reload page → character state còn nguyên | ✅ PASS | ExUnit `world_channel_test.exs` / `combat_channel_test.exs` / `item_channel_test.exs` (reload + restart Session đọc lại DB); E2E [15] (cấp, EXP, Zen, stat, đồ giống hệt sau reload) |
| 16 | 2 player login cùng lúc thấy nhau di chuyển | ✅ PASS | ExUnit `world_channel_test.exs` "2 người chơi…"; E2E [16] (2 trình duyệt, B thấy A đi tới đúng ô); ảnh `accept-two-players.png`; E2E 19/19 cũng qua khi server đang có 20 bot soak |

Thêm: `test/mu/phase1_scope_test.exs` — dữ liệu khớp đúng JSON scope (1 class, 1 map, 1 quái,
1 NPC, 10 item, 2 skill, maxLevel 10) và mọi feature flag ngoài Phase 1 tắt.

## 2. Soak test

Chạy **10 phút** trong cloud (anh yêu cầu rút từ 20 xuống 10; bản 1 giờ chạy local theo
`docs/RUN_LOCAL.md`): **20 bot** WebSocket (`client/e2e/soak.mjs`) đi lang thang, đánh Spider, uống
potion, mua potion ở NPC; cùng lúc chạy lại 2 bộ E2E (thêm 2–3 người chơi). Server đo từ node Erlang
khác mỗi phút (`scripts/soak_probe.exs`). 01:10:42 → 01:20:02 UTC.

| Chỉ số | Kết quả |
|---|---|
| Nhịp mô phỏng | 1 200 tick/phút mọi phút; 01:11:42 → 01:19:42: **9 601 tick / 480 s = 20,0 Hz** |
| Trễ tick lớn nhất (`max_drift`) | **47 ms** (giữ nguyên từ phút thứ 2, không tăng dần) |
| Hàng đợi MapServer | **0** ở mọi lần đo |
| Bộ nhớ VM | 46–49 MB, không tăng dần; state MapServer 140–674 KB; số process ổn định 575 (+ phiên E2E) |
| Snapshot tới client (bot 0) | p50 **100 ms**, p99 **102 ms**, max 201 ms (snapshot chỉ gửi khi có thay đổi) |
| Kết nối | 20/20 bot online suốt; **0** WebSocket bị đóng bất thường |
| Lệnh | 7 777 `cmd`, 96,3 % ok. Lỗi là lỗi luật hợp lệ của bot đơn giản: `INVALID_TARGET` 176 (quái vừa chết/bị người khác hạ), `OUT_OF_RANGE` 69, `FORBIDDEN` 38 (lệnh lúc đang chết), `COOLDOWN` 1, `NOT_ENOUGH_ZEN` 1 |
| Gameplay | 20 lần lên cấp, 14 lần chết + hồi sinh, 24 lần mua potion, 18 lần dùng potion |
| Log server | **0** `[error]`, **0** `[warning]` |
| E2E chạy song song | smoke 24/24, acceptance 19/19 |

Ghi chú đo của lần chạy này (đã sửa trong `soak.mjs` sau đó, thử lại 1 phút × 3 bot):
cột "giết" trong log cũ đếm trùng khi nhiều bot cùng đánh một con, và HP của bot chỉ cập nhật theo
event `player` nên bot uống potion muộn (nhiều lần chết hơn thực tế). Không ảnh hưởng số đo server.

## 3. Cân bằng lệch / cần anh quyết

| # | Vấn đề | Số liệu | Đề xuất |
|---|---|---|---|
| Q14 | Một món áo (Leather Armor, def +10 → tổng 15) làm Spider (8–14) gần như vô hại | Simulator: nhận 7.56 HP/con khi không đồ → **0.73 HP/con** khi đủ đồ t0; tới cấp 10 dùng 149 → 2 potion. E2E: mặc giáp đánh 8 con không cần potion | Chấp nhận cho slice (KB) hoặc giảm `defense` Leather / tăng `damageMax` Spider |
| G26 | Bầy Spider cùng aggro (vùng 17×21, 10 con, `aggroRange` 5) | Chạy thật: đánh 1 con thì **~6 con lao vào**, mất ~150/185 HP cho 1 con (không đồ) | (a) `aggroRange` 3, (b) giãn/chia vùng sinh, (c) giữ (hiện tại) |
| E-1 | Kinh tế potion khi không đồ | Zen/con 5–15 (TB 10) vs potion 100 → 10 con/potion; không đồ cần ~1 potion/6.6 con. Simulator tới cấp 10: cần 14 900 Zen potion, kiếm 11 126 Zen | Đủ khi bán đồ rơi (TB 232 món/1111 con); xem lại khi chỉnh Q14/G26 |
| E-2 | `twisting_slash` cần cấp 10 = `maxLevel` Phase 1 | Chỉ dùng được ở cấp cuối (G7) | Giữ (KB), hoặc hạ `requiredLevel` để slice có skill |
| E-3 | Tốc độ lên cấp | 10 / 171 / 1111 Spider tới cấp 2/5/10; ~130 phút (không đồ) / ~75 phút (đủ đồ) tới cấp 10, đi bộ 2 s/con | Theo KB (G25 lệch ≤ 1 con do làm tròn) |
| E-4 | Tỉ lệ trúng chạm trần sớm | DK trúng Spider 92% ở cấp 1, 95% (trần) từ cấp ~2; Spider trúng DK 62.5% (giảm khi cộng AGI) | Theo công thức §5 |
| E-5 | MP potion chỉ có qua drop; DK chỉ tốn MP cho Twisting Slash (cấp 10) | MP gần như không dùng ở Phase 1 | Theo KB |

## 4. Chưa đạt / lệch còn lại

| Mục | Trạng thái |
|---|---|
| Game view bằng **Phaser 3** | ↪️ Chuyển sang phase sau (anh chọn b, DEC-53): `registry.npmjs.org` bị gateway chặn. Phase 1 dùng Canvas 2D; kế hoạch chuyển: `docs/BACKLOG.md` §1 |
| Sprite DCSS (CC0) | ✅ Đã dùng (E8 xong): Spider, NPC, thân DK, 7 tile Lorencia — đối chiếu license từng file (`CREDITS.md`, `assets/mapping.json`) |
| Asset §6.1 (DK 6 animation × 4 hướng, effect, BGM) | ❌ DK chỉ có 1 khung tĩnh (DCSS `human_m`, không vẽ trang bị), chưa có animation/effect/BGM; 7 SFX Web Audio (M5-3) |
| Icon item thật | Chờ anh (Q11/A6); pipeline sẵn, input rỗng → placeholder |
| E6 `items_raw.json` | Chưa có file: 1 test KB_ITEM_REFERENCE §6 đang `@tag :skip` |
| Soak 1 giờ | Cloud chạy 10 phút (theo yêu cầu); bản 1 giờ: anh chạy local (`docs/RUN_LOCAL.md` §6, lệnh ở §5 dưới) |
| Docker image | Chưa build được trong cloud (Docker Hub bị chặn); đã kiểm `mix release` + migrate |

## 5. Chạy lại

```bash
mix test                                              # ExUnit
(cd client && npm test)                               # logic client
mix phx.server &                                      # rồi:
node client/e2e/smoke.mjs http://localhost:4000 docs/screenshots
node client/e2e/acceptance.mjs http://localhost:4000 docs/screenshots   # cần `mix run scripts/e2e_seed.exs`
node client/e2e/classes.mjs http://localhost:4000 docs/screenshots      # Phase 2 (P2-M2): tạo DW/ELF, Elf bắn xa
node client/e2e/skills.mjs http://localhost:4000 docs/screenshots       # Phase 2 (P2-M3): cần server chạy với TRUSTED_PROXIES=127.0.0.1
# soak: server với TRUSTED_PROXIES=127.0.0.1 và tên node để probe
TRUSTED_PROXIES=127.0.0.1 elixir --sname mu -S mix phx.server &
node client/e2e/soak.mjs http://localhost:4000 20 60 &      # 20 bot × 60 phút
elixir --sname probe scripts/soak_probe.exs mu@$(hostname -s) 61 60
```
