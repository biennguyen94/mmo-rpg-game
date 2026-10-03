# ACCEPTANCE_PHASE2 — Nghiệm thu Phase 2 "Core" (P2-M7)

> **Danh sách nghiệm thu = P2-15** (em soạn theo scope `KB_00_RULES §7` Phase 2, anh cho làm luôn
> 2026-10-03; KB chỉ có danh sách cho Phase 1). Ngày chạy: 2026-10-03, môi trường Claude Code cloud
> (4 vCPU, Elixir 1.17.3 / OTP 25, Postgres 16, Chromium). Bằng chứng 3 lớp như Phase 1:
> **ExUnit** (`mix test`: 247 test, 0 lỗi), **E2E** trình duyệt thật trên server thật (7 bộ trong
> `client/e2e/`), **soak** 20 bot. Nghiệm thu Phase 1 (16 mục) xem `docs/ACCEPTANCE.md` — đã chạy lại,
> vẫn xanh (mục 17).

## 1. Danh sách nghiệm thu P2-15 và kết quả

| # | Mục (scope Phase 2) | Kết quả | Bằng chứng |
|---|---|---|---|
| 1 | **DW, Elf**: tạo nhân vật chọn class DK / DW / ELF; chỉ số cấp 1 đúng `KB_CONFIG §2` + `§4.1`; đồ khởi đầu (DW gậy, Elf cung) | ✅ PASS | ExUnit `characters_test.exs` (HP/MP/sát thương/thủ/tầm từng class); E2E `classes.mjs` 6/6 (màn chọn class có hình, tạo ELF/DW qua UI); ảnh `p2-create-class.png` |
| 2 | **Vũ khí theo class**: cung đánh xa tầm 5, cung hai tay khóa khiên, đồ đúng class | ✅ PASS | ExUnit `items_test.exs` (hai tay, Pad/Vine sai class), `combat_channel_test.exs` (Elf bắn từ 5 ô, DK tay không 1 ô); E2E `classes.mjs` (Elf bắn trúng Spider từ ≥ 2 ô); ảnh `p2-elf-ranged.png` |
| 3 | **Inventory**: lưới 8×8, chuyển / hoán đổi / gộp stack, tách stack, vứt xuống đất (hỏi xác nhận), nhặt lại đúng serial + thuộc tính | ✅ PASS | ExUnit `inventory_test.exs`, `items_test.exs`, `item_channel_test.exs` (idempotent `rid`, người khác nhặt sau loot protect); E2E `acceptance.mjs` 5 mục P2; ảnh `p2-inventory-drop.png` |
| 4 | **Equipment**: mặc / tháo qua kéo thả và tooltip; đồ t1 cấp 10 | ✅ PASS | E2E `acceptance.mjs` [10] (giáp kéo vào ô ARMOR, kiếm/nhẫn qua tooltip); ExUnit `items_test.exs` |
| 5 | **Skills**: 12 skill theo class (đơn mục tiêu, AOE quanh mình / quanh mục tiêu / tại ô, Heal, Buff, Teleport), mana, cooldown, safe zone | ✅ PASS | ExUnit `skills_test.exs` 9 test (từng loại, buff hết hạn / mất khi chết, Greater Damage ở bước 3 §4), `combat_channel_test.exs` (buff → `player.view.buffs`, heal → `combat.heal`); E2E `skills.mjs` 7/7; ảnh `p2-elf-buff.png`, `p2-dw-teleport.png` |
| 6 | **Hồi MP** `energy/40` mỗi giây; MP cập nhật qua snapshot | ✅ PASS | ExUnit `skills_test.exs` "hồi MP…"; E2E `skills.mjs` "MP tự hồi" |
| 7 | **Monster AI**: 13 loại quái / 2 map, đuổi / đánh / quay về, quái đánh xa đứng cách 4 ô | ✅ PASS | ExUnit `monster_ai_test.exs`, `combat_test.exs` (sinh đúng vùng từng loại; **Lich đánh từ 4 ô không lại gần** — test thêm ở P2-M7); E2E `maps.mjs` (thấy đủ quái Noria, sprite tải được) |
| 8 | **Drop table**: mọi quái có bảng, Zen đúng bảng quái, đồ t1 chỉ từ quái cấp ≥ 10, potion vừa ở Noria | ✅ PASS | ExUnit `drops_test.exs` (tỉ lệ nhóm Spider 15 % / 6 %, 22 món; mọi quái); `combat_test.exs` (đồ rơi thuộc bảng) |
| 9 | **NPC / Shop**: 4 NPC (2 map), mua / bán, Weapon Merchant bán đồ t0 cả 3 class, MP potion ở Potion Merchant | ✅ PASS | ExUnit `item_channel_test.exs` (shop có HP + MP potion), `maps_test.exs` (mỗi NPC có shop đúng map); E2E `maps.mjs` (Weapon Merchant 19 món), `acceptance.mjs` [12]; ảnh `p2-weapon-merchant.png` |
| 10 | **Map Noria + cổng**: cổng hai chiều, thiếu cấp 10 bị chặn có thông báo, chuyển map lưu ngay, reload vào đúng map | ✅ PASS | ExUnit `maps_test.exs` (mọi map: khép kín, liên thông, cổng hai chiều), `portal_channel_test.exs` 3 test; E2E `maps.mjs` 8/8; ảnh `p2-noria-town.png`, `p2-noria-field.png` |
| 11 | **Death / respawn**: hồi sinh ở thị trấn của map đang đứng, mất buff | ✅ PASS | ExUnit `portal_channel_test.exs` (chết ở Noria → (31,50)), `skills_test.exs` (mất buff); soak: 185 lần chết + hồi sinh, 0 lỗi |
| 12 | **Pathfinding**: click-to-move trên 2 map, mọi ô đi được nối với điểm hồi sinh | ✅ PASS | ExUnit `maps_test.exs` (BFS mọi map), `pathfinding_test.exs`, `map_server_test.exs`; E2E (đi Lorencia → cổng → Noria → về) |
| 13 | **Chat**: NORMAL theo map, WHISPER theo tên, SYSTEM, PARTY/GUILD tắt, làm sạch + cắt 100 ký tự, lọc từ cấm, rate-limit, cấm chat | ✅ PASS | ExUnit `chat_test.exs`, `chat_channel_test.exs` 7 test; E2E `chat.mjs` 7/7 (chống XSS: thẻ HTML hiện như chữ); `mix mu.chat` chạy thử trên server thật; ảnh `p2-chat.png`, `p2-chat-mobile.png` |
| 14 | **Hộp thư hệ thống** (§19.10): thư chào mừng, badge, lọc, nhận quà (1 transaction, audit), xóa đã đọc | ✅ PASS | ExUnit `mail_test.exs` 5 test (hết hạn, túi đầy không nhận gì), `mail_channel_test.exs` (badge, idempotent `rid`); E2E `mail_map.mjs`; `mix mu.mail` chạy thử; ảnh `p2-mail.png` |
| 15 | **Panel Bản đồ** (§19.12): tab 🗺️ (dock 5 tab), phím M, minimap 256×256 (bạn / NPC / cổng / thị trấn), vị trí | ✅ PASS | E2E `mail_map.mjs` 10/10 (desktop + mobile 360px không tràn); ảnh `p2-map.png`, `p2-map-mobile.png` |
| 16 | **UI desktop (1280px) + mobile (360px)** cho mọi panel / khung mới | ⚠️ PASS tự động, **cần anh xem local** | E2E smoke 24/24 + mobile ở `chat.mjs`, `mail_map.mjs`; ảnh trong `docs/screenshots/` |
| 17 | **Không hồi quy Phase 1** (16 mục `KB_00 §7`) | ✅ PASS | E2E `acceptance.mjs` 24/24, `smoke.mjs` 24/24 (chạy lại ở mọi milestone P2-M1…M7, lần cuối khi đang soak) |
| 18 | **Cân bằng**: 3 class lên cấp 30 bằng quái ngang cấp, không chết (simulator) | ✅ PASS (có lưu ý §3) | `mix mu.simulate --runs 20 --monster auto --progress --skills` (§3) |
| 19 | **Tải**: 20 người chơi 10 phút trên server thật | ✅ PASS | Soak §2 |
| 20 | **Asset**: không file MU-derived trong git; sprite/tile bên thứ ba có license + hash | ✅ PASS | `git ls-files` (0 file `assets_src/private`, `icons/items`, `icon_map.json`); `mapping.json` + `CREDITS.md` (DCSS CC0, kiểm từng file); `docs/ICON_REPORT.md` (43/43 placeholder, cảnh báo, exit 0) |
| 21 | **Server-authoritative / protocol**: lệnh sai kiểu, sai chủ, ngoài tầm, cooldown, thiếu mana, rate-limit, `rid` lặp đều bị chặn đúng mã lỗi | ✅ PASS | ExUnit các `*_channel_test.exs` (act sai tham số, `NOT_OWNER`, `OUT_OF_RANGE`, `COOLDOWN`, `NO_MANA`, `RATE_LIMITED`, idempotent `rid`) |

## 2. Soak test (20 bot × 10 phút, 03:55 → 04:05 UTC)

Server `TRUSTED_PROXIES=127.0.0.1 elixir --sname mu -S mix phx.server`; 20 bot WebSocket
(`client/e2e/soak.mjs`) đi lang thang ở Lorencia (nay có 43 quái / 6 loại), đánh Spider, uống / mua
potion; đo server mỗi phút từ node khác (`scripts/soak_probe.exs`). **Cùng lúc chạy cả 7 bộ E2E**
(thêm 2–3 người chơi, có người đi sang Noria).

| Chỉ số | Kết quả | Phase 1 (để so) |
|---|---|---|
| Nhịp mô phỏng | **1 200 tick / phút mọi phút** (03:56:12 → 04:05:12: 10 801 tick / 540 s = **20,0 Hz**) | 20,0 Hz |
| `max_drift` | **35 ms** (22 ms tới phút 6, không tăng tiếp) | 47 ms |
| Hàng đợi MapServer | **0** mọi lần đo | 0 |
| RAM VM | 52–57 MB, không tăng dần; state MapServer 160–417 KB; process ổn định 580 | 46–49 MB |
| Snapshot tới bot | p50 **100 ms**, p99 **104 ms**, max 201 ms | 100 / 102 / 201 |
| Kết nối | 20/20 online suốt 10 phút, **0** WS đóng bất thường (19 "đóng" ở dòng tổng kết là bot tự đóng lúc hết giờ) | 0 |
| Lệnh | 6 600 `cmd`, 95,3 % ok; lỗi: `FORBIDDEN` 249 (lệnh khi đang chết), `INVALID_TARGET` 49, `OUT_OF_RANGE` 14 | 96,3 % |
| Log server | **0** `[error]`, **0** `[warning]` | 0 / 0 |
| E2E song song | smoke 24/24, acceptance 24/24, classes 6/6, skills 7/7, maps 8/8, chat 7/7, mail_map 10/10 | 2 bộ |
| Gameplay bot | 179 lần hạ quái, 9 lần lên cấp, **185 lần chết**, 7 potion, 7 lần mua | 14 lần chết |

**Phát hiện (§3, mục B-1):** bot cấp 1 chết gấp ~13 lần Phase 1. Bot đi lang thang "thiên về phía
đông" (vùng Spider) và bị quái mạnh ở vùng kề đánh: vùng Lich + Elite Bull Fighter bắt đầu ở y = 46,
chỉ cách mép nam vùng Spider (y = 44) **2 ô** (Lich đánh xa 4 ô, aggro 5); vùng Bull Fighter kết
thúc ở y = 19, cách mép bắc vùng Spider (y = 24) **5 ô** = đúng `aggroRange`. Server không lỗi; đây là
vấn đề bố trí map cho người mới.

## 3. Cân bằng (simulator 20 lần / class, `--monster auto --progress --skills`)

| Class (cộng điểm) | Cấp 10 | Cấp 20 | Cấp 30 | Potion tới cấp 30 | Chết | Zen tới cấp 30 |
|---|---|---|---|---|---|---|
| DK (balanced) | 298 con, 32,5 phút | 604 con, 71 phút | 907 con, 114,5 phút | 331 | 0 | ≈ 63 900 |
| DW (ene) | 26 phút | 50,5 phút | 72 phút | **731** | 0 | ≈ 64 100 |
| ELF (agi) | 26,5 phút | 52,5 phút | 76 phút | 262 | 0 | ≈ 63 900 |

Giả định simulator: đứng đánh quái ngang cấp (không thả diều), chỉ potion HP nhỏ, Elf không tự Heal.

## 4. Chờ anh quyết (không chặn nghiệm thu)

| # | Vấn đề | Đề xuất |
|---|---|---|
| B-1 | **Vùng tân thủ Lorencia không an toàn** (soak §2): Lich / Elite Bull Fighter sát mép nam vùng Spider (2 ô), Bull Fighter cách mép bắc 5 ô | (a) **khuyến nghị**: dời vùng Lich + EBF xuống y ≥ 51 và Bull Fighter lên y ≤ 15 (cách vùng Spider ≥ 7 ô > aggro 5 + tầm 4 của Lich); (b) giảm `aggroRange` quái Lorencia cấp ≥ 6 xuống 3; (c) giữ |
| B-2 | **DW thiếu Zen mua potion** (P2M4-4): 731 potion ≈ 73 100 Zen > 64 100 Zen kiếm được | Tăng Zen quái cấp ≥ 10 (vd. ×1,3) hoặc tỉ lệ rơi potion; xem lại sau khi chơi thử |
| B-3 | **Tiến bộ chủ yếu nhờ đồ** (P2M4-1): sát thương người chơi tăng chậm theo stat (KB §4.1) | Chấp nhận Phase 2 hoặc anh tăng hệ số §4.1 trong KB |
| B-4 | KB cần anh bổ sung: KB_TECHNICAL §5 (`map_change`, act/event hộp thư, trường mới), §9 (bảng `mail`) | P2M4-3, P2M6-1 |
| B-5 | Dữ liệu chờ anh: Item.txt (E6 — số + icon thật 33 món P2), danh sách từ cấm chat (P2M5-1), quà thư chào mừng (P2M6-2) | — |
| B-6 | Vẫn từ Phase 1: G26 (bầy Spider, đang giữ c), Q14, soak 1 giờ chạy local, kiểm tra UI bằng mắt (mục 16) | — |

## 5. Chạy lại

```bash
mix test && (cd client && npm test)
TRUSTED_PROXIES=127.0.0.1 elixir --sname mu -S mix phx.server &
for f in smoke acceptance classes skills maps chat mail_map; do node client/e2e/$f.mjs http://localhost:4000 docs/screenshots; done
node client/e2e/soak.mjs http://localhost:4000 20 10 & elixir --sname probe scripts/soak_probe.exs mu@$(hostname -s) 11 60
for c in "DK --strategy balanced" "DW --strategy ene" "ELF --strategy agi"; do mix mu.simulate --runs 20 --class $c --monster auto --progress --skills; done
```

Giới hạn đăng ký 5 tài khoản / giờ / IP: `smoke` + `acceptance` + `classes` dùng hết 5 lượt từ
127.0.0.1; các bộ còn lại đăng ký qua `X-Forwarded-For` riêng (cần `TRUSTED_PROXIES`).
