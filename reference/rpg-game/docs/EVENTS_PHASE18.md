# Phase 18 — Sự kiện cuối game (cấp 35–50)

Anh chốt 2026-10-10: làm M1 Quảng Trường Quỷ trước, rồi M2 Lâu Đài Máu; vé bán bằng vàng; cánh cấp 3 cần thêm Lông Vũ
Kền Kền (M2). Mọi số ở `priv/game_data/rules.json`, đổi được, không cần sửa code.

## M1. Quảng Trường Quỷ (Devil Square)

### Cách chơi

- **Lịch:** mỗi `every_hours` (2) giờ, giờ Việt Nam, lệch `offset_hours` (1) giờ so với Golden Invasion → mở lúc 1h, 3h,
  5h … 23h; cho vào trong `entry_minutes` (10) phút. Mỗi lần mở mỗi nhân vật vào **một lần**.
- **Vào:** gặp **Người Gác Tháp** ở Làng (thẻ "😈 Quảng Trường Quỷ" dưới Tháp Vô Tận), từ cấp `min_level` (35), tốn 1
  **Vé Quảng Trường** (`ds_ticket`). Vé mua tại đó giá `ticket_price` (20 000 vàng) hoặc rơi từ quái thường cấp
  ≥ `ticket_drop.min_level` (30) với tỉ lệ `ticket_drop.chance` (1 %).
- **Trong lượt:** bản đồ riêng (như một tầng Tháp), `waves` (5) đợt: 4 / 5 / 6 / 6 quái rồi 2 trùm. Hạ hết quái thì
  cầu thang "Đợt sau" mở. Lượt dài `run_minutes` (5) phút.
- **Kết thúc** khi: hết giờ (bước tiếp theo sau giờ hết), gục ngã, qua hết các đợt, hoặc tự đi cầu thang xuống "Về Làng".
  Luôn nhận thưởng theo điểm đã có.
- **Cấp quái** theo cấp người chơi (`tiers`): cấp 35–39 → quái cấp 36, 40–44 → 42, 45+ → 48; mỗi đợt cộng thêm
  `waves[].add_level`. Quái lấy từ vùng cuối, trùm là các trùm vùng (trừ Hắc Long), máu × `boss_hp`.

### Điểm và thưởng

| Khóa `devil_square` | Mặc định | Ý nghĩa |
|---|---|---|
| `score.monster` / `score.boss` | 1 / 10 | điểm mỗi quái / trùm (tối đa 41 điểm một lượt) |
| `reward.gold_per_point` | 5 | vàng = `base_gold(cấp quái)` × hệ số × điểm (lượt đủ ≈ 17 000–22 000 ≈ giá vé) |
| `reward.xp_per_point` | 0,15 | kinh nghiệm = `base_xp(cấp quái)` × hệ số × điểm (lượt đủ ≈ 1 cấp) |
| `reward.jewel_every` | 8 | mỗi 8 điểm một viên ngọc (Phúc Lành / Linh Hồn / Hỗn Nguyên / Sinh Mệnh theo `JEWELS.weights`) |
| `reward.clear_exc_chance` / `clear_anc_chance` | 0,3 / 0,15 | qua hết đợt: thêm 1 món đồ Hiếm / Sử Thi; 30 % Excellent, 15 % là đồ Thần (nếu là món bộ giáp) |
| `top` | 100k + 3 Hỗn Nguyên + 3 Linh Hồn / 60k + 2 + 2 / 30k + 1 + 1 | thưởng hạng 1 / 2 / 3 mỗi ngày, gửi thư lúc 0h05 |

- Quái trong lượt **không** rơi đồ / ngọc / vé riêng (như Tháp); thưởng tính một lần lúc kết thúc.
- Điểm cao nhất hôm nay lưu ở `daily.ds_best`; đợt đã vào ở `daily.ds_slot` (chặn vào lại).
- Bảng xếp hạng ngày (`HacLong.DevilSquareBoard`) giữ trong bộ nhớ: khởi động lại server giữa ngày thì mất bảng hôm đó.

### Thử / e2e

- `HL_DS_OPEN=1 mix phx.server`: Quảng Trường luôn mở (CI e2e đặt sẵn). Vẫn chỉ vào một lần mỗi "đợt".
- `HacLong.DevilSquareBoard.payout("2026-10-10")` (iex): gửi thưởng top 3 của một ngày ngay.
- e2e `e2e/ds.mjs`; test `test/hac_long/game/devil_square_test.exs`.

### Code

`HacLong.Game.DevilSquare` (hàm thuần: lịch, vé, đợt, điểm, thưởng), chạy trên trạng thái Tháp (`p.tower.ds`, cột
`tower` sẵn có — không đổi schema); `HacLong.World` (bước đi trong lượt), `HacLong.Game.Tower.after_battle/1`,
`HacLong.DevilSquareBoard`, `Session.ds_record/2`; giao diện `ui.js` `dsCard`, `map.js` (tên bản đồ / đợt).

## M2. Lâu Đài Máu (Blood Castle)

### Cách chơi

- **Lịch:** mỗi `every_hours` (2) giờ, giờ Việt Nam, lệch `offset_minutes` (30) phút → mở lúc 0h30, 2h30 … 22h30 (xen
  giữa Golden Invasion và Quảng Trường Quỷ); cho vào trong `entry_minutes` (10) phút; mỗi lần mở vào **một lần**
  (`daily.bc_slot`).
- **Vào:** Người Gác Tháp ở Làng (thẻ "🏰 Lâu Đài Máu"), từ cấp `min_level` (40), tốn 1 **Vé Lâu Đài** (`bc_ticket`): mua
  giá `ticket_price` (30 000 vàng) hoặc rơi từ quái thường cấp ≥ `ticket_drop.min_level` (35), tỉ lệ 0,5 %.
- **Ba bước** trong `run_minutes` (8) phút, bản đồ riêng:
  1. hạ `guards` (8) **quân canh** (quái vùng cuối, máu / đòn × `guard_mult` 1,1);
  2. phá **Cổng Thành** (`gate`: không đánh trả, máu × 6) — hiện gần cầu thang lên;
  3. hạ trùm **Hiệp Sĩ Máu** (`boss`: cấp + 3, mạnh × 1,6, máu × 4).
- **Cấp quái** (`tiers`): cấp 40–44 → 44, 45+ → 50.
- **Thắng** (hạ trùm): thưởng ngay, gồm **Lông Vũ Kền Kền** (`condor_feather`); bước tiếp theo về Làng.
- **Không xong** (hết giờ, gục ngã, tự đi cầu thang xuống): thưởng theo số quân canh đã hạ, không có lông vũ.

### Thưởng (`blood_castle.reward`)

| Khóa | Mặc định | Lượt thắng ở quái cấp 44 / 50 |
|---|---|---|
| `success.gold_mult` | 250 × `base_gold` | ≈ 25 000 / 28 000 vàng (≈ giá vé) |
| `success.xp_mult` | 8 × `base_xp` | ≈ 9 900 / 12 500 kinh nghiệm |
| `success.items` | 1 Lông Vũ Kền Kền | |
| `success.jewels` | 2 ngọc (theo `JEWELS.weights`) | |
| `partial.gold_per_guard` / `xp_per_guard` | 6 / 0,3 mỗi quân canh | hạ đủ 8 không qua cổng: ≈ 4 800 vàng, 3 000 KN |

Quái trong lượt không rơi đồ / ngọc / vé riêng (như Tháp).

### Cánh cấp 3

Công thức `wing3` (`chaos.json`) cần thêm **1 Lông Vũ Kền Kền** — mỗi cánh cấp 3 thử ghép cần một lượt Lâu Đài thắng
(thất bại mất cả lông vũ).

### Thử / e2e

- `HL_DS_OPEN=1` mở luôn cả Lâu Đài Máu (chung cờ với Quảng Trường).
- e2e `e2e/bc.mjs`; test `test/hac_long/game/blood_castle_test.exs`.

### Code

`HacLong.Game.BloodCastle` (hàm thuần: lịch, vé, bước, quái, thưởng), trạng thái `p.tower.bc` (cột `tower` sẵn có — không
đổi schema); `HacLong.World` (mệnh đề `tower_move` cho `bc`, đứng trước mệnh đề Tháp chung), `Tower.after_battle/1`;
giao diện `ui.js` `bcCard`, `map.js` (tên bản đồ theo bước).
