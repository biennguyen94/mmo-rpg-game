# Kinh tế vật phẩm — cày hay mua bằng vàng?

So sánh, cho từng vật phẩm sự kiện / ngọc / bình, **cần hạ xấp xỉ bao nhiêu quái** nếu tự cày (chờ rơi, ghép) và nếu
mua bằng vàng (quy số vàng ra số quái phải hạ để kiếm đủ). Số lấy từ `priv/game_data/rules.json`, `chaos.json`,
`items.json` (tháng 10/2026, sau DECISIONS B-23). Đổi số ở đó thì sửa lại bảng này.

## Cách tính

- **Vàng mỗi quái** (`Engine.base_gold/1`, chưa tính may rủi ±20 %, trùm, quái vàng, bang):

  | Cấp quái | 12 | 15 | 20 | 25 | 30 | 35 | 40 | 45 | 50 |
  |---|---|---|---|---|---|---|---|---|---|
  | Vàng / quái | 29 | 36 | 47 | 58 | 69 | 80 | 91 | 102 | 113 |

- **"Quái để mua"** = giá ÷ vàng / quái ở cấp vào sự kiện.
- **"Quái để cày"** = số quái trung bình để rơi đủ nguyên liệu (dài hạn: mỗi mảnh rơi đều nhau), chia tỉ lệ ghép thành
  công. Vàng ghép cũng quy ra quái, cộng vào cột **tổng**.
- Chỉ là trung bình: thực tế lệch nhiều do may rủi. Tỉ lệ rơi chỉ tính quái thường (không tính tháp, trùm thế giới, đấu trường).

## Vé và nguyên liệu sự kiện

| Vật phẩm | Mua bằng vàng | Cày: rơi | Cày: quái để có 1 cái | Vàng ghép | Tổng cày (quy ra quái) |
|---|---|---|---|---|---|
| **Vé Quảng Trường** (cấp 35+) | 20.000 ≈ **250 quái** (cấp 35) | Mắt Quỷ / Chìa Khóa Quỷ: quái cấp 30+ rơi 5 % (một trong 2 mảnh) | 40 quái / cặp ÷ 80 % ≈ **50 quái** | 12.000 / lần ≈ 15.000 / vé ≈ 190 quái | ≈ **240 quái** |
| **Vé Lâu Đài** (cấp 40+) | 30.000 ≈ **330 quái** (cấp 40) | Cuộn Giấy Tổng Lãnh Thiên Thần / Xương Máu: quái cấp 35+ rơi 4 % | 50 quái / cặp ÷ 80 % ≈ **63 quái** | 18.000 / lần ≈ 22.500 / vé ≈ 250 quái | ≈ **310 quái** |
| **Áo Giáp Vệ Binh** (Hỗn Chiến Thành, cấp 15+) | 5.000 ≈ **140 quái** (cấp 15), ≈ 70 quái (cấp 30) | quái cấp 15+ rơi 2 % | **50 quái** | — | **50 quái** |
| **Bản Đồ Thất Lạc** (Kalima, cấp 20+) | không bán | Dấu Ấn Kundun: quái cấp 20+ rơi 4 %, cần 5 | **125 quái** | 5.000 ≈ 105 quái (cấp 20), 70 (cấp 30) | ≈ **200–230 quái** |
| Lông Vũ Kền Kền | không bán | chỉ thưởng khi hạ Hiệp Sĩ Máu (Lâu Đài Máu) | 1 lượt Lâu Đài thành công | — | — |

**Nhận xét:**
- Áo Giáp Vệ Binh: cày rẻ hơn mua rõ rệt (50 so với 140 quái ở cấp 15); mua là để tiết kiệm thời gian.
- Vé Quảng Trường / Lâu Đài: phần lớn chi phí cày là **vàng ghép**, nên tổng cày chỉ rẻ hơn mua khoảng 5–10 %. Cày có lợi
  khi đã có sẵn mảnh rơi trong lúc đánh quái thường; muốn cày thật sự rẻ hơn thì giảm vàng ghép (`chaos.json`).
- Vé, mảnh vé, Dấu Ấn Kundun, Bản Đồ Thất Lạc **không bán lại cho NPC được** (giá 0), nên không có vòng cày → bán lấy lời.

## Ngọc

Không bán ở cửa hàng. Bán lại cho NPC: Ước Nguyện 1.000, Tâm Linh 1.500, Hỗn Nguyên 1.250, Sinh Mệnh 1.250 vàng.

| Ngọc | Quái cấp 12+ rơi (0,6 % một viên, chia theo trọng số) | Quái để có 1 viên | Nguồn khác |
|---|---|---|---|
| Ước Nguyện | 0,6 % × 50 % = 0,30 % | ≈ **330 quái** | trùm vùng 30 %, rương, tháp, Quảng Trường, Lâu Đài, Kalima, Hỗn Chiến Thành, Công Thành Chiến |
| Tâm Linh | 0,6 % × 35 % = 0,21 % | ≈ **480 quái** | như trên; Phù Thủy Trắng rơi thêm 30 % |
| Hỗn Nguyên | 0,6 % × 15 % = 0,09 % | ≈ **1.100 quái** | ghép 10 Quặng Mithril + 1 Vảy Cổ Long + 5.000 vàng (70 %); Rồng Đỏ thêm 30 %, Phù Thủy Trắng thêm 50 % |
| Sinh Mệnh | 0,6 % × 10 % = 0,06 % | ≈ **1.700 quái** | Rồng Đỏ rơi thêm 10 % |

Ngọc là thứ quý nhất game (ép đồ, ghép cánh, +10 / +11), nên không có giá mua bằng vàng.

## Bình máu / mana

| Bình | Giá | Quái để mua | Rơi |
|---|---|---|---|
| Nhỏ | 15 | ≈ 1–3 quái (cấp 1–8) | 12 % mỗi quái (loại bình theo cấp quái: cấp 0–8 nhỏ, 9–19 vừa, 20+ lớn) → ≈ 8 quái / bình |
| Vừa | 55 | ≈ 2 quái (cấp 10) | |
| Lớn | 150 | ≈ 2–3 quái (cấp 25) | |

Mua rẻ hơn chờ rơi; bình rơi chỉ là phần thưởng thêm. Hợp lý vì bình là đồ tiêu hao hằng ngày.

## Chi phí lớn khác

| Việc | Vàng | Quy ra quái |
|---|---|---|
| Đăng ký Công Thành Chiến (bang chủ / phó) | 200.000 | ≈ 2.200 quái cấp 40 (một lần / tuần / bang) |
| Pha Excellent / ép +10, +11 ở Máy Hỗn Nguyên | xem `docs/BALANCE_REPORT.md` §2–3 | — |

## Trang bị

Thợ Rèn chỉ bán **đồ cơ bản cấp ≤ 17** (75 món: vũ khí, khiên, bộ giáp 4 bậc đầu; DECISIONS B-24, kiểu MU). Đồ cấp 22+
chỉ có từ quái rơi, sự kiện, rương, chợ / giao dịch. Đồ rơi: mỗi quái thường 8 % ra một món (Bóng Đêm 25 %, trùm 35 %,
tinh anh 50 %), chia theo ô (vũ khí 38 %, bộ giáp 43 % chia đều 5 món, khiên 13 %, trang sức 6 %), rồi chia đều các món
hợp cấp quái **và hợp lớp mình**. Thư viện ghi khoảng cấp quái rơi từng món. Thêm từ thưởng Quảng Trường Quỷ, Kalima
(hạ Kundun), rương.

Ví dụ trước B-24 (giá Thợ Rèn cũ; quái ở đúng cấp món, rơi 6 %; "rơi đúng món" tính trên mọi lớp, nên với một lớp thực tế
ít hơn khoảng 2–4 lần). Từ B-24, các món cấp 22+ không còn bán, rơi nhanh hơn ~25 %:

| Món | Cấp | Giá Thợ Rèn | Quái để mua | Quái để rơi đúng món |
|---|---|---|---|---|
| Mũ / giày / găng bậc thấp | 3–7 | 7–60 | 1–3 | 600–1.400 |
| Giáp Hộ Vệ | 17 | 456 | ≈ 11 | ≈ 1.200 |
| Giáp Phượng Hoàng Đen | 32 | 4.253 | ≈ 58 | ≈ 3.700 |
| Giáp Tia Tiên | 48 | 16.471 | ≈ 150 | ≈ 2.500 |
| Cung Hổ | 22 | 3.600 | ≈ 70 | ≈ 1.000 |
| Gậy Sấm Hỗn Nguyên | 32 | 15.000 | ≈ 200 | ≈ 1.200 |
| Chùy Băng Giá | 42 | 50.000 | ≈ 520 | ≈ 900 |
| Khiên Diệt Rồng | 27 | 7.500 | ≈ 120 | ≈ 510 |
| Khiên Nguyên Tố | 46 | 45.000 | ≈ 430 | ≈ 510 |

**Nhận xét:** đồ cơ bản mua rẻ hơn chờ rơi nhiều, để người mới có đồ nhanh. Từ cấp 22 phải cày / săn sự kiện / mua chợ,
nên đồ rơi (nhất là có dòng cộng thêm, Excellent, Thần) có giá trị thật và chợ có hàng để bán.
