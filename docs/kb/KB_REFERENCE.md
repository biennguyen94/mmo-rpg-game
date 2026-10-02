# KB_REFERENCE — Tham chiếu MU Online cổ điển

> Mọi mục ở đây là `REFERENCE`. Mục `verified:false` **chưa được đối chiếu nguồn**: dùng làm default, không dùng làm "sự thật".
> Dự án có thể override bằng `KB_CONFIG.md`.

## 1. Classes

```json
[
  {
    "id": "DK", "name": "Dark Knight",
    "role": ["melee_dps", "tank", "pvp_melee"],
    "primaryStat": "strength", "secondaryStats": ["agility", "vitality"],
    "weapons": ["sword", "axe", "mace", "spear"], "offhand": ["shield"],
    "statPerLevel": 5,
    "sourceType": "REFERENCE", "version": "0.97d", "verified": false
  },
  {
    "id": "DW", "name": "Dark Wizard",
    "role": ["magic_dps", "aoe", "ranged"],
    "primaryStat": "energy", "secondaryStats": ["agility", "vitality"],
    "weapons": ["staff"], "offhand": ["shield"],
    "statPerLevel": 5,
    "sourceType": "REFERENCE", "version": "0.97d", "verified": false
  },
  {
    "id": "ELF", "name": "Fairy Elf",
    "role": ["ranged_dps", "support"],
    "archetypes": ["damage_elf", "support_elf"],
    "weapons": ["bow", "crossbow", "one_handed_sword"], "offhand": ["shield"],
    "supportSkills": ["healing", "greater_defense", "greater_damage"],
    "statPerLevel": 5,
    "sourceType": "REFERENCE", "version": "0.97d", "verified": false
  }
]
```

### Magic Gladiator — **KHÔNG phải REFERENCE của target 0.97d**

MG là class mở rộng (`IMPLEMENTATION`, xem KB_GAME_DESIGN §2). Thông tin tham khảo từ MU sau này:
7 stat/level, không dùng helmet, unlock sau khi account có nhân vật ~lv 220. `version: "later"`, `verified:false`.

## 2. Core stats

Strength, Agility, Vitality, Energy. **Không có Leadership** (Dark Lord ngoài scope).

## 3. Maps

| Map | Level vào | Ghi chú | version | verified |
|---|---|---|---|---|
| Lorencia | 1 | Town + vùng Spider/Bull Fighter | 0.97d | false |
| Noria | ~10 | Elf town | 0.97d | false |
| Devias | ~20 | | 0.97d | false |
| Dungeon | ~25 | | 0.97d | false |
| Atlans | ~40 | Map nước | 0.97d | false |
| Lost Tower | ~50 | Số tầng: **mâu thuẫn nguồn (7 vs 8)** — xem Q1 | 0.97d | false |
| Tarkan | 140 (đường bộ) | | 0.97d | false |

> Cột "Level vào" ngoại trừ Tarkan là xấp xỉ, **phải đối chiếu** trước khi dùng. Tarkan = 140 là giá trị đã được đối chiếu một lần, nhưng vẫn cần source link.

Nếu hai nguồn khác nhau, lưu cả hai:

```json
[{"map":"tarkan","levelRequired":140,"version":"0.97d"},
 {"map":"tarkan","levelRequired":80,"version":"private-server-X"}]
```

## 4. Item concepts (không kèm số)

- Categories: weapon, armor, shield, helmet, potion, jewel, scroll, quest, misc.
- Item có: level (+N), durability, option Luck, option Skill, Excellent options.
- Jewels cổ điển: Bless, Soul, Life, Chaos. **Harmony / Guardian / Creation = `LATER_VERSION`.**
- Wings (Elf/Heaven/Satan/Spirit/Soul/Dragon…) = `LATER_VERSION` cho đến Phase 6. Level yêu cầu từng wing: chưa verify.

## 5. Quest

Tên quest (Proof of Strength/Wisdom/Courage/Hero…) **không được coi là Season 1 canonical**. Quest của dự án được định nghĩa trong KB_GAME_DESIGN.

## 6. Công thức đã BỊ LOẠI khỏi core (không có nguồn / không rõ version)

| Công thức | Xử lý |
|---|---|
| `EXP(N) = 100 × 2^(N-1)` | Thay bằng EXP table (CONFIG) |
| `Damage = (Skill - Def) × (200 + MP/10)%` | Bỏ |
| `Excellent Damage = ×1.2` | Excellent là option đọc từ data |
| Upgrade +9→+15 chuẩn Season 1 | Dùng `UpgradeRule` data-driven |

## 7. Nguồn tham chiếu nên đối chiếu

- OpenMU (open-source MU server): game configuration cho EXP, skill, item, monster.
- Dữ liệu client/server gốc của đúng version 0.97d.

Mỗi khi verify xong một mục: đặt `verified:true` và điền `source`.
