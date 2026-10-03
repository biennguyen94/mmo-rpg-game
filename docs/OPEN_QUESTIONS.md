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
| E7 | **(ĐÓNG 2026-10-03 — phương án b, DEC-53)** ~~npm registry bị chặn~~ — gateway trả `x-deny-reason: host_not_allowed` dù anh đã thêm vào allowlist; Phase 1 giữ Canvas 2D, Phaser chuyển sang `docs/BACKLOG.md`. | `npm view esbuild` → `403 Forbidden - GET https://registry.npmjs.org/esbuild` (M0 còn tải được). Máy không có sẵn `phaser`/`esbuild`/`vitest` (cache npm cũng không có) | Mở lại `registry.npmjs.org` cho môi trường (Network access → Custom, giữ danh sách package manager mặc định). Trong lúc chờ: client chạy bằng `tsc` có sẵn + Canvas 2D tạm (DEC-43, DEC-46); **PhaserView chưa làm**. Cũng chưa sinh được `client/package-lock.json` |
| E8 | **(M5 → ĐÃ XONG 2026-10-03)** ~~Không đối chiếu được license sprite DCSS~~ — mạng mở lại; 10 sprite/tile đã đối chiếu từng file (tên + đường dẫn gốc không có trong danh sách loại trừ, trùng từng byte theo git blob hash), xem `CREDITS.md`, `priv/static/assets/mapping.json`. Lưu ý: DCSS loại `tree1/tree2/tree3…` — cây dùng `mangrove1.png` (không bị loại) | `raw.githubusercontent.com/crawl/tiles/.../TILES_UNDER_UNKNOWN_LICENSE.md` → `CONNECT tunnel failed, response 403` (M0 còn đọc được). KB_ASSETS §2.1 bắt agent tự đọc file license, không dựa nguồn thứ cấp (`reference/rpg-game/CREDITS.md`) | Mở `raw.githubusercontent.com` hoặc anh xác nhận dùng theo CREDITS của repo nền. Hiện: không copy sprite nào, vẽ hình học (người = tròn, Spider = thân + 8 chân, NPC vàng, đồ = hình thoi) |
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

## M2. Câu hỏi phát sinh ở M2 (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Câu hỏi | Đã làm (đề xuất) |
|---|---|---|
| M2-1 | **Protocol:** client cần dữ liệu map để vẽ; §5 không có event map | Reply của join thêm `entityId` (id entity của mình) và `map {id, name, width, height, tiles, legend, safeZones, npcs}` (KB_TECH_STACK §6: dữ liệu tĩnh gửi lúc join). Không có collision/công thức |
| M2-2 | **Protocol:** `move_to` tới ô tường/nước/NPC/ngoài biên/không có đường, hoặc `x`,`y` sai kiểu: mã lỗi nào? | `INVALID_TARGET` (sai kiểu còn ghi log cảnh báo). Thành công: ack `{rid}`; vị trí chỉ đến qua `snapshot` |
| M2-3 | **Protocol:** `snapshot.entities[].state` của người chơi | `"idle"` / `"walk"` (M3 thêm `"attack"`, `"dead"`) |
| M2-4 | **Map:** bố cục Lorencia tự vẽ (thị trấn có tường 2 cổng ở tây, safe zone = trong tường, NPC bán thuốc trong thị trấn, hồ phía bắc, vùng 10 Spider phía đông) | Anh xem `priv/maps/lorencia.json` (hàng `tiles`); M5 sẽ vẽ được để xem bằng mắt |

## M3. Câu hỏi phát sinh ở M3 (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Câu hỏi | Đã làm (đề xuất) |
|---|---|---|
| G23 | **Gameplay:** §3 nói EXP "giảm tuyến tính tới `minExpRatio`" khi người chơi cao hơn quái quá `levelDiffPenaltyStart` cấp, nhưng không cho độ dốc | `experience.levelDiffPenaltyPerLevel = 0.1` (mỗi cấp vượt giảm 10%, sàn 0.1). **Không chạm ở Phase 1** (Spider cấp 2, maxLevel 10 → chênh tối đa 8 < 10) |
| G24 | **Gameplay:** nhiều người cùng đánh một quái: EXP cho ai? (G12 chỉ nói Zen cho "người giết") | EXP + Zen cho người ra đòn cuối; đồ rơi thuộc người gây nhiều sát thương nhất trong 10s (G13). Party chia EXP là Phase 3 |
| G25 | **Gameplay:** KB_CONFIG ghi 10 / 170 / 1110 Spider tới cấp 2 / 5 / 10; với `expRequired` làm tròn từng cấp (G19) ra **10 / 171 / 1111** | Giữ G19 (lệch ≤ 1 con) |
| G26 | **Cân bằng — cần anh quyết (2026-10-03: anh trả lời "ok" chung, chưa chọn → giữ nguyên số, tức (c)):** vùng Spider 17×21 ô có 10 con, `aggroRange` 5 → chạy thật trên server, đánh 1 con thì **6 con cùng aggro**: mất ~150/185 HP để hạ 1 Spider (simulator đánh từng con chỉ mất ~7.6 HP/con). DK cấp 1 không có đồ gần như chắc chết khi vào giữa vùng | Chưa đổi số. Đề xuất (chọn một): (a) giảm `aggroRange` 5 → 3; (b) giãn vùng sinh (vd. 30×30) hoặc chia 2–3 vùng nhỏ; (c) giữ nguyên, coi là độ khó (mua potion ở NPC trước) |
| M3-1 | **Protocol:** trượt đòn thể hiện thế nào? §5 `combat` không có trường `miss` | `dmg: 0` = trượt (đòn trúng luôn ≥ `hardFloor` 1 nên không nhầm) |
| M3-2 | **Protocol:** `state` của quái: `"idle"`, `"chase"`, `"attack"`, `"return"`, `"dead"`; người chơi: `"idle"`, `"walk"`, `"dead"` | Như bên trái |
| M3-3 | **Protocol:** báo EXP/Zen/lên cấp | Event `player` (đầy đủ + `view`) mỗi khi đổi; client so chênh lệch để hiện `EXP_GAIN`/`LEVEL_UP` (theo P4, không thêm event) |
| M3-4 | **Protocol:** `alloc` lỗi | Không đủ điểm → `REQUIREMENT_NOT_MET`; stat/điểm sai kiểu hoặc ≤ 0 → `FORBIDDEN` |

## M4. Câu hỏi phát sinh ở M4 (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Câu hỏi | Đã làm (đề xuất) |
|---|---|---|
| M4-1 | **Protocol:** `equip {itemId, slot}` / `unequip {slot, toSlot}`: `slot` là số hay tên? | Số theo `KB_CONFIG §6` (0 HELM … 5 WEAPON, 6 SHIELD, 8/9 RING). Nhẫn vào 8 hoặc 9. `toSlot` bỏ trống = ô túi trống thấp nhất |
| M4-2 | **Protocol:** `npc_open` trả `shop {npcId, items: [{templateId, price}]}` (§5) | Thêm `name` (`Potion Merchant`) để client hiện tiêu đề §19.7. `npcId` nhận cả `lorencia_potion_merchant` lẫn `npc_lorencia_potion_merchant` |
| M4-3 | **Protocol:** dữ liệu túi đồ gửi client | Trong event `player` (DEC-42); không thêm event mới |
| M4-4 | **Mã lỗi đồ:** | Item không phải của mình/không có → `NOT_OWNER`; đồ đang mặc mà bán/dùng, ô sai → `INVALID_SLOT`; số lượng sai, template không bán ở shop → `INVALID_TARGET`; act `move_item/split/drop/chat` (ngoài UI Phase 1) → `FORBIDDEN` |
| M4-5 | **Gameplay:** bán potion được không? Bán một phần stack? | Được: bán item bất kỳ trong túi (không bán đồ đang mặc), `quantity` bỏ trống = cả stack (UI §19.7 bán cả stack) |
| M4-6 | **Gameplay:** mua đồ không stack nhiều cái một lần | Shop Phase 1 chỉ bán potion; đồ không stack giới hạn `quantity = 1` |

Trạng thái mục cũ: **E6 vẫn mở** — chưa có `priv/reference/items_raw.json`, test "template khớp dòng gốc" đang `@tag :skip` (`test/mu/game/item_import_test.exs`). Các test bắt buộc còn lại của KB_ITEM_REFERENCE §6 đã có. **Q11/A6 vẫn mở** — chưa có icon thật: `docs/ICON_REPORT.md` ghi 10/10 item dùng placeholder.

## M5. Câu hỏi phát sinh ở M5

| # | Câu hỏi | Đã làm (đề xuất) |
|---|---|---|
| M5-1 | **ĐÃ QUYẾT 2026-10-03: (b)** — registry npm bị chặn → chưa có Phaser | (a) **mở `registry.npmjs.org`** (khuyến nghị): em viết `PhaserView` thay `CanvasView`, giữ nguyên logic/UI; (b) không mở được: giữ Canvas 2D làm game view chính thức Phase 1 (lệch quyết định "Phaser 3" đã chốt) |
| M5-2 | **Protocol:** client cần tầm nhặt/NPC và tên/tầm skill | Reply join thêm `config.pickupRange`, `config.npcRange`, `data.skills [{id, name, range, manaCost, requiredLevel}]` |
| M5-3 | **Asset (A4, §6.1):** chưa có sprite DK 6 animation × 4 hướng, tileset, effect, BGM | Placeholder hình học + số sát thương bay lên; SFX tổng hợp Web Audio (hit, miss, hurt, potion, pickup, level up, click); **chưa có BGM** — ghi là lệch ở M6 |
| M5-4 | Mô tả "Atk Speed" trong panel Nhân vật | Hiện `view.attackSpeed` (DK cấp 1 = 1) như §4.1; số trong hình §19.3 chỉ minh họa |

## M6. Trạng thái khi nghiệm thu (2026-10-03)

| # | Mục | Trạng thái |
|---|---|---|
| M6-1 | **E7 — ĐÓNG (b), DEC-53** (npm): anh chọn (a) mở registry, nhưng phiên đang chạy vẫn nhận 403 (thử lại 2026-10-03 sau khi anh sửa mạng: `raw.githubusercontent.com` và `github.com` đã mở, `registry.npmjs.org` **vẫn 403**) (cả đi thẳng lẫn qua proxy phiên) — thay đổi mạng có lẽ chỉ áp dụng cho phiên/container mới | `PhaserView` chưa làm; mở phiên mới trên môi trường đã sửa để em làm nốt (interface `GameView` sẵn sàng) |
| M6-2 | **G26** (bầy Spider) — vẫn chờ anh chọn a/b/c | Giữ nguyên số |
| M6-3 | Cân bằng: xem `docs/ACCEPTANCE.md §3` (Q14, G26, kinh tế potion, Twisting Slash ở cấp 10) | Chờ anh |

## P2. Câu hỏi Phase 2 (kế hoạch: `docs/PHASE2_PLAN.md`) — ⛔ = chặn milestone

| # | Câu hỏi | Đề xuất của em (chỉ làm sau khi anh đồng ý) |
|---|---|---|
| P2-1 | `CLAUDE.md` quy tắc 3 "Chỉ làm Phase 1" mâu thuẫn với yêu cầu làm Phase 2 | Đổi thành "Chỉ làm phase đang mở (hiện tại: Phase 2)" — câu đầy đủ ở `PHASE2_PLAN.md §0`; em không tự sửa |
| P2-2 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** (`docs/PHASE2_PROPOSAL_M2_M3.md`) | `maxLevel` Phase 2? (Phase 1 = 10; `KB_CONFIG §1` master = 400) | Theo map cao nhất làm ở Phase 2, vd 30 nếu có Lorencia + Noria/Devias; chỉnh bằng simulator |
| P2-3 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** (`docs/PHASE2_PROPOSAL_M2_M3.md`) | Tạo nhân vật DW/Elf: map xuất phát, Zen, đồ khởi đầu theo class? (`newCharacter` hiện cố định DK, Lorencia) | Mọi class bắt đầu Lorencia, Zen 0, không đồ (giống DK) cho tới khi có map Noria |
| P2-4 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** (`docs/PHASE2_PROPOSAL_M2_M3.md`) | **Số liệu skill** DW (vd Energy Ball, Fire Ball, Lightning, Teleport…) và Elf (vd Triple Shot; support Healing, Greater Defense, Greater Damage — `KB_REFERENCE §1`): `manaCost`, `cooldownMs`, `range`, `radius`, `damageMultiplier`, `targetType`, `requiredLevel`. Buff: thời hạn, công thức cộng (theo energy?), cộng dồn? Heal: công thức? Mục tiêu buff khi chưa có party (Phase 3): chỉ bản thân hay mọi người chơi? Học skill vẫn theo `requiredLevel` (§7) hay qua scroll/NPC? | Anh cho danh sách skill + số; hoặc em đề xuất bảng IMPLEMENTATION để anh duyệt. Học theo `requiredLevel` như Phase 1. Buff Elf: bản thân + người chơi khác được chọn làm target |
| P2-5 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** (`docs/PHASE2_PROPOSAL_M2_M3.md`) | Cung/nỏ: chiếm cả slot khiên? cần mũi tên (item tiêu hao)? tầm `basic_attack` theo vũ khí (cung, staff) lấy ở đâu? DW đánh thường bằng staff là cận chiến hay phép? | Cung 2 tay (khóa SHIELD), **không** dùng mũi tên; `basic_attack` có `range` theo loại vũ khí trong config (vd melee 1, bow 5, staff 1) |
| P2-6 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** (`docs/PHASE2_PROPOSAL_M2_M3.md`) | **E6 vẫn mở:** cần `priv/reference/items_raw.json` (hoặc Item.txt) để nhập staff/bow/giáp DW-Elf theo `KB_ITEM_REFERENCE §3`. Item nào vào Phase 2 (tier nào, bao nhiêu món)? Staff có "magic power" riêng không (công thức DW §4.1 chỉ dùng `weapon.attackMax`)? | Mỗi class 1–2 tier vũ khí + bộ giáp tier thấp nhất class dùng được; staff dùng cột Dmg như vũ khí khác theo §4.1 |
| P2-7 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** (`docs/PHASE2_PROPOSAL_M4.md`) | **Quái mới:** loại nào, map nào, chỉ số (level, hp, damage, defense, attackRate, defenseRate, exp, aggroRange, speed, respawn), có quái đánh xa không? KB chỉ có Spider (`KB_CONFIG §4`); `KB_ASSETS §7` nói 6–10 quái mỗi map mới | Anh cho bảng; hoặc em đề xuất IMPLEMENTATION theo đường cong EXP hiện có để duyệt |
| P2-8 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** (DEC-56) | **UI túi đồ Phase 2:** `KB_CONFIG §6` ghi Phase 1 là danh sách "không phải lưới 8x8"; Phase 2 có chuyển sang lưới 8×8 không? Item chiếm nhiều ô theo `reference.cells` (X×Y) hay mỗi item 1 ô? Kéo thả cụ thể (kéo lên slot trang bị = equip, kéo ra ngoài = drop có hỏi xác nhận?) — §19 chưa có hình | Lưới 8×8, **mỗi item 1 ô** (đơn giản, khớp 64 slot hiện có), kéo thả + vẫn giữ nút `[Trang bị]` cho mobile; drop hỏi xác nhận |
| P2-9 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** (DEC-58) | `drop {itemId}`: item ra mặt đất (location `GROUND` là `LATER_VERSION`, `KB_TECHNICAL §9`) hay hủy? | Ra mặt đất **trong bộ nhớ MapServer** như drop của quái (không thêm location DB), xóa khỏi DB trong transaction + `item_audit_log` `DROP`; ai cũng nhặt được sau `lootProtectSeconds`; mất sau `groundItemSeconds` (item mất hẳn) |
| P2-10 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** | **Map Phase 2:** làm map nào ngoài Lorencia (Noria/Devias/Dungeon — level vào `verified:false`)? Kích thước, layout (em tự vẽ hay anh có Tiled)? Portal nối ở đâu? Có cần đổi `KB_TECHNICAL §5` cho chuyển map (event mới hay dùng `player` + `spawn`)? | 1 map thêm (Noria), em tự dựng layout + tile DCSS; portal là ô đặc biệt trong map JSON; chuyển map = server đẩy lại payload như join (cần `CHANGE_REASON`) |
| P2-11 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** | NPC/Shop mới: NPC nào, bán gì, giá? (giá hiện là placeholder IMPLEMENTATION) | 1 NPC vũ khí/giáp ở Lorencia bán đồ tier thấp; giá = `buyPrice` từ template |
| P2-12 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** | **Chat (§16):** độ dài tối đa, rate-limit, phạm vi NORMAL (cả map hay bán kính), WHISPER tìm theo tên nhân vật (offline → mã lỗi nào?), danh sách từ cấm (ai cung cấp?), mute/report: ai mute (admin, cách nào)? Lịch sử chat có lưu DB không? | 100 ký tự, 1 tin/giây (burst 5), NORMAL = cả map, WHISPER offline → `INVALID_TARGET`, lọc từ cấm từ file config (anh cung cấp danh sách), mute bằng mix task admin, không lưu DB |
| P2-13 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** | **Hộp thư:** `§19.10` yêu cầu bổ sung vào `KB_TECHNICAL` bảng `mail` + `mail_list/mail_claim/mail_delete` — em không được sửa `docs/kb/`. Ai gửi mail (mix task admin, mail chào mừng khi tạo nhân vật)? Mail theo nhân vật hay tài khoản? Đề xuất schema để anh chép vào KB: `mail(id, character_id, kind, title, body, zen, item_template_id, item_quantity, read_at, claimed_at, created_at, expires_at)`; action `mail_list {}` → event `mail {items}`, `mail_claim {mailId}`, `mail_delete {mailId}` (chỉ mail đã đọc/đã nhận) | Như cột trái, mail theo nhân vật, nhận quà trong 1 transaction + `item_audit_log` `MAIL_CLAIM`, mail chào mừng khi tạo nhân vật |
| P2-14 **ĐÃ QUYẾT 2026-10-03: theo đề xuất** | Panel Bản đồ §19.12: hiện cả quái/người chơi khác không? Ký hiệu 🏠 lấy từ đâu (vùng safe zone?) | Chỉ bản thân, NPC, portal, vùng safe zone; không hiện quái/người khác |
| P2-15 **ĐÃ LÀM 2026-10-03: danh sách 21 mục ở `docs/ACCEPTANCE_PHASE2.md §1`** | Danh sách nghiệm thu Phase 2 (KB_00 §7 chỉ có cho Phase 1) | Em soạn dựa trên scope Phase 2 ở P2-M7 để anh duyệt |
| P2-16 | Durability giảm khi chết/đánh (§11, "CONFIG") — số chưa có; làm ở Phase 2 không? | Để sau (không có số), ghi BACKLOG |
| P2-17 | Monster AI §9: trạng thái SEARCH và "sleep khi vùng không có người" — vùng = gì khi AOI là Phase 3? | Sleep theo map không có người chơi; SEARCH = IDLE quét aggro (đã có) |

### P2-M1. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Câu hỏi | Đã làm |
|---|---|---|
| P2M1-1 | **Protocol:** `move_item.to.location` = `EQUIPMENT` có cần hỗ trợ không? | Không: trả `INVALID_SLOT`; kéo vào ô trang bị → client gửi `equip`, kéo ra → `unequip` (DEC-59) |
| P2M1-2 | Giới hạn nhóm lệnh đồ 5 lệnh/giây (`rateLimit.cmd.categories.item`) có đủ khi sắp xếp túi nhanh? | Giữ nguyên; vượt thì client báo "gửi quá nhanh". Nếu chơi thử thấy vướng, tăng `limit` trong config |
| P2M1-3 | Vứt đồ trong safe zone? Người vứt có quyền nhặt trước `lootProtectSeconds`? | Cho vứt ở mọi nơi; người vứt giữ quyền nhặt 10 s như đồ quái rơi (P2-9) |

### P2-M2. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Câu hỏi | Đã làm |
|---|---|---|
| P2M2-1 | **Protocol:** event `spawn` của người chơi thêm `class` (để vẽ sprite theo class); `player.view` thêm `attackRange`; reply join thêm `config.twoHandedWeaponTypes` và `weaponType` trong `data.items` | Đã thêm (chỉ thêm trường, không đổi trường cũ) |
| P2M2-2 | **HTTP:** `GET /characters` thêm `classes: [{id, name}]` (danh sách class tạo được, mục đầu mặc định) | Đã thêm; `POST /characters` nhận `class` như KB (thiếu = `defaultClass`, ngoài danh sách → `INVALID_CLASS`) |
| P2M2-3 | **Cân bằng (simulator thật, 20 lần):** Elf cầm cung gần như không mất máu với Spider (0,08 máu/con) vì bắn hạ trước khi Spider tới; DW có gậy mất 2 máu/con; DK tay không 3,1 | Chấp nhận cho map đầu; xem lại khi có quái đánh xa / nhanh ở P2-M4 |
| P2M2-4 | Đồ Pad/Vine/gậy/cung chưa có nguồn nhặt (Spider chưa rơi, shop chưa bán) — chỉ có đồ khởi đầu | Đúng kế hoạch: bảng drop + NPC vũ khí/giáp ở P2-M4. Có cần cho Spider rơi sớm không? |
| P2M2-5 | Số tạm của 12 template (`data/items/phase2.json`), index bộ Vine | Chờ Item.txt (E6) |

### P2-M3. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Câu hỏi | Đã làm |
|---|---|---|
| P2M3-1 | **Protocol:** `snapshot` của người chơi thêm `mp`; `combat` thêm `skill` + `heal` / `buff` (skill hỗ trợ); `player.view.buffs`; `data.skills` thêm `class, category, targetType, center, radius, cooldownMs` | Đã thêm (chỉ thêm trường) — DEC-66, DEC-67 |
| P2M3-2 | Teleport: ô đích chỉ cần đi được + trong tầm 6 (Chebyshev), **không** kiểm tầm nhìn / tường chắn giữa đường; vào / ra thị trấn được | Theo đề xuất §5.2; nếu muốn chặn xuyên tường thì cần luật line-of-sight |
| P2M3-3 | Triple Shot: mục tiêu + tối đa 2 quái gần nhất trong 1 ô quanh mục tiêu (chưa có hình nón / hướng bắn) | Theo đề xuất §5.3 |
| P2M3-4 | Buff lên người chơi khác dùng được với mọi người (chưa có party). Buff không cộng vào số Phòng thủ ở panel Nhân vật (panel hiện chỉ số gốc; buff hiện riêng ở góc trên) | Theo §5.4 |
| P2M3-5 | Flame khi tự đánh: bắn vào ô của quái đang đánh (chưa có chọn ô tự do cho Flame) | DEC-69 |

### P2-M4 (chuẩn bị). Phát hiện khi soạn bảng số

| # | Câu hỏi | Đề xuất |
|---|---|---|
| P2M4-1 | Công thức §4.1 cho sát thương người chơi tăng chậm theo stat → máu quái để "~5 s/con" gần như phẳng theo cấp (66 → 155); tiến bộ chủ yếu nhờ đồ | Chấp nhận cho Phase 2; muốn quái "trâu" hơn ở cấp cao thì anh tăng hệ số §4.1 trong KB |
| P2M4-2 | **Protocol:** event mới `map_change {map, player, entityId}` khi qua cổng (cần `CHANGE_REASON` ở KB_TECHNICAL §5) | Như `PHASE2_PROPOSAL_M4.md §2` |

### P2-M4. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Câu hỏi | Đã làm |
|---|---|---|
| P2M4-3 | **KB_TECHNICAL §5 cần anh bổ sung** (em không sửa `docs/kb/`): event `map_change {map, entityId, player}` + `CHANGE_REASON: P2-M4 chuyển map qua cổng`; `error` có thể kèm `reason/map/levelRequired`; `map.portals` trong reply join | Đã làm theo P2M4-2 (anh duyệt "theo đề xuất hết") |
| P2M4-4 | **Cân bằng (simulator thật, 10 lần, `--monster auto --progress --skills`):** cấp 1 → 30 ≈ 907 con; DK 115 phút / 330 potion; DW 72 phút / **725 potion**; ELF 76 phút / 260 potion; không chết. Zen kiếm được ≈ 63.000 — DW cần ~72.500 Zen potion nhỏ → **thiếu Zen** nếu chỉ mua potion | Đề xuất xem lại khi chơi thử: tăng Zen quái cấp ≥ 10, hoặc tăng tỉ lệ rơi potion, hoặc giảm sát thương quái với DW (simulator chưa tính thả diều / Heal của Elf) |
| P2M4-5 | Budge Dragon dời sang đông bắc (DEC-72) để đường lên cổng an toàn | Đã làm |
| P2M4-6 | **G26** (bầy Spider): giữ phương án c (giữ nguyên) như trước | Không đổi |

### P2-M5. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Câu hỏi | Đã làm |
|---|---|---|
| P2M5-1 | **Danh sách từ cấm** (`chat.bannedWords` trong `priv/game_data/config.json`) đang **rỗng** — anh cung cấp danh sách | Cơ chế lọc đã có + test |
| P2M5-2 | Chặn người chơi / báo cáo tin nhắn (repo nền có, KB §16 nhắc "mute/report") cần bảng DB ngoài §9 | Chưa làm; nếu cần thì anh bổ sung bảng vào KB_TECHNICAL §9 |
| P2M5-3 | **Protocol:** bản sao WHISPER của người gửi có thêm `to`; chat không có lịch sử khi vào game (tin chỉ tới người đang online) | Đã làm |

### P2-M6. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Câu hỏi | Đã làm |
|---|---|---|
| P2M6-1 | **KB_TECHNICAL cần anh bổ sung** (em không sửa `docs/kb/`): §9 bảng `mail` (migration `20261004000000_create_mail.exs`, CHANGE_REASON); §5 act `mail_list {}`, `mail_claim {mailId}`, `mail_delete {mailId}` hoặc `{read: true}` (xóa mọi thư đã đọc, cho nút [Xóa đã đọc]), event `mail {unread, items?}`; nhóm rate-limit `mail` 5 lệnh / giây | Đã làm theo đề xuất P2-13 |
| P2M6-2 | Mail chào mừng **không kèm quà** (§19.10 chỉ có lời chào, không có số) | Muốn tặng quà khởi đầu thì anh cho số (Zen / item) |
| P2M6-3 | Mở panel = đánh dấu mọi thư đã đọc (badge tắt, §19.10); lọc [Chưa đọc] dùng trạng thái lúc mở | Đã làm |
| P2M6-4 | Thư hết hạn sau 30 ngày (`mail.expireDays`): không hiện, không nhận được; chưa có job xóa hẳn row hết hạn | Thêm dọn định kỳ khi cần |
| P2M6-5 | Gửi thư hàng loạt (mọi nhân vật) chưa có; quản trị gửi từng người bằng `mix mu.mail send` | Theo đề xuất |

### P2-M7. Nghiệm thu Phase 2 (2026-10-03) — chi tiết `docs/ACCEPTANCE_PHASE2.md`

| # | Vấn đề | Đề xuất |
|---|---|---|
| B-1 **ĐÃ QUYẾT 2026-10-03: (a), đã làm** | Vùng tân thủ Lorencia không an toàn: Lich / Elite Bull Fighter cách mép nam vùng Spider 2 ô, Bull Fighter cách mép bắc 5 ô (soak: bot cấp 1 chết 185 lần / 10 phút, Phase 1 là 14) | (a) dời vùng (khuyến nghị) / (b) giảm aggroRange / (c) giữ |
| B-2 | DW thiếu Zen mua potion (simulator) | tăng Zen quái cấp ≥ 10 hoặc tỉ lệ potion |

## P3. Câu hỏi Phase 3 (kế hoạch: `docs/PHASE3_PLAN.md`) — ⛔ = chặn milestone

| # | Câu hỏi | Đề xuất của em (chỉ làm sau khi anh đồng ý) |
|---|---|---|
| P3-1 | `CLAUDE.md` quy tắc 3 vẫn "Chỉ làm Phase 1" | "Chỉ làm phase đang mở (hiện tại: Phase 3)" — câu đầy đủ ở `PHASE3_PLAN.md §0`; em không tự sửa |
| P3-2 **ĐÃ LÀM (P3-M5, a)** | **MG mở ở cấp 220** (`mg.unlockLevel`) nhưng `maxLevel` hiện 30 → MG không bao giờ mở | (a) **đề xuất**: Phase 3 đặt `mg.unlockLevel` = 20 (IMPLEMENTATION, ghi lý do), giữ maxLevel 30; (b) nâng maxLevel lên ≥ 220 (cần nhiều quái / map mới, ngoài scope); (c) bỏ điều kiện, MG tạo được ngay |
| P3-3 **ĐÃ LÀM (P3-M5)** | **Nhiều nhân vật**: `maxCharacters` 4 — màn chọn nhân vật (§19 không vẽ); có cho **xóa** nhân vật không? Một tài khoản chỉ một nhân vật online (single login) | Màn chọn: danh sách tối đa 4 (tên, class, cấp, map) + [Vào game] + [Tạo nhân vật] khi còn chỗ; **chưa cho xóa** ở Phase 3; vẫn một nhân vật online / tài khoản |
| P3-4 **ĐÃ LÀM (P3-M5)** | **MG**: skill nào? Đồ khởi đầu? Cấp khởi đầu? (MU bản sau MG bắt đầu cấp cao; KB không nói) | MG dùng lại skill DK (Falling Slash, Twisting Slash, Death Stab — sức mạnh vật lý) + DW (Energy Ball, Fire Ball, Lightning — dùng `attackPowerMagic` / `attackSpeedMagic` §4.1); **cấp 1**, đồ khởi đầu `sword_t0`; không đội mũ (§6); 7 stat / cấp, 26 mỗi stat (KB) |
| P3-5 **ĐÃ LÀM (P3-M4)** | **Party — protocol + luật** (§12 chỉ liệt kê thao tác, `KB_TECHNICAL §5` chưa có act): (1) act; (2) chia EXP; (3) loot; (4) đồng bộ HP / vị trí; (5) UI; (6) khác map / offline | (1) act `party_invite {to}` (tự lập nhóm nếu chưa có), `party_accept {from}`, `party_decline {from}`, `party_leave {}`, `party_kick {name}`, `party_disband {}` (chỉ trưởng nhóm); event `party {leader, members: [{name, class, level, hp, maxHp, mapId, online}]}`, `party_invite {from}`. (2) Quái chết: mọi thành viên **cùng map, còn sống, trong `party.expRange` (20) ô** của quái chia đều `exp × (1 + 0,1 × (số người nhận − 1))`, phạt chênh cấp áp riêng từng người; Zen như cũ (người ra đòn cuối). (3) Loot protect: chủ hoặc cùng nhóm với chủ. (4) Event `party` 2 lần / giây khi HP / vị trí đổi. (5) Khung nhóm bên trái dưới HUD (tên, class, thanh HP, "khác map"); mời bằng click người chơi → [Mời vào nhóm]; lời mời hiện hộp [Đồng ý] / [Từ chối] 30 s; chat `PARTY` bật. (6) Nhóm chỉ trong RAM; mất kết nối quá `reconnectGraceSeconds` thì rời nhóm; trưởng nhóm rời → người vào sớm nhất làm trưởng |
| P3-6 **ĐÃ LÀM (P3-M3)** | **Warehouse**: NPC nào, ở đâu? Có cất Zen (schema §9 không có cột)? Phí? UI (§19 không vẽ) | NPC mới "Warehouse Keeper" ở thị trấn Lorencia + Noria; **không cất Zen, không phí** (schema chưa có); panel full-screen: lưới kho 15×8 + lưới túi 8×8 (mobile xếp dọc), kéo thả / nút [Gửi] / [Rút] trong tooltip; chỉ mở trong tầm `npcRange` |
| P3-7 | **AOI**: chat NORMAL vẫn cả map hay theo tầm nhìn? Minimap (§19.12) đã chỉ hiện mình / NPC / cổng nên không ảnh hưởng | Giữ chat NORMAL cả map (P2-12); AOI chỉ áp cho `spawn` / `despawn` / `snapshot` / `combat` |
| P3-8 | **Reconnect**: trong 30 s chờ, nhân vật đứng yên (dừng tự đánh) và vẫn bị đánh; tab mới của cùng tài khoản vào lại thì tiếp quản | Như cột trái (đúng §4); thông báo "Đã kết nối lại" |
| P3-9 **ĐÃ LÀM (P3-M6)** | Danh sách nghiệm thu Phase 3 | Em soạn ở P3-M6 (như P2-15) |
| P3-10 | **KB_TECHNICAL §5** cần anh bổ sung act / event party (+ warehouse nếu cần act riêng) sau khi chốt P3-5, P3-6 | Em ghi `CHANGE_REASON` khi làm |

### P3-M1. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Vấn đề | Đã làm / đề xuất |
|---|---|---|
| P3M1-1 **ĐÃ QUYẾT 2026-10-03: giữ KB** | **Map hiện tại 64×64 = 4×4 ô AOI**, tầm nhìn 3×3 ô (48×48) phủ 56–100 % map → AOI tiết kiệm ít (soak 20 bot, nửa ở thị trấn: −21 % byte; cả 20 bot săn Spider: −5 %) | Giữ đúng KB (DEC-85). Lợi ích lớn khi map rộng hơn / đông người hơn; nếu anh muốn thấy rõ ngay thì có thể giảm `aoiCellSize` (vd. 12) — đổi số KB, cần anh quyết |
| P3M1-2 | Lọc ở kênh, MapServer vẫn broadcast trong máy (DEC-84) | Đổi sang gửi riêng từ MapServer khi cần (nhiều node / rất đông) |

### P3-M2. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Vấn đề | Đã làm / đề xuất |
|---|---|---|
| P3M2-1 | Đóng tab / tải lại trang cũng tính là mất kết nối (nhân vật ở lại 30 s); chỉ nút **Đăng xuất** mới rời ngay (hoặc sau 10 s nếu đang combat) — DEC-88 | Theo KB §4; anh muốn đóng tab = đăng xuất thì báo em |
| P3M2-2 | Rớt mạng không có gói đóng: server biết sau tối đa 60 s (timeout WebSocket Phoenix) rồi mới đếm 30 s — DEC-89 | Giữ mặc định; có thể giảm timeout (vd. 45 s) nếu cần |

### P3-M3. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Vấn đề | Đã làm / đề xuất |
|---|---|---|
| P3M3-1 | **KB_TECHNICAL §5 cần anh bổ sung** (em không sửa `docs/kb/`): event `warehouse {npcId, slots, items: [ItemView]}`; `move_item.to.location` nhận `WAREHOUSE`; `npc_open` Thủ kho trả `warehouse` thay cho `shop` (gộp vào P3-10) | Đã làm (DEC-93); không đổi schema |
| P3M3-2 | Vị trí Thủ kho: Lorencia (11,31) giữa hai NPC bán hàng, Noria (26,54) góc tây nam thị trấn | Đổi chỗ thì sửa `priv/maps/*.json` |

### P3-M4. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Vấn đề | Đã làm / đề xuất |
|---|---|---|
| P3M4-1 | **KB_TECHNICAL §5 cần anh bổ sung** (gộp vào P3-10): act `party_invite {to}`, `party_accept {from}`, `party_decline {from}`, `party_leave {}`, `party_kick {name}`, `party_disband {}` (nhóm rate-limit `party` 5 / giây); event `party {leader, members: [{name, class, level, hp, maxHp, mapId, x, y, online}]}`, `party_invite {from}`; chat `PARTY` bật | Đã làm theo P3-5 (DEC-96 … DEC-101) |
| P3M4-2 | Chỉ trưởng nhóm được mời (P3-5 không nói rõ) | DEC-97; muốn ai cũng mời được thì báo em |
| P3M4-3 | Config mới (IMPLEMENTATION): `party.inviteSeconds` 30, `party.statusIntervalMs` 500; `party.maxSize` 5 / `expRange` 20 lấy từ KB_CONFIG | Đã thêm vào `config.json` |
| P3M4-4 | Bấm người chơi khác giờ luôn mở menu (có [Đi tới đây]) thay vì đi thẳng tới đó | DEC-101 |

### P3-M5. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Vấn đề | Đã làm / đề xuất |
|---|---|---|
| P3M5-1 | KB §4.1 MG chỉ cho `attackPowerMagic` (đòn tối đa), không có đòn tối thiểu phép | Skill phép của MG: tối thiểu = `attackMin` thường (STR/6 + vũ khí), tối đa = ENE/4 + vũ khí (DEC-104). Muốn công thức tối thiểu riêng (vd ENE/9 như DW) thì anh cho số |
| P3M5-2 | MG mặc được đồ nào trong 16 món Phase 2 (số tạm, chưa có Item.txt) | Theo mẫu Item.txt ở Phase 1: mọi món DK / DW không phải mũ (DEC-105); đối chiếu khi có Item.txt (E6) |
| P3M5-3 | **KB cần anh bổ sung**: `GET /characters` có `maxCharacters` + `classes[].locked/unlockLevel`, lỗi `CLASS_LOCKED`; `player.view.attackMaxMagic / attackSpeedMagic / cooldownMsMagic`; `data.skills[].classes / magic` (gộp vào P3-10) | Đã làm, không đổi schema DB (CHECK class đã có MG) |
| P3M5-4 | Simulator 10 lần (quái auto, đồ theo cấp, skill): MG cộng ENE 69,7 phút tới cấp 30 (574 potion), cộng STR 78,1 phút; DK 78,3; DW 72,0 (725 potion) | Cân bằng gần các class khác; MG / DW tốn potion như B-2 |

### P3-M6. Nghiệm thu Phase 3 (2026-10-03) — chi tiết `docs/ACCEPTANCE_PHASE3.md`

| # | Vấn đề | Đề xuất |
|---|---|---|
| B-7 **ĐÃ QUYẾT 2026-10-03: giữ** | Event `party` ~1,2 KB/s/bot (≈ 19 % băng thông) khi nhóm 5 người cùng di chuyển | Giữ (§12); hoặc chỉ đẩy khi HP / map / online / ô AOI đổi, hoặc `party.statusIntervalMs` 1 000 |
| B-8 | KB_TECHNICAL §5 cần bổ sung act / event Phase 3 (P3-10: P3M3-1, P3M4-1, P3M5-3) | Anh bổ sung KB |
| B-9 | `CLAUDE.md` quy tắc 3 (P3-1) | Anh sửa hoặc cho em sửa |

## P4. Câu hỏi Phase 4 "PvP & Social" (kế hoạch: `docs/PHASE4_PLAN.md`) — ⛔ = chặn milestone

KB Phase 4 chỉ có `KB_GAME_DESIGN §13` (bảng mode, `NORMAL → WARNING → MURDERER`) và `§14` (guild:
level + Zen, master / assistant / member). Mọi số dưới đây là **đề xuất IMPLEMENTATION** của em
(tham khảo cảm giác MU, không coi là số MU gốc), chỉ làm sau khi anh duyệt.

| # | Câu hỏi | Đề xuất của em |
|---|---|---|
| P4-1 | `CLAUDE.md` quy tắc 3 (B-9) | "Chỉ làm phase đang mở (hiện tại: Phase 4)" — câu đầy đủ ở `PHASE4_PLAN.md §0`; em không tự sửa |
| P4-2 **ĐÃ LÀM (P4-M1)** | **Đánh người chơi** — ai đánh được ai, bấm thế nào, AOE, sát thương | (1) `features.pvp` bật. Cả hai phải đủ `pvp.minLevel` = **6** (người mới cấp 1–5 không bị đánh và không đánh được người). Trong safe zone: không đánh được, không bị đánh. (2) Bấm người chơi → menu thêm **[⚔ Tấn công]**. Nếu đánh người NORMAL (sẽ bị tính PK), hỏi xác nhận lần đầu mỗi phiên. Tự đánh lặp như với quái. Skill đơn mục tiêu dùng được lên người. (3) **AOE chỉ trúng quái**, và trúng người đang duel / đang chiến với mình. Không trúng người trung lập, tránh PK vô ý. (4) Sát thương: pipeline §4 với `defense` / `defenseRate` của nạn nhân, nhân `pvp.damageMultiplier` = **0,5** (người chơi máu ít, đánh nhau quá nhanh nếu để 1,0). (5) Buff / heal lên người vẫn như Phase 2 |
| P4-3 **ĐÃ LÀM (P4-M1)** | **PK + Self-defense** — ngưỡng, giảm, phạt | (1) Giết người NORMAL ngoài duel / war / tự vệ: `pkPoints` +1, ghi `last_pk_at`. (2) Trạng thái: 0 = NORMAL; 1 = **WARNING** (tên cam); ≥ 2 = **MURDERER** (tên đỏ). Ngưỡng ở config `pk.warningAt` 1, `pk.murdererAt` 2. (3) Giảm 1 điểm mỗi `pk.decayMinutes` = **60 phút** tính theo giờ thực từ `last_pk_at`; tính lại khi vào game và mỗi phút khi online. (4) **Tự vệ:** B bị A đánh trước thì B được đánh A trong `pk.selfDefenseSeconds` = **30 s** (mỗi đòn của A làm mới); giết A khi tự vệ không tính PK. Đánh hoặc giết người WARNING / MURDERER không tính PK. Người đánh trước một người NORMAL thì tên nhấp nháy cam trong 30 s (người khác biết ai gây sự). (5) **Phạt MURDERER:** không dùng được NPC (shop, kho); bị người chơi giết thì rơi **1 món ngẫu nhiên trong túi** (không phải đồ đang mặc), tỉ lệ `pk.dropChance.MURDERER` 0,5 (WARNING 0,1, NORMAL 0). Đồ rơi theo đường `drop` hiện có (giữ serial, audit). Chết vì quái không rơi đồ (§11). Không mất EXP (`expLossPercent` vẫn 0) |
| P4-4 **ĐÃ LÀM (P4-M2)** | **Duel** — "vùng riêng" là gì, kết thúc thế nào | (1) "Vùng riêng" = **khoanh riêng hai người**: trong duel chỉ hai người đánh được nhau, người ngoài không đánh được họ và họ không đánh được người ngoài. Duel được ở mọi chỗ ngoài safe zone; **không làm map đấu trường riêng** (cần map / asset mới). (2) Act `duel_request {to}` (đứng trong 10 ô, đủ `pvp.minLevel`, không ai đang duel / war), `duel_accept {from}`, `duel_decline {from}`, `duel_cancel {}`; lời mời hết hạn sau 30 s. (3) Kết thúc: một bên về 0 HP thì **không chết**, giữ 1 HP và thua. Hoặc hết `duel.maxSeconds` = 180 s thì hòa. Hoặc một bên đi xa quá 20 ô / rời map / mất kết nối thì người đó thua. Không PK, không rơi đồ, không thưởng. (4) Event `duel {state: "request"/"start"/"end", opponent, winner?, endsAt?}`; kết quả báo cả map bằng dòng SYSTEM |
| P4-5 **ĐÃ LÀM (P4-M3)** | **Guild** — số, quyền, DB, UI | (1) Tạo: cấp ≥ `guild.createLevel` **20**, tốn `guild.createZen` **10 000** Zen (một transaction + audit Zen). Tên 3–8 chữ / số ASCII, không trùng (không phân biệt hoa thường). Mỗi nhân vật tối đa một guild. (2) Tối đa `guild.maxMembers` **20** người. Vai trò: **master** (1), **assistant** (tối đa `guild.maxAssistants` **2**), member. (3) Quyền: master và assistant mời được; master đuổi được mọi người, assistant đuổi được member; chỉ master phong / hạ assistant và giải tán; master không rời được mà phải giải tán (chưa có chuyển master). Lời mời hết hạn sau 30 s. (4) **DB:** bảng `guilds (id, name, master_id, created_at)` và `guild_members (character_id PK, guild_id, role, joined_at)`, migration mới có **CHANGE_REASON** (KB §9 chưa có). (5) Chat GUILD bật (`/g nội dung`). Tên guild hiện dưới tên nhân vật `<Tên guild>`. (6) UI: Menu → **[🛡 Guild]** mở panel full-screen: chưa có guild thì có form tạo; có guild thì danh sách thành viên (vai trò, cấp, online), nút mời theo tên, đuổi, phong / hạ, rời, giải tán; mời cũng làm được từ menu người chơi. **Không có NPC guild riêng** |
| P4-6 **ĐÃ LÀM (P4-M4)** | **Guild war** | (1) Master guild A gửi `guild_war_declare {guild}`; master guild B có 60 s để `guild_war_accept` / `guild_war_decline`. Mỗi guild chỉ một war một lúc. (2) Trong war, thành viên hai guild đánh nhau được ở mọi chỗ ngoài safe zone; AOE trúng người guild địch. Kill không tính PK, không rơi đồ. (3) Mỗi kill người guild địch +1 điểm. War kết thúc khi một bên đạt `guildWar.scoreToWin` **20** điểm, hoặc hết `guildWar.durationMinutes` **30** phút (điểm cao hơn thắng, bằng thì hòa), hoặc master một bên đầu hàng (`guild_war_surrender`). (4) Không thưởng (Phase 5 mới có kinh tế). Kết quả báo SYSTEM cho hai guild; tên địch hiện màu tím. War chỉ trong RAM: server khởi động lại thì hủy |
| P4-7 | **Protocol** (`KB_TECHNICAL §5` chưa có) | Act: `attack {target}` nhận cả id người chơi (`p_…`); `duel_*` (P4-4); `guild_create {name}`, `guild_invite {to}`, `guild_accept {guild}`, `guild_decline {guild}`, `guild_leave {}`, `guild_kick {name}`, `guild_promote {name}`, `guild_demote {name}`, `guild_disband {}`, `guild_war_*` (P4-6); nhóm rate-limit `pvp` 5 / giây. Event: `spawn` / `player` thêm `pkState`, `guild`; `duel`, `guild {…}`, `guild_invite {from, guild}`, `guild_war {…}`. Lỗi dùng mã sẵn có (`FORBIDDEN`, `INVALID_TARGET`, `OUT_OF_RANGE`, `REQUIREMENT_NOT_MET`, `NOT_ENOUGH_ZEN`). Em ghi `CHANGE_REASON`; anh bổ sung KB sau khi chốt |
| P4-8 **ĐÃ LÀM (P4-M1)** | Chết vì người chơi | Hồi sinh ở thị trấn như chết vì quái (§11). Buff mất như Phase 2. Không mất EXP. Kẻ giết **không nhận EXP / Zen** (tránh nuôi nick) |
| P4-9 **ĐÃ LÀM (P4-M5)** | Danh sách nghiệm thu Phase 4 | 12 mục, kết quả ở `docs/ACCEPTANCE_PHASE4.md` |
| P4-10 | **KB_TECHNICAL §5 / §9** cần anh bổ sung sau khi chốt P4-2 … P4-7 | Em ghi `CHANGE_REASON` khi làm |

### P4-M1. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Vấn đề | Đã làm / đề xuất |
|---|---|---|
| P4M1-1 **ĐÃ QUYẾT: theo đề xuất** | **Sát thương PvP rất thấp ở cấp thấp:** DK cấp 10 tay không, chưa cộng điểm đánh DK cấp 10 chỉ ~1 / đòn (sau thủ, × 0,5) → giết người 30 HP mất ~30 s | Giữ `pvp.damageMultiplier` 0,5 (người chơi thật có vũ khí + cộng điểm); xem lại khi chơi thử, có thể nâng lên 0,75–1,0 |
| P4M1-2 **ĐÃ QUYẾT: theo đề xuất** | Thành viên **cùng nhóm** vẫn đánh được nhau (P4-2 không nói) | Đang cho phép (bị tính PK như thường); đề xuất **cấm đánh người cùng nhóm** — anh quyết |
| P4M1-3 **ĐÃ QUYẾT: theo đề xuất** | Rơi đồ PK: loot protect thuộc **kẻ giết** (DEC-114) | Muốn ai cũng nhặt ngay thì đổi thành không có chủ |
| P4M1-4 | **KB cần anh bổ sung** (gộp P4-10): `attack.target` nhận `p_<id>`; `spawn` người chơi thêm `pkState`, `aggressor`; `player.view.pkPoints / pkState`; join `config.pvp {enabled, minLevel}`; config `pvp`, `pk` | Đã làm, không đổi schema (cột PK có sẵn) |
| P4M1-5 | Lỗi HUD sau hồi sinh có từ Phase 2 (DEC-117) | Đã sửa |

### P4-M2. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Vấn đề | Đã làm / đề xuất |
|---|---|---|
| P4M2-1 | "Một bên đi xa quá 20 ô thì người đó thua" — cần biết ai đi xa | Người **xa trung điểm lúc bắt đầu hơn** thua (DEC-122) |
| P4M2-2 | Duelist có bị quái đánh không? | Có (chết vì quái thì thua duel); duel chỉ "khoanh" người với người |
| P4M2-3 | Đang duel có được vào thị trấn? | Được, nhưng trong safe zone không đánh được nhau; đi xa quá 20 ô thì thua |
| P4M2-4 | **KB cần anh bổ sung** (gộp P4-10): act `duel_request / accept / decline / cancel`, event `duel`, `spawn.dueling`, config `duel`, nhóm rate-limit `pvp` | Đã làm, không đổi schema |

### P4-M3. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Vấn đề | Đã làm / đề xuất |
|---|---|---|
| P4M3-1 **ĐÃ QUYẾT: theo đề xuất** | P4-5 (1) ghi "audit Zen" nhưng KB §9 **không có bảng audit Zen** (chỉ `item_audit_log`) | Ghi một dòng log server mỗi lần tạo guild (DEC-126). Muốn lưu DB thì cần bảng `zen_audit_log` (đổi schema, CHANGE_REASON) — anh quyết |
| P4M3-2 **ĐÃ QUYẾT: theo đề xuất** | Giải tán / bị đuổi khi đang **offline** | Không báo riêng; vào game lại thì thấy không còn guild (event `guild` rỗng). Có thể gửi thư hệ thống nếu anh muốn |
| P4M3-3 **ĐÃ QUYẾT: theo đề xuất** | Xóa nhân vật là master | FK `master_id ON DELETE CASCADE` → guild bị xóa theo (thành viên mất guild). Chưa có chuyển master (P4-5 (3)) |
| P4M3-4 **ĐÃ QUYẾT: theo đề xuất** | Cấp thành viên trong danh sách | Đọc lại khi có thay đổi thành viên / khi một thành viên vào game, không cập nhật ngay mỗi lần lên cấp (DEC-127) |
| P4M3-5 **ĐÃ QUYẾT: theo đề xuất** | Tên guild chỉ chữ cái **không dấu** + số (`^[A-Za-z0-9]{3,8}$`, theo P4-5 (1) "ASCII") | Giữ; muốn cho tiếng Việt có dấu thì đổi `guild.namePattern` + cột `VARCHAR`/CHECK |
| P4M3-6 | **KB cần anh bổ sung** (gộp P4-10): bảng `guilds`, `guild_members` (§9); act `guild_*`, event `guild`, `guild_invite`, `spawn.guild`, join `config.guild`, nhóm rate-limit `guild` (§5); config `guild` | Đã làm (migration có CHANGE_REASON) |

### P4-M4. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Vấn đề | Đã làm / đề xuất |
|---|---|---|
| P4M4-1 **ĐÃ QUYẾT: theo đề xuất** | P4-6 nói "đánh nhau được ở mọi chỗ ngoài safe zone" — có bỏ cấp tối thiểu PvP không? | Giữ `pvp.minLevel` 6 (thành viên cấp < 6 không đánh / bị đánh), như mọi PvP khác |
| P4M4-2 **ĐÃ QUYẾT: theo đề xuất** | Hai người cùng nhóm nhưng thuộc hai guild đang war | Nhóm thắng: không đánh được nhau (P4M1-2) |
| P4M4-3 **ĐÃ QUYẾT: theo đề xuất** | Tuyên chiến khi master bên kia offline | Không được (`INVALID_TARGET`); không có lời mời chờ offline |
| P4M4-4 **ĐÃ QUYẾT: theo đề xuất** | Nuôi điểm bằng nick phụ (kill liên tục một người) | Không thưởng nên không chặn; Phase 5 có thưởng thì cần luật (vd. cùng nạn nhân chỉ tính 1 lần / x phút) |
| P4M4-5 | **KB cần anh bổ sung** (gộp P4-10): act `guild_war_*`, event `guild_war`, config `guildWar` | Đã làm, không đổi schema (war chỉ trong RAM) |

### P4-M5. Nghiệm thu Phase 4 (2026-10-03) — chi tiết `docs/ACCEPTANCE_PHASE4.md`

12/12 mục PASS (mục 11 UI cần anh xem bằng mắt). Việc chờ anh: B-11 (KB bổ sung P4-10), B-9
(`CLAUDE.md`), B-7, B-10 — xem `ACCEPTANCE_PHASE4.md §5.2`. **B-12 đã quyết (2026-10-03): theo đề
xuất** (P4M4-1 … 4).

## P5. Câu hỏi Phase 5 "Economy" (kế hoạch: `docs/PHASE5_PLAN.md`) — ⛔ = chặn milestone

KB Phase 5 có: bảng upgrade +0 → +9 (`KB_CONFIG §5`), cách chốt trade (`KB_TECHNICAL §10`), schema
item / audit (`§9`), danh sách jewel (`KB_ITEM_REFERENCE`). Thiếu: nguồn jewel, chỉ số theo +N, Jewel
of Life, luật trade, audit Zen. Mọi số dưới đây là **đề xuất IMPLEMENTATION** (tham khảo cảm giác
MU, không coi là số MU gốc), chỉ làm sau khi anh duyệt.

| # | Câu hỏi | Đề xuất của em |
|---|---|---|
| P5-1 **ĐÃ QUYẾT: theo đề xuất (giữ tắt)** | **KB mâu thuẫn:** `KB_00_RULES` S6 ghi Wings / Harmony / Guardian / Creation "bật ở Phase 5"; `§7` (nguồn duy nhất về scope) đặt Wings ở Phase 6, Phase 5 không có Harmony / Guardian / Creation; `KB_CONFIG §5` ghi upgrade trên +9 là `LATER_VERSION` | Theo `§7`: **giữ tắt cả bốn** trong Phase 5 (`features.wings / harmonyJewel / guardianJewel` vẫn `false`, không có template Creation). Anh sửa S6 trong KB nếu đồng ý |
| P5-2 **ĐÃ LÀM (P5-M1)** | **Jewel** — template, nguồn, giá | (1) Ba template `jewel_bless`, `jewel_soul`, `jewel_life` (group 14 / 13, 14, 16), stack tối đa `20`, icon theo `iconRef` (thiếu thì placeholder + cảnh báo build như item khác). (2) **Chỉ rơi từ quái**: thêm nhóm drop `jewels` cho quái cấp ≥ `10` (Lich trở lên), tỉ lệ mỗi lần hạ `0,6 %` × `dropMultiplier`, trọng số Bless 50 / Soul 35 / Life 15 (≈ 4–5 jewel / giờ săn liên tục; chỉnh bằng simulator). Spider / Budge Dragon / Bull Fighter / Hound không rơi. (3) **Không bán ở NPC**; NPC mua lại: Bless `10 000`, Soul `15 000`, Life `15 000` Zen. (4) Jewel cất kho, trade, vứt như đồ thường |
| P5-3 **ĐÃ LÀM (P5-M1, P5-M2)** | **Upgrade** — +N cộng gì, thao tác | (1) **Chỉ số theo +N** (config `items.levelBonus`, KB chưa có): vũ khí `attackMin` / `attackMax` **+3 mỗi cấp**; giáp (mũ, áo, quần, găng, giày) `defense` **+3 mỗi cấp**; khiên `defense` **+2 mỗi cấp**; nhẫn **không ép được**. Yêu cầu sức mạnh / cấp của đồ không đổi theo +N. (2) Ép **đồ trong túi** (không ép đồ đang mặc, như MU): kéo jewel thả lên món đồ; trên mobile bấm jewel → [Ép lên…] → chọn đồ. Mỗi lần dùng 1 jewel, **không tốn Zen**. (3) Bless chỉ dùng cho +0 … +5 (lên +1 … +6, 100 %); Soul cho +6 … +8 (70 / 60 / 50 %); dùng sai loại → `INVALID_TARGET`; đã +9 → `FORBIDDEN`. (4) Soul thất bại `DECREASE` = **giảm 1 cấp** (+7 hỏng → +6), mất jewel. (5) `luck` (chưa có roll lúc drop) không cộng tỉ lệ ở Phase 5. (6) Kết quả: thông báo cho người ép + dòng SYSTEM cả map khi lên **+7 trở lên** |
| P5-4 **ĐÃ LÀM (P5-M2): (A)** | **Jewel of Life** — §9 chưa có cột "option" | **(A, đề xuất)** Thêm cột `items.option_level SMALLINT 0..4` (migration + CHANGE_REASON). Mỗi lần dùng Life trên vũ khí / giáp / khiên: 50 % lên 1 cấp option (tối đa 4), thất bại **không đổi** (mất jewel). Option cộng **+4 mỗi cấp**: vũ khí `attackMin` / `attackMax`, giáp / khiên `defense`. (B) Chỉ làm Bless / Soul, để Life sang Phase 6 (Chaos Machine) |
| P5-5 **ĐÃ DUYỆT** | **Trading** — luật + UI | (1) Mời từ menu người chơi **[🤝 Giao dịch]**, người kia nhận trong `30` s. Hai bên cùng map, cách ≤ `5` ô, còn sống, không đang duel / trade khác. Trong / ngoài thị trấn đều được, MURDERER vẫn trade được. (2) Mỗi bên đặt tối đa `16` món **từ túi** (không đồ đang mặc / trong kho) và một lượng Zen (0 … Zen đang có). (3) Hai bước: **[Khóa]** (chốt danh sách) → khi cả hai đã khóa mới bấm **[Đồng ý]**; bất kỳ thay đổi nào (thêm / bớt món, đổi Zen, món trên bàn bị di chuyển) → cả hai về chưa khóa. (4) Chốt: một transaction theo `KB_TECHNICAL §10`; bên nhận không đủ chỗ → `INVENTORY_FULL`, trade vẫn mở, cả hai về chưa khóa. (5) Hủy khi: bấm [Hủy], cách nhau > `10` ô, đổi map, chết, mất kết nối, đăng xuất, hết `3` phút không chốt. (6) Audit: mỗi món `TRADE` (`char:A → char:B`), Zen ghi `zen_audit_log` hai bên. (7) UI: cửa sổ hai nửa "Của bạn" / "Của <tên>" (icon, +N, số lượng, Zen, trạng thái khóa / đồng ý); kéo đồ từ túi vào hoặc bấm đồ → [Đưa vào giao dịch]; mobile xếp dọc. Nhóm rate-limit `trade` 5 / giây |
| P5-6 **ĐÃ DUYỆT** | **Audit Zen + anti-dupe** | (1) Bảng mới `zen_audit_log (id, character_id, delta, balance, reason, ref, at)` (migration + CHANGE_REASON), ghi **trong cùng transaction** với mọi đổi Zen: mua / bán NPC, nhặt Zen (tức là Zen rơi từ quái — gộp theo lần lưu nhân vật, reason `MONSTER`, để không ghi mỗi con), thư, tạo guild, trade. Khi chạy migration ghi một dòng `BASELINE` = Zen hiện có của mỗi nhân vật. (2) `mix mu.audit` (chỉ quản trị): serial trùng; item không có chỗ (orphan); chỗ hiện tại khác `to_owner` của dòng audit cuối; Zen nhân vật ≠ tổng `zen_audit_log`; tổng cung Zen + nguồn / chỗ tiêu theo ngày. Có sai lệch → in chi tiết, thoát mã ≠ 0. (3) Không tự khóa tài khoản; chạy sau soak / theo lịch quản trị. Bỏ P4M3-1 (log tạo guild) sang bảng này |
| P5-7 **ĐÃ DUYỆT** | **Protocol** (`KB_TECHNICAL §5` chưa có) | Act: `upgrade {itemId, jewelId}` (idempotent theo `rid` như act item); `trade_request {to}`, `trade_accept {from}`, `trade_decline {from}`, `trade_put {itemId, quantity?}`, `trade_take {itemId}`, `trade_zen {amount}`, `trade_lock {}`, `trade_confirm {}`, `trade_cancel {}`. Event: `trade {state, partner, mine: {items, zen, locked, confirmed}, theirs: {…}, result?}`, `trade_invite {from}`; kết quả ép đồ qua `player` + dòng thông báo. Lỗi dùng mã sẵn có. Em ghi `CHANGE_REASON`; anh bổ sung KB sau khi chốt |
| P5-8 **ĐÃ DUYỆT** | Ngoài scope Phase 5 | **Repair / độ bền** (§17 nhắc "sink Zen: repair" nhưng §7 không có, hệ độ bền chưa làm), roll **luck / excellent** khi drop, trên +9 (Harmony / Guardian), Chaos Machine (Phase 6) — **không làm** ở Phase 5 |
| P5-9 | Danh sách nghiệm thu Phase 5 | Em soạn ở P5-M5 (như P4-9) |
| P5-10 | **KB_TECHNICAL §5 / §9** cần anh bổ sung sau khi chốt P5-2 … P5-7 | Em ghi `CHANGE_REASON` khi làm |

### P5-M1. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Vấn đề | Đã làm / đề xuất |
|---|---|---|
| P5M1-1 **ĐÃ QUYẾT: giữ 0,6 %** | Ước lượng "≈ 4–5 jewel / giờ" của P5-2: simulator ra DW / ELF / MG 5,0–5,3 nhưng **DK 2,6** jewel / giờ (DK giết quái cấp ≥ 10 chậm gần gấp đôi) | Giữ 0,6 % cho mọi quái (DEC-143). Muốn DK theo kịp thì nâng lên ~1 % (class khác thành ~8 / giờ) — anh quyết |
| P5M1-2 **ĐÃ QUYẾT: theo đề xuất** | Icon jewel (`item_14_13 / 14 / 16`) chưa có trong bộ icon local thì hiện placeholder (cảnh báo build như item khác) | Anh đặt icon tay ở `assets_src/private/item_icons/` như các item MU khác |
| P5M1-3 | **KB cần anh bổ sung** (gộp P5-10): config `items.levelBonus`, template type `JEWEL`, join `config.items.levelBonus` | Đã làm, không đổi schema (`items.item_level` có sẵn) |

### P5-M2. Phát sinh khi làm (đã làm theo đề xuất, anh xác nhận hoặc đổi)

| # | Vấn đề | Đã làm / đề xuất |
|---|---|---|
| P5M2-1 | P5-7 ghi kết quả ép "qua `player` + thông báo", nhưng Soul hỏng chỉ giảm cấp → client không phân biệt được "thành công lên +7" với "hỏng rơi về +5" chỉ từ `player` | Thêm event riêng `upgrade {…, ok, level, option}` (DEC-147) |
| P5M2-2 | `onFailure: DECREASE` trên bảng có thể đưa đồ +6 về +5, rồi Bless dùng lại được (+5 → +6 luôn thành công) | Đúng theo bảng KB; vòng "ép Soul hỏng → Bless lại" tốn 1 Soul + 1 Bless mỗi lần hỏng |
| P5M2-3 | **KB cần anh bổ sung** (gộp P5-10): §9 cột `items.option_level`; §5 act `upgrade`, event `upgrade`, `item.optionLevel`; config `upgrade` (bảng §5 + `life`, `announceFromLevel`) | Migration có CHANGE_REASON |

