# KB_BASE_REPO — Repo nền tham khảo: Hắc Long RPG (IMPLEMENTATION)

> Repo: https://github.com/biennguyen94/rpg-game — Elixir + Phoenix + PostgreSQL, client JS thuần, game nhập vai **theo lượt**, tối ưu điện thoại.
> Dùng làm **nền để tái sử dụng code, tính năng và UI**, không phải để sao chép nguyên xi.
> Bổ sung cho `KB_TECH_STACK.md` (kiến trúc). File này trả lời: *module nào tái dùng, sửa, viết lại, bỏ*.

## 0. Độ tin cậy & điều kiện sử dụng

### 0.1. Quyền sử dụng (đã xác nhận)

- **Chủ repo** (`biennguyen94/rpg-game`) là chủ dự án này và **cho phép toàn quyền dùng lại**: copy, sửa, viết lại, tích hợp, và mọi hoạt động khác liên quan tới code do chủ repo viết. Câu hỏi B1 **đã đóng**. Agent **không cần** xin phép từng module và **không** coi việc repo thiếu `LICENSE` là rào cản.
- Ghi nhận này do chủ repo tuyên bố trong cuộc trao đổi; **không** có file `LICENSE` trong repo (danh sách file gốc xác nhận lại: có `CREDITS.md`, `README.md`, `Dockerfile`, `mix.exs`…, không có `LICENSE`). Khuyến nghị chủ repo **thêm `LICENSE`** (hoặc một dòng "all rights reserved by owner, reuse permitted in project X") vào repo để người ngoài và công cụ tự động không hiểu nhầm. Chưa làm thì quyền trên vẫn có hiệu lực với dự án này.
- **Phạm vi:** chỉ áp cho **code do chủ repo viết**. **Không** áp cho tài sản bên thứ ba trong repo:
  - Hình quái/tile từ Dungeon Crawl Stone Soup: **CC0** (README).
  - Icon từ game-icons.net: **CC BY 3.0**, **bắt buộc ghi tên tác giả**. Chủ repo không có quyền miễn điều kiện này. Dự án này dùng icon item do bạn cung cấp (`KB_ASSETS §2.1`), nên **không** lấy icon game-icons.net cho item.
  - Thư viện trong `mix.lock` giữ license riêng của chúng.
  - Nếu repo có người đóng góp khác (README/GitHub không liệt kê), phần của họ cần xác nhận riêng (B5).

### 0.2. Nguồn thông tin

- **Đã đọc:** `README.md` (nội dung, kiến trúc, cấu trúc thư mục, giao thức, cách chạy/sản xuất) và danh sách file gốc. Repo công khai, nhánh `main`, 51 commit.
- **Chưa đọc:** source code `lib/`, `test/`, `priv/`, `CREDITS.md`, `docs/DEPLOY.md`, `docs/ROADMAP.md` (`CREDITS.md` lần tải gần nhất vẫn lỗi 503). Tên module/hàm dưới đây lấy từ README.
- Có quyền dùng lại **không** có nghĩa là bỏ qua việc đọc: vẫn **mở file thật và đọc test** trước khi quyết định REUSE/ADAPT/REWRITE (§1, B3), vì README có thể lệch với code.
- Cố định một commit khi bắt đầu tái dùng (B2) để code đọc được không đổi dưới chân.


## 1. Quy tắc cho AI Agent

1. Trước khi tái dùng một module: **mở file thật**, đọc cả test của nó, rồi mới quyết định REUSE / ADAPT / REWRITE.
2. Nội dung KB (`KB_GAME_DESIGN`, `KB_CONFIG`, `KB_TECHNICAL`) **thắng** repo khi mâu thuẫn. Repo chỉ là nguồn code.
3. Mỗi module tái dùng ghi một dòng vào `docs/REUSE_LOG.md`: file nguồn, commit, mức thay đổi (REUSE/ADAPT/REWRITE), lý do. (Dùng để theo dõi nguồn gốc và thay đổi, **không** phải thủ tục xin phép.)
4. Code của chủ repo: được copy/sửa tự do (§0.1); giữ nguyên ghi chú tác giả nếu có. **Asset và thư viện bên thứ ba vẫn theo license riêng**; asset phải ghi vào `CREDITS.md` ngay khi thêm (CC BY 3.0 của game-icons.net bắt buộc ghi tên).
5. Không kéo tính năng ngoài scope phase hiện tại (`KB_00_RULES §7`) chỉ vì repo đã có sẵn.

## 2. Khác biệt cốt lõi với KB này

| Mục | Repo nền | KB này |
|---|---|---|
| Chiến đấu | Theo lượt: bước vào quái → trận (tấn công, kỹ năng, uống máu, bỏ chạy) | Real-time: click-to-attack, cooldown, tầm đánh |
| Di chuyển | Từng ô, ~11 bước/giây, server kiểm tra từng bước | Tick-based (`KB_TECH_STACK §3`, phương án A) |
| Multiplayer | Thấy người cùng bản đồ; chưa có AOI | Phase 1 broadcast đơn giản, AOI ở Phase 3 |
| Nhân vật | 3 lớp, 1 nhân vật/tài khoản | DK trước; DW, Elf, MG về sau |
| Client | JS thuần (`ui.js`, `map.js`, `net.js`, `sound.js`, `doll.js`) | Phaser 3 + TypeScript, layout `KB_GAME_DESIGN §19` |
| Auth | Token ngẫu nhiên, băm lưu DB, vào socket bằng `?token=` | Token opaque + WS ticket một lần trong ETS (`KB_TECHNICAL §4`) |
| Mật khẩu | PBKDF2 | Argon2id |
| Vật phẩm | Chỉ số ngẫu nhiên, không serial | Serial theo stack, `item_locations`, audit log (`KB_TECHNICAL §9`) |

## 3. Bảng tái sử dụng theo module

Mức: **REUSE** (dùng gần như nguyên), **ADAPT** (giữ khung, sửa), **REWRITE** (chỉ học ý tưởng), **SKIP** (không dùng).

### 3.1. Hạ tầng & server

| Module (theo README) | Làm gì | Mức | Phase | Ghi chú |
|---|---|---|---|---|
| `Dockerfile`, `docker-compose(.caddy).yml`, `deploy/`, `rel/overlays`, `docs/DEPLOY.md` | Deploy Docker + Caddy | REUSE | 1 | Chỉnh tên app/biến môi trường |
| `.github/workflows/ci.yml` | CI: format, biên dịch không cảnh báo, `mix test` | REUSE | 1 | |
| `hac_long_web/remote_ip.ex` | Lấy IP thật qua `X-Forwarded-For` + `TRUSTED_PROXIES` | REUSE | 1 | |
| `hac_long/rate_limit.ex` | Giới hạn tần suất đăng nhập, chat, thao tác | REUSE | 1 | Thêm giới hạn theo từng `act` (`KB_TECHNICAL §5`) |
| `hac_long/accounts.ex` | Đăng ký, đăng nhập, token băm, đăng xuất mọi thiết bị, đổi mật khẩu | ADAPT | 1 | Đổi PBKDF2 → Argon2id; thêm WS ticket |
| `hac_long_web/channels/` (`UserSocket`, `GameChannel`) | Socket + kênh `"game"` | ADAPT | 1 | Đổi sang ticket; payload theo `KB_TECHNICAL §5` (`rid`, event `error`) |
| `hac_long/game/session.ex` | 1 tiến trình / tài khoản, xử lý lệnh tuần tự, lưu sau mỗi thay đổi, idle 10 phút thì tắt | ADAPT | 1 | Khung giống `KB_TECH_STACK §2`; thêm idempotency theo `rid` |
| `hac_long/game/commands.ex` | Validate lệnh từ client → gọi engine | ADAPT | 1 | Thêm các act mới (`unequip`, `npc_open`, …) |
| `hac_long/game/characters.ex` | Đọc/ghi bảng characters | ADAPT | 1 | Thêm `items`, `item_locations`, `free_stat_points` |
| `hac_long/game/data.ex` + `priv/game_data.json` | Nạp dữ liệu game từ JSON | ADAPT | 1 | KB tách JSON theo loại (`classes`, `monsters`, `items`, …) |
| `hac_long/game/names.ex` | Chuẩn hóa/kiểm tra tên nhân vật | ADAPT | 1 | Quy tắc tên theo CHECK `^[A-Za-z0-9]{4,10}$` |
| `hac_long/world/map_server.ex`, `world/maps.ex`, `world.ex` | 1 tiến trình / bản đồ giữ quái + người chơi; đọc bản đồ; cổng | ADAPT | 1 | Thêm vòng tick real-time; ai đến trước đánh trước vẫn dùng được |
| `priv/maps/*.json` + test cổng nối hai chiều | Bản đồ dạng ký tự + kiểm tra hợp lệ | ADAPT | 1 | Giữ test; nguồn bản đồ của KB là Tiled `.tmj` |
| `hac_long/game/simulator.ex`, `mix hac_long.simulate` | Bot chơi thử để cân bằng | ADAPT | 1–2 | Viết lại phần chiến đấu cho real-time; giữ khung báo cáo |
| `lib/mix/tasks/` (`hac_long.admin`) | Cấp/thu hồi quyền admin | REUSE | 2 | |

### 3.2. Luật chơi

| Module | Làm gì | Mức | Phase | Ghi chú |
|---|---|---|---|---|
| `hac_long/game/engine.ex` | Luật chơi bằng hàm thuần (`derived`, `make_monster`, `damage`) | **REWRITE** | 1 | Giữ phong cách hàm thuần + test. Công thức theo `KB_GAME_DESIGN §4`, `§4.1`; thêm cooldown, tầm đánh, hit/crit |
| `hac_long/game/gear.ex` | Đồ chỉ số ngẫu nhiên (Tốt, Hiếm, Sử Thi) | ADAPT | 2 | Phải gắn serial/`item_locations` |
| `hac_long/game/crafting.ex`, upgrade ở Thợ Rèn | Nâng cấp đến +5 | REWRITE | 5 | KB dùng bảng tỉ lệ `KB_CONFIG §5` và Jewel |
| `hac_long/game/quests.ex`, `daily.ex` | Nhiệm vụ, việc hằng ngày | ADAPT | 6 | |

### 3.3. Xã hội & kinh tế

| Module | Làm gì | Mức | Phase | Ghi chú |
|---|---|---|---|---|
| `hac_long/chat.ex` | Chat thế giới, giữ 50 tin | ADAPT | 2 | Kênh theo `KB_TECHNICAL §5` |
| `hac_long/mailbox.ex` | Hộp thư: thư kèm quà, mở thư nhận quà | ADAPT | 2 | Khớp `KB_GAME_DESIGN §19.10`; quà item qua audit log |
| `hac_long/moderation.ex` | Chặn, báo cáo, cấm chat, khóa tài khoản | ADAPT | 2 | |
| `hac_long/party.ex` | Tổ đội tối đa 3 người | ADAPT | 3 | Chia thưởng giữ được; phần "đánh chung trận theo lượt" viết lại |
| `hac_long/guilds.ex`, `guild_quests.ex` | Bang hội, quỹ, nhiệm vụ tuần | ADAPT | 4 | |
| `hac_long/trade.ex`, `game/trade_offer.ex` | Giao dịch trực tiếp, hai bên xác nhận; kiểm tra bằng hàm thuần | ADAPT | 5 | Khung hợp với `TradeSettlement`; thêm transaction DB, lock theo `item_id`, audit |
| `hac_long/market.ex` | Chợ giữa người chơi | ADAPT | 5+ | Ngoài scope hiện tại của KB |
| `hac_long/leaderboard.ex` | Bảng xếp hạng | ADAPT | 6 | |
| `hac_long/world_boss.ex` | Trùm thế giới: lịch, máu chung, chia thưởng theo sát thương | ADAPT | 6 | |
| `hac_long/arena.ex` | PvP bất đồng bộ (bản sao chỉ số, Elo) | SKIP | — | KB dùng PvP real-time (`KB_GAME_DESIGN §13`) |

### 3.4. Client & UI

| Thành phần (`priv/static`) | Làm gì | Mức | Ghi chú |
|---|---|---|---|
| `js/net.js` | Phoenix channel, tự kết nối lại, thanh báo mất mạng | REUSE (ý tưởng + code) | Đổi sang ticket và `rid` |
| `js/sound.js` | Nhạc/SFX tổng hợp bằng Web Audio, đổi theo nơi đang đứng, bật/tắt riêng | REUSE | Không cần file audio ở Phase 1 |
| `js/doll.js` | Vẽ nhân vật theo `look` (tóc, vũ khí, áo, khiên, thú) | ADAPT | Chuyển sang layer sprite Phaser (`KB_ASSETS §4`) |
| `js/map.js`, `js/ui.js`, `index.html`, `css/` | Bản đồ ô vuông, các panel, mobile-first | REWRITE | Layout mới theo `KB_GAME_DESIGN §19` (dock, full-screen panel, context menu quái) |
| Hình quái/tile DCSS trong `assets/` | Sprite quái, tile | REUSE có điều kiện | CC0 theo README; theo `KB_ASSETS §2.1`; xác nhận từng file qua `CREDITS.md` (B4). Quyền của chủ repo không thay đổi license của asset |

### 3.5. Tính năng của repo nằm ngoài KB (mặc định không làm)

Tháp Vô Tận, câu cá, thú cưng, trang trí nhà, nghề (nấu ăn/rèn), lễ hội theo mùa, Sổ tay quái vật, chuyển sinh, thành tựu/danh hiệu, hướng dẫn người mới, bạn bè/nhắn tin riêng, đấu trường Elo, đá dịch chuyển.
Muốn thêm: đưa vào `KB_00_RULES §7` thành phase trước, rồi mới tái dùng module tương ứng.

## 4. Protocol — chỗ khớp và chỗ lệch

Khớp với `KB_TECHNICAL §5`: kênh `"game"`, `push "cmd"` với `{act, ...}`, server đẩy `"player"` (nhân vật + `view` tính sẵn) và `"map"` (quái, người chơi), chat đẩy riêng. Client chỉ gửi ý định.

Lệch, cần sửa khi tái dùng:
- Repo trả `{ok, msg?, result?, player}` cho mỗi `cmd`; KB dùng `rid` + event `error` `{rid, error}` + mã lỗi (`KB_TECHNICAL §5`).
- Repo vào socket bằng `?token=`; KB dùng WS ticket một lần (`KB_TECHNICAL §4`).
- Danh sách `act` của repo thiên về turn-based (`attack`, `skill`, `potion`, `flee`, `leave`); KB cần `move_to`, `attack {target}`, `use_item`, `equip`, `unequip`, … (`KB_TECHNICAL §5`).

## 5. Các lô công việc gợi ý (Phase 1)

1. Bộ khung: auth, socket, `Session`, `Commands`, rate-limit, Docker, CI — chủ yếu REUSE/ADAPT.
2. Dữ liệu & map: JSON dữ liệu, bản đồ, test cổng/spawn — ADAPT.
3. Engine real-time cho Spider/DK — REWRITE.
4. Client Phaser + UI §19 — REWRITE, chỉ lấy `net.js`, `sound.js`, `doll.js` làm tham khảo.

## 6. Open questions

| # | Câu hỏi | Mặc định tạm |
|---|---|---|
| B1 | ~~Chủ repo có cho phép dùng lại code không?~~ **Đã trả lời:** có, toàn quyền (§0.1). Repo không có `LICENSE` | — |
| B2 | Commit nào làm mốc? | Ghi hash khi clone lần đầu |
| B3 | Đọc source để xác nhận tên module/hàm trong §3 (hiện chỉ dựa README) | Bắt buộc **trước khi chọn** REUSE/ADAPT/REWRITE cho từng module; không còn bị chặn bởi license |
| B4 | `CREDITS.md` của repo ghi gì cho từng asset? | Chưa đọc được (lỗi 503, đã thử lại). Tạm dùng README: DCSS = CC0, game-icons.net = CC BY 3.0 |
| B5 | Repo có đóng góp (code/asset) của người khác ngoài chủ repo không? | Giả định không; nếu có, xin xác nhận riêng cho phần đó |
| B6 | Có thêm file `LICENSE` vào repo để ghi nhận quyền ở §0.1 không? | Khuyến nghị có; chưa bắt buộc |