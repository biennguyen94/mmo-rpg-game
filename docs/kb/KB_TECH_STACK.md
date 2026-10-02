# KB_TECH_STACK — Elixir + 2D Web (IMPLEMENTATION)

> Ghi đè các phần infra trong `KB_TECHNICAL.md` §1–2 (không dùng Redis / Game Gateway riêng; OTP đảm nhiệm).
> Mẫu tham khảo kiến trúc: https://github.com/biennguyen94/rpg-game (Elixir + Phoenix + PostgreSQL). Nội dung dưới đây dựa trên README của repo, chưa đọc source.
> Module nào của repo tái dùng/sửa/viết lại: xem `KB_BASE_REPO.md`.
>
> ⚠️ **File này override `KB_TECHNICAL.md §1–2`.**
> Khi có mâu thuẫn về infra (Redis, Gateway, architecture), **file này thắng**.
> Khi có mâu thuẫn về DB schema, protocol, security → `KB_TECHNICAL.md` thắng.
>
> **Không dùng Redis.** Session/presence/lock do OTP (`Registry`, `ETS`, `GenServer`) đảm nhiệm.

## 1. Stack

| Lớp | Chọn | Ghi chú |
|---|---|---|
| Server | Elixir ≥ 1.14, Phoenix, Phoenix Channels (WebSocket) | |
| DB | PostgreSQL + Ecto | Schema ở KB_TECHNICAL §9 |
| Client render | **Phaser 3** (hoặc PixiJS) + TypeScript | Canvas/WebGL 2D; nhúng vào `priv/static` |
| Net client | `phoenix` JS client | Kênh `"game"` |
| Tilemap | Tiled (`.tmj`) → convert sang JSON/collision | |
| Hash password | `argon2_elixir` | Repo mẫu dùng PBKDF2; KB chọn Argon2id |
| Rate limit | `hammer` hoặc module tự viết | |
| Item serial | ULID (`ecto_ulid`) | Do server sinh |
| Deploy | Docker + Caddy (TLS) | Repo mẫu có sẵn Dockerfile/compose |
| CI | GitHub Actions: `mix format --check`, compile warnings-as-errors, `mix test` | |

## 2. Điểm nên học từ repo mẫu

- **1 process `Session` / account**: lệnh xử lý tuần tự → chống race, chống dupe đồ khi mở nhiều tab. Lưu DB sau mỗi thay đổi quan trọng; idle thì tự tắt.
- **1 process `MapServer` / map**: giữ vị trí quái + người chơi, xử lý tuần tự (ai đến trước đánh trước).
- **Engine = hàm thuần** (`engine.ex`), `Commands` validate input → gọi Engine. Dễ test.
- **Dữ liệu trong JSON** (`game_data.json`, `maps/*.json`), client nhận từ server, không chứa công thức.
- **Client chỉ gửi ý định**; server trả `player` + `view` (chỉ số tính sẵn).
- **Simulator bot** (`mix …simulate`) để kiểm tra cân bằng EXP/độ khó.
- Token hash trong DB, thu hồi được; rate-limit đăng nhập; mô-đun moderation/admin từ sớm.
- Test kiểm tra map: cổng nối hai chiều, vị trí spawn hợp lệ.

## 3. Điểm KHÁC: repo mẫu là turn-based, MU là real-time

Repo mẫu: đi từng ô, bước vào quái → trận theo lượt. MU: click-to-move/click-to-attack real-time.
→ **Tái dùng**: kiến trúc process, Commands/Engine, data JSON, auth, moderation, CI/deploy.
→ **Viết lại**: Engine combat (cooldown, range, AoE, hit/crit), movement (liên tục hoặc theo ô nhưng tick-based), monster AI loop.

**Quyết định cần chốt (D1):**

| Lựa chọn | Mô tả | Ước lượng |
|---|---|---|
| A. Real-time, di chuyển theo ô (grid) | Tick 20 Hz, entity đứng trên ô, đi ô-qua-ô mượt bằng interpolation. Gần MU, dễ validate | **Khuyến nghị** |
| B. Real-time, tọa độ liên tục | Va chạm/pathfinding phức tạp hơn | Chậm hơn |
| C. Turn-based như repo mẫu | Dễ nhất nhưng mất cảm giác MU | Nhanh nhất |

**Đã chốt: A** (`KB_00_RULES` S9; `KB_BASE_REPO §2` cũng dựa trên A).

## 4. Kiến trúc OTP

```
Application
├── Repo (Ecto)
├── Phoenix.PubSub
├── Registry (session, map)
├── DynamicSupervisor: Session   (1 / account đang online)
├── DynamicSupervisor: MapServer (1 / map)
├── DynamicSupervisor: Trade     (TradeSettlement, 1 / trade đang mở — Phase 5)
├── WorldBoss, Chat, RateLimit, Leaderboard
└── Endpoint (Channels)
```

**MapServer (GenServer)**
- State: entities (players, monsters, ground items), spatial grid (AOI cell 16×16), collision grid.
- Loop: `Process.send_after(self(), :tick, 50)` (20 Hz) bù drift bằng thời gian thực; AI chạy mỗi 2 tick (10 Hz).
- Command từ Session: `cast`/`call` vào MapServer (`move_to`, `attack`, `use_skill`, `pickup`).
- Broadcast: delta theo AOI qua PubSub topic `map:<id>:cell:<x>:<y>` (client subscribe ô quanh mình) hoặc gửi trực tiếp tới channel pid.
- Monster ở vùng không có player: `sleep` (không tick AI).

**Session (GenServer)**
- Giữ character state, inventory, equipment, cooldown skill.
- Validate (class/level/stat/ownership) rồi mới gọi MapServer / ghi DB.
- Ghi DB debounce 30–60s + ngay khi giao dịch item/Zen/level up/logout (Ecto.Multi, optimistic lock `version`).
- Reconnect: Session sống `reconnectGraceSeconds` sau khi channel đóng.

**Pathfinding**: A* trên collision grid, viết thuần Elixir; monster giới hạn độ sâu + cache; nếu thành bottleneck → Rustler NIF.

**Scale**: bắt đầu 1 node. Muốn nhiều node: `libcluster` + `Horde`/phân map theo node. Không cần Redis.

## 5. Protocol (Channels)

Định nghĩa đầy đủ (event `cmd` `{act, rid, ...}`, snapshot/combat/player/spawn/despawn/chat/error, error codes) nằm **duy nhất** ở `KB_TECHNICAL §5`. Không định nghĩa lại ở đây.

Bắt đầu bằng JSON; cân nhắc binary (MessagePack) nếu băng thông thành vấn đề.

## 6. Client (Phaser)

- Scenes: Boot/Preload → Login → CharacterSelect → World (+ UI overlay).
- Render map từ tilemap; entity sprite theo state (idle/walk/attack/die) × hướng.
- **Interpolation**: vẽ entity tại thời điểm `now - interpolationDelayMs`; click-to-move hiện marker, vẽ trước (prediction) nhưng chấp nhận correction từ server.
- UI (DOM overlay hoặc Phaser UI): HP/MP, skill bar, inventory, equipment, chat, party, tooltip item.
- Dữ liệu tĩnh (item/monster/skill) lấy từ server lúc join, không nhúng công thức.
- Mobile (Phase 1): touch = click-to-move; tap quái mở context menu; dock + nút nổi HP/MP/Nhặt (xem `KB_GAME_DESIGN §19`).

## 7. Cấu trúc project (Phoenix)

```
mu_web/
├── lib/mu/
│   ├── accounts.ex  game/{engine,commands,session,characters,items,skills,drops,party,pvp}.ex
│   ├── world/{map_server,maps,pathfinding,aoi,monster_ai}.ex
│   └── chat.ex  moderation.ex  rate_limit.ex  leaderboard.ex  simulator.ex
├── lib/mix/tasks/        (mu.items.import, mu.icons.index — KB_ITEM_REFERENCE §6; bản tham chiếu Python: scripts/parse_items.py)
├── lib/mu_web/{channels,controllers}/
├── priv/
│   ├── reference/        (items_raw.json: REFERENCE thuần, không phục vụ cho client)
│   ├── game_data/{classes,monsters,skills,items,drops,shop}.json
│   ├── maps/*.json  (+ collision)
│   └── static/{index.html, js/, assets/{sprites,tiles,icons,audio}}
├── assets_src/ (Tiled, Aseprite, atlas nguồn)
│   └── private/      (item_icons/, equip_layers/ — MU-derived, GITIGNORE; KB_ASSETS §2.2)
├── config/  deploy/  docs/  test/  .github/workflows/
```

## 8. Test & cân bằng

- Unit test Engine (damage, hit, EXP, drop roll với seed cố định).
- Test map: collision hợp lệ, portal hai chiều, spawn không nằm trong tường.
- Simulator bot: mô phỏng số lần giết/EXP để level 1→N, kiểm tra độ khó.
- Load test WebSocket (vd. `k6`/`tsung`) mục tiêu 500 CCU/world.

## 9. Phase 1 checklist (Elixir)

1. `mix phx.new`, Accounts + token + Channel `"game"`.
2. Schema `characters`, tạo DK. Dữ liệu item Phase 1: `data/items/phase1.json` + `icon_map.json` (`KB_ITEM_REFERENCE §5–§6`).
3. MapServer Lorencia: collision, tick 20 Hz, move_to + A*.
4. Spider spawn + AI (IDLE→CHASE→ATTACK→RETURN).
5. Engine: hit/damage/EXP/level/stat/drop.
6. Client Phaser: render map, click-to-move, click-to-attack, HP bar, inventory/equip.
7. Save/load (persistence). Reconnect giữa phiên là Phase 3; 2 player thấy nhau bằng broadcast đơn giản, chưa cần AOI.
