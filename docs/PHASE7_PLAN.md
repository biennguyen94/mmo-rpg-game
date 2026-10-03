# PHASE7_PLAN — Kế hoạch Phase 7 "Endgame" (bước lập kế hoạch, chưa code)

> **Scope** = dòng Phase 7 trong `docs/kb/KB_00_RULES.md §7` (bổ sung 2026-10-03, DEC-179):
> **Blood Castle, Devil Square** (map event riêng, vé vào, giới hạn người), **Daily quest**,
> **Upgrade +10 / +11** (công thức Chaos Machine), **Wings cấp 2** (`LATER_VERSION`).
>
> **Ngoài scope:** Chaos Castle, pet, Jewel of Harmony / Guardian / Creation, map mới ngoài map
> event, class DL / SUM.
>
> - Câu hỏi mở ở `docs/OPEN_QUESTIONS.md` mục **P7**.
> - KB gần như không có số cho Phase 7, nên mọi milestone chờ anh duyệt bảng đề xuất (⛔).
> - Như Phase 5–6: mỗi milestone có ExUnit + test client + e2e viết sẵn. Toàn bộ E2E chỉ chạy một
>   lần ở milestone nghiệm thu.

## 1. KB có gì / thiếu gì

| Hạng mục | KB / dự án đã có | Thiếu / cần anh quyết |
|---|---|---|
| **Cấp tối đa** | `game.maxLevel` 30. Simulator: lên cấp 30 trong 70–115 phút chơi | Endgame cho cấp 30 thì giữ 30 hay nâng? Ảnh hưởng mốc cấp vào event và cấp cánh 2 (P7-1) |
| **Daily quest** | Quest Phase 6 (`quests.json`, `character_quests`, Quest Master). Repo nền `daily.ex` mức ADAPT | Số nhiệm vụ / ngày, giờ reset, mục tiêu, thưởng, chỗ lưu (bảng mới → migration) (P7-2) |
| **Upgrade +10 / +11** | Bảng `upgrade.levels` tới +9 (KB_CONFIG §5). Chaos Machine + `chaos.json` (Phase 6). Trên +9 = `LATER_VERSION` | Công thức, tỉ lệ, phí, thất bại mất gì, chỉ số mỗi cấp, Jewel đi kèm (P7-3) |
| **Map event** | Map tĩnh + MapServer / map; đổi map qua cổng (`change_map`); event theo lịch (`Mu.WorldEvents`) | Map event đi vào thế nào, giới hạn người, chết / thoát / mất kết nối thì sao, có phòng riêng (instance) không (P7-4) |
| **Devil Square** | Chỉ có tên | Lịch, vé, luật (đợt quái, điểm), thưởng (P7-5) |
| **Blood Castle** | Chỉ có tên | Lịch, vé, luật (cổng, tượng, vũ khí), thưởng (P7-6) |
| **Vé** | — | Vé lấy ở đâu (rơi / ghép / mua), stack, giá (P7-7) |
| **Wings cấp 2** | 3 cánh cấp 1, `damageIncrease` / `absorb` trong pipeline sát thương (DEC-172). `KB_REFERENCE §4`: cánh = `LATER_VERSION`, cấp yêu cầu chưa verify | Cánh nào, chỉ số, cấp yêu cầu, công thức (P7-8) |
| **Protocol** | Chưa có act / event Phase 7 trong `KB_TECHNICAL §5` | Đề xuất ở P7-9 |
| **Asset** | Sprite / tile DCSS đã có trong repo. Không tải asset mới được trong cloud | Map event vẽ bằng tile có sẵn; NPC / quái mới dùng lại sprite có sẵn (P7-10) |

## 2. Milestone đề xuất

| Milestone | Nội dung | Chặn bởi |
|---|---|---|
| **P7-M1 Daily quest** | Bảng `character_dailies` (migration + CHANGE_REASON); 3 nhiệm vụ / ngày chọn từ pool theo cấp, reset 00:00 UTC; nhận / trả ở Quest Master; thưởng một transaction (audit `DAILY`); tab "Hằng ngày" trong panel Nhiệm vụ | ⛔ P7-1, P7-2 |
| **P7-M2 Upgrade +10 / +11** | Thêm công thức vào `chaos.json` (đồ +9 / +10 + Bless + Soul + Chaos + Zen); `items.levelBonus` dùng tới +11; SYSTEM khi thành công; UI Chaos Machine hiện công thức mới | ⛔ P7-3 |
| **P7-M3 Khung map event + Devil Square** | Map `devil_square` (JSON + collision, tile có sẵn); `Mu.EventRoom` (cửa sổ vào, giới hạn người, đưa vào / đưa ra, kết thúc); vé Devil's Invitation; đợt quái + điểm + thưởng theo hạng; thanh event / bảng điểm trên client | ⛔ P7-4, P7-5, P7-7 |
| **P7-M4 Blood Castle** | Map `blood_castle`; dùng lại khung P7-M3; cổng thành + tượng (thực thể có máu, không đánh trả); Archangel's Weapon (đồ nhiệm vụ) mang về NPC; thưởng cả đội + người về đích; vé Invisibility Cloak | ⛔ P7-6, P7-7 (cần P7-M3) |
| **P7-M5 Wings cấp 2** | 4 cánh cấp 2 (theo class), Loch's Feather (từ Blood Castle); công thức Chaos Machine; vẽ cánh lớn hơn / màu riêng | ⛔ P7-8 (cần P7-M4) |
| **P7-M6 Nghiệm thu Phase 7** | Danh sách P7-11, toàn bộ E2E một lần, soak có Devil Square / Blood Castle, `mix mu.audit`, simulator | P7-11 |

**Thứ tự:** M1 → M2 → M3 → M4 → M5 → M6.
- Daily quest và +10 / +11 nhỏ, độc lập nên làm trước.
- Blood Castle dùng lại khung phòng event của Devil Square.
- Cánh cấp 2 cần Loch's Feather từ Blood Castle.

## 3. Thiết kế kỹ thuật dự kiến (không đổi gameplay, để anh nắm)

- **Daily quest:**
  - luật thuần `Mu.Game.Dailies` (chọn nhiệm vụ theo ngày + cấp bằng RNG có seed = ngày + nhân vật → cùng ngày luôn ra cùng bộ);
  - đếm tiến độ đi chung đường `map_reward` như quest;
  - bảng riêng để reset theo ngày mà không đụng quest thường.
- **+10 / +11:**
  - chỉ thêm dữ liệu vào `chaos.json` (công thức có điều kiện cấp đồ chính xác + kết quả "đồ đó +1");
  - `Mu.Game.Chaos` thêm loại kết quả `upgrade`;
  - giao dịch dùng lại `Items.chaos_combine` (một transaction, audit `CHAOS_IN` / `CHAOS_OUT`). Đồ được nâng **giữ serial**, chỉ đổi `item_level`.
- **Phòng event (Devil Square / Blood Castle):**
  - map event là map thường có MapServer riêng, nhưng **không có cổng vào**;
  - `Mu.EventRoom` (một tiến trình / loại event, `Mu.WorldEvents` ra lịch):
    - mở cửa sổ vào;
    - nhận người ở NPC (kiểm vé + cấp + chỗ trống, tiêu vé trong một transaction);
    - đưa người vào bằng `change_map` có sẵn;
    - sinh quái theo đợt (`spawn_event`);
    - tính điểm / mục tiêu, kết thúc thì trả thưởng và đưa mọi người về thị trấn.
  - Mỗi lúc chỉ **một phòng** / loại event (không instance nhiều phòng: đủ cho số người hiện tại, ít rủi ro).
- **Wings cấp 2:** chỉ thêm template + công thức; pipeline sát thương Phase 6 dùng lại nguyên.
- **AOI, Party, Guild, Trade, Quest** không đổi. Người trong phòng event vẫn chat / nhóm bình thường.

## 4. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Phòng event có nhiều trạng thái (vào / chết / mất kết nối / hết giờ / server khởi động lại) → kẹt người trong map event | Một tiến trình giữ trạng thái; mọi đường ra đều về thị trấn; vào lại game khi phòng đã đóng thì đưa thẳng về thị trấn (kiểm lúc `attach`); test từng đường |
| Vé / thưởng / +10 sinh đồ → kênh dupe mới | Một transaction, audit vào / ra, `mix mu.audit` sau soak, test song song như Phase 5 |
| Đồ +11 + cánh 2 làm lệch PvP | % nhỏ (P7-3, P7-8), PvP vẫn × 0,5; simulator so trước / sau |
| Thất bại +10 / +11 mất đồ → người chơi nản | Đề xuất cho anh chọn: mất đồ (như MU) hay về +0 (P7-3) |
| Map event vẽ bằng tile có sẵn trông đơn điệu | Chấp nhận ở Phase 7, ghi BACKLOG (asset thật để sau) |
| Lịch chồng nhau (boss, Golden Invasion, DS, BC) | Đặt DS / BC ở phút 30, boss / Golden ở phút 0 (P7-5, P7-6) |
