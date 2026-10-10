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
