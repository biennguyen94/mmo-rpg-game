# Báo cáo cân bằng (sinh tự động)

> Sinh bằng `mix hac_long.balance` từ `priv/game_data/` (rules.json, upgrade.json, chaos.json). **Đừng sửa tay**: đổi số
> trong dữ liệu rồi chạy lại. Giải thích các khóa: `docs/ITEMS_PHASE15B.md`.

## 1. Đồ rơi mỗi lần hạ một quái

Xác suất trên **một** con quái (số trong ngoặc: trung bình bao nhiêu con thì ra một lần). Đồ rơi theo loại:
trang sức 6.00 %, bộ giáp 43.00 %, khiên 13.00 %, vũ khí 38.00 %. Trùm thế giới / đấu trường không rơi đồ hiếm.

| Quái | Đồ hiếm | Excellent | May mắn | Vũ khí Kỹ năng | Đồ Thần |
|---|---|---|---|---|---|
| thường | 4.00 % (~25 con) | 0.16 % (~625 con) | 0.40 % (~250 con) | 0.23 % (~439 con) | 0.02 % (~5814 con) |
| đêm | 25.00 % (~4 con) | 2.00 % (~50 con) | 3.75 % (~27 con) | 1.42 % (~70 con) | 0.22 % (~465 con) |
| tinh anh | 50.00 % (~2 con) | 6.00 % (~17 con) | 10.00 % (~10 con) | 2.85 % (~35 con) | 0.86 % (~116 con) |
| trùm | 35.00 % (~3 con) | 7.00 % (~14 con) | 12.25 % (~8 con) | 1.99 % (~50 con) | 1.20 % (~83 con) |

## 2. Ép ngọc +6 → +11

| Bước | Ngọc | Tỉ lệ | Có May mắn | Thất bại |
|---|---|---|---|---|
| +6 | Ngọc Phúc Lành | 100.00 % | 100.00 % | — |
| +7 | Ngọc Linh Hồn | 70.00 % | 95.00 % | tụt 1 cấp |
| +8 | Ngọc Linh Hồn | 60.00 % | 85.00 % | tụt 1 cấp |
| +9 | Ngọc Linh Hồn | 50.00 % | 75.00 % | tụt 1 cấp |
| +10 | Ngọc Hỗn Nguyên | 50.00 % | 75.00 % | vỡ đồ |
| +11 | Ngọc Hỗn Nguyên | 45.00 % | 70.00 % | vỡ đồ |

## 3. Máy Hỗn Nguyên

| Công thức | Cần | Tỉ lệ | Cấp cần +2 | Ở +11 | Vàng | Nguyên liệu |
|---|---|---|---|---|---|---|
| Cánh cấp 1 (`wing1`) | +5 | 10.00 % | 20.00 % | 40.00 % | 20000 | 1 Ngọc Hỗn Nguyên |
| Cánh cấp 2 (`wing2`) | +5 | 20.00 % | 30.00 % | 50.00 % | 200000 | 5 Ngọc Phúc Lành, 2 Ngọc Hỗn Nguyên, 5 Ngọc Linh Hồn |
| Cánh cấp 3 (`wing3`) | +9 | 15.00 % | 25.00 % | 25.00 % | 500000 | 10 Ngọc Phúc Lành, 3 Ngọc Hỗn Nguyên, 3 Ngọc Sinh Mệnh, 10 Ngọc Linh Hồn |
| Ngọc Hỗn Nguyên (`make_chaos`) | — | 70.00 % | 70.00 % | 70.00 % | 5000 | 1 Vảy Cổ Long, 10 Quặng Mithril |
| Pha Excellent (`add_exc`) | +5 | 30.00 % | 40.00 % | 60.00 % | 100000 | 1 Ngọc Hỗn Nguyên, 2 Ngọc Sinh Mệnh |
| Pha May mắn (`add_luck`) | +3 | 50.00 % | 60.00 % | 75.00 % | 50000 | 3 Ngọc Phúc Lành, 1 Ngọc Hỗn Nguyên |

## 4. Simulator (chơi từ đầu tới Hắc Long)

| Lớp | Cách chơi | Số trận | Cấp cuối | Chết | Vàng cuối | Ngọc | Hạ Hắc Long |
|---|---|---|---|---|---|---|---|
| Kiếm Sĩ | chỉ đánh | 405 | 35 | 0 | 5808 | 3.7 | 3/3 |
| Kiếm Sĩ | +nhiệm vụ | 342 | 35 | 0 | 8886 | 4.7 | 3/3 |
| Kiếm Sĩ | +hằng ngày | 323 | 35 | 0 | 8766 | 9.0 | 3/3 |
| Kiếm Sĩ | +nâng cấp | 318 | 35 | 0 | 24916 | 8.7 | 3/3 |
| Kiếm Sĩ | +rương | 325 | 35 | 0 | 19431 | 8.3 | 3/3 |
| Phù Thủy | chỉ đánh | 409 | 35 | 0 | 17501 | 2.0 | 3/3 |
| Phù Thủy | +nhiệm vụ | 340 | 35 | 0 | 16840 | 2.3 | 3/3 |
| Phù Thủy | +hằng ngày | 324 | 35 | 0 | 14892 | 7.3 | 3/3 |
| Phù Thủy | +nâng cấp | 320 | 35 | 0 | 22917 | 9.0 | 3/3 |
| Phù Thủy | +rương | 324 | 35 | 0 | 16346 | 8.0 | 3/3 |
| Tiên Nữ | chỉ đánh | 408 | 35 | 1 | 2302 | 2.0 | 3/3 |
| Tiên Nữ | +nhiệm vụ | 366 | 36 | 2 | 3338 | 3.3 | 3/3 |
| Tiên Nữ | +hằng ngày | 322 | 35 | 1 | 5228 | 7.7 | 3/3 |
| Tiên Nữ | +nâng cấp | 320 | 35 | 0 | 18513 | 7.0 | 3/3 |
| Tiên Nữ | +rương | 336 | 35 | 1 | 12525 | 9.7 | 3/3 |
| Đấu Sĩ | chỉ đánh | 403 | 35 | 0 | 8266 | 3.0 | 3/3 |
| Đấu Sĩ | +nhiệm vụ | 340 | 35 | 0 | 12753 | 3.0 | 3/3 |
| Đấu Sĩ | +hằng ngày | 321 | 35 | 0 | 8471 | 8.7 | 3/3 |
| Đấu Sĩ | +nâng cấp | 319 | 35 | 0 | 23600 | 8.7 | 3/3 |
| Đấu Sĩ | +rương | 321 | 35 | 0 | 16226 | 10.3 | 3/3 |

