# KB_TECHNICAL — Kiến trúc, DB, Protocol, Security (IMPLEMENTATION)

## 1. Kiến trúc

> §1–2 đã đồng bộ với `KB_TECH_STACK.md` (Elixir + Phoenix + OTP, không Redis, không Game Gateway riêng).
> Nếu có mâu thuẫn về infra, `KB_TECH_STACK.md` thắng.

```
Browser → HTTPS → Phoenix Endpoint → Channel "game"
                                 → Session   (GenServer / account)
                                 → MapServer (GenServer / map)
                                 → Ecto → PostgreSQL
```

Không replicate ConnectServer/JoinServer/DataServer/GameServer của MU.

Phoenix Endpoint đóng vai gateway. MapServer chịu trách nhiệm: movement, combat, monster AI, skills, drops, EXP, items, party, PvP.
Mỗi map/world là một simulation loop riêng; có thể scale ngang bằng cách gán map cho process.

## 2. Realtime loop

| Loop | Tần số | Ghi chú |
|---|---|---|
| Simulation (move, combat) | 20 Hz | Đủ cho web; client nội suy |
| Monster AI | 10 Hz | Chỉ zone có player |
| Snapshot gửi client | 10 Hz | Delta, theo AOI |
| Client interpolation | ~100 ms trễ | Che jitter mạng |

Tần số lấy từ `KB_CONFIG.server`.

DB **không** ghi mỗi tick. Chỉ lưu: định kỳ (30–60s), logout, giao dịch item/Zen, level up, chết khi cần.
Session/presence/state ngắn hạn do OTP (Registry, ETS) đảm nhiệm — xem `KB_TECH_STACK §4`.
Không dùng Redis.

## 3. Interest management (AOI)

Chia map thành lưới ô `aoiCellSize` tile. Mỗi client chỉ nhận entity trong ô của mình + `aoiViewCells` ô lân cận. Enter/leave view gửi `spawn`/`despawn`; thay đổi gửi delta. Bắt buộc từ Phase 3.

## 4. Session & reconnect

- Flow đăng nhập (không dùng JWT; token là opaque, thu hồi được):
  1. `POST /login` → verify Argon2id → trả **access token** ngẫu nhiên (≥ 256 bit). DB chỉ lưu **hash**, có TTL ngắn, thu hồi được.
  2. `POST /ws-ticket` kèm access token → server sinh **WS ticket** ngẫu nhiên, lưu **ETS** với TTL 30s.
  3. Client mở socket với ticket → server verify rồi **xóa ngay** (dùng một lần). Ticket không nằm trong DB.
  4. Client `join` channel `"game"` với `{clientVersion, characterId}`; channel giữ tham chiếu tới Session process của account.
- Một account một session (`singleLoginPerAccount`); login mới kick session cũ.
- Mất kết nối: giữ nhân vật `reconnectGraceSeconds`, vẫn có thể bị tấn công; reconnect trong hạn thì khôi phục.
- Logout khi đang combat: nhân vật ở lại `logoutInCombatSeconds`.
- `clientVersion` nằm trong payload `join` của channel `"game"`; server từ chối version không tương thích.
- WS ticket truyền qua query string: **không log query string** ở proxy/Caddy/Phoenix access log. ETS là theo từng node; khi chạy nhiều node phải chuyển ticket sang store dùng chung hoặc sticky routing.

## 5. WebSocket protocol (nguồn duy nhất)

> Đây là **định nghĩa protocol duy nhất**. `KB_TECH_STACK §5` chỉ tham chiếu về đây.
> Transport: Phoenix Channels, topic `"game"`. Bắt đầu bằng JSON.

Client → server chỉ gửi **ý định**, qua một event duy nhất `cmd`:

```json
{ "act": "attack", "rid": "abc123", "target": "monster_102" }
```

| `act` | Payload (ngoài `act`, `rid`) |
|---|---|
| `move_to` | `{x, y}` |
| `attack` | `{target}` |
| `skill` | `{id, target}` hoặc `{id, x, y}` |
| `pickup` | `{id}` |
| `equip` | `{itemId, slot}` — slot trang bị theo `KB_CONFIG §6` |
| `unequip` | `{slot, toSlot}` — `toSlot` là slot inventory đích |
| `move_item` | `{itemId, to: {location, slot}}` — hoán đổi trong túi; thả lên stack cùng template thì server merge |
| `split` | `{itemId, quantity, toSlot}` — chỉ item `stackable` |
| `drop` | `{itemId}` (cả stack) |
| `use_item` | `{itemId}` |
| `npc_open` | `{npcId}` — server kiểm tra khoảng cách, trả event `shop` |
| `buy` | `{npcId, templateId, quantity}` |
| `sell` | `{npcId, itemId, quantity}` |
| `alloc` | `{stat, points}` |
| `chat` | `{channel, text}` — `channel ∈ NORMAL, PARTY, GUILD, WHISPER` (`SYSTEM` chỉ server gửi); WHISPER thêm `to` |

> UI Phase 1 (danh sách, không kéo thả) không dùng `move_item`, `split`, `drop`; giữ lại cho Phase 2.

Server → client:

| Event | Payload |
|---|---|
| `snapshot` | `{t, entities: [{id, x, y, hp, state}], removed: [...]}` — 10 Hz, delta, theo AOI |
| `combat` | `{rid, attacker, target, dmg, crit, hp}` |
| `player` | state đầy đủ + `view` tính sẵn |
| `spawn` / `despawn` | entity vào/ra vùng nhìn |
| `chat` | `{channel, from, text, t}` |
| `shop` | `{npcId, items: [{templateId, price}]}` |
| `error` | `{rid, error}` |

Server quyết định: position validity, attack validity, cooldown, hit, damage, critical, death, loot, EXP.
Mọi `cmd` có `rid`; server idempotent theo `rid` với action tạo/đổi item.
Rate-limit theo loại message; vượt ngưỡng → drop, lặp lại → kick.

**Error codes** (`error`):

| Code | Ý nghĩa |
|---|---|
| `INVALID_TARGET` | Target không tồn tại / không hợp lệ |
| `OUT_OF_RANGE` | Ngoài tầm đánh / nhặt |
| `COOLDOWN` | Chưa hết cooldown |
| `NO_MANA` | Không đủ mana |
| `INVENTORY_FULL` | Hết slot |
| `REQUIREMENT_NOT_MET` | Thiếu class/level/stat để equip hoặc dùng |
| `NOT_OWNER` | Item không thuộc người chơi / bị loot-protect |
| `INVALID_SLOT` | Slot sai hoặc không hợp lệ cho item |
| `NOT_ENOUGH_ZEN` | Không đủ Zen |
| `RATE_LIMITED` | Gửi quá nhanh |
| `FORBIDDEN` | Hành động bị cấm (safe zone, feature tắt…) |

## 6. Movement & anti-cheat

Client gửi điểm đến. Server kiểm tra: walkable, tốc độ, va chạm, biên map, khoảng teleport, tần suất.
Anti-cheat: max displacement/tick, max speed, invalid path, packet rate. Vi phạm: rubber-band về vị trí hợp lệ, log, tăng điểm nghi ngờ.

## 7. Pathfinding

- Lưới collision từ `collision.bin`; A* 8 hướng có heuristic octile.
- Player: client dự đoán đường, server tự tính/validate đường.
- Monster: A* giới hạn độ sâu (vd 32 node) + cache; ngoài ra đi thẳng khi đường thông.
- Spawn/portal/safezone đọc từ map data.

## 8. Map data

Pipeline duy nhất (khớp `KB_ASSETS §8`):

```
Tiled (.tmj) → convert script → maps/<id>.json + collision.bin
```

Không đưa việc convert asset legacy của MU vào KB; nếu cần port map gốc cho prototype cá nhân thì đó là workflow riêng, ngoài dự án.

```json
{ "width": 256, "height": 256, "collision": "collision.bin",
  "safeZones": [], "pvpZones": [], "spawns": [], "portals": [] }
```

## 9. Database (PostgreSQL)

```sql
CREATE TABLE accounts (
  id UUID PRIMARY KEY,
  username VARCHAR(32) NOT NULL,        -- unique không phân biệt hoa thường: xem index bên dưới
  email TEXT UNIQUE,
  password_hash TEXT NOT NULL,          -- Argon2id (hoặc bcrypt)
  status SMALLINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX accounts_username_ci ON accounts (lower(username));

CREATE TABLE characters (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(id),
  name VARCHAR(10) NOT NULL CHECK (name ~ '^[A-Za-z0-9]{4,10}$'),   -- ASCII-only: không cần NFC
  class VARCHAR(8) NOT NULL CHECK (class IN ('DK','DW','ELF','MG')),
  level INT NOT NULL DEFAULT 1,
  experience BIGINT NOT NULL DEFAULT 0,
  strength INT NOT NULL, agility INT NOT NULL, vitality INT NOT NULL, energy INT NOT NULL,
  free_stat_points INT NOT NULL DEFAULT 0,
  hp_current INT NOT NULL, mana_current INT NOT NULL,
  zen BIGINT NOT NULL DEFAULT 0 CHECK (zen >= 0),
  map_id VARCHAR(32) NOT NULL, position_x INT NOT NULL, position_y INT NOT NULL,
  pk_points INT NOT NULL DEFAULT 0,
  last_pk_at TIMESTAMPTZ,
  version INT NOT NULL DEFAULT 0,       -- optimistic locking
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX characters_name_ci ON characters (lower(name));

-- Phase 1: không có bảng character_skills. Skill tự học theo class + level (KB_GAME_DESIGN §7),
-- suy ra lúc chạy. Thêm bảng này khi có rule skill level hoặc học skill qua item/NPC.

CREATE TABLE items (
  id UUID PRIMARY KEY,
  serial CHAR(26) NOT NULL UNIQUE,      -- ULID do SERVER sinh; định danh của STACK, không phải từng đơn vị
  template_id VARCHAR(50) NOT NULL,
  quantity INT NOT NULL DEFAULT 1 CHECK (quantity >= 1),   -- 1 với item không stack
  item_level SMALLINT NOT NULL DEFAULT 0,
  durability INT,
  luck BOOLEAN NOT NULL DEFAULT FALSE,
  skill BOOLEAN NOT NULL DEFAULT FALSE,
  excellent_options JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Vị trí tách riêng; item_id là PK => mỗi item chỉ có ĐÚNG MỘT chỗ (chặn dupe 2 tab).
CREATE TABLE item_locations (
  item_id UUID PRIMARY KEY REFERENCES items(id),
  location VARCHAR(12) NOT NULL CHECK (location IN ('INVENTORY','EQUIPMENT','WAREHOUSE')),
  character_id UUID REFERENCES characters(id) ON DELETE CASCADE,
  account_id   UUID REFERENCES accounts(id)   ON DELETE CASCADE,
  slot INT NOT NULL,
  CHECK (
    (location IN ('INVENTORY','EQUIPMENT') AND character_id IS NOT NULL AND account_id IS NULL)
    OR
    (location = 'WAREHOUSE' AND account_id IS NOT NULL AND character_id IS NULL)
  ),
  CHECK (
    (location = 'EQUIPMENT' AND slot BETWEEN 0 AND 9)  OR
    (location = 'INVENTORY' AND slot BETWEEN 0 AND 63) OR
    (location = 'WAREHOUSE' AND slot BETWEEN 0 AND 119)   -- 120: placeholder IMPLEMENTATION, xem KB_CONFIG §6
  )
);
-- Partial index (UNIQUE thường không bắt trùng khi cột owner là NULL)
CREATE UNIQUE INDEX item_loc_char_slot ON item_locations (character_id, location, slot) WHERE character_id IS NOT NULL;
CREATE UNIQUE INDEX item_loc_acc_slot  ON item_locations (account_id, location, slot)   WHERE account_id IS NOT NULL;

-- item_id cố ý KHÔNG có FK: log phải sống lâu hơn item bị xóa.
CREATE TABLE item_audit_log (
  id BIGSERIAL PRIMARY KEY,
  item_id UUID NOT NULL, action VARCHAR(20) NOT NULL,
  from_owner TEXT, to_owner TEXT, detail JSONB,
  at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX item_audit_item_at ON item_audit_log (item_id, at);
```

Dữ liệu tĩnh (`item_templates`, monsters, skills) nằm trong `data/*.json` hoặc bảng riêng, load lúc khởi động.
Template item có `stackable: boolean` và `maxStack` (chỉ có nghĩa khi `stackable = true`; trang bị `stackable = false`). `stackable` đặt theo từng template, không suy từ group của Item.txt. Template còn có `iconRef`, `reference`, `sourceType` (schema đầy đủ: `KB_ITEM_REFERENCE §3.1`).
Template potion thêm `potionType` (`HP` | `MP`) và `effect {hp, mp}` (lượng hồi).

**Phase 1 chỉ có 3 location** (`INVENTORY`, `EQUIPMENT`, `WAREHOUSE`). `MAIL`, `TRADE`, `GROUND` là `LATER_VERSION`.
- **Ground item**: chỉ sống trong memory của MapServer; serial sinh lúc drop, row `items` + `item_locations` chỉ được insert khi nhặt. Server crash → item dưới đất mất (chấp nhận).
- **Trade** (Phase 5): trạng thái nằm trong process `TradeSettlement`; chốt bằng một DB transaction (xem §10).
- **Stack**: split → item mới với serial mới; merge → xóa row stack thừa. Cả hai ghi `item_audit_log`.
- **Orphan item** (có trong `items` nhưng không có trong `item_locations`): job dọn định kỳ (mỗi giờ) — log rồi xóa. Không dùng deferred FK ở Phase 1.
Không lưu inventory dạng blob nhị phân. Mọi thay đổi item/Zen trong **một transaction**; dùng `version` để tránh ghi đè.
Thêm migration cho mọi thay đổi schema (`database/migrations/`).

## 10. Security

**Không tin client**: damage, EXP, Zen, item, price, item level, position, speed, cooldown, skill, class, stats, drop.

- Password: Argon2id/bcrypt, không plaintext. Rate-limit login, khoá tạm khi brute-force.
- Inventory validation: slot, serial, ownership, stack, equip restriction, class/level/stat requirement.
- Serial unique do server sinh (ULID); audit log mọi chuyển owner → phát hiện dupe.
- Chat rate-limit; sanitize nội dung hiển thị (chống XSS).
- Anti-bot: phát hiện hành vi lặp bất thường, CAPTCHA khi nghi ngờ.
- Thao tác item trong **một account**: gửi qua Session process (1 process / account, xử lý tuần tự) — xem `KB_TECH_STACK §2`.
- **Trade giữa 2 account** (Session không đủ, vì là cross-account; Phase 5):
  - Mỗi trade là một process `TradeSettlement` (GenServer dưới `DynamicSupervisor: Trade`). State trade (slot, xác nhận 2 bên) **chỉ** nằm ở đây, không nằm trong Session; không ghi DB cho tới khi chốt.
  - Chỉ khi **cả hai** đã confirm, `TradeSettlement` chạy **một** DB transaction.
  - Lock `SELECT … FOR UPDATE` trên các `item_locations`/`items` liên quan, **sắp theo `item_id`** (tránh deadlock); không lock row account; kiểm tra `version` của character khi đổi Zen.
  - Session của một bên disconnect hoặc chết trước khi chốt → huỷ trade **ngay** (không chờ `reconnectGraceSeconds`), không có DB write nào, bên còn lại nhận thông báo.
  - Restart node → mất mọi trade đang mở (chấp nhận được; chưa có gì được ghi DB).

## 11. Cấu trúc project

> Sơ đồ generic. Cấu trúc thực tế của dự án Phoenix nằm ở `KB_TECH_STACK §7`; khi khác nhau thì file đó thắng.

```
game/
├── client/   (rendering, input, ui, inventory, combat, network)
├── server/   (auth, gateway, world, combat, entities, monsters, skills, items, quests, party, guild, pvp)
├── shared/   (protocol, types, constants)
├── data/     (classes, monsters, maps, items, skills, quests, configs)
└── database/ (migrations, seeds)
```

## 12. Mô hình tổng thể

```
ACCOUNT ── CHARACTER ── CLASS / STATS / LEVEL / SKILLS / EQUIPMENT / INVENTORY
        └─ WAREHOUSE
WORLD ── MAP ── NPC / MONSTER / PLAYER / PORTAL / SPAWN
      └─ PARTY / GUILD
COMBAT: TARGET → HIT → DAMAGE → CRITICAL → DEBUFF → DEATH → EXP → LOOT
```
