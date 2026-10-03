# ACCEPTANCE_PHASE3 — Nghiệm thu Phase 3 "Multiplayer" (P3-M6)

> **Danh sách nghiệm thu = P3-9.** Em soạn theo scope `KB_00_RULES §7` Phase 3 (AOI, reconnect giữa
> phiên, Party, Warehouse, MG) và các đề xuất đã duyệt P3-2 … P3-8; anh cho làm 2026-10-03. Ngày
> chạy: 2026-10-03, môi trường Claude Code cloud (Elixir 1.17.3 / OTP 25, Postgres 16, Chromium).
>
> Bằng chứng 3 lớp như Phase 1 / 2:
> - **ExUnit:** `mix test`, 285 test, 0 lỗi.
> - **E2E:** trình duyệt thật trên server thật, 11 bộ / 134 mục trong `client/e2e/`. Cả 11 bộ chạy
>   **trong lúc soak**.
> - **Soak:** 20 bot × 10 phút, có lập nhóm.
>
> Nghiệm thu Phase 1 (`docs/ACCEPTANCE.md`) và Phase 2 (`docs/ACCEPTANCE_PHASE2.md`) đã chạy lại
> và vẫn xanh (mục 9).

## 1. Danh sách nghiệm thu P3-9 và kết quả

| # | Mục (scope Phase 3) | Kết quả | Bằng chứng |
|---|---|---|---|
| 1 | **AOI** (`KB_TECHNICAL §3`): mỗi người chỉ nhận entity trong 3×3 ô (ô 16, đọc từ config). Vào / ra tầm nhìn = `spawn` / `despawn`. `snapshot` / `combat` lọc theo tầm nhìn. Chat NORMAL vẫn gửi cả map (P3-7) | ✅ PASS | ExUnit `aoi_test.exs` 6 (ô, vào / ra, mình đổi ô, mình hồi sinh), `aoi_channel_test.exs` 2 (kênh thật: đi xa → `despawn`, quay lại → `spawn` đúng vị trí; `combat` ngoài tầm không gửi). E2E `maps.mjs` (NPC ngoài tầm không thấy). Đo băng thông §3 |
| 2 | **Reconnect giữa phiên** (`§4`, P3-8): mất kết nối thì nhân vật đứng yên trên map 30 s và vẫn bị đánh. Vào lại trong hạn giữ vị trí / HP / MP / buff và báo "Đã kết nối lại.". Quá hạn thì rời map và lưu. Đăng xuất rời ngay (đang combat thì sau 10 s) | ✅ PASS | ExUnit `reconnect_channel_test.exs` 4, `combat_channel_test.exs` (đăng xuất khi combat). E2E `reconnect.mjs` 11/11: rớt mạng thật, người khác vẫn thấy, tự nối lại giữ vị trí, đăng xuất biến mất ngay, đóng tab rời map sau 30,0 s. Ảnh `p3-reconnect-lost.png` |
| 3 | **Warehouse** (P3-6): NPC Warehouse Keeper ở Lorencia + Noria. Kho 120 ô dùng chung cho mọi nhân vật của tài khoản. Gửi / rút bằng `move_item` (một transaction, audit). Phải đứng trong tầm NPC. Không cất Zen, không phí | ✅ PASS | ExUnit `warehouse_test.exs` 6 (luật thuần, dùng chung nhân vật, tài khoản khác `NOT_OWNER`, audit `WAREHOUSE_IN/OUT`), `warehouse_channel_test.exs` 2 (`OUT_OF_RANGE`, `rid` idempotent). E2E `warehouse.mjs` 12/12: [Gửi] / kéo thả / [Rút], tải lại trang đồ vẫn còn, tài khoản khác thấy kho trống, mobile xếp dọc. Ảnh `p3-warehouse-desktop.png`, `p3-warehouse-mobile.png` |
| 4 | **Party** (P3-5): mời / nhận / từ chối / rời / đuổi / giải tán; tối đa 5; lời mời 30 s; chỉ trưởng nhóm mời / đuổi / giải tán. Chia EXP trong 20 ô với bonus 10 % / người. Loot protect cả nhóm. Chat `/p`. Khung nhóm (HP, cấp, map, mất kết nối). Mất kết nối quá hạn thì rời nhóm | ✅ PASS | ExUnit `party_channel_test.exs` 10, `engine_test.exs` (công thức EXP nhóm). E2E `party.mjs` 13/13. Soak: 4 nhóm × 5 bot suốt 10 phút. Ảnh `p3-party-frame.png`, `p3-party-invite.png`, `p3-party-mobile.png`, `p3-party-invite-mobile.png` |
| 5 | **Nhiều nhân vật** (P3-3): tối đa 4 nhân vật, chưa cho xóa, một nhân vật online. Màn chọn nhân vật; [Đổi nhân vật] trong game (nhân vật cũ rời map + nhóm) | ✅ PASS | ExUnit `characters_test.exs` (4 nhân vật, tạo song song chỉ 1 lọt), `switch_character_test.exs` 2, `character_controller_test.exs`. E2E `mg.mjs` (danh sách 1/4 → 4/4, hết nút tạo; đổi qua lại DK ↔ MG). Ảnh `p3-character-list.png`, `p3-character-list-mobile.png` |
| 6 | **Magic Gladiator** (P3-2 a, P3-4): mở khi tài khoản có nhân vật cấp 20. 26 mỗi stat, 7 điểm / cấp, cầm sẵn `sword_t0`. Skill DK + DW, skill phép dùng chỉ số phép (§4.1). Không đội mũ | ✅ PASS | ExUnit `mg_test.exs` 3, `characters_test.exs` (khóa / mở ở cấp 19 / 20, chỉ số cấp 1). E2E `mg.mjs` 12/12 (MG khóa 🔒 → mở, HP 188 / MP 112, "Dmg phép"). Ảnh `p3-create-mg-locked.png`, `p3-mg-character.png` |
| 7 | **Server-authoritative / protocol** cho act mới: `party_*` sai trưởng nhóm / đầy / mời hết hạn; `move_item` WAREHOUSE ngoài tầm / sai chủ; tạo MG khi chưa mở; skill sai class; mũ cho MG | ✅ PASS | ExUnit (`FORBIDDEN`, `INVALID_TARGET`, `OUT_OF_RANGE`, `NOT_OWNER`, `CLASS_LOCKED`, `REQUIREMENT_NOT_MET`, `INVALID_SLOT`) |
| 8 | **Tải nhiều người:** 20 người chơi 10 phút (có nhóm, 1/4 ở thị trấn) cùng 11 bộ E2E | ✅ PASS | Soak §2 |
| 9 | **Không hồi quy Phase 1 + 2** | ✅ PASS | E2E `smoke` 24/24, `acceptance` 24/24, `classes` 6/6, `skills` 7/7, `maps` 8/8, `chat` 7/7, `mail_map` 10/10 (chạy trong lúc soak). Simulator DK / DW / ELF ra **đúng số Phase 2** (§4) |
| 10 | **Cân bằng MG** (simulator) | ✅ PASS | §4 |
| 11 | **UI desktop + mobile** cho kho, khung nhóm, hộp lời mời, màn chọn nhân vật | ⚠️ PASS tự động, **cần anh xem bằng mắt ở local** | E2E (kho mobile không tràn ngang), ảnh mobile 390px trong `docs/screenshots/p3-*` |
| 12 | **Asset:** không có file MU-derived trong git. Sprite mới (Warehouse Keeper, MG) là DCSS CC0, có hash | ✅ PASS | `git ls-files`: 0 file `assets_src/private`, `icons/items`, `icon_map.json`. `mapping.json` + `CREDITS.md` |

## 2. Soak test (20 bot × 10 phút, 07:17 → 07:27 UTC)

**Thiết lập:**
- Server: `TRUSTED_PROXIES=127.0.0.1 elixir --sname mu -S mix phx.server`.
- Soak: `SOAK_PARTY=5 node client/e2e/soak.mjs … 20 10 0.25`.
  - 20 bot lập 4 nhóm × 5 người.
  - 5 bot chỉ đi lại trong thị trấn; 15 bot săn Spider.
- Probe đo server mỗi phút từ node khác (`scripts/soak_probe.exs`, nay đo thêm hàng đợi `Mu.Party`).
- **Cùng lúc chạy cả 11 bộ E2E.**

| Chỉ số | Phase 3 | Phase 2 (để so) |
|---|---|---|
| Nhịp mô phỏng | **1 200 tick / phút** mọi phút (12 022 tick / 600 s = **20,0 Hz**) | 20,0 Hz |
| `max_drift` | 38 ms trong lúc chạy E2E, một lần **59 ms** ở phút 6, sau đó không tăng | 35 ms |
| Hàng đợi MapServer / `Mu.Party` | **0 / 0** mọi lần đo | 0 / — |
| RAM VM | 55–57 MB, không tăng dần; state MapServer 160–417 KB; ~581 process | 52–57 MB |
| Snapshot tới bot | p50 100 ms, p99 200 ms, max 400 ms (AOI bỏ snapshot rỗng sau lọc nên có khoảng trống > 100 ms) | 100 / 104 / 201 |
| Kết nối | 20/20 online suốt 10 phút, **0** lần WS đóng bất thường | 0 |
| Lệnh | 6 754 `cmd`, **97,9 % ok** | 95,3 % |
| Log server | **0** `[error]`, **0** `[warning]` | 0 / 0 |
| Nhóm | 4 nhóm đủ 5 người suốt 10 phút; 23 614 event `party` (~2 / giây / bot) | — |
| Gameplay bot | 750 lần hạ quái, **10 lần lên cấp** (có chia EXP nhóm; Phase 2 là 9 nhưng 179 con), 40 lần chết (đều do Spider) | 185 lần chết (trước B-1) |

Lỗi lệnh: `INVALID_TARGET` 55 và `OUT_OF_RANGE` 32 là quái vừa chết hoặc chạy khỏi tầm; `FORBIDDEN`
54 là lệnh gửi khi đang chết; `NOT_ENOUGH_ZEN` 1; `NOT_OWNER` 1 (nhặt đồ của người khác, đúng luật
loot protect).

## 3. Băng thông (AOI + nhóm)

Byte nhận mỗi bot / giây, tính trên tổng 10 phút:

| Nguồn | Bot săn (15) | Bot thị trấn (5) |
|---|---|---|
| `snapshot` | 3,98 KB/s | 3,91 KB/s |
| `party` | **1,18 KB/s** | 1,19 KB/s |
| `combat` | 0,65 KB/s | 0,24 KB/s |
| `spawn` + `despawn` (vào / ra tầm nhìn) | 0,51 KB/s | 0,71 KB/s |
| **Tổng** | **6,37 KB/s** | **6,04 KB/s** |

**AOI** (P3-M1, cùng kịch bản 20 bot, nửa ở thị trấn, chưa có nhóm): 6,56 → 5,21 KB/s/bot
(−21 %). Map 64×64 chỉ có 4×4 ô AOI nên AOI giảm được ít; anh đã chọn giữ đúng số KB (P3M1-1).

**Event `party` chiếm ~19 % băng thông** khi cả 20 người đều trong nhóm: đẩy tới 2 lần / giây, mỗi
lần đủ 5 thành viên kèm vị trí. Ghi ở §5 (B-7).

## 4. Cân bằng (simulator 20 lần / class, `--monster auto --progress --skills`)

| Class (cộng điểm) | Cấp 10 | Cấp 20 | Cấp 30 | Potion tới cấp 30 | Chết | Zen tới cấp 30 |
|---|---|---|---|---|---|---|
| DK (balanced) | 32,5 phút | 71,1 phút | 114,5 phút | 331 | 0 | ≈ 63 900 |
| DW (ene) | 26,0 phút | 50,5 phút | 72,2 phút | **731** | 0 | ≈ 64 100 |
| ELF (agi) | 26,5 phút | 52,5 phút | 76,3 phút | 262 | 0 | ≈ 63 900 |
| **MG (ene)** | 25,2 phút | 48,3 phút | **69,7 phút** | **574** | 0 | ≈ 63 800 |

DK / DW / ELF giống hệt Phase 2 (không hồi quy). MG nhanh nhất một chút (skill phép + đánh
thường), tốn potion như DW (B-2).

## 5. Phát hiện khi nghiệm thu và việc chờ anh

### 5.1 Lỗi tìm ra và đã sửa trong P3-M6

| # | Vấn đề | Đã làm |
|---|---|---|
| A-1 | **Đông người:** bấm vào ô có người chơi khác thì mở menu người chơi (từ P3-M4). Mục [Đi tới đây] lúc đó lại đi tới **vị trí hiện tại của người kia**, mà người kia đang di chuyển, nên mình đi sai chỗ | [Đi tới đây] giờ đi đúng **ô mình đã bấm** (DEC-110) |
| A-2 | E2E cũ (`smoke`, `party`) hỏng khi chạy cùng soak. Nguyên nhân: bấm đi trúng bot, và bot ra đòn cuối nên người chơi test không nhận EXP | Hàm đi bộ của e2e chọn [Đi tới đây]; `smoke` đánh tối đa 6 lượt (chờ Spider hồi sinh) tới khi tự mình ra đòn cuối. Chạy lại cùng soak: 11/11 bộ xanh |

### 5.2 Chờ anh quyết (không chặn nghiệm thu)

| # | Vấn đề | Đề xuất |
|---|---|---|
| B-7 | Event `party` ~1,2 KB/s/bot (≈ 19 % băng thông) khi nhóm 5 người cùng di chuyển | Giữ (đúng §12 "đồng bộ HP và vị trí"). Hoặc giảm: chỉ đẩy khi HP / map / online đổi hay khi đổi ô AOI, hoặc đổi `party.statusIntervalMs` thành 1 000 ms |
| B-8 | **KB cần anh bổ sung** (P3-10, em không sửa `docs/kb/`): §5 act `party_*` + event `party` / `party_invite` / `warehouse`, `move_item` có `WAREHOUSE`, `GET /characters` (`maxCharacters`, `locked`), lỗi `CLASS_LOCKED`, chỉ số phép trong `player.view`, `data.skills[].classes / magic` | Chi tiết ở `OPEN_QUESTIONS` P3M3-1, P3M4-1, P3M5-3 |
| B-9 | `CLAUDE.md` quy tắc 3 vẫn ghi "Chỉ làm Phase 1" (P3-1) | Câu đề xuất ở `PHASE3_PLAN.md §0`; anh sửa hoặc cho em sửa |
| B-10 | Còn mở từ trước: B-2 (DW / MG thiếu Zen mua potion), B-3, B-5 (Item.txt — đối chiếu cả đồ MG P3M5-2, từ cấm, quà thư), B-6 (G26, Q14, soak 1 giờ local, kiểm tra UI bằng mắt), P3M5-1 (đòn phép tối thiểu của MG) | — |

## 6. Chạy lại

```bash
mix test && (cd client && npm test)
TRUSTED_PROXIES=127.0.0.1 elixir --sname mu -S mix phx.server &
SOAK_PARTY=5 SOAK_EVENTS=1 node client/e2e/soak.mjs http://localhost:4000 20 10 0.25 &
elixir --sname probe scripts/soak_probe.exs mu@$(hostname -s) 11 60 &
for f in smoke acceptance classes skills maps chat mail_map reconnect warehouse party mg; do
  node client/e2e/$f.mjs http://localhost:4000 docs/screenshots
done
for c in "DK --strategy balanced" "DW --strategy ene" "ELF --strategy agi" "MG --strategy ene"; do
  mix mu.simulate --runs 20 --class $c --monster auto --progress --skills
done
```

Giới hạn đăng ký là 5 tài khoản / giờ / IP:
- `smoke`, `acceptance` và `classes` đăng ký từ 127.0.0.1, dùng hết 5 lượt. Chạy lại lần hai thì
  phải khởi động lại server.
- Các bộ còn lại đăng ký qua `X-Forwarded-For` riêng, nên server cần `TRUSTED_PROXIES`.
