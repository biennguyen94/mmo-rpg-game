# Danh mục tính năng MU Web có thể mang sang Hắc Long

> Liệt kê **toàn bộ** tính năng của MU Web (server + client + vận hành), so với Hắc Long hiện tại, kèm đánh giá của Claude.
> Anh đánh dấu cột **Chọn** (`[x]`) cho mục muốn làm. Mục đã chọn sẽ được đưa vào `docs/INTEGRATION_PLAN.md`
> (thiết kế chi tiết + câu hỏi) trước khi code.
>
> - Bản đồ code Hắc Long: `docs/CODEBASE_NOTES.md`.
> - Mục có ★ đã có thiết kế trong `INTEGRATION_PLAN.md`.

## Nguyên tắc giao diện (anh chốt 2026-10-04)

- **Giữ nguyên giao diện Hắc Long hiện tại:** trang chính, bản đồ, màn trận, HUD, thanh tab, phong cách thẻ (card) và màu sắc.
- **Chỉ làm đẹp lại một số màn theo kiểu MU Web**, hiện là:
  - **túi đồ** (lưới ô, tooltip, thanh tóm tắt);
  - **phần nhân vật** (hình nhân vật kèm ô trang bị, bảng chỉ số, cộng điểm).
- **Được gộp / tách / chuyển chỗ các phần có sẵn**, vd chuyển **Thành tựu** ra khỏi tab Nhân vật.
- Mục nào đổi bố cục ngoài những màn trên thì đánh giá ❌, trừ khi anh chọn riêng.
- Đề xuất sắp xếp cụ thể ở **mục Q**.

## Cách đọc

| Cột | Ý nghĩa |
|---|---|
| **Đánh giá** | ✅ **Nên làm**: hợp kiến trúc Hắc Long, có ích rõ · 🟡 **Cân nhắc**: hợp nhưng đổi cảm giác chơi / cân bằng, hoặc tốn công · ❌ **Không nên**: không hợp (Hắc Long đánh theo lượt, 1 tài khoản 1 nhân vật), hoặc Hắc Long đã có tương đương / tốt hơn |
| **Công** | **S** nhỏ (vài giờ) · **M** vừa (1–2 ngày) · **L** lớn (nhiều ngày, đụng nhiều phần) |
| **Hắc Long** | "Có", "Không", "Khác" (có nhưng cách khác), "Kiểm" (chưa xác minh hết, kiểm lại khi làm) |

## Mục lục

- A. [Chiến đấu và công thức](#a-chiến-đấu-và-công-thức)
- B. [Nhân vật, lớp, cấp, điểm](#b-nhân-vật-lớp-cấp-điểm)
- C. [Đồ, trang bị, túi](#c-đồ-trang-bị-túi)
- D. [Nâng cấp, ngọc, máy ghép, cánh](#d-nâng-cấp-ngọc-máy-ghép-cánh)
- E. [Kinh tế, cửa hàng, giao dịch, chống gian lận](#e-kinh-tế-cửa-hàng-giao-dịch-chống-gian-lận)
- F. [Thế giới, quái, sự kiện](#f-thế-giới-quái-sự-kiện)
- G. [Nhiệm vụ](#g-nhiệm-vụ)
- H. [Xã hội: tổ đội, bang, PvP, chat, thư, xếp hạng](#h-xã-hội-tổ-đội-bang-pvp-chat-thư-xếp-hạng)
- I. [Server: phiên, đồng bộ, bảo mật, độ bền dữ liệu](#i-server-phiên-đồng-bộ-bảo-mật-độ-bền-dữ-liệu)
- J. [Dữ liệu game và cấu hình](#j-dữ-liệu-game-và-cấu-hình)
- K. [Quản trị và vận hành](#k-quản-trị-và-vận-hành)
- L. [Client: màn hình, panel, thao tác](#l-client-màn-hình-panel-thao-tác)
- M. [Client: vẽ, hiệu ứng, kỹ thuật](#m-client-vẽ-hiệu-ứng-kỹ-thuật)
- N. [Test, CI, công cụ](#n-test-ci-công-cụ)
- O. [Tài liệu](#o-tài-liệu)
- P. [Bổ sung sau khi rà toàn bộ `docs/` của MU Web](#p-bổ-sung-sau-khi-rà-toàn-bộ-docs-của-mu-web)
- Q. [Sắp xếp lại giao diện Hắc Long](#q-sắp-xếp-lại-giao-diện-hắc-long)
- [Tổng hợp đề xuất của Claude](#tổng-hợp-đề-xuất-của-claude)

---

## A. Chiến đấu và công thức

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| A1 | **Sát thương nhiều bước:** đòn ngẫu nhiên **min~max** × hệ số kỹ năng + cộng phẳng → chí mạng → × buff × (1 + % cánh) → **trừ thủ** → **sàn mềm** (không dưới x % đòn gốc) → × (1 − % hấp thụ) → **sàn cứng** | Khác: một số `atk²/(atk+def) × rand(0,9–1,1)` | 🟡 | M | Công thức Hắc Long đã mượt (thủ cao vẫn ăn đòn). Đáng lấy: **khoảng đòn min~max** (vũ khí có đòn thấp / cao, hiện rõ trên đồ) và chỗ cắm **% cánh / % hấp thụ** (D6). Đổi cân bằng → simulator | [ ] |
| A2 | **Tỉ lệ trúng** = attackRate / (attackRate + defenseRate), chặn 5–95 %; attackRate = cấp × 5 + AGI × 1,5 | Khác: có né theo agi | 🟡 | S | Thêm cảm giác "Trượt!". Đụng cân bằng lớp Thích Khách | [ ] |
| A3 | **Tham số chiến đấu trong config** (minHitChance, maxHitChance, minDamageRatio, hardFloor, critChance, critMultiplier) | Không: hằng số trong `engine.ex` | ✅ | S | Đưa hằng số chiến đấu vào `game_data.json`, chỉnh không cần sửa code (xem J1) | [ ] |
| A4 | **Phạt EXP chênh cấp:** cao hơn quái > 10 cấp thì −10 % / cấp, tối thiểu 10 % | Kiểm | ✅ | S | Chống đánh quái yếu lấy EXP, ép người chơi lên vùng mới | [ ] |
| A5 | **PvP × 0,5 sát thương** (giảm hệ số khi người đánh người) | Khác: đấu trường đánh bản sao chỉ số | 🟡 | S | Chỉ cần nếu thấy đấu trường kết thúc quá nhanh | [ ] |
| A6 | **Kỹ năng tốn MP**, MP hồi theo ENE / giây | Khác: hồi chiêu theo lượt | ❌ | L | Hệ khác, không đáng đổi | [ ] |
| A7 | **Kỹ năng hỗ trợ đồng đội:** Heal (10 + ENE/4), Tăng thủ (2 + ENE/8, 60 s), Tăng công (3 + ENE/7, 60 s) | Khác: buff bản thân (rage, guard) | 🟡 | M | Hợp tổ đội 3 người đánh chung một quái. Cần thiết kế lại kỹ năng lớp (vd Hiệp Sĩ có Hồi Máu cho đồng đội) | [ ] |
| A8 | **Kỹ năng vùng / đánh xa / dịch chuyển** | Khác | ❌ | – | Theo lượt một-một | [ ] |
| A9 | **Vũ khí hai tay** (cung: không cầm khiên), **tầm đánh theo vũ khí** | Không | 🟡 | S | Chỉ phần "hai tay": vũ khí to công cao nhưng mất khiên. Thêm lựa chọn build | [ ] |
| A10 | **Chí mạng tắt / bật bằng config** | Có chí mạng theo agi | ❌ | – | Đã có | [ ] |
| A11 | **Tự đánh lặp lại** (chọn kỹ năng một lần, tự đánh theo hồi chiêu) | Khác: bấm từng lượt | 🟡 | S | Nút **"Tự đánh"** trong trận (lặp đòn / kỹ năng tới khi thắng hoặc máu < x %). Đỡ mỏi tay trên điện thoại | [ ] |
| A12 | **Hồi chiêu bình máu** (1 s) | Khác: uống máu tốn lượt | ❌ | – | Turn-based đã cân bằng sẵn | [ ] |

## B. Nhân vật, lớp, cấp, điểm

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| B1 | **Lên cấp hồi đầy HP / MP** | Kiểm | ✅ | S | Rất nhỏ, cảm giác thưởng | [ ] |
| B2 | **EXP cần lên cấp theo công thức trong config** (`100 × L^1.5`) | Kiểm (trong code) | ✅ | S | Gộp vào J1 | [ ] |
| B3 | **Điểm / cấp khác nhau theo lớp** (MG 7, lớp khác 5) | Khác: 3 điểm / cấp cho mọi lớp | 🟡 | S | Chỉ có ích nếu thêm lớp đặc biệt (B5) | [ ] |
| B4 | **Đồ khởi đầu theo lớp** (DW có gậy, ELF có cung…) | Khác: mọi lớp `club` + `vest` | ✅ | S | Chiến Binh rìu, Thích Khách dao găm, Hiệp Sĩ chùy + khiên. Tăng bản sắc lớp ngay từ đầu | [ ] |
| B5 | **Lớp mở khóa** (MG: tài khoản có nhân vật cấp 20) | Không (1 nhân vật / tài khoản) | 🟡 | L | Biến thể hợp Hắc Long: **lớp ẩn mở sau chuyển sinh** lần 1. Cần thiết kế lớp mới + hình nhân vật | [ ] |
| B6 | **Cộng điểm gom lệnh** (bấm + nhiều lần, gửi 1 lệnh sau 200 ms, hiện "+n" đang chờ) | Khác: +1 / +5 mỗi bấm gửi một lệnh | ✅ | S | Đỡ spam lệnh, mượt hơn trên mạng chậm | [ ] |
| B7 | **Chỉ số dẫn xuất theo lớp trong data** (công thức đòn / thủ / HP mỗi lớp khác nhau) | Khác: một công thức chung | 🟡 | M | Lớp khác biệt rõ hơn (Thích Khách ăn agi, Chiến Binh ăn str). Đổi cân bằng | [ ] |
| B8 | **Bảng chỉ số chi tiết** (đòn min~max, thủ, tỉ lệ trúng, tốc độ, HP / MP tối đa) | Có công / thủ / chí mạng / né | ✅ | S | Thêm HP tối đa, % thú / món ăn đang cộng, % cánh (nếu làm D6) | [ ] |
| B9 | **Tên nhân vật: lọc từ cấm** (`names.bannedWords`) | Kiểm | ✅ | S | Đi cùng H10 | [ ] |

## C. Đồ, trang bị, túi

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| C1 | **10 ô trang bị:** mũ, áo, quần, găng, giày, vũ khí, khiên, cánh, 2 nhẫn | Khác: 3 ô (vũ khí / giáp / khiên) | 🟡 | L | Chiều sâu đồ lớn nhất. Đụng data, `derived`, hình nhân vật (`doll.js` cần ảnh mũ / găng / giày; tile Dungeon Crawl có sẵn), UI, chợ, giao dịch. **Đề xuất làm từng bước:** thêm **nhẫn** (không cần vẽ) và **cánh** (D6) trước | [ ] |
| C2 | **Nhẫn** (+HP, không ép được) | Không | ✅ | M | Ô dễ thêm nhất: không vẽ trên người. Nhẫn rơi từ trùm / nhiệm vụ | [ ] |
| C3 | **Yêu cầu chỉ số để mặc** (STR / AGI / ENE tối thiểu), hiện đỏ khi thiếu | Khác: chỉ yêu cầu cấp | 🟡 | S | Cho điểm tiềm năng thêm ý nghĩa. Đổi cân bằng | [ ] |
| C4 | **Đồ theo lớp** (danh sách lớp được mặc; MG không đội mũ) | Kiểm (có vẻ mọi lớp mặc được hết) | 🟡 | S | Đi cùng B4 / B7 | [ ] |
| C5 | **Túi dạng lưới 8×8, kéo thả** xếp / mặc / tháo | Khác: danh sách theo nhóm | ✅ | M | Đẹp trên máy tính, **kém hơn danh sách trên điện thoại** (Hắc Long ưu tiên điện thoại). Đề xuất: lưới cho màn ≥ 1024 px, giữ danh sách cho màn hẹp | [ ] |
| C6 | **Tách stack, vứt đồ có xác nhận** | Không thấy | 🟡 | S | Vứt đồ ít cần (bán được). Tách stack chỉ có ích nếu chợ bán theo số lượng | [ ] |
| C7 | **Kho đồ** (MU: 15×8, chung tài khoản) | Không | 🟡 | M | Hắc Long 1 nhân vật nên đổi thành **"Rương ở Nhà"**: chỗ cất đồ ngoài túi (`gear` tối đa 20 món) | [ ] |
| C8 | **Đồ rơi dưới đất, giữ riêng 10 s, 60 s biến mất, nhặt bằng phím** | Khác: vào thẳng túi | ❌ | – | Không hợp turn-based | [ ] |
| C9 | **Mỗi món đồ có serial riêng** (bảng `items` + `item_locations`) | Khác: số đếm trong `inv`; đồ ngẫu nhiên có `uid` | 🟡 | L | Nền cho chống nhân bản đồ (E3). Đổi cách lưu đồ, migration lớn | [ ] |
| C10 | **Cấp nâng theo từng món** (không theo loại) | Khác: theo loại đồ thường (hai `broadsword` chung cấp) | ✅ | M | Sửa "bẫy" ở `CODEBASE_NOTES §10.4`. Cần trước khi làm D1 (mất đồ +10 thì mất đúng món) | [ ] |
| C11 | **Tooltip đồ đầy đủ:** chỉ số, +N, dòng tùy chọn, yêu cầu (đỏ khi thiếu), giá bán, nút hành động | Có dòng chỉ số + **so sánh với đồ đang mặc** (MU không có) | 🟡 | S | Chỉ thêm +N / yêu cầu rõ hơn | [ ] |
| C12 | **Độ bền đồ** (`durability`) | Không | ❌ | – | MU có trường nhưng chưa dùng; thêm chỉ làm phiền | [ ] |

## D. Nâng cấp, ngọc, máy ghép, cánh

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| D1 ★ | **Ép +6 → +11 bằng ngọc**, có rủi ro (tụt cấp / mất đồ), bảng bước trong config | Khác: Thợ Rèn +5, chắc chắn | ✅ | M | `INTEGRATION_PLAN §3`. Nên làm C10 trước | [x] |
| D2 | **+10 / +11 cộng gấp đôi** | Không | ✅ | S | Đi cùng D1 | [ ] |
| D3 | **Thông báo toàn server khi ép thành công từ +7** | Không | ✅ | S | Đi cùng D1 | [ ] |
| D4 | **Ngọc Sinh Mệnh:** dòng tùy chọn +4 công / thủ, tối đa 4, 50 % | Khác: đồ ngẫu nhiên đã có dòng chỉ số | 🟡 | M | `INTEGRATION_PLAN 3-C` | [ ] |
| D5 ★ | **Máy ghép** (công thức: đầu vào theo loại / cấp / số lượng, phí, tỉ lệ cơ bản + theo cấp đồ, trần 60 %; xem trước tỉ lệ; thất bại mất hết) | Khác: công thức nấu / rèn chắc chắn | ✅ | M | `INTEGRATION_PLAN §4` | [x] |
| D6 ★ | **Cánh** (ô riêng, % sát thương / % hấp thụ, ép +N mỗi cấp +2 %, cấp 2 theo lớp, vẽ bằng code) | Không | ✅ | L | `INTEGRATION_PLAN §4` | [x] |
| D7 | **Ngọc rơi theo nhóm có trọng số** từ quái cấp cao, trùm, top 3 trùm thế giới | Khác: nguyên liệu chỉ từ điểm thu thập | ✅ | S | Đi cùng D1 | [ ] |
| D8 | **Kéo ngọc thả lên đồ** để ép; điện thoại: [Ép lên…] rồi chạm đồ | Khác: nâng ở Thợ Rèn | 🟡 | S | Giữ Thợ Rèn (hợp không khí làng) + thêm nút "Ép ngọc" trong tooltip đồ | [ ] |

## E. Kinh tế, cửa hàng, giao dịch, chống gian lận

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| E1 ★ | **Log vàng** (mỗi lần đổi một dòng, cùng transaction) + **audit lệch vàng** + **thống kê vàng sinh ra / mất đi theo ngày × lý do** | Không | ✅ | M | `INTEGRATION_PLAN §1` | [x] |
| E2 | **Log đồ** (mỗi lần đồ đổi chủ: chợ, giao dịch, thư, bán, ép, ghép) | Không | ✅ | M | Bắt đầu với đồ ngẫu nhiên (`uid`); đầy đủ cần C9 | [ ] |
| E3 | **Audit đồ:** serial trùng, đồ không chủ, chủ hiện tại ≠ log | Không | 🟡 | L | Cần C9 | [ ] |
| E4 | **Giao dịch một transaction**, khóa hai nhân vật theo thứ tự id (tránh deadlock), kiểm lại đồ / vàng / chỗ trống | Khác: 2 pha qua Session, không transaction | ✅ | M | `INTEGRATION_PLAN 1-B`. Lỗ hổng tiềm ẩn duy nhất về nhân bản đồ / vàng em thấy | [ ] |
| E5 | **Giao dịch tự hủy** khi: đi xa, đổi map, chết, mất kết nối, đăng xuất, quá 180 s; **đổi gì cũng mở khóa hai bên** | Kiểm | 🟡 | S | Kiểm luồng hiện có, thêm điều kiện thiếu | [ ] |
| E6 | **Sửa `Market.commit/4` bỏ qua kết quả transaction** | Lỗi đang có | ✅ | S | Sửa ngay dù không làm gì khác | [ ] |
| E7 | **Giá bán lại = tỉ lệ trong config** (MU 50 %) | Khác: 40 % trong code | ✅ | S | Gộp J1 | [ ] |
| E8 | **Cửa hàng theo NPC trong data** (`shop.json`) | Có (`stock` trong map JSON) | ❌ | – | Đã có | [ ] |
| E9 | **Mọi thao tác đồ / vàng trong một transaction** (mua, bán, ép, ghép, nhận thư, giao dịch) | Khác: hàm thuần + lưu cả dòng (một Session nên an toàn trong RAM) | 🟡 | M | Rủi ro thấp vì Session tuần tự; chỉ cần ở chỗ đụng 2 người (E4, chợ) | [ ] |
| E10 | **Trần vàng gửi qua thư / giao dịch** | Có trần giao dịch 10 triệu; thư không trần | 🟡 | S | Thêm trần cho thư quản trị (tránh gõ nhầm số) | [ ] |

## F. Thế giới, quái, sự kiện

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| F1 | **Golden Invasion:** quái vàng theo lịch ở các vùng, thưởng ×5, rơi ngọc 10 %, hạ hết thì kết thúc sớm | Không | ✅ | M | Hoạt động đông người định kỳ, rẻ (dùng lại MapServer) | [ ] |
| F2 | **Lịch sự kiện chung** (`WorldEvents`): giờ UTC trong config, báo trước 5 phút, báo bắt đầu / kết thúc, bật / tắt tay, người vào giữa chừng vẫn thấy | Khác: trùm thế giới có lịch riêng; lễ hội theo mùa | 🟡 | M | Gom trùm thế giới + lễ hội + Golden vào một lịch, một thanh đếm ngược | [ ] |
| F3 | **Trùm thế giới: top 3 sát thương nhận ngọc** | Khác: chia vàng theo sát thương | ✅ | S | Đi cùng D7 | [ ] |
| F4 | **Quái sự kiện không hồi sinh**, vùng sinh trong config | – | ✅ | S | Đi cùng F1 | [ ] |
| F5 | **Quái tự đi / đuổi / kéo về, đánh xa, AI 10 Hz** | Khác | ❌ | – | | [ ] |
| F6 | **Tick bản đồ 20 Hz, snapshot 10 Hz, chỉ gửi thay đổi, AOI theo ô** | Khác | ❌ | – | Không cần cho turn-based | [ ] |
| F7 | **Giới hạn người / world** (`maxPlayersPerWorld`) | Không | 🟡 | S | Bảo vệ server khi đông bất thường | [ ] |
| F8 | **Cổng có yêu cầu cấp**, danh sách cổng trên bản đồ nhỏ | Khác: hạ trùm mở cổng; đá dịch chuyển | ❌ | – | Hắc Long hay hơn | [ ] |
| F9 | **Map phòng sự kiện** (Devil Square / Blood Castle) | – | ❌ | – | MU **chưa làm** (Phase 7 đang chờ duyệt) | [ ] |

## G. Nhiệm vụ

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| G1 | **Bỏ nhiệm vụ** ở bất kỳ đâu (có xác nhận) | Không | ✅ | S | | [ ] |
| G2 | **Theo dõi nhiệm vụ trên màn hình** (x/y, bấm mở panel) | Kiểm | ✅ | S | | [ ] |
| G3 | **Quái do đồng đội hạ cũng tính tiến độ** | Kiểm | ✅ | S | Khuyến khích chơi tổ đội | [ ] |
| G4 | **Giới hạn nhiệm vụ đang làm** (5) | Kiểm | ❌ | – | Ít giá trị | [ ] |
| G5 | **Mục tiêu "đạt cấp N"** | Kiểm | 🟡 | S | | [ ] |
| G6 | **Thưởng nhiệm vụ có ngọc** | – | ✅ | S | Đi cùng D7 | [ ] |

## H. Xã hội: tổ đội, bang, PvP, chat, thư, xếp hạng

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| H1 | **EXP tổ đội có thưởng** ×(1 + 0,1 × (n−1)), người ở xa / đã chết không nhận | Khác: chia vàng ×1,2/n | 🟡 | S | So lại công thức EXP của Hắc Long | [ ] |
| H2 | **Lời mời hết hạn 30 s** (tổ đội / bang / giao dịch) | Kiểm | 🟡 | S | | [ ] |
| H3 | **Trưởng nhóm rời → người vào sớm nhất lên thay; còn 1 người thì tan** | Kiểm | 🟡 | S | | [ ] |
| H4 | **Vai trò bang:** chủ / phó (tối đa 2) / thành viên; phó mời được, chỉ đuổi thành viên thường | Kiểm | 🟡 | S | | [ ] |
| H5 | **Chiến bang** (tuyên chiến, 60 s nhận, 20 điểm hoặc 30 phút, đầu hàng) | Không | 🟡 | M | Biến thể: **chiến bang trên đấu trường** (điểm theo trận đấu trường giữa hai bang trong 1 giờ) | [ ] |
| H6 | **Tên bang trên đầu nhân vật** | Kiểm | ✅ | S | | [ ] |
| H7 | **PK mở** (điểm PK, tên cam / đỏ, tự vệ 30 s, rơi đồ khi chết, Sát nhân bị cấm NPC) | Không | ❌ | – | | [ ] |
| H8 | **Thách đấu trực tiếp** (3 phút, 1 HP thua) | Khác: đấu trường bản sao | ❌ | – | Đã có tương đương | [ ] |
| H9 | **Chat bằng lệnh:** `/w Tên`, `/m`, `/p`, `/g` | Khác: chọn kênh bằng nút | ✅ | S | Gõ nhanh trên máy tính | [ ] |
| H10 | **Lọc từ cấm trong chat** (thay bằng `***`, danh sách trong config) | Không thấy | ✅ | S | | [ ] |
| H11 | **Giới hạn chat theo nhóm lệnh** (5 tin / 5 s) | Có giới hạn | ❌ | – | Đã có | [ ] |
| H12 | **Thư hết hạn 30 ngày; lọc Tất cả / Chưa đọc / Có quà; xóa đã đọc; tối đa 100** | Khác: giữ 50 | 🟡 | S | | [ ] |
| H13 | **Thư chào mừng khi tạo nhân vật** | Khác: quà tân thủ qua hướng dẫn | ❌ | – | Đã có tương đương | [ ] |
| H14 ★ | **Xếp hạng theo lớp + cache + hạng của mình** | Có 7 bảng, không cache, top 10 | ✅ | S | `INTEGRATION_PLAN §6` | [x] |
| H15 | **Xếp hạng bang theo tổng cấp thành viên** | Khác: theo quỹ, theo sát thương trùm | ❌ | – | Đã có | [ ] |

## I. Server: phiên, đồng bộ, bảo mật, độ bền dữ liệu

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| I1 | **Vé WebSocket ngắn hạn** (`POST /ws-ticket`, hạn vài chục giây) thay vì gửi token 30 ngày trong URL socket | Khác: `new Phoenix.Socket('/socket', {params: {token}})` (`net.js:57`); token nằm trong URL, có thể lọt vào log proxy | ✅ | S | Bảo mật, ít công | [ ] |
| I2 | **Lệnh có `rid`** (mã yêu cầu): gửi lại cùng `rid` không chạy hai lần | Không | ✅ | S | Chống bấm đúp / mạng chập chờn làm mua 2 lần | [ ] |
| I3 | **Kiểm phiên bản client** (`clientVersion`): bản cũ bị yêu cầu tải lại | Không | ✅ | S | Sau cập nhật, tab cũ không gửi lệnh sai | [ ] |
| I4 | **Giới hạn lệnh theo nhóm** (di chuyển / đánh / đồ / chat / thư…) | Khác: giới hạn chung 80 ms, burst 10 | 🟡 | S | Chặn spam riêng từng loại mà không làm chậm di chuyển | [ ] |
| I5 | **Khóa lạc quan `version`** trên `characters` | Không | ✅ | S | Chống ghi đè khi sửa DB ngoài Session (lệnh admin, script). Nên có trước K1 | [ ] |
| I6 | **Một phiên / tài khoản: đăng nhập nơi khác đẩy phiên cũ** | Khác: các tab dùng chung Session | ❌ | – | Thiết kế khác, không lỗi | [ ] |
| I7 | **Giữ nhân vật 30 s khi mất mạng; thoát khi đang đánh ở lại 10 s** | Khác: trận lưu trong DB | ❌ | – | Đã có tương đương | [ ] |
| I8 | **Ghi DB gộp** (30 s) + **ghi ngay khi có vàng / lên cấp** | Khác: lưu sau mỗi lệnh | ❌ | – | Hắc Long an toàn hơn | [ ] |
| I9 | **Băm mật khẩu Argon2** | Khác: PBKDF2 | ❌ | – | Cả hai đều ổn | [ ] |
| I10 | **Giới hạn đăng nhập theo IP + theo tên; đăng ký theo IP** | Có | ❌ | – | | [ ] |
| I11 | **Proxy tin cậy, `CHECK_ORIGIN`** | Có | ❌ | – | | [ ] |
| I12 | **Job dọn dữ liệu mồ côi định kỳ** | – | ❌ | – | Chỉ cần nếu làm C9 | [ ] |

## J. Dữ liệu game và cấu hình

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| J1 | **Không đặt cứng số gameplay:** mọi số trong data / config | Khác: nhiều số trong module (rương, rèn, bang, chợ, giao dịch, nâng cấp, chiến đấu, giá bán) | ✅ | M | Gom vào khóa `RULES` / `CONFIG` của `game_data.json`. Cân bằng không cần sửa code. Nền cho A3, B2, E7 | [ ] |
| J2 | **Kiểm dữ liệu lúc biên dịch** (tham chiếu sai → báo lỗi ngay: đồ trong cửa hàng không tồn tại, công thức thiếu nguyên liệu…) | Kiểm (có test bản đồ) | ✅ | S | Bắt lỗi gõ nhầm id khi thêm nội dung | [ ] |
| J3 | **Tách file data theo loại** (`items.json`, `monsters.json`, `skills.json`, `chaos.json`…) | Khác: một `game_data.json` | 🟡 | S | Dễ đọc hơn khi data lớn lên | [ ] |
| J4 | **Siêu dữ liệu mỗi bản ghi** (`sourceType`, `version`, `verified`) | – | ❌ | – | Quy trình riêng của MU | [ ] |
| J5 | **Công cụ nhập data** (`mix mu.items.import`: kiểm + chuẩn hóa) | – | ❌ | – | Chưa cần | [ ] |

## K. Quản trị và vận hành

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| K1 ★ | **Lệnh admin chỉnh nhân vật:** tặng xp / cấp / vàng / đồ +N / chỉ số; chạy trong Session (online thấy ngay) | Khác: tặng qua thư | ✅ | M | `INTEGRATION_PLAN §2` | [x] |
| K2 ★ | **`admin_log`** mọi thao tác quản trị | Không (chỉ Logger) | ✅ | S | Đi cùng K1 | [x] |
| K3 | **Lệnh dòng lệnh / rpc** cho thông báo, thư, sự kiện, audit (`mix x --node`, `bin/x rpc`) | Khác: tab Quản trị | 🟡 | S | Tiện khi vận hành từ xa / tự động hóa | [ ] |
| K4 | **Bật / tắt sự kiện tay** | Có gọi trùm thế giới | 🟡 | S | Đi cùng F1 / F2 | [ ] |
| K5 | **Phân quyền mod / admin** | Không (một cờ `admin`) | 🟡 | S | `INTEGRATION_PLAN 2-B` | [ ] |
| K6 | **Quyền đọc lại khi đổi** (không cần kết nối lại) | Khác: gán lúc kết nối | 🟡 | S | | [ ] |
| K7 | **Công thức dựng nhân vật admin** (một khối lệnh copy là xong) | – | ✅ | S | Đi cùng K1, ghi trong `ADMIN_GUIDE` | [ ] |
| K8 | **Release tự chạy migration khi khởi động** | Kiểm (có `rel/`) | ❌ | – | | [ ] |

## L. Client: màn hình, panel, thao tác

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| L1 | **Hình nhân vật kèm ô trang bị** (bố cục "búp bê": ô quanh hình nhân vật) | Khác: 3 dòng danh sách | ✅ | S–M | Đẹp hơn ngay cả với 3–4 ô; cần nếu làm C1 / C2 / D6 | [ ] |
| L2 | **Panel Thông báo** (lưu lại, chưa đọc / đã đọc, xóa) | Khác: toast rồi mất | ✅ | S | Người chơi không lỡ tin quan trọng | [ ] |
| L3 | **Phím tắt máy tính** (C / I / M nhân vật / túi / bản đồ, Q / W bình, Enter chat, Esc đóng) | Kiểm (có `keydown`) | ✅ | S | | [ ] |
| L4 | **Bản đồ nhỏ** (mình, NPC, cổng, vùng an toàn) | Kiểm | 🟡 | S | | [ ] |
| L5 | **Thanh sự kiện đếm ngược** giữa trên màn hình | Khác: banner trùm thế giới | 🟡 | S | Đi cùng F2 | [ ] |
| L6 | **Thanh buff có đếm ngược** (icon + giây còn lại) | Khác: tag hiệu ứng trong trận | 🟡 | S | Món ăn / lễ hội đang có hiệu lực ngoài trận | [ ] |
| L7 | **Panel Máy ghép** (đặt đồ, xem tỉ lệ / phí, kết quả) | – | ✅ | M | Đi cùng D5 | [ ] |
| L8 | **Xác nhận hành động nguy hiểm** (vứt đồ, bỏ nhiệm vụ, ép có rủi ro, đánh người) | Kiểm (trùm có xác nhận) | ✅ | S | Đi cùng D1 / G1 | [ ] |
| L9 | **Màn chọn nhân vật** (4 ô, đổi nhân vật trong game) | Khác: 1 nhân vật | ❌ | – | | [ ] |
| L10 | **Menu khi chạm người chơi** (tấn công, thách đấu, mời tổ đội / bang, giao dịch, đi tới) | Có (xem đồ, mời tổ đội, thách đấu…) | ❌ | – | Đã có | [ ] |
| L11 | **Panel giao dịch hai bàn** (khóa → đồng ý) | Có | ❌ | – | Kiểm "đổi thì mở khóa" ở E5 | [ ] |
| L12 | **Nút nổi trên điện thoại** (🧪 💧 ✋ 💬), không tràn ngang ở 360 px | Thiết kế điện thoại sẵn | ❌ | – | Hắc Long tốt hơn | [ ] |
| L13 | **Thanh trạng thái mạng + tự nối lại** | Có | ❌ | – | | [ ] |
| L14 | **Cài đặt âm thanh** | Có (tốt hơn) | ❌ | – | | [ ] |

## M. Client: vẽ, hiệu ứng, kỹ thuật

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| M1 | **Vẽ cánh bằng code** (2 lớp, cấp 2 to hơn, màu theo lớp) | – | ✅ | S | Đi cùng D6 | [ ] |
| M2 | **Tên màu theo trạng thái** (bang địch, PK…), tên bang trên đầu | Kiểm | 🟡 | S | Đi cùng H6 | [ ] |
| M3 | **Quầng vàng cho quái sự kiện, trùm vẽ to 1,5 lần, thanh máu dài** | Kiểm | ✅ | S | Đi cùng F1 | [ ] |
| M4 | **Số sát thương bay, hiệu ứng trúng / trượt** | Kiểm (màn trận theo lượt) | 🟡 | S | Đi cùng A2 | [ ] |
| M5 | **Di chuyển trượt mượt (Glide), camera theo vị trí vẽ** | Đã mượt | ❌ | – | | [ ] |
| M6 | **Client TypeScript**, kiểu cho protocol | Khác: JS thuần (`ui.js` 2 100 dòng) | 🟡 | L | Lớn. Thay thế nhẹ: tách dần logic thuần (giá, công thức hiển thị, chat) ra module riêng có test (N2) | [ ] |
| M7 | **Icon item thật + ảnh thay thế khi thiếu** (build không lỗi) | Có icon | ❌ | – | | [ ] |
| M8 | **Hook test** (`window.__mu`: trạng thái, vị trí vẽ) | Không | ✅ | S | Đi cùng N1 | [ ] |

## N. Test, CI, công cụ

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| N1 ★ | **E2E Playwright** (smoke, xã hội, tiến trình, quản trị, điện thoại) | Không | ✅ | M | `INTEGRATION_PLAN §5` | [x] |
| N2 | **Unit test logic client** (`node --test`) | Không | ✅ | S | Đi cùng M6 (bản nhẹ) | [ ] |
| N3 ★ | **Soak test** (N bot, đo trễ p50 / p95, lỗi, bộ nhớ) + audit sau soak | Không | ✅ | M | `INTEGRATION_PLAN §5` | [x] |
| N4 | **CI chạy được** (job ở repo ngoài, `working-directory`) | Không chạy (thư mục con) | ✅ | S | `INTEGRATION_PLAN §0` | [ ] |
| N5 | **Test chống nhân bản song song** (bắn nhiều lệnh cùng lúc, kiểm không ra đồ / vàng thừa) | Không | ✅ | S | Đi cùng E1 / E4 | [ ] |
| N6 | **Simulator theo cách chơi** | Có | ❌ | – | Chỉ thêm mode mới khi làm D1 / D6 | [ ] |
| N7 | **Kiểm tài sản riêng không vào git** (CI kiểm `git ls-files`) | – | ❌ | – | Hắc Long không có tài sản riêng | [ ] |

## O. Tài liệu

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| O1 | **`USER_GUIDE`** (hướng dẫn người chơi đầy đủ) | Khác: README có phần nội dung | ✅ | S | | [ ] |
| O2 | **`ADMIN_GUIDE`** (lệnh quản trị, sao lưu, xử lý tình huống) | Khác: `DEPLOY.md` | ✅ | S | Đi cùng K1 | [ ] |
| O3 | **`DECISIONS` / `OPEN_QUESTIONS`** (ghi quyết định, câu hỏi chờ duyệt) | Không | 🟡 | S | Theo dõi vì sao số / luật được chọn | [ ] |
| O4 | **Ảnh chụp màn hình trong tài liệu** (do e2e chụp) | Kiểm | 🟡 | S | Đi cùng N1 | [ ] |

---

## P. Bổ sung sau khi rà toàn bộ `docs/` của MU Web

> Rà ngày 2026-10-04: đọc hết `docs/kb/*`, `DECISIONS` (DEC-1 → DEC-188), `OPEN_QUESTIONS`, `BACKLOG`, các file kế hoạch / nghiệm thu / hướng dẫn.
> Chỉ ghi mục **chưa có** ở A–O. Đánh số tiếp theo từng nhóm.
>
> **"MU chưa làm"** = MU mới có trong kế hoạch / backlog, chưa code. Mang sang Hắc Long thì phải tự thiết kế.

### P-A. Chiến đấu

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| A13 | **Thứ tự kiểm một đòn**: còn sống → đã học kỹ năng → mục tiêu hợp lệ → không ở vùng an toàn → tầm → hồi chiêu → MP; trả đúng mã lỗi | Khác (theo lượt) | ❌ | – | | [ ] |
| A14 | **Hồi chiêu theo tốc đánh**: `max(250, 1000 / (1 + AS/100))`, AS = AGI/15 + tốc vũ khí | Khác | ❌ | – | Theo lượt không có hồi chiêu theo ms | [ ] |
| A15 | **Chỉ làm tròn xuống ở bước cuối** công thức sát thương (các bước giữa giữ số thực) | Kiểm | 🟡 | S | Đi cùng A1 | [ ] |
| A16 | **Luật cộng dồn buff**: dùng lại cùng buff thì làm mới thời gian và giữ giá trị lớn hơn; buff khác nhau cộng dồn; mất khi chết / thoát; hồi máu không vượt HP tối đa | Có hiệu ứng trong trận | 🟡 | S | Chỉ cần nếu làm A7 | [ ] |
| A17 | **Không thưởng khi hạ người chơi** (chống nuôi tài khoản phụ) | Khác: đấu trường thắng được `30 + 5 × Δ Elo` vàng | 🟡 | S | Chống "bơm" Elo / vàng: thưởng giảm dần khi đánh cùng một người nhiều lần trong ngày | [ ] |
| A18 | **Vùng an toàn cho phép hồi máu / buff**; chỉ đòn tấn công mới tính "đang chiến đấu" | Khác | ❌ | – | | [ ] |
| A19 | **Quái chọn mục tiêu**: gần nhất, bị đánh thì chuyển sang người gây nhiều sát thương; bị kéo xa thì về chỗ cũ, hồi đầy máu | Khác | ❌ | – | | [ ] |
| A20 | **Dòng Excellent / Luck rơi ngẫu nhiên trên đồ** (MU chưa làm) | Có: đồ ngẫu nhiên 3 độ hiếm | ❌ | – | Hắc Long đã có tương đương | [ ] |

### P-B. Nhân vật

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| B10 | **Không gỡ được điểm**; MU để ngỏ **vật phẩm Reset điểm** | Kiểm (có chuyển sinh) | 🟡 | M | "Thuốc Tẩy Tủy" bán đắt: cho làm lại điểm + rút vàng khỏi kinh tế | [ ] |
| B11 | **Vị trí lưu không đi được → đưa về điểm sinh** khi vào game | Kiểm | ✅ | S | Chống kẹt sau khi sửa bản đồ | [ ] |
| B12 | **Xóa / đổi tên nhân vật** (MU chưa làm) | Kiểm | 🟡 | S | Đổi tên có phí = chỗ tiêu vàng; giữ tên cũ trong log | [ ] |
| B13 | **Chỉ số phép tách riêng cho lớp lai** (đòn phép, tốc phép) | – | ❌ | – | Chỉ cần nếu làm B5 | [ ] |

### P-C. Đồ, túi

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| C13 | **Luật gộp stack** (gộp vào stack ô thấp nhất, tràn ra stack mới, có log) | Khác (`inv` là số đếm) | ❌ | – | | [ ] |
| C14 | **Nhặt đồ nguyên tử** (bản đồ trao cho đúng 1 người, ghi DB lỗi thì đồ về đất) | Khác | ❌ | – | | [ ] |
| C15 | **Ép chỉ đồ trong túi** (không ép đồ đang mặc) | Ngược lại: chỉ ép đồ đang mặc | ❌ | – | Giữ kiểu Hắc Long | [ ] |
| C16 | **Ô khóa theo cờ tính năng** (🔒 ô cánh khi chưa bật), **ô cấm theo lớp** | – | 🟡 | S | Đi cùng D6 / C1 / J6 | [ ] |
| C17 | **Kích thước ô của đồ** (kiếm 1×3, giáp 2×2) cho túi lưới | – | 🟡 | S | Chỉ khi làm C5 | [ ] |
| C18 | **Khóa đồ** (chống bán / ghép / giao dịch nhầm) — MU chưa làm | Không | ✅ | S | Rất nên có khi thêm Máy ghép (D5): lỡ bỏ đồ +9 vào máy là mất | [ ] |
| C19 | **Sắp xếp túi**, **chọn số lượng khi tách** — MU chưa làm | Khác: túi đã chia nhóm | ❌ | – | | [ ] |
| C20 | **Đồ nhiệm vụ ràng buộc** (không bán / giao dịch / cất; mất khi rời phòng) — MU chưa làm | Kiểm | 🟡 | S | Cần nếu làm F16 | [ ] |
| C21 | **Hình mờ ở ô trang bị trống** | – | ✅ | S | Đi cùng L1 | [ ] |

### P-D. Nâng cấp, máy ghép, cánh

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| D9 | **Sự kiện kết quả ép riêng** `{ok, level, option, destroyed}`: client phân biệt "thành công" / "tụt cấp" / "mất đồ" (hiệu ứng, âm thanh khác nhau) | – | ✅ | S | Đi cùng D1 | [ ] |
| D10 | **Vòng Soul thất bại → Bless lại** (+6 tụt +5, Bless lên lại +6 chắc chắn): chấp nhận như chi phí | – | ✅ | S | Ghi rõ trong thiết kế D1 để người chơi hiểu | [ ] |
| D11 | **Giá NPC thu lại cánh / ngọc thấp hơn chi phí tạo** (chống "in tiền") | – | ✅ | S | Bắt buộc khi đặt giá D1 / D6 | [ ] |
| D12 | **Máy ghép khớp chặt**: đặt thừa đồ = không khớp; ngọc phải đủ trong một stack; tối đa 8 món | – | ✅ | S | Đi cùng D5; chống mất đồ do đặt nhầm | [ ] |
| D13 | **Thông báo khi ghép thành công** (cánh, +10 / +11) | – | ✅ | S | Đi cùng D3 / D5 | [ ] |

### P-E. Kinh tế, chống gian lận

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| E11 | **Bắt buộc lý do khi đổi vàng** (thiếu lý do → báo lỗi ngay khi chạy test) | Không | ✅ | S | Đi cùng E1 | [ ] |
| E12 | **Script test / admin đổi vàng qua log `ADMIN`** để audit luôn sạch | – | ✅ | S | Đi cùng E1 / K1 | [ ] |
| E13 | **Gom / dọn log vàng** (theo phút hoặc xóa sau N ngày) — MU chưa làm | – | 🟡 | S | `INTEGRATION_PLAN 1-A` | [ ] |
| E14 | **Ràng buộc DB: vàng `BIGINT CHECK (gold >= 0)`** | Không: `gold` là `integer`, không có CHECK | ✅ | S | Lỗi code làm âm vàng sẽ bị DB chặn; `bigint` tránh tràn số | [ ] |
| E15 | **Chi tiết giao dịch**: đồ nhận vào ô trống, không gộp (giữ dấu vết); một giao dịch / người; chốt lỗi thì giữ phiên + mở khóa; đóng panel = hủy; đồ trên bàn bị đổi ở chỗ khác thì gỡ khỏi bàn | Kiểm | 🟡 | S | Đi cùng E4 / E5 | [ ] |
| E16 | **Giao dịch một phần stack** — MU chưa làm | Kiểm | 🟡 | S | | [ ] |
| E17 | **Nhận thư "tất cả hoặc không"** (túi đầy thì không nhận gì, kể cả vàng) | Kiểm | ✅ | S | Tránh mất quà khi túi đồ ngẫu nhiên đầy | [ ] |
| E18 | **Hệ số toàn server** (x2 EXP / x2 rơi đồ / x2 vàng) trong config, bật theo sự kiện | Khác: lễ hội có `xp_bonus` | ✅ | S | Lệnh admin "x2 EXP cuối tuần" có hạn giờ | [ ] |

### P-F. Thế giới, sự kiện

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| F10 | **Luật bố trí bãi tân thủ** (cách quái mạnh ≥ 7 ô, có test) | Khác (vùng tách bản đồ) | ❌ | – | | [ ] |
| F11 | **Bản đồ "ngủ" khi không có người** (AI quái dừng) | Kiểm | 🟡 | S | Tiết kiệm CPU khi server có nhiều bản đồ | [ ] |
| F12 | **Quái hồi sinh ở ô ngẫu nhiên trong vùng** | Kiểm | ❌ | – | | [ ] |
| F13 | **Lịch sự kiện tránh trùng** (phút 0 / phút 30) | – | ✅ | S | Đi cùng F2 | [ ] |
| F14 | **Quái đánh xa** (HP ×0,8) | Khác | ❌ | – | | [ ] |
| F15 | **Phòng sự kiện theo lịch** (Devil Square / Blood Castle: vé, tối đa 10 người, vào qua NPC 5 phút trước giờ, đợt quái, điểm, thưởng theo hạng; cổng / tượng là vật có máu không đánh trả) — **MU chưa làm** | Khác: Tháp Vô Tận, trùm thế giới | 🟡 | L | Biến thể hợp Hắc Long: "Đấu Trường Quỷ" cho tổ đội 3 người, 10 đợt quái theo lượt, giới hạn giờ, bảng điểm tuần | [ ] |
| F16 | **Vé sự kiện rơi từ quái** (0,2–0,3 %, quái vàng 5 %) — MU chưa làm | – | 🟡 | S | Đi cùng F15 | [ ] |
| F17 | **Đo cân bằng đã biết** (bầy Spider cùng lao vào, DW thiếu tiền bình, tốc độ ngọc theo lớp) bằng simulator | – | ✅ | S | Gộp N15 | [ ] |

### P-G. Nhiệm vụ

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| G7 | **Thu thập: đếm đồ trong túi lúc trả**, dùng stack nhỏ trước | Có | ❌ | – | | [ ] |
| G8 | **Trả nhiệm vụ nguyên tử**: kiểm lại tiến độ / cấp trong DB, không trả được 2 lần, có log | Kiểm | ✅ | S | Đi cùng I2 (`rid`) | [ ] |
| G9 | **Việc hằng ngày kiểu MU P7** (seed theo ngày + nhân vật, thưởng 25 % EXP cấp, **làm đủ 3 việc thưởng ngọc**) — MU chưa làm | Có việc hằng ngày | 🟡 | S | Chỉ lấy phần "đủ 3 việc thưởng ngọc" (đi cùng D7) | [ ] |

### P-H. Xã hội

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| H16 | **Khung tổ đội đầy đủ**: ★ trưởng nhóm, lớp, cấp, thanh máu, "Khác map" / "Mất kết nối", nút đuổi | Có `viewParty` | 🟡 | S | So lại, thêm phần còn thiếu | [ ] |
| H17 | **Chuyển chủ bang** (MU chưa làm) | **Có** (`Guilds.transfer`) | ❌ | – | Hắc Long đã có | [ ] |
| H18 | **Báo thay đổi bang khi offline bằng thư** (bị đuổi, được phong) — MU chưa làm | Kiểm | 🟡 | S | | [ ] |
| H19 | **Người bị cấm chat nhận thông báo kèm giờ hết cấm** | Kiểm | 🟡 | S | | [ ] |
| H20 | **Chặn / báo cáo người chơi** (MU chưa làm) | **Có** | ❌ | – | | [ ] |
| H21 | **Thư giữa người chơi**, **lịch sử chat đầy đủ** (MU chưa làm) | Có tin nhắn bạn bè, giữ 50 tin | ❌ | – | | [ ] |
| H22 | **Chống nuôi điểm chiến bang** (cùng nạn nhân chỉ tính 1 lần / X phút) — MU chưa làm | – | 🟡 | S | Chỉ khi làm H5 | [ ] |

### P-I. Server, bảo mật

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| I13 | **Tự ngắt kết nối khi vi phạm giới hạn lệnh liên tục ≥ 5 s** | Kiểm | ✅ | S | Chặn script spam | [ ] |
| I14 | **Giới hạn riêng từng endpoint** (vé WS 20 / phút / tài khoản, tạo nhân vật 10 / phút) | Có giới hạn đăng nhập / đăng ký | 🟡 | S | | [ ] |
| I15 | **Mọi lệnh phải thuộc một nhóm giới hạn** (test kiểm, quên là test đỏ) | – | ✅ | S | Đi cùng I4 | [ ] |
| I16 | **Lỗi vào game có lý do** (`clientVersion` / nhân vật / tham số) | – | ✅ | S | Đi cùng I3 | [ ] |
| I17 | **Lọc tham số nhạy cảm khỏi log** (`token`, `ticket`, `password` → `[FILTERED]`; không ghi query string) | **Không** (`filter_parameters` không có) | ✅ | S | Bảo mật, 1 dòng config. Rất nên làm cùng I1 | [ ] |
| I18 | **Giao diện chống XSS** (chỉ dùng `textContent`) | Khác: dựng HTML bằng chuỗi + `innerHTML`, có hàm `esc()` (≈ 97 chỗ) | 🟡 | S | Rà lại mọi chỗ chèn tên / chat / tên bang đều qua `esc()`; thêm test XSS | [ ] |
| I19 | **Bộ mã lỗi chuẩn** (12 mã), client dịch sang tiếng Việt | Khác: server trả câu tiếng Việt | 🟡 | M | Tiện test / đa ngôn ngữ sau này; không gấp | [ ] |
| I20 | **Chống gian lận di chuyển + điểm nghi ngờ** (kéo về, ghi log, cộng điểm) | Có kiểm từng bước (≈ 11 bước / s) | 🟡 | S | Thêm log + điểm nghi ngờ hiện ở tab Quản trị | [ ] |
| I21 | **Phát hiện bot / CAPTCHA** — MU chưa làm | Không | 🟡 | M | Chống treo máy cày | [ ] |
| I22 | **Nhiều node** (libcluster / Horde), **MessagePack** — MU chưa làm | Không | ❌ | – | Chưa cần | [ ] |
| I23 | **Ràng buộc DB "một đồ một chỗ"** (khóa chính `item_locations`, unique ô) | – | 🟡 | – | Chỉ khi làm C9 | [ ] |
| I24 | **Không cập nhật giao diện trước khi server trả lời** | Có | ❌ | – | | [ ] |

### P-J. Dữ liệu, cấu hình

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| J6 | **Cờ tính năng** (`features.*`) bật / tắt cả hệ thống; tắt → lệnh trả FORBIDDEN; test kiểm cờ | Không | ✅ | S | Bật dần Ngọc / Cánh / Máy ghép, tắt nhanh khi có lỗi | [ ] |
| J7 | **Gửi luật cho client lúc vào game** (UI kiểm trước, server vẫn quyết) | Có (`GAME_DATA`) | ❌ | – | | [ ] |
| J8 | **Số đề xuất gắn `verified: false`** chờ duyệt; lệch thiết kế ghi `CHANGE_REASON` | – | 🟡 | S | Quy trình, đi cùng O3 | [ ] |

### P-K. Quản trị, vận hành

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| K9 | **Sổ tay vận hành**: quy trình bảo trì, bảng xử lý sự cố, sao lưu / phục hồi DB (`pg_dump` theo lịch, thử phục hồi) | Có `DEPLOY.md` | ✅ | S | Đi cùng O2 | [ ] |
| K10 | **Tra người online** (số người, danh sách tên) | Có tra theo tên | 🟡 | S | Thêm số online + danh sách trong tab Quản trị | [ ] |
| K11 | **Quy tắc "chỉ sửa khi offline", "không sửa đồ / vàng bằng SQL"** | – | ✅ | S | Ghi trong `ADMIN_GUIDE`; đi cùng I5 | [ ] |

### P-L. Giao diện

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| L15 | **Panel NPC tự đóng khi đi xa** | Kiểm | 🟡 | S | | [ ] |
| L16 | **Ưu tiên chạm**: quái / đồ / NPC hơn người chơi cùng ô | Khác: người chơi trước | 🟡 | S | | [ ] |
| L17 | **Chỉ dựng lại phần giao diện có dữ liệu đổi** (không vẽ lại cả trang mỗi lần nhận trạng thái) | Kiểm: `refresh()` có vẻ dựng lại cả khung | ✅ | S–M | Đỡ giật, không mất chữ đang gõ / vị trí cuộn | [ ] |
| L18 | **Thanh tóm tắt cuối túi** (vàng, số món / tối đa, số bình, gợi ý "bán ở NPC") | Kiểm | 🟡 | S | | [ ] |
| L19 | **Panel cửa hàng hai cột** (hàng NPC \| đồ của mình + [Bán]) | Kiểm | 🟡 | S | | [ ] |
| L20 | **Thư: icon theo loại** (🎁 quà / 🔧 hệ thống / 🎉 chào mừng), **thời gian tương đối**, ✓ đã nhận | Kiểm | 🟡 | S | | [ ] |
| L21 | **Thông báo phân loại** (lên cấp / rơi đồ / nhặt / EXP / lỗi / hệ thống, có icon, giữ 50) | – | ✅ | S | Đi cùng L2 | [ ] |
| L22 | **Thông tin quái khi chạm** (cấp, máu, loại) trước khi đánh — MU chưa làm | Có xác nhận trước khi đấu trùm | ✅ | S | Thẻ thông tin quái thường: cấp, máu, vàng / EXP dự kiến, đã hạ bao nhiêu (sổ tay) | [ ] |
| L23 | **Kéo panel, gán phím bình / kỹ năng, xem trước nhân vật khi mặc thử** — MU chưa làm | – | 🟡 | S–M | "Mặc thử" xem hình nhân vật trước khi mua: hay cho cửa hàng | [ ] |
| L24 | **Bố cục HUD / panel một màn hình / menu ☰ hiện dần theo tính năng** | Khác (thiết kế riêng) | ❌ | – | | [ ] |

### P-M. Vẽ, asset

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| M9 | **Viền / màu đồ theo cấp +N** (khác nhau ở +7, +9, +11) | – | ✅ | S | Đi cùng D1: nhìn là biết đồ "khủng" | [ ] |
| M10 | **Ảnh đồ không kéo giãn, chỉ phóng số nguyên** | Kiểm | 🟡 | S | | [ ] |
| M11 | **Hoạt ảnh nhân vật nhiều khung, hiệu ứng kỹ năng / lên cấp / hồi máu** — MU chưa làm | Kiểm | 🟡 | M | Hiệu ứng nhỏ bằng CSS / canvas (lóe sáng khi trúng, chữ "LÊN CẤP") | [ ] |
| M12 | **Tối ưu tải ảnh** (tải trước theo bản đồ, nén, cache header, ghép atlas) — MU chưa làm | Kiểm | 🟡 | S | Đỡ tốn mạng điện thoại | [ ] |
| M13 | **Tách lớp vẽ (`GameView`)**, **Phaser** | – | ❌ | – | | [ ] |

### P-N. Test, công cụ

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| N8 | **Test tất định** (RNG có seed, đồng hồ giả, tick tay) | Có `HacLong.Game.Rng` | 🟡 | S | Kiểm `Rng` có seed được trong test không; cần cho D1 / D5 | [ ] |
| N9 | **Script seed dữ liệu test đi qua đường có log** | – | ✅ | S | Đi cùng N1 / E12 | [ ] |
| N10 | **IP giả mỗi trình duyệt trong e2e** (không nới giới hạn đăng nhập) | – | ✅ | S | Đi cùng N1 | [ ] |
| N11 | **Soak chi tiết**: kịch bản theo cờ (tổ đội / chợ / giao dịch / trùm), **probe ở node riêng** (độ trễ tick, hàng đợi tiến trình, RAM, số process), tiêu chí đạt, **băng thông theo loại sự kiện**, chạy e2e trong lúc soak | – | ✅ | M | Chi tiết hóa N3 | [ ] |
| N12 | **Test phạm vi tính năng** (cờ chưa bật phải tắt) | – | ✅ | S | Đi cùng J6 | [ ] |
| N13 | **Theo dõi test chập chờn** (ghi tên + seed) | – | 🟡 | S | | [ ] |
| N14 | **Đo kinh tế trong simulator** (vàng tiêu bình / giờ, ngọc / giờ, theo lớp) | Có simulator | ✅ | S | Cần trước khi đặt số D1 / D7 | [ ] |
| N15 | **Kiểm thử tải 500 người** (k6 / tsung) | – | 🟡 | M | | [ ] |
| N16 | **Môi trường cloud cho agent** (hook khởi động Postgres + `deps.get`) | Không | ✅ | S | Agent sau chạy `mix test` Hắc Long ngay | [ ] |

### P-O. Tài liệu, quy trình

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| O5 | **Checklist nghiệm thu đánh số**, 3 lớp bằng chứng (ExUnit / E2E / soak), chạy lại phần cũ | – | 🟡 | S | | [ ] |
| O6 | **Tài liệu đề xuất số có phương án A / B + bảng simulator** trước khi chốt | – | ✅ | S | Dùng cho D1 / D6 / D7 | [ ] |
| O7 | **Kế hoạch theo bước có ⛔ chờ duyệt, dừng báo cáo mỗi bước** | – | 🟡 | S | Đã áp dụng trong `INTEGRATION_PLAN` | [ ] |
| O8 | **`USER_GUIDE`: hỏi đáp, mẹo tân thủ, lộ trình luyện cấp, đổi giờ UTC → VN** | – | ✅ | S | Đi cùng O1 | [ ] |
| O9 | **Checklist kiểm bằng mắt** (máy tính ≥ 1280, điện thoại 360×740, 2 người, tải lại trang) | – | 🟡 | S | | [ ] |

### Ngoài phạm vi (MU cũng không làm)

Chaos Castle, Jewel of Harmony / Guardian / Creation, lớp DL / SUM, nhiều phòng sự kiện cùng lúc, chế vé sự kiện, sửa đồ / độ bền.

---

## Q. Sắp xếp lại giao diện Hắc Long

> Theo nguyên tắc ở đầu file. **Không đụng:** tab Bản đồ (bản đồ, NPC, trận đánh, chat, tổ đội), HUD, thanh tab, màn đăng nhập / tạo nhân vật, phong cách thẻ.

### Q.1 Hiện trạng (`priv/static/js/ui.js`)

| Tab | Đang chứa | Hàm |
|---|---|---|
| **Bản đồ** | bản đồ, hướng dẫn, banner trùm, nội thất, hội thoại, câu cá, tổ đội, chat; NPC mở đè lên | `ui.js:115` |
| **Hành trình** | hồi máu, hành trình diệt rồng, thẻ bang, đấu trường, sổ tay quái, trùm thế giới, bảng xếp hạng (7 bảng), "Thành tích" (số quái / số lần gục), âm thanh, dữ liệu | `viewTown` `ui.js:840` |
| **Nhân vật** | hình + công / thủ / chí mạng / né; tiềm năng (+1 / +5); trang bị (3 dòng); thú cưng; kỹ năng; **thành tựu + danh hiệu** | `viewHero` `ui.js:1070` |
| **Túi đồ** | thẻ Bình máu / Món ăn / Đồ (trang bị + đồ ngẫu nhiên) / Nguyên liệu, mỗi món một dòng có nút | `viewBag` `ui.js:1229` |
| **Nhiệm vụ** | nhiệm vụ Trưởng Làng, việc hằng ngày, nhiệm vụ bang | `viewQuests` `ui.js:1567` |
| Quản trị | (chỉ admin) | `viewAdmin` `ui.js:143` |

**Nhận xét:**
- Tab **Nhân vật** dài: 6 thẻ, thành tựu chiếm nhiều chỗ nhất.
- Tab **Hành trình** gom quá nhiều thứ khác loại (xếp hạng, bang, đấu trường, cài đặt).
- Tab **Túi đồ** dạng danh sách, khó nhìn khi nhiều đồ.

### Q.0 Đã làm (2026-10-04)

Anh chốt:
- tab **Nhân vật** và **Túi đồ** làm **giống hệt MU Web** (cấu trúc + tính năng), giữ font / màu vàng-đen của Hắc Long;
- **bố cục 10 ô với 7 ô khóa**;
- **lưới tự xếp**;
- các phần không liên quan chuyển sang tab **Khác**.

Đã làm: Q1 (bố cục 10 ô), Q2, Q3 (cộng điểm gom lệnh), Q4 (tab Khác), Q5 (chuyển ra tab Khác), Q6 (lưới), Q7 (tooltip), Q8, Q9 (kéo thả), Q11 (phím tắt C / I / M / Q / Enter / Esc).
Chưa làm: Q10. Chi tiết code: `CODEBASE_NOTES.md §6`.

### Q.2 Đề xuất

| # | Thay đổi | Chi tiết | Lấy từ MU | Công | Chọn |
|---|---|---|---|---|---|
| Q1 | **Tab Nhân vật kiểu "búp bê"** | Trên cùng: hình nhân vật to (`Doll`, phóng ×3–4) ở giữa, **ô trang bị bao quanh** (vũ khí trái, giáp giữa-dưới, khiên phải; chừa sẵn ô nhẫn / cánh nếu làm C2 / D6, hiện 🔒 khi chưa mở). Ô trống có hình mờ. Bấm ô → tooltip (chỉ số, +N, so sánh, [Tháo]) | L1, C21, C11 | M | [ ] |
| Q2 | **Bảng chỉ số chi tiết 2 cột** | HP tối đa, công, thủ, chí mạng (% × hệ số), né, % thú / món ăn đang cộng, % cánh (nếu có); số hiện từ `view` server | B8 | S | [ ] |
| Q3 | **Cộng điểm kiểu MU** | 4 dòng Sức mạnh / Thể lực / Nhanh nhẹn / Phòng thủ, mỗi dòng: giá trị, mô tả ngắn, nút **[+]** (bấm nhiều lần, gom 1 lệnh, hiện "+n" đang chờ) và giữ **[+5]**; "Điểm còn: n" nổi bật | B6 | S | [ ] |
| Q4 | **Chuyển Thành tựu + danh hiệu ra khỏi Nhân vật** | Lựa chọn: **(a)** sang tab Hành trình, cạnh Sổ tay quái (đề xuất); **(b)** thành tab con "Thành tựu" trong Nhân vật; **(c)** nút "🏅 Thành tựu" mở panel riêng. Chọn danh hiệu vẫn làm được ở chỗ mới | – | S | [ ] |
| Q5 | **Thú cưng và Kỹ năng thu gọn** | Kỹ năng: 3 icon một hàng, bấm xem mô tả. Thú cưng: một thẻ nhỏ (icon, cấp, nút đổi); danh sách đầy đủ mở khi bấm | – | S | [ ] |
| Q6 | **Túi đồ dạng lưới ô** | Ô vuông 48–56 px: icon, số lượng góc dưới, **viền màu theo độ hiếm** (Tốt / Hiếm / Sử Thi) và **+N** góc trên. Lọc phía trên: Tất cả / Trang bị / Bình / Món ăn / Nguyên liệu (thay cho 4 thẻ). Điện thoại 5–6 cột, máy tính 8 cột. Không cần kéo thả trên điện thoại | C5, M9 | M | [ ] |
| Q7 | **Tooltip đồ** khi bấm ô | Tên (màu độ hiếm), chỉ số, dòng cộng, +N, cấp yêu cầu (đỏ khi thiếu), **so sánh với đồ đang mặc** (giữ của Hắc Long), giá bán; nút [Trang bị] / [Dùng] / [Ăn] / [Khóa]; trên máy tính hiện khi rê chuột | C11, C18 | S | [ ] |
| Q8 | **Thanh tóm tắt cuối túi** | Vàng · đồ ngẫu nhiên n/20 · bình máu (tổng) · gợi ý "Bán đồ ở Thợ Rèn" | L18 | S | [ ] |
| Q9 | **Kéo thả trên máy tính** (tùy chọn) | Kéo đồ từ túi lên ô trang bị để mặc, kéo ra để tháo | C5 | S | [ ] |
| Q10 | **Chia tab Hành trình thành tab con** (tùy chọn) | Hành trình (diệt rồng, sổ tay, thành tựu nếu chọn Q4a) · Xếp hạng · Bang & Đấu trường · Cài đặt (âm thanh, dữ liệu) | – | S | [ ] |
| Q11 | **Phím tắt máy tính** | C Nhân vật, I Túi, M Bản đồ, Q bình máu, Esc đóng | L3 | S | [ ] |

**Không đổi:**
- tab Bản đồ / NPC / trận đánh / chat / tổ đội, HUD, thanh tab dưới (vẫn 5 tab + Quản trị);
- màn đăng nhập / tạo nhân vật;
- phong cách thẻ và màu.

**Thứ tự gợi ý:** Q4 → Q1 + Q2 + Q3 + Q5 (tab Nhân vật) → Q6 + Q7 + Q8 (túi) → Q11 → Q9 / Q10 nếu muốn.

- Mỗi bước có ảnh chụp trước / sau (máy tính + điện thoại 360 px) để anh duyệt.
- Có e2e kiểm không tràn ngang.

---

## Tổng hợp đề xuất của Claude

**Đã chọn trước** (★, có thiết kế): E1, K1, K2, D1, D5, D6, N1, N3, H14.

**Nên thêm, công nhỏ, giá trị rõ** (≈ 1–2 ngày tổng):

| Nhóm | Mục |
|---|---|
| Sửa lỗi / an toàn | **E6** (lỗi chợ), **I1** (vé WebSocket), **I2** (`rid`), **I3** (phiên bản client), **I5** (khóa `version`), **N4** (CI chạy được) |
| Chơi | **A4** (phạt EXP chênh cấp), **B1** (lên cấp hồi đầy), **B4** (đồ khởi đầu theo lớp), **G1** (bỏ nhiệm vụ), **H10** (lọc từ cấm) |
| Giao diện | **B6** (cộng điểm gom lệnh), **L2** (panel Thông báo), **L3** (phím tắt), **L8** (xác nhận nguy hiểm) |

**Bổ sung từ lần rà `docs/` (mục P), nên làm, công nhỏ:**

| Nhóm | Mục |
|---|---|
| An toàn / bảo mật | **I17** (lọc token khỏi log), **E14** (vàng `bigint` + CHECK ≥ 0), **I13** (ngắt khi spam), **I15** / **I16**, **I18** (rà XSS) |
| Đi cùng ngọc / máy ghép | **C18** (khóa đồ), **D9**–**D13**, **M9** (viền theo +N), **N14** (đo kinh tế simulator), **O6** (đề xuất số A / B) |
| Vận hành | **J6** (cờ tính năng) + **N12**, **K9** (sổ tay vận hành), **N16** (môi trường cloud) |
| Chơi / giao diện | **B11** (vị trí kẹt → điểm sinh), **E17** (nhận thư tất cả hoặc không), **E18** (x2 EXP theo sự kiện), **L17** (chỉ vẽ lại phần đổi), **L21**, **L22** (thẻ thông tin quái) |

**Đợt 1 đã làm (2026-10-04):** E6, I17, E14, I2, I3, I1, N4. Chi tiết: `CODEBASE_NOTES.md §9b`.

**Đợt 2 đã làm (2026-10-04):** E1 (+ E12, E13), E2 (chỉ đồ hiếm có `uid`), E4, K1, K2, K3 (một phần: `HacLong.Admin.console`,
`HacLong.Release.audit` / `prune_logs`), O2 (`docs/ADMIN_GUIDE.md`), vai trò `player / mod / admin` (câu 2-B).
Câu 1-A, 1-B, 1-C, 2-A, 2-B chốt theo đề xuất. Chi tiết: `CODEBASE_NOTES.md §9c`.

**Nên làm, công vừa:**
- **C10:** cấp nâng theo từng món; cần trước D1.
- ~~**E4:** giao dịch một transaction.~~ (Đợt 2)
- ~~**E2:** log đồ ngẫu nhiên.~~ (Đợt 2)
- **F1:** Golden Invasion.
- **J1:** đưa số vào data.
- **L1:** hình nhân vật kèm ô trang bị.
- **C2:** nhẫn.

**Cân nhắc** (đổi cảm giác chơi / lớn):
- A1, A2: công thức đòn + tỉ lệ trúng;
- A7: kỹ năng hỗ trợ đồng đội;
- A11: nút tự đánh;
- C1: đủ 10 ô;
- C3: yêu cầu chỉ số;
- C5: túi lưới;
- C9 / E3: serial đồ;
- H5: chiến bang;
- M6: TypeScript.

**Thứ tự gợi ý nếu chọn hết nhóm "nên":**
1. Sửa lỗi / an toàn (E6, I1, I2, I3, I5, N4).
2. J1 + E1 + K1 / K2.
3. H14 + nhóm chơi / giao diện nhỏ.
4. N1 / N3.
5. C10 → D1 (+D2, D3, D7) → D5 / D6 (+L1, M1, L7).
6. F1.
