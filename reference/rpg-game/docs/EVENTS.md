# Sự kiện trong game — Hắc Long

Tài liệu cho người chơi: các sự kiện hiện có, giờ mở, cách tham gia và phần thưởng. Mọi giờ là **giờ Việt Nam**.
Số liệu lấy từ `priv/game_data/rules.json` (khóa ghi trong ngoặc) và `priv/game_data/events.json`; đổi số ở đó thì sửa
lại tài liệu này. Chi tiết kỹ thuật của Quảng Trường Quỷ và Lâu Đài Máu: `docs/EVENTS_PHASE18.md`. Cày hay mua vé / nguyên liệu (xấp xỉ
bao nhiêu quái): [`ECONOMY.md`](ECONOMY.md).

## Mục lục

1. [Lịch trong ngày](#1-lịch-trong-ngày)
2. [Golden Invasion — quái vàng](#2-golden-invasion--quái-vàng)
   - [Rồng Đỏ / Phù Thủy Trắng xâm lăng](#rồng-đỏ--phù-thủy-trắng-xâm-lăng)
3. [Quảng Trường Quỷ (Devil Square)](#3-quảng-trường-quỷ-devil-square)
4. [Lâu Đài Máu (Blood Castle)](#4-lâu-đài-máu-blood-castle)
   - [Hỗn Chiến Thành (Chaos Castle)](#hỗn-chiến-thành-chaos-castle)
   - [Kalima](#kalima)
   - [Công Thành Chiến (Castle Siege)](#công-thành-chiến-castle-siege)
5. [Trùm thế giới Cổ Long](#5-trùm-thế-giới-cổ-long)
6. [Lễ hội theo mùa](#6-lễ-hội-theo-mùa)
7. [Hoạt động hằng ngày](#7-hoạt-động-hằng-ngày)
8. [Hoạt động lúc nào cũng có](#8-hoạt-động-lúc-nào-cũng-có)
9. [Dành cho quản trị viên](#9-dành-cho-quản-trị-viên)

---

## 1. Lịch trong ngày

Bốn sự kiện chạy xen kẽ, mỗi sự kiện lặp lại **mỗi 2 giờ** (thêm hai cuộc xâm lăng **mỗi 4 giờ**):

| Giờ (lặp mỗi 2 giờ) | Sự kiện | Cấp | Vé | Thời gian |
|---|---|---|---|---|
| 0h00, 2h00, 4h00 … 22h00 | Golden Invasion | mọi cấp | không cần | 15 phút |
| 0h30, 2h30, 4h30 … 22h30 | Lâu Đài Máu | từ 40 | Vé Lâu Đài | mở cửa 10 phút, mỗi lượt 8 phút |
| 1h00, 3h00, 5h00 … 23h00 | Quảng Trường Quỷ | từ 35 | Vé Quảng Trường | mở cửa 10 phút, mỗi lượt 5 phút |
| 1h30, 3h30, 5h30 … 23h30 | Hỗn Chiến Thành | từ 15 | Áo Giáp Vệ Binh | cho vào 5 phút, hỗn chiến 10 phút |
| 0h45, 4h45, 8h45 … 20h45 | Phù Thủy Trắng xâm lăng | mọi cấp | không cần | 20 phút |
| 2h45, 6h45, 10h45 … 22h45 | Rồng Đỏ xâm lăng | mọi cấp | không cần | 20 phút |
| Thứ Bảy 20h00 (mỗi tuần) | Công Thành Chiến | từ 30, theo bang | bang đăng ký trước | 30 phút |

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

### Rồng Đỏ / Phù Thủy Trắng xâm lăng

(`RULES.raids`, DECISIONS B-20) Không cần vé, ai cũng đánh được; cả server nhận thông báo kèm tên bản đồ.

- **Rồng Đỏ** (2h45, 6h45 … 22h45, 20 phút): 3 bản đồ vùng ngẫu nhiên, mỗi bản đồ **2 Rồng Đỏ** (cấp trùm vùng + 4, mạnh,
  đứng yên). Hạ được: kinh nghiệm, vàng **×4**, **chắc chắn 1 ngọc**, có thể thêm Ngọc Hỗn Nguyên (30 %) / Sinh Mệnh (10 %).
- **Phù Thủy Trắng** (0h45, 4h45 … 20h45, 20 phút): 2 bản đồ, mỗi bản đồ **1 Phù Thủy Trắng** (cấp trùm vùng + 5) và **6 Lính
  Orc** đi lang thang. Phù Thủy: ×3, chắc chắn 1 ngọc, có thể thêm Hỗn Nguyên (50 %) / Tâm Linh (30 %); Lính Orc: ×3, ngọc 15 %.
- Quái xâm lăng không hồi sinh, tên màu cam trên bản đồ. Hạ hết → kết thúc sớm; hết giờ con chưa ai đánh biến mất.

## 3. Quảng Trường Quỷ (Devil Square)

(`RULES.devil_square`)

- **Khi nào:** 1h, 3h, 5h … 23h; cho vào trong **10 phút** đầu. Mỗi lần mở, mỗi nhân vật vào **một lần**.
- **Điều kiện:** cấp **35** trở lên và 1 **Vé Quảng Trường**.
- **Vé:** mua ở Người Gác Tháp giá **20.000 vàng**, hoặc **ghép** ở Máy Hỗn Nguyên: **Mắt Quỷ + Chìa Khóa Quỷ**
  + 12.000 vàng (80 %). Mắt / Chìa Khóa rơi từ quái thường cấp ≥ 30 (5 %).
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
- **Vé:** mua ở Người Gác Tháp giá **30.000 vàng**, hoặc **ghép** ở Máy Hỗn Nguyên: **Cuộn Giấy Tổng Lãnh Thiên Thần + Xương
  Máu** + 18.000 vàng (80 %). Hai mảnh rơi từ quái thường cấp ≥ 35 (4 %).
- **Cách vào:** Làng → **Người Gác Tháp** → thẻ **🏰 Lâu Đài Máu** → Vào.
- **Cách chơi:** bản đồ riêng, **8 phút**, ba bước:
  1. hạ **8 quân canh**;
  2. phá **Cổng Thành** (không đánh trả, nhiều máu) — ở gần cầu thang lên;
  3. hạ trùm **Hiệp Sĩ Máu** (mạnh hơn quân canh nhiều).

  Quái theo cấp mình: cấp 40–44 → 44, 45+ → 50.
- **Thắng (hạ trùm):** ≈ 25.000–28.000 vàng, kinh nghiệm, **2 ngọc** và **1 Lông Vũ Kền Kền** — nguyên liệu bắt buộc để ghép
  **cánh cấp 3** ở Máy Hỗn Nguyên (ghép hỏng mất lông vũ). Bước tiếp theo về Làng.
- **Không xong** (hết giờ, gục, tự về): thưởng theo số quân canh đã hạ (đủ 8 ≈ 4.800 vàng), không có lông vũ.

### Hỗn Chiến Thành (Chaos Castle)

(`RULES.chaos_castle`, DECISIONS B-19)

- **Khi nào:** 1h30, 3h30, 5h30 … 23h30; cho vào trong **5 phút** đầu, sau đó **10 phút** hỗn chiến.
- **Điều kiện:** cấp **15** trở lên và 1 **Áo Giáp Vệ Binh** (mua ở Người Gác Tháp **5.000 vàng**, hoặc rơi 2 % từ quái
  thường cấp ≥ 15).
- **Cách vào:** Làng → **Người Gác Tháp** → thẻ **⚔ Hỗn Chiến Thành** → Vào. Mọi người vào **cùng một thành** (bản đồ chung).
- **Cách chơi:** hết 5 phút cho vào thì thành thả quái (30 trừ số người vào, ít nhất 10 con, cấp quanh cấp trung bình người
  vào). Từ lúc đó **quái và người đánh lẫn nhau**: đồ sát người khác trong thành **không mất vàng, không bị tên đỏ**.
  Gục ngã (quái hay người), rời thành hay thoát game là **bị loại** và về Làng (không mất vàng).
- **Thưởng** (gửi **qua thư**):
  - còn **đúng 1 người** và **hết quái** → người đó thắng: **60.000 vàng + 1 Ngọc Hỗn Nguyên + 2 Ngọc Ước Nguyện + 1 Ngọc Tâm Linh**;
  - **hết giờ** → mỗi người còn trụ: **8.000 vàng + 1 Ngọc Ước Nguyện**;
  - mỗi người mình hạ được: **+2.000 vàng**.
- Hết lượt, người còn trong thành được đưa về Làng, quái còn lại biến mất.

### Kalima

(`RULES.kalima`, DECISIONS B-21) Không theo lịch — có Bản Đồ Thất Lạc là vào được.

- **Điều kiện:** cấp **20** trở lên và 1 **Bản Đồ Thất Lạc**.
- **Bản Đồ Thất Lạc:** ghép **5 Dấu Ấn Kundun + 5.000 vàng** ở Máy Hỗn Nguyên (luôn thành công). Dấu ấn rơi 4 % từ quái
  thường cấp ≥ 20.
- **Cách vào:** Làng → **Người Gác Tháp** → thẻ **👹 Kalima** → Vào. Cấp Kalima theo cấp nhân vật: 20 → Kalima 1, 25 → 2,
  30 → 3, 35 → 4, 40 → 5, 45 → 6, 50 → 7 (quái cấp 22, 27 … 52).
- **Cách chơi:** bản đồ riêng, **10 phút**: hạ **10 quái Kalima**, rồi **Kundun** hiện gần cầu thang lên (rất trâu).
- **Thắng (hạ Kundun):** vàng, kinh nghiệm lớn, **3 ngọc** và **1 món đồ** (50 % Excellent; bộ giáp thì 30 % là đồ Thần).
  Bước tiếp theo về Làng.
- **Không xong** (hết giờ, gục, tự về): thưởng theo số quái đã hạ.

### Công Thành Chiến (Castle Siege)

(`RULES.castle_siege`, DECISIONS B-22)

- **Khi nào:** **thứ Bảy 20h00**, mỗi tuần, đánh **30 phút**.
- **Đăng ký:** bang chủ / phó bang đến **Người Gác Tháp** → thẻ **🏰 Công Thành Chiến** → Đăng ký (**200.000 vàng**), trước giờ
  đánh. Bang đang là Chủ Thành tự động tham gia.
- **Vào:** trong 30 phút đánh, thành viên **cấp 30+** của bang tham gia gặp Người Gác Tháp → Vào thành. Gục ngã thì về Làng
  (không mất vàng) và vào lại được.
- **Cách chơi:** giữa thành có **Vương Miện**. Bang nào hạ được nó thì **giữ Vương Miện**; 60 giây sau Vương Miện hiện lại cho
  các bang khác giành (bang đang giữ không đánh được nó — hãy chặn người bang khác). Người hai bang khác nhau được đồ sát
  nhau, không mất vàng, không tên đỏ.
- **Kết quả:** hết giờ, bang đang giữ Vương Miện là **Chủ Thành** tới trận sau (hiện trên thẻ); mọi thành viên nhận qua thư
  **100.000 vàng + 1 Ngọc Hỗn Nguyên + 3 Ngọc Ước Nguyện + 2 Ngọc Tâm Linh**.

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
  🏰 Mở Lâu Đài Máu, ⚔ Mở Hỗn Chiến Thành (cho vào 5 phút rồi hỗn chiến 10 phút), 🐲 Rồng Đỏ xâm lăng, 🧙 Phù Thủy Trắng
  xâm lăng (bắt đầu ngay ở bản đồ ngẫu nhiên), 🏰 Mở Công Thành Chiến (bắt đầu ngay, mọi bang vào được, kết quả tính thật). Quảng Trường / Lâu Đài mở một đợt riêng ngoài lịch, cho vào trong 10 phút, cả server nhận thông báo;
  người chơi vẫn cần vé và đủ cấp, ai đã vào đợt thường vẫn vào được đợt này.
- **Đổi lịch trùm thế giới** (biến môi trường, khởi động lại server; xem `config/runtime.exs`):
  `WORLD_BOSS_FIRST_MINUTES` (lần đầu sau khởi động, mặc định 10), `WORLD_BOSS_EVERY_MINUTES` (120),
  `WORLD_BOSS_DURATION_MINUTES` (30), `WORLD_BOSS_HP` (20.000).
- **Đổi giờ / số liệu các sự kiện khác:** sửa `priv/game_data/rules.json` (`invasion`, `raids`, `devil_square`, `blood_castle`, `chaos_castle`, `kalima`, `castle_siege`,
  `events`, `daily`, `arena`, `pk`…) rồi khởi động lại; lễ hội thêm / sửa ở `priv/game_data/events.json`.
- **Tặng vé:** tab Quản trị → Đồ thường → `ds_ticket` (Vé Quảng Trường) / `bc_ticket` (Vé Lâu Đài) /
  `cc_ticket` (Áo Giáp Vệ Binh) / `lost_map` (Bản Đồ Thất Lạc) / `kundun_mark` (Dấu Ấn Kundun).
