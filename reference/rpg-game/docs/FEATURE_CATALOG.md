# Danh mục tính năng MU Web có thể mang sang Hắc Long

> Liệt kê **toàn bộ** tính năng của MU Web (server + client + vận hành), so với Hắc Long hiện tại, kèm đánh giá của Claude.
> Anh đánh dấu cột **Chọn** (`[x]`) cho mục muốn làm. Mục đã chọn sẽ được đưa vào `docs/INTEGRATION_PLAN.md`
> (thiết kế chi tiết + câu hỏi) trước khi code.
>
> - Bản đồ code Hắc Long: `docs/CODEBASE_NOTES.md`.
> - Mục có ★ đã có thiết kế trong `INTEGRATION_PLAN.md`.

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
| B8 | **Bảng chỉ số chi tiết** (đòn min~max, thủ, tỉ lệ trúng, tốc độ, HP / MP tối đa) | Có công / thủ / chí mạng / né | 🟡 | S | Thêm HP tối đa, % thú / món ăn đang cộng, % cánh (nếu làm D6) | [ ] |
| B9 | **Tên nhân vật: lọc từ cấm** (`names.bannedWords`) | Kiểm | ✅ | S | Đi cùng H10 | [ ] |

## C. Đồ, trang bị, túi

| # | Tính năng MU Web | Hắc Long | Đánh giá | Công | Ghi chú | Chọn |
|---|---|---|---|---|---|---|
| C1 | **10 ô trang bị:** mũ, áo, quần, găng, giày, vũ khí, khiên, cánh, 2 nhẫn | Khác: 3 ô (vũ khí / giáp / khiên) | 🟡 | L | Chiều sâu đồ lớn nhất. Đụng data, `derived`, hình nhân vật (`doll.js` cần ảnh mũ / găng / giày; tile Dungeon Crawl có sẵn), UI, chợ, giao dịch. **Đề xuất làm từng bước:** thêm **nhẫn** (không cần vẽ) và **cánh** (D6) trước | [ ] |
| C2 | **Nhẫn** (+HP, không ép được) | Không | ✅ | M | Ô dễ thêm nhất: không vẽ trên người. Nhẫn rơi từ trùm / nhiệm vụ | [ ] |
| C3 | **Yêu cầu chỉ số để mặc** (STR / AGI / ENE tối thiểu), hiện đỏ khi thiếu | Khác: chỉ yêu cầu cấp | 🟡 | S | Cho điểm tiềm năng thêm ý nghĩa. Đổi cân bằng | [ ] |
| C4 | **Đồ theo lớp** (danh sách lớp được mặc; MG không đội mũ) | Kiểm (có vẻ mọi lớp mặc được hết) | 🟡 | S | Đi cùng B4 / B7 | [ ] |
| C5 | **Túi dạng lưới 8×8, kéo thả** xếp / mặc / tháo | Khác: danh sách theo nhóm | 🟡 | M | Đẹp trên máy tính, **kém hơn danh sách trên điện thoại** (Hắc Long ưu tiên điện thoại). Đề xuất: lưới cho màn ≥ 1024 px, giữ danh sách cho màn hẹp | [ ] |
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

## Tổng hợp đề xuất của Claude

**Đã chọn trước** (★, có thiết kế): E1, K1, K2, D1, D5, D6, N1, N3, H14.

**Nên thêm, công nhỏ, giá trị rõ** (≈ 1–2 ngày tổng):

| Nhóm | Mục |
|---|---|
| Sửa lỗi / an toàn | **E6** (lỗi chợ), **I1** (vé WebSocket), **I2** (`rid`), **I3** (phiên bản client), **I5** (khóa `version`), **N4** (CI chạy được) |
| Chơi | **A4** (phạt EXP chênh cấp), **B1** (lên cấp hồi đầy), **B4** (đồ khởi đầu theo lớp), **G1** (bỏ nhiệm vụ), **H10** (lọc từ cấm) |
| Giao diện | **B6** (cộng điểm gom lệnh), **L2** (panel Thông báo), **L3** (phím tắt), **L8** (xác nhận nguy hiểm) |

**Nên làm, công vừa:**
- **C10:** cấp nâng theo từng món; cần trước D1.
- **E4:** giao dịch một transaction.
- **E2:** log đồ ngẫu nhiên.
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
