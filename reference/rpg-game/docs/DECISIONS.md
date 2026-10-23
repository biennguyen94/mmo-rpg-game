# Quyết định nhỏ đã tự chốt — Hắc Long

> Những điều anh không nói tới mà em phải chọn khi làm, kèm lý do. Quyết định ảnh hưởng cân bằng / dữ liệu lưu / giao thức
> thì **không** tự chốt mà ghi vào `OPEN_QUESTIONS.md` để hỏi. Anh thấy chỗ nào không hợp thì báo, em đổi lại.
>
> Mỗi dòng: ngày · phase / đợt · quyết định · lý do.

## Phase 1 — Nền dữ liệu và cấu hình (2026-10-04)

| # | Quyết định | Lý do |
|---|---|---|
| P1-1 | Tách dữ liệu thành 12 file `priv/game_data/*.json`; mỗi file vẫn là object các **khóa lớn cũ** (`CLASSES`, `ZONES`…), không đổi tên khóa. `BOSS_DROPS` đi cùng `zones.json`, `JEWELS` cùng `upgrade.json`. | Sửa ít nhất có thể; client và code đọc khóa như cũ; nhóm theo chỗ dùng. |
| P1-2 | Hai file trùng khóa lớn → lỗi biên dịch (không ghi đè). | Tránh sửa nhầm một bản mà bản kia thắng âm thầm. |
| P1-3 | `RULES` nạp **lúc biên dịch** như mọi dữ liệu khác (không đọc lúc chạy). | Giữ kiểu Hắc Long (dữ liệu là hằng số biên dịch, nhanh); đổi số thì build lại như sửa đồ / quái. |
| P1-4 | Khóa trong `rules.json` viết `snake_case` (như `double_from`, `chest_chance` có sẵn); client nhận một số ở `GAME_DATA.RULES` kiểu `camelCase` như trước. | Thống nhất với dữ liệu server có sẵn, không đổi tên khóa client đang dùng. |
| P1-5 | Số chuyển sang `RULES` giữ **đúng giá trị và thứ tự phép tính** (vd `xp / 3` vẫn là chia 3 — `xp_div`, không đổi thành nhân 0,333). | Simulator cùng seed phải giống hệt trước / sau (đã kiểm: giống hệt). |
| P1-6 | Thông số của kỹ năng nằm ở `RULES.skill_effects` theo **kiểu tác dụng** (`cleave`, `holy`…), không nằm ở từng kỹ năng trong `classes.json`. | Nhiều kỹ năng dùng chung một kiểu tác dụng (`fire_ball`, `stun_bash`); sửa một chỗ. Câu thông báo trong trận (`+40%`…) tính từ số này. |
| P1-7 | **Để lại trong code** (không phải số cân bằng): thời gian (`@flush_ms`, `@hold_ms`, câu cá chờ / cửa sổ giật), giới hạn tần suất lệnh, kích thước tháp 13×11, độ dài tên 2–16 / bang 3–20 / chat 120, số dòng nhật ký, giới hạn quản trị, giới hạn chống lạm dụng của giao dịch (8 dòng, 10 triệu vàng), bạn bè (50), hộp thư (50). | Là giới hạn kỹ thuật / an toàn, không phải luật chơi; để trong code tránh sửa nhầm làm hỏng server. |
| P1-8 | **Để lại trong code, chuyển sau nếu cần:** danh sách thành tựu (`achievements.ex`), các bước hướng dẫn (`tutorial.ex`, chỉ quà đã sang `RULES.tutorial`), trùm thế giới (`world_boss.ex`). | Là nội dung có cấu trúc riêng (điều kiện là atom / hàm), chuyển sang JSON cần thêm bước dịch; chưa có nhu cầu chỉnh. |
| P1-9 | Kiểm dữ liệu (J2) chạy trong `Data` và `Maps` lúc biên dịch; lỗi gom hết rồi báo một lần, mỗi dòng có tên file + id. Danh sách `role` NPC và kỹ năng thú hợp lệ nằm trong `DataCheck` (code xử lý chúng ở đó). | Gõ nhầm id không lọt ra lúc chơi; thấy mọi lỗi một lượt thay vì sửa từng cái. |
| P1-10 | Từ cấm (B9): hai danh sách. `banned_words` khớp **nguyên từ** (sau bỏ dấu, chữ thường; số / ký hiệu là chỗ ngắt từ) để từ ngắn như `gm`, `dm`, `lon` không chặn nhầm "Thiên **Lon**g". `banned_parts` khớp **một phần** tên viết liền (có đổi `4dm1n` → `admin`), chỉ để từ dài, không lẫn. Bỏ `cac` khỏi danh sách vì trùng chữ "các". | Chặn được cách lách thường gặp mà ít chặn nhầm tên tiếng Việt. Anh sửa danh sách ở `rules.json` → `RULES.names`. |
| P1-11 | Từ cấm áp dụng cho tên nhân vật **mới**, tên và ký hiệu bang **mới**; tên đã có không bị đổi. | Đổi tên người đang chơi là việc của quản trị (chưa có công cụ đổi tên). |
| P1-12 | Vị trí lưu hỏng (B11): coi là hỏng khi bản đồ không còn, ô không đi được, **hoặc** bị bít cả bốn phía. Về **điểm vào của chính bản đồ đó** (cạnh đá dịch chuyển; không có thì chỗ đứng khi qua cổng vào), không được thì về Nhà. | Sau khi sửa bản đồ, người chơi vẫn ở vùng của mình thay vì bị đá về Nhà. |
| P1-13 | `mix hac_long.simulate` thêm `--seed`; tên bot lấy từ số ngẫu nhiên có seed (trước dùng `System.unique_integer`, làm việc hằng ngày đổi theo lần chạy). | Cần kết quả lặp lại được để so trước / sau khi đổi số. |

## Phase 2 — Lưới an toàn test (2026-10-04)

| # | Quyết định | Lý do |
|---|---|---|
| P2-1 | Hook test `window.__hl` chỉ bật khi mở trang với `?test=1`; chỉ đọc trạng thái và gọi đúng các thao tác người chơi vẫn làm (đi tới ô, gửi lệnh). | Không mở quyền mới; server vẫn kiểm mọi lệnh. Người chơi thường không thấy gì khác. |
| P2-2 | E2E dùng tài khoản quản trị `e2e_admin` (do `scripts/e2e_seed.exs` tạo) để tặng vàng / đồ / cấp cho nhân vật test qua lệnh quản trị thật, thay vì sửa database. | Đi đúng đường người vận hành dùng (có nhật ký ADMIN), kịch bản ngắn mà vẫn qua server thật. |
| P2-3 | Mỗi người chơi test gửi `X-Forwarded-For` ngẫu nhiên; server e2e chạy với `TRUSTED_PROXIES=127.0.0.1`. | Không phải nới giới hạn đăng ký 5 tài khoản / giờ / IP trong code. |
| P2-4 | Soak viết bằng WebSocket thô (giao thức Phoenix v2) trong Node, không cần trình duyệt hay thư viện ngoài; tìm đường dùng chung `logic.js` với client. | Chạy được 30–100 bot trên một máy, không phụ thuộc gói npm. |
| P2-5 | Ngưỡng soak đạt: không lỗi giao thức / quá giờ / mất kết nối, p95 < 150 ms (`SOAK_P95_MS`), có trận đánh; sau đó `mix hac_long.audit` sạch. | Theo `INTEGRATION_PLAN §5.3`. |
| P2-6 | CI: workflow riêng `hac-long-e2e.yml`, chỉ chạy khi sửa `reference/rpg-game/**`; tự chạy soak ngắn 10 bot / 2 phút, soak 30 bot / 10 phút chạy tay (Run workflow). | Câu 5-A / 5-B; giữ CI nhanh. |
| P2-7 | Hàm thuần của client (tìm đường, hình theo cấp, tỉ lệ máy ghép, cấp thú, gom lệnh cộng điểm) chuyển sang `priv/static/js/logic.js` (`window.HLLogic`), `ui.js` / `map.js` gọi lại; test `node --test test/js/*.test.mjs`. | Test được không cần trình duyệt; giữ JS thuần như cũ (không thêm bước build). |
| P2-8 | Ảnh trong tài liệu: `HL_SHOTS_DOCS=1 node e2e/run.mjs` chép 7 ảnh chọn lọc sang `docs/screenshots/e2e-*.png`. Ảnh cũ chụp tay giữ nguyên. | Ảnh luôn đúng giao diện hiện tại khi chạy lại e2e. |
| P2-9 | Giá thuần phục thú (`RULES.pets.tame_price*`) gửi cho client; mô tả việc hằng ngày sửa thành 4 việc (code tạo 4 việc từ trước, moduledoc ghi nhầm 3). | e2e bắt được chỗ lệch. |

## Phase 3 — Công thức chiến đấu (2026-10-04)

| # | Quyết định | Lý do |
|---|---|---|
| P3-1 | Hệ số kỹ năng / chí mạng / % cánh nhân **trước** bước trừ thủ (trước đây nhân sau). | Đúng thứ tự A1 của MU; đòn mạnh ít bị thủ "ăn" hơn. Simulator cho thấy không đổi cân bằng (thủ quái thấp). |
| P3-2 | Hệ số DR của quái `monster_dr = 0,8` × cấp (không chỉnh thêm). | Trúng quái cùng cấp 91–95 %, simulator lệch ≤ 2,7 % nên không cần bù. |
| P3-3 | Trượt quyết định bằng `Rng.uniform() < 1 − tỉ lệ trúng` (số ngẫu nhiên lớn = trúng). | Giữ cách test cũ: dãy số 0,99 là "đòn tốt". |
| P3-4 | `dodge` của quái giữ trong dữ liệu quái nhưng chỉ còn dùng ở đấu trường (né của bản sao người chơi). | Người đánh quái giờ theo tỉ lệ trúng (3-A). |

## Phase 4 — Ngọc, ép, kho (2026-10-04)

| # | Quyết định | Lý do |
|---|---|---|
| P4-1 | Đồ hiếm cất tủ vẫn nằm trong `gear` của nhân vật với cờ `stored`; đồ thường cất ở cột mới `characters.storage`. | Nhật ký đồ hiếm, đối soát trùng `uid` không phải đổi; cất / lấy không phải "ra / vào" nhân vật. |
| P4-2 | Ép (+N, Ngọc Sinh Mệnh) đồ thường **trong túi** tách một món ra thành bản riêng, nên cần một chỗ trống trong túi đồ hiếm (20). | Cấp ép / dòng tùy chọn lưu theo bản riêng như đồ đang mặc (Đợt 3, C10). |
| P4-3 | Ngọc Sinh Mệnh thất bại khi món chưa có dòng nào: chỉ mất ngọc. Ép được cả đồ đang khóa. | Đúng đề xuất §12.1; khóa chỉ chặn bán / vứt / giao dịch / máy ghép. |
| P4-4 | Nút "Ép" trong tooltip chỉ **chọn món** cho thẻ "Ép đồ" (không ép ngay); ở xa Thợ Rèn thì báo mang tới, món đã chọn giữ đến khi tới. | Ép có thể vỡ đồ: luôn thấy giá, tỉ lệ, rủi ro trước khi bấm. |
| P4-5 | Vứt một món: hộp xác nhận; nhiều món: hỏi số lượng (mặc định cả chồng). Đồ đang cất không vứt được (lấy ra trước). | Không có tách chồng (4-E) nên chọn số ngay khi vứt. |
| P4-6 | Bot simulator không dùng Ngọc Sinh Mệnh. | Giữ so sánh trước / sau; ngọc chỉ +4 / dòng, ít ảnh hưởng. |
| P4-7 | Kết quả lệnh `upgrade` / `life` kèm `uid` món vừa ép. | Client giữ món đang chọn khi đồ thường vừa được tách thành bản riêng. |

## Phase 5 — Xã hội, xếp hạng, PK cược vàng (2026-10-04)

| # | Quyết định | Lý do |
|---|---|---|
| P5-1 | Trận cược: người mời đánh trước; hết 30 lượt thì so **% máu còn**, bằng nhau là hòa (không ai mất vàng). Không đổi điểm Elo. | Luật rõ, kết quả lặp lại được khi test; Elo chỉ cho đấu trường thường. |
| P5-2 | Cược và đấu trường dùng chung bản sao `Arena.opponent/2` (cánh gộp vào máu / công). | Một chỗ tính sức mạnh PvP. |
| P5-3 | "Online" = Session còn chạy (như tổ đội, giao dịch, bạn bè hiện có); danh sách online của quản trị thì chỉ tính người còn mở tab. | Giữ cách hiện có; quản trị cần biết ai thật sự đang chơi. |
| P5-4 | Nhường bang chủ khi bang đã đủ 2 phó và người nhận là thành viên thường: bang chủ cũ thành **thành viên**. | Không vượt giới hạn phó bang. |
| P5-5 | Chiến bang chỉ tính trận **người thách đấu thắng** (không tính khi bản sao thắng). Tuyên chiến bằng ký hiệu bang. | Điểm do người chơi tự đánh; ký hiệu ngắn, dễ gõ. |
| P5-6 | Bảng xếp hạng: cache 60 s cho mọi bảng (cả bảng cũ), top 10 bảng cũ giữ nguyên; `me` (hạng chung) giữ cho client cũ, thêm `me_rank`. | Lợi nhất khi đông người; không phá client đang mở. |
| P5-7 | Lời mời tổ đội hết hạn mà tổ đội chỉ có người mời (lập lúc mời) và không còn lời mời nào: tổ đội tan. | Không để tổ đội một người treo mãi. |
| P5-8 | Giao dịch: "đi xa" kiểm lúc mời và lúc chốt (cùng bản đồ, ≤ 8 ô); không theo dõi từng bước đi. Đổi bản đồ / vào trận thì hủy ngay. | Đủ chặn giao dịch từ xa mà không tốn công theo dõi vị trí. |
| P5-9 | "Xóa thư đã đọc" chỉ xóa thư đã mở (đã nhận quà); thư chưa mở không xóa được. | Không lỡ tay mất quà. |

## Phase 8 — Giao diện, hướng dẫn người chơi (2026-10-04)

| # | Quyết định | Lý do |
|---|---|---|
| P8-1 | Thông báo (L2) chỉ lưu ở **trình duyệt** (`localStorage` theo tài khoản, 50 tin), không thêm bảng database / giao thức. | Không đụng schema / protocol; mất tin cũ khi đổi máy là chấp nhận được (tin quan trọng đã có ở Hộp thư). |
| P8-2 | Tin giữ lại: lên cấp, ép thất bại hoặc thành công từ +7, ghép (máy Hỗn Nguyên), thư mới, lời mời (tổ đội, giao dịch, cược), kết quả cược, tin hệ thống gửi riêng. Tin vặt ("Đã gửi lời mời") không lưu. | Bảng gọn, chỉ những gì người chơi muốn xem lại. |
| P8-3 | Hiệu ứng lớn (M11) chỉ bằng CSS (không canvas, không ảnh mới); "giảm chuyển động" thì chỉ hiện rồi mờ đi. | Nhẹ, không cần asset. |
| P8-4 | `USER_GUIDE.md` dùng ảnh e2e có sẵn (thêm `e2e-pk.png`, `e2e-wardrobe.png`; `run.mjs` chép lại khi `HL_SHOTS_DOCS=1`). | Ảnh luôn khớp giao diện hiện tại. |

## Phase 7 — Golden Invasion (2026-10-04)

| # | Quyết định | Lý do |
|---|---|---|
| P7-1 | Quái vàng ở bản đồ đầu mỗi vùng (6 bản đồ × 4 con), loài ngẫu nhiên của vùng; số trong `RULES.invasion.maps`. | Ai cũng có chỗ đánh hợp cấp; anh đổi bản đồ / số lượng trong data. |
| P7-2 | Quái vàng mạnh ×1,5 (như quái Bóng Đêm), trùm vàng giữ sức trùm vùng; thưởng ×5 không đổi sức mạnh. | Thưởng lớn thì phải khó hơn một chút, nhưng người cùng cấp vẫn đánh được. |
| P7-3 | Hết giờ: quái vàng chưa ai đánh biến mất, trận đang đánh thì đánh nốt (vẫn nhận thưởng). | Không cắt ngang trận của người chơi. |
| P7-4 | Bản đồ nào hết chỗ trống để thả quái thì coi như xong; mọi bản đồ xong (đã hạ trùm vàng) thì kết thúc sớm. | Không kẹt sự kiện. |
| P7-5 | Trạng thái sự kiện không lưu database; server khởi động lại thì đợt đang chạy mất, đợi lịch tiếp theo. | Sự kiện ngắn (15 phút); không thêm bảng. |

## Phase 9 — Menu, chat trong bản đồ, màn vừa khít (2026-10-04)

| # | Quyết định | Lý do |
|---|---|---|
| P9-1 | Menu tách tab Khác thành: Nhiệm vụ, Hành trình (hồi máu, hành trình trùm, trùm thế giới sắp tới), Đấu trường, Xếp hạng, Bang hội, Thành tựu, Thú cưng, Kỹ năng, Sổ quái, Cài đặt (+ Quản trị cho admin). Dùng lại đúng nội dung cũ. | Không mất tính năng nào, ít rủi ro. |
| P9-2 | Nút 🗺 trên dock tạm hiện thông báo "sắp có"; bảng chọn bản đồ làm ở Phase 10 cùng 20 bản đồ mới. Phím M giữ "về bản đồ" tới Phase 10. | Đúng thứ tự anh chốt (9-E). |
| P9-3 | Nút 💬 hiện cả trên máy tính (cùng chỗ góc dưới phải); máy tính có thêm Enter / Esc. Trong trận đánh không hiện khung chat (màn trận đánh riêng). | Một cách dùng cho mọi máy; trận đánh cần chỗ cho nút hành động. |
| P9-4 | Hộp thoại trên bản đồ (thông tin người chơi, lời mời…) nằm trên khung chat. | e2e phát hiện khung chat đang mở che nút trong hộp thoại. |

## Phase 10 — Hai ngôn ngữ (2026-10-04)

| # | Quyết định | Lý do |
|---|---|---|
| P10-1 | Dịch trên trình duyệt bằng từ điển mẫu câu (`i18n.js` + `en.json`) thay vì gắn khóa vào từng câu trong code / server. | Anh muốn làm cả A + B + C nhưng ít credit: một cơ chế phủ giao diện, dữ liệu game và tin server; không đổi giao thức / schema. |
| P10-2 | Ngôn ngữ lưu ở trình duyệt, không lưu theo tài khoản. | Không thêm cột database; đổi máy thì chọn lại một lần. |
| P10-3 | Bản dịch đầu do máy dịch theo bảng thuật ngữ (Kiếm Sĩ = Dark Knight, Ngọc Ước Nguyện = Jewel of Bless…), kiểm tự động giữ đúng {n}. | Nhanh; anh / người chơi góp ý thì sửa thẳng `en.json`. |

## Phase 11 (2026-10-09)
- **P11-1** Sáng / Tối / Tự động chỉ đổi độ tối khi vẽ bản đồ (lưu `hl-theme` ở trình duyệt); luật ngày đêm (quái hiếm ban đêm) vẫn theo giờ server, biểu tượng giờ trên bản đồ vẫn là giờ thật.
- **P11-2** Chat ở góc bản đồ: mỗi tin hiện 5 giây kể từ lúc tới; lịch sử nạp lúc vào game không hiện ở góc (bấm 💬 để xem). `/d` chỉ xóa trên máy mình.
- **P11-3** Gặp trùm: client luôn gửi `move` kèm `confirm: true` nên vào trận ngay; server giữ nguyên giao thức (`confirm: "boss"` vẫn có cho client cũ).
- **P11-4** Quà cho mọi người kèm trang bị: khóa `items` `"gear:<mẫu>:<độ hiếm>:<+N>"` trong thư (không đổi schema `mails`); độ hiếm 0 = đồ thường, 1..3 = đồ hiếm chỉ số `1 + cấp/6` cho 1..3 chỉ số đầu (như lệnh `give_gear` không nhập chỉ số); mỗi thư tối đa 100 món mỗi loại; túi đồ hiếm không đủ chỗ thì không mở được thư (không tự bán).
- **P11-5** Bỏ form "Gửi quà" riêng ở thẻ tra cứu người chơi (trùng Chỉnh nhân vật); lệnh `gift` với `uid` trên server vẫn giữ.

## Phase 12 (2026-10-09) — MP
- **P12-1** MP kỹ năng: `mp` gốc ở `classes.json` (kỹ năng mạnh / mở muộn gốc cao hơn, đã phản ánh sát thương) × (1 + `RULES.combat.skill_mp_per_level` (0.04) × (cấp − 1)). Không thêm cấp kỹ năng (game chưa có).
- **P12-2** Hồi MP mỗi lượt: `mp_regen` (0.03) × MP tối đa + `mp_regen_ene` (0.1) × Năng lượng (cả đồ cộng), tối thiểu 1 (câu 12-A).
- **P12-3** Bình máu `heal` → `heal_pct` 0.2 / 0.4 / 0.7; thêm `mana_s/m/l` (`mana_pct` cùng mức), slot `potion`, Bà Lang bán. Giá mua bình × (1 + `RULES.shop.potion_price_per_level` (0.1) × (cấp − 1)); giá bán lại theo giá gốc (không lời khi mua rồi bán).
- **P12-4** Trong trận thêm lệnh `mana` (như `potion`, mất một lượt, chọn bình nhỏ nhất đủ đầy). Phím Q vẫn chỉ uống bình máu.

## Phase 13 (2026-10-09) — người chơi và quái trên bản đồ
- **P13-1** Máu quái: Session gửi `MapServer.hp/3` (phần trăm) sau mỗi lệnh khi đang đánh quái của bản đồ chung; snapshot có `hp` (100 khi chưa ai đánh), nhả quái thì về 100. Tần suất theo lượt đánh (không thêm luồng riêng), gộp vào lần phát bản đồ ~20 lần/giây sẵn có.
- **P13-2** Không vẽ người khác (cả thú cưng, bong bóng chat của họ) trên bản đồ; `playerAt` luôn null. Dock thêm **👫 Quanh đây** (số đỏ = số người khác cùng bản đồ) → danh sách → hồ sơ.
- **P13-3** Hồ sơ dùng lại lệnh `inspect` (thêm `me`, `profile`, `HacLong.Profile`): mình và người khác cùng bố cục; người khác có nút hành động (tổ đội, thăm nhà, giao dịch, kết bạn, thách đấu, cược đấu, chặn chat). "Lần cuối online" = lần ghi nhân vật gần nhất (`characters.updated_at`). Vàng người khác hiện như ảnh mẫu.
- **P13-4** Tab Nhân vật: chỉ số hiện `+N` từ đồ hiếm; tấn công / phòng thủ / máu hiện `+N%` từ thú cưng + món ăn (`view.extra`).

## Phase 14 (2026-10-09) — Thư viện
- **P14-1** `HacLong.Library` sinh danh sách bản đồ (bỏ Nhà riêng), quái (cả trùm vùng; chỉ số theo `Engine.make_monster/2`, vàng lấy trung bình không may rủi), vật phẩm (nguồn: NPC bán, pha chế / nấu, thưởng nhiệm vụ, trùm rơi, bình quái rơi theo `RULES.loot.potions`, ngọc theo `JEWELS`, thu thập) từ dữ liệu game, giữ trong `:persistent_term`, gửi một lần trong `GAME_DATA.LIBRARY`.
- **P14-2** Tìm theo tên không cần dấu (`HLLogic.fold`), cả tên đã dịch khi chơi tiếng Anh; gõ chỉ vẽ lại phần kết quả. Tên trong chi tiết là liên kết sang mục tương ứng. Đồ hiếm chỉ số ngẫu nhiên không liệt kê riêng (là biến thể của vũ khí / giáp / khiên).

## Phase 15a (2026-10-09) — 50 bản đồ phụ, chọn bản đồ
- **P15a-1** Anh yêu cầu **50** bản đồ (thay 20 trong 9-B). 10 nhóm chủ đề × 5 bản đồ (`side_01`…`side_50`), bản đồ i có quái cấp i, i+1, i+2 (52 loài trong `priv/game_data/side.json`, chỉ số theo `RULES.monster` như vùng cũ). Không trùm, không khóa theo vùng, không liên quan Hắc Long.
- **P15a-2** Cổng: trong nhóm nối tiếp trái ↔ phải; bản đồ đầu nhóm có cổng (ô `O`, mép phải) từ một bản đồ có sẵn gần cấp: Rừng Mê 1, Rừng Mê 2, Trại Goblin 1, 2, Nghĩa Địa Cổ 2, Núi Khổng Lồ 1, 2, Đầm Lầy Rồng 2, Hang Hắc Long 1, 2. Bản đồ sinh bằng `scripts/gen_side_maps.py` (hạt giống cố định; ô không tới được từ cổng bị lấp).
- **P15a-3** Hình 52 loài quái lấy từ Dungeon Crawl Stone Soup tiles (CC0, `github.com/crawl/tiles`, bản Nov-2015) bằng `scripts/side_monsters.py`, ghi `CREDITS.md`. Nền ô / trận dùng lại hình vùng cũ (`theme`).
- **P15a-4** Chọn bản đồ (phím **M**, nút dock **Chọn map**): mọi bản đồ (trừ Tháp) xếp theo cấp quái thấp nhất; giá `RULES.travel` = 20 + 4 × cấp (Làng, Nhà miễn phí; Tế Đàn không quái = 20). Tới được: Làng, Nhà, bản đồ vùng đã mở, bản đồ phụ đã đi qua cổng (`characters.visited`, migration mới). Nhật ký vàng lý do `TRAVEL`. Đá dịch chuyển giữ nguyên.
- **P15a-5** Trận ở bản đồ phụ: `battle.zone = nil`, `battle.place` / `battle.theme` cho nền; không tính vào việc hằng ngày "hạ N quái ở vùng X". Golden Invasion không vào bản đồ phụ.

## Phase 16 (2026-10-09) — người chơi AI
- **P16-1** 20 bot (`RULES.bots.count`; biến môi trường `HL_BOTS` đổi số, `0` là tắt; test luôn tắt). Mỗi bot là tài khoản thật `bot_01`… với `users.role = "bot"` (migration nới ràng buộc `users_role`), mật khẩu ngẫu nhiên, nhân vật thật trong database. Lớp xoay vòng Kiếm Sĩ / Phù Thủy / Tiên Nữ / Đấu Sĩ; tên tiếng Việt (trùng tên người thật thì thêm số).
- **P16-2** `HacLong.Bots.Bot` gắn vào `Session` như một tab đang mở và gửi lệnh qua `Session.command/2` → cùng luật, cùng giới hạn tốc độ, cùng lưu database / nhật ký vàng như người thật. Quyết định trong `HacLong.Bots.Brain` (hàm thuần, có test): đánh (kỹ năng mạnh nhất, máu < 35 % uống bình, thiếu MP uống mana), cộng điểm vào chỉ số chính, mặc đồ rơi tốt hơn, máu < 45 % uống bình hoặc về Nhà uống giếng, chọn bản đồ hợp cấp (cấp quái cao nhất ≤ cấp + 1; mỗi bot chọn một trong 3 bản đồ tốt nhất để không dồn một chỗ), dịch chuyển nếu đủ gấp đôi giá, không thì đi bộ qua cổng theo đường ngắn nhất (mở dần bản đồ phụ), săn quái gần nhất.
- **P16-3** Không đánh dấu là bot. Không lên bảng xếp hạng và không chiếm hạng người thật (`Leaderboard` bỏ `role = "bot"`). Giao dịch với bot bị từ chối ("Người này không nhận giao dịch."). Lời mời cược đấu: bot từ chối sau vài giây. Thách đấu (đấu trường, PK với bản sao) đánh được bot như người thường.
- **P16-5** Đủ cấp (cấp trùm + 1) thì bot vào phòng trùm vùng chưa hạ để mở vùng mới (nên lên tiếp được các nhóm bản đồ phụ có cổng trong vùng sau).
- **P16-4** Khoảng 4 phút mỗi bot nói một câu ngắn trong kênh thế giới (danh sách câu cố định). Bot không mua đồ ở NPC, không làm nhiệm vụ / việc hằng ngày, không vào tháp (để sau nếu cần).

## Cân bằng đầu game (2026-10-09)
- **B-1** Máu quái `RULES.monster.hp.base` 20 → **170**: trước đó nhân vật mới (đánh 70–110) hạ quái cấp 1–5 một đòn ở cả 4 lớp. Giờ quái cùng cấp cần ~2–3 đòn ở cấp 1–10 (chưa tính vũ khí), tăng dần ~3–7 đòn ở cấp 30–50 tùy lớp. Trùm vùng cũng trâu hơn tương ứng (Sói Xám 474 → 834 máu). Mô phỏng 4 lớp × 5 lượt: vẫn thắng Hắc Long 5/5, số trận (~390) và số lần chết gần như không đổi. Kinh nghiệm / vàng mỗi quái không đổi.
- **B-2** (theo yêu cầu) Thách đấu ở đấu trường: **gục ngã tính như chết thường** — mất `death_gold_loss` vàng, tăng số lần chết, máu còn `death_hp`, về Nhà. Bỏ chạy vẫn tính thua điểm Elo nhưng không mất vàng / máu như trước trận.
- **B-3** Sửa lỗi: quái bản đồ phụ trên bản đồ luôn hiện "cấp 1" vì client chỉ tra cấp quái vùng; giờ tra thêm `LIBRARY.monsters`.

## Đồ sát thay PK cược vàng (2026-10-10, theo yêu cầu)
- **P18-1** PK kiểu đồ sát: không cần bên kia đồng ý. Bấm **🗡 Đồ sát** trong hồ sơ / bảng người chơi → cả hai vào trận ngay (`HacLong.Slay`, kênh `slay`). Đối thủ hiện như quái là bản sao chỉ số, máu là máu thật (không quy đổi cánh như đấu trường).
- **P18-2** Luân phiên lượt, người tấn công đi trước, mỗi lượt `RULES.slay.turn_s` = 10 giây; quá giờ server đánh thường thay. Đánh thay thất bại `RULES.slay.max_timeouts` = 3 lần liền (Session không chạy) thì người đó thua. Engine chạy ở chế độ `live` (đối thủ không tự đánh trả; độc / choáng không tác dụng chéo giữa hai người).
- **P18-3** Điều kiện: cả hai online, cùng bản đồ chung (không phải tháp), ngoài vùng an toàn `RULES.slay.safe_maps` (Làng, Nhà), cả hai từ cấp `RULES.slay.min_level` = 10, không ai đang đánh. Bot bị đánh được như người (đánh thay khi hết giờ).
- **P18-4** Hết máu hoặc **bỏ chạy** = gục ngã như chết thường (mất `death_gold_loss` vàng, máu còn `death_hp`, về Nhà, +1 lần chết). Số vàng mất chuyển cho người thắng. Chốt trận giữ cả hai Session rồi ghi hai nhân vật + một dòng `pk_matches` (a = người tấn công, `wager` = vàng chuyển) trong một transaction, nhật ký vàng lý do `SLAY`.
- **P18-5** PK cược vàng cũ: mời cược qua kênh trả lỗi (đã thay); lịch sử `pk_matches` và số thắng/thua trong hồ sơ dùng chung cho đồ sát. Thách đấu đấu trường giữ nguyên.

## Đồ sát: chống lạm dụng (2026-10-10, theo yêu cầu)
- **P19-1** Người vừa gục trong đồ sát được **bảo vệ** `RULES.slay.protect_s` = 120 giây (không bị đồ sát). Tự đi đồ sát người khác thì mất bảo vệ ngay.
- **P19-2** Một người đồ sát cùng một người tối đa `RULES.slay.per_target_hour` = 3 lần trong 60 phút gần nhất (tính lúc mở trận, kể cả trận thua / bỏ chạy). Chống "nuôi" vàng bằng nick phụ.
- **P19-3** **Tên đỏ:** người tấn công thắng một người không tên đỏ thì đỏ tên `RULES.slay.red_s` = 30 phút, cộng dồn mỗi lần. Người tên đỏ gục trong đồ sát mất vàng gấp `RULES.slay.red_gold_mult` = 2 lần (20%), toàn bộ về tay người thắng. Hạ người tên đỏ, hoặc người bị đánh thắng lại, thì không bị đỏ tên. Tên đỏ hiện màu đỏ đậm trong Quanh đây và hồ sơ (kèm số phút còn lại); hồ sơ cũng hiện thời gian bảo vệ.
- **P19-4** Mỗi trận xong báo kênh thế giới: "X đã hạ Y ở <bản đồ>." hoặc "Y bỏ chạy khỏi X ở <bản đồ>."
- **P19-5** Bảo vệ / tên đỏ / số lần đánh giữ trong bộ nhớ (`HacLong.Slay`, bảng ETS `:slay_marks`), khởi động lại server thì xóa. Chấp nhận vì thời hạn ngắn (≤ 30 phút); cần bền hơn thì thêm cột vào `characters`.
- **P19-6** Đồng hồ lượt đồ sát: server gửi số mili giây còn lại (`view.slayLeft`, tính lúc gửi), client cộng vào đồng hồ máy mình nên máy lệch giờ vẫn đếm đúng. Bot đang đồ sát mà chưa tới lượt thì chờ (không gửi lệnh), hỏi lại mỗi ~1 giây; tới lượt thì đánh / uống bình như đánh quái.

## Phase 17 — Tiến Lên Miền Nam (2026-10-10, theo yêu cầu)
Nguồn: repo `biennguyen94/Tien-Len-Mien-Nam` @ `c1f3f07` (của anh, Elixir/Phoenix). Luật là `docs/RULES.md` T1–T26 của repo đó, giữ nguyên.
- **P17-1** Port gần nguyên văn, đổi namespace `TienLen` → `HacLong.TienLen` (`lib/hac_long/tien_len/`):
  - REUSE: `Card`, `Deck`, `Combination`, `Rules`, `InstantWin`, `Payout`, `Bot`, `Hint`, `Lobby`, `Commentary`, `BotTalk`, `Throws`, `Replay` cùng test của chúng.
  - ADAPT `Game`: `Enum.sum_by` → `map |> sum` (Elixir 1.17).
  - ADAPT `Room`: cược tối đa `RULES.tienlen.stake_max`; ván có bot vẫn ra kết quả để lưu xem lại.
  - ADAPT `RoomServer`: số phòng tối đa `RULES.tienlen.max_rooms`; module tiền / ghi ván cắm từ cấu hình `:tienlen_economy`, `:tienlen_recorder`; bỏ lì xì Tết; khớp `HacLong.RateLimit`.
  - REWRITE `Chat` (biểu cảm, câu nhanh, chuẩn hóa) và `Text` (lấy từ `TienLenWeb.Text`, "coin" → "vàng").
- **P17-2** Tiền là **vàng Hắc Long** (`HacLong.TienLen.Gold`, thay `TienLen.Economy`):
  - Cách trả giữ nguyên luật T20–T25: cược S, cần ≥ 10×S vàng để được chia bài (từ 2026-10-11: 2×S, `RULES.tienlen.min_balance_mult`); tiền hạng, chặt heo / chặt chồng, thối heo, tới trắng; thiếu vàng thì trả tối đa số đang có, chia theo tỉ lệ.
  - Mọi lần trả giữ Session của người liên quan (theo thứ tự id) rồi ghi nhân vật + khóa trả (`tienlen_settlements`) trong một transaction, nhật ký vàng lý do `TIENLEN`.
  - Ném đồ trừ vàng, lý do `TIENLEN_THROW`.
  - Không có thưởng ngày / cứu trợ / chuyển xu riêng.
- **P17-3** Bàn có bot thì cược = 0 (giữ B1 của repo gốc), nên không cày vàng từ bot. Khác repo gốc: ván có bot **vẫn được lưu** để xem lại (Hắc Long không có bảng xếp hạng Tiến Lên); chỉ người thật có tên trong `player_ids`.
- **P17-4** Không port: tài khoản, bảng xếp hạng Tiến Lên, nhiệm vụ / mùa giải, bạn bè / mời / chat sảnh / chat riêng (Hắc Long đã có), cửa hàng mặt bài, tướng xấu hổ, sự kiện Tết / Trung thu, trang quản trị riêng. Có thể thêm sau nếu anh muốn.
- **P17-5** Kênh: thêm sự kiện `tl` vào kênh `game` (`HacLongWeb.TienLenHandler`) thay các LiveView. Kênh là tiến trình được phòng theo dõi: đóng hết tab thì 20 giây sau bị loại khỏi ván (T15).

## Chọn bản đồ (2026-10-10, theo yêu cầu)
- **P15-T1** Bảng chọn bản đồ: **đủ cấp + đủ vàng** là đi được. Đủ cấp = cấp nhân vật ≥ cấp quái thấp nhất của bản đồ (`World.min_level/1`; bản đồ không có quái thì luôn được). Bỏ điều kiện "vùng đã mở" (bản đồ thường) và "đã đi qua cổng" (bản đồ phụ). Giá giữ nguyên `RULES.travel`. Tháp và bản đồ riêng vẫn không dịch chuyển tới được.
- **B-4** (theo yêu cầu, 2026-10-10) **Bỏ khóa vùng bằng trùm.** Vùng `zi` mở khi cấp nhân vật ≥ cấp quái thấp nhất của vùng (`Engine.zone_level/1`): cổng, đá dịch chuyển, chọn bản đồ, đánh quái, việc hằng ngày, nhiệm vụ, bot đều theo đó. Trùm thành thử thách có thưởng (`RULES.boss_rewards`):
  - hạ lần đầu: chắc chắn một món đồ Hiếm (75%) / Sử Thi (25%) **đúng lớp** cấp ≤ cấp trùm, cộng món rơi riêng cũ (Khiên Rồng, Bảo vật) nếu có;
  - thành tựu + danh hiệu "Diệt <trùm>" cho 5 trùm vùng (Hắc Long giữ "Kẻ Diệt Rồng");
  - lần đầu mỗi ngày hạ một trùm vùng: vùng 1–3 +1 Ngọc Ước Nguyện, vùng 4–6 +1 Ngọc Tâm Linh (ghi trong `daily.bosses`).
  - Mô phỏng 4 lớp × 5 lượt sau thay đổi: vẫn thắng 5/5, Hắc Long ở cấp ~35, số trận gần như cũ; ngọc thu được ~gấp đôi.
- **P17-6** Mời bạn vào bàn Tiến Lên: chỉ bạn bè (dùng tin riêng sẵn có), nội dung `🃏 Mời bạn vào bàn Tiến Lên [mã] · …`; client nhận ra `[mã]` để hiện nút Vào bàn (thông báo nổi + trong khung tin riêng). Tối đa 10 lời mời / phút.

## Bản tiếng Anh cho các phần mới (2026-10-10)
- **I-1** Dịch 347 câu mới (Tiến Lên, đồ sát, thưởng trùm, chọn bản đồ) và 50 tên bản đồ phụ vào `priv/static/i18n/en.json`. Tên trò chơi ở bản tiếng Anh viết "Tien Len" (không dấu).
- **I-2** `scripts/i18n_extract.py` coi `{a}` `{b}` `{n}` (chỗ trống câu bình luận Tiến Lên) là chỗ nội suy, đánh số `{0}`… như tên / số; `i18n.js` thử khớp mẫu dự phòng cho cả khối chữ trước khi tách câu (chỗ trống không được nuốt qua ranh giới câu), nên câu mẫu nhiều câu ("Ối dồi ôi! {0} vừa chặt…") dịch được.
- **I-3** Thông báo kênh thế giới khi đồ sát đổi thành "🗡 A đã đồ sát B ở X." (rõ nghĩa hơn "đã hạ", và đủ chữ cố định để khớp mẫu dịch).

## Phase 15b — Đồ từ Item.txt, M1 (2026-10-10, anh chốt)
- **I15b-1** Nguồn `afrokick/muonlinejs` (`tools/Item.txt`, `public/items`); anh bỏ qua license. Vẫn giữ CLAUDE.md §7 phần "không vào git / Docker": file và hình ở `assets_src/private/`, hình chép ra `priv/static/assets/mu_items/` (thư mục `items/` cũ là hình tự vẽ, vẫn trong git); CI `private-assets` kiểm cả đường dẫn Hắc Long.
- **I15b-2** Chọn theo bậc (114 món: vũ khí 7 bậc × 3 dòng lớp, khiên 3, bộ giáp 5 món × 6 bậc × 3 dòng lớp; Đấu Sĩ dùng chung đồ DK, không mũ). Yêu cầu chỉ số × 0,35; bậc 1 không đòi chỉ số.
- **I15b-3** Item.txt quyết định món gì (tên, hình, lớp, tỉ lệ), Hắc Long quyết định mạnh cỡ nào (đường cong công / thủ / giá cũ) để giữ cân bằng. Mọi hệ số trong `priv/game_data/item_pick.json`, giải thích từng khóa ở `docs/ITEMS_PHASE15B.md` §3.
- **I15b-4** Lệnh tải thư mục hình tự động bị chặn trong môi trường cloud (clone repo ngoài) → hình chép tay vào `assets_src/private/item_icons/`.
- **I15b-5 (M2)** Đồ dựng ra ghi file riêng `items_mu.json` (`ITEMS_MU`), không sửa `items.json` / `shop.json` / bản đồ: `Data` gộp vào `ITEMS`, gắn `legacy` cho đồ cũ trong `ITEM_PICK.legacy`, tự thay đồ cũ trong cửa hàng và hàng Thợ Rèn. Đồ cũ vẫn còn định nghĩa (thư, chợ, Tủ Đồ cũ vẫn mở được) và được đổi khi nạp nhân vật.
- **I15b-6** Giá món trong bộ giáp chia theo tỉ lệ thủ (`piece_weight: "def"`): đủ bộ = giá giáp cũ cùng bậc, để giữ kinh tế (trọng số tay làm tổng bộ đắt gấp 3,4).
- **I15b-7** Đồ rơi từ quái hợp lớp người hạ (`RULES.loot.gear_own_class: true`) để tốc độ có đồ như trước; đổi `false` là kiểu MU (rơi đồ mọi lớp).
- **I15b-8** Yêu cầu chỉ số so với chỉ số gốc đã cộng điểm (không tính đồ), chỉ kiểm lúc mặc.
- **I15b-9 (M3)** Hình đồ lấy từ repo riêng của anh `biennguyen94/mmo-rpg-game-items` (`item_ref/items`), chỉ chép hình của đồ đang có trong game, cắt viền trong suốt bằng ImageMagick lúc `mix hac_long.icons`. Cánh, Thánh Kiếm, Khiên Vảy Rồng mượn hình MU qua `ITEM_PICK.refs` (đổi được).
- **I15c-1** Bậc 7–8: Kiếm Sĩ / Đấu Sĩ Hắc Long, Phượng Hoàng Đen; Phù Thủy Đại Linh Hồn, Hồn Bóng Tối; Tiên Nữ Thần Thánh, Linh Hồn Đỏ (bộ "bậc 2" của MU, dùng tên đẹp; số theo đường cong Hắc Long).
- **I15c-2** Nhẫn / dây chuyền: chỉ số cho tay (Item.txt nhóm 13 không có số dùng được), chỉ rơi, không bán.
- **I15c-3** Thưởng đủ bộ chỉ tính từ bậc 2 (`min_tier`), để bộ khởi đầu không cho thưởng sẵn.
- **I15c-4** Excellent chỉ cho đồ rơi từ quái và đồ trùm lần đầu; dòng lấy từ dòng Excellent MU nhưng rút gọn còn 7 dòng game tính được.
- **I15d-1** Kỹ năng trên vũ khí = chiêu +10 % sát thương (anh chốt, phương án a; không giảm hồi chiêu, không mở chiêu sớm).
- **I15d-2** May mắn trên giáp / trang sức chỉ cộng tỉ lệ ép ngọc, không cộng chí mạng (anh chốt, như MU).
- **I15d-3** May mắn / Kỹ năng chỉ có ở đồ rơi từ quái và đồ trùm lần đầu (như Excellent); tỉ lệ ép có May mắn tối đa 95 %.
- **I15e-1** Cánh cấp 3 dùng hình gốc 12/36–12/39 theo Item.txt bản afrokick (Đấu Sĩ lấy Wings of Hurricane vì bản này không có Wing of Ruin); số theo đường cong cánh cấp 1 → 2 (10 → 18 → 25 %).
- **I15e-2** Dòng cánh chỉ bốc khi ghép ở Máy Hỗn Nguyên (cánh tặng không có dòng, trừ khi quản trị ghi `wopt`); cánh cấp 2 cũ giữ nguyên, không bù dòng.
- **I15e-3** `ignore_def` áp lên phòng thủ đối thủ sau hệ số kỹ năng (`def_mult`), trước công thức sát thương.
- **I15f-1** Mục 4 (Máy Chaos): thêm Pha Excellent / Pha May mắn (biến đổi chính món đồ) thay vì đồ Chaos mới; thất bại mất món như mọi công thức của máy. Trái Cây hoãn vì cần đổi schema (OPEN_QUESTIONS 15f-A).
- **I15g-1** Bộ Thần (mục 6): không tạo bộ mới mà cho mọi bộ giáp sẵn có một bản Thần (rơi hiếm); thưởng theo số món Thần cùng bộ, cộng dồn với thưởng đủ bộ thường. Vũ khí / khiên / trang sức không có bản Thần.
- **I15h-1** Chợ (mục 7): chợ và giao dịch trực tiếp đã có từ trước nên mục này là sửa lỗi mất dòng đồ khi rao bán + lọc / sắp xếp ở client; không thêm đấu giá / đặt mua (sẽ đổi schema).
- **I15i-1** Báo cáo cân bằng (mục 8) tính thẳng từ dữ liệu (không đo trên server thật) + simulator; ghi vào `docs/BALANCE_REPORT.md`, chỉ nêu nhận xét, không tự đổi số gameplay.
- **E18-1** Quảng Trường Quỷ chạy như một chế độ của Tháp Vô Tận (bản đồ riêng, trạng thái trong cột `tower`) để không đổi schema; một người một lượt (không đánh chung), NPC dùng lại Người Gác Tháp.
- **E18-2** Mở lệch Golden Invasion 1 giờ (1h, 3h … 23h), 10 phút cho vào, lượt 5 phút; hết giờ được kiểm khi người chơi bước tiếp (không có hẹn giờ riêng mỗi lượt).
- **E18-3** Thưởng tính một lần lúc kết thúc theo điểm; lượt đủ ≈ giá vé về vàng, lãi là ngọc + món đồ khi qua hết đợt; kinh nghiệm ≈ 1 cấp / lượt đủ.
- **E18-4** Bảng xếp hạng ngày giữ trong bộ nhớ (không thêm bảng DB); thưởng top 3 gửi thư lúc 0h05.
- **E18-5** Lâu Đài Máu là một người một lượt (như Quảng Trường), ba bước quân canh → cổng → trùm; mở lệch 30 phút (0h30, 2h30 …) để không trùng Quảng Trường / Golden Invasion.
- **E18-6** Lượt thắng ≈ giá vé về vàng; lãi là Lông Vũ Kền Kền + 2 ngọc + kinh nghiệm. Không xong thì thưởng theo quân canh đã hạ, không có lông vũ.
- **E18-7** Cổng / trùm hiện ở ô trống gần cầu thang lên nhưng không trùng ô người chơi đang đứng (đứng sẵn trên ô quái thì không bước vào đánh được).

## Bot nghỉ sau khi gục (2026-10-11, anh chốt)

- **B-1** Bot gục (bị đồ sát, thua quái…) về Nhà rồi đứng nghỉ ngẫu nhiên 30–90 giây (`RULES.bots.rest_after_death_s`,
  anh chọn) mới đi luyện tiếp. Trước đây bot dịch chuyển về chỗ cũ chỉ sau ~4 giây nên trông như không chết. Người chơi
  thật không đổi gì (đồ sát người chơi đã về Nhà, rời bản đồ đúng). Bot nhận ra mình vừa gục qua số lần chết (`deaths`)
  tăng; khởi động lại server thì không nghỉ (chấp nhận).
- **B-2** Hình nhân vật: giáp bậc 7–8 và vũ khí bậc 8 (Rìu Lưỡi Liềm) chưa có hình đồ cũ cùng bậc nên trước đây nhân vật hiện
  không giáp / tay không. `ItemBuild.look/3` cho bậc cao hơn danh sách `ITEM_PICK.legacy` mượn món cũ bậc cao nhất (giáp tấm,
  rìu đôi). Mũ / quần / găng / giày vẫn chưa vẽ lên nhân vật (cần thêm hình CC0, chưa làm).
- **B-3** Hình gốc MU cho món dùng hằng ngày (`ITEM_PICK.refs`): bình máu 14/1–3, bình mana 14/4–6, Ngọc Ước Nguyện 14/13, Linh Hồn
  14/14, Sinh Mệnh 14/16, Hỗn Nguyên 12/15, Vé Quảng Trường 14/19 (Invitation of Devil Square), Vé Lâu Đài 13/18 (Invisibility
  Cloak — vé Blood Castle của MU), Lông Vũ Kền Kền 13/53 (Condor's Feathers), Quả Lộc 14/0 (Apple). Chỉ đổi hình, không đổi
  gameplay; máy chủ chưa chép hình mới thì vẫn dùng icon cũ.
- **B-4** (anh chốt) Món phụ (`alt`, `ITEM_PICK.weapons_alt / shields_alt / sets_alt`): cùng công / thủ / cấp / giá với món chính
  cùng bậc, chỉ khác tên, hình, yêu cầu chỉ số (lấy từ Item.txt). Chỉ rơi: không bán, không làm đồ khởi đầu, không làm đồ thay
  đồ cũ. Đồ rơi lấy mọi món thuộc 2 mức cấp cao nhất (trước: 2 món) để món phụ không đẩy bậc dưới ra. Khiên 3 → 8 bậc. Đấu Sĩ
  có bộ riêng MU (Quạ Bão, Dũng Mãnh, Ưng Sấm, Cuồng Phong) làm bộ phụ, không mũ. Đổi tên để không trùng đồ cũ: 2/0 Chùy Tròn
  (đồ cũ có Chùy Gai), 6/7 Khiên Đinh (Khiên Gai), 1/5 Rìu Chiến Binh (Rìu Chiến).
- **B-5** (anh chốt phương án B) Đồ đặc biệt từ quái thường (`rules.json`): tỉ lệ rơi đồ `loot.gear_chance.normal` 4% → 6%,
  Excellent `excellent.chance.normal` 4% → 10%, Thần `ancient.chance.normal` 1% → 5%. Quái thường giờ ~1/167 con ra Excellent,
  ~1/775 con ra Thần. Tinh anh / đêm / trùm giữ nguyên số; tỉ lệ trên mỗi món đã rơi của quái thường có chỗ cao hơn, nhưng tính
  trên mỗi con hạ thì tinh anh / đêm / trùm vẫn cao hơn nhiều vì rơi đồ thường xuyên hơn (50% / 25% / 35% so với 6%).
- **B-6** (anh chốt) Tên ngọc theo bản MU Việt: Jewel of Bless = **Ngọc Ước Nguyện** (trước: Phúc Lành), Jewel of Soul =
  **Ngọc Tâm Linh** (trước: Linh Hồn). Ngọc Sinh Mệnh (Life) và Ngọc Hỗn Nguyên (Chaos) giữ nguyên. Chỉ đổi tên hiển thị, id
  (`jewel_bless`, `jewel_soul`) và luật ép không đổi; bộ giáp / cánh / kỹ năng tên "Linh Hồn" giữ nguyên.
- **B-7** (anh yêu cầu) Máy Hỗn Nguyên ghép cánh (`wing1`, `wing2`, `wing3`): người chơi **chọn lớp** của cánh ra (mặc định lớp
  mình) để ghép cánh lớp khác đem bán ở chợ / tặng. Lệnh `chaos` thêm trường tùy chọn `cls`; lớp không có thì dùng lớp nhân vật.
  Cánh lớp khác vẫn không mặc được (giữ luật lớp). Cánh đầu vào của `wing2` / `wing3` nhận cánh lớp nào cũng được (như cũ).
- **B-8** (anh yêu cầu) Túi đồ: ô trống cạnh Mũ thành ô **Thú nuôi** — hiện thú đang dắt (hình thú, cấp thú), bấm mở Menu → Thú cưng
  để chọn / đổi thú. Chỉ là giao diện (thú vẫn chọn bằng `pet_choose`, không kéo thả). Thú trong `pets.json` có thể thêm `ref`
  ("13/80"…) để dùng hình MU riêng của anh: `mix hac_long.items.fetch --icons-from` chép cả hình của thú có `ref`. Chưa gán `ref`
  cho thú nào vì hình thú MU (Thiên Thần, Satan, sừng Uniria / Dinorant / Fenrir, Ngựa Đen, Quạ Đen, Daemon, Tinh Linh, Rudolph,
  Gấu Trúc) không khớp sáu thú hiện có — chờ anh chọn.
- **B-9** (anh chọn, em đề xuất số) Thêm 6 thú theo hình thú MU anh cung cấp, bán ở Người Nuôi Thú, dùng lại các loại
  cộng chỉ số và kỹ năng có sẵn (không đổi Engine): Gấu Trúc 13/80 (12.000 vàng, EXP +6%, vàng +6%, Móc Túi), Quạ Đen 13/5
  (20.000, tấn công +5%, Phấn Độc), Thiên Thần Hộ Mệnh 13/0 (25.000, phòng thủ +5%, máu +5%, Liếm Vết Thương), Quỷ Satan 13/1
  (60.000, tấn công +7%, Cắn Xé), Tinh Linh Hộ Vệ 13/65 (80.000, phòng thủ +6%, máu +7%, Liếm Vết Thương), Ác Quỷ Daemon 13/64
  (120.000, tấn công +8%, EXP +3%, Cắn Xé). Hình: có hình MU (`ref`) thì dùng ở ô Thú nuôi, danh sách thú và cửa hàng; không có
  (máy chưa chép hình riêng) thì dùng hình CC0 trong `pets/` — trên bản đồ luôn dùng hình CC0 (cỡ ô 32px). Không thêm Rudolph,
  Ngựa Đen, các "Sừng" (Uniria, Dinorant, Fenrir): không có hình CC0 hợp / hình chỉ là cái sừng. Thành tựu "có đủ thú" giờ cần 12 thú.
- **B-10** (anh chọn) Đấu trường: thêm ô **tìm người chơi theo tên** để thách đấu bất kỳ ai (trước chỉ có 5 người điểm gần nhất
  nên hai người điểm khác nhau có thể không thấy nhau). Kênh thêm `arena_find {q}` → `{found}` (tối đa 10 người, tên chứa `q`,
  không phân biệt hoa thường, tên khớp đúng lên đầu, không ra chính mình; giới hạn 30 lần / phút). Thách đấu vẫn qua
  `pvp_challenge` như cũ (giới hạn trận / ngày giữ nguyên).
- **B-11** (anh chốt) **Tháo được vũ khí và giáp** như mọi ô khác (trước: chỉ thay bằng món khác). Tay không thì tấn công chỉ
  tính theo chỉ số (không cộng vũ khí, ép, dòng phụ của vũ khí); không giáp thì phòng thủ chỉ còn phần chỉ số và các ô khác.
  Hình nhân vật vẽ tay không / không giáp. Client: nút Tháo và kéo vũ khí / giáp từ ô trang bị về túi.
- **B-12** (anh yêu cầu) Sổ tay quái vật gồm cả **52 loài quái bản đồ phụ** (`SIDE_MONSTERS`), không chỉ 30 loài của 6 vùng chính
  (trước đó hạ quái bản đồ phụ vẫn được đếm và cộng % sát thương, chỉ là sổ không hiện). Sổ chia hai nhóm: Vùng chính, Bản đồ phụ.
  Thành tựu "Nhà Sinh Vật Học" (hạ đủ mỗi loài) giờ cần đủ 82 loài; ai đã nhận rồi vẫn giữ.
- **B-13** (anh chốt) **Ép đồ kiểu MU** (`priv/game_data/upgrade.json`, `Engine.upgrade_cost/2`):
  +1 → +6 mỗi lần 1 Ngọc Ước Nguyện, luôn thành công (bỏ đường ép bằng quặng / Vảy Cổ Long; quặng vẫn dùng rèn đồ và Máy Hỗn
  Nguyên); +7 → +9 1 Ngọc Tâm Linh, 50 % (May mắn +25 % = 75 %), thất bại **về +0**; +10 / +11 chỉ ép ở Máy Hỗn Nguyên (lệnh
  mới `chaos_upgrade` ở Lão Hỗn Nguyên): +10 = 1 Hỗn Nguyên + 1 Ước Nguyện + 1 Tâm Linh 50 %, +11 = 1 Hỗn Nguyên + 2 Ước
  Nguyện + 2 Tâm Linh 45 %, thất bại vỡ đồ. Vàng như cũ (8 % giá × cấp lên). Đồ đã ép trước đây giữ nguyên cấp. Bỏ
  `RULES.upgrade.rare_ore_level` / `scale_step` (không còn dùng).
- **B-14** (anh yêu cầu) **Bảng chi tiết món đồ kiểu MU** (chỉ giao diện): chữ giữa nền tối; tên màu theo loại (thường trắng, +7 trở
  lên vàng, "Đồ hoàn hảo …" xanh lá cho Excellent, "Đồ Thần …" trên dải xanh cho đồ Thần); "Cấp / Sức mạnh … yêu cầu: N" (thiếu
  thì đỏ kèm số thiếu); dải "Dùng cho …" (đỏ khi lớp mình không dùng được); các dòng cộng thêm màu xanh ("Gia tăng …", May mắn,
  Kỹ năng, Ngọc Sinh Mệnh, Excellent, dòng cánh); khung thông tin bộ (Bộ Thần: các mức thưởng, mức đã đạt sáng; bộ giáp
  thường: thưởng đủ bộ). Độ hiếm Tốt / Hiếm / Sử Thi (của Hắc Long, không có trong MU) hiện thành "Gia tăng <chỉ số> +N".
  Client nhận thêm `RULES.ancient.bonus` để hiện mức thưởng Bộ Thần.
- **B-15** (anh chốt "làm đi, cho giống MU") **Bỏ độ hiếm Tốt / Hiếm / Sử Thi, đồ theo kiểu MU**: đồ thường (có thể kèm May mắn,
  Kỹ năng, **dòng cộng thêm** +4 / +8 / +12 / +16), đồ hoàn hảo (Excellent), đồ Thần — như MU, không còn chỉ số STR / AGI / VIT /
  ENE cộng ngẫu nhiên và hậu tố tên ("… Sức Mạnh"). Dòng cộng thêm dùng chung trường `opt` với Ngọc Sinh Mệnh (mỗi dòng
  `RULES.upgrade.life.per_line` = 4 tấn công / phòng thủ, tối đa 4 dòng). Đồ rơi từ quái: `RULES.loot.gear_weights` giờ là
  `[số dòng, trọng số]` = không dòng 50 %, +4 35 %, +8 12 %, +12 3 % (em đề xuất số). Rương, rèn, Túi Quà Lễ Hội, trùm lần đầu,
  Quảng Trường Quỷ giữ nguyên bảng trọng số cũ nhưng đọc là số dòng (độ hiếm 1..3 → 1..3 dòng), nên luôn có dòng.
  **Đồ cũ**: khi nạp, độ hiếm N thành N dòng cộng thêm (lấy số lớn hơn nếu món đã có dòng Ngọc Sinh Mệnh), bỏ điểm chỉ số
  cộng thêm; thư cũ `gear:<mẫu>:<1..3>:<+N>` mở ra cũng thành chừng đó dòng. Không đổi schema: hai trường `rarity` (luôn 0) /
  `bonus` (luôn rỗng) giữ trong `gear` và cột `gear_log.rarity`. Giá bán: `giá × 0.4 × (1 + 0.25 × số dòng)` × Excellent ×
  May mắn / Kỹ năng × Thần (`RULES.shop.gear_opt_value`, bỏ `gear_rarity_value`, `gear_bonus_value`, `loot.gear_bonus_per_level`).
  Thành tựu "Của Hiếm" đổi thành có một món hoàn hảo hoặc đồ Thần (ai nhận rồi vẫn giữ). Quản trị: `give_gear` nhận `opt` 0..4
  thay `rarity` / `bonus`. Client: tên / viền / bóng icon theo loại (`kind`: xanh có dòng, lục hoàn hảo, Thần), bỏ nhãn độ hiếm.
- **B-16** (anh chốt "làm 1 và 2", em đề xuất số) **Excellent đủ 6 dòng mỗi nhóm như MU** (`RULES.excellent.options`):
  vũ khí / dây chuyền thêm `atk_lvl` (tấn công + cấp × 0.1; MU là cấp/20, nhân đôi cho hợp số tấn công Hắc Long) và `ar_pct`
  (MU "tăng tốc độ đánh"; trận theo lượt nên đổi thành tỉ lệ trúng +10 %); giáp / khiên / nhẫn thêm `mp_pct` (MP tối đa +4 %),
  `reflect` (phản 5 % sát thương quái vừa gây, cộng dồn tối đa `max_reflect` 20 %, quái còn ít nhất 1 máu — không giết bằng phản
  đòn; chỉ trận đánh quái, chưa áp vào PK) và `def_rate` (MU "tỉ lệ phòng thủ thành công +10 %" → tỉ lệ né × 1.1). Đồ rơi vẫn
  1–3 dòng (`excellent.lines` giữ nguyên); Máy Hỗn Nguyên "Pha Excellent" thêm tới đủ 6 dòng (trước tối đa 3). Quản trị: ô tặng
  đồ riêng có thêm ô tick May mắn / Kỹ năng / đồ Thần và từng dòng Excellent (server vẫn kiểm dòng hợp loại đồ); client nhận
  `RULES.excOptions`.
- **B-17** (anh yêu cầu "tôi muốn có tất cả items trong file Item.txt", em đề xuất số) **Đủ trang bị của Item.txt**:
  thêm 135 món còn thiếu (tổng 281 → 416): mọi vũ khí nhóm 0–5, khiên nhóm 6, bộ giáp nhóm 7–11. Không thêm: Kiếm Tổng Lãnh
  Thiên Thần 0/19 và Khiên Rồng 6/13 (đã có dạng đồ trùm `relic`, `dragonshield`), Tên / Mũi Tên Nỏ 4/7, 4/15 (đạn, Hắc Long
  không có). Lớp: cờ lớp ≥ 1 (cả đồ bậc tiến hóa 2, 3) cho lớp gốc; đồ của **Chúa Tể** (quyền trượng, bộ Hắc Chủ / Vinh Quang /
  Ánh Dương / Bá Vương) → Kiếm Sĩ + Đấu Sĩ; đồ của **Triệu Hồi Sư** (sách, gậy Hồng Đen / Hào Quang / Huệ Tây, bộ Hồng Đen /
  Hào Quang / Huệ Tây / Nữ Hoàng) → Phù Thủy. **Bậc mới**: vũ khí bậc 9 / 10 / 11 (cấp 37 / 42 / 47, công 98 / 120 / 145
  theo `stats.weapon_atk` / `staff_atk`, giá 28k / 50k / 85k), bộ giáp bậc 9 / 10 (cấp 40 / 48, thủ cả bộ 80 / 105, giá
  32k / 70k), khiên bậc 9 / 10 (cấp 46 / 50, thủ 52 / 62, giá 45k / 80k). Bậc theo cấp rơi MU: vũ khí ≤ 110 / 130 / 150, giáp
  106–150 / 380, khiên < 380 / 380; món cấp MU thấp vào bậc cũ làm món phụ. Món chính mỗi bậc bán ở cửa hàng, món phụ chỉ
  rơi (như Phase 19). Tiên Nữ không có bộ giáp bậc 9 trong Item.txt (bậc 8 lên thẳng 10). `ItemBuild`: thêm `mode: "curve"`,
  sách phép (không có sát thương trong file) lấy khoảng ±10 %, danh sách chính được `null`. Chưa thêm (cần hệ thống mới, chờ
  anh chốt): cánh của Chúa Tể / Triệu Hồi Sư (12/40, 12/41, 12/43), ngọc cầu / sách phép học kỹ năng (12/7–48, nhóm 15),
  hạt / giáo hạt socket, thú cưỡi, nhẫn biến hình / nhẫn sự kiện, vật phẩm sự kiện / nhiệm vụ (nhóm 13–14).
- **B-18** (anh chốt "làm luôn 9, 1, 2, 3, 4", em đề xuất số) **Ghép vé kiểu MU**: quái không rơi thẳng vé nữa mà rơi **mảnh vé**
  (`RULES.devil_square.ticket_drop` / `blood_castle.ticket_drop`): Mắt Quỷ / Chìa Khóa Quỷ (quái cấp ≥ 30, 2 %), Cuộn Giấy Tổng
  Lãnh Thiên Thần / Xương Máu (cấp ≥ 35, 1 %) — gấp đôi tỉ lệ rơi vé cũ vì cần 2 mảnh. Ghép ở Máy Hỗn Nguyên (`chaos.json`
  `ds_ticket`: 2 mảnh + 1 Hỗn Nguyên + 10.000 vàng, 80 %; `bc_ticket`: 2 mảnh + 1 Hỗn Nguyên + 15.000 vàng, 80 %; hỏng mất cả).
  Vẫn mua vé bằng vàng ở Người Gác Tháp như cũ. Hình gốc theo `refs` 14/17, 14/18, 13/16, 13/17.
- **B-19** (anh chốt "làm luôn 9, 1, 2, 3, 4", em đề xuất số) **Hỗn Chiến Thành** (kiểu MU Chaos Castle, `RULES.chaos_castle`,
  `HacLong.ChaosCastle`): mỗi 2 giờ lệch 90 phút (1h30, 3h30 … 23h30), cho vào **5 phút** rồi **10 phút** hỗn chiến. Cấp ≥ 15,
  tốn 1 **Áo Giáp Vệ Binh** (`cc_ticket`, hình 13/29; mua 15.000 vàng ở Người Gác Tháp hoặc rơi 0,5 % từ quái cấp ≥ 15).
  Bản đồ chung `chaos_castle` (`event: "chaos_castle"`): không chọn map / dịch chuyển tới, vào lại game khi đã bị loại thì về
  Làng. Lúc bắt đầu thả `max(10, 30 − số người)` quái cấp trung bình người vào ± 2 (quái vùng + quái phụ, không trùm). Trong
  thành được đồ sát nhau ngay khi hỗn chiến (trước đó cấm), **không mất vàng, không tên đỏ**; gục (quái hay người), đổi bản
  đồ, thoát game là bị loại, về Làng. Còn đúng 1 người và hết quái → thắng: 60.000 vàng + 1 Hỗn Nguyên + 2 Ước Nguyện + 1 Tâm
  Linh; hết giờ → người còn trụ: 8.000 vàng + 1 Ước Nguyện; mỗi người hạ được +2.000 vàng. Thưởng **gửi thư**. Khác MU: không
  thu hẹp sàn, không chia theo 7 cấp thành (một thành, quái theo cấp người vào), không rơi đồ khi chết.
- **B-20** (anh chốt "làm luôn 9, 1, 2, 3, 4", em đề xuất số) **Rồng Đỏ / Phù Thủy Trắng xâm lăng** (`RULES.raids`,
  `HacLong.Raids`, tách khỏi Golden Invasion để chạy song song): **Rồng Đỏ** 2h45, 6h45 … 22h45 (4 giờ một lần), 20 phút, 3
  bản đồ vùng ngẫu nhiên, mỗi bản đồ 2 Rồng Đỏ (cấp trùm vùng + 4, sức ×1,5, tính như trùm, đứng yên); **Phù Thủy Trắng**
  0h45, 4h45 … 20h45, 20 phút, 2 bản đồ, mỗi bản đồ 1 Phù Thủy Trắng (cấp trùm vùng + 5, sức ×2) + 6 Lính Orc (cấp quái mạnh
  nhất vùng + 1, sức ×1,2, đi lang thang). Không hồi sinh; thưởng kinh nghiệm/vàng ×4 (Rồng) / ×3 (Phù Thủy); đầu đàn chắc chắn
  rơi 1 ngọc và có thể rơi thêm (Rồng: Hỗn Nguyên 30 %, Sinh Mệnh 10 %; Phù Thủy: Hỗn Nguyên 50 %, Tâm Linh 30 %); Lính Orc
  rơi ngọc 15 %. Hạ hết → kết thúc sớm; hết giờ con chưa ai đánh biến mất. Khác MU: không rơi Hộp Kundun (chưa có hộp), quái
  theo cấp vùng thay vì cấp cố định, hình tô lại màu từ hình CC0 sẵn có.
- **B-21** (anh chốt "làm luôn 9, 1, 2, 3, 4", em đề xuất số) **Kalima** (`RULES.kalima`, `HacLong.Game.Kalima`, chạy trên
  trạng thái tháp như Lâu Đài Máu, `p.tower.kal`, không đổi schema): **Dấu Ấn Kundun** (`kundun_mark`, 14/29) rơi 1 % từ quái
  thường cấp ≥ 20; ghép **5 dấu ấn + 5.000 vàng** ở Máy Hỗn Nguyên ra **Bản Đồ Thất Lạc** (`lost_map`, 14/28, 100 %). Đưa bản
  đồ cho Người Gác Tháp (không theo lịch, từ cấp 20) → **Kalima 1–7 theo cấp nhân vật** (20/25/30/35/40/45/50 → quái cấp
  22/27/…/52). 10 phút: hạ 10 quái Kalima (×1,15) → **Kundun** (cấp +3, sức ×1,8, máu ×5) hiện gần cầu thang lên → hạ
  Kundun: vàng ×300 / kinh nghiệm ×10 theo cấp quái, 3 ngọc, **1 món đồ** (Excellent 50 %, đồ Thần 30 % nếu là bộ giáp).
  Không xong: thưởng theo số quái đã hạ. Khác MU: chỉ một loại dấu ấn / bản đồ (không chia 7 cấp vật phẩm), Kalima là bản
  đồ riêng một người (không tổ đội, không cổng mở cho người khác). Sửa kèm: trận đang đánh trong Quảng Trường / Lâu Đài
  (quái có cờ `ds` / `bc`) lưu xuống rồi nạp lại bị lỗi vì thiếu khóa trong `Characters @battle_keys` — đã thêm `ds bc kal`.
- **B-22** (anh chốt "làm luôn 9, 1, 2, 3, 4", em đề xuất số) **Công Thành Chiến** (`RULES.castle_siege`,
  `HacLong.CastleSiege`, bản đồ chung `castle_siege` "Thành Hắc Long"): **thứ Bảy 20h00, 30 phút** mỗi tuần. Bang chủ / phó
  bang đăng ký ở Người Gác Tháp trước giờ đánh (**200.000 vàng** của người đăng ký); bang đang giữ thành không cần đăng ký;
  không ai đăng ký và chưa có Chủ Thành thì tuần đó không đánh. Trong trận, thành viên cấp ≥ 30 của các bang tham gia vào
  thành (sân phía nam), gục thì về Làng không mất vàng, vào lại được. **Vương Miện** (cấp 50, sức ×2,5, đứng giữa thành): bang
  hạ được thì giữ Vương Miện, nó hiện lại sau 60 giây, bang đang giữ không đánh được nó. Người hai bang khác nhau đồ sát
  nhau (không mất vàng, không tên đỏ), cùng bang không đánh nhau. Hết giờ: bang đang giữ Vương Miện là **Chủ Thành** tới trận
  sau; mọi thành viên nhận qua thư **100.000 vàng + 1 Hỗn Nguyên + 3 Ước Nguyện + 2 Tâm Linh**. Khác MU: không có cổng /
  tượng thủ thành / máy bắn đá, không thu thuế, Chủ Thành chỉ có danh hiệu trên thẻ + phần thưởng. **CHANGE_REASON (schema):**
  thêm bảng `castle_siege` (một dòng: `owner_guild_id`, `owner_since`, `registered`) để Chủ Thành và đăng ký còn sau khi khởi
  động lại server; không đổi bảng cũ.
- **B-23** (anh chốt "ok sửa") **Tăng tỉ lệ rơi vé / nguyên liệu sự kiện** (đồ không quý, mua vé bằng vàng rẻ hơn cày):
  Mắt Quỷ / Chìa Khóa Quỷ 2 % → **5 %**, Cuộn Giấy Tổng Lãnh Thiên Thần / Xương Máu 1 % → **4 %**, Áo Giáp Vệ Binh 0,5 % →
  **2 %**, Dấu Ấn Kundun 1 % → **4 %** (≈ 40 / 50 / 50 / 125 quái cho một vé / Bản Đồ Thất Lạc). Cấp quái bắt đầu rơi giữ nguyên.
  Cùng đợt (anh chốt "ok"): **ghép vé không cần Ngọc Hỗn Nguyên nữa** (ngọc quá hiếm so với vé mua được bằng vàng):
  `ds_ticket` 2 mảnh + 12.000 vàng, `bc_ticket` 2 mảnh + 18.000 vàng (vẫn 80 %); **Áo Giáp Vệ Binh 15.000 → 5.000 vàng**
  (cấp 15 mỗi quái ≈ 36 vàng, giá cũ ≈ 420 quái).
- **B-24** (anh chốt "như em đề xuất") **Thợ Rèn chỉ bán đồ cơ bản** (kiểu MU): đồ thường cấp ≤ 17 (`RULES.shop.smith_max_level`,
  4 bậc đầu, 75 món thay vì 170); đồ cấp 22+ chỉ có từ quái rơi, sự kiện, rương, chợ / giao dịch. Bù lại quái thường rơi đồ
  6 % → **8 %** (`RULES.loot.gear_chance.normal`; Bóng Đêm, trùm, tinh anh giữ nguyên). Đồ đã mua trước giữ nguyên.


- **B-25** (anh chốt "ok theo đề xuất", Phase 1 đợt sửa lỗi 2026-10-16):
  - **Túi đồ hiếm đầy (20/20): đồ rơi gửi vào Hộp thư** thay vì tự bán. Mỗi món một thư, giữ đủ dòng (May mắn / Kỹ năng /
    Excellent / Thần / dòng phụ cánh) qua khóa `items` mới `"gearx:<base64 JSON>"` (không đổi schema `mails`); gửi cùng
    transaction với lần ghi nhân vật (`Session.save`). Hộp thư đã có `RULES.mail.keep` thư chưa mở thì mới bán lấy vàng.
  - **"+N" chỉ là cấp ép.** Dòng cộng thêm (Ngọc Sinh Mệnh) ghi chữ: `Kiếm Rồng (cộng thêm 8)` thay cho `(+8)`.
  - **Tháp Thử Thách tầng 51+**: 5 vùng quái lặp lại theo vòng 50 tầng, tên thêm hậu tố vòng (Cổ Đại, Hắc Ám, Thần Thoại,
    Hỗn Mang, Vĩnh Hằng) để không trùng tên / hình với tầng 1–50 ở cùng chỗ (chỉ số vẫn tăng theo tầng như cũ).
  - **Bỏ chạy rồi đánh lại quái trên bản đồ: quái giữ máu** đã mất và hồi 2 % máu tối đa mỗi giây (không về đầy ngay).
  - Quản trị `give_gear` nhận cả cánh (dòng cộng thêm, May mắn, `wopt`).
- **B-26** (anh chốt "ok làm phase 2", 2026-10-16) **Đài Phúc Lành thay đá dịch chuyển** (ô `W`, việc đi lại đã có bảng
  chọn bản đồ). Chạm đài: phúc lành của bản đồ (+5 % kinh nghiệm / phòng thủ / tấn công / vàng / máu tối đa, loại theo thứ
  tự đài, `RULES.blessing`) và đài thành **điểm hồi sinh** khi gục ở bản đồ thường (bản đồ sự kiện vẫn về Làng; chưa chạm
  đài nào thì về Nhà). Phúc lành tính theo **số trận** (30 trận, như món ăn) thay vì 10 phút như đề xuất, để Engine vẫn là
  hàm thuần, không phụ thuộc đồng hồ. Bỏ lệnh `teleport` và bảng dịch chuyển. Cột mới `characters.blessing` (map,
  migration `20261105000000_add_blessing`). Thành tựu "Lữ Khách" giờ là ghé mọi Đài Phúc Lành. Hình đài: tô vàng từ hình
  đá cũ (`e2e/tint_sprites.mjs`).
  - Cùng đợt: đồ nhận sau trận bấm xem chi tiết và **🗑 Hủy** ngay trên bảng kết quả (vứt được khi trận đã xong);
    Thợ Rèn có hai thẻ **Đang mặc / Trong túi**, hướng dẫn ép thành bảng gấp gọn; bấm avatar mở hồ sơ, bấm đồ trong hồ sơ
    (mình và người khác) xem chi tiết; header bỏ lớp và chuyển sinh.
  - Quà cho mọi người: nhiều món một thư, lọc người nhận (cấp, chuyển sinh, online), **không gửi bot**, xem trước số
    người nhận, lịch sử 20 đợt (`gift_count`, `gift_log`, chỉ đọc).
- **B-27** (Phase 8, rà soát công thức, `docs/FORMULA_AUDIT.md`) sửa 3 lỗi khi đánh người (Đấu trường, Đồ sát, PK cược):
  phần giảm sát thương của đối thủ (hấp thụ cánh × Excellent "giảm sát thương") giờ áp vào đòn đánh họ (`taken`; trước đây
  Đồ sát bỏ qua hẳn, Đấu trường chỉ quy cánh vào máu); dòng cánh "bỏ qua phòng thủ" của đối thủ có tác dụng khi họ đánh
  mình; chí mạng của bản sao đối thủ dùng hệ số thật của người đó thay vì × 1,5 của quái. Đề xuất A–D trong báo cáo chờ anh chốt.
- **B-28** (anh chốt "A, B, C, D ok", `docs/FORMULA_AUDIT.md` §2): Excellent `atk_lvl` 0,1 → **0,6** (cấp 50 ≈ +30 công);
  né chặn **`combat.dodge.max_total` 0,6** sau khi nhân Excellent `def_rate`; **ép nhẫn chỉ có máu cộng máu** (8 % máu gốc
  mỗi cấp hiệu dụng) thay vì +1 thủ; bỏ `monster.dodge` khỏi RULES (quái không né, trúng theo AR / DR).
- **B-29** (anh chốt "làm phase 3", theo đề xuất Phase 3) **Kỹ năng Tháp Thử Thách + nguyên tố + bộ 4 kỹ năng.**
  - Mỗi lớp 10 kỹ năng tháp (`CLASSES[lớp].tower_skills`), mở khi kỷ lục tháp ≥ tầng 10, 20, … 100, giữ vĩnh viễn.
    Hệ số 1,45× (tầng 10) → 3,7× (tầng 100), MP 13 → 40 (tăng theo cấp như kỹ năng lớp).
  - Tác dụng ghi trong dữ liệu (`RULES.tower_skills._doc`): nhiều đòn, xuyên giáp, chắc chí mạng, hồi máu, hút máu, khống chế,
    cuồng nộ / thủ thế / né, **khiên** (hấp thụ % máu tối đa), **bất tử** (gục thì đứng dậy một lần), **phá giáp**, độc / đốt.
    Mô tả trên giao diện dựng từ số, không chép chữ.
  - **Nguyên tố** (`RULES.elements`): Lửa > Băng > Gió > Đất > Sét > Lửa, Ánh Sáng ↔ Bóng Tối.
    - Kỹ năng khắc nguyên tố quái +30 % sát thương, bị khắc −20 %; đòn thường không nguyên tố.
    - Quái mang nguyên tố theo cấp (`by_level`), vì vậy tháp, bản đồ phụ, sự kiện đều có nguyên tố.
    - 12 kỹ năng lớp cũ được gán nguyên tố.
  - **Bộ kỹ năng:** mang tối đa 4 kỹ năng (kỹ năng lớp + kỹ năng tháp) vào trận, chọn ở Menu → Kỹ năng → ⚙ (bỏ nút ⚙ trong trận cho gọn, theo yêu cầu).
    - Đổi được cả khi đang đánh; hồi chiêu giữ nguyên.
    - Chưa chọn thì mặc định 4 kỹ năng mạnh nhất đã mở.
    - Cột mới `characters.skill_set` (migration `20261106000000_add_skill_set`).
    - Quản trị thêm `set_tower {floor}`.
- **B-30** (anh chốt phương án (a) và "ok" Phase 6) **10 vùng đất chuyển sinh** (`realm_01…10`, `scripts/gen_realms.py`,
  `priv/game_data/realms.json`, `RULES.realms`).
  - **Vào:** vùng k cần chuyển sinh ≥ k và cấp ≥ 40 (qua Chọn bản đồ, cổng nối vùng k ↔ k+1, vùng 1 nối Làng);
    mỗi vùng có Đài Phúc Lành.
  - **Quái:** mỗi vùng 3 quái + 1 chúa tể, cấp hiện 52…150, nguyên tố riêng.
    - Giữ cấp tối đa 50: chỉ số quái tính ở cấp 50 × hệ số (1 + 0,4k; chúa tể × 1,8).
    - Vàng / kinh nghiệm theo cấp hiện.
    - Đo bằng script cân bằng: nhân vật CS1 đồ +7 đánh được vùng 1; chúa tể vùng 10 là thử thách cho nhân vật tối đa
      (hạ ~9 lượt, trụ ~12 lượt). Hệ số 0,15 thử trước quá dễ, đã tăng lên 0,4.
  - **Rơi quý hơn:** tỉ lệ ra đồ / Excellent / May mắn / đồ Thần × (1 + 0,1 × k), tối đa 0,9; ngọc 2 % + 0,4 % × k mỗi quái
    (chúa tể × 5).
  - **Tháp:** tầng 1–60 quái 6 vùng cũ, 61–160 quái 10 vùng đất chuyển sinh (nền tầng theo vùng), sau đó quay vòng có
    tiền tố tên.
  - **Hình quái:** 40 hình tô lại từ hình CC0 sẵn có (`e2e/tint_sprites.mjs`).
  - **Quản trị:** thêm `set_rebirths {n}` (chỉ đặt số lần, không về cấp 1).
- **B-31** (anh chốt "chỉ online thôi, làm phase 4") **Tự đánh quái** (`HacLong.Game.AutoHunt`, `RULES.auto`).
  - **Chỉ khi online:** chạy trong `Session` (nhịp `:auto_tick`) khi còn ít nhất một tab mở; đóng hết tab là tắt.
    Không có tự đánh offline.
  - **Server-authoritative:** client chỉ gửi lệnh `auto {on, target, hp, mp, loot}`; mỗi nhịp server tự chọn lệnh
    (`move` / `attack` / `skill` / `potion` / `mana` / `use` / `discard` / `leave`) và chạy qua đúng đường lệnh client
    (cùng luật, cùng giới hạn tốc độ, cùng lưu database).
  - **Dùng lại bot:** `Bots.Brain.fight/3` (ngưỡng máu / mana theo cài đặt, kỹ năng mạnh nhất trong bộ 4 kỹ năng đang mang)
    và `Brain.hunt/3` (tìm đường tới con quái gần nhất không ai đánh).
  - **Chọn quái:** quái hợp cấp (cấp ≤ cấp mình + 1; bản đồ không có con nào như vậy, vd vùng chuyển sinh, thì mọi quái thường)
    hoặc một loại có trên bản đồ. Không đánh trùm của bản đồ có quái hồi sinh.
  - **Lọc đồ "chỉ đồ quý":** hủy món đồ thường vừa nhặt; giữ Excellent / Thần / May mắn / Kỹ năng / từ
    `keep_opt_min` (2) dòng cộng thêm / cánh / trang sức / món tốt hơn đồ đang mặc / món đã khóa. Ngọc, bình, nguyên liệu luôn giữ.
  - **Dừng:** hết bình máu, có người tên đỏ trên bản đồ, bị đồ sát, gục ngã / bỏ chạy, rời bản đồ.
  - **Không tự đánh:** bản đồ riêng (Nhà, sự kiện), Làng, Tháp, Hỗn Chiến Thành, Công Thành Chiến.
  - Cài đặt chỉ nằm trong bộ nhớ (`player.auto`, không thêm cột database); cài đặt lần trước nhớ ở trình duyệt.
- **B-32** (anh "ok làm phase 5") **Bản đồ động + bot thông minh hơn.**
  - **Bản đồ động** (chỉ ở client, `map.js`, không đổi luật): nước gợn, cây lay theo gió, quái đứng yên nhún nhẹ, đài phun nước lấp lánh;
    thời tiết theo nền bản đồ (đầm lầy mưa, hang / vùng chuyển sinh tro lửa, núi tuyết, nghĩa địa sương, rừng / trại lá rơi,
    Làng khói bếp từ góc mỗi khối nhà); ban đêm / chạng vạng có đom đóm và đèn lồng quanh người dân.
    - Hạt tính thẳng từ thời gian (không giữ trạng thái), vẽ lại ~12 khung/giây khi đang xem bản đồ, dừng khi ẩn tab.
    - Nút tắt ở Menu → Cài đặt (`hl-fx`); máy đặt "giảm chuyển động" thì mặc định tắt.
  - **Bot mua bình** (`Brain.restock/1`, `RULES.bots`): còn < 3 bình máu (< 2 bình mana, lớp có MP) mà đủ vàng mua ít nhất
    mức đó thì về Làng mua ở Bà Lang tới 10 / 6 bình. Loại bình: rẻ nhất hồi được ≥ 30 % máu (MP) tối đa, không có thì
    loại mạnh nhất mua được.
  - **Bot nghỉ trọ:** máu < 45 %, hết bình, không mua nổi bình mà có ≥ 2 × giá trọ thì nghỉ ở Quán Trọ Làng; không thì về
    Nhà uống giếng như cũ.
  - **Sửa lỗi bot đứng yên:** mốc "nghỉ sau khi gục" khởi đầu bằng 0 trong khi `System.monotonic_time` có thể là số âm
    (máy ảo) → bot bị coi là đang nghỉ mãi, không làm gì từ lúc khởi động server. Giờ mốc khởi đầu là lúc bot khởi động.
    Chạy thử 90 giây: cả 20 bot về Làng mua bình rồi đi săn, lên kinh nghiệm bình thường.
- **B-33** (anh "ok làm phase 7") **Bộ hình đồ thay thế, không dùng hình MU.**
  - Menu → Cài đặt → **Hình đồ**: **MU** (chỉ hiện khi máy chủ có hình MU riêng, `mix hac_long.icons`) / **Pixel** / **Biểu tượng**
    (SVG game-icons như trước). Mặc định: MU nếu có, không thì Pixel. Lưu ở trình duyệt (`hl-icons`); chỉ đổi hình, không đổi luật.
  - **Pixel:** 173 hình CC0 từ Dungeon Crawl Stone Soup cho 454 món (mọi vũ khí, khiên, mũ, giáp, quần, găng, giày, nhẫn, dây
    chuyền, bình, ngọc, vé / nguyên liệu sự kiện). `scripts/pixel_icons.py`: mỗi loại đồ một dãy hình yếu → mạnh, món trong loại
    xếp theo cấp rồi chia đều nên đồ cấp cao trông xịn hơn; Pháp Sư mặc áo choàng / đội nón, Tiên Nữ giáp da / vảy rồng; nhẫn,
    dây chuyền theo nguyên tố trong tên. Bỏ mọi file thuộc `TILES_UNDER_UNKNOWN_LICENSE.md`.
  - Chưa có hình pixel (cánh, đồ ăn, nguyên liệu đã có hình riêng) thì giữ hình cũ.
  - Hình MU vẫn không vào git / Docker; bộ Pixel có trong git (CC0, ghi ở `CREDITS.md`).
- **B-34** (anh góp ý sau đợt 8 phase, 2026-10-17) **Sửa theo phản hồi.**
  - Mang **5 kỹ năng** vào trận (`RULES.tower_skills.loadout` 4 → 5; điện thoại 4 kỹ năng để trống một ô).
  - **Bỏ chạy giữ máu quái** cả trong Tháp, Quảng Trường Quỷ, Lâu Đài Máu, Kalima (`Tower.keep_hp/1`, `resume_hp/2`; quái
    lưu `hp_pct`). Quái bản đồ chung hồi `RULES.monster.flee_regen_pct_s` = 0,5 %/giây (trước 2 %/giây, đầy lại sau ~50 giây
    nên trông như không giữ máu).
  - Thanh máu quái: chữ "❤ máu / tối đa" ở giữa cho mọi loại quái (quái vàng trước bị lệch trái do trùng class `.gold`).
  - Nhẫn, dây chuyền MU (hình gốc ~21 px) phóng vừa ô kiểu điểm ảnh, sáng hơn.
  - Header điện thoại: tên + cấp một dòng (cấp luôn hiện), vàng xuống dòng dưới tên.
  - Cài đặt: hàng nút xuống dòng, không che tiêu đề mục.
  - Hiệu ứng bản đồ: vòng `requestAnimationFrame` ~30 khung/giây đều nhịp (trước ~12 khung/giây bằng hẹn giờ nên lá / tuyết giật).

## Hạ kỹ năng lớp xuống dưới kỹ năng Tháp (2026-10-17, anh chốt phương án A)
- Trước: kỹ năng lớp cấp 1 mạnh hơn kỹ năng Tháp tầng 10–30 (Chém Xoáy 220% hồi 3 lượt so với Phong Trảm tầng 10 145% hồi 4 lượt), thưởng Tháp gần như vô nghĩa đầu game.
- `RULES.skill_effects`: `cleave` 2.2 → 1.4 (Chém Xoáy); `fire_ball` 2.0 → 1.35, giữ xuyên 30% giáp (Cầu Lửa, Kiếm Lửa); `judgement` 1.8 → 1.4 (Phán Quyết); `backstab` `def_mult` 0.5 → 0.7 (Tam Tiễn xuyên 30% giáp, vẫn chắc chắn chí mạng). Mô tả trong `classes.json` sửa theo.
- Giữ nguyên các kỹ năng mà tác dụng phụ là chính: Trảm Choáng, Tia Sét, Hồi Sinh Lực, Tăng Sức Mạnh, Khiên Linh Hồn, Nộ Chiến, Kiếm Độc Hỏa.
- `mix hac_long.simulate 5 --seed 42` trước / sau: cả 4 lớp vẫn hạ Hắc Long 5/5 mọi cách chơi; phần lớn số trận chỉ xê dịch vài phần trăm, chết 0–2. Riêng Kiếm Sĩ "chỉ đánh" (không nhiệm vụ / nâng cấp) khó hơn rõ: 450 → 508 trận, chết 0 → 6 (Chém Xoáy là đòn chính của lớp này). Theo dõi; cần thì nâng `cleave` lên 1.5.

## Tự đánh kiểu MU Helper: phạm vi, kỹ năng, lọc đồ, lưu cài đặt (2026-10-17, anh chốt "làm như đề xuất")
- So với MU Helper (Hunting / Obtaining): làm (1) phạm vi săn + về chỗ cũ, (2) cách dùng kỹ năng + buff trước,
  (3) lọc đồ theo loại tích chọn, (5) lưu cài đặt theo nhân vật. Không làm: đánh trả từ xa, nhặt theo phạm vi, sửa đồ
  (game theo lượt, đồ tự vào túi, không có độ bền). Không làm (anh chốt 2026-10-17): giữ đồ theo tên, tự về Làng mua bình (hết bình máu thì tự đánh vẫn tắt).
- `RULES.auto` (version 2): `range_options` [0, 4, 8, 12] ô (0 = cả bản đồ, mặc định), khoảng cách Manhattan tính từ chỗ bật;
  `skills` all / basic / boss; `keep` exc / anc / luck / opt / better / cls, `keep_default` như bộ lọc "chỉ đồ quý" cũ
  (không có `cls`). Ngọc, nguyên liệu, cánh, nhẫn, dây chuyền luôn giữ. `loot: "good"` cũ đọc như `"pick"` + mặc định.
- "Kỹ năng buff tung trước": kỹ năng có `buff` (Tháp) hoặc tác dụng war_cry / guard / shadow_step xếp trước trong lượt chọn;
  hồi chiêu các kỹ năng này đều ≥ số lượt buff nên không tung đè.
- **CHANGE_REASON (schema):** thêm cột `characters.auto_cfg` (map, migration `20261107000000_add_auto_cfg`) lưu cài đặt
  lần bật gần nhất (target, hp, mp, loot, keep, range, skills). `p.auto` (đang chạy) vẫn chỉ trong bộ nhớ như B-31.
- Lệnh `auto` nhận thêm `range`, `skills`, `keep` (protocol thêm trường, client cũ không gửi thì lấy mặc định).

## Đồ sát cắt ngang trận đánh quái (2026-10-17, anh chốt)
- Người bị đồ sát đang đánh quái (bản đồ chung, đánh cùng tổ đội, ở bảng kết quả) vẫn bị đồ sát ngay: trận đó kết thúc như bỏ chạy
  (`World.finish_encounter/2` với kết quả "fled": quái nhả ra, giữ máu; đồng đội đánh tiếp), không phạt; nhật ký trận đồ sát ghi
  "Trận với … bị cắt ngang". Chỉ chặn khi người đó đang trong một trận đồ sát khác (`Slay.slaying?/1`).
- Người tấn công vẫn phải rảnh tay (không trong trận nào). Tự đánh của người bị đánh tự tắt như trước (bị đồ sát).

## Cân bằng cuối game (2026-10-17, anh chốt "ok như đề xuất")
- **A. Công quái vùng chuyển sinh** tách khỏi máu: máu vẫn × (1 + 0,4k), công × (1 + 0,15k) (`RULES.realms.atk_mult_per_realm`,
  `realms.json` thêm `atk_mult`, chúa tể × hệ số chúa tể). Trước đó công nhân cùng hệ số máu nên vùng 10 công ×5, giáp gần như vô dụng.
- **B. Ngọc vùng chuyển sinh**: 2 % + 1 %·k mỗi con (`jewel_per_realm` 0,004 → 0,01). Vàng đã nhân theo vùng nên giữ.
- **C. "Rơi quý thêm"** chỉ nhân tỉ lệ ra đồ; tỉ lệ Excellent / May mắn / Thần nhân không nhân nữa (trước nhân hai lần: nhiều đồ rơi hơn và mỗi món dễ quý hơn).
- **D. Dòng cộng thêm / Ngọc Sinh Mệnh**: mỗi dòng = 4 % công (vũ khí) hoặc thủ (món khác) gốc của món, ít nhất +4
  (`RULES.upgrade.life.per_line_pct`; `Engine.line_value/1`, client `lineVal`). Trước cộng phẳng +4 nên đồ bậc cao gần như không đáng ép dòng.
- **E. Né trong trận đánh quái** cộng buff né (Ảnh Bộ…) tối đa 85 % (`RULES.combat.dodge.max_with_buff`; `Engine.dodge_chance/2`). Trước buff cộng không trần.
- **F. MP kỹ năng** tăng 2 % mỗi cấp nhân vật (`skill_mp_per_level` 0,04 → 0,02): cấp 50 trước tốn ×2,96, nay ×1,98.
- Không làm (để sau): đường cong ép +N so với bậc đồ, định giá hiệu ứng kỹ năng.
- Mô phỏng (Kiếm Sĩ cấp 50, đồ bậc 11 +7 hai dòng, cánh cấp 3 +7, 200 trận mỗi loại quái), trước → sau:

  | Quái | Công | Máu mất mỗi trận thắng | Thua | Excellent / 100 con | Ngọc / 100 con |
  |---|---|---|---|---|---|
  | Vùng 1 | 462 → 379 | 3,5 % → 2,4 % | 0 → 0 | — | — |
  | Vùng 5 | 990 → 578 | 16,8 % → 6,4 % | 0 → 0 | 1,8 → 1,2 | 4 → 7 |
  | Vùng 10 | 1650 → 825 | 55 % → 27 % | 25 % → 0 % | 3,2 → 1,6 | 6 → 12 |
  | Chúa tể vùng 10 | 2970 → 1485 | — | 100 % → 83 % (không bình) | — | 30 → 60 |

- `mix hac_long.simulate 5 --seed 42`: cả 4 lớp vẫn hạ Hắc Long 5/5; Kiếm Sĩ "chỉ đánh" 508 → 451 trận, chết 6 → 1; các lớp khác xê dịch ít.

## Công cụ mô phỏng cả hành trình (2026-10-17, anh yêu cầu)
- `mix hac_long.journey` / `scripts/balance/journey.sh` (`HacLong.Game.Journey`, báo cáo `HacLong.Game.JourneyReport`): một bot
  chơi từ cấp 1 qua tối đa 10 lần chuyển sinh bằng đúng hàm của game (đánh, rơi đồ, ép, Ngọc Sinh Mệnh, Máy Hỗn Nguyên
  ghép cánh, nghỉ trọ, mua bình như bot thật, chuyển sinh). Chỉ là công cụ đo, không đổi luật game.
- Cách bot tự quyết (không có trong KB, em tự chọn cho công cụ): chọn bản đồ nhiều EXP nhất mỗi con trong các bản đồ dịch
  chuyển tới được (bản đồ thường bỏ nếu quái cao hơn mình quá 2 cấp), thua 2 trong 8 trận gần nhất thì tránh bản đồ đó 150 trận;
  chúa tể vùng chuyển sinh thử mỗi 40 trận (cấp ≥ 40); so đồ bằng điểm `công × máu hiệu dụng` (`Journey.score/1`);
  ép Ước Nguyện → +6, Tâm Linh → +9 (tắt bằng `--no-soul`), +10/+11 chỉ khi `--chaos-up`; giữ ngọc cho bậc cánh tiếp theo;
  chuyển sinh ngay ở cấp 50 sau khi hạ Hắc Long. Không mô phỏng: việc hằng ngày, sự kiện, tháp, chợ, tổ đội, PK, trùm thế giới.
- Lần chạy đầu (`--rebirths 10 --farm 1000 --seed 42`, Kiếm Sĩ), để anh xem:
  - mỗi chặng sau chuyển sinh vẫn ~470–530 trận (chặng đầu ~590): 15 điểm mỗi lần chuyển sinh và đồ giữ lại làm cấp 1–40 nhanh
    hơn ít (lượt / trận giảm 4,7 → 3), nhưng số trận gần như không đổi vì EXP cần lên cấp không đổi;
  - cấp 40 → 50 ở vùng chuyển sinh chỉ mất 3–5 trận (quái vùng cấp 52–150 cho EXP rất lớn);
  - cày ở các vùng cuối sau cấp 50: ~14 % trận thua, phần lớn do chúa tể (thua gần 100 %) và quái vùng 9–10;
  - ghép cánh 1 với món +5 chỉ 10 %: 7 lần thử đều trượt; ngọc Ước Nguyện hiếm nên đồ ép ít khi quá +5.

## Cân bằng ngọc, cánh, kinh nghiệm vùng chuyển sinh (2026-10-17, anh chốt "làm 1 2 3")
- **1. Kinh nghiệm quái vùng chuyển sinh** tính ở `stat_level` (50) × `xp_mult` = 1 + 0,2k (chúa tể × `boss_mult`)
  (`RULES.realms.xp_mult_per_realm`, `realms.json` thêm `xp_mult`, `Engine.make_monster/2`). Trước tính theo cấp hiện 52–150 × hệ số máu:
  quái vùng 10 cho ~54.700 kinh nghiệm (gấp 42 quái cấp 45), cấp 40 → 50 chỉ 4 con. Vàng vẫn theo cấp hiện.
- **2. Ngọc rơi** quái thường cấp ≥ 12: `JEWELS.monster_chance` 0,006 → 0,015 (~1 viên mỗi 67 con, 1 Ước Nguyện mỗi ~150 con).
  Ngọc vùng chuyển sinh (2 % + 1 %·k) giữ.
- **3. Ghép cánh cấp 1**: tỉ lệ gốc 0,10 → 0,25 (món +5 25 %, +7 35 %, trần 60 % giữ). Cánh 2, 3 giữ.
- Không làm (anh chưa chọn): kinh nghiệm / điểm theo số lần chuyển sinh, sức chúa tể.
- `scripts/balance/journey.sh --cls all --rebirths 10 --farm 1000 --seed 42`, trước → sau:

  | Lớp | Tổng trận | Trận cấp 40 → 50 mỗi chặng (vùng chuyển sinh) | Ép thành công | Món ép cuối (cao nhất) | Cánh |
  |---|---|---|---|---|---|
  | Kiếm Sĩ | 6442 → 7051 | 19 → 74 | 5 → 49 | +2 → +9 | không → không (9 lần trượt) |
  | Phù Thủy | 6452 → 6954 | 20 → 67 | 39 → 63 | +9 → +9 | có → có |
  | Tiên Nữ | 6439 → 6888 | 19 → 60 | 19 → 77 | +9 → +9 | có → có |
  | Đấu Sĩ | 6437 → 6916 | 19 → 62 | 3 → 94 | +2 → +9 | không → có |

  Chết ở vùng chuyển sinh tăng (Kiếm Sĩ 6 → 64 trên ~740 trận) vì giờ phải đánh ở đó thật; cày sau cấp 50 thua ít hơn (Kiếm Sĩ 137 → 113 / 1000) nhờ đồ ép cao hơn.

## Thú cưng: sức cắn riêng, cấp 20, cho ăn, thuần phục vùng chuyển sinh (2026-10-17, anh chốt "làm hết, nhưng thú không quá mạnh")
- **A. Sức cắn riêng mỗi thú** (`PETS.bite`, 15 % → 30 % đòn thường, thú đắt mạnh hơn) thay cho sức cắn chung 25 %. Tỉ lệ cắn
  30 % + 0,5 %/cấp (trước 35 % + 2 %/cấp), sức cắn + 0,8 %/cấp (trước + 2 %/cấp), Cắn Xé × 1,6 (trước × 2), Liếm Vết Thương 4 % (trước 5 %).
- **B. Móc Túi** lấy 10 % số vàng con quái rơi (trước cấp quái × 3: quái vùng chuyển sinh cấp 150 làm vàng gấp đôi).
- **C. Thuần phục** cả quái bản đồ phụ và vùng chuyển sinh (trừ trùm, chúa tể vùng chuyển sinh). Vùng k: công +3 % + 0,5 %·k,
  sức cắn 15 % + 1 %·k, giá × (1 + k). Thú thuần có 2 kỹ năng: Cắn Xé (cấp 5), Húc Ngã (cấp 15).
- **D. Cấp tối đa 10 → 20** (1.900 trận), chỉ số cộng +5 %/cấp (trước +10 %/cấp, nên cấp 20 ≈ cấp 10 cũ); kỹ năng thứ hai (`PETS.skill2`)
  ở cấp 15. **Cho ăn** ở Người Nuôi Thú (lệnh `pet_feed`, protocol thêm lệnh): 500 × cấp² vàng → +20 trận cho thú đang dắt.
  Thành tựu "Bậc Thầy Thuần Thú" (cấp tối đa) giờ cần cấp 20.
- **E.** Menu → Thú cưng và Người Nuôi Thú hiện tỉ lệ cắn, sức cắn, hai kỹ năng (đã học / khóa), giá cho ăn (`Engine.view/1` thêm
  `pets`, `tameable`, `taming`); Kho Đồ thêm mục Thú cưng.
- Đo (Kiếm Sĩ cấp 50, đồ +7, 300 trận với quái vùng 7; không thú: 6,1 lượt, mất 40 % máu), trước → sau:

  | Thú | Trước cấp 10 | Sau cấp 10 | Sau cấp 20 |
  |---|---|---|---|
  | Ác Quỷ Daemon (120.000) | 4,2 lượt, 23 % máu | 4,8 lượt, 28 % | 4,1 lượt, 23 % |
  | Chó Săn (3.000) | 4,5 lượt, 25 % | 5,2 lượt, 33 % | 4,9 lượt, 26 % |
  | Thú thuần quái vùng chính | 4,4 lượt, 25 % | 5,4 lượt, 33 % | 5,2 lượt, 28 % |
  | Thú thuần quái vùng 10 | — | 4,7 lượt, 27 % | 4,5 lượt, 23 % |
  | Sóc Túi: vàng mỗi con (970 khi không thú) | 1.980 | 1.244 | 1.334 |

  Thú mạnh nhất ở cấp 20 chỉ ngang cấp 10 cũ; thú đắt giờ hơn thú rẻ rõ rệt.

## Mô phỏng hành trình có thú cưng (2026-10-17)
- `mix hac_long.journey` cho bot nuôi thú (`--no-pets`, `--no-feed` để tắt): mua / thuần phục con mạnh hơn hẳn (≥ 10 %) khi giá ≤ 30 %
  vàng dư, dắt con mạnh nhất (điểm = phần cắn trung bình mỗi lượt + công + nửa thủ / máu cộng thêm), cho ăn khi vàng dư > 20 lần giá.
  Báo cáo ghi thú ở mỗi mốc, vàng tiêu cho thú, diễn biến mua / thuần / đạt cấp 5, 10, 15, 20.
- Kiếm Sĩ, 10 lần chuyển sinh + cày 1000 trận, seed 42: không thú → có thú: 7051 → 6880 trận, chết 204 → 55, lượt / trận các chặng
  sau 4,2 → 3,3. Bot mua Cừu Bông ở cấp 41 (vàng đầu game eo hẹp), Bằng Mã Lửa (40.000) ở chặng 1, thú đạt cấp 20 sau ~1.850 trận
  dắt theo; vàng dư không đủ để cho ăn (cần > 20 lần giá).

## Ép +7 → +11 chênh lệch lớn, +10/+11 không vỡ (2026-10-17, anh yêu cầu, em đề xuất số)
- +10, +11 (Máy Hỗn Nguyên) thất bại **về +0, không vỡ đồ** (`fail: "reset"`, không cần xác nhận nữa); tỉ lệ giảm: +10 50 % → **35 %**,
  +11 45 % → **25 %** (May mắn vẫn + 25 %). +7 → +9 giữ 50 %.
- Chỉ số cộng theo bảng `eff` của từng bước trong `UPGRADE` (`Engine.upgrade_eff/1`): cộng = eff × 8 % × chỉ số gốc món.

  | Cấp | +6 | +7 | +8 | +9 | +10 | +11 |
  |---|---|---|---|---|---|---|
  | Trước (% chỉ số gốc) | 48 | 56 | 64 | 72 | 88 | 104 |
  | Sau | 48 | 62 | 80 | 104 | 140 | 190 |
  | Bước nhảy sau (trước) | | +14 (+8) | +18 (+8) | +24 (+8) | +36 (+16) | +50 (+16) |

  +1 → +6 không đổi. Cánh: % sát thương / hấp thụ theo cấp vẫn như cũ (`effective_level/1`, từ +10 gấp đôi), chỉ phần thủ của cánh theo bảng mới.
- Mô phỏng hành trình giữ mặc định không ép +10/+11 (`--chaos-up` để bật): seed 42 bật thì bot thử +10 hai lần đều trượt, vũ khí +9 về +0.

## Ép +10/+11 khác biệt, cánh theo bậc (2026-10-17, anh chốt; thay cho mục "Ép +7 → +11 chênh lệch lớn" ngay trên)
- Đồ: +1 → +9 như cũ (8 %/cấp, +9 = 72 %); **+10 = 120 %, +11 = 180 %** chỉ số gốc (`UPGRADE.steps[].eff` 15 / 22,5).
- Tỉ lệ: +10 35 %, +11 25 %, thất bại về +0 (không vỡ). **May mắn theo bước** (`UPGRADE.steps[].luck`): +7 → +9 cộng 25 % (75 %),
  +10 / +11 chỉ cộng 10 % (45 % / 35 %) — May mắn dễ có (đồ rơi 10–35 %, Pha May mắn) nên không để +11 thành 50 %.
- Cánh (`RULES.wing_upgrade`, `Engine.wing_up/3`; bỏ `combat.wing_per_level`):
  - sát thương mọi bậc: +2 %/cấp tới +9, lên +10 thêm 12 %, lên +11 thêm 15 % (+11 = +45 %; cánh 3 +11 gây thêm 70 %);
  - hấp thụ theo bậc: cánh 1 +0,5 %/cấp, +3 %, +5 %; cánh 2 +0,75 %/cấp, +5 %, +7 %; cánh 3 +1 %/cấp, +7 %, +9 %; trần 50 %
    (+9 / +10 / +11: cánh 1 14,5 / 17,5 / 22,5 %, cánh 2 21,75 / 26,75 / 33,75 %, cánh 3 34 / 41 / 50 %); cánh 2 hấp thụ gốc 18 % → 15 %;
  - phòng thủ cánh theo bảng eff như đồ.
- Ảnh hưởng người chơi hiện có: đồ +10 / +11 mạnh lên; cánh đang ép giảm hấp thụ (vd cánh 3 +9 43 % → 34 %, cánh 2 +9 36 % → 21,75 %).

## Tầng Tháp / Quảng Trường / Lâu Đài / Kalima: quái đi lang thang, hiệu ứng bản đồ (2026-10-17, anh báo)
- Quái trên tầng riêng (`p.tower.monsters`) đi lang thang như bản đồ chung: Session hẹn `:tower_wander` mỗi `:wander_ms` (1,2 s) khi
  đang ở tầng và có tab mở, không trong trận, không bị giao dịch giữ; `Tower.wander/4`: mỗi con 35 % đi một ô sang ô trống `.`,
  không đè quái khác, không vào ô người chơi; trùm tầng (`elite`) đứng yên. Vị trí mới đẩy cho client như mọi thay đổi nhân vật.
- Hiệu ứng bản đồ (lá, tuyết, mưa, tro, sương) bật cả trên tầng, theo nền của tầng; không có ngày đêm (trong nhà).

## Chuyển sinh: thêm kinh nghiệm, điểm, điều kiện chúa tể (2026-10-17, anh chốt A + C, 25 điểm)
- **A.** Kinh nghiệm lên cấp × (1 + `character.rebirth_xp_pct` × số lần đã chuyển sinh), `rebirth_xp_pct` = 0,25
  (`Engine.xp_to_next/2`, `xp_need/1`; trần EXP trùm thế giới cũng theo `xp_need`).
- **C.** Từ lần chuyển sinh `rebirth_lord_from` (1): muốn chuyển sinh lần n + 1 phải từng hạ chúa tể vùng chuyển sinh n
  (đếm trong sổ quái; `Engine.rebirth_need/1`, `realm_lord/1`). Thẻ chuyển sinh ở Trưởng Làng ghi chúa tể còn thiếu và ẩn nút.
- **Điểm:** 15 → 25 điểm tiềm năng mỗi lần chuyển sinh (`rebirth_points`).
- Cả ba số sửa được trong `priv/game_data/rules.json` (`character`), khởi động lại server để có hiệu lực.
- Mô phỏng (seed 42, `tmp/journey_ac`): mỗi lớp ~12 900–16 200 trận (trước ~5 900), mỗi chặng 593 → ~1 760 trận; Kiếm Sĩ / Tiên Nữ chết
  ~13 lần. Pháp Sư kẹt chúa tể vùng 9 (thua 138 trận), Thuật Sĩ kẹt vùng 7–8 (thua ~290 trận): đánh một mình chúa tể vùng 7–10
  gần như không thắng (thử 200 trận ở cấp 50: Kiếm Sĩ 0 %, Pháp Sư 1 %, Thuật Sĩ 0 %). Sức chúa tể: đang hỏi anh
  (giữ khó để đánh cùng người khác hay giảm theo vùng).

## Vùng chuyển sinh 5 bản đồ (2026-10-17, anh yêu cầu "thêm mỗi vùng 4 bản đồ", chốt quái mạnh dần, chúa tể ở bản đồ 5)
- `RULES.realms.maps_per_realm` = 5, `depth_step` = 0,2 (version 4), sinh bằng `scripts/gen_realms.py`.
- Bản đồ 1 `realm_KK` giữ như cũ (cửa vào, Đài Phúc Lành, cổng vùng trước / sau), thêm cổng mép dưới vào `realm_KK_2` → … →
  `realm_KK_5` (tên "<vùng> 2…5"); bản đồ 2–5 không có Đài Phúc Lành. Vào bằng cổng hoặc Chọn bản đồ, cùng điều kiện vùng.
- Quái: 3 loài của vùng; bản đồ thứ n đánh như vùng k + 0,2 × (n − 1): hệ số máu / công / kinh nghiệm, `rich` (rơi đồ), ngọc
  và cấp hiện (+2 mỗi bản đồ) nội suy về phía vùng k + 1, nên bản đồ 5 vẫn yếu hơn bản đồ 1 vùng sau. (Đề xuất ban đầu
  +5 % / bản đồ; nội suy để vùng cao không vượt vùng sau — ví dụ vùng 9 bản đồ 5 +5 % × 4 sẽ mạnh hơn vùng 10.)
  Quái bản đồ 1 giữ id cũ (sổ quái, thú đã thuần không đổi); bản đồ sau `r<k>_<loài>_<n>` (`depth: n`), hình tô tối dần.
- Chúa tể dời sang bản đồ 5, sức vẫn theo vùng k, đánh dấu `lord: true` (trước nhận diện bằng `rich > k`, nay bản đồ sâu có
  `rich` lẻ nên đổi sang cờ: `Engine.realm_lord/1`, thú cưng, tháp, mô phỏng). Tháp tầng 61–160 chỉ dùng quái bản đồ 1.

## Mô phỏng hành trình: leo tháp, ép +10/+11 ở chặng cao (2026-10-17, anh yêu cầu mô phỏng đầy đủ hơn)
- Trước đó mô phỏng không leo tháp (không có kỹ năng tháp) và không ép +10/+11, nên nhân vật chuyển sinh cao yếu hơn người
  chơi thật. Thử chúa tể với cùng nhân vật (200 trận, chúa tể giữ nguyên sức): Pháp Sư chúa tể vùng 9 0 % → tháp 100: 84 %,
  +9 đủ 4 dòng + tháp 100: 98,5 %; Thuật Sĩ chúa tể vùng 8 0 % → tháp 50: 62 %, +9 + tháp 100: 99,5 %.
- `Journey` thêm: leo Tháp Vô Tận mỗi `tower_every` (300) trận từ cấp `tower_level` (30), từ tầng bắt đầu cao nhất đã mở,
  tối đa `tower_floors` (30) tầng / lần, dừng khi máu < 50 % sau một tầng hoặc thua; dùng `Tower.build/2`,
  `Tower.battle_monster/1`, `Tower.climb/1` (thưởng, ngọc mỗi 10 tầng, kỷ lục mở kỹ năng tháp). Ép +10/+11 tự bật từ lần
  chuyển sinh `chaos_from` (5). Tùy chọn `--no-tower`, `--tower-every`, `--tower-floors`, `--chaos-from`.
- Kết quả (seed 42, `tmp/journey_full`, 5 bản đồ / vùng, chúa tể giữ nguyên sức): mọi lớp xong 10 lần chuyển sinh trong
  12 200–12 800 trận (~16–20 giờ đánh), chết 8–22 lần; hạ chúa tể 26–32 lần, thua 3–6; kỷ lục tháp 49–59. Không còn chặng
  kẹt → **giữ nguyên sức chúa tể** (khó với người chơi chưa leo tháp / ép đồ, đúng ý ban đầu).

## Bot chọn kỹ năng, uống mana (2026-10-17, anh "sửa 2 điểm trên")
- (Bản đầu thêm công thức đổi 2 Tâm Linh → 1 Ước Nguyện; anh không muốn đổi ngọc → bỏ, thay bằng chỉnh tỉ lệ rơi, mục dưới.)
- Tiên Nữ ở tháp 100 thua chúa tể nhiều hơn tháp 50: không phải mất kỹ năng hồi máu (bộ vẫn có Phúc Lành) mà do MP — kỹ năng
  tháp 60–100 tốn 55–79 MP ở cấp 50, Tiên Nữ / Kiếm Sĩ chỉ có 83–113 MP; bot chỉ uống mana khi MP < 30 %. Sửa bot
  (`Brain.fight/1`): còn kỹ năng hết hồi chiêu mà không đủ MP thì uống bình mana; `Brain.loadout/2`: bỏ kỹ năng tốn hơn MP tối
  đa, giữ một kỹ năng hồi / hút máu, còn lại hệ số cao nhất. Tiên Nữ tháp 100 vs chúa tể vùng 9: 21 % → 54 % (tháp 50: 83 %).

## Tỉ lệ rơi Ước Nguyện (2026-10-17, anh: không đổi ngọc, chỉnh tỉ lệ rơi)
- Trọng số loại ngọc (`JEWELS.weights`, upgrade.json): Ước Nguyện 50 → **60**, Tâm Linh 35 → **25** (Hỗn Nguyên 15, Sinh Mệnh 10
  giữ nguyên, tổng không đổi nên số ngọc rơi như cũ). Mỗi viên ngọc rơi: Ước Nguyện 45 % → 55 %, Tâm Linh 32 % → 23 %.
- Lý do: mô phỏng đầy đủ thừa 33–56 Tâm Linh cuối hành trình, Ước Nguyện cạn nên giáp / trang sức kẹt +0…+4.

## MP kỹ năng tháp theo lớp (2026-10-17, anh chốt phương án B)
- Kiếm Sĩ / Tiên Nữ cộng Năng lượng chỉ được MP (không thêm công), MP cấp 50 ~80 / ~113, trong khi kỹ năng tháp tầng 100 tốn
  79 MP ở cấp 50. `RULES.tower_skills.mp_mult` = {dk: 0,5, elf: 0,6} nhân MP **kỹ năng tháp** (có `floor`) của lớp đó; kỹ
  năng lớp và lớp khác giữ nguyên (`Engine.skill_mp/2`, client `Logic.skillMp` nhận hệ số qua `RULES.towerSkills.mp_mult`).
  Kiếm Sĩ cấp 50: kỹ năng tầng 100 79 → 40 MP; Tiên Nữ 79 → 47 MP.
- Sổ ngọc mô phỏng (`JourneyReport` mục "Sổ ngọc"): mỗi lớp nhận ~250 Ước Nguyện cả hành trình, dùng 150–210 để ép +1…+6 — đủ
  ~40 món +6, nhưng đồ cuối vẫn +0…+4 vì mỗi chặng chuyển sinh rơi đồ bậc cao hơn, thay món đã ép. Bot đã thử ém ngọc (món phụ
  chỉ ép khi cấp ≥ 45 hoặc đánh vất vả) và thay đồ khắt khe hơn: tốn ngọc ít hơn nhưng chết nhiều gấp 3–10 lần → giữ mặc định
  (thay khi hơn 5 % + 2 % mỗi cấp ép). **Anh chốt (a): giữ nguyên** — đồ ép cao "dính" ở chặng cuối như MU; tỉ lệ Ước Nguyện 60 /
  Tâm Linh 25 giữ; không thêm chuyển cấp ép.

## Máy Hỗn Nguyên: Pha Excellent / May mắn thất bại giữ món (2026-10-17, anh: "cánh thì mất, còn lại không mất đồ")
- Công thức `mode` (Pha Excellent, Pha May mắn) thất bại: **giữ món đồ** (cấp ép, dòng không đổi), chỉ mất nguyên liệu + vàng;
  không hỏi xác nhận nữa. Công thức ra món mới (ghép cánh 1 / 2 / 3) vẫn mất món đồ bỏ vào (`Chaos.transform/4`).

## Tự đánh: thêm "Tất cả quái", đổi tên "Quái hợp cấp" (2026-10-17, anh yêu cầu)
- `AutoHunt` thêm `target: "all"` (mọi quái trên bản đồ), **mặc định mới**. `"level"` giữ nguyên cách lọc (cấp ≤ cấp mình + 1,
  không có thì mọi quái) nhưng đổi tên hiển thị "Quái không cao hơn mình (≤ cấp + 1)" — tên cũ "Quái hợp cấp" gây hiểu nhầm vì
  ở cấp cao / vùng chuyển sinh gần như đánh tất cả. Cài đặt đã lưu (`auto_cfg`) giữ lựa chọn cũ của người chơi.

## Quái sự kiện theo chuyển sinh (2026-10-17, anh "theo e đề xuất")
- Quái sự kiện làm cho cấp 35–50 chưa chuyển sinh (mạnh nhất ~×1,8), người chuyển sinh cao đánh quá dễ. `RULES.event_scale`:
  với k lần chuyển sinh của **người đánh** (tối đa `max_rebirths`): máu / thủ × (1 + 0,4k), công × (1 + 0,15k) — như vùng
  chuyển sinh — kinh nghiệm / vàng × (1 + 0,2k). `Engine.scale_event/1` gọi ngay khi vào trận: Quảng Trường Quỷ, Lâu Đài Máu,
  Kalima (trước `Tower.resume_hp`), bản đồ sự kiện (Hỗn Chiến Thành, Vương Miện) và quái vàng Golden Invasion (`World.encounter/3`).
- Đề xuất ghi "theo trung bình người trong phòng"; làm theo **người đánh** vì mỗi người đánh bản quái riêng (máu quái trên bản đồ
  chung lưu theo %), ai chuyển sinh nhiều gặp quái mạnh hơn, người mới vẫn đánh được. Trùm thế giới (máu chung cả server) và tháp
  (đã mạnh theo tầng) không áp.

## Bỏ Menu → Hành trình (2026-10-17, anh "ok làm đi")
- Mục Hành trình (tàn dư tab cũ: hồi máu, 6 trùm vùng, hết bình, giờ trùm thế giới, thẻ Chiến thắng) bỏ khỏi Menu.
- Giữ 2 phần có ích: **"Mục tiêu kế tiếp"** (Menu → Nhiệm vụ và Trưởng Làng): chưa chuyển sinh và dưới cấp tối đa → trùm vùng kế
  tiếp; sau đó → lên cấp tối đa / hạ chúa tể (kèm tên bản đồ, `view.rebirthNeed.map`) / đủ điều kiện chuyển sinh; chuyển sinh tối
  đa thì ẩn. **Giờ trùm thế giới xuất hiện** ở Bảng Tin và Menu → Nhiệm vụ.

## Cài đặt: tự hủy đồ rơi (2026-10-17, anh yêu cầu)
- Menu → Cài đặt thẻ "Tự hủy đồ rơi": bật thì món trang bị rơi (`Engine.gear_drop`) không thuộc loại nào trong danh sách "Giữ
  lại" bị bỏ ngay, không vào túi, ghi "🗑 Tự hủy …" — áp cả đánh tay lẫn tự đánh. Loại giữ lại và luật như lọc đồ của tự đánh
  (`AutoHunt.good?/3`: Excellent, Thần, May mắn / Kỹ năng, từ `keep_opt_min` dòng, tốt hơn đồ đang mặc, mặc được); nhẫn, dây
  chuyền, cánh, ngọc, nguyên liệu luôn giữ; đồ trùm rơi lần đầu (`boss_gear`) không lọc.
- Lệnh `loot_filter {on, keep}`; lưu theo nhân vật trong `auto_cfg["filter"]` (cột có sẵn, không cần migration); bật tự đánh
  không ghi đè mục này.

## Cài đặt: bỏ nút "Chơi lại từ đầu" (2026-10-17, anh hỏi "có cần không, không thì bỏ")
- Mỗi tài khoản một nhân vật; nút xóa vĩnh viễn toàn bộ tiến trình (cấp, đồ, kho, ngọc, chuyển sinh) không hoàn tác được, dễ bấm
  nhầm, và lợi ích duy nhất (đổi lớp / chơi lại) làm được bằng tài khoản mới. Bỏ nút và trạng thái xác nhận khỏi `ui.js`.
- Lệnh server `reset` (`commands.ex`) giữ lại cho test / quản trị; client không còn gửi.

## Icon ứng dụng (2026-10-17, anh yêu cầu "thêm avatar hình cho game")
- Ô tắt trình duyệt / màn hình chính hiện trống vì `favicon.ico` là ảnh trong suốt mặc định. Icon mới: hình trùm **Hắc Long**
  (`monsters/shadow_dragon.png`, CC0) phóng to kiểu pixel trên nền trắng, sinh bằng `node e2e/app_icons.mjs`.
- `priv/static/app/`: `icon-192/512.png`, `icon-maskable-512.png` (Android cắt hình), `apple-touch-icon.png` (iPhone),
  `favicon-32.png`; `favicon.ico` 64×64. `manifest.json` (tên, màu, icon; "Thêm vào màn hình chính" mở toàn màn hình).
  `static_paths` thêm `app`, `manifest.json`.
- Bản 2 (2026-10-18, anh "theo em đề xuất"): Chrome không hiện icon thẻ (giữ icon trống cũ), Brave vẽ rồng nhỏ, tối. Icon thành
  hình vuông kín nền tím sáng hơn, không viền / lề, rồng gần kín ô (trình duyệt, máy tự bo góc / cắt tròn; maskable vẫn chừa
  vùng an toàn). `favicon.ico` là ICO thật 16/32/48 (trước là PNG đổi đuôi). Đường dẫn icon / manifest thêm `?v=2` để trình
  duyệt tải lại; đổi hình lần sau thì tăng số này.
- Bản 3 (2026-10-18, anh "nền trắng ok hơn đen"): nền icon trắng (giữa trắng, mép tím rất nhạt), bóng rồng xám nhẹ thay ánh
  đỏ; đường dẫn `?v=3`.

## Quản trị: lệnh `reset_stats` (2026-10-18, anh "làm 1 thôi")
- Công thức "nhân vật admin tối đa" cộng dồn lên điểm / chỉ số đã cày nên mạnh hơn người chơi thật. Lệnh mới `reset_stats`
  (nút **Đặt lại chỉ số** ở Chỉnh nhân vật, hỏi xác nhận): chỉ số về gốc của lớp, điểm tiềm năng **đặt** bằng
  (cấp − 1) × điểm mỗi cấp + số lần chuyển sinh × `rebirth_points` (chỉ lên cấp và chuyển sinh cho điểm), chưa cộng.
- `docs/ADMIN_GUIDE.md` §6: `set_rebirths 10` → `set_level 50` → `reset_stats` (495 điểm, Thuật Sĩ Kiếm 593), bỏ
  `add_points 300` / `add_stats`; thêm đoạn tự chia điểm theo tỉ lệ gợi ý từng lớp (chỉ cho chính mình). Sửa "+3 điểm mỗi cấp"
  thành đúng 5 (Thuật Sĩ Kiếm 7). Vàng / đồ vẫn cộng thêm (anh chỉ chọn mục 1).

## Đổi chữ "đồ hiếm" thành "trang bị" (2026-10-18, anh "đồ chữ trắng, xanh vẫn được xem là đồ hiếm")
- Từ B-15 mọi trang bị rơi ra là một món riêng (có `uid`, dòng cộng thêm), nên "túi đồ hiếm" thật ra là túi trang bị: đồ trắng,
  xanh cũng nằm đó. Đổi mọi chữ người chơi thấy: "Túi trang bị đầy…", "Trang bị x/20" (Túi đồ, Tủ Đồ), lọc chợ "Trang bị",
  thư "Túi trang bị đầy: …"; bản tiếng Anh "Gear bag". Đồ Excellent / Thần vẫn có nhãn riêng. Tên nội bộ (`gear_log`, đối
  soát, tài liệu quản trị) giữ nguyên.

## Túi trang bị 40 (2026-10-18, anh "làm như em đề xuất")
- Giới hạn túi trang bị (món chưa mặc) từ số cứng 20 trong `Gear` (có từ thời túi chỉ chứa đồ hiếm) chuyển vào
  `rules.json` `RULES.loot.gear_bag`, tăng lên **40**: mọi món rơi giờ đều vào túi, ~32 món / giờ cày nên 20 đầy chưa tới
  một giờ. Client đọc `RULES.gearBag` như cũ. Tủ Đồ (20, mở rộng bằng vàng) không đổi.

## Deploy: truyền `HL_BOTS` vào container (2026-10-18)
- `docker-compose.yml` chưa truyền `HL_BOTS` nên đặt trong `.env` không có tác dụng (luôn 20 bot). Thêm `HL_BOTS: ${HL_BOTS:-}`;
  `config/runtime.exs` coi giá trị rỗng là chưa đặt (lấy `RULES.bots.count`). `.env.example`, `DEPLOY.md` ghi cách đặt.

## Bot mặc định 0 (2026-10-18, anh yêu cầu)
- `rules.json` `RULES.bots.count` 20 → **0**: server không chạy bot trừ khi đặt `HL_BOTS` (vd. `.env` `HL_BOTS=10`). Bot cũ
  trong database giữ nguyên, chỉ không chạy.

## Trang bị luôn là món riêng (2026-10-18, anh "làm đi")
- Trước: trang bị mua ở cửa hàng / thưởng / admin "Đồ thường" nằm xếp chồng trong `inv` (không tính túi), còn đồ rơi là món
  riêng (tính túi) → cùng một món mà hai kiểu, mua vô hạn không giới hạn túi. Nay mọi trang bị (vũ khí, giáp, khiên, nhẫn,
  dây chuyền, cánh) là **món riêng** trong túi trang bị (`Engine.add_item/3` → `Gear.add/2`, 0 dòng, túi đầy thì gửi Hộp
  thư); bình, ngọc, nguyên liệu, vé vẫn xếp chồng. Mua trang bị khi túi đầy bị từ chối. Đồ khởi đầu đang mặc cũng là món riêng.
- Dữ liệu cũ (`Engine.instance_gear/1`, chạy lúc nạp nhân vật, sau `split_upgrades`): đồ đang mặc mã loại → món riêng; chồng
  trang bị trong túi → từng món (dư thì `mail_out` → Hộp thư, không mất); chồng trang bị trong Tủ Đồ → món cất tủ.
- Lệnh gửi mã loại (`equip` / `sell` / `discard` / `lock` với `"item_1_0"`, công cụ / test cũ) dùng món riêng cùng loại đầu
  tiên trong túi (`Engine.bag_uid/2`). Thư cũ có trang bị mã loại cũng cần chỗ túi khi mở.
- Tab Quản trị: "Đồ thường (bình, ngọc, nguyên liệu, vé…)" không còn liệt kê trang bị; trang bị tặng ở "Trang bị".

## Quản trị `clear_bag` + chỉ số món đồ xuống dòng (2026-10-18, anh yêu cầu)
- Lệnh `clear_bag` (nút "Hủy trang bị trong túi", hỏi xác nhận): xóa mọi trang bị trong túi trang bị, cả món khóa và cấp ép
  của chúng; đồ đang mặc, đồ cất Tủ Đồ, bình / ngọc / nguyên liệu giữ nguyên.
- Bảng chi tiết món đồ (và Thư viện): mỗi chỉ số chính một dòng (cánh: phòng thủ / sát thương / nhận sát thương / lớp; nhẫn:
  máu / phòng thủ) thay vì nối " · ". Danh sách gọn (cửa hàng, chợ) vẫn một dòng. Tab Nhân vật / hồ sơ: dòng Cánh tách
  "+x% sát thương" và "−y% nhận" thành hai dòng.
- Form gửi quà (riêng / mọi người): mục "Đồ thường (bình, ngọc, nguyên liệu, vé…)" không còn liệt kê trang bị; trang bị gửi
  ở mục "Trang bị" (chọn món một dòng riêng, rồi số dòng "0–4 dòng", +N, số lượng). Giữ hai mục vì trang bị cần dòng / +N,
  đồ xếp chồng chỉ cần số lượng.
- Tab Quản trị → Trang bị: ô "dòng phụ cánh" chỉ hiện khi món chọn là cánh có dòng phụ (bậc trong `wing_options.by_tier`,
  hiện là cấp 2–3), ghi số của bậc đó (vd. "Cánh: máu tối đa +120"); client nhận bảng qua `RULES.wingOptions`.
- Tab Quản trị → Trang bị: ô tick Excellent chỉ hiện nhóm hợp món đang chọn (vũ khí / dây chuyền → "Excellent vũ khí /
  dây chuyền"; giáp, mũ, quần, găng, giày, khiên, nhẫn → "Excellent giáp / khiên / nhẫn"; cánh → không có), "Kỹ năng" chỉ
  với vũ khí, "Đồ Thần" chỉ với món thuộc bộ; đổi món thì bỏ tick các ô bị ẩn. Server `give_gear` cũng từ chối Excellent
  trên cánh (như rơi đồ: cánh không ra Excellent).
- Bộ hình Pixel: quần thay hình chân nhân vật Dungeon Crawl (`player/legs`, bị cắt / phóng nên xấu) bằng **CC0 Leggings
  Icons** (AntumDeluge, CC0, anh tải gửi; 9 hình 32×32 ở `assets_src/pixel_extra/leggings/`, nguồn trong `SOURCES.md`).
  `scripts/pixel_icons.py` đọc "extra:leggings/…" từ thư mục đó; dãy hình: Pháp Sư vải → áo choàng → quần lụa → giáp quỷ,
  Tiên Nữ da → lá rừng → giáp xanh, còn lại vải → da → xích → giáp tấm → giáp thép → giáp quỷ. Bỏ `e2e/crop_icons.mjs`.
- Bộ hình Pixel: cánh (trước dùng biểu tượng SVG) dùng đôi cánh Draconian của Dungeon Crawl (`player/drcwing`, CC0, anh
  chỉ nguồn), ghép sát hai cánh + căn giữa, để ở `assets_src/pixel_extra/wings/`. Màu theo lớp / bậc 1→3: Chiến Binh nâu →
  đỏ → tím, Pháp Sư trắng → vàng → xanh nhạt, Tiên Nữ lục → đốm → trắng, Đấu Sĩ xám → tím → đen.
- Hình MU (`mix hac_long.icons`): mũ (`item_7_*`), bình / ngọc (`item_14_*`) sau khi cắt viền được chừa thêm viền trong suốt
  (`-extent 118%`) để món đồ chiếm ~85% khung. Hình gốc của các món này chỉ ~20–60 px nên bị phóng 2–3 lần trên màn hình
  nét và nhòe; chừa viền làm món đồ nhỏ đi chút trong ô nhưng bớt nhòe (anh xem ảnh trước / sau và đồng ý). Máy chủ chạy lại
  `mix hac_long.icons` (hoặc `scripts/setup_items.sh`) để có hình mới.
- Hình MU mũ / bình / ngọc: đổi mức chừa viền từ ~85% sang **~75%** khung (`-extent 133%`, anh chọn).
- (anh "ok làm đi") **Thêm Kiếm Tổng Lãnh Thiên Thần** (Sword of Archangel, `0/19`) làm kiếm phụ bậc 11 cho Kiếm Sĩ + Đấu
  Sĩ (`item_0_19`, cấp 47, công 145, cùng giá / chỉ rơi như các món phụ bậc 11; yêu cầu str 49 agi 18) — B-17 từng bỏ vì
  trùng hình với đồ trùm Thánh Kiếm Diệt Long (`relic`). Không còn hình kiếm MU nào chưa dùng (`0/32`–`0/35` là găng đấm,
  `2/22` trống), nên `relic` giữ hình `0/19` nhưng luôn lấy **bản phát sáng** (`icon_variant: "e"` trong `items.json`, client
  `ownIcon`). Công thức nhân vật tối đa (ADMIN_GUIDE §6): vũ khí Kiếm Sĩ đổi từ Kiếm Lửa Lượn sang Kiếm Tổng Lãnh Thiên Thần.
- Công thức nhân vật tối đa (ADMIN_GUIDE §6) dựng theo **tên** (`NAME`, trống = chính mình): lớp lấy từ nhân vật được dựng
  (`lookup` trả thêm `character.cls`), không theo admin; chia điểm bằng `add_stats` + `add_points` (lệnh quản trị) thay cho
  lệnh người chơi `alloc`, nên dựng được cho người khác, online hay offline. Console in "Dựng cho: …" để kiểm đúng người.
- (anh "theo e đề xuất hết") **Bà Lang: đồ uống thay pha bình máu; món ăn giảm % kéo dài trận.**
  - Bỏ 6 công thức pha / nấu bình máu ở Bà Lang (bình vẫn mua ở Bà Lang). Thay bằng 4 đồ uống (`items.json`, `drink: true`,
    `slot: "food"`): Bia Thảo Dược (Thảo Dược ×3) vàng +8 %; Rượu Thuốc (Thảo Dược ×2 + Linh Chi) máu +6 %; Rượu Linh Chi
    (Linh Chi ×2) EXP +8 % — 30 trận; Rượu Long Huyết (Linh Chi ×3 + Cá Chép Vàng, nghề cấp 3) công +4 %, thủ +4 %, 40 trận.
    Pha cần cấp nghề Nấu ăn (`Crafting.brew/2`; sau đó đổi thành không cộng kinh nghiệm nghề, mục dưới).
  - Đồ uống nằm **ô riêng** `characters.drink` (migration `20261108000000_add_drink`), cộng dồn với món ăn; uống món khác thì thay.
  - Món ăn Bác Đầu Bếp (trước 10–20 % trong 5–10 trận, hết rất nhanh khi tự đánh): Chả Cá công +5 % 30 trận, Bánh Mì Cá thủ
    +6 % 30 trận, Bánh Xèo Lươn máu +6 % công +4 % 40 trận, Mâm Cỗ Cá Vàng EXP +10 % vàng +5 % 50 trận — ngang Đài Phúc
    Lành (+5 %, 30 trận). Hình đồ uống: chai thuốc CC0 của Dungeon Crawl (`assets/food/`, `CREDITS.md`).
- (anh "ok làm đi") **Nghề Nấu ăn chậm lại; món cá vàng mạnh hẳn.** Cá Chép Vàng cắn câu 1 % (hồ sâu 2 %), ~7–14 phút câu một
  con, nên hai món cần nó phải đáng công:
  - Mâm Cỗ Cá Vàng: EXP +10 %, vàng +10 %, công / thủ / máu +5 %, **100 trận**. Rượu Long Huyết: công +8 %, thủ +8 %, máu +5 %,
    **80 trận**. Hai món cùng lúc: +13 % công / thủ, +10 % máu. Món thường giữ nguyên.
  - Ngưỡng nghề Nấu ăn `RULES.crafting.cook_levels` = 0 / 20 / 60 / 120 / 200 (trước dùng chung `levels` 0 / 5 / 15 / 30 / 50 với
    Rèn; Rèn giữ nguyên). Kinh nghiệm theo công thức (`xp` trong `recipes.json`): Chả Cá, Bánh Mì Cá 1; Bánh Xèo Lươn 2; Mâm Cỗ 5;
    **pha đồ uống 0** (chỉ nấu ở Bác Đầu Bếp mới lên nghề). Cày riêng: cấp 3 ~40–60 phút, cấp 5 ~2,5–3,5 giờ.
  - Nhân vật đã có kinh nghiệm nghề giữ số lần nấu, cấp tính lại theo ngưỡng mới (có thể tụt cấp). Client nhận
    `RULES.craftLevels` dạng `{cook, smith}`.
- (anh "ok làm đi") **Nghề Rèn chậm lại, ít ra đồ 3 dòng hơn.** Trước: ngưỡng 0 / 5 / 15 / 30 / 50 lần rèn (~1,5–2,5 giờ hái
  quặng lên cấp 5), 3 dòng 6 % × cấp nghề (cấp 5: 30 %, quái rơi chỉ 3 %). Nay `RULES.crafting.levels` = 0 / 15 / 40 / 80 / 130
  (cấp 3 ~2 giờ, cấp 5 ~5–6 giờ cày riêng) và `smith_epic_per_level` = 4 (cấp 5: 20 %); 2 dòng 50 %, giá quặng / vàng và "luôn
  ít nhất 1 dòng" giữ nguyên. Cấp Rèn đã có tính lại theo ngưỡng mới. Kho Đồ thêm ghi chú rèn đồ (`{{SMITH}}`).
- (anh "ok nâng 2 cục đi") **Rèn vũ khí tốn 2 Quặng Mithril** (`RULES.crafting.smith_costs.weapon.ore_rare` 1 → 2; giáp, khiên giữ 1).
  Quặng Mithril hái từ cấp 18 (~25–40 giây một cục khi hái riêng), trước đó nút thắt chỉ là quặng thường.
- (anh "ok làm đi", chọn màu vàng, "thêm bến, thuyền, cầu") **Long Vương: thú hiếm duy nhất, câu ở Hồ Long Vương.**
  - Bản đồ mới `long_vuong_lake` (27 × 20, `priv/maps/long_vuong_lake.json`): hồ ở giữa, Vực Rồng (nước sâu) ở tâm, lối đi vòng
    quanh, 4 bến gỗ + một cầu bắc qua hồ có nhánh ra sát Vực Rồng, thuyền, sen, cây đước, đèn lồng, Miếu Long Vương có tượng rồng
    vàng. Không có quái, không PK (không phải bản đồ sự kiện, không có quái để đánh). Cổng ở mép trái Rừng Mê 1; cũng có trong
    bảng Chọn map. Vào từ **cấp 30** (`min_level`; trước đây chỉ vùng chuyển sinh có `min_level`, nay bản đồ thường không quái cũng
    dùng: cổng chặn, `World.min_level/1` trả cấp này để tính giá dịch chuyển).
  - Ô mới (`Maps.@legend`): `=` nước sâu, `M` cây đước, `Q` sen, `U` thuyền (đều là nước, đứng cạnh câu được), `B` / `E` bến / cầu
    gỗ (đi được), `G` tượng rồng, `J` đèn lồng. Hình: `scripts/long_vuong_assets.sh` (CREDITS).
  - Bảng cá `RULES.fishing.pools.lake`: ủng 5, Cá Diếc 25, Cá Chép 35, Lươn Điện 32, **Cá Chép Vàng 3** (hồ sâu 2, hồ thường 1).
  - `RULES.fishing.dragon`: mỗi lần **thả câu** ở hồ có 1/20.000 cơ hội Long Vương cắn (quyết định lúc thả, client hiện "Có gì đó rất
    lớn…", khung rung); giật đúng lúc thì được, trễ thì "dây câu đứt". Có **Mồi Rồng** trong túi: mỗi lần thả tốn 1 mồi, 1/10.000.
    Mồi pha ở Bà Lang: Cá Chép Vàng + 3 Linh Chi → **100 mồi** (công thức có `n`), cần nghề Nấu ăn cấp 3, không cộng kinh nghiệm nghề.
  - Mỗi nhân vật tối đa 1 con; đã có thì lần đó ra Cá Chép Vàng. Không bán (`PETS.rare`), không tính vào thành tựu "đủ thú".
  - Chỉ số (`pets.json`): công +10 %, thủ +8 %, máu +8 %, EXP +5 %, vàng +5 % (×1,95 ở cấp 20), sức cắn 45 %. Kỹ năng: **Thủy Long Ba**
    (cấp 5, cắn ×2 và quái choáng 1 lượt, mỗi 3 lượt một lần), **Long Lân Hộ Thể** (cấp 15, giảm 10 % sát thương nhận, mỗi lần cắn hồi
    5 % máu), **Long Vương Hồi Sinh** (cấp 20 = `RULES.pets.skill3_level`, mỗi trận một lần gục thì sống lại 30 % máu). Số ở
    `RULES.pets.skills` (`tidal_*`, `scales_*`, `rebirth_hp`).
  - **Bia Long Vương**: bảng `rare_pets` (migration `20261109000000_create_rare_pets`, `HacLong.RarePets`), đánh số theo thứ tự;
    câu được thì báo cả server "… Long Vương Chủ thứ #n", thành tựu + danh hiệu **Long Vương Chủ**. NPC Ông Lão Câu Cá và Bia Long
    Vương (role `dragon`) hiện tỉ lệ, số mồi, kỹ năng và bảng tên (lệnh `dragon_board`).
- (anh "cập nhật admin để cấp thú nuôi này") **Lệnh quản trị `give_pet`** (`id` thú trong `PETS` kể cả `long_vuong`, `level` 1..20):
  tặng thú, đặt cấp thú, dắt theo luôn; đã có thì chỉ đặt lại cấp. Tab Quản trị có mục **Thú cưng** (🐉 Long Vương đầu danh sách),
  công thức nhân vật tối đa (ADMIN_GUIDE §6) thêm Long Vương cấp 20 + 100 Mồi Rồng. Thú quản trị tặng **không** ghi Bia Long Vương
  và không báo cả server (bia chỉ dành cho người tự câu được); thành tựu / danh hiệu Long Vương Chủ vẫn có (tính theo thú đang có).
- (anh "làm 1-6") **Hiệu ứng câu cá và Hồ Long Vương** (chỉ client, `map.js` + `ui.js`, không đổi luật; game vẽ bằng Canvas 2D, không
  dùng Phaser). Câu ở mọi hồ: cần + dây + phao (ném theo đường cong, vòng gợn, nhấp nhô), cắn câu (phao chìm, dấu ! nảy, nước bắn,
  bản đồ rung nhẹ; Long Vương quầng vàng, rung mạnh), câu được (cá bay vòng cung xoay tròn, lấp lánh; Cá Chép Vàng / Long Vương có
  cột sáng và sao, Long Vương hiện hình rồng lớn), Ủng Cũ (ủng bay to dần vào màn hình, 💫 trên đầu, quạ bay ngang). Hồ Long
  Vương (`fish: "lake"`): bóng cá lượn (trang trí, không liên quan tỉ lệ), xoáy Vực Rồng, lá / hoa rơi ban ngày, tia nắng lúc sáng
  sớm / chiều tà, đèn lồng sáng ban đêm. Theo công tắc hiệu ứng (`hl-fx`) và "giảm chuyển động". Không làm "cá to kéo lê nhân vật"
  (vị trí do server quyết) và chưa cho người khác thấy phao của mình.

## Long Vương nổi mỗi giờ (thay 1/20.000 mỗi lần thả)

Anh chọn (bước 1): thay cơ hội 1/20.000 ở mọi lần thả câu bằng một lần **Long Vương nổi** mỗi giờ để người chơi có lúc hồi hộp và có
việc để làm ở hồ ngoài lúc đó.
- `HacLong.LakeEvent` (GenServer, trong bộ nhớ): mỗi `RULES.fishing.dragon.every` = 3600 giây, vào một lúc ngẫu nhiên trong giờ, Ngài
  nổi ở một ô nước ngẫu nhiên của Hồ Long Vương (ô trong tầm `reach` = 3 ô của một ô đi được cạnh nước, tức câu tới được), ở lại
  `stay` = 180 giây. Có người câu được (`Session.rare_pet` gọi `dive/0`) hoặc hết giờ thì lặn. Mọi người nhận `lake` (`{tile, left}`)
  qua kênh; client vẽ bọt vàng + bóng rồng ở ô đó (cả khi tắt hiệu ứng, chỉ không động) và báo người đang ở hồ.
- Thả câu gửi ô nước đã chọn (`fish_cast` có `x`, `y`; nút Câu cá gửi ô phao mặc định). Server kiểm ô là nước, trong tầm `reach`.
  Chỉ lần thả **trúng đúng ô Ngài** ở hồ mới có cơ hội `chance` = 1/2.000 × (1 + Long Khí / `long_khi_div` 100) × `bait_mult` 2 nếu có
  Mồi Rồng; mồi **chỉ tốn khi thả trúng ô Ngài**.
- **Long Khí** (`characters.long_khi`, migration `20261110000000_add_long_khi`): +1 mỗi con cá (kể cả Cá Chép Vàng nhả lại) câu được ở hồ,
  tối đa `long_khi_max` 200, về 0 khi câu được Ngài. Hiện ở thanh câu cá và thẻ Long Vương (cơ hội hiện tại).
- Đầy Long Khí + mồi: 1/333 mỗi lần thả trúng ô; ~20 lần thả trong 3 phút ≈ 5,8 % mỗi lần nổi, trung bình ~17 lần nổi (~17 giờ nếu lần
  nào cũng có mặt). Quản trị: `lake_summon` gọi Ngài nổi ngay. Test: `config :hac_long, :lake_event, auto: false`.
- Bước 2: xem "Đàn Cá Vàng, việc của Ông Lão".

## Đàn Cá Vàng, việc của Ông Lão

Anh chọn (bước 2 của "Long Vương nổi mỗi giờ"), để thời gian giữa các lần Ngài nổi vẫn đáng ở hồ:
- **Đàn Cá Vàng** (`RULES.fishing.school`): `HacLong.LakeEvent` hẹn thêm sự kiện thứ hai, mỗi `every` = 900 giây vào lúc ngẫu nhiên,
  hiện ở một ô câu tới được (khác ô Ngài nếu Ngài đang nổi) trong `stay` = 120 giây; không tan khi có người câu. Thả trúng ô đó:
  `gold_chance` = 15 % ra Cá Chép Vàng (còn lại theo bảng cá hồ, Cá Chép Vàng 3 %), mỗi con cá +`long_khi` = 3 Long Khí thay cho +1.
  Client vẽ cá vàng lượn + viền chấm, báo người đang ở hồ. Quản trị: `lake_school`.
- **Việc của Ông Lão** (`RULES.fishing.elder`): câu `count` = 30 con cá ở hồ trong ngày (ủng cũ không tính; đếm ở `daily.lake_n`, cùng
  ngày với việc ở Bảng Tin nên không cần migration) rồi gặp Ông Lão (thẻ trên Long Vương) nhận một lần: vàng / kinh nghiệm theo công
  thức việc câu cá ở Bảng Tin (`daily.reward.fish`, theo cấp nhân vật, × 30 con) và +`long_khi` = 20 Long Khí. Lệnh `elder_claim`.
- Ủng cũ không còn cộng Long Khí (chỉ cá).

## Đăng nhập nhanh hơn, quên mật khẩu, hồ sơ, Tiên Nữ

- **Đăng nhập nhanh hơn:** `pbkdf2_elixir` tự lặp 160.000 vòng HMAC bằng Elixir (~0,6 giây mỗi lần đăng nhập / đăng ký).
  `HacLong.Accounts.Password` dùng `:crypto.pbkdf2_hmac/5` (C trong OTP): cùng thuật toán, số vòng, định dạng hash nên tài khoản cũ
  vẫn đăng nhập được, ~0,13 giây (đo ở máy dev). Nút đăng nhập / tạo tài khoản đổi chữ "Đang đăng nhập…" ngay khi bấm.
- **Quên mật khẩu:** tài khoản không có email nên không gửi mail được. Màn đăng nhập có "Quên mật khẩu?": người chơi để lại tên
  đăng nhập + cách liên lạc (`POST /api/forgot`, giới hạn 5 lần/giờ/IP, luôn trả ok để không lộ tài khoản có tồn tại không; mỗi
  tài khoản một yêu cầu chờ). Bảng `password_resets` (migration `20261111000000`). Quản trị đặt lại → mật khẩu tạm 8 ký tự, thu hồi
  mọi token, đăng xuất mọi thiết bị; mật khẩu tạm không ghi vào `admin_log`.
- **Hồ sơ:** phần Trang bị dùng lưới ô y như Túi đồ → Trang bị đang mặc (viền loại đồ, viền +N, ô Thú nuôi; thú hiếm như Long
  Vương có viền vàng xoay). Profile gửi thêm `pet_id`, `pet_lv`. Viền +7 / +9 giờ cũng nhấp nháy nhẹ (+11 vẫn mạnh nhất), ở mọi chỗ
  có ô đồ.
- **Tiên Nữ hình nữ:** thân `base/elf_f` + tóc `hair/fem_yellow` (Dungeon Crawl CC0); `classes.json` thêm `body`, `Engine.look`
  gửi `body`, `doll.js` dùng `look.body` thay thân nam mặc định.

## Hiệu ứng trận đánh và di chuyển (FX_PLAN đợt 1 + một phần đợt 5)

- `priv/static/js/fx.js` (`BattleFx`): canvas trong suốt phủ màn hình (`#bfx`, không bắt chuột), vị trí lấy từ hình quái / nhân
  vật trong bảng trận lúc phát, nên mọi chế độ dùng bảng trận đều có. Chỉ là hình, server vẫn quyết định kết quả.
  - Đòn thường theo lớp: Kiếm Sĩ / Đấu Sĩ hai vệt chém, Tiên Nữ tên bay, Phù Thủy cầu phép; nhân vật nhún tới; quái chớp trắng,
    hạt tung; chí mạng: chữ "CHÍ MẠNG!", vòng to, rung bảng. Trượt: quái né sang bên.
  - Kỹ năng theo hệ: lửa (cầu lửa + tàn lửa bay lên), sét (3 tia từ trên + chớp màn hình), gió (3 lưỡi gió + xoáy), đất (đá rơi +
    bụi + rung), bóng tối (cầu tím + co lại), ánh sáng (cột sáng). Kỹ năng lên mình (hồi máu, tăng sức) có vòng sáng + dấu "+".
  - Quái đánh mình: vết cào đỏ + viền đỏ màn hình. Quái gục: tan thành hạt, vàng bay về số vàng trên đầu trang.
    Thanh máu quái có lớp trắng trễ chạy theo.
  - Tự đánh / đánh chung: suy ra từ máu hai bên khi server đẩy trạng thái trận mới.
- Bản đồ (`map.js` `moveFx`): bụi bước chân (gợn nước khi đi trên bến / cầu gỗ), vòng sáng ở ô vừa chạm để đi tới, cột sáng khi
  vừa sang bản đồ mới.
- Theo công tắc hiệu ứng (`hl-fx`) và "giảm chuyển động". Hướng C (người khác thấy mình đánh trên bản đồ) cần server gửi thêm sự
  kiện, chưa làm.

