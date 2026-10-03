# PHASE4_PLAN — Kế hoạch Phase 4 "PvP & Social" (bước lập kế hoạch, chưa code)

> Scope duy nhất là dòng Phase 4 trong `docs/kb/KB_00_RULES.md §7`:
> **Duel, PK, Self-defense, Guild, Guild war.**
> Câu hỏi mở nằm ở `docs/OPEN_QUESTIONS.md` mục **P4**. KB gần như không có số cho Phase 4 nên
> mọi milestone đều chờ anh duyệt bảng đề xuất (⛔).

## 0. `CLAUDE.md`

Quy tắc 3 vẫn ghi "Chỉ làm Phase 1" (B-9 / P3-1 chưa xử lý). Đề xuất câu thay (anh duyệt hoặc tự
sửa; em không sửa):

> 3. **Chỉ làm phase đang mở** (hiện tại: **Phase 4**, `KB_00_RULES §7`). Không thêm tính năng
> `LATER_VERSION` hoặc phase sau, kể cả khi repo nền đã có sẵn.

## 1. KB có gì / thiếu gì

| Hạng mục | KB có | Thiếu / cần anh quyết |
|---|---|---|
| **Tấn công người chơi** (nền cho mọi mode) | `KB_GAME_DESIGN §13`: dùng state machine, **không** dùng một boolean `isPvP`; safe zone cấm tấn công. `KB_TECHNICAL §1`: MapServer xử lý PvP. `features.pvp` | Ai đánh được ai (cấp tối thiểu), cách bấm đánh người, AOE có trúng người không, hệ số sát thương PvP (P4-2) |
| **PK** | `PKState: NORMAL → WARNING → MURDERER`; giết người trung lập thì tăng `pkPoints`; giảm PK theo thời gian; phạt khi chết, rơi đồ, hạn chế vào town / NPC. Cột `characters.pk_points`, `last_pk_at` đã có (§9) | Ngưỡng từng trạng thái, tốc độ giảm, phạt cụ thể, màu tên (P4-3) |
| **Self-defense** | "Người bị tấn công trước được đánh trả, không bị tính PK" | Quyền đánh trả kéo dài bao lâu; giết người PK có bị tính PK không (P4-3) |
| **Duel** | "Hai bên đồng ý, vùng riêng, không PK" | "Vùng riêng" là gì (đấu trường hay khoanh riêng hai người); kết thúc thế nào; act / event (P4-4) |
| **Guild** | `§14`: tạo guild cần level + Zen; master / assistant / member; mời / đuổi; chat GUILD (`§16`); `features.guild`. Repo nền `guilds.ex` mức ADAPT | Số (cấp, Zen, số người, số assistant), quyền từng vai trò, giải tán, UI (§19 không vẽ). **Không có bảng guild trong §9** → cần migration mới có CHANGE_REASON (P4-5) |
| **Guild war** | "Hai guild khai chiến, kill không tính PK" | Cách khai chiến / chấp nhận, thời gian, tính điểm, kết thúc, thưởng (P4-6) |
| **Protocol** | Chưa có act / event nào cho Phase 4 trong `KB_TECHNICAL §5` | Đề xuất ở P4-7; anh bổ sung KB sau khi chốt (như P3-10) |

## 2. Milestone đề xuất

| Milestone | Nội dung | Chặn bởi |
|---|---|---|
| **P4-M1 PvP nền + PK + Self-defense** ✅ | `Mu.Game.Pvp` (bảng quyết định thuần); đánh người (cấp ≥ 6, ngoài safe zone, × 0,5, AOE chỉ quái); tự vệ 30 s + kẻ gây sự; PK +1 khi giết NORMAL, WARNING / MURDERER, giảm 1 điểm / 60 phút; MURDERER bị NPC từ chối; rơi đồ khi bị giết (MURDERER 50 %, WARNING 10 %); màu tên; xác nhận khi đánh người NORMAL (DEC-112 … DEC-118). E2E `pvp.mjs` 14/14 | xong |
| **P4-M2 Duel** ✅ | Mời / nhận / từ chối / hủy / đầu hàng; "vùng riêng" (chỉ hai người đánh nhau); về 0 HP → 1 HP thua, hết 3 phút hòa, đi xa > 20 ô / rời map / mất kết nối thua; không PK, không rơi đồ; AOE trúng đối thủ; cấm đánh người cùng nhóm (DEC-119 … DEC-124). E2E `duel.mjs` 14/14 | xong |
| **P4-M3 Guild** ✅ | Bảng `guilds`, `guild_members` (migration + CHANGE_REASON). Tạo (cấp 20 + 10 000 Zen, một transaction), mời (menu người chơi / theo tên) / nhận / từ chối / rời / đuổi / phong / hạ / giải tán (xác nhận), master / assistant (≤ 2) / member, tối đa 20. Chat GUILD (`/g`). Panel Guild. `<Tên guild>` dưới tên nhân vật (DEC-125 … DEC-131). E2E `guild.mjs` 24/24 | xong |
| **P4-M4 Guild war** ✅ | Master tuyên chiến / nhận / từ chối (60 s) / đầu hàng; thành viên hai guild đánh nhau ngoài safe zone, AOE trúng địch, không PK, không rơi đồ; +1 điểm / kill, 20 điểm hoặc 30 phút (điểm cao thắng, bằng hòa), giải tán = đầu hàng; tên địch tím; thanh war; SYSTEM hai guild (DEC-132 … DEC-137). ExUnit thuần + kênh; E2E `guildwar.mjs` viết sẵn, **chạy ở P4-M5** | xong |
| **P4-M5 Nghiệm thu Phase 4** ✅ | Danh sách nghiệm thu P4-9 (12 mục), 15 bộ E2E / 213 mục chạy trong lúc soak 20 bot × 10 phút có guild war, simulator không đổi — `docs/ACCEPTANCE_PHASE4.md` (DEC-138, DEC-139) | xong |

Thứ tự: P4-M1 → P4-M2 → P4-M3 → P4-M4 → P4-M5. Duel và guild war dựng trên tấn công người – người
của P4-M1.

## 3. Thiết kế kỹ thuật dự kiến (không đổi gameplay, để anh nắm)

- **State machine** (theo §13): module thuần `Mu.Game.Pvp` quyết định "A đánh B được không, kết
  quả tính gì":
  - **quan hệ** giữa hai người: `:duel` / `:guild_war` / `:self_defense` / `:none`;
  - **trạng thái PK** của từng người: `NORMAL` / `WARNING` / `MURDERER`.

  MapServer chỉ hỏi module này. Có test thuần cho từng ô của bảng quyết định.
- **PK** lưu ở `characters` (đã có cột). Session ghi DB ngay khi PK đổi, như khi lên cấp.
- **Duel và guild war** sống trong RAM (như Party). Guild lưu DB vì phải còn sau khi khởi động lại.
- **AOI** (P3-M1) không đổi; event mới đi qua kênh riêng như `party`.

## 4. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| PvP mở ra lạm dụng (giết người mới ở ngoài thị trấn) | Cấp tối thiểu để bị / được đánh (P4-2); thị trấn là safe zone; MURDERER bị phạt nặng |
| Rơi đồ khi chết vì PK dễ sinh lỗi dupe | Dùng lại đường `drop` (một transaction, audit, serial giữ nguyên) |
| Guild + war cắt ngang nhiều tài khoản | Một tiến trình cho war (như Party, ghi trong RAM); guild trong DB với transaction + khóa |
| Bấm người chơi đã mở menu (P3-M4) nay thêm [Tấn công] → dễ bấm nhầm | Hỏi xác nhận lần đầu khi đánh người NORMAL (sẽ thành PK); không đánh nhầm trong safe zone |
