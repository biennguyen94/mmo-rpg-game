# Rà soát công thức (Phase 8, 2026-10-16)

Kiểm lại toàn bộ công thức chỉ số nhân vật, quái, sát thương, phòng thủ, kỹ năng và mọi dòng cộng thêm trên đồ:
có thật sự được cộng vào chỉ số không, có đúng số trong `priv/game_data/` không. Mỗi mục có test ở
`test/hac_long/game/formula_audit_test.exs` (đọc số từ RULES, không chép số). Bảng §3 tạo bằng
`mix run --no-start scripts/formula_table.exs`.

## 1. Công thức (nơi tính: `Engine.derived/1`, `Engine.damage/4`, `Engine.make_monster/2`)

| Chỉ số | Công thức |
|---|---|
| Máu tối đa | (hệ số lớp × STR/AGI/VIT/ENE/cấp + máu nhẫn + thưởng đủ bộ + đồ Thần + dòng cánh `hp`) × (1 + thú + món ăn + Đài Phúc Lành) × (1 + Excellent `hp_pct`) |
| MP tối đa | (hệ số lớp + dòng cánh `mp`) × (1 + Excellent `mp_pct`) |
| Tấn công | (hệ số lớp + Excellent `atk_lvl` × cấp + công vũ khí + ép vũ khí + dòng cộng thêm vũ khí + công dây chuyền + ép / dòng dây chuyền) × (1 + thú + món ăn + Đài) × (1 + Excellent `atk_pct` + đủ bộ `atk_pct` + đồ Thần `atk_pct`) |
| Phòng thủ | (hệ số lớp + Σ thủ các ô giáp / khiên / cánh / mũ / quần / găng / giày / nhẫn + ép + dòng cộng thêm từng món) × (1 + thú + món ăn + Đài) × (1 + đủ bộ `def_pct` + đồ Thần `def_pct`) |
| Ép +N | mỗi cấp hiệu dụng + `bonus_pct` (8 %) chỉ số gốc món (công / thủ; nhẫn chỉ có máu thì cộng máu), ít nhất +1; cấp hiệu dụng = N, từ +10 mỗi cấp tính 2 |
| Chí mạng | min(0,6; 0,04 + AGI × 0,0035) + Excellent `crit` + May mắn vũ khí 5 %; hệ số chí mạng min(2,5; 1,6 + AGI × 0,004) |
| Né | min(0,6; min(0,4; 0,02 + AGI × 0,0025) × (1 + Excellent `def_rate` cộng dồn)) |
| Trúng quái | AR / (AR + cấp quái × 0,8), trong [5 %, 95 %]; AR = cấp × 5 + AGI × 1,5, × (1 + Excellent `ar_pct`). Kỹ năng luôn trúng |
| Sát thương một đòn | đòn = công × ngẫu nhiên [0,9; 1,1] × hệ số (kỹ năng, chí mạng, sổ quái, % cánh, Kỹ năng vũ khí); trừ thủ: đòn² / (đòn + thủ × (1 − bỏ qua thủ)), không dưới 20 % đòn; × phần nhận (thủ thế, hấp thụ cánh, Excellent giảm sát thương ≤ 20 %); ít nhất 1 |
| Quái cấp L | máu 170 + 26L + 0,6L² (trùm × 2,4); công 10 + 6,4L; thủ 1 + 2L; chí mạng 5 % × 1,5; không né (trúng theo AR / DR) |
| Cánh | thủ cánh + ép; sát thương / hấp thụ = số cánh + 2 % × cấp ép hiệu dụng; dòng phụ hp / mp / bỏ qua thủ |
| Đồ Thần | thủ món × 1,2; 2 món +3 % công, 3 món +5 % thủ, đủ bộ +5 % công +5 % thủ +150 máu (cộng dồn) |
| Đủ bộ giáp (bậc ≥ 2) | +10 % thủ, +3 % công, + 15 × bậc máu |

## 2. Kết quả kiểm

**Đúng (có test):**
- Dòng cộng thêm: vũ khí / dây chuyền → tấn công, giáp / khiên / cánh / nhẫn → phòng thủ, +4 mỗi dòng.
- Ép +1…+11, cấp hiệu dụng gấp đôi từ +10.
- Cả 12 dòng Excellent: cộng đúng chỉ số; trần giảm sát thương / phản đòn 20 % khi mặc nhiều món.
  - `gold_pct` vào vàng khi hạ quái.
  - `heal_kill` / `mp_kill` hồi khi hạ quái.
- May mắn: vũ khí +5 % chí mạng; giáp không cộng chí mạng, chỉ +25 % tỉ lệ ép. Kỹ năng: +10 % sát thương chiêu.
- Đồ Thần: thủ từng món, mức thưởng bộ. Đủ bộ giáp.
- Cánh: thủ, ép, % sát thương / hấp thụ, dòng phụ.
- Nhẫn máu, Đài Phúc Lành.
- Sát thương: trừ thủ, sàn mềm, sàn cứng, phần nhận. Tỉ lệ trúng.
- Kỹ năng: hệ số khớp mô tả (220 %, 200 % xuyên 30 %, chắc chí mạng xuyên 50 %, 130 % + hồi 25 %…).
  - Thời lượng hiệu ứng khớp mô tả: Nộ Chiến 3 lượt tiếp theo; thủ thế / ảnh bộ / suy yếu tính cả lượt dùng; độc 3 lần.

**Lỗi đã sửa:**
1. **Đánh người (Đồ sát): phần giảm sát thương của đối thủ bị bỏ qua.** Hấp thụ của cánh và Excellent "giảm sát thương" không có tác dụng.
   - Ở Đấu trường / PK cược, hấp thụ cánh được quy vào máu nhưng thiếu Excellent.
   - Giờ bản sao đối thủ mang `taken` = (1 − hấp thụ cánh) × (1 − giảm Excellent) và máu thật; Engine và PK cược đều nhân phần này.
2. **Dòng cánh "bỏ qua phòng thủ" của đối thủ không có tác dụng khi họ đánh mình** (Đấu trường, Đồ sát, PK cược). Đã áp dụng.
3. **Chí mạng của bản sao đối thủ luôn × 1,5** (hệ số của quái) thay vì hệ số chí mạng thật của người đó (tới × 2,5). Đã dùng hệ số thật.

**Đã chỉnh theo anh chốt ("A, B, C, D ok", DECISIONS B-28):**

| # | Điểm | Hiện tại | Đề xuất |
|---|---|---|---|
| A | Excellent **"tấn công + cấp × giá trị"** (`atk_lvl` 0,1) | Cấp 50: +5 công ≈ 0,7 % tấn công. Dòng yếu nhất, gần như vô dụng so với `atk_pct` +5 % | `atk_lvl` = **0,6** (cấp 50 ≈ +30 công ≈ 4 %) |
| B | **Né vượt trần** khi mặc nhiều món Excellent `def_rate` | Trần 40 % nhân thêm (1 + 0,1 × số món): mặc đủ 9 món → **76 %** né | Chặn né sau khi nhân ở **60 %** (`combat.dodge.max_total`) |
| C | **Ép nhẫn máu** (Nhẫn Băng / Lửa / Gió) | Mỗi cấp chỉ +1 phòng thủ (nhẫn không có thủ), máu không tăng | Ép nhẫn máu tăng **máu** 8 % mỗi cấp hiệu dụng như ép công / thủ |
| D | `monster.dodge` trong RULES | Không dùng ở đánh quái (trúng tính theo AR / DR) | Ghi rõ là không dùng, hoặc bỏ |

## 3. Bảng số theo lớp (quái thường cùng cấp)

Phân điểm giả định:
- Kiếm Sĩ: STR 50 %, VIT 30 %, AGI 20 %.
- Phù Thủy: ENE 55 %, VIT 30 %, STR 10 % (đủ mặc giáp), AGI 5 %.
- Tiên Nữ: AGI 55 %, VIT 30 %, STR 15 %.
- Đấu Sĩ: STR 35 %, ENE 25 %, VIT 25 %, AGI 15 %.

Đồ tốt nhất mặc được ở cấp đó; "+7, 2 dòng" là mọi món ép +7 có 2 dòng cộng thêm; không cánh, không Excellent.

Cột:
- **Đòn TB:** sát thương trung bình một đòn thường, đã tính chí mạng.
- **Lượt hạ:** số lượt hạ quái, đã tính tỉ lệ trúng.
- **Quái đánh TB:** sát thương trung bình quái gây mỗi lượt, đã tính né.
- **Lượt chết:** số lượt tới khi gục nếu không uống bình.

| Lớp | Cấp | Đồ | Máu | Tấn công | Thủ | Chí mạng | Né | Trúng | Quái: máu / công / thủ | Đòn TB | Lượt hạ | Quái đánh TB | Lượt chết |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dk | 1 | trắng | 300 | 93 | 14 | 11% | 7% | 95% | 197 / 16 / 3 | 97 | 3 | 8 | 37 |
| dk | 10 | trắng | 575 | 185 | 36 | 14% | 9% | 92% | 490 / 74 / 21 | 183 | 3 | 46 | 13 |
| dk | 10 | +7, 2 dòng | 575 | 200 | 135 | 14% | 9% | 92% | 490 / 74 / 21 | 199 | 3 | 24 | 24 |
| dk | 25 | trắng | 900 | 335 | 85 | 19% | 13% | 91% | 1195 / 170 / 51 | 335 | 4 | 101 | 9 |
| dk | 25 | +7, 2 dòng | 900 | 364 | 182 | 19% | 13% | 91% | 1195 / 170 / 51 | 367 | 4 | 73 | 13 |
| dk | 40 | trắng | 1280 | 520 | 162 | 25% | 17% | 90% | 2170 / 266 / 81 | 543 | 5 | 141 | 10 |
| dk | 40 | +7, 2 dòng | 1280 | 584 | 273 | 25% | 17% | 90% | 2170 / 266 / 81 | 619 | 4 | 112 | 12 |
| dk | 50 | trắng | 1530 | 652 | 224 | 28% | 19% | 90% | 2970 / 330 / 101 | 704 | 5 | 163 | 10 |
| dk | 50 | +7, 2 dòng | 1530 | 744 | 370 | 28% | 19% | 90% | 2970 / 330 / 101 | 817 | 5 | 129 | 12 |
| dw | 1 | trắng | 199 | 99 | 14 | 10% | 7% | 95% | 197 / 16 / 3 | 103 | 3 | 8 | 25 |
| dw | 10 | trắng | 420 | 194 | 27 | 11% | 7% | 91% | 490 / 74 / 21 | 188 | 3 | 52 | 9 |
| dw | 10 | +7, 2 dòng | 420 | 209 | 102 | 11% | 7% | 91% | 490 / 74 / 21 | 204 | 3 | 30 | 15 |
| dw | 25 | trắng | 775 | 364 | 84 | 12% | 8% | 89% | 1195 / 170 / 51 | 347 | 4 | 107 | 8 |
| dw | 25 | +7, 2 dòng | 775 | 400 | 181 | 12% | 8% | 89% | 1195 / 170 / 51 | 385 | 4 | 78 | 10 |
| dw | 40 | trắng | 1140 | 557 | 140 | 14% | 9% | 88% | 2170 / 266 / 81 | 534 | 5 | 163 | 8 |
| dw | 40 | +7, 2 dòng | 1140 | 621 | 237 | 14% | 9% | 88% | 2170 / 266 / 81 | 603 | 5 | 131 | 9 |
| dw | 50 | trắng | 1380 | 699 | 226 | 14% | 10% | 88% | 2970 / 330 / 101 | 675 | 6 | 182 | 8 |
| dw | 50 | +7, 2 dòng | 1380 | 791 | 379 | 14% | 10% | 88% | 2970 / 330 / 101 | 775 | 5 | 142 | 10 |
| elf | 1 | trắng | 250 | 77 | 12 | 13% | 8% | 95% | 197 / 16 / 3 | 81 | 3 | 9 | 30 |
| elf | 10 | trắng | 525 | 157 | 30 | 22% | 14% | 94% | 490 / 74 / 21 | 162 | 4 | 46 | 12 |
| elf | 10 | +7, 2 dòng | 525 | 172 | 113 | 22% | 14% | 94% | 490 / 74 / 21 | 180 | 3 | 26 | 21 |
| elf | 25 | trắng | 940 | 303 | 76 | 36% | 25% | 93% | 1195 / 170 / 51 | 349 | 4 | 91 | 11 |
| elf | 25 | +7, 2 dòng | 940 | 340 | 159 | 36% | 25% | 93% | 1195 / 170 / 51 | 398 | 4 | 68 | 14 |
| elf | 40 | trắng | 1230 | 453 | 114 | 50% | 35% | 93% | 2170 / 266 / 81 | 602 | 4 | 124 | 10 |
| elf | 40 | +7, 2 dòng | 1230 | 517 | 189 | 50% | 35% | 93% | 2170 / 266 / 81 | 700 | 4 | 104 | 12 |
| elf | 50 | trắng | 1630 | 591 | 187 | 60% | 40% | 92% | 2970 / 330 / 101 | 880 | 4 | 130 | 13 |
| elf | 50 | +7, 2 dòng | 1630 | 686 | 300 | 60% | 40% | 92% | 2970 / 330 / 101 | 1043 | 4 | 106 | 16 |
| mg | 1 | trắng | 284 | 91 | 12 | 13% | 9% | 95% | 197 / 16 / 3 | 96 | 3 | 9 | 34 |
| mg | 10 | trắng | 563 | 174 | 25 | 16% | 11% | 93% | 490 / 74 / 21 | 174 | 4 | 51 | 12 |
| mg | 10 | +7, 2 dòng | 563 | 190 | 91 | 16% | 11% | 93% | 490 / 74 / 21 | 192 | 3 | 30 | 19 |
| mg | 25 | trắng | 992 | 323 | 68 | 22% | 15% | 91% | 1195 / 170 / 51 | 328 | 5 | 106 | 10 |
| mg | 25 | +7, 2 dòng | 992 | 353 | 134 | 22% | 15% | 91% | 1195 / 170 / 51 | 363 | 4 | 83 | 12 |
| mg | 40 | trắng | 1286 | 485 | 107 | 27% | 19% | 90% | 2170 / 266 / 81 | 515 | 5 | 158 | 9 |
| mg | 40 | +7, 2 dòng | 1286 | 549 | 174 | 27% | 19% | 90% | 2170 / 266 / 81 | 592 | 5 | 134 | 10 |
| mg | 50 | trắng | 1548 | 609 | 154 | 31% | 21% | 90% | 2970 / 330 / 101 | 669 | 5 | 182 | 9 |
| mg | 50 | +7, 2 dòng | 1548 | 701 | 249 | 31% | 21% | 90% | 2970 / 330 / 101 | 785 | 5 | 152 | 11 |

**Nhận xét:**
- Mọi lớp hạ quái cùng cấp trong 3–6 lượt và chịu được 8–16 lượt: nhịp ổn, không lớp nào bị kẹt.
- **Tiên Nữ dồn AGI chạm trần chí mạng 60 % và né 40 % ở cấp 50**, nên sát thương trung bình cao nhất (880–1043, các lớp khác 670–820). Bù lại Tiên Nữ không khiên, máu và thủ thấp hơn Kiếm Sĩ. Em thấy chấp nhận được (giống MU: Tiên Nữ AGI mạnh).
- Phù Thủy thủ thấp nhất và chết nhanh nhất (8–10 lượt). Hợp vai pháp sư, có Khiên Linh Hồn giảm 50 % sát thương.
- Ép +7 và 2 dòng cộng thêm: +13–15 % tấn công, +50–70 % phòng thủ. Ép có giá trị rõ, nhất là cho phòng thủ.
