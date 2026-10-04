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
