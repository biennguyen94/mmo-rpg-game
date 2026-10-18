# Báo cáo cân bằng (sinh tự động)

> Sinh bằng `mix hac_long.balance` từ `priv/game_data/` (rules.json, upgrade.json, chaos.json). **Đừng sửa tay**: đổi số
> trong dữ liệu rồi chạy lại. Giải thích các khóa: `docs/ITEMS_PHASE15B.md`.

## 1. Đồ rơi mỗi lần hạ một quái

Xác suất trên **một** con quái (số trong ngoặc: trung bình bao nhiêu con thì ra một lần). Đồ rơi theo loại:
trang sức 6.00 %, bộ giáp 43.00 %, khiên 13.00 %, vũ khí 38.00 %. Trùm thế giới / đấu trường không rơi đồ hiếm.

| Quái | Đồ hiếm | Excellent | May mắn | Vũ khí Kỹ năng | Đồ Thần |
|---|---|---|---|---|---|
| thường | 6.00 % (~17 con) | 0.60 % (~167 con) | 0.60 % (~167 con) | 0.34 % (~292 con) | 0.13 % (~775 con) |
| đêm | 25.00 % (~4 con) | 2.00 % (~50 con) | 3.75 % (~27 con) | 1.42 % (~70 con) | 0.22 % (~465 con) |
| tinh anh | 50.00 % (~2 con) | 6.00 % (~17 con) | 10.00 % (~10 con) | 2.85 % (~35 con) | 0.86 % (~116 con) |
| trùm | 35.00 % (~3 con) | 7.00 % (~14 con) | 12.25 % (~8 con) | 1.99 % (~50 con) | 1.20 % (~83 con) |

## 2. Ép +1 → +11 (kiểu MU, DECISIONS B-13)

| Bước | Ngọc | Tỉ lệ | Có May mắn | Thất bại |
|---|---|---|---|---|
| +1 | 1 Ngọc Ước Nguyện | 100.00 % | 100.00 % | — |
| +2 | 1 Ngọc Ước Nguyện | 100.00 % | 100.00 % | — |
| +3 | 1 Ngọc Ước Nguyện | 100.00 % | 100.00 % | — |
| +4 | 1 Ngọc Ước Nguyện | 100.00 % | 100.00 % | — |
| +5 | 1 Ngọc Ước Nguyện | 100.00 % | 100.00 % | — |
| +6 | 1 Ngọc Ước Nguyện | 100.00 % | 100.00 % | — |
| +7 | 1 Ngọc Tâm Linh | 50.00 % | 75.00 % | về +0 |
| +8 | 1 Ngọc Tâm Linh | 50.00 % | 75.00 % | về +0 |
| +9 | 1 Ngọc Tâm Linh | 50.00 % | 75.00 % | về +0 |
| +10 | 1 Ngọc Ước Nguyện + 1 Ngọc Hỗn Nguyên + 1 Ngọc Tâm Linh | 50.00 % | 75.00 % | vỡ đồ |
| +11 | 2 Ngọc Ước Nguyện + 1 Ngọc Hỗn Nguyên + 2 Ngọc Tâm Linh | 45.00 % | 70.00 % | vỡ đồ |

## 3. Máy Hỗn Nguyên

| Công thức | Cần | Tỉ lệ | Cấp cần +2 | Ở +11 | Vàng | Nguyên liệu |
|---|---|---|---|---|---|---|
| Cánh cấp 1 (`wing1`) | +5 | 10.00 % | 20.00 % | 40.00 % | 20000 | 1 Ngọc Hỗn Nguyên |
| Cánh cấp 2 (`wing2`) | +5 | 20.00 % | 30.00 % | 50.00 % | 200000 | 5 Ngọc Ước Nguyện, 2 Ngọc Hỗn Nguyên, 5 Ngọc Tâm Linh |
| Cánh cấp 3 (`wing3`) | +9 | 15.00 % | 25.00 % | 25.00 % | 500000 | 1 Lông Vũ Kền Kền, 10 Ngọc Ước Nguyện, 3 Ngọc Hỗn Nguyên, 3 Ngọc Sinh Mệnh, 10 Ngọc Tâm Linh |
| Ngọc Hỗn Nguyên (`make_chaos`) | — | 70.00 % | 70.00 % | 70.00 % | 5000 | 1 Vảy Cổ Long, 10 Quặng Mithril |
| Pha Excellent (`add_exc`) | +5 | 30.00 % | 40.00 % | 60.00 % | 100000 | 1 Ngọc Hỗn Nguyên, 2 Ngọc Sinh Mệnh |
| Pha May mắn (`add_luck`) | +3 | 50.00 % | 60.00 % | 75.00 % | 50000 | 3 Ngọc Ước Nguyện, 1 Ngọc Hỗn Nguyên |

## 4. Simulator (chơi từ đầu tới Hắc Long)

_Chưa chạy simulator (`mix hac_long.balance --sim 3`)._

