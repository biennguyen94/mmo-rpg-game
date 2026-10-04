# Kế hoạch các phase tiếp theo — Hắc Long

> Lập 2026-10-04 từ các mục anh đã chọn trong `docs/FEATURE_CATALOG.md` mà chưa làm.
> Thiết kế chi tiết của từng phase sẽ viết vào `docs/INTEGRATION_PLAN.md` (một mục mới) **trước khi code**, kèm câu hỏi ⛔.
>
> Đã xong trước đó: Đợt 1 (bảo mật, kết nối), Đợt 2 (nhật ký vàng, giao dịch an toàn, quản trị), Đợt 3 (ép +11, máy ghép,
> cánh, khóa đồ), Đợt 4 (4 lớp MU, công cụ Item.txt + hình theo cấp).

## Cách làm mỗi phase

1. Viết thiết kế + câu hỏi vào `INTEGRATION_PLAN.md`, **dừng chờ anh chốt**.
2. Code. Hàm thuần có test với số ngẫu nhiên cố định; thao tác vàng / đồ đi qua `Characters.save!` (có nhật ký).
3. Chạy đủ `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`, `node --check`, e2e (từ Phase 2).
4. Phase đổi cân bằng: chạy `mix hac_long.simulate 20` trước / sau, ghi bảng số vào tài liệu.
5. Cập nhật `FEATURE_CATALOG` (cột Chọn: `✅ Pn`), `CODEBASE_NOTES`, hướng dẫn liên quan; commit, push, **báo cáo, chờ "OK"**.

## Tổng quan

| Phase | Tên | Mục (FEATURE_CATALOG) | Đổi cân bằng | Công | Phụ thuộc |
|---|---|---|---|---|---|
| 1 ✅ | Nền dữ liệu và cấu hình | J1, J2, J3, A3, B2, E7, B9, B11, O3 | Không | M | – |
| 2 ✅ | Lưới an toàn test | N1, N2, N3, N5, M8, O4 | Không | M | – |
| 3 | Công thức chiến đấu | A1, A2, A4 | **Có** | M | 1, 2 |
| 4 | Ngọc, ép, kho | D4, D8, C6, C7, E10 | Nhẹ | M | 1 |
| 5 | Xã hội, xếp hạng, PK cược vàng | H1–H9, H12, H14, E5, K10, M2 | Nhẹ | M–L | 2 |
| 6 | Đồ từ Item.txt | C1, C2, C3, C4, B4, A9, C17, C21, M10, B8, L1 (phần còn lại) | **Có** | L | 1, 3; **chờ Item.txt** |
| 7 | Sự kiện Golden Invasion | F1, F4, M3 | Nhẹ | M | 1 |
| 8 | Giao diện, hướng dẫn người chơi | L2, M11, O1 | Không | S–M | – |

**Lý do thứ tự:**

- **Phase 1 trước:** mọi phase sau đều đổi số (giá, tỉ lệ, công thức). Đưa số ra file dữ liệu trước thì chỉnh cân bằng không
  phải sửa code, và kiểm dữ liệu lúc biên dịch bắt lỗi gõ nhầm id khi thêm nhiều đồ ở Phase 6.
- **Phase 2 trước Phase 3:** đổi công thức đánh dễ làm hỏng chỗ khác; cần e2e + test chống nhân bản làm lưới an toàn.
- **Phase 6 để sau Phase 3:** Item.txt có đòn thấp / cao (`DmgMin` / `DmgMax`), nên công thức min~max (A1) nên có trước.
  Phase 6 cũng đang **chờ anh gửi Item.txt**; có file sớm thì đưa lên ngay sau Phase 3.
- Phase 4, 5, 7, 8 độc lập nhau, đổi thứ tự được theo ý anh.

---

## Phase 1 — Nền dữ liệu và cấu hình ✅ (xong 2026-10-04)

**Mục tiêu:** mọi số gameplay nằm trong file dữ liệu; dữ liệu sai thì biên dịch báo lỗi; không đổi cảm giác chơi.

| Mục | Việc |
|---|---|
| **J1** | Gom số đang viết cứng trong code (~46 hằng số: rương, rèn, bang, chợ, giao dịch, nâng cấp, chiến đấu, giá bán, thư, thú cưng, tháp…) vào khóa `RULES` / `CONFIG`. Module đọc qua `Data`. |
| **J3** | Tách `priv/game_data.json` cũ (≈ 1 800 dòng) thành `priv/game_data/{classes,zones,items,shop,recipes,quests,pets,furniture,events,upgrade,chaos,rules}.json`; `Data` ghép lại lúc biên dịch, client nhận như cũ. |
| **J2** | Kiểm lúc biên dịch: đồ trong cửa hàng / công thức / rơi trùm / nhiệm vụ phải tồn tại; kỹ năng có `effect` hợp lệ; cánh có `cls` hợp lệ; NPC trên bản đồ có `role` đã biết. Sai → lỗi biên dịch có tên file + id. |
| **A3** | Tham số chiến đấu (chí mạng, né, hệ số chí mạng, sàn sát thương, % hồi MP mỗi lượt) vào `RULES.combat`. |
| **B2** | Công thức EXP lên cấp vào data (hiện `25 × L^1.75 + 15`; giữ nguyên số, chỉ chuyển chỗ). |
| **E7** | Tỉ lệ giá bán lại vào data (hiện 40 %; giữ nguyên). |
| **B9** | Lọc từ cấm khi đặt tên nhân vật / bang (`RULES.names.bannedWords`, không phân biệt dấu / hoa thường). |
| **B11** | Vào game mà vị trí lưu không đi được (sửa bản đồ) → về điểm sinh của bản đồ đó, hoặc Làng. |
| **O3** | Tạo `docs/DECISIONS.md` (quyết định nhỏ đã tự chốt + lý do) và `docs/OPEN_QUESTIONS.md` (câu hỏi đang chờ anh). |

**Câu hỏi (đã chốt 2026-10-04):**

- 1-A Danh sách từ cấm: ~~anh gửi hay em lập?~~ → **em lập danh sách cơ bản** (`RULES.names`, anh sửa thêm được).
- 1-B Tách file data (`priv/game_data.json` → thư mục `priv/game_data/`)? → **đồng ý**.

**Xong khi:** simulator trước / sau giống hệt (cùng seed); `grep` không còn số gameplay trong `lib/hac_long/game/*.ex` (trừ
hằng số kỹ thuật); test cố ý sửa sai một id trong data → biên dịch báo lỗi.

**Kết quả:**

- `priv/game_data/` 12 file; `RULES` (`rules.json`) gom số luật chơi của `engine`, `gear`, `chests`, `crafting`, `tower`,
  `pets`, `bestiary`, `home`, `events`, `daily`, `fishing`, `tutorial`, `guilds`, `guild_quests`, `market`, `arena`,
  `party`, `map_server`. Còn trong code: hằng số kỹ thuật và vài nội dung có cấu trúc riêng (`DECISIONS.md` P1-7, P1-8).
- `MIX_ENV=test mix hac_long.simulate 5 --seed 42` trước / sau: **giống hệt từng dòng** (4 lớp × 5 cách chơi).
- Sửa `"dagger"` thành `"daggerr"` trong `shop.json` → `mix compile` dừng:
  `shop.json: SHOP có món "daggerr" không có trong ITEMS`.
- Test mới `test/hac_long/game/data_rules_test.exs` (15 test); tổng 189 test xanh.
- `docs/DECISIONS.md`, `docs/OPEN_QUESTIONS.md` (O3).

---

## Phase 2 — Lưới an toàn test ✅ (xong 2026-10-04)

**Mục tiêu:** có test giao diện tự động + test tải + test chống nhân bản, chạy trên CI.

| Mục | Việc |
|---|---|
| **N1** | `reference/rpg-game/e2e/` (Playwright, Chromium có sẵn): `smoke` (đăng ký → tạo 4 lớp → đi → đánh → mua / bán → nghỉ), `social` (2 trình duyệt: tổ đội, giao dịch, bạn bè, chợ), `progress` (nhiệm vụ, hằng ngày, ép, rương, máy ghép), `admin`, `mobile` (360 px không tràn ngang). Mỗi kịch bản in PASS / FAIL + chụp ảnh. Theo `INTEGRATION_PLAN §5`. |
| **M8** | Hook test `window.__hl` (trạng thái nhân vật, tab, NPC đang mở) để e2e không phải đọc chữ trên màn hình. |
| **N2** | Test logic client bằng `node --test` (tách hàm thuần ra khỏi `ui.js`: chọn hình theo cấp, tỉ lệ máy ghép, gom lệnh cộng điểm…). |
| **N5** | Test chống nhân bản: bắn nhiều lệnh song song (giao dịch + chợ + bán + thư cùng lúc) → `HacLong.Audit` không lỗi, tổng vàng / đồ không tăng. |
| **N3** | Soak: N bot (WebSocket) chơi song song X phút, đo trễ p50 / p95, lỗi, bộ nhớ; chạy `mix hac_long.audit` sau soak. |
| **O4** | Ảnh chụp màn hình trong tài liệu lấy từ e2e (cập nhật tự động khi chạy). |

**Câu hỏi (chốt 2026-10-04 theo đề xuất):** 5-A soak 30 bot / 10 phút (chạy tay; CI tự chạy 10 bot / 2 phút), 5-B e2e trên
CI chỉ khi sửa `reference/rpg-game/**`.

**Xong khi:** CI chạy e2e xanh; soak 30 bot không lỗi, audit sạch.

**Kết quả:**

- `e2e/` 5 kịch bản trên server thật, tất cả PASS: `smoke` 19, `social` 16, `progress` 12, `admin` 10, `mobile` 12 bước
  (kèm "không lỗi JS" ở mọi kịch bản). Hook `window.__hl` (`?test=1`).
- `node --test test/js/*.test.mjs`: 7 test hàm thuần (`priv/static/js/logic.js`).
- `test/hac_long_web/dupe_test.exs`: 3 kịch bản × 4 vòng bắn lệnh song song, chạy nhiều seed: không sinh vàng / đồ, audit sạch.
- Soak 30 bot × 10 phút (máy dev): 88 688 lệnh (148 / s), 368 trận, 924 tin chat; độ trễ p50 1,2 ms · p95 2,4 ms ·
  max 174,6 ms; 0 lỗi, 0 quá giờ, 0 mất kết nối; bộ nhớ server 115 → 163 MB. `mix hac_long.audit` sau soak: **không có lỗi**.
- CI: `.github/workflows/hac-long-e2e.yml` chạy trên PR #3. Lần đầu kịch bản `admin` trượt vì tra cứu nhân vật vừa tạo trước khi
  Session lưu xuống database (lưu định kỳ 5 giây); đã sửa kịch bản để tra lại tới khi thấy.

---

## Phase 3 — Công thức chiến đấu

**Mục tiêu:** đánh có cảm giác MU (đòn thấp / cao, trượt, phạt đánh quái yếu) mà độ khó tổng thể giữ như hiện tại.

| Mục | Việc |
|---|---|
| **A1** | Sát thương nhiều bước: đòn ngẫu nhiên giữa **min~max** của vũ khí × hệ số kỹ năng → chí mạng → × buff × (1 + % cánh) → trừ thủ → **sàn mềm** (không dưới x % đòn gốc) → × (1 − % hấp thụ) → sàn cứng. Vũ khí hiện có thêm `atkMin` / `atkMax` (tạm suy từ `atk`, Phase 6 lấy từ Item.txt). Tooltip và bảng nhân vật hiện "Tấn công 40 ~ 52". |
| **A2** | Tỉ lệ trúng = attackRate / (attackRate + defenseRate), chặn 5–95 %; attackRate = cấp × 5 + AGI × 1,5. Trượt hiện "Trượt!". Thay cho né hiện tại (né theo AGI). |
| **A4** | Phạt EXP khi cao hơn quái > 10 cấp: −10 % mỗi cấp, tối thiểu 10 %. |

**⛔ Câu hỏi:**

- 3-A Bỏ hẳn "né" hiện tại, thay bằng tỉ lệ trúng (A2)? Hay giữ cả hai (quái trượt theo tỉ lệ trúng, người chơi vẫn né theo AGI)?
- 3-B Sàn mềm bao nhiêu (đề xuất 20 % đòn gốc như MU)?
- 3-C Phạt EXP (A4) áp cả trong tháp và trùm thế giới không? Đề xuất: chỉ quái thường.
- 3-D Khoảng đòn thấp ~ cao áp cho toàn bộ công hay chỉ phần vũ khí? Đề xuất: toàn bộ công ±10 % cho đến Phase 6.
- 3-E Kỹ năng có thể trượt không (hiện luôn trúng)? Đề xuất: có.

Thiết kế chi tiết: `INTEGRATION_PLAN.md §11`.

**Xong khi:** simulator 4 lớp: số trận hạ Hắc Long lệch ≤ 10 % so với hiện tại (≈ 440 / 340), số lần chết không tăng quá 1;
e2e smoke xanh.

---

## Phase 4 — Ngọc, ép, kho

| Mục | Việc |
|---|---|
| **D4** | **Ngọc Sinh Mệnh** (`jewel_life`): thêm dòng tùy chọn +4 công (vũ khí) / +4 thủ (giáp, khiên), tối đa 4 dòng (+16), 50 %; thất bại mất dòng tùy chọn cuối. Rơi như ngọc khác (bảng `JEWELS`). Hiện trong tooltip. |
| **D8** | Nút **"Ép ngọc"** trong bảng chi tiết món đồ, cho **cả đồ trong túi lẫn đồ đang mặc** (thay C15); máy tính kéo ngọc thả lên đồ. Vẫn phải đứng cạnh Thợ Rèn (giữ không khí làng), hoặc đề xuất bỏ điều kiện này (câu 4-A). |
| **C6** | Tách chồng đồ (số lượng) và **vứt đồ** có xác nhận (đồ khóa không vứt được). |
| **C7** | **Rương ở Nhà**: chỗ cất đồ ngoài túi (đồ thường + đồ hiếm), đứng cạnh rương mới gửi / rút. Bảng mới hoặc cột mới trong `characters`; gửi / rút đi qua nhật ký đồ. |
| **E10** | Trần vàng khi gửi thư (quản trị và quà tất cả), tránh gõ nhầm số. |

**⛔ Câu hỏi:**

- 4-A Ép ngọc ở bất kỳ đâu, hay vẫn phải đứng cạnh Thợ Rèn?
- 4-B Rương ở Nhà chứa bao nhiêu (đề xuất 40 ô đồ thường + 20 đồ hiếm), có nâng cấp chỗ bằng vàng không?
- 4-C Trần vàng thư: 1 triệu / thư?

**Xong khi:** test hàm thuần (ngọc, vứt, rương), audit sạch sau gửi / rút, e2e ép ngọc từ tooltip.

---

## Phase 5 — Xã hội, xếp hạng, PK cược vàng

| Mục | Việc |
|---|---|
| **H7 + H8** | **PK = trận đấu trường có cược vàng**: mời một người cụ thể (cả hai online), đặt cược bằng nhau, vàng giữ trong một transaction tới khi xong; đánh với bản sao chỉ số người kia như đấu trường hiện có; thắng nhận cả hai phần (trừ phí), thua mất cược. Lời mời hết hạn 30 s. Có lịch sử trận. |
| **H14** | Xếp hạng theo lớp (Kiếm Sĩ / Phù Thủy / Tiên Nữ / Đấu Sĩ) + cache + hạng của mình (`INTEGRATION_PLAN §6`). |
| **H1** | EXP tổ đội ×(1 + 0,1 × (n − 1)), người ở bản đồ khác / đã gục không nhận (hiện chia vàng ×1,2 / n: so và chọn một). |
| **H2, H3, H4, H6, H9, H12, E5, M2** | Kiểm lại từng luật đang có, sửa chỗ thiếu: lời mời hết hạn 30 s (tổ đội / bang / giao dịch); trưởng nhóm rời thì người vào sớm nhất lên thay; vai trò bang (phó tối đa 2); tên bang trên đầu + màu tên theo quan hệ; chat bằng lệnh `/w Tên`, `/p`, `/g`; thư hết hạn 30 ngày, lọc, xóa đã đọc, tối đa 100 (hiện giữ 50); giao dịch tự hủy khi đi xa / đổi bản đồ / mất kết nối / quá 180 s. |
| **H5** | Chiến bang trên đấu trường: hai bang tuyên chiến, 1 giờ, điểm theo số trận thắng giữa thành viên hai bang. |
| **K10** | Tab Quản trị: số người online + danh sách. |

**⛔ Câu hỏi:**

- 5-C Cược tối thiểu / tối đa, phí sàn (đề xuất 100 – 1 000 000 vàng, phí 5 %)? Mỗi ngày tối đa bao nhiêu trận cược?
- 5-D Có giới hạn chênh cấp khi mời PK không (đề xuất ±10 cấp)?
- 5-E Chiến bang (H5) có thưởng gì (quỹ bang, danh hiệu)?

**Xong khi:** e2e 2 trình duyệt cho PK cược (thắng / thua / từ chối / hết hạn), audit sạch; test từng luật kiểm lại.

---

## Phase 6 — Đồ từ Item.txt (chờ file)

**Mục tiêu:** đồ trong game lấy từ `Item.txt` của anh, theo lớp, đủ 10 ô trang bị, hình theo cấp.

| Mục | Việc |
|---|---|
| **C1, C2** | Mở 6 ô còn khóa: mũ, quần, găng, giày, 2 nhẫn (cánh đã có). `derived`, chợ, giao dịch, nâng cấp, máy ghép nhận ô mới. Hình nhân vật vẽ thêm mũ / găng / giày (tile hiện có hoặc hình anh gửi). |
| **C3** | Yêu cầu STR / AGI / VIT / ENE để mặc, hiện đỏ khi thiếu (hệ số theo câu 10-A). |
| **C4** | Đồ theo lớp (`classes` từ cờ lớp trong Item.txt); Đấu Sĩ không đội mũ. |
| **B4** | Đồ khởi đầu theo lớp: Kiếm Sĩ kiếm, Phù Thủy gậy, Tiên Nữ cung, Đấu Sĩ kiếm. |
| **A9** | Vũ khí hai tay (cung, nỏ, kiếm lớn): không cầm khiên. |
| **C17, C21, M10** | Kích thước ô theo `X × Y` (chỉ dùng để vẽ hình đúng tỉ lệ, túi vẫn tự xếp); hình mờ ở ô trống; hình không kéo giãn. |
| **B8, L1** | Bảng chỉ số đủ (đòn min~max, tỉ lệ trúng, MP…); hình nhân vật to ở giữa lưới trang bị. |
| Khác | Thay 18 vũ khí / giáp / khiên hiện có bằng đồ Item.txt cho cửa hàng, rơi theo vùng, đồ trùm; thêm bình MP; gắn `ref` để dùng hình `item_{nhóm}_{số}`. |

**⛔ Câu hỏi:** 10-A … 10-D trong `INTEGRATION_PLAN §10.3` (hệ số yêu cầu chỉ số, lấy món nào, giá, bình MP / nhẫn / dây
chuyền). Thêm:

- 6-A Nhân vật đang chơi lúc đổi đồ: giữ đồ cũ (vẫn mặc được) hay đổi sang món Item.txt tương đương?

**Xong khi:** mỗi lớp cấp 1 mặc được ít nhất một món mỗi ô; simulator 4 lớp lệch ≤ 10 %; e2e túi đồ 10 ô; audit sạch.

---

## Phase 7 — Sự kiện Golden Invasion

| Mục | Việc |
|---|---|
| **F1** | Theo lịch (data), quái vàng xuất hiện ở các vùng: thưởng ×5, rơi ngọc 10 %; hạ hết thì kết thúc sớm; thông báo cả server lúc bắt đầu / kết thúc. |
| **F4** | Quái sự kiện không hồi sinh; vùng / số lượng / thời gian trong data. |
| **M3** | Quầng vàng cho quái sự kiện, trùm vẽ to 1,5 lần, thanh máu dài. |

**⛔ Câu hỏi:** 7-A lịch (đề xuất mỗi 2 giờ, 15 phút / lần, giờ Việt Nam); 7-B có trùm vàng cuối đợt không?

**Xong khi:** test lịch với đồng hồ giả; e2e thấy quái vàng và nhận thưởng.

---

## Phase 8 — Giao diện, hướng dẫn người chơi

| Mục | Việc |
|---|---|
| **L2** | Panel Thông báo: lưu tin (ép +7, ghép cánh, thư, mời…), chưa đọc / đã đọc, xóa. |
| **M11** | Hiệu ứng nhỏ bằng CSS / canvas: lóe sáng khi trúng, chữ "LÊN CẤP", hồi máu / MP, ép thành công / vỡ. |
| **O1** | `docs/USER_GUIDE.md` cho Hắc Long: 4 lớp, chỉ số, kỹ năng, ép, máy ghép, cánh, chợ, giao dịch, bang… kèm ảnh từ e2e. |

**Xong khi:** e2e mobile không tràn ngang; hướng dẫn đủ mọi tính năng đang có.

---

## Gợi ý lịch (mỗi phase dừng chờ anh duyệt)

| Thứ tự | Phase | Ghi chú |
|---|---|---|
| 1 | Phase 1 | Bắt đầu ngay được |
| 2 | Phase 2 | Cần chốt 5-A, 5-B |
| 3 | Phase 3 | Cần chốt 3-A … 3-C |
| 4 | **Phase 6** nếu đã có Item.txt, không thì Phase 4 | |
| 5+ | Phase 4 / 5 / 7 / 8 theo ý anh | Độc lập nhau |
