# KB_CONFIG — Giá trị chỉnh được (CONFIG)

> Mọi giá trị dưới đây là **default tạm**. `verified:false` = chưa đối chiếu MU gốc.
> Code đọc các giá trị này từ `data/configs/*.json`, không hard-code.

## 1. Master config

```json
{
  "game": { "name": "MU Web", "mode": "classic-inspired", "targetVersion": "0.97d", "maxLevel": 400 },

  "features": {
    "magicGladiator": false,
    "wings": false,
    "harmonyJewel": false,
    "guardianJewel": false,
    "chaosMachine": false,
    "pvp": false,
    "guild": false,
    "party": false,
    "quest": false,
    "mail": false,
    "mapPanel": false
  },

  "server": {
    "simulationHz": 20,
    "monsterAiHz": 10,
    "snapshotHz": 10,
    "interpolationDelayMs": 100,
    "maxPlayersPerWorld": 500,
    "aoiCellSize": 16,
    "aoiViewCells": 1
  },

  "combat": {
    "hardFloor": 1,
    "minDamageRatio": 0.1,
    "minHitChance": 0.05,
    "maxHitChance": 0.95,
    "baseCooldownMs": 1000,
    "minCooldownMs": 250,
    "hitFormula": "attackRate / (attackRate + defenseRate)",
    "potionCooldownMs": 1000
  },

  "experience": {
    "mode": "formula",
    "formula": "100 * level ^ 1.5",
    "formulaSemantics": "EXP cần để đi từ level N sang level N+1. level = N.",
    "multiplier": 1.0,
    "levelDiffPenaltyStart": 10,
    "minExpRatio": 0.1,
    "partyBonusPerMember": 0.1,
    "deathExpLossPercent": 0
  },

  "party": { "maxSize": 5, "expRange": 20 },

  "drop": {
    "zenMultiplier": 1,
    "dropMultiplier": 1,
    "itemDropMultiplier": 1,
    "lootProtectSeconds": 10,
    "groundItemSeconds": 60
  },

  "economy": { "sellRatio": 0.5 },

  "items": {
    "speedScale": 1.0,
    "requirementScale": 0.35,
    "iconBuckets": [0, 3, 5, 7, 9, 11, 13, 15],
    "ancientVariants": false
  },

  "account": { "maxCharacters": 1 },

  "mg": { "unlockLevel": 220, "statPerLevel": 7, "startingStatEach": 26 },

  "session": {
    "reconnectGraceSeconds": 30,
    "logoutInCombatSeconds": 10,
    "singleLoginPerAccount": true
  },

  "security": {
    "serverAuthoritative": true,
    "itemSerialRequired": true,
    "clientDamageTrusted": false
  }
}
```

> `experience.formula` ở trên là **placeholder IMPLEMENTATION**, không phải EXP của MU. Thay bằng table khi có dữ liệu (Q4).
> Số Spider cần giết (EXP 10/con, chưa tính penalty) để tới level 2 / 5 / 10: với exponent 1.5 là 10 / 170 / 1110; với exponent 2.2 (bản cũ) là 10 / 379 / 4189 và level 30 cần ~165.000 EXP chỉ riêng bước 29→30. Đã đổi sang 1.5 và `maxLevel` Phase 1 = 10. Chỉnh tiếp bằng simulator (`KB_TECH_STACK §8`).
> `items.speedScale`/`requirementScale`: hệ số quy đổi từ `Item.txt` (Q12, `KB_ITEM_REFERENCE §3.2`), **dùng lúc import để sinh template**, không đọc lúc runtime. Với 0.35: Bronze 80 → 28 (= STR khởi điểm DK). `account.maxCharacters`: Phase 1 = 1; đặt 4 khi bật MG (Q13).

## 2. Class base stats + HP/Mana growth

```json
{
  "DK": {
    "strength": 28, "agility": 20, "vitality": 25, "energy": 10,
    "hpBase": 110, "hpPerLevel": 3, "hpPerVit": 3,
    "mpBase": 20,  "mpPerLevel": 1, "mpPerEne": 1,
    "statPerLevel": 5,
    "sourceType": "CONFIG", "verified": false
  },
  "DW": {
    "strength": 18, "agility": 18, "vitality": 15, "energy": 30,
    "hpBase": 80,  "hpPerLevel": 1, "hpPerVit": 2,
    "mpBase": 60,  "mpPerLevel": 2, "mpPerEne": 2,
    "statPerLevel": 5,
    "sourceType": "CONFIG", "verified": false
  },
  "ELF": {
    "strength": 22, "agility": 25, "vitality": 20, "energy": 15,
    "hpBase": 90,  "hpPerLevel": 1, "hpPerVit": 2,
    "mpBase": 40,  "mpPerLevel": 1, "mpPerEne": 1.5,
    "statPerLevel": 5,
    "sourceType": "CONFIG", "verified": false
  },
  "MG": {
    "strength": 26, "agility": 26, "vitality": 26, "energy": 26,
    "hpBase": 110, "hpPerLevel": 3, "hpPerVit": 3,
    "mpBase": 60,  "mpPerLevel": 2, "mpPerEne": 2,
    "statPerLevel": 7,
    "sourceType": "IMPLEMENTATION", "verified": false
  }
}
```

> HP/Mana growth là `IMPLEMENTATION`. Q2 vẫn mở để đối chiếu 0.97d sau.

## 3. Maps

```json
[
  { "id": "lorencia", "levelRequired": 1,   "safeZones": ["town"], "sourceType": "REFERENCE", "version": "0.97d", "verified": false },
  { "id": "noria",    "levelRequired": 10,  "sourceType": "REFERENCE", "verified": false },
  { "id": "devias",   "levelRequired": 20,  "sourceType": "REFERENCE", "verified": false },
  { "id": "dungeon",  "levelRequired": 25,  "sourceType": "REFERENCE", "verified": false },
  { "id": "atlans",   "levelRequired": 40,  "sourceType": "REFERENCE", "verified": false },
  { "id": "lost_tower", "levelRequired": 50, "floors": 7, "sourceType": "REFERENCE", "verified": false, "note": "7 vs 8 tầng: xem Q1" },
  { "id": "tarkan",   "levelRequired": 140, "sourceType": "REFERENCE", "version": "0.97d", "verified": false }
]
```

## 4. Phase 1 content tối thiểu

```json
{
  "monsters": [
    { "id": "spider", "mapId": "lorencia", "level": 2, "hp": 30, "damageMin": 8, "damageMax": 14,
      "defense": 1, "attackRate": 10, "defenseRate": 3, "experience": 10,
      "zenMin": 5, "zenMax": 15, "moveSpeed": 3, "attackRange": 1,
      "aggroRange": 5, "leashRange": 12, "respawnSeconds": 8,
      "sourceType": "CONFIG", "verified": false }
  ],
  "shop": [
    { "item": "hp_potion_small", "buyPrice": 100, "sellPrice": 50, "sourceType": "CONFIG" }
  ]
}
```

Số của Spider chỉ là ví dụ để chạy vertical slice, cần cân bằng lại.
Lý do đổi `damage` 3–6 → 8–14: DK level 1 có `defense = agility/4 = 5` (`KB_GAME_DESIGN §4.1`), nên đòn 3–6 chỉ gây 1 sát thương (hardFloor) và HP 185 gần như không giảm, khiến potion không có tác dụng. Với 8–14, mỗi đòn trúng gây 3–9.
`mp_potion_small` ở Phase 1 chỉ có qua drop, chưa bán ở shop.

Drop table Spider (Phase 1), `CONFIG`, `verified:false`. Mọi `item` là `templateId` trong `data/items/phase1.json`:

```json
{
  "monsterId": "spider",
  "zen": { "min": 5, "max": 15 },
  "groups": [
    { "id": "potions", "chance": 0.15, "entries": [
      { "item": "hp_potion_small", "weight": 80 }, { "item": "mp_potion_small", "weight": 20 } ] },
    { "id": "equipment", "chance": 0.06, "entries": [
      { "item": "sword_t0", "weight": 1 }, { "item": "shield_t0", "weight": 1 },
      { "item": "helm_t0", "weight": 1 },  { "item": "armor_t0", "weight": 1 },
      { "item": "pants_t0", "weight": 1 }, { "item": "gloves_t0", "weight": 1 },
      { "item": "boots_t0", "weight": 1 }, { "item": "ring_hp_t0", "weight": 1 } ] }
  ]
}
```

Kỳ vọng: 6% × 1 lần giết ≈ 1 món trang bị mỗi ~17 Spider. Đủ 8 món trang bị cần ~130 con nếu rơi đều (chưa tính trùng). Chỉnh bằng simulator.

## 5. Upgrade rates (Phase 5)

```json
[
  { "fromLevel": 0, "toLevel": 1, "successRate": 1.00, "onFailure": "UNCHANGED", "requires": ["jewel_bless"] },
  { "fromLevel": 1, "toLevel": 2, "successRate": 1.00, "onFailure": "UNCHANGED", "requires": ["jewel_bless"] },
  { "fromLevel": 2, "toLevel": 3, "successRate": 1.00, "onFailure": "UNCHANGED", "requires": ["jewel_bless"] },
  { "fromLevel": 3, "toLevel": 4, "successRate": 1.00, "onFailure": "UNCHANGED", "requires": ["jewel_bless"] },
  { "fromLevel": 4, "toLevel": 5, "successRate": 1.00, "onFailure": "UNCHANGED", "requires": ["jewel_bless"] },
  { "fromLevel": 5, "toLevel": 6, "successRate": 1.00, "onFailure": "UNCHANGED", "requires": ["jewel_bless"] },
  { "fromLevel": 6, "toLevel": 7, "successRate": 0.70, "onFailure": "DECREASE", "requires": ["jewel_soul"] },
  { "fromLevel": 7, "toLevel": 8, "successRate": 0.60, "onFailure": "DECREASE", "requires": ["jewel_soul"] },
  { "fromLevel": 8, "toLevel": 9, "successRate": 0.50, "onFailure": "DECREASE", "requires": ["jewel_soul"] }
]
```

> Chỉ áp dụng cho +0 → +9. Upgrade trên +9 là `LATER_VERSION` (feature flag `harmonyJewel` / `guardianJewel`).
> Toàn bộ rate là `IMPLEMENTATION`. Q6 mới (xem `KB_00_RULES §6`).

## 6. Equipment slot mapping

```json
{
  "EQUIPMENT": {
    "0": "HELM",
    "1": "ARMOR",
    "2": "PANTS",
    "3": "GLOVES",
    "4": "BOOTS",
    "5": "WEAPON",
    "6": "SHIELD",
    "7": "WING",
    "8": "RING1",
    "9": "RING2"
  },
  "INVENTORY": {
    "0-63": "64 slot; UI Phase 1 hiển thị dạng danh sách (KB_GAME_DESIGN §19.4), không phải lưới 8x8"
  },
  "WAREHOUSE": {
    "0-119": "account-wide slots (15x8)",
    "sourceType": "IMPLEMENTATION", "verified": false
  }
}
```

> MG không được equip slot `0` (HELM). Validate ở server.
> Slot `7` (WING) bị khóa khi `features.wings = false`.
