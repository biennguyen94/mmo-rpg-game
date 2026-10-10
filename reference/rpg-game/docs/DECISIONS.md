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
| P10-3 | Bản dịch đầu do máy dịch theo bảng thuật ngữ (Kiếm Sĩ = Dark Knight, Ngọc Phúc Lành = Jewel of Bless…), kiểm tự động giữ đúng {n}. | Nhanh; anh / người chơi góp ý thì sửa thẳng `en.json`. |

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
  - Cách trả giữ nguyên luật T20–T25: cược S, cần ≥ 10×S vàng để được chia bài; tiền hạng, chặt heo / chặt chồng, thối heo, tới trắng; thiếu vàng thì trả tối đa số đang có, chia theo tỉ lệ.
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
  - lần đầu mỗi ngày hạ một trùm vùng: vùng 1–3 +1 Ngọc Phúc Lành, vùng 4–6 +1 Ngọc Linh Hồn (ghi trong `daily.bosses`).
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
