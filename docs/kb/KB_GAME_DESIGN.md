# KB_GAME_DESIGN — Rule của game (IMPLEMENTATION)

> Tất cả ở đây là `IMPLEMENTATION` trừ khi ghi khác. Số liệu cụ thể nằm ở `KB_CONFIG.md`.

## 1. Stats

```
earnedPoints = (level - 1) × statPerLevel
totalStat    = startingStat + allocatedPoints
freePoints   = earnedPoints - allocatedPoints
```

Ví dụ lv 400: DK 399×5 = 1995; MG 399×7 = 2793 điểm earned.
Validate server-side: `allocatedPoints ≤ earnedPoints`; không cho giảm stat (trừ Reset item nếu có).

## 2. Magic Gladiator (IMPLEMENTATION, bật Phase 3)

- Unlock: account có ≥1 nhân vật đạt level `mg.unlockLevel` (CONFIG, mặc định 220).
- 7 stat/level, không dùng helmet, starting stat 26 mỗi loại.
- Build gợi ý: Physical (STR/AGI), Magic (ENE/AGI), Hybrid.
- Cờ `features.magicGladiator` điều khiển.

## 3. Level & EXP

- `expRequired(level)` đọc từ EXP table hoặc formula trong config. Không hard-code.
- EXP monster = `monster.experience × expMultiplier × levelDiffModifier`.
- `levelDiffModifier` (CONFIG): player cao hơn monster quá N level → giảm EXP tuyến tính tới tối thiểu `minExpRatio`.
- Party EXP: chia theo số thành viên trong `partyRange`, cộng `partyBonus` mỗi thành viên (CONFIG).

## 4. Damage pipeline (một thứ tự duy nhất)

```
1. rawAttack      = random(damageMin, damageMax) của vũ khí + stat bonus
2. × skillMultiplier, + skillBonus
3. + flat damageBonus (item option, buff)
4. × critical / excellent multiplier (nếu roll thành công)
5. × buff/debuff multiplier
6. − targetDefense (reduction)
7. floor + minimum damage
```

```javascript
function calculateDamage(ctx) {
  let d = ctx.rawAttack;
  d = d * ctx.skillMultiplier + ctx.skillBonus + ctx.damageBonus;
  if (ctx.isCritical)  d *= ctx.criticalMultiplier;
  if (ctx.isExcellent) d *= ctx.excellentMultiplier;
  d *= ctx.buffMultiplier;
  const afterDef = d - ctx.targetDefense;
  const softFloor = d * ctx.config.minDamageRatio;
  return Math.max(ctx.config.hardFloor, Math.floor(Math.max(afterDef, softFloor)));
}
```

`minDamageRatio` (mặc định 0.1) và `hardFloor` (mặc định 1) đều ở `KB_CONFIG`. Hai lớp này thay cho 3 lớp floor trước đây. `minDamageRatio` tránh tình trạng defense cao biến mọi đòn thành 1. Đây là quyết định thiết kế, không phải công thức MU.

## 4.1. Per-class stat mapping (IMPLEMENTATION)

> Đây là rule của dự án, **không phải** công thức MU gốc. `verified: false` — có thể tinh chỉnh.
> Mọi biến `weapon.*`, `armor.*`, `equipment.*` là tổng từ item đang mặc.

```json
{
  "DK": {
    "attackPower":  "strength / 4 + weapon.attackMax",
    "attackMin":    "strength / 6 + weapon.attackMin",
    "defense":      "agility / 4 + sum(armor.defense)",
    "attackRate":   "level * 5 + agility * 1.5",
    "defenseRate":  "agility / 3",
    "attackSpeed":  "agility / 15 + sum(equipment.speed)",
    "hpMax":        "hpBase + (level - 1) * hpPerLevel + vitality * hpPerVit",
    "mpMax":        "mpBase + (level - 1) * mpPerLevel + energy * mpPerEne",
    "sourceType":   "IMPLEMENTATION",
    "verified":     false
  },
  "DW": {
    "attackPower":  "energy / 4 + weapon.attackMax",
    "attackMin":    "energy / 9 + weapon.attackMin",
    "defense":      "agility / 5 + sum(armor.defense)",
    "attackRate":   "level * 5 + agility * 1.5",
    "defenseRate":  "agility / 4",
    "attackSpeed":  "agility / 10 + sum(equipment.speed)",
    "hpMax":        "hpBase + (level - 1) * hpPerLevel + vitality * hpPerVit",
    "mpMax":        "mpBase + (level - 1) * mpPerLevel + energy * mpPerEne",
    "sourceType":   "IMPLEMENTATION",
    "verified":     false
  },
  "ELF": {
    "attackPower":  "agility / 4 + strength / 8 + weapon.attackMax",
    "attackMin":    "agility / 7 + strength / 14 + weapon.attackMin",
    "defense":      "agility / 10 + sum(armor.defense)",
    "attackRate":   "level * 5 + agility * 1.5",
    "defenseRate":  "agility / 3",
    "attackSpeed":  "agility / 50 + sum(equipment.speed)",
    "hpMax":        "hpBase + (level - 1) * hpPerLevel + vitality * hpPerVit",
    "mpMax":        "mpBase + (level - 1) * mpPerLevel + energy * mpPerEne",
    "sourceType":   "IMPLEMENTATION",
    "verified":     false
  },
  "MG": {
    "attackPower":  "strength / 4 + weapon.attackMax",
    "attackPowerMagic": "energy / 4 + weapon.attackMax",
    "attackMin":    "strength / 6 + weapon.attackMin",
    "defense":      "agility / 5 + sum(armor.defense)",
    "attackRate":   "level * 5 + agility * 1.5",
    "defenseRate":  "agility / 4",
    "attackSpeed":  "agility / 15 + sum(equipment.speed)",
    "attackSpeedMagic": "agility / 20 + sum(equipment.speed)",
    "hpMax":        "hpBase + (level - 1) * hpPerLevel + vitality * hpPerVit",
    "mpMax":        "mpBase + (level - 1) * mpPerLevel + energy * mpPerEne",
    "sourceType":   "IMPLEMENTATION",
    "verified":     false
  }
}
```

**Quy tắc áp dụng:**

- `hpBase`, `hpPerLevel`, `hpPerVit`, `mpBase`, `mpPerLevel`, `mpPerEne` đọc từ `KB_CONFIG §2`.
- `weapon.attackMin/attackMax` là chỉ số của vũ khí đang trang bị (không phải của class).
- `armor.defense` là tổng defense của tất cả armor đang mặc.
- `equipment.speed` là tổng attack speed bonus từ item.
- `rawAttack` (§4 bước 1) = `random(attackMin, attackPower)`.
- Chỉ số derived ở §4.1 làm tròn xuống (`floor`) khi tính. Pipeline damage ở §4 chỉ `floor` **một lần** ở bước 7 (không làm tròn giữa các bước nhân) trừ khi config ghi khác.
- Attack speed cuối cùng clamp theo `KB_GAME_DESIGN §6` (`attackSpeed` ở §6 chính là giá trị tính ở đây).
- Nếu class là MG và skill là magic → dùng `attackPowerMagic` + `attackSpeedMagic`.

## 5. Hit chance (IMPLEMENTATION)

```
hitChance = clamp(attackRate / (attackRate + defenseRate), minHit, maxHit)
```

`minHit`/`maxHit` ở config (mặc định 0.05 / 0.95). Công thức thay thế có thể đặt trong `config.hitFormula`.

## 6. Attack speed & cooldown

Tách 4 khái niệm: `attackSpeed`, `attackCooldown`, `animationSpeed`, `movementSpeed`.

```
cooldownMs = max(minCooldownMs, baseCooldownMs / (1 + attackSpeed / 100))
```

Với `baseCooldownMs=1000`, `minCooldownMs=250`:

| attackSpeed | cooldown |
|---|---|
| 0 | 1000 ms |
| 50 | 667 ms |
| 100 | 500 ms |
| 200 | 333 ms |
| 300+ | 250 ms (cap) |

Animation phải co giãn theo cooldown ở client, nhưng server quyết định.

## 7. Skills (data-driven)

Categories: `DAMAGE, AOE, BUFF, DEBUFF, HEAL, SUMMON, MOVEMENT`.

```json
{
  "id": "twisting_slash", "class": "DK",
  "manaCost": 10, "cooldownMs": 800,
  "range": 2, "radius": 2,
  "damageMultiplier": 1.2, "targetType": "AOE",
  "requiredLevel": 10,
  "sourceType": "CONFIG", "version": null, "verified": false
}
```

Mọi `requiredLevel`, `manaCost` là CONFIG.

**Học skill (Phase 1):** `basic_attack` là implicit, mọi class đều có. Skill khác tự học khi đạt `requiredLevel`; tập skill suy ra từ `class` + `level`, không lưu DB. Học qua scroll/NPC và skill level là chưa có rule.
Elf: Damage Elf (ranged skill) **và** Support Elf (heal/buff) đều cần skill set riêng.

## 8. Items

```typescript
interface Item {
  id: string; templateId: string; type: ItemType;
  level: number; durability: number;
  quantity: number;            // 1 với item không stack; serial thuộc về stack
  excellentOptions: ExcellentOption[];
  luck: boolean; skill: boolean;
  serial: string; ownerId?: string;
}
```

- Excellent là **option**; combat engine đọc `modifiers`, không có hệ số cứng.
- Equip validation: class, level, STR/AGI/ENE/VIT requirement (`requirements` của template, đã scale), slot, durability, ownership.
- Template item (`data/items/*.json`) có `templateId`, `iconRef`, `reference`, `requirements` (đã nhân `items.requirementScale` lúc import), `sourceType`; cách seed từ `Item.txt` và chọn icon: `KB_ITEM_REFERENCE §3–§4`. Instance chỉ giữ `templateId`, `level`, `excellentOptions`, `quantity`, `serial`; client suy ra icon, server không gửi tên file.
- `Item.level` (cường hóa +N) khác với cột `ItemLvl` của `Item.txt` (level gốc của loại item).

### Upgrade (Phase 5)

```json
{ "fromLevel": 6, "toLevel": 7, "successRate": 0.5,
  "onFailure": "DECREASE", "requires": ["jewel_soul"] }
```

`onFailure ∈ {DECREASE, UNCHANGED, DESTROY}`. Rate là CONFIG.

## 9. Monster AI

```
IDLE → SEARCH → CHASE → ATTACK → DEAD → RESPAWN
CHASE → RETURN  (vượt leashRange / mất target)
```

- AI tick 10 Hz, chạy theo **zone có người** (monster ở vùng không có player thì sleep).
- Aggro: chọn target theo khoảng cách + damage gần nhất (CONFIG).
- Chase dùng pathfinding giới hạn độ sâu (xem KB_TECHNICAL §7).
- RETURN: monster hồi HP đầy, bỏ aggro, không drop.

## 10. Drop system

```json
{
  "monsterId": "spider",
  "zen": { "min": 5, "max": 15 },
  "groups": [
    { "id": "potions", "chance": 0.15, "entries": [{ "item": "hp_potion_small", "weight": 80 }, { "item": "mp_potion_small", "weight": 20 }] },
    { "id": "equipment", "chance": 0.02, "entries": [{ "item": "sword_t0", "weight": 1, "levelRoll": [0, 1] }] }
  ]
}
```

> Ví dụ minh họa (rút gọn). Drop table Phase 1 đầy đủ của Spider ở `KB_CONFIG §4`; `item` là `templateId` trong `data/items/phase1.json`.

Quy trình: mỗi group roll `chance × dropMultiplier` → chọn entry theo weight → roll option (luck/skill/excellent) theo bảng config → tạo item (có serial) trên mặt đất.
Loot: chỉ owner/party được nhặt trong `lootProtectSeconds` (mặc định 10s); item biến mất sau `groundItemSeconds` (60s).

## 11. Death & respawn

- Chết: respawn ở safe zone của map (hoặc town gần nhất).
- Mất `expLossPercent` của EXP level hiện tại (CONFIG, mặc định 0 ở Phase 1–2). Không mất level.
- Không rơi item khi chết bởi monster. PK rơi item: xem §13.
- Giảm durability trang bị khi chết/đánh (CONFIG).

## 12. Party (Phase 3)

Create, Invite, Accept, Leave, Kick, Disband. Tối đa `maxPartySize` (CONFIG, mặc định 5). Chia EXP trong `partyRange`. Đồng bộ HP và vị trí member. Chat party.

## 13. PvP & PK (Phase 4)

Tách thành state machine riêng, **không dùng một boolean `isPvP`**:

| Mode | Mô tả |
|---|---|
| Duel | Hai bên đồng ý, vùng riêng, không PK |
| Self-defense | Người bị tấn công trước được đánh trả không bị tính PK |
| PK | Giết người chơi trung lập → tăng `pkPoints` |
| Guild war | Hai guild khai chiến, kill không tính PK |

```
PKState: NORMAL → WARNING → MURDERER
```

Server xử lý: tăng/giảm PK theo thời gian, penalty chết, item drop, hạn chế vào town/NPC. Safe zone cấm tấn công.

## 14. Guild (Phase 4)

Tạo guild (level + Zen), master/assistant/member, mời/kick, guild chat, guild war.

## 15. Quest (Phase 6)

```typescript
interface Quest {
  id: string; name: string; minLevel: number;
  objectives: Objective[]; rewards: Reward[];
  sourceType: "REFERENCE" | "IMPLEMENTATION" | "CONFIG";
}
```

## 16. Chat

Channels: `NORMAL, PARTY, GUILD, WHISPER, SYSTEM`. Rate-limit, độ dài tối đa, filter từ cấm, mute/report.

## 17. Economy

- Shop price, Zen drop: CONFIG. Sell price mặc định = `buyPrice × sellRatio`.
- Trading (Phase 5): hai bên xác nhận, khoá slot, giao dịch atomic trong DB transaction, log đầy đủ.
- Sink Zen: repair, upgrade, shop. Source Zen: drop, bán item. Theo dõi tổng cung Zen.

## 18. Naming

Tên nhân vật 4–10 ký tự, chỉ chữ cái/số, unique (không phân biệt hoa thường), qua filter từ cấm.

## 19. UI túi đồ, trang bị & panel (Phase 1)

> `IMPLEMENTATION`, `verified: false`. Chỉ mô tả hành vi UI; luật item/slot/validation ở `KB_TECHNICAL §5, §9` và `KB_CONFIG §6`.
> UI chỉ gửi ý định (`cmd`); server quyết định. Client **không** tự tính công thức và **không** optimistic update: UI chỉ đổi khi server trả kết quả; số hiển thị lấy từ `view` trong event `player`. Hover/tooltip là thuần client, không gửi `cmd`.
> Phase 1 hỗ trợ desktop và mobile. **Không có nút X** — panel mở full-screen, đóng bằng cách bấm lại tab hoặc `Esc` (desktop) / nút back (mobile).
>
> **Chú ý về hình vẽ:** Các hình ASCII trong §19 chỉ để minh họa cho người đọc.
> Phần **mô tả chi tiết bằng text** là nguồn chính; AI Agent đọc text, không đọc hình.
> Nếu hình bị lệch khi format, dùng mô tả text.
> **Số liệu trong hình (Dmg, Defense, Atk Speed, Atk Rate, HP…) chỉ là minh họa, không khớp §4.1** (vd DK cấp 5 có Atk Rate ≈ 55, Atk Speed chỉ vài đơn vị, không phải 145 / 87). Hiển thị thật lấy từ `view` do server tính.
>
> **Phạm vi Phase 1 của §19:** dock 4 tab (Nhân vật, Túi đồ, Thông báo, Menu), panel Character / Inventory / Thông báo / Shop, submenu Menu, context menu quái, nút mobile.
> **Hộp thư (§19.10) và Map (§19.12) là thiết kế cho Phase 2**, không làm ở Phase 1. Một số hình ASCII bên dưới còn vẽ tab 🗺️ và icon 📬 để tham khảo; **text ưu tiên hơn hình**.

### 19.1. Layout

**Desktop (≥1280px):**

```
┌─────────────────────────────────────────────────────────────┐
│ Lorencia (142,121)      📬³    HP ███████████████ 200/200   │  Top HUD (48px)
│                                MP ███████████      30/30    │
├─────────────────────────────────────────────────────────────┤
│ EXP ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  120/500   │  EXP bar (24px)
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                                                             │
│                          [GAME VIEW]                        │
│                                                             │
│                          👤 Player                          │
│                                                             │
│                          🕷️ Spider                          │
│                                                             │
│                                                             │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────┬─────────┬─────────┬───────────┬─────────┐       │  Dock (64px)
│ │   👤    │   🎒    │   🗺️    │    🔔     │   ☰     │       │
│ │Nhân vật │ Túi đồ  │ Bản đồ  │ Thông báo │  Menu   │       │
│ └─────────┴─────────┴─────────┴───────────┴─────────┘       │
└─────────────────────────────────────────────────────────────┘
```

**Mô tả chi tiết — Desktop:**

Cấu trúc từ trên xuống — 4 tầng:

1. **Top HUD (48px)** — nền bán trong suốt, full width
   - Bên trái: text `Lorencia (142,121)` — tên map + tọa độ
   - Ở giữa: icon 📬 (hộp thư) với badge số đỏ ở góc phải trên icon — **Phase 2**, Phase 1 không hiển thị
   - Bên phải: 2 thanh HP và MP xếp dọc
     - HP bar: nền đỏ, chữ trắng `200/200`
     - MP bar: nền xanh dương, chữ trắng `30/30`
   - Cạnh thanh HP hiện `Q ×12`, cạnh thanh MP hiện `W ×12` (tổng số HP/MP potion trong túi). Chỉ desktop; mobile có nút riêng (§19.16)

2. **EXP bar (24px)** — ngay dưới Top HUD, full width
   - Nền xám, phần đã đạt màu vàng
   - Bên phải thanh: text `120 / 500`

3. **Game view (chiếm phần còn lại)** — nền tối
   - Ở giữa: player sprite `👤 Player`, bên dưới là `🕷️ Spider`
   - Phase 1: chỉ có 1 player + spider

4. **Dock (64px)** — sát đáy, full width
   - 4 tab chia đều chiều ngang ở Phase 1 (Phase 2 thêm tab 🗺️ Bản đồ)
   - Mỗi tab: icon (24×24) + label (11px) bên dưới
   - Tab Phase 1: `👤 Nhân vật` | `🎒 Túi đồ` | `🔔 Thông báo` | `☰ Menu` (Phase 2 thêm `🗺️ Bản đồ` giữa Túi đồ và Thông báo)
   - Nền tối, tab active sáng hơn

**Mobile (≥360px):**

```
┌─────────────────────────────────────┐
│ Lorencia (142,121)      📬³         │  Top HUD
│ HP ████████  200/200                │
│ MP ██████    30/30                  │
├─────────────────────────────────────┤
│ EXP ████████░░░░░░  120/500         │  EXP bar
├─────────────────────────────────────┤
│                                     │
│              [GAME VIEW]            │
│                                     │
│              👤 Player              │
│                                     │
│              🕷️ Spider              │
│                                     │
│                        ┌───┐        │
│                        │🧪 │        │  Nút mobile
│                        │ 12│        │
│                        └───┘        │
│                        ┌───┐        │
│                        │💧 │        │
│                        │ 12│        │
│                        └───┘        │
│                        ┌───┐        │
│                        │✋ │        │
│                        └───┘        │
├─────────────────────────────────────┤
│ ┌────────┬────────┬────────┬────────┬────────┐ │
│ │   👤   │   🎒   │   🗺️   │   🔔   │   ☰    │ │  Dock (5 tab)
│ │Nhân vật│ Túi đồ │Bản đồ  │Thông báo│ Menu │ │
│ └────────┴────────┴────────┴────────┴────────┘ │
└─────────────────────────────────────┘
```

**Mô tả chi tiết — Mobile:**

Khác Desktop:
- **Top HUD:** HP/MP bar xếp dọc thay vì ngang (do hẹp)
- **3 nút mobile** ở góc phải dưới, trên dock:
  - `🧪` HP potion (kèm số lượng bên dưới)
  - `💧` MP potion (kèm số lượng bên dưới)
  - `✋` Nhặt item
  - Mỗi nút 56×56px, xếp dọc, cách nhau 8px, cách mép phải 16px
  - **Chỉ hiện khi không có panel mở**
- **Dock 4 tab (Phase 1):** giống desktop nhưng nhỏ hơn

**Quy tắc layout:**

- **Top HUD (48px):** `{mapName} ({x},{y})` bên trái, HP/MP bar bên phải (icon 📬 Hộp thư chỉ có từ Phase 2).
- **EXP bar (24px):** ngay dưới Top HUD, full width. Text `{current} / {required}` bên phải thanh.
- **Game view:** phần còn lại ở giữa.
- **Dock (64px):** sát đáy, 4 tab chia đều chiều ngang (Phase 1).
- **Không panel nào mở khi login.**
- **Panel chiếm toàn bộ vùng game view khi mở** (full-screen panel). Không có nút X.
- **Chỉ 1 panel mở tại một thời điểm.** Mở panel khác → panel cũ tự đóng.
- **Đóng panel:** bấm lại tab đang active; bấm tab khác (chuyển panel); `Esc` (desktop); nút back (mobile).
- **Dock vẫn hiện ở dưới cùng** khi panel mở; tab đang active được highlight.
- **Nút mobile (🧪 HP, 💧 MP, ✋ Nhặt):** chỉ hiện khi KHÔNG có panel mở. Khi panel mở → ẩn để tránh chồng.
- **Icon 📬 Hộp thư trên Top HUD (Phase 2):** vẫn hiện khi panel mở; bấm vào sẽ chuyển sang panel Hộp thư, giống bấm một tab trên dock.

### 19.2. Phím tắt

**Desktop:**

| Phím | Chức năng |
|---|---|
| `C` | Mở/đóng panel Character |
| `I` | Mở/đóng panel Inventory |
| `M` | Mở/đóng panel Map (Phase 2) |
| `Q` | Dùng HP potion |
| `W` | Dùng MP potion |
| `Space` | Nhặt item gần nhất |
| `Esc` | Đóng panel đang mở |

**Không có hotkey `1`–`6` cho skill.** Skill dùng qua context menu khi click/tap quái (xem §19.9).

**Mobile:** không có phím tắt. Dùng dock + nút hành động nổi + tap quái.

### 19.3. Panel Character (tab "Nhân vật")

**Desktop:**

```
┌─────────────────────────────────────────────────────────────┐
│ Top HUD + EXP bar                                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                    ┌─────────────────────────┐              │
│                    │      NHÂN VẬT           │              │
│                    │                         │              │
│                    │  Fenrir                 │              │
│                    │  DK · Cấp 5             │              │
│                    │  ─────────────────────  │              │
│                    │  EXP: 120 / 500         │              │
│                    │  ─────────────────────  │              │
│                    │  STR    28        [+]   │              │
│                    │  AGI    20        [+]   │              │
│                    │  VIT    25        [+]   │              │
│                    │  ENE    10        [+]   │              │
│                    │  Điểm còn: 5            │              │
│                    │  ─────────────────────  │              │
│                    │  Dmg:       12 ~ 18     │              │
│                    │  Defense:   8           │              │
│                    │  Atk Speed: 87          │              │
│                    │  Atk Rate:  145         │              │
│                    │  HP:  200 / 200         │              │
│                    │  MP:   30 / 30          │              │
│                    └─────────────────────────┘              │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ │  👤▓▓   │   🎒    │   🗺️    │    🔔     │   ☰     │      │
│ │Nhân vật │ Túi đồ  │ Bản đồ  │ Thông báo │  Menu   │      │
└─────────────────────────────────────────────────────────────┘
```

**Mobile:**

```
┌─────────────────────────────────────┐
│ Top HUD + EXP bar                   │
├─────────────────────────────────────┤
│              NHÂN VẬT                │
│                                     │
│  Fenrir                             │
│  DK · Cấp 5                         │
│  ─────────────────────────────      │
│  EXP: 120 / 500                     │
│  ─────────────────────────────      │
│  STR    28                     [+]  │
│  AGI    20                     [+]  │
│  VIT    25                     [+]  │
│  ENE    10                     [+]  │
│  Điểm còn: 5                        │
│  ─────────────────────────────      │
│  Dmg:       12 ~ 18                 │
│  Defense:   8                       │
│  Atk Speed: 87                      │
│  Atk Rate:  145                     │
│  HP:  200 / 200                     │
│  MP:   30 / 30                      │
├─────────────────────────────────────┤
│ │  👤▓▓   │  🎒  │  🗺️  │  🔔  │ ☰  │
└─────────────────────────────────────┘
```

**Mô tả chi tiết:**

Panel full-screen chiếm giữa màn hình. Cấu trúc:
- **Tiêu đề:** `NHÂN VẬT` — căn giữa, font lớn
- **Tên nhân vật:** `Fenrir`
- **Class + level:** `DK · Cấp 5`
- **Dòng phân cách**
- **EXP:** `120 / 500`
- **Dòng phân cách**
- **4 stat chính:** STR, AGI, VIT, ENE. Mỗi dòng có nút `[+]` bên phải để cộng điểm
- **Điểm còn:** `5` (free stat points)
- **Dòng phân cách**
- **Derived stats:** Dmg, Defense, Atk Speed, Atk Rate, HP, MP — số server tính

Dock ở dưới: tab `👤 Nhân vật` được highlight.

Nút `+`: client debounce 200ms, gộp nhiều lần bấm vào cùng một stat thành **một** `alloc {stat, points}`.

### 19.4. Panel Inventory (tab "Túi đồ")

Panel full-screen gồm 2 phần và một thanh dưới cố định:

1. **Trang bị đang mặc** (EQUIPMENT) — lưới slot 3×4 cố định
2. **Trang bị trong túi** (LIST) — danh sách item có nút `[Trang bị]`, có scroll
3. **Thanh dưới** (cố định) — Zen, số slot, số potion, gợi ý bán đồ

**Bố cục:** Desktop chia **2 cột** (EQUIPMENT bên trái, LIST bên phải) vì vùng trống ở 720p chỉ ~584px, xếp dọc thì LIST chỉ thấy ~2 item. Mobile xếp **dọc**. Thanh dưới trải hết chiều ngang panel ở cả hai.

**Desktop:**

```
┌─────────────────────────────────────────────────────────────┐
│ Top HUD + EXP bar                                            │
├─────────────────────────────────────────────────────────────┤
│       ┌──────────────────────────────────────────────┐       │
│       │                  TÚI ĐỒ                      │       │
│       ├────────────────────┬─────────────────────────┤       │
│       │ Trang bị đang mặc  │ Trang bị trong túi   ▲  │       │
│       │      ┌───────┐     │ ─────────────────────── │       │
│       │      │  🪖   │     │ ⚔️ Gậy Gỗ    [Trang bị] │       │
│       │      └───────┘     │    Tấn công +3          │       │
│       │ ┌─────┐┌─────┐┌───┐│ ─────────────────────── │       │
│       │ │ ⚔️  ││ 👕  ││🛡️ ││ 🛡️ Khiên Vảy Rồng [Trang bị]│    │
│       │ │WEAP ││ARMOR││SHD││    Phòng thủ +20  █     │       │
│       │ └─────┘└─────┘└───┘│ ─────────────────────── │       │
│       │ ┌─────┐┌─────┐┌───┐│ 🗡️ Đại Kiếm    [Trang bị]│       │
│       │ │ 🧤  ││ 👖  ││👢 ││    Tấn công +44         │       │
│       │ │GLOV ││PANTS││BTS││ ─────────────────────── │       │
│       │ └─────┘└─────┘└───┘│ 🎽 Áo Da Mỏng  [Trang bị]│       │
│       │ ┌─────┐┌─────┐┌───┐│    Phòng thủ +2         │       │
│       │ │ 💍  ││🪽🔒 ││💍 ││ ─────────────────────── │       │
│       │ │RING1││WING ││RN2││                      ▼  │       │
│       │ └─────┘└─────┘└───┘│                         │       │
│       ├────────────────────┴─────────────────────────┤       │
│       │ 💰 Zen: 92                    Túi: 7/64      │       │
│       │ Q 🧪 HP Potion ×12     W 💧 MP Potion ×12    │       │
│       │ Muốn bán đồ, hãy gặp NPC bán hàng.           │       │
│       └──────────────────────────────────────────────┘       │
├─────────────────────────────────────────────────────────────┤
│ │   👤    │  🎒▓▓   │   🗺️    │    🔔     │   ☰     │      │
└─────────────────────────────────────────────────────────────┘
```

**Mobile:**

```
┌─────────────────────────────────────┐
│ Top HUD + EXP bar                   │
├─────────────────────────────────────┤
│              TÚI ĐỒ                 │
│                                     │
│  Trang bị đang mặc                  │
│         ┌───────┐                   │
│         │  🪖   │                   │
│         └───────┘                   │
│  ┌───────┐┌───────┐┌───────┐        │
│  │  ⚔️   ││  👕   ││  🛡️   │        │
│  │WEAPON ││ARMOR  ││SHIELD │        │
│  └───────┘└───────┘└───────┘        │
│  ┌───────┐┌───────┐┌───────┐        │
│  │  🧤   ││  👖   ││  👢   │        │
│  │GLOVES ││PANTS  ││BOOTS  │        │
│  └───────┘└───────┘└───────┘        │
│  ┌───────┐┌───────┐┌───────┐        │
│  │  💍   ││  🪽🔒 ││  💍   │        │
│  │RING1  ││WING   ││RING2  │        │
│  └───────┘└───────┘└───────┘        │
│                                     │
│  Trang bị trong túi          ▲      │
│  ────────────────────────────│─     │
│                              │      │
│  ⚔️  Gậy Gỗ          [Trang bị]     │
│      Tấn công +3             │      │
│  ────────────────────────────│─     │
│                              █      │
│  🛡️  Khiên Vảy Rồng  [Trang bị]     │
│      Phòng thủ +20           │      │
│  ────────────────────────────│─     │
│                              │      │
│  🗡️  Đại Kiếm        [Trang bị]     │
│      Tấn công +44            │      │
│  ────────────────────────────│─     │
│                              │      │
│  🎽  Áo Da Mỏng      [Trang bị]     │
│      Phòng thủ +2            ▼      │
│  ────────────────────────────        │
├─────────────────────────────────────┤
│  💰 Zen: 92           Túi: 7/64     │
│  Q 🧪 ×12            W 💧 ×12       │
│  Muốn bán đồ, hãy gặp NPC bán hàng. │
├─────────────────────────────────────┤
│ │  👤  │  🎒▓▓  │  🗺️  │  🔔  │ ☰  │
└─────────────────────────────────────┘
```

**Mô tả chi tiết:**

**Phần 1 — Trang bị đang mặc (EQUIPMENT):**
- Lưới 3 cột × 4 hàng, slot 64×64px, dùng đúng 10 ô
- Layout đối xứng:
  ```
          c0          c1          c2
   r0      ·        HELM(0)        ·
   r1   WEAPON(5)   ARMOR(1)    SHIELD(6)
   r2   GLOVES(3)   PANTS(2)    BOOTS(4)
   r3   RING1(8)    WING(7)     RING2(9)
  ```
- Slot đang mặc hiện icon item. Slot trống hiện silhouette mờ
- `WING` hiện khóa (🔒) khi `features.wings = false`
- Click slot đang mặc → tooltip item, kèm nút `[Tháo]` (xem Tương tác)

**Phần 2 — Trang bị trong túi (LIST)** (desktop: cột phải; mobile: dưới EQUIPMENT):
- Tiêu đề: `Trang bị trong túi` — cố định, không scroll
- Danh sách item dọc, mỗi item gồm 2 dòng:
  - Dòng 1: `[Icon] [Tên item]` — bên phải có nút `[Trang bị]`
  - Dòng 2: `[Mô tả ngắn]` (ví dụ: `Tấn công +3`, `Phòng thủ +20`)
- Phân cách giữa các item: dòng kẻ ngang
- Chỉ liệt kê item loại trang bị. Potion và item tiêu hao **không** nằm trong danh sách này ở Phase 1; số lượng potion xem ở thanh dưới và dùng qua `Q` / `W` hoặc nút mobile (§19.6)
- Thứ tự theo `slot` tăng dần trong `item_locations`; sức chứa túi vẫn là 64 slot (`INVENTORY_FULL` tính theo 64 slot)

**Phần 3 — Thanh dưới (cố định, không scroll):**
- Dòng 1: `💰 Zen: {số}` bên trái, `Túi: {đã dùng}/64` bên phải (đếm số slot `INVENTORY` đã dùng)
- Dòng 2: `Q 🧪 HP Potion ×{n}` và `W 💧 MP Potion ×{n}` — tổng số potion cùng `potionType` trong mọi stack (client cộng từ `view`). Không có potion → `×0`
- Dòng 3: gợi ý `Muốn bán đồ, hãy gặp NPC bán hàng.`

**Scroll:**

- Chỉ vùng **"Trang bị trong túi"** scroll.
- Header `Trang bị trong túi` **cố định**.
- EQUIPMENT (phần trên) **cố định**.
- Thanh dưới (Zen, số slot, potion, gợi ý) **cố định**.
- Scrollbar hiện ở cạnh phải vùng scroll khi nội dung dài hơn vùng hiển thị. Ẩn khi không cần.
- Scroll indicator `▲` / `▼` hiện theo vị trí scroll:
  - `▲` hiện khi còn item phía trên
  - `▼` hiện khi còn item phía dưới
- Desktop: cuộn chuột giữa, kéo scrollbar, hoặc phím ↑/↓ (khi focus panel).
- Mobile: vuốt lên/xuống.
- List rỗng → hiện text `Không có trang bị trong túi`.

**Tương tác:**

| Hành động | Kết quả |
|---|---|
| Click nút `[Trang bị]` bên phải item | Gửi `equip {itemId, slot}`; `slot` theo loại item. Nhẫn: `RING1` nếu trống, ngược lại `RING2` |
| Click vào item (không phải nút) | Hiện tooltip |
| Click vào slot đang mặc | Hiện tooltip, có nút `[Tháo]` → `unequip {slot, toSlot}` (`toSlot` = slot túi trống đầu tiên; hết chỗ → `INVENTORY_FULL`) |

**Không có (Phase 1):**
- Grid 8×8 với 64 ô
- Kéo thả / drag-drop; `move_item`, `split`, `drop` không dùng ở UI Phase 1 (action vẫn giữ trong `KB_TECHNICAL §5` cho Phase 2)
- Số stack trên ô grid (hiển thị trong tên nếu cần: `HP Potion x12`)

**Icon:** giả định 32×32 cho tới khi có số đo của bộ icon thật (`KB_ASSETS` A6), hiển thị ×1 (không scale lẻ): khung 48px trong danh sách, khung 64px ở slot equipment. Tooltip dùng ×2 (64×64). Icon không vuông (nếu có) căn giữa trong khung, không kéo giãn.

**Chọn icon:** client tra `icon_map.json` bằng `iconRef` của template + `level` cường hóa của instance + `excellentOptions.length > 0` (quy tắc và chuỗi fallback ở `KB_ITEM_REFERENCE §4`). Không dò file lúc runtime. Thiếu file → placeholder, ghi cảnh báo, không crash.

### 19.5. Tương tác

Phase 1 **không có kéo thả**. Tương tác của panel Inventory nằm ở §19.4 (bảng "Tương tác"). Các cử chỉ khác:

| Thao tác | Kết quả |
|---|---|
| Click/tap item | Hiện tooltip (tên, chỉ số, yêu cầu; yêu cầu không đủ hiện chữ đỏ). Không gửi `cmd` |
| Chuột phải / double-click | Không dùng |

### 19.6. Potion (không có skill bar)

- **Không có skill bar hiển thị trên màn hình.** Skill dùng qua context menu khi click/tap quái (xem §19.9).
- **Desktop:** bấm `Q` dùng HP potion, `W` dùng MP potion. Số potion còn lại hiện cạnh thanh HP/MP ở Top HUD.
- **Mobile:** tap nút 🧪 (HP) hoặc 💧 (MP) ở góc phải dưới (chỉ hiện khi không có panel mở).
- Cách dùng: client chọn stack đầu tiên (slot thấp nhất) có `template.potionType` tương ứng, gửi `use_item` với `itemId` của stack đó.
- Hết potion: không gửi gì. Mobile: nút hiện xám.
- Nút mobile hiển thị **tổng** số potion cùng `potionType` trong mọi stack của túi.
- Cooldown: `combat.potionCooldownMs` (`KB_CONFIG §1`).
- Potion không hiện trong danh sách §19.4 (chỉ liệt kê trang bị). Số lượng hiện ở: Top HUD (desktop, `Q ×n` / `W ×n`), thanh dưới panel Inventory, và nút mobile.

### 19.7. Panel Shop

- Click/tap NPC → `npc_open` → panel Shop mở **full-screen** với 2 cột: trái Shop, phải Inventory.

**Desktop:**

```
┌─────────────────────────────────────────────────────────────┐
│ Top HUD + EXP bar                                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   SHOP                              INVENTORY               │
│   Potion Merchant                                           │
│   ─────────────────────              EQUIPMENT              │
│                                       ┌───────┐             │
│   🧪 HP Potion (S)                    │  🪖   │             │
│      100 Zen                          └───────┘             │
│                                       ┌───────┐             │
│   🧪 MP Potion (S)                    │  ⚔️   │             │
│      100 Zen                          │WEAPON │             │
│                                       └───────┘             │
│   ─────────────────────              ...                   │
│   Bấm [Bán] cạnh item bên phải để bán                       │
│                                                             │
│                                      💰 Zen: 92             │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ Dock (không có tab nào active)                              │
└─────────────────────────────────────────────────────────────┘
```

**Mô tả chi tiết:**

Panel full-screen, chia 2 cột bằng nhau:

**Cột trái — SHOP:**
- Tiêu đề: `SHOP`
- Tên NPC: `Potion Merchant`
- Dòng phân cách
- Danh sách item bán, mỗi item: icon + tên + giá
- Dòng phân cách
- Text hướng dẫn: `Bấm [Bán] cạnh item bên phải để bán`

**Cột phải — INVENTORY:**
- Chỉ danh sách trang bị trong túi (nút `[Trang bị]` đổi thành `[Bán]`) và Zen; không hiện equipment, để vừa màn hình

Dock ở dưới: không có tab nào active (vì Shop mở từ click NPC, không phải tab).

**Đóng Shop:** Rời tầm NPC, `Esc`, hoặc bấm tab bất kỳ trên dock.

- Mua = click item trong Shop → gửi `buy`.
- Bán = bấm `[Bán]` cạnh item trong danh sách bên phải → `sell` (cả stack).

### 19.8. Lỗi

Server trả `error` → hiện thông báo ngắn trong panel Thông báo (xem §19.11). UI chưa đổi gì trước khi server trả, nên không cần revert.

### 19.9. Context menu khi click/tap quái

- **Desktop:** click trái vào quái → hiện context menu.
- **Mobile:** tap vào quái → hiện context menu.
- Menu nổi lên tại vị trí click/tap, không che quái.

```
                          ┌──────────────────────┐
                          │ Tấn công thường      │
                          │ Twisting Slash       │
                          │ ──────────────────── │
                          │ Hủy                  │
                          └──────────────────────┘
```

**Mô tả chi tiết:**

- Menu nổi lên tại vị trí click/tap trên quái
- Không che quái
- 3 item:
  - `Tấn công thường` — basic attack
  - `Twisting Slash` — skill (chỉ hiện nếu đã học)
  - `Hủy` — đóng menu
- Dòng phân cách giữa skill và Hủy
- Click ngoài menu → đóng

| Item | Chức năng |
|---|---|
| Tấn công thường | Basic attack |
| Twisting Slash | Dùng skill (nếu class DK và level ≥ requiredLevel) |
| Hủy | Đóng menu, không làm gì |

- Click/tap ngoài menu → đóng, không làm gì.
- Skill chưa học → không hiện trong menu.

**Hành vi tấn công (IMPLEMENTATION):**
- Chọn `Tấn công thường` → **tự đánh liên tục**: client gửi `attack {target}` theo nhịp attack cooldown cho tới khi quái chết, người chơi click-to-move, hoặc mất mục tiêu.
- Quái ngoài tầm đánh → client gửi `move_to` tiến lại gần (đi thẳng, chưa cần pathfinding) rồi đánh tiếp.
- Chọn skill → dùng **một lần**, sau đó quay lại tự đánh thường. Thiếu mana (`NO_MANA`) → ghi thông báo và đánh thường.
- Server vẫn kiểm tra tầm, cooldown và rate-limit từng `attack` (xem `KB_TECHNICAL §5`); client không được bỏ qua.

### 19.10. Panel Hộp thư hệ thống (Phase 2 — không làm ở Phase 1)

> Thiết kế dự kiến. Trước khi làm cần bổ sung vào `KB_TECHNICAL`: bảng `mail`, action `mail_list` / `mail_claim` / `mail_delete`, và cách cấp Zen/item (qua `item_audit_log`).


- Icon 📬 ở góc trên HUD (giữa map name và HP bar), kích thước 32×32px.
- Badge số đỏ ở góc phải trên icon khi có mail chưa đọc. Badge tắt khi mở panel.
- Click icon → panel Hộp thư mở **full-screen**.

```
┌─────────────────────────────────────────────────────────────┐
│ Top HUD + EXP bar                                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                       HỘP THƯ                                │
│                                                             │
│              [Tất cả] [Chưa đọc] [Có quà]                   │
│              ─────────────────────────────                  │
│              🎁 Admin tặng quà Tết                          │
│                 Tặng 1000 Zen nhân dịp Tết                  │
│                 2 giờ trước                                 │
│                 [Nhận]                                      │
│              ─────────────────────────────                  │
│              🔧 Bảo trì server                              │
│                 Bảo trì lúc 3h sáng mai                     │
│                 1 ngày trước                                │
│              ─────────────────────────────                  │
│              🎉 Chào mừng bạn đến MU Web                    │
│                 Chúc bạn chơi game vui vẻ!                  │
│                 3 ngày trước                                │
│              ─────────────────────────────                  │
│              [Xóa đã đọc]                                   │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ Dock (không có tab nào active)                              │
└─────────────────────────────────────────────────────────────┘
```

**Mô tả chi tiết:**

- **Tiêu đề:** `HỘP THƯ`
- **Filter:** `[Tất cả]` `[Chưa đọc]` `[Có quà]`
- **Danh sách mail:**
  - Icon (🎁 quà, 🔧 system, 🎉 welcome)
  - Tiêu đề mail
  - Nội dung mail
  - Thời gian
  - Nút `[Nhận]` nếu có reward (mail đã nhận có dấu ✓)
- **Nút `[Xóa đã đọc]`**

Dock ở dưới: không có tab nào active (vì Hộp thư mở từ icon 📬 trên HUD).

**Đóng:** Bấm lại icon 📬, `Esc`, hoặc bấm tab bất kỳ trên dock.

- Mail hệ thống lưu DB lâu dài, có `expires_at`.
- Phase 1 mail có thể chứa: Zen, item.

### 19.11. Panel Thông báo gameplay

- Tab 🔔 trên dock (tab thứ 4), badge số đỏ khi có thông báo chưa đọc. Badge tắt khi mở panel.
- Click tab → panel Thông báo mở **full-screen**.

```
┌─────────────────────────────────────────────────────────────┐
│ Top HUD + EXP bar                                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                      THÔNG BÁO                              │
│                                                             │
│              [Tất cả] [Chưa đọc]                            │
│              ─────────────────────────────                  │
│              ⚡ Level up!                                   │
│                 Level 5 → 6                                 │
│                 2 phút trước                                │
│              ─────────────────────────────                  │
│              🎁 Nhặt: HP Potion (S)                         │
│                 5 phút trước                                │
│              ─────────────────────────────                  │
│              ⚠️ Không đủ mana                               │
│                 10 phút trước                               │
│              ─────────────────────────────                  │
│              [Xóa tất cả]                                   │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ │   👤    │   🎒    │   🗺️    │   🔔▓▓    │   ☰     │      │
└─────────────────────────────────────────────────────────────┘
```

**Mô tả chi tiết:**

- **Tiêu đề:** `THÔNG BÁO`
- **Filter:** `[Tất cả]` `[Chưa đọc]`
- **Danh sách thông báo**, mỗi cái gồm:
  - Icon (⚡ level up, 🎁 item, ⚠️ error)
  - Text chính
  - Text phụ (nếu có)
  - Thời gian
- **Dòng phân cách giữa các thông báo**
- **Nút `[Xóa tất cả]`** ở cuối

Dock ở dưới: tab `🔔 Thông báo` được highlight.

- Filter: `Tất cả` / `Chưa đọc`.
- Không có nút action trên từng thông báo.
- Lưu tối đa 50 thông báo gần nhất; cũ nhất tự xóa.
- Loại: `LEVEL_UP`, `ITEM_DROP`, `ITEM_PICKUP`, `EXP_GAIN`, `ERROR`, `SYSTEM`.
- Đóng: bấm lại tab 🔔, `Esc`, hoặc bấm tab khác.
- Phase 1: lưu trong session memory.

### 19.12. Panel Map (tab "Bản đồ") (Phase 2 — không làm ở Phase 1)

- Click tab → panel Map mở **full-screen**.

```
┌─────────────────────────────────────────────────────────────┐
│ Top HUD + EXP bar                                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                        BẢN ĐỒ                                │
│                                                             │
│                     LORENCIA                                │
│           ┌─────────────────────────────┐                   │
│           │  ·   ·   🏠   ·   ·   ·    │                   │
│           │  ·   ·   ·    ·   ·   ·    │                   │
│           │  ·   🟢  ·    ·   ·   ·    │                   │
│           │  ·   ·   ·    🟡  ·   ·    │                   │
│           │  ·   ·   ·    ·   ·   ·    │                   │
│           │  ·   ·   ·    ·   ▲   ·    │                   │
│           └─────────────────────────────┘                   │
│           🟢 Bạn   🟡 NPC   ▲ Portal                        │
│           ─────────────────────────────                     │
│           Vị trí: (142, 121)                                │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ │   👤    │   🎒    │  🗺️▓▓   │    🔔     │   ☰     │      │
└─────────────────────────────────────────────────────────────┘
```

**Mô tả chi tiết:**

- **Tiêu đề:** `BẢN ĐỒ`
- **Tên map:** `LORENCIA`
- **Minimap:** khung vuông 256×256px
  - Nền tối
  - `·` = ô trống
  - `🏠` = nhà/NPC
  - `🟢` = vị trí player (chấm xanh)
  - `🟡` = NPC (chấm vàng)
  - `▲` = portal (mũi tên)
- **Legend:** `🟢 Bạn    🟡 NPC    ▲ Portal`
- **Tọa độ:** `Vị trí: (142, 121)`

Dock ở dưới: tab `🗺️ Bản đồ` được highlight.

- Đóng: bấm lại tab 🗺️, `Esc`, hoặc bấm tab khác.

### 19.13. Menu submenu

- Tab ☰ trên dock mở **submenu nổi** trên dock (không phải full-screen).

```
                                          ┌─────────────────────┐
                                          │ ⚙️ Cài đặt          │
                                          │ 🚪 Đăng xuất        │
                                          └─────────────────────┘
```

**Mô tả chi tiết:**

- Submenu nổi lên trên dock, căn mép phải với tab Menu
- Mỗi item: icon + label
- Phase 1 chỉ có 2 item: `⚙️ Cài đặt` và `🚪 Đăng xuất`
- Các item khác (Kinh nghiệm, Bạn bè, Hộp thư, Nhiệm vụ, Hành trình, Guild) ẩn, hiện khi Phase 4-6
- Click ngoài submenu → đóng
- Bấm tab Menu lần 2 → đóng

**Phase 1 submenu:**

| Item | Chức năng |
|---|---|
| ⚙️ Cài đặt | Mở màn hình cài đặt (âm thanh, đăng xuất) |
| 🚪 Đăng xuất | Thoát về màn hình login |

**Chưa có (Phase 4+):** Kinh nghiệm, Bạn bè, Hộp thư (đã có icon riêng), Nhiệm vụ, Hành trình, Guild.

- Đóng: bấm tab ☰ lần 2, click ngoài submenu, `Esc`.

### 19.14. Floating notification — không dùng

Phase 1 **không có floating notification**. Tất cả thông báo gameplay gom vào panel Thông báo (§19.11), mail hệ thống gom vào panel Hộp thư (§19.10).

### 19.15. Bảng vị trí panel

| Panel | Mở bằng | Full-screen? | Đóng bằng |
|---|---|---|---|
| Character | Tab 👤, `C` | ✅ | Bấm lại tab, `Esc` |
| Inventory | Tab 🎒, `I` | ✅ | Bấm lại tab, `Esc` |
| Map (Phase 2) | Tab 🗺️, `M` | ✅ | Bấm lại tab, `Esc` |
| Thông báo | Tab 🔔 | ✅ | Bấm lại tab, `Esc` |
| Shop | Click NPC | ✅ (2 cột) | Rời tầm NPC, `Esc` |
| Hộp thư (Phase 2) | Icon 📬 | ✅ | Bấm lại icon, `Esc` |
| Menu | Tab ☰ | Submenu nổi | Bấm lại tab, click ngoài |

**Chỉ 1 panel mở tại một thời điểm.** Mở panel khác → panel cũ tự đóng.

### 19.16. Nút mobile

Chỉ hiện khi **không có panel mở**:

| Nút | Chức năng |
|---|---|
| 🧪 HP | Dùng HP potion |
| 💧 MP | Dùng MP potion |
| ✋ Nhặt | Nhặt item gần nhất |

- Kích thước 56×56px
- Góc phải dưới, trên dock
- Cách mép phải 16px

### 19.17. Quy ước ký hiệu trong hình vẽ

| Ký hiệu | Ý nghĩa |
|---|---|
| `┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ ─ │` | Khung viền (box drawing) |
| `═ ║ ╔ ╗ ╚ ╝` | Khung đôi (dùng cho outer frame) |
| `▓▓` | Highlight (tab active, vùng sáng) |
| `···` | Vùng trống |
| `🔒` | Khóa (feature tắt) |
| `↑ ↓ ← →` | Mũi tên chỉ |
| `🟢` | Chấm xanh (player) |
| `🟡` | Chấm vàng (NPC) |
| `▲` | Mũi tên (portal) |

**Nếu hình vẽ bị lệch khi paste:**
- Dấu hiệu: cột `│` không thẳng hàng, khung `┌─┐` bị vỡ, text chạy ra ngoài khung.
- Cách khắc phục: dùng font monospace (Consolas, Monaco, Courier New, Fira Code); không edit text trong hình khi paste; nếu vẫn lệch, dùng phần "Mô tả chi tiết" ở mỗi hình.
- **Trong KB:** AI Agent đọc text, không đọc hình. Phần "Mô tả chi tiết" là **nguồn chính**, hình chỉ để human đọc.

**Chưa làm (Phase 2+):** lưới túi 8×8 và kéo thả, Hộp thư, panel Bản đồ, kéo panel, gán potion/skill thủ công, chọn số lượng khi split, so sánh với item đang mặc, icon item khóa, sort, repair, character preview, double-tap attack nhanh, "Thông tin quái" trong context menu, chat log đầy đủ, mail từ player khác.
