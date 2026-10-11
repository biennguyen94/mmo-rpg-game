# Sự kiện trong game — Hắc Long

Tài liệu cho người chơi: các sự kiện hiện có, giờ mở, cách tham gia và phần thưởng. Mọi giờ là **giờ Việt Nam**.
Số liệu lấy từ `priv/game_data/rules.json` (khóa ghi trong ngoặc) và `priv/game_data/events.json`; đổi số ở đó thì sửa
lại tài liệu này. Chi tiết kỹ thuật của Quảng Trường Quỷ và Lâu Đài Máu: `docs/EVENTS_PHASE18.md`.

## Mục lục

1. [Lịch trong ngày](#1-lịch-trong-ngày)
2. [Golden Invasion — quái vàng](#2-golden-invasion--quái-vàng)
3. [Quảng Trường Quỷ (Devil Square)](#3-quảng-trường-quỷ-devil-square)
4. [Lâu Đài Máu (Blood Castle)](#4-lâu-đài-máu-blood-castle)
5. [Trùm thế giới Cổ Long](#5-trùm-thế-giới-cổ-long)
6. [Lễ hội theo mùa](#6-lễ-hội-theo-mùa)
7. [Hoạt động hằng ngày](#7-hoạt-động-hằng-ngày)
8. [Hoạt động lúc nào cũng có](#8-hoạt-động-lúc-nào-cũng-có)
9. [Dành cho quản trị viên](#9-dành-cho-quản-trị-viên)

---

## 1. Lịch trong ngày

Ba sự kiện chạy xen kẽ, mỗi sự kiện lặp lại **mỗi 2 giờ**:

| Giờ (lặp mỗi 2 giờ) | Sự kiện | Cấp | Vé | Thời gian |
|---|---|---|---|---|
| 0h00, 2h00, 4h00 … 22h00 | Golden Invasion | mọi cấp | không cần | 15 phút |
| 0h30, 2h30, 4h30 … 22h30 | Lâu Đài Máu | từ 40 | Vé Lâu Đài | mở cửa 10 phút, mỗi lượt 8 phút |
| 1h00, 3h00, 5h00 … 23h00 | Quảng Trường Quỷ | từ 35 | Vé Quảng Trường | mở cửa 10 phút, mỗi lượt 5 phút |

Trùm thế giới Cổ Long xuất hiện khoảng **2 giờ một lần**, mỗi lần 30 phút; lịch tính từ lúc server khởi động (lần đầu sau
10 phút) nên không cố định theo giờ đồng hồ. Khi trùm xuất hiện, cả server nhận thông báo trong chat.

## 2. Golden Invasion — quái vàng

(`RULES.invasion`)

- **Khi nào:** 0h, 2h, 4h … 22h, kéo dài 15 phút. Dải vàng trên bản đồ cho biết thời gian còn lại.
- **Ở đâu:** bản đồ đầu của mỗi vùng: Rừng Mê 1, Trại Goblin 1, Nghĩa Địa Cổ 1, Núi Khổng Lồ 1, Đầm Lầy Rồng 1,
  Hang Hắc Long 1 — mỗi bản đồ 4 quái vàng (có quầng vàng quanh người).
- **Tham gia:** không cần vé, không giới hạn cấp — chỉ cần đi tới bản đồ đó và đánh. Ai nhanh tay thì được.
- **Quái vàng:** mạnh hơn quái thường ×1,5; thưởng vàng / kinh nghiệm **×5**; 10 % rơi ngọc; hạ rồi không hồi sinh.
- **Trùm vàng:** hạ hết quái vàng của một bản đồ thì trùm vàng xuất hiện ở đó, hạ được **chắc chắn rơi ngọc**.

Mẹo: chọn vùng hợp cấp mình (dùng **Chọn map**, phím M, để đi nhanh) và tới ngay đầu giờ chẵn.

## 3. Quảng Trường Quỷ (Devil Square)

(`RULES.devil_square`)

- **Khi nào:** 1h, 3h, 5h … 23h; cho vào trong **10 phút** đầu. Mỗi lần mở, mỗi nhân vật vào **một lần**.
- **Điều kiện:** cấp **35** trở lên và 1 **Vé Quảng Trường**.
- **Vé:** mua ở Người Gác Tháp giá **20.000 vàng**, hoặc nhặt từ quái thường cấp ≥ 30 (1 %).
- **Cách vào:** Làng → **Người Gác Tháp** → thẻ **😈 Quảng Trường Quỷ** → Vào.
- **Cách chơi:** bản đồ riêng, **5 phút**, **5 đợt**: 4 / 5 / 6 / 6 quái rồi 2 trùm (các trùm vùng). Hạ hết một đợt thì cầu
  thang "Đợt sau" mở. Quái theo cấp mình: cấp 35–39 → quái cấp 36, 40–44 → 42, 45+ → 48 (mỗi đợt cao hơn một chút).
- **Kết thúc:** hết giờ, gục ngã, qua hết 5 đợt, hoặc tự đi cầu thang "Về Làng". Lúc nào cũng nhận thưởng theo điểm đã có.
- **Điểm:** mỗi quái 1 điểm, mỗi trùm 10 điểm (tối đa 41).
- **Thưởng:**
  - vàng và kinh nghiệm theo điểm (lượt đủ ≈ 17.000–22.000 vàng, ≈ 1 cấp kinh nghiệm);
  - cứ **8 điểm một viên ngọc** (Ước Nguyện / Tâm Linh / Hỗn Nguyên / Sinh Mệnh);
  - **qua hết 5 đợt:** thêm 1 món đồ có dòng cộng thêm +8 / +12; 30 % là đồ **Hoàn hảo**, 15 % là **đồ Thần** (nếu là món bộ giáp).
- **Top ngày:** 3 người điểm cao nhất mỗi ngày nhận thêm qua thư lúc **0h05**:

  | Hạng | Thưởng |
  |---|---|
  | 1 | 100.000 vàng + 3 Ngọc Hỗn Nguyên + 3 Ngọc Tâm Linh |
  | 2 | 60.000 vàng + 2 Hỗn Nguyên + 2 Tâm Linh |
  | 3 | 30.000 vàng + 1 Hỗn Nguyên + 1 Tâm Linh |

Quái trong Quảng Trường không rơi đồ / ngọc riêng; thưởng tính một lần lúc kết thúc.

## 4. Lâu Đài Máu (Blood Castle)

(`RULES.blood_castle`)

- **Khi nào:** 0h30, 2h30, 4h30 … 22h30; cho vào trong **10 phút** đầu; mỗi lần mở vào **một lần**.
- **Điều kiện:** cấp **40** trở lên và 1 **Vé Lâu Đài**.
- **Vé:** mua ở Người Gác Tháp giá **30.000 vàng**, hoặc nhặt từ quái thường cấp ≥ 35 (0,5 %).
- **Cách vào:** Làng → **Người Gác Tháp** → thẻ **🏰 Lâu Đài Máu** → Vào.
- **Cách chơi:** bản đồ riêng, **8 phút**, ba bước:
  1. hạ **8 quân canh**;
  2. phá **Cổng Thành** (không đánh trả, nhiều máu) — ở gần cầu thang lên;
  3. hạ trùm **Hiệp Sĩ Máu** (mạnh hơn quân canh nhiều).

  Quái theo cấp mình: cấp 40–44 → 44, 45+ → 50.
- **Thắng (hạ trùm):** ≈ 25.000–28.000 vàng, kinh nghiệm, **2 ngọc** và **1 Lông Vũ Kền Kền** — nguyên liệu bắt buộc để ghép
  **cánh cấp 3** ở Máy Hỗn Nguyên (ghép hỏng mất lông vũ). Bước tiếp theo về Làng.
- **Không xong** (hết giờ, gục, tự về): thưởng theo số quân canh đã hạ (đủ 8 ≈ 4.800 vàng), không có lông vũ.

## 5. Trùm thế giới Cổ Long

(`config :hac_long, :world_boss`, `HacLong.WorldBoss`)

- **Khi nào:** khoảng 2 giờ một lần, mỗi lần **30 phút**; cả server nhận thông báo khi trùm xuất hiện.
- **Ở đâu:** **Tế Đàn** — đi từ cổng ở Làng.
- **Cách chơi:** cả server đánh chung **một thanh máu**. Mỗi người đánh theo lượt như trận thường, trùm đánh trả từng người.
- **Thưởng** (khi trùm gục) — ai có gây sát thương đều được, theo **phần sát thương** của mình so với máu trùm:
  - vàng: 300 + 5.000 × phần sát thương; kinh nghiệm: 1.000 + 30.000 × phần sát thương;
  - **3 người gây nhiều sát thương nhất**: thêm **Vảy Cổ Long** + 1 viên ngọc;
  - **người ra đòn cuối**: thêm 500 vàng;
  - đã thoát game vẫn nhận (gửi thẳng vào nhân vật).
- Hết 30 phút chưa hạ được thì trùm bay đi, **không ai được thưởng** — nên rủ cả bang / tổ đội cùng đánh.

## 6. Lễ hội theo mùa

(`priv/game_data/events.json`, `RULES.events`)

Tự bật theo ngày trong năm, không cần quản trị viên làm gì:

| Lễ hội | Thời gian | Quái rơi |
|---|---|---|
| 🏮 Tết Trung Thu | 15/9 – 10/10 | Bánh Trung Thu |
| 🎃 Lễ Hội Bí Ngô | 25/10 – 7/11 | Kẹo Bí Ngô |
| 🎄 Giáng Sinh | 15/12 – 2/1 | Hộp Quà |
| 🧧 Tết Nguyên Đán | 20/1 – 20/2 | Quả Lộc |

- Trong mùa lễ hội: **kinh nghiệm +10 %**, đánh quái thường có thể rơi vật phẩm lễ hội.
- **Đổi quà** ở **Người Tổ Chức Hội** (Làng):

  | Quà | Giá (vật phẩm lễ hội) |
  |---|---|
  | Đồ trang trí Nhà riêng của lễ hội | 30 |
  | Túi Quà Lễ Hội: một món đồ hợp cấp, chắc chắn có dòng cộng thêm | 12 |
  | 3 bình máu lớn | 6 |
  | Vàng (60 + 12 × cấp) | 3 |

## 7. Hoạt động hằng ngày

Làm mới lúc 0h mỗi ngày.

- **Bảng Tin** (Làng): 4 việc — diệt quái, đánh ở một vùng, nhặt nguyên liệu, câu cá; xong việc nhận vàng + kinh nghiệm.
- **Rương Gia Truyền** (ở Nhà): mở **một lần mỗi ngày** — vàng, bình máu, nguyên liệu, 20 % có thêm một món đồ.
- **Trùm vùng:** lần đầu mỗi ngày hạ một trùm vùng được thêm ngọc (vùng 1–3: Ngọc Ước Nguyện, vùng 4–6: Ngọc Tâm Linh).
  Lần đầu tiên hạ mỗi trùm: chắc chắn một món đồ đúng lớp có dòng +8 / +12 và danh hiệu "Diệt <tên trùm>".
- **Đấu trường:** tối đa **15 trận** mỗi ngày, thắng lên điểm xếp hạng, thua không mất gì.
- **PK cược vàng:** tối đa **10 trận** mỗi ngày (cược 100 – 1.000.000 vàng).

## 8. Hoạt động lúc nào cũng có

- **Tháp Vô Tận** (Người Gác Tháp): leo từng tầng, hạ hết quái để lên; cứ 5 tầng có trùm; máu không tự hồi trong tháp.
- **Ban đêm:** quái hiếm xuất hiện nhiều hơn (12 %).
- **Chiến bang:** bang chủ / phó tuyên chiến bang khác, trận 60 phút; bang thắng nhận 5.000 vào quỹ, thành viên có ít nhất 1 điểm nhận 500 vàng qua thư.
- **Đồ sát** (từ cấp 10, ngoài Làng và Nhà): tấn công người khác; giết người bị tên đỏ 30 phút.
- **Tiến Lên Miền Nam** (Bà Chủ Sòng ở Làng): chơi vui hoặc cược vàng (cược S cần ít nhất 2×S vàng).

## 9. Dành cho quản trị viên

- **Mở sự kiện ngay** (tab Quản trị → khung **Sự kiện**): 🐉 Gọi Cổ Long, ✨ Golden Invasion, 😈 Mở Quảng Trường Quỷ,
  🏰 Mở Lâu Đài Máu. Quảng Trường / Lâu Đài mở một đợt riêng ngoài lịch, cho vào trong 10 phút, cả server nhận thông báo;
  người chơi vẫn cần vé và đủ cấp, ai đã vào đợt thường vẫn vào được đợt này.
- **Đổi lịch trùm thế giới** (biến môi trường, khởi động lại server; xem `config/runtime.exs`):
  `WORLD_BOSS_FIRST_MINUTES` (lần đầu sau khởi động, mặc định 10), `WORLD_BOSS_EVERY_MINUTES` (120),
  `WORLD_BOSS_DURATION_MINUTES` (30), `WORLD_BOSS_HP` (20.000).
- **Đổi giờ / số liệu các sự kiện khác:** sửa `priv/game_data/rules.json` (`invasion`, `devil_square`, `blood_castle`,
  `events`, `daily`, `arena`, `pk`…) rồi khởi động lại; lễ hội thêm / sửa ở `priv/game_data/events.json`.
- **Tặng vé:** tab Quản trị → Đồ thường → `ds_ticket` (Vé Quảng Trường) / `bc_ticket` (Vé Lâu Đài).
