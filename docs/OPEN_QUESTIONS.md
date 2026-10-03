# OPEN_QUESTIONS — Câu hỏi mở (M0)

> Cách đọc: mỗi câu có **đề xuất mặc định**. Anh trả lời "OK" cho cả nhóm nghĩa là chấp nhận mọi đề xuất; muốn khác thì chỉ cần nêu mã câu (vd "G3: 6 ô/giây").
> Theo `CLAUDE.md` §9: câu nào ảnh hưởng gameplay/schema/protocol thì em hỏi; việc nhỏ thuần kỹ thuật em tự quyết và ghi `docs/DECISIONS.md`.
> **Trạng thái 2026-10-02:** anh trả lời "ok" sau M0 → các mặc định P, G, D được áp dụng (đổi được bất cứ lúc nào).
> **Trạng thái 2026-10-03 (M1):** E1–E4 đã xong (môi trường có Elixir 1.17.3 / OTP 25, Hex tải được, Postgres `postgres/postgres`). E5 xem báo cáo push M1. E6 vẫn mở. Câu mới: mục **M1** cuối file.
> Câu hỏi gốc của KB (Q1–Q15, A1–A6, B1–B6) giữ nguyên trong `docs/kb/`; mục **K** cuối file chỉ ghi trạng thái liên quan Phase 1.

## E. Môi trường cloud — ~~chặn M1~~ (E1–E4 đã xong 2026-10-03) (chi tiết `docs/CLOUD_CHECK.md`)

| # | Vấn đề | Bằng chứng | Cần anh làm / đề xuất |
|---|---|---|---|
| E1 | Chưa có Elixir/Erlang/mix | `elixir --version` → `command not found`; phiên chạy trên môi trường `cloud_default`, không phải `mu-web-phase1` | Tạo môi trường theo `PROMPT_PHASE1_CLOUD §A2` (kèm setup script ở E3) rồi mở phiên mới trên môi trường đó. Em không tự đổi cấu hình môi trường |
| E2 | Hex bị proxy chặn | `curl https://repo.hex.pm/names` → `CONNECT tunnel failed, response 403`; `builds.hex.pm` cũng 403 | Thêm `repo.hex.pm` và `builds.hex.pm` vào allowlist (Network access: Custom) |
| E3 | Elixir 1.14 từ apt **không đủ** cho mix.lock của repo nền | `ecto_sql 3.14.0`, `postgrex 0.22.4`, `plug 1.20.3` yêu cầu `elixir ~> 1.15` (tra hex.pm API). Repo nền chạy CI với Elixir 1.17 / OTP 25 | **Đề xuất:** setup script cài OTP 25 từ apt, rồi tải Elixir 1.17.3 build sẵn cho OTP 25 từ `builds.hex.pm` (cần E2). Ví dụ: `apt-get install -y erlang erlang-dev inotify-tools unzip build-essential` → `curl -fsSL https://builds.hex.pm/builds/elixir/v1.17.3-otp-25.zip -o /tmp/e.zip && unzip -q /tmp/e.zip -d /opt/elixir && ln -sf /opt/elixir/bin/* /usr/local/bin/` → `mix local.hex --force && mix local.rebar --force`. Phương án dự phòng: giữ Elixir 1.14 và hạ bản thư viện (ecto_sql 3.12, postgrex ≤ 0.19, plug ≤ 1.16), không khuyến nghị |
| E4 | Postgres tắt khi vào phiên và user `postgres` chưa có mật khẩu | `pg_lsclusters` → `down`; `psql -h localhost -U postgres` (mật khẩu `postgres`) → `password authentication failed` | Setup script đặt mật khẩu như `§A2` (`ALTER USER postgres PASSWORD 'postgres'`). Hook SessionStart bật Postgres mỗi phiên: ở M1 em sẽ commit `.claude/settings.json` + `scripts/cloud_session_start.sh` đúng nội dung `§A3` (đây là file trong repo, không phải cấu hình môi trường) — anh xác nhận giúp |
| E5 | Phiên này không push được lên GitHub | Công cụ gắn repo báo: Claude chưa có quyền ghi `biennguyen94/mmo-rpg-game` | Cài Claude GitHub App cho repo (https://github.com/apps/claude/installations/select_target) hoặc kết nối lại GitHub ở claude.ai Settings → Connectors |
| E6 | File được nhắc nhưng không có trong repo | `priv/reference/items_raw.json` không có; `reference/rpg-game/COMMIT` không có (hash ở `reference/COMMIT` = `5c514b75…`); `Item.txt` không có | Commit `items_raw.json` (KB_ITEM_REFERENCE §6 bắt buộc test "template khớp dòng gốc trong items_raw.json"). Nếu không có, em bỏ test đó và ghi lý do. `reference/COMMIT` em dùng thay `reference/rpg-game/COMMIT` (không cần sửa) |

## P. Protocol / API (KB_TECHNICAL §4–§5 chưa đủ chi tiết)

| # | Câu hỏi | Đề xuất mặc định |
|---|---|---|
| P1 | Tạo/xem nhân vật đi qua đâu? §5 không có act `create`, còn `join` đã cần `characterId` | HTTP: `POST /register`, `POST /login`, `POST /ws-ticket`, `GET /characters`, `POST /characters {name}` (Bearer access token). Đường dẫn đúng như KB §4 (không thêm tiền tố `/api`) |
| P2 | Kết quả thành công của `cmd`? §5 chỉ định nghĩa `error {rid, error}` | Channel reply `{:ok, %{rid}}` (ack) + trạng thái mới qua `player`/`snapshot`/`combat`/`shop`; lỗi gửi cả event `error {rid, error}` (đúng §5) |
| P3 | Payload `spawn` / `despawn` chưa định nghĩa; snapshot không có kiểu entity | `spawn {id, kind: "player"\|"monster"\|"npc"\|"item", x, y, hp, maxHp, state, name, level, templateId?, look?}`; `despawn {id}`. `snapshot` giữ đúng `{t, entities:[{id,x,y,hp,state}], removed}`. Id dạng chuỗi có tiền tố: `p_<uuid>`, `m_<n>`, `npc_<id>`, `g_<serial>` |
| P4 | Thông báo `EXP_GAIN`, `LEVEL_UP`, `ITEM_DROP`, `ITEM_PICKUP` (§19.11) lấy từ đâu khi protocol không có event riêng? | Client tự suy ra từ chênh lệch `player` (exp, level), `spawn` item rơi và kết quả `pickup`. Không thêm event mới. Nếu anh muốn rõ ràng hơn: thêm event `notice {type, data}` (đổi protocol) |
| P5 | Access token "TTL ngắn" là bao lâu? Có refresh không? | 24 giờ, không refresh (hết hạn thì đăng nhập lại). Ticket WS 30 giây (đúng KB) |
| P6 | Quy tắc username/mật khẩu khi đăng ký (KB chỉ có schema) | username 3–32 ký tự `[A-Za-z0-9_]`, unique không phân biệt hoa thường; mật khẩu 8–72 ký tự; `email` bỏ trống được |
| P7 | "clientVersion không tương thích" nghĩa là gì? | So khớp chính xác với `server.clientVersion` trong config (vd `"0.1.0"`); sai → join lỗi `FORBIDDEN` |
| P8 | Ngưỡng rate-limit theo loại `act` | `move_to` 10/giây, `attack`/`skill` 10/giây, item/shop 5/giây, `alloc` 5/giây, `chat` 5/10 giây; vượt → bỏ lệnh + `RATE_LIMITED`; vượt liên tục 5 giây → kick. Đăng nhập: giữ ngưỡng repo nền (10 lần/5 phút/tên, 30/5 phút/IP) |

## G. Gameplay (KB_GAME_DESIGN / KB_CONFIG thiếu số)

| # | Câu hỏi | Đề xuất mặc định (CONFIG, `verified:false`) |
|---|---|---|
| G1 | **Chí mạng**: §4 có `isCritical × criticalMultiplier` nhưng không có tỉ lệ/hệ số ở đâu | `combat.critChance = 0` (tắt) ở Phase 1; code và test sẵn đường crit với hệ số đặt trong config. Nếu anh muốn bật: 0.05 và ×1.5 |
| G2 | Tầm đánh của DK / `basic_attack` (chỉ Spider có `attackRange 1`) | `basic_attack`: `range 1`, `damageMultiplier 1.0`, `manaCost 0`, cooldown = công thức §6 |
| G3 | Tốc độ di chuyển người chơi (không có trong KB). Spider `moveSpeed 3` cũng chưa rõ đơn vị | Đơn vị là **ô/giây**. Người chơi 5 ô/giây; Spider 3 ô/giây; đi chéo tốn thời gian ×1.414 |
| G4 | Khoảng cách tính thế nào (tầm đánh, nhặt, aggro, leash, mở NPC) | Chebyshev (8 hướng); nhặt đồ ≤ 1 ô; mở shop ≤ 3 ô; Shop tự đóng khi > 3 ô |
| G5 | Nhịp đánh của Spider | Mỗi đòn cách `combat.baseCooldownMs` = 1000 ms; trúng theo §5 với `attackRate` Spider vs `defenseRate` người chơi; sát thương theo pipeline §4 (raw = random(damageMin, damageMax) − defense người chơi) |
| G6 | `ring_hp_t0` có `hpBonus 20` nhưng công thức `hpMax` §4.1 không cộng item | `hpMax = công thức §4.1 + sum(equipment.hpBonus)` (CHANGE_REASON: thiếu trong §4.1) |
| G7 | Twisting Slash: `range 2, radius 2` tính quanh ai? | Mục tiêu phải trong 2 ô; trúng mọi Spider trong bán kính 2 quanh **người dùng**; một lần roll hit/dmg riêng cho từng con. Giữ `requiredLevel 10` = `maxLevel 10` (chỉ dùng được ở cấp tối đa) — anh xác nhận đây là ý muốn |
| G8 | Nhân vật mới: Zen, vật phẩm, vị trí ban đầu | 0 Zen, túi trống, đứng ở điểm spawn trong safe zone Lorencia. (Hệ quả: muốn mua potion phải giết ~10 Spider lấy Zen) |
| G9 | Hồi HP/MP tự nhiên | Không hồi tự nhiên ở Phase 1 (chỉ potion, level up, hồi sinh) để acceptance "dùng potion" có ý nghĩa |
| G10 | Lên cấp có hồi đầy HP/MP không? | Có |
| G11 | Chết: hồi sinh ra sao? | Sau 3 giây, hồi sinh ở spawn safe zone với HP/MP đầy; mất 0% EXP (đúng `deathExpLossPercent 0`); không rơi đồ |
| G12 | Zen rơi từ Spider: nằm dưới đất hay cộng thẳng? (Zen không phải item theo KB) | Cộng thẳng cho người giết khi Spider chết, ghi vào `characters.zen` ngay (transaction) |
| G13 | Ai được nhặt đồ trong `lootProtectSeconds` | Người gây nhiều sát thương nhất lên con quái đó |
| G14 | Spider có được vào safe zone? Đánh nhau trong safe zone? | Quái không bước vào ô safe zone, bỏ đuổi (RETURN) khi mục tiêu vào safe zone; người chơi trong safe zone không bị đánh và không tấn công được |
| G15 | Aggro "theo khoảng cách + damage" chưa có trọng số | Chọn người chơi gần nhất trong `aggroRange`; bị đánh thì đổi sang kẻ đang gây nhiều sát thương nhất |
| G16 | Số Spider và vùng sinh trên Lorencia (KB không có) | 1 vùng sinh ngoài thị trấn, 10 Spider; map ~64×64 em tự vẽ |
| G17 | Option lúc rơi đồ (luck/skill/excellent, `levelRoll`) chưa có bảng | Phase 1: đồ rơi luôn +0, không option |
| G18 | Độ bền giảm khi đánh/chết ("CONFIG", không có số) | Không giảm độ bền ở Phase 1 (giữ cột `durability` = giá trị template) |
| G19 | `expRequired` = `100 × level^1.5` ra số lẻ | Làm tròn `round()`; EXP vượt ngưỡng chuyển sang cấp sau; ở `maxLevel` EXP dừng ở 0 |
| G20 | Mua/nhặt potion: gộp vào stack có sẵn? | Gộp vào stack cùng template có slot thấp nhất còn chỗ (`maxStack 99`), thừa thì tạo stack mới (serial mới, ghi audit) |
| G21 | Mất kết nối ở Phase 1 (reconnect là Phase 3) | Kênh đóng → nhân vật rời map ngay nếu không combat; đang combat thì ở lại `logoutInCombatSeconds` (10s) rồi lưu và rời. Reload trang vào lại bình thường |
| G22 | Lọc từ cấm cho tên nhân vật (§18) | Danh sách rỗng trong config, có sẵn chỗ để thêm |

## D. Dữ liệu / KB không khớp nhau

| # | Mâu thuẫn | Đề xuất |
|---|---|---|
| D1 | Vị trí config: `KB_CONFIG` ghi `data/configs/*.json`; `CLAUDE.md` §4 và `KB_TECH_STACK §7` ghi `priv/game_data/` | Dùng `priv/game_data/` (CLAUDE.md + TECH_STACK; `priv/` vào được bản release). `data/items/phase1.json` là **nguồn**; `mix mu.items.import` kiểm tra rồi sinh `priv/game_data/items.json` (commit) |
| D2 | `game.maxLevel = 400` (KB_CONFIG §1) vs Phase 1 `maxLevel 10` (KB_00 §7) | Config Phase 1 đặt `maxLevel 10` (§7 là nguồn duy nhất về scope) |
| D3 | `KB_TECHNICAL §9` ghi migration ở `database/migrations/`; Phoenix dùng `priv/repo/migrations/` | `priv/repo/migrations/` (KB_TECH_STACK §7 thắng về cấu trúc; TECHNICAL §11 tự ghi là sơ đồ generic) |
| D4 | `KB_TECHNICAL §8`: `collision.bin` nhưng không có định dạng | 1 byte/ô theo hàng (0 đi được, 1 chặn), `width×height` byte; sinh từ map JSON bằng mix task, test kiểm khớp |
| D5 | Bản ghi trong `data/items/phase1.json` không có `version`/`verified`/`source` ở cấp bản ghi (chỉ nằm trong `reference`); `ring_hp_t0` không có cả ba (KB_00 §2 yêu cầu mọi bản ghi có) | Không sửa file nguồn; lúc import điền `version`/`verified`/`source` từ `reference` (ring: `version: null, verified: false, source: null`) và test kiểm đủ trường |
| D6 | `data/items/phase1.json` không có `sellPrice` (KB_ITEM_REFERENCE §3.3 nói "phải tự thêm") | Tính lúc import: `sellPrice = floor(buyPrice × economy.sellRatio)` (hp potion → 50, khớp KB_CONFIG §4) |
| D7 | Hình ASCII mobile §19.1 vẽ dock 5 tab; text nói 4 tab | Theo text: 4 tab (KB ghi text ưu tiên) — không cần trả lời |
| D8 | Phaser bản mới nhất trên npm là **4.2.1**; prompt chốt Phaser 3 | Ghim `phaser@3.90.0` (bản 3.x cuối) |

## K. Trạng thái câu hỏi gốc của KB liên quan Phase 1

| # | Trạng thái với Phase 1 |
|---|---|
| Q2, Q4 | Dùng giá trị tạm của KB_CONFIG (`verified:false`) |
| Q12 | Prompt đã chốt `requirementScale 0.35` → đóng với Phase 1 |
| Q13 | 1 nhân vật/tài khoản, enforce ở app |
| Q14 | Chấp nhận như KB; M6 test "dùng potion" trước khi mặc áo và báo trong bảng cân bằng |
| Q15 | `defenseRate` của item không dùng trong combat |
| Q11, A5, A6 | Không có icon thật trong cloud → placeholder; `mix mu.icons.index` + `docs/ICON_REPORT.md` ở M4–M5 |
| A4 | Chưa có sprite nhân vật. KB_ASSETS §2.1 **cấm** dùng DCSS cho trang bị nhân vật, nên không dùng lớp `doll/` của repo nền. Đề xuất: thân DK dùng `monsters/hero.png` (DCSS CC0, 32×32, 1 hướng) hoặc hình học, **không vẽ trang bị lên người**; chuyển động bằng tween. Thiếu 6 animation × 4 hướng của KB_ASSETS §6.1 → ghi là lệch ở M6 |
| B2 | Commit mốc repo nền: `5c514b7512183d714afb1d35ad310fa4a62f2a5d` (`reference/COMMIT`) |
| B3 | Đã đọc source + test các module Phase 1 (xem `docs/PHASE1_PLAN.md §2`) |
| B4 | Đã đọc `reference/rpg-game/CREDITS.md`: DCSS = CC0 (bản `releases/Nov-2015`, đã đối chiếu danh sách license không rõ), game-icons.net = CC BY 3.0 (Lorc, Delapouite, Willdabeast). Phase 1 không dùng icon game-icons.net |

## M1. Câu hỏi phát sinh ở M1 (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Câu hỏi | Đã làm (đề xuất) |
|---|---|---|
| M1-1 | **Schema:** §4 yêu cầu access token lưu hash trong DB, có TTL, thu hồi được, nhưng §9 không có bảng | Thêm bảng `access_tokens (id BIGSERIAL, account_id UUID FK ON DELETE CASCADE, token_hash BYTEA UNIQUE, expires_at TIMESTAMPTZ, created_at)` — migration riêng `20261003000001`, `CHANGE_REASON` trong moduledoc + commit |
| M1-2 | **Protocol:** lỗi khi join `"game"` không có trong §5 | `{error: "FORBIDDEN", reason}` (DEC-11) |
| M1-3 | **Protocol:** báo cho tab bị đá (single login) | event `error {rid: null, error: "FORBIDDEN"}` rồi đóng kênh (DEC-14). Nếu anh muốn rõ hơn: thêm event `kicked` (đổi protocol) |
