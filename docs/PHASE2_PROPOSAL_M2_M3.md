# Đề xuất số liệu P2-M2 (DW, Elf) và P2-M3 (skill theo class)

> Trả lời P2-2 … P2-6 trong `docs/OPEN_QUESTIONS.md`. **Chỉ là đề xuất, chưa vào `priv/game_data/`.**
> Mọi số dưới đây là `sourceType: "IMPLEMENTATION"`, `verified: false` — số của dự án, **không phải
> số MU**. Tên skill/item lấy theo MU cho quen thuộc, nhưng chỉ số item thật sẽ lấy từ `Item.txt`
> khi có (E6). Anh duyệt từng mục (A/B hoặc sửa số); mục nào duyệt xong em ghi vào JSON ở milestone.

## 0. Cách tính

Số ước lượng bằng công thức KB: chỉ số theo `KB_GAME_DESIGN §4.1`, sát thương theo §4, tỉ lệ trúng
§5, cooldown §6, Spider theo `KB_CONFIG §4` (HP 30, sát thương 8–14, def 1, attackRate 10,
defenseRate 3, đi 3 ô/s). Đây là **giá trị kỳ vọng** (script nhỏ), chưa phải simulator; ở M2 em mở
rộng `mix mu.simulate` theo class rồi báo số thật trước khi chốt.

### 0.1. Chỉ số cấp 1 (từ KB, không đề xuất gì mới)

| Class | STR/AGI/VIT/ENE | HP | MP | Sát thương tay không | Def | attackRate | defenseRate | attackSpeed |
|---|---|---|---|---|---|---|---|---|
| DK | 28/20/25/10 | 185 | 30 | 4~7 | 5 | 35 | 6 | 1 |
| DW | 18/18/15/30 | 110 | 120 | 3~7 | 3 | 32 | 4 | 1 |
| ELF | 22/25/20/15 | 130 | 62 | 5~9 | 2 | 42 | 8 | 0 |

### 0.2. Cấp 1 đánh Spider (ước lượng)

| Trường hợp | Giết 1 con | Máu mất / con | Số con / 1 thanh máu |
|---|---|---|---|
| DK tay không (Phase 1) | 7.2 s | 27 | 7 |
| DK + `sword_t0` | 2.8 s | 11 | 17 |
| DW tay không | 8.1 s | 46 | **2.4** |
| DW + gậy t0, `energy_ball` tầm 4 | 3.2 s | 12.5 | 9 |
| ELF tay không | 5.4 s | 27 | 5 |
| ELF + cung t0 tầm 5 | 2.8 s | 7.4 | 17.5 |
| DW / ELF + bộ giáp t0 (def +12 / +10) | 2.8–3.2 s | 1–2 | > 70 |

### 0.3. Simulator thật sau P2-M2 (`mix mu.simulate --runs 20`, tới 5000 con)

| Lệnh | Tới cấp 10 | Potion tới cấp 10 | Máu mất / con |
|---|---|---|---|
| `--class DK --gear none` | 1111 con, 130 phút | 149 | 3,1 |
| `--class DK --gear full` | 75 phút | 2 | 0,53 |
| `--class DW --gear none --strategy ene` | 95 phút | 265 | 5,3 |
| `--class DW --gear starter --strategy ene` | 66 phút | 103 | 2,0 |
| `--class DW --gear full --strategy ene` | 66 phút | 7 | 0,25 |
| `--class ELF --gear none --strategy agi` | 81 phút | 71 | 0,98 |
| `--class ELF --gear starter --strategy agi` | 63 phút | 0,6 | 0,08 |

Không ai tới cấp 20 chỉ với Spider (EXP giảm theo chênh cấp) — cần quái P2-M4. Simulator giả định
đứng yên đánh (không thả diều), DW chưa có skill (P2-M3).

**Kết luận:** DW tay không quá yếu (chết sau ~2 con) → cần vũ khí khởi đầu hoặc skill tầm xa từ cấp 1.
Có giáp t0 thì Spider gần như vô hại với mọi class (giống Q14 của DK) — chấp nhận cho map đầu.

## 1. P2-2 — `maxLevel` Phase 2

| Phương án | Ghi chú |
|---|---|
| **A (đề xuất): 30** | Đủ chỗ cho skill cấp 5–18 dưới đây; cần quái cấp 10–30 ở P2-M4 (EXP `round(100·l^1.5)`: cấp 30 cần ~16.400 EXP / cấp) |
| B: 20 | Ít quái hơn ở M4; skill cấp > 20 dời sang Phase 3 |

Đổi `maxLevel` cũng gỡ được **E-2** (Twisting Slash cấp 10 = maxLevel Phase 1).

## 2. P2-3 — Tạo nhân vật theo class

- Màn tạo nhân vật có chọn class: DK, DW, ELF (MG khóa tới Phase 3).
- Map xuất phát: **Lorencia cho mọi class** (Noria chỉ khi P2-M4 làm map Noria; lúc đó Elf xuất phát Noria nếu anh muốn).
- Zen khởi đầu 0 (như DK).
- Đồ khởi đầu — chọn một:

| Phương án | DK | DW | ELF | Ghi chú |
|---|---|---|---|---|
| **A (đề xuất)** | không có (giữ Phase 1) | `staff_t0` | `bow_t0` | DW/Elf cần vũ khí để không chết ngay (§0.2); DK giữ nguyên để không đổi nghiệm thu Phase 1 |
| B | `sword_t0` | `staff_t0` | `bow_t0` | Công bằng hơn; phải sửa test/nghiệm thu DK (Dmg 4~7 → 7~14) |
| C | không | không | không | DW cần `energy_ball` miễn phí mana và tầm xa để sống sót |

Cấu hình: `newCharacter.classes = ["DK","DW","ELF"]`, `newCharacter.startingItems = {DK: [], DW: ["staff_t0"], ELF: ["bow_t0"]}` (đồ mặc sẵn, ghi audit `STARTER`).

## 3. P2-5 — Cung, gậy, tầm đánh

| Luật | Đề xuất |
|---|---|
| Loại vũ khí | Thêm `weaponType` vào template lúc import theo group Item.txt: 0 sword, 1 axe, 2 mace, 3 spear, **4 bow/crossbow**, **5 staff** (`KB_ITEM_REFERENCE §2`) |
| Tầm đánh thường | `combat.basicAttackRange`: mặc định 1; `bow` 5; `staff` 1 (DW đánh xa bằng skill `energy_ball`) |
| Cung hai tay | Cung/nỏ khóa ô SHIELD: mặc cung khi có khiên → `INVALID_SLOT` (client báo "Cung cần hai tay — tháo khiên trước"); mặc khiên khi đang cầm cung → `INVALID_SLOT` |
| Mũi tên | **Không dùng** (không có item tiêu hao cho cung) |
| Đánh xa ra sao | Server kiểm tầm Chebyshev như hiện tại (G4); chưa kiểm vật cản giữa hai bên (line of sight) |

## 4. P2-6 — Item cho DW/Elf

Item thật nhập từ `Item.txt` theo `KB_ITEM_REFERENCE §3` khi anh đặt file (E6). Danh sách đề xuất (tier thấp nhất class dùng được):

| templateId | Item.txt | Class | Số tạm nếu chưa có Item.txt (IMPLEMENTATION) |
|---|---|---|---|
| `staff_t0` | 5/0 Skull Staff | DW | Dmg 3–6, speed 20, yêu cầu ENE ≤ 30, STR ≤ 18 (để DW cấp 1 mặc được) |
| `bow_t0` | 4/0 Short Bow | ELF | Dmg 2–5, speed 20, yêu cầu AGI ≤ 25 |
| `pad_{helm,armor,pants,gloves,boots}_t0` | 7–11/2 bộ Pad (KB: "Pad Helm (7/2) DK=0") | DW | Def 3 / 6 / 4 / 1 / 1 (tổng 15, Leather DK = 26) |
| `vine_{helm,armor,pants,gloves,boots}_t0` | bộ Vine (index tra lúc import) | ELF | Def 4 / 8 / 5 / 2 / 2 (tổng 21) |

- `sword_t0`, `shield_t0`, `ring_hp_t0` đã cho cả DW/ELF (cờ class trong Item.txt); DW STR 18 < 21 nên chưa cầm kiếm được ở cấp 1.
- **Câu hỏi còn mở:** gậy trong Item.txt có cột "magic power" riêng. KB §4.1 công thức DW chỉ dùng `weapon.attackMax` → em đề xuất **bỏ qua magic power**, dùng cột Dmg như vũ khí khác. Nếu cột Dmg của gậy = 0 thì phải đổi: dùng magic power làm `attackMin/Max`.
- Shop (P2-11 nhắc lại): Potion Merchant bán thêm `mp_potion_small` (giá 120 có sẵn trong template); thêm NPC vũ khí/giáp ở M4.

## 5. P2-4 — Skill theo class

Định dạng giữ như `priv/game_data/skills.json`. `cooldownMs: null` = theo attackSpeed (như `basic_attack`).
Học skill: **tự có khi đạt `requiredLevel`** (§7, như Phase 1); chưa có sách/NPC.

### 5.1. DK

| id | Tên | Cấp | Mana | Cooldown | Tầm | Vùng | Hệ số | Loại |
|---|---|---|---|---|---|---|---|---|
| `falling_slash` | Falling Slash | 5 | 6 | 900 | 1 | 0 | 1.6 | SINGLE |
| `twisting_slash` | Twisting Slash | 10 | 10 | 800 | 2 | 2 | 1.2 | AOE quanh mình (có sẵn) |
| `death_stab` | Death Stab | 18 | 12 | 1200 | 2 | 0 | 2.0 | SINGLE |

### 5.2. DW

| id | Tên | Cấp | Mana | Cooldown | Tầm | Vùng | Hệ số | Loại |
|---|---|---|---|---|---|---|---|---|
| `energy_ball` | Energy Ball | 1 | 1 | null | 4 | 0 | 1.0 | SINGLE |
| `fire_ball` | Fire Ball | 5 | 3 | 1000 | 5 | 0 | 1.5 | SINGLE |
| `lightning` | Lightning | 12 | 6 | 1200 | 5 | 0 | 2.0 | SINGLE |
| `teleport` | Teleport | 15 | 20 | 3000 | 6 | — | — | MOVEMENT `{id, x, y}`: ô đích walkable, không trong vùng cấm |
| `flame` | Flame | 18 | 15 | 1500 | 5 | 2 | 1.2 | AOE tại ô chọn `{id, x, y}` |

### 5.3. ELF

| id | Tên | Cấp | Mana | Cooldown | Tầm | Vùng | Hệ số / tác dụng | Loại |
|---|---|---|---|---|---|---|---|---|
| `heal` | Heal | 3 | 8 | 1500 | 4 | — | hồi `10 + energy/4` HP (ENE 15 → 13) | HEAL bản thân / người chơi |
| `triple_shot` | Triple Shot | 6 | 6 | 1000 | 5 | 1 | 0.8 mỗi mục tiêu, tối đa 3 quái quanh mục tiêu | AOE tại mục tiêu |
| `greater_defense` | Greater Defense | 8 | 15 | 1500 | 4 | — | +`2 + energy/8` defense, 60 s | BUFF |
| `greater_damage` | Greater Damage | 12 | 20 | 1500 | 4 | — | +`3 + energy/7` sát thương phẳng (bước 3 của §4), 60 s | BUFF |

### 5.4. Luật buff / heal (mới, cần duyệt)

- Mục tiêu: **bản thân hoặc người chơi khác** trong tầm (chưa có party tới Phase 3; PvP tắt nên chỉ có lợi). Không lên quái.
- Cùng buff: làm mới thời gian, giữ giá trị lớn hơn. Khác buff: cộng dồn.
- Mất khi chết hoặc thoát game; không lưu DB.
- Heal không vượt `hpMax`; dùng được trong safe zone.
- **Protocol:** `player.view` thêm `buffs: [{id, value, remainingMs}]`; `skill` đã có `{id, target}` và `{id, x, y}` trong §5. Event `combat` của heal: `dmg` âm hay event mới? Đề xuất: thêm trường `heal` vào `combat` (`CHANGE_REASON` khi làm).

### 5.5. Mana — chọn một

DW dùng `energy_ball` (1 mana) mất ~4 mana mỗi con Spider; MP 120 đủ ~30 con. Không có hồi mana thì
MP potion (120 Zen, +20 MP ≈ 5 con) đắt hơn Zen nhặt được (~10 Zen/con) → DW không tự nuôi được.

| Phương án | Mô tả |
|---|---|
| **A (đề xuất)** | Hồi MP tự nhiên `combat.mpRegenPerSecond = energy / 40` (DW cấp 1: 0.75/s; DK 0.25; ELF 0.375). HP vẫn không tự hồi (G9) |
| B | `energy_ball` miễn phí mana (0); vẫn không hồi tự nhiên; MP chỉ cho skill mạnh |
| C | Giữ G9, giảm giá MP potion |

### 5.6. Client

- Menu skill (context menu §19.9) liệt kê skill theo class; skill `{x, y}` (teleport, flame) chọn ô sau khi bấm skill.
- **Tự đánh lặp lại skill đã chọn** tới khi hết mana / mục tiêu chết (hiện chỉ dùng skill 1 lần rồi về đánh thường) — cần cho DW. Hết mana → về đánh thường như hiện tại.
- Hiệu ứng: số bay lên + màu theo loại (sát thương / hồi máu); sprite effect để sau (BACKLOG §2).

## 6. Việc kèm theo khi làm M2–M3

- `classes.json` thêm DW/ELF từ `KB_CONFIG §2` + `derived` từ §4.1 (đã có trong KB, không đề xuất).
- Sprite DW/Elf: DCSS (CC0) như DEC-52, ghi `CREDITS.md`.
- Simulator theo class + báo cáo số thật trong `docs/ACCEPTANCE.md`.
- Test: tạo 3 class, chỉ số cấp 1 đúng bảng §0.1, luật cung/khiên, tầm đánh, mỗi skill (mana, cooldown, tầm, vùng), buff hết hạn/mất khi chết, heal không vượt max.
