# PHASE6_PLAN — Kế hoạch Phase 6 "Advanced" (bước lập kế hoạch, chưa code)

> Scope duy nhất là dòng Phase 6 trong `docs/kb/KB_00_RULES.md §7`:
> **Quest, Chaos Machine, Wings (`LATER_VERSION`), Events, Bosses, Ranking.**
> Ràng buộc phụ thuộc (`§7`): Chaos Machine cần Upgrade + Jewel (đã có ở Phase 5).
> Câu hỏi mở ở `docs/OPEN_QUESTIONS.md` mục **P6**. KB gần như không có số cho Phase 6, nên mọi
> milestone đều chờ anh duyệt bảng đề xuất (⛔).
> **Nghiệm thu Phase 5 gộp vào cuối Phase 6** (anh chọn (A), DEC-160): P6-M6 nghiệm thu chung.

## 0. `CLAUDE.md`

Quy tắc 3 vẫn ghi "Chỉ làm Phase 1" (B-9). Em không tự sửa. Câu đề xuất:

> 3. **Chỉ làm phase đang mở** (hiện tại: **Phase 6**, `KB_00_RULES §7`). Không thêm tính năng
> `LATER_VERSION` hoặc phase sau, kể cả khi repo nền đã có sẵn.

## 1. KB có gì / thiếu gì

| Hạng mục | KB có | Thiếu / cần anh quyết |
|---|---|---|
| **Quest** | `KB_GAME_DESIGN §15`: `interface Quest {id, name, minLevel, objectives, rewards, sourceType}`. `KB_REFERENCE §5`: tên quest MU (Proof of Strength…) **không** coi là canonical — quest của dự án tự định nghĩa. `features.quest`. Repo nền `quests.ex`, `daily.ex` mức ADAPT | Loại mục tiêu, phần thưởng, nhận / trả ở đâu, danh sách quest, lưu tiến độ (§9 **chưa có bảng** → migration + CHANGE_REASON) (P6-2) |
| **Chaos Machine** | `features.chaosMachine`. Cần Upgrade + Jewel. `KB_REFERENCE §4`: jewel cổ điển gồm cả **Chaos** (chưa làm ở Phase 5). Upgrade trên +9 = `LATER_VERSION` | NPC nào, công thức nào (đề xuất: chỉ công thức **tạo cánh**), tỉ lệ, phí Zen, thất bại mất gì, Jewel of Chaos rơi ở đâu (P6-3) |
| **Wings** | `features.wings` (tắt), slot `7` WING đã có trong `KB_CONFIG §6` và UI (khóa 🔒). `KB_ITEM_REFERENCE`: group 12 = Wing/Orb/Seed (raw chuẩn **bỏ group 12**; `scripts/parse_items.py` đọc được). `KB_REFERENCE §4`: wing = `LATER_VERSION` tới Phase 6, level yêu cầu chưa verify | Cánh nào (đề xuất 3 cánh cấp 1), chỉ số (KB **không có công thức** % tăng sát thương / hấp thụ), lấy ở đâu, ép +N được không, hình trên nhân vật (P6-4) |
| **Events** | Chỉ có tên trong `§7`. Repo nền `game/events.ex` | Event nào (Blood Castle / Devil Square cần map riêng + vé — đề xuất để sau; làm **Golden Invasion**), lịch, phần thưởng (P6-5) |
| **Bosses** | Chỉ có tên. `KB_TECH_STACK §4` cây giám sát có `WorldBoss`. Repo nền `world_boss.ex` (lịch, máu chung, chia thưởng theo sát thương) mức ADAPT | Boss nào, ở đâu, chỉ số, lịch, chia thưởng (P6-6) |
| **Ranking** | Chỉ có tên. `KB_TECH_STACK §4` có `Leaderboard`. Repo nền `leaderboard.ex` mức ADAPT | Bảng nào, bao nhiêu hạng, cập nhật bao lâu (P6-7) |
| **Protocol** | Chưa có act / event Phase 6 trong `KB_TECHNICAL §5` | Đề xuất ở P6-8 |

## 2. Milestone đề xuất

| Milestone | Nội dung | Chặn bởi |
|---|---|---|
| **P6-M1 Ranking** ✅ | `Mu.Leaderboard` (cache RAM, đọc DB khi bảng cũ > 5 phút): cấp (tất cả / DK / DW / ELF / MG), guild (tổng cấp); top 50 + hạng của mình; panel Xếp hạng (DEC-163). E2E `ranking.mjs` viết sẵn | xong |
| **P6-M2 Quest** ✅ | Bảng `character_quests` (migration + CHANGE_REASON), `quests.json` 10 quest, Quest Master ở Lorencia + Noria, mục tiêu kill / collect / level, trả quest một transaction (EXP, Zen + đồ có audit `QUEST`). Panel Nhiệm vụ + hộp NPC + dòng theo dõi (DEC-164 … 167). E2E `quest.mjs` viết sẵn | xong |
| **P6-M3 Jewel of Chaos + Chaos Machine** ✅ | `jewel_chaos` + nhóm rơi 45/30/12/13; Chaos Goblin (Noria); cửa sổ CHAOS MACHINE (đặt đồ → server báo công thức, tỉ lệ, phí); `chaos.json`; kết hợp một transaction, audit `CHAOS_IN` / `CHAOS_OUT` / Zen `CHAOS` (DEC-168 … 171). E2E `chaos.mjs` viết sẵn | xong (chung commit với M4) |
| **P6-M4 Wings** ✅ | `features.wings` bật; 3 cánh cấp 1; slot 7 mở; Engine % sát thương / % hấp thụ; ép +N (không Life); vẽ cánh hình học; spawn có `wing` (DEC-172) | xong |
| **P6-M5 Bosses + Events** | `Mu.WorldEvents` (lịch trong config + lệnh quản trị bật tay): world boss (máu chung, chia thưởng theo sát thương), Golden Invasion (quái vàng rơi jewel); thông báo SYSTEM | ⛔ P6-5, P6-6 |
| **P6-M6 Nghiệm thu Phase 5 + 6** | Danh sách nghiệm thu P5-9 + P6-9, **toàn bộ E2E một lần**, soak có trade / upgrade / quest / boss, `mix mu.audit` sau soak, simulator, báo cáo | P5-9, P6-9 |

Thứ tự: M1 → M2 → M3 → M4 → M5 → M6. Ranking làm trước vì nhỏ và không phụ thuộc gì; Wings sau
Chaos Machine vì cánh lấy từ Chaos Machine. E2E chỉ chạy ở P6-M6 (như DEC-149 / DEC-160); mỗi
milestone vẫn có ExUnit + test client + e2e viết sẵn.

## 3. Thiết kế kỹ thuật dự kiến (không đổi gameplay, để anh nắm)

- **Ranking:** một tiến trình giữ bảng trong RAM, đọc DB mỗi `ranking.refreshSeconds`; client
  xin bảng bằng act, không đẩy liên tục (không tốn băng thông).
- **Quest:** luật thuần `Mu.Game.Quests` (tiến độ, đủ điều kiện, thưởng); Session cập nhật tiến độ
  khi MapServer báo hạ quái (`{:map_reward, …}` — thêm loại quái vào tin) và khi túi đổi; trả quest là một
  transaction (thu vật phẩm + thưởng + `zen_audit_log` + `item_audit_log`).
- **Chaos Machine:** công thức là data (`chaos.json`: điều kiện đầu vào, tỉ lệ, phí, kết quả); luật
  thuần + một transaction ở `Mu.Game.Items` (như `upgrade`): tiêu đồ đầu vào (audit `CHAOS_IN`),
  tạo kết quả (audit `CHAOS_OUT`) hoặc mất hết khi thất bại. RNG ở server.
- **Wings:** thêm hai hệ số vào pipeline sát thương §4 (`damageIncrease` bên đánh, `absorb` bên
  nhận) đọc từ template; không đổi công thức chỉ số cũ.
- **Boss / Events:** một tiến trình lịch (`Mu.WorldEvents`) ra lệnh cho MapServer sinh / thu quái
  đặc biệt; MapServer ghi sát thương theo người cho boss; chia thưởng khi boss chết. Không lưu DB
  (khởi động lại thì lịch chạy lại từ đầu).
- **AOI, Party, Guild, Trade** không đổi.

## 4. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Chaos Machine / quest sinh đồ → kênh dupe mới | Một transaction, audit vào / ra, `mix mu.audit` kiểm sau soak; test song song như P5-M3 |
| Cánh làm lệch cân bằng PvE / PvP | % nhỏ (P6-4); simulator có cánh; PvP vẫn × 0,5 |
| Boss đông người làm MapServer chậm (tick 20 Hz) | Boss chỉ 1 con / map, AOE có giới hạn mục tiêu; soak có boss đo `max_drift` |
| Event theo lịch khó test | Lệnh quản trị bật tay (`mix mu.event start …`) + test với đồng hồ giả |
| Quá nhiều milestone không chạy E2E | Mỗi milestone viết sẵn e2e; P6-M6 chạy toàn bộ một lần (anh đã chọn) |
