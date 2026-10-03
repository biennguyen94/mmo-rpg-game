# PHASE2_PLAN — Kế hoạch Phase 2 "Core" (bước lập kế hoạch, chưa code)

> Scope duy nhất: `docs/kb/KB_00_RULES.md §7` dòng Phase 2:
> **DW, Elf, Inventory, Equipment, Skills, Monster AI, Drop table, NPC, Shop, Chat, Death/respawn,
> Pathfinding, Hộp thư hệ thống, panel Bản đồ.**
> Câu hỏi mở của phase này: `docs/OPEN_QUESTIONS.md` mục **P2**. Chưa viết dòng code gameplay
> nào cho tới khi anh "OK" kế hoạch này và trả lời các câu hỏi chặn (đánh dấu ⛔).

## 0. Lưu ý về `CLAUDE.md`

`CLAUDE.md` quy tắc 3 ghi "Chỉ làm Phase 1". Anh đã yêu cầu sang phase tiếp, nên em làm theo yêu cầu
mới nhưng **không tự sửa `CLAUDE.md`**. Đề xuất câu thay thế (anh duyệt rồi em sửa, hoặc anh tự sửa):

> 3. **Chỉ làm phase đang mở** (hiện tại: **Phase 2**, `KB_00_RULES §7`). Không thêm tính năng
> `LATER_VERSION` hoặc phase sau, kể cả khi repo nền đã có sẵn.

Nguyên tắc còn lại giữ nguyên (KB thắng, không bịa số, server-authoritative, asset MU ngoài git…).

## 1. Hiện trạng sau Phase 1 so với scope Phase 2

| Hạng mục Phase 2 | Đã có từ Phase 1 | Còn thiếu cho Phase 2 | KB có đủ dữ liệu? |
|---|---|---|---|
| **DW** | Engine stat theo `classes.json` (`derived` terms), tạo nhân vật cố định DK | Thêm class DW, chọn class lúc tạo, vũ khí staff, sprite | Stat gốc ✅ `KB_CONFIG §2`; công thức ✅ `KB_GAME_DESIGN §4.1`; **skill ⛔, item staff ⛔ (E6)** |
| **Elf** | như trên | Class Elf, bow/crossbow (đánh xa), skill support | Stat ✅; công thức ✅; **skill/buff ⛔, cung ⛔ (luật slot, tầm, mũi tên)** |
| **Inventory** | 64 slot, UI danh sách §19.4, equip/unequip/use/sell | `move_item`, `split`, `drop` (protocol đã có §5), UI kéo thả | Protocol ✅; **UI lưới/kéo thả ⛔** (§19 chỉ vẽ danh sách); `drop` → mặt đất ⛔ (`GROUND` là `LATER_VERSION`) |
| **Equipment** | 10 slot §6, kiểm class/level/stat | Luật cung/khiên, WING khóa, MG không HELM (MG là Phase 3) | Phần lớn ✅; cung ⛔ |
| **Skills** | `basic_attack`, `twisting_slash`, cooldown/mana | Skill DW, Elf (damage + support), buff/heal, hiệu ứng | Chỉ có mẫu `twisting_slash` §7 → **⛔ thiếu toàn bộ số** |
| **Monster AI** | IDLE→CHASE→ATTACK→RETURN, A*, 10 Hz | Nhiều loại quái, quái đánh xa?, SEARCH, sleep zone không người | Máy trạng thái ✅ §9; **chỉ số quái ⛔** (KB chỉ có Spider) |
| **Drop table** | Spider theo `KB_CONFIG §4`, zen/group/weight | Bảng drop cho quái mới, item mới | Định dạng ✅ §10; **số ⛔** |
| **NPC / Shop** | Potion Merchant Lorencia | NPC bán vũ khí/giáp/staff/bow, NPC map mới | Định dạng ✅; danh sách/giá ⛔ |
| **Chat** | act `chat` trả `FORBIDDEN` (M4-4) | NORMAL, WHISPER, SYSTEM; PARTY/GUILD tắt tới Phase 3/4 | Protocol ✅ §5; **giới hạn độ dài, rate, lọc từ, mute ⛔** §16 |
| **Death/respawn** | Chết → hồi sinh safe zone sau `playerRespawnSeconds`, `expLossPercent` 0 | Respawn town gần nhất khi có nhiều map; giảm durability (§11)? | Luật ✅; **số durability ⛔** |
| **Pathfinding** | A* octile, `maxPathNodes` | Monster A* giới hạn độ sâu + cache (§7), nhiều map | ✅ |
| **Hộp thư** | — | Bảng `mail`, `mail_list/claim/delete`, UI §19.10 | **⛔ KB tự ghi: phải bổ sung vào `KB_TECHNICAL` trước** |
| **Panel Bản đồ** | — | Minimap 256×256 §19.12, chấm player/NPC/portal | UI ✅; **portal ⛔** (cần map thứ 2) |

Kết luận: phần **khung** (luồng, protocol, UI) đa số có trong KB; phần **số liệu nội dung** (skill,
quái, item, map, chat, mail schema) gần như chưa có → đây là việc chặn chính.

## 2. Milestone đề xuất

Mỗi milestone: commit riêng trên `ccr-c1e9e89f-eb2dxu`, format/compile/test xanh, cập nhật
`DECISIONS`/`OPEN_QUESTIONS`/`REUSE_LOG`, **dừng báo cáo chờ "OK"**.

| Milestone | Nội dung | Chặn bởi |
|---|---|---|
| **P2-M1 Inventory & Equipment** ✅ 2026-10-03 | `move_item` (hoán đổi/merge stack), `split`, `drop`; UI túi đồ mới (lưới hoặc danh sách + kéo thả, theo P2-8); giữ transaction + `item_audit_log` + idempotent `rid`; test thuần `Inventory` | P2-8, P2-9 (có thể làm trước vì ít phụ thuộc số) |
| **P2-M2 Class DW + Elf** ✅ 2026-10-03 | `classes.json` thêm DW/ELF (KB_CONFIG §2 + §4.1), màn tạo nhân vật chọn class, sprite DCSS cho DW/Elf, basic attack đánh xa cho Elf/DW, item staff/bow nhập từ Item.txt | P2-3, P2-5, P2-6 (E6) |
| **P2-M3 Skills theo class** | `skills.json` DW/Elf/DK thêm skill, hệ buff (thời hạn, cộng chỉ số), heal; menu skill client; effect placeholder | P2-4 |
| **P2-M4 Nội dung: quái, drop, NPC, map** | Quái mới cho Lorencia (+ map 2), drop table, NPC shop vũ khí/giáp, map thứ 2 + portal, chuyển map (MapServer theo map, kênh đổi topic), respawn town gần nhất, `maxLevel` Phase 2 | P2-2, P2-7, P2-10, P2-11 |
| **P2-M5 Chat** | NORMAL/WHISPER/SYSTEM, PARTY/GUILD → `FORBIDDEN` (feature tắt), rate-limit theo `rateLimit` config, sanitize hiển thị, lọc từ, mute | P2-12 |
| **P2-M6 Hộp thư + panel Bản đồ** | Migration `mail` + action theo KB_TECHNICAL (sau khi anh bổ sung), nhận Zen/item trong 1 transaction; minimap §19.12 | P2-13, P2-14 |
| **P2-M7 Nghiệm thu Phase 2** | e2e mở rộng (3 class, chat 2 tab, mail, chuyển map), simulator cân bằng cho DW/Elf, soak 20 bot 10 phút | Danh sách nghiệm thu P2-15 |

Thứ tự gợi ý: **P2-M1 trước** (ít phụ thuộc dữ liệu mới nhất), song song anh chuẩn bị dữ liệu cho M2–M4.

## 3. Nguyên tắc giữ nguyên từ Phase 1

- Không hard-code số: mọi số mới vào `priv/game_data/*.json`/`config.json` với `sourceType`, `version`,
  `verified`. Số em đề xuất khi KB thiếu → `sourceType: "IMPLEMENTATION"`, `verified: false` **chỉ sau
  khi anh đồng ý** (không tự bịa số gameplay).
- Protocol chỉ theo `KB_TECHNICAL §5`; event/act mới (mail, chuyển map) → `CHANGE_REASON` + hỏi.
- Schema chỉ theo `KB_TECHNICAL §9`; bảng `mail` cần anh cập nhật KB trước.
- Engine thuần + RNG seed; thao tác item/Zen trong 1 transaction.
- Asset: DCSS (CC0) cho sprite DW/Elf/quái như DEC-52; icon item MU-derived vẫn ngoài git.
- Phaser vẫn theo `docs/BACKLOG.md §1` — registry npm vẫn `403` (kiểm 2026-10-03), Phase 2 tiếp tục
  Canvas 2D trừ khi môi trường mở.

## 4. Rủi ro

| Rủi ro | Ảnh hưởng | Giảm thiểu |
|---|---|---|
| Thiếu số skill/quái/item | Chặn M2–M4 | Anh cung cấp, hoặc duyệt bảng số IMPLEMENTATION em đề xuất (tính bằng `mix mu.simulate`) |
| Chưa có `items_raw.json` (E6) | Không nhập được staff/bow đúng quy trình KB_ITEM_REFERENCE | Anh đặt `priv/reference/items_raw.json` (hoặc Item.txt) ở máy local/không vào git nếu cần |
| Chuyển map + nhiều MapServer | Đổi cách kênh đăng ký topic (hiện đăng ký mọi map rồi bỏ) | Làm ở M4, test chuyển map; AOI vẫn để Phase 3 |
| Mail cần đổi KB_TECHNICAL | Em không được sửa `docs/kb/` | Em soạn bản đề xuất schema/action trong OPEN_QUESTIONS để anh chép vào KB |
| Cân bằng 3 class | DW/Elf yếu/mạnh hơn DK | Mở rộng simulator theo class, báo cáo như `ACCEPTANCE.md §3` |

## 5. Trạng thái

| Milestone | Kết quả |
|---|---|
| P2-M1 (2026-10-03) | Server: `move_item` (chuyển / hoán đổi / gộp stack), `split`, `drop` (xuống đất trong RAM, giữ serial + thuộc tính, P2-9), idempotent `rid`, audit `MOVE` / `MERGE` / `SPLIT` / `DROP`. Client: lưới 8×8, kéo thả (chuột) + nút trong tooltip (cảm ứng), thùng rác + xác nhận (DEC-56); panel không còn dựng lại mỗi snapshot (DEC-57). Test: 202 ExUnit, 13 node, smoke 24/24, nghiệm thu 24/24 (thêm 5 mục P2). Ảnh: `docs/screenshots/p2-inventory-drop.png` |
| P2-M2 (2026-10-03) | DW + ELF trong `classes.json` (KB_CONFIG §2 + §4.1), tạo nhân vật chọn class + đồ khởi đầu (gậy / cung), `maxLevel` 30, `weaponType` + tầm đánh theo vũ khí (cung 5), luật cung hai tay, 12 template t0 (số tạm), MP potion ở shop, sprite DCSS cho DW/Elf, simulator theo class. Test: 208 ExUnit, 14 node, smoke 24/24, nghiệm thu 24/24, `classes.mjs` 6/6. Ảnh: `docs/screenshots/p2-create-class.png`, `p2-elf-ranged.png` |
