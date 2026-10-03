# PHASE1_PLAN — Kế hoạch Phase 1 (vertical slice)

> Viết ở M0, trước khi có code. Nguồn: `docs/kb/` (đọc đủ theo thứ tự trong `CLAUDE.md`), source + test của `reference/rpg-game/` tại commit `5c514b7512183d714afb1d35ad310fa4a62f2a5d` (`reference/COMMIT`).
> Scope duy nhất: `KB_00_RULES §7`. Câu hỏi mở: `docs/OPEN_QUESTIONS.md`. Môi trường: `docs/CLOUD_CHECK.md`.
> **M1 bị chặn** cho tới khi xong E1–E4 trong `OPEN_QUESTIONS.md` (chưa có Elixir, Hex bị chặn).

## 1. Repo nền: hiện trạng đọc được từ source

- App `:hac_long`, Phoenix 1.7 (chỉ JSON API + Channels, không LiveView), Ecto/Postgres, Bandit, `pbkdf2_elixir`. Elixir `~> 1.14` trong `mix.exs` nhưng `mix.lock` cần ≥ 1.15; CI chạy 1.17/OTP 25.
- **Chiến đấu theo lượt** nằm trong trạng thái nhân vật (`player.battle`), bước vào ô quái → trận; `Engine` (1231 dòng) là hàm thuần dùng `Rng` (dãy số cố định cho test).
- **MapServer** không có vòng tick: hướng sự kiện (gọi `step`), quái đi lang thang theo timer, gom thay đổi rồi phát **toàn bộ** trạng thái map qua PubSub (`map:<id>`). Không có A*, không có snapshot delta.
- **Session** (1 GenServer/tài khoản, Registry + DynamicSupervisor): xử lý lệnh tuần tự, token bucket chống spam (`@step_ms`, `@act_ms`), ghi DB sau **mọi** thay đổi (vị trí ghi dồn 5s), tắt sau 10 phút rảnh; nhiều tab cùng gắn vào một Session.
- **Nhân vật lưu dạng map JSON** (`inv`, `equip`, `stats`, `battle`… là cột `:map`) → trái với KB (§9: không lưu inventory dạng blob, cần `items` + `item_locations`).
- **Auth**: bảng `users` (id integer), PBKDF2, token 32 byte băm SHA-256 lưu `user_tokens`, hạn 30 ngày, socket vào bằng `?token=`. Rate-limit ETS cửa sổ cố định (`RateLimit.hit/3`) cho đăng nhập/đăng ký.
- **Dữ liệu game**: một file `priv/game_data.json`, đọc lúc biên dịch (`Data`), gửi cho client qua `window.GAME_DATA`.
- **Bản đồ**: `priv/maps/*.json` dạng hàng ký tự (`tiles`) + legend, đọc lúc biên dịch (`Maps`); test kiểm cổng hai chiều và ô spawn đi được.
- **Client**: JS thuần (`net.js`, `ui.js` 2100 dòng, `map.js`, `sound.js`, `doll.js`), không bundler.
- **Ops**: Dockerfile release nhiều tầng, compose + Caddy, `rel/overlays/bin/start` chạy migrate, CI GitHub Actions (format, warnings-as-errors, test).
- Ngoài scope Phase 1 (có trong repo, **bỏ**): tháp, câu cá, thú cưng, nhà/trang trí, nấu ăn/rèn/nâng cấp, rương, sự kiện, sổ tay quái, chuyển sinh, thành tựu, hướng dẫn, nhiệm vụ, việc hằng ngày, bạn bè/tin riêng, bang hội, tổ đội, giao dịch, chợ, đấu trường, trùm thế giới, hộp thư, chat thế giới, bảng xếp hạng, moderation/admin, ngày-đêm.

## 2. Quyết định REUSE / ADAPT / REWRITE / SKIP theo module

Mức như `KB_BASE_REPO §3`. Cột "Đọc" = đã mở source **và** test. Ghi nguồn gốc chi tiết từng file ở `docs/REUSE_LOG.md` khi thực sự copy (M1+).

### 2.1 Hạ tầng (M1)

| Module repo nền | Đọc | Quyết định | Đích (namespace Mu) | Lý do |
|---|---|---|---|---|
| `mix.exs`, `.formatter.exs`, `config/*.exs`, `test/support/{conn,data,channel}_case.ex` | ✅ | ADAPT | cùng tên | Đổi app/namespace; thay `pbkdf2_elixir` → `argon2_elixir`; thêm config game; bỏ config world boss/wander/event |
| `lib/hac_long/application.ex` | ✅ | ADAPT | `lib/mu/application.ex` | Giữ Repo, PubSub, RateLimit, Registry + DynamicSupervisor Session; thêm `WsTicket` (ETS), MapServer Lorencia; bỏ Chat/WorldBoss/Party/Trade |
| `lib/hac_long/rate_limit.ex` | ✅ | REUSE | `lib/mu/rate_limit.ex` | Cửa sổ cố định trên ETS, đúng yêu cầu; thêm khóa theo `act` |
| `lib/hac_long_web/remote_ip.ex` (+ test) | ✅ | REUSE | `lib/mu_web/remote_ip.ex` | Không có gì cần đổi |
| `lib/hac_long_web/{endpoint,router,telemetry}.ex`, `controllers/error_json.ex` | ✅ | ADAPT | `lib/mu_web/…` | Route theo KB §4 (`/login`, `/ws-ticket`…); **không log query string** (ticket) |
| `lib/hac_long/accounts.ex`, `accounts/user.ex`, `accounts/user_token.ex` (+ test) | ✅ | ADAPT | `lib/mu/accounts.ex`, `accounts/{account,access_token}.ex` | Bảng `accounts` UUID theo §9 (username ci-unique, email); Argon2id; token băm giữ nguyên ý tưởng nhưng TTL ngắn (P5); bỏ ban/mute (moderation Phase 2) |
| — | — | MỚI | `lib/mu/accounts/ws_ticket.ex` | Ticket 1 lần trong ETS, TTL 30s, xóa ngay khi dùng (KB §4) |
| `controllers/auth_controller.ex` (+ test) | ✅ | ADAPT | `lib/mu_web/controllers/auth_controller.ex` | Giữ rate-limit đăng nhập/đăng ký; thêm `/ws-ticket`; bỏ đổi mật khẩu/đăng xuất mọi thiết bị (không trong scope) |
| `controllers/page_controller.ex` | ✅ | REWRITE | `lib/mu_web/controllers/page_controller.ex` | Chỉ phục vụ `index.html` của client Phaser; dữ liệu tĩnh gửi lúc `join` (KB_TECH_STACK §6) |
| `channels/user_socket.ex` | ✅ | ADAPT | `lib/mu_web/channels/user_socket.ex` | `connect` bằng `ticket` thay `token`; id socket theo account |
| `channels/game_channel.ex` (+ test 1294 dòng) | ✅ | ADAPT (~10%) | `lib/mu_web/channels/game_channel.ex` | Giữ khung join → attach Session → subscribe; `join` kiểm `clientVersion`/`characterId`; một event `cmd` có `rid`; lỗi theo mã §5; bỏ mọi kênh phụ (guild, party, trade, market, admin…) |
| `lib/hac_long/release.ex`, `rel/overlays/bin/start` | ✅ | ADAPT | `lib/mu/release.ex` | Giữ `migrate/0`; bỏ `admin/2` (moderation) |
| `Dockerfile`, `docker-compose*.yml`, `deploy/Caddyfile`, `.env.example` | ✅ | ADAPT | gốc repo | Đổi tên app; thêm bước `npm ci && npm run build` của client; `.dockerignore` thêm 3 đường dẫn KB_ASSETS §2.2; Caddy không log query string |
| `.github/workflows/ci.yml` | ✅ | ADAPT | `.github/workflows/ci.yml` | Giữ format/compile/test; thêm job client (`npm ci`, `tsc --noEmit`, `vitest`) và bước `git ls-files` rỗng cho đường dẫn MU-derived |
| `deploy/nginx.conf`, `docs/DEPLOY.md` | ✅ | SKIP | — | Dùng Caddy theo KB; DEPLOY viết lại ngắn khi cần (ngoài M0–M6) |

### 2.2 Dữ liệu & nhân vật (M1, M4)

| Module | Đọc | Quyết định | Đích | Lý do |
|---|---|---|---|---|
| `game/data.ex` + `priv/game_data.json` | ✅ | ADAPT | `lib/mu/game/data.ex` + `priv/game_data/*.json` | Giữ cách đọc lúc biên dịch + `@external_resource`; tách file theo loại (KB); kiểm `sourceType/version/verified` khi nạp |
| `game/characters.ex`, `game/character.ex` | ✅ | REWRITE | `lib/mu/game/{characters,character}.ex` | Schema §9 (cột rời, `version` optimistic lock, CHECK); không lưu blob; chỉ học cách `load/save` |
| `game/names.ex` | ✅ | ADAPT | `lib/mu/game/names.ex` | Luật mới `^[A-Za-z0-9]{4,10}$` (ASCII, không NFC) + lọc từ cấm (G22) |
| `game/rng.ex` | ✅ | ADAPT | `lib/mu/game/rng.ex` | Giữ dãy số cố định cho test; thêm RNG có seed (`:rand.seed(:exsss, seed)`) truyền vào Engine |
| `game/commands.ex` (+ test) | ✅ | REWRITE (giữ khung) | `lib/mu/game/commands.ex` | Danh sách `act` §5 khác hẳn; giữ ý "validate → gọi engine, trả `{kết quả, trạng thái}`", ép kiểu số an toàn (`int/1`) |
| `game/session.ex` | ✅ | ADAPT | `lib/mu/game/session.ex` | Giữ: Registry/DynamicSupervisor, `call` có retry khi vừa tắt, token bucket, monitor tab, `trap_exit` + flush khi tắt. Đổi: idempotency theo `rid`, `singleLoginPerAccount` (kick tab cũ), ghi DB debounce 30–60s + ngay khi item/Zen/level/logout, combat ở MapServer chứ không trong Session |
| `game/engine.ex` items/equip/buy/sell | ✅ | REWRITE | `lib/mu/game/inventory.ex` (thuần) + `lib/mu/game/items.ex` (DB) | Repo nền giữ đồ trong map `inv`; KB cần `items`/`item_locations`/audit, serial ULID, stack |
| `game/gear.ex` | ✅ (lướt) | SKIP | — | Đồ chỉ số ngẫu nhiên: Phase 2 (KB_BASE_REPO §3.2) |

### 2.3 World & combat (M2, M3)

| Module | Đọc | Quyết định | Đích | Lý do |
|---|---|---|---|---|
| `world/map_server.ex` | ✅ | REWRITE (giữ khung) | `lib/mu/world/map_server.ex` | Giữ: 1 process/map qua Registry, monitor pid người chơi, topic PubSub, gom thay đổi. Mới: vòng tick 20 Hz bù drift, AI 10 Hz, snapshot delta 10 Hz, monster sleep khi không có người, ground items, respawn |
| `world/maps.ex` + `priv/maps/*.json` + test map | ✅ | ADAPT | `lib/mu/world/maps.ex`, `priv/maps/lorencia.json` + `lorencia.collision.bin` | Giữ đọc lúc biên dịch, grid tuple, `walkable?`; định dạng theo KB_TECHNICAL §8 (`safeZones`, `spawns`, `portals`, `npcs`); map Lorencia ~64×64 tự vẽ |
| `world.ex` | ✅ | REWRITE | `lib/mu/world/movement.ex` | Bước 4 hướng theo lượt → `move_to {x,y}` + A* 8 hướng, kiểm walkable/tốc độ/teleport |
| — | — | MỚI | `lib/mu/world/pathfinding.ex` | A* octile, giới hạn node cho quái |
| — | — | MỚI | `lib/mu/world/monster_ai.ex` | IDLE→CHASE→ATTACK→RETURN (+DEAD/RESPAWN), hàm thuần trên state |
| `game/engine.ex` (combat, level, alloc) (+ test) | ✅ | REWRITE | `lib/mu/game/engine.ex` | Công thức KB §4, §4.1 (DK), §5, §6; cooldown/range/hit/crit; EXP §3; alloc §1. Giữ phong cách hàm thuần + Rng + test seed; học `allocate/3`, `level_up` đệ quy |
| — | — | MỚI | `lib/mu/game/drops.ex` | Drop table KB_CONFIG §4, roll theo seed |
| `game/simulator.ex` + `mix hac_long.simulate` (+ test) | ✅ | ADAPT | `lib/mu/game/simulator.ex`, `lib/mix/tasks/mu.simulate.ex` | Giữ khung báo cáo (số lần chạy, trung bình); viết lại vòng lặp: mô phỏng giết Spider theo thời gian thực (cooldown, hit) bằng Engine, đo số con/thời gian tới cấp 2/5/10, số potion |
| `world/clock.ex` | ✅ | SKIP | — | Ngày/đêm không có trong KB |

### 2.4 Client (M5)

| Thành phần | Đọc | Quyết định | Đích | Lý do |
|---|---|---|---|---|
| `js/net.js` | ✅ | ADAPT → TS | `client/src/net/` | Giữ: lưu token, tự kết nối lại, thanh báo mất mạng, kiểm token khi rớt mạng. Đổi: lấy ticket trước mỗi lần mở socket, `rid` cho mọi `cmd` |
| `js/sound.js` | ✅ (đầu file) | REUSE → TS | `client/src/audio/sound.ts` | Web Audio tổng hợp, không cần file âm thanh (KB_BASE_REPO §3.4) |
| `js/doll.js` | ✅ (đầu file) | SKIP | — | KB_ASSETS §2.1 cấm DCSS cho trang bị nhân vật; Phase 1 không vẽ trang bị lên người (OPEN_QUESTIONS A4) |
| `js/map.js`, `js/ui.js`, `index.html`, `css/style.css` | ✅ (lướt) | REWRITE | `client/src/scenes/`, `client/src/ui/` | Layout mới §19 (dock 4 tab, panel full-screen, context menu, nút mobile) bằng Phaser + DOM overlay |
| Sprite DCSS (`monsters/spider.png`, `monsters/hero.png`, `npcs/merchant.png`, `tiles/{grass,dirt,water,tree,rock,brick,flowers}.png`) | ✅ CREDITS | REUSE có điều kiện | `priv/static/assets/{sprites,tiles}/` + `mapping.json` + `CREDITS.md` | CC0; trước khi copy đối chiếu từng file với `TILES_UNDER_UNKNOWN_LICENSE.md` (đọc được qua raw.githubusercontent.com) |
| Icon game-icons.net | ✅ CREDITS | SKIP | — | Item icon do dự án cung cấp (KB_ASSETS §2.1); UI dùng emoji/hình học |

### 2.5 Bỏ hẳn (SKIP, ngoài Phase 1)

`arena.ex`, `chat.ex`, `friends.ex`, `guilds.ex`, `guild_quests.ex`, `homes.ex`, `leaderboard.ex`, `mailbox.ex`, `market.ex`, `moderation.ex`, `party.ex`, `trade.ex`, `world_boss.ex`, `game/{achievements,bestiary,chests,crafting,daily,events,fishing,home,pets,quests,tower,trade_offer,tutorial}.ex`, `mix hac_long.admin`, 20/27 migration của repo nền (viết migration mới theo §9), mọi map ngoài làng, mọi asset không dùng.

## 3. Cấu trúc thư mục dự kiến

```
/                                 (app :mu, Phoenix không LiveView, không Tailwind)
├── mix.exs  mix.lock  .formatter.exs  .gitignore  .dockerignore
├── Dockerfile  docker-compose.yml  docker-compose.caddy.yml  deploy/Caddyfile  .env.example
├── .claude/settings.json  scripts/cloud_session_start.sh        (hook §A3, M1)
├── .github/workflows/ci.yml
├── config/{config,dev,test,prod,runtime}.exs
├── lib/mu/
│   ├── application.ex  repo.ex  release.ex  rate_limit.ex
│   ├── accounts.ex  accounts/{account,access_token,ws_ticket}.ex
│   ├── game/{data,config,engine,rng,commands,session,characters,character,names,
│   │         inventory,items,item,item_location,item_audit,ulid,drops,skills,simulator}.ex
│   └── world/{map_server,maps,movement,pathfinding,monster_ai}.ex
├── lib/mu_web/{endpoint,router,telemetry,remote_ip}.ex
│   ├── channels/{user_socket,game_channel}.ex
│   └── controllers/{auth,character,page,error_json}.ex
├── lib/mix/tasks/{mu.items.import,mu.icons.index,mu.maps.build,mu.simulate}.ex
├── data/items/phase1.json                  (nguồn, có sẵn)
├── priv/game_data/{config,classes,monsters,skills,items,drops,shop,npcs}.json
├── priv/maps/lorencia.json  priv/maps/lorencia.collision.bin
├── priv/reference/items_raw.json           (chờ E6)
├── priv/repo/migrations/
├── priv/static/index.html  priv/static/js/app.js (build, gitignore)
├── priv/static/assets/{sprites,tiles,icons/{custom,ui,placeholder.png},mapping.json}
├── client/                                 (TypeScript + Phaser 3, build bằng esbuild qua npm)
│   ├── package.json  package-lock.json  tsconfig.json  build.mjs
│   ├── src/{main.ts, net/, scenes/{boot,login,create,world}.ts, ui/, icons/, audio/}
│   └── test/ (vitest)
├── assets_src/private/                     (gitignore + dockerignore; KB_ASSETS §2.2)
├── test/{mu,mu_web,support}/
├── docs/{PHASE1_PLAN,REUSE_LOG,OPEN_QUESTIONS,CLOUD_CHECK,DECISIONS,RUN_LOCAL,ICON_REPORT}.md
└── CREDITS.md
```

`reference/` và `docs/kb/` giữ nguyên, không sửa. `reference/` loại khỏi biên dịch (không nằm trong `elixirc_paths`) và khỏi Docker.

## 4. Kế hoạch từng milestone

Mỗi milestone: nêu ngắn việc sẽ làm + file → code → `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test` (+ `npm test` từ M5) xanh → commit riêng → push nhánh phiên → báo cáo (đã làm, test, lệch KB có `CHANGE_REASON`, câu hỏi mở) → chờ "OK".

| M | Nội dung | Test chính |
|---|---|---|
| **M1** Khung | `mix phx.new`-tương đương bằng tay (không cần Hex archive `phx_new`: copy khung từ repo nền rồi đổi tên), namespace Mu; Docker/CI; migration §9 (`accounts`, `access_tokens`, `characters`, `items`, `item_locations`, `item_audit_log`, partial unique index, CHECK); Accounts + Argon2id + access token băm + WS ticket ETS; RateLimit; `UserSocket` vào bằng ticket; channel `"game"` join `{clientVersion, characterId}`; `POST /characters` tạo DK (1/tài khoản, tên §18); `.gitignore`/`.dockerignore` KB_ASSETS §2.2; hook SessionStart; `priv/game_data/config.json` + `classes.json` | Đăng ký/đăng nhập/sai mật khẩu/rate-limit; token hết hạn; ticket dùng 1 lần, hết hạn 30s; join sai `clientVersion` bị từ chối; tạo DK đúng chỉ số KB_CONFIG §2 (HP 185, MP 30); tên trùng không phân biệt hoa thường; tài khoản thứ 2 nhân vật bị từ chối; migration CHECK chặn dữ liệu sai |
| **M2** World | `maps.ex` + Lorencia 64×64 (safe zone thị trấn, NPC, vùng Spider) + `mu.maps.build` sinh `collision.bin`; MapServer tick 20 Hz, snapshot delta 10 Hz; `move_to` + A* (người chơi), kiểm walkable/biên/tốc độ/tần suất, rubber-band khi sai; Session gắn MapServer; `spawn`/`despawn`; broadcast đơn giản (chưa AOI); lưu vị trí khi logout/định kỳ | Map: spawn hợp lệ, safe zone đúng, NPC/spawn quái không trong tường, collision khớp JSON; A* (đường ngắn nhất, không đường → lỗi); MapServer tick đều (đo drift); 2 client ChannelTest thấy nhau di chuyển; lệnh đi quá xa/đi vào tường bị từ chối |
| **M3** Combat | Engine thuần: derived DK §4.1, pipeline §4, hit §5, cooldown §6, EXP §3/KB_CONFIG, alloc §1, level up; Spider AI 10 Hz (IDLE→CHASE→ATTACK→RETURN, DEAD→RESPAWN 8s, sleep khi vắng người); `attack`, `skill` (twisting_slash), drop (KB_CONFIG §4, ground item sống trong MapServer, loot protect, hết hạn 60s), Zen; chết/hồi sinh; `mu.simulate` cơ bản | Engine với seed cố định (số khớp tay: DK lv1 HP 185, def 5, attackRate 35, cooldown 990ms…); cooldown bị chặn (`COOLDOWN`), ngoài tầm (`OUT_OF_RANGE`), `NO_MANA`; AI chuyển trạng thái đúng, leash 12; EXP/level/maxLevel 10; alloc vượt điểm bị chặn; drop roll theo seed; simulator ra số con Spider tới cấp 2/5/10 (so với 10/170/1110 của KB_CONFIG) |
| **M4** Items | `mu.items.import` (data/items → priv/game_data/items.json, kiểm luật KB_ITEM_REFERENCE §6); ULID tự viết (thuần Elixir, test); `pickup`/`equip`/`unequip`/`use_item`/`buy`/`sell`/`npc_open`; mọi thay đổi item/Zen trong 1 transaction + `item_audit_log`; idempotent theo `rid`; validate class/level/stat/slot/ownership/giá; `mu.icons.index` (input rỗng → placeholder, exit 0, `docs/ICON_REPORT.md`) | Test bắt buộc §6 của KB_ITEM_REFERENCE (trừ test `items_raw.json` nếu E6 chưa có); DK lv1 mặc được ≥1 món mỗi slot; **2 Session thao tác cùng item không nhân đôi** (unique `item_locations.item_id` + transaction); mua thiếu Zen; túi đầy; nhặt đồ của người khác trong 10s → `NOT_OWNER`; `rid` lặp không mua 2 lần |
| **M5** Client | Phaser 3 + TS (esbuild qua npm): Login → tạo DK → World; render map/tile, click-to-move có marker + interpolation 100ms, context menu quái (Tấn công thường / Twisting Slash / Hủy, tự đánh liên tục), dock 4 tab, panel Nhân vật/Túi đồ/Thông báo/Shop, submenu Menu, nút mobile, phím tắt §19.2; icon_map + placeholder; `docs/RUN_LOCAL.md` | vitest: protocol client (rid, ticket), interpolation, chọn potion stack (§19.6), debounce alloc 200ms, chọn icon theo `icon_map` + fallback; Playwright headless chụp 1280px và 360px làm bằng chứng phụ |
| **M6** Nghiệm thu | Chạy từng mục acceptance KB_00 §7 bằng test tự động end-to-end (ChannelTest + client node); bảng pass/fail + bằng chứng; soak ≤ 25 phút (nhiều client bot, chạy nền có timeout); liệt kê cân bằng lệch (Q14 và kết quả simulator) | Bảng acceptance; mục giao diện/mobile: "cần anh kiểm tra local" |

## 5. Rủi ro

| # | Rủi ro | Mức | Giảm thiểu |
|---|---|---|---|
| R1 | Môi trường cloud chưa có Elixir, Hex bị chặn, Elixir apt quá cũ (E1–E3) | **Cao — chặn M1** | Chờ anh sửa môi trường; không lách proxy |
| R2 | Phiên không push được (E5) → mất việc khi VM bị thu hồi | Cao | Cấp quyền GitHub App; nếu chưa, em vẫn commit cục bộ và báo rõ hash chưa lên GitHub |
| R3 | Tick 20 Hz trong một GenServer với A* cho quái làm trễ tick | Trung bình | Giới hạn node A* (32) + cache; đo thời gian tick trong test/soak; quái ngủ khi vắng người |
| R4 | Ground item chỉ trong RAM + pickup ghi DB: race giữa hai người nhặt | Trung bình | MapServer xử lý pickup tuần tự (xóa khỏi map trước khi trả cho Session), Session ghi DB trong transaction; lỗi ghi DB → item trở lại mặt đất |
| R5 | Session (item/Zen) và MapServer (vị trí, combat, drop) cùng sửa trạng thái nhân vật → lệch HP/EXP khi lưu | Trung bình | Một chiều sở hữu: MapServer giữ HP/MP/vị trí khi đang online và đẩy sự kiện (EXP, Zen, chết) về Session; Session là nơi duy nhất ghi DB |
| R6 | Test realtime dễ chập chờn (phụ thuộc thời gian) | Trung bình | Tick điều khiển được trong test (gửi `:tick` thủ công, đồng hồ giả), RNG có seed |
| R7 | Không có sprite/tileset/icon thật | Thấp (đã chốt placeholder) | DCSS CC0 có sẵn + placeholder, ghi `CREDITS.md`, `mapping.json` |
| R8 | Docker build trong cloud (Docker Hub có thể bị chặn) | Thấp | Kiểm Dockerfile bằng CI hoặc local; trong cloud chỉ chạy `mix release` nếu được |
| R9 | Phaser 4 là bản mặc định trên npm | Thấp | Ghim `phaser@3.90.0` |
| R10 | Cân bằng: Leather Armor làm Spider vô hại (Q14), `twisting_slash` chỉ dùng ở cấp 10 | Thấp (đã biết) | Simulator + test potion trước khi mặc áo; báo ở M6 |
| R11 | Câu hỏi G/P chưa trả lời khi tới milestone tương ứng | Trung bình | Dùng mặc định đề xuất, ghi rõ trong báo cáo milestone để anh đổi sau |
