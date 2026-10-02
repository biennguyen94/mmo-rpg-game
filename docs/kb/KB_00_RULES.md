# KB_00_RULES — Quy tắc chung, Scope, Ưu tiên dữ liệu

> Đọc file này **đầu tiên**. Các file khác: `KB_REFERENCE.md`, `KB_GAME_DESIGN.md`, `KB_CONFIG.md`, `KB_TECHNICAL.md`, `KB_TECH_STACK.md`, `KB_ASSETS.md`, `KB_BASE_REPO.md`, `KB_ITEM_REFERENCE.md`.

## 1. Mục tiêu

Web MMORPG lấy cảm hứng từ MU Online cổ điển (Season 1 / early classic):
isometric action RPG, click-to-move, click-to-attack, real-time combat, stats, equipment, skill, monster grinding, EXP/level, drops, jewels, party, PvP, guild, town/NPC/shop, WebSocket multiplayer.

**Không** sao chép legacy client/server của MU. Mục tiêu: *cảm giác chơi cổ điển + kiến trúc web hiện đại + server-authoritative + data-driven*.

## 2. Source types

| Tag | Ý nghĩa |
|---|---|
| `REFERENCE` | Thông tin tham chiếu từ MU cổ điển (có version + nguồn) |
| `IMPLEMENTATION` | Rule do dự án này tự thiết kế |
| `CONFIG` | Giá trị chỉnh được bằng server config |
| `LATER_VERSION` | Có trong MU ở version sau, **mặc định tắt** |

**Mọi bản ghi gameplay** (class, map, skill, item, monster, công thức…) phải có:

```json
{
  "sourceType": "REFERENCE",
  "version": "0.97d",
  "verified": false,
  "source": "URL hoặc null"
}
```

- `verified: false` = chưa đối chiếu nguồn. Agent **không được** coi là sự thật MU và phải nêu rõ khi dùng.
- Một giá trị `REFERENCE` có thể dùng làm *default* của `CONFIG`, nhưng **không bao giờ ghi đè** CONFIG đã chọn.

## 3. Thứ tự ưu tiên (DUY NHẤT)

```
1. Yêu cầu tường minh của developer / project spec
2. Server CONFIG hiện hành
3. IMPLEMENTATION rules (KB_GAME_DESIGN, KB_TECHNICAL)
4. REFERENCE theo đúng version target
5. REFERENCE chung / kiến thức MU khác version
6. Giả định của AI  →  KHÔNG ĐƯỢC dùng; thay bằng ASK/FLAG
```

Hai version MU có số liệu khác nhau → **không merge**; ghi từng bản ghi theo `version`.

## 4. Scope decisions (đã chốt)

| ID | Quyết định | Loại |
|---|---|---|
| S1 | Target: `0.97d`, mode `classic-inspired` | CONFIG |
| S2 | Class mặc định: DK, DW, Elf | REFERENCE |
| S3 | Magic Gladiator: **tính năng mở rộng**, unlock lv 220. Không khẳng định MG thuộc Season 1 gốc | IMPLEMENTATION |
| S4 | Dark Lord, Leadership, Summoner…: ngoài scope | — |
| S5 | `maxLevel = 400` là CONFIG của dự án, không phải fact Season 1 | CONFIG |
| S6 | Wings, Harmony, Guardian, Creation: `LATER_VERSION`, tắt mặc định, bật ở Phase 5 | LATER_VERSION |
| S7 | Damage/hit/EXP formula: chỉ là IMPLEMENTATION, không phải công thức MU gốc | IMPLEMENTATION |
| S8 | Server-authoritative 100% | IMPLEMENTATION |
| S9 | Combat real-time, di chuyển theo lưới ô, tick 20 Hz (D1 = phương án A, `KB_TECH_STACK §3`) | IMPLEMENTATION |
| S11 | Asset MU-derived (icon item, layer trang bị) để **ngoài git** (`assets_src/private/` + output sinh tự động, gitignore); không vào repo công khai/Docker production trừ khi developer quyết định (A2, A5). Chi tiết: `KB_ASSETS §2.2` | IMPLEMENTATION |
| S10 | `Item.txt` là Season 5+ (có `//Season5`, Seed): chỉ làm seed, mọi bản ghi lấy từ đó mang `version: "s5+"` (`KB_ITEM_REFERENCE`) | REFERENCE |

## 5. AI Agent Rules

1. Không tạo mechanic mới nếu KB đã có mechanic tương ứng.
2. Đổi công thức combat → ghi `CHANGE_REASON` trong commit/PR.
3. Không coi REFERENCE là yêu cầu bắt buộc phải bắt chước.
4. Mọi giá trị gameplay phải thuộc đúng một source type.
5. Không hard-code số gameplay trong code; đọc từ `data/` hoặc config.
6. Thiếu dữ liệu → **ASK / FLAG** (ghi vào mục 6), không bịa.
7. Không thêm hệ thống `LATER_VERSION` khi flag chưa bật.
8. Không bao giờ tin client cho damage, EXP, Zen, item, price, position, speed, cooldown, skill, class, stats, drop.

## 6. Open questions (cần developer / nguồn xác nhận)

| # | Câu hỏi | Mặc định tạm |
|---|---|---|
| Q1 | Lost Tower: 7 hay 8 tầng? Các nguồn khác nhau, chưa đối chiếu | 7 (`verified:false`) |
| Q2 | Starting HP/Mana từng class chính xác theo 0.97d? | Giá trị trong KB_CONFIG |
| Q3 | Yêu cầu level từng map theo 0.97d? | Bảng trong KB_REFERENCE |
| Q4 | EXP table: dùng bảng nào? | Công thức placeholder trong KB_CONFIG |
| Q5 | Có bật MG và maxLevel 400 ngay không? | Bật từ Phase 2 |
| Q6 | Upgrade rate +0→+9 chính xác theo 0.97d? | Bảng trong KB_CONFIG §5 |
| Q7 | `Valor` (group 14 của Item.txt) nghĩa là gì? | Không dùng; `effect` ghi tường minh |
| Q8 | Cột class của Item.txt: giá trị 0/1/2/3 là bậc tiến hóa? (dữ liệu ủng hộ) | Dùng được khi giá trị == 1 |
| Q9 | `Item.txt` thuộc version nào? | Season 5+, chỉ làm seed |
| Q10 | `ring_hp_t0` không có trong Item.txt | Template tự tạo (`IMPLEMENTATION`), `iconRef` `custom/…` |
| Q11 | Icon item/trang bị do ai làm, license, kích thước pixel? (`X×Y` đã rõ là ô túi) (`KB_ASSETS` A5, A6) | Prototype riêng tư, asset ngoài git (S11); giả định 32×32 cho tới khi `ICON_REPORT.md` có số đo |
| Q12 | Quy đổi `Speed` và yêu cầu stat từ Item.txt | `items.speedScale = 1.0`, `items.requirementScale = 0.35` |
| Q14 | Đồ Phase 1 làm Spider vô hại: chỉ Leather Armor (defense tổng 15) đã đủ vì Spider tối đa 14; full Leather + Shield = 32 (`KB_ITEM_REFERENCE §5.1`). Chấp nhận hay chỉnh? | Chấp nhận cho slice; test "dùng potion" trước khi mặc áo; kiểm tra bằng simulator |
| Q15 | `DefRate` shield/gloves/boots nghĩa là gì? | Không dùng trong combat |
| Q13 | Số nhân vật mỗi tài khoản? MG unlock (§4 S3) cần ≥ 2 nhân vật | Phase 1: 1 (app enforce, không ràng buộc DB); từ Phase 3: `account.maxCharacters = 4` |

## 7. Lộ trình phase (nguồn duy nhất về scope)

> Đây là **nguồn duy nhất** định nghĩa scope từng phase.
> Các file khác (`KB_ASSETS`, `KB_CONFIG`, `KB_TECH_STACK`) chỉ mô tả asset/config/code cho phase đã chốt ở đây.

| Phase | Scope |
|---|---|
| 1. Vertical slice | Login → tạo DK → Lorencia → move → đánh **Spider** → EXP → level up → cộng stat → drop → equip → save/load |
| 2. Core | DW, Elf, Inventory, Equipment, Skills, Monster AI, Drop table, NPC, Shop, Chat, Death/respawn, Pathfinding, Hộp thư hệ thống, panel Bản đồ |
| 3. Multiplayer | AOI (tối ưu băng thông cho nhiều người), reconnect giữa phiên, Party, Warehouse, MG |
| 4. PvP & Social | Duel, PK, Self-defense, Guild, Guild war |
| 5. Economy | Trading, Jewels, Upgrade, serial/anti-dupe audit |
| 6. Advanced | Quest, Chaos Machine, Wings (`LATER_VERSION`), Events, Bosses, Ranking |

**Phase 1 — chi tiết scope tối thiểu:**

```json
{
  "classes": ["DK"],
  "maps": ["lorencia"],
  "monsters": ["spider"],
  "npcs": ["lorencia_potion_merchant"],
  "items": [
    "hp_potion_small", "mp_potion_small",
    "sword_t0", "shield_t0",
    "helm_t0", "armor_t0", "pants_t0", "gloves_t0", "boots_t0",
    "ring_hp_t0"
  ],
  "skills": ["basic_attack", "twisting_slash"],
  "features": {
    "party": false, "pvp": false, "guild": false,
    "quest": false, "wings": false, "chaosMachine": false,
    "magicGladiator": false, "mail": false, "mapPanel": false
  },
  "maxLevel": 10,
  "acceptance": [
    "login OK",
    "tạo DK OK",
    "vào Lorencia OK",
    "click-to-move OK",
    "click-to-attack Spider OK",
    "Spider chết + respawn OK",
    "nhận EXP + lên level OK",
    "cộng stat OK",
    "nhặt item OK",
    "equip item OK",
    "mỗi item hiển thị một icon: icon thật nếu đã có trong icon_map.json, nếu chưa có thì placeholder (ghi cảnh báo build) OK",
    "mua potion từ NPC OK",
    "dùng potion OK",
    "UI: dock + panel Character / Inventory / Thông báo / Shop dùng được trên desktop (≥1280px) và mobile (≥360px) OK",
    "reload page → character state còn nguyên OK (persistence, chưa phải reconnect giữa phiên)",
    "2 player login cùng lúc thấy nhau di chuyển OK (broadcast đơn giản, chưa cần AOI)"
  ]
}
```

> `maxLevel` Phase 1 = 10 (trước là 30): chỉ có Spider (level 2, EXP 10) và penalty EXP bắt đầu ở level 12 nên level 30 không đạt được bằng grind Spider. Xem số liệu trong `KB_CONFIG §1`.
> `ring_hp_t0` không có trong `Item.txt` nên là `IMPLEMENTATION`; các item còn lại seed từ `Item.txt` (`KB_ITEM_REFERENCE §5`, đã tra: `data/items/phase1.json`).

**Ràng buộc phụ thuộc:** Upgrade (5) cần Jewel (5); Chaos Machine (6) cần Upgrade + Jewel; Trading (5) cần Item serial + ownership validation.
