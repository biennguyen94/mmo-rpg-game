# Đề xuất số liệu P2-M4 — quái, drop, NPC, map Noria, cổng chuyển map

> Trả lời P2-7, P2-10, P2-11 (`docs/OPEN_QUESTIONS.md`). **Chỉ là đề xuất, chưa vào `priv/game_data/`.**
> Mọi số là `sourceType: "IMPLEMENTATION"`, `verified: false` — số của dự án, **không phải số MU**.
> Tên quái/item mượn từ MU cho quen. Anh duyệt từng mục (A/B hoặc sửa số).

## 0. Cách tính và phát hiện quan trọng

Script nhỏ dùng chính `Mu.Game.Engine` (chỉ số §4.1, sát thương §4, trúng §5, cooldown §6). Người
chơi giả định: cộng điểm cân bằng theo class (DK 40% STR / 30% AGI / 30% VIT; DW 50% ENE / 20% AGI /
30% VIT; ELF 50% AGI / 20% STR / 30% VIT), đồ t0 dưới cấp 10, t1 (§3) từ cấp 10. DW dùng skill
mạnh nhất đã học (Energy Ball → Fire Ball cấp 5 → Lightning cấp 12). Mục tiêu khi đánh quái
**ngang cấp**: ~5 giây / con, DK chịu ~7–8 con / thanh máu, ~29 con / cấp.

**Phát hiện (cần anh biết):** công thức §4.1 cho sát thương người chơi tăng rất chậm theo stat
(`STR/4`, `ENE/4`…): DK cấp 29 chỉ đánh ~23–36. Vì vậy máu quái để "5 giây / con" gần như phẳng
(66 → 155 từ cấp 4 tới 29); tiến bộ chủ yếu đến từ **đồ** (t0 → t1). Chấp nhận cho Phase 2, hoặc
tăng hệ số §4.1 (là IMPLEMENTATION nhưng nằm trong KB → anh quyết, em không sửa `docs/kb/`).

## 1. P2-7 — Quái (13 loại, 2 map)

Công thức nền (chỉnh tay theo vai trò): `exp = round(3.5 × level^1.5)` (≈ 29 con ngang cấp / cấp với
`100 × level^1.5`), `attackRate = 5 × level`, `defenseRate = 1.5 × level`, `defense ≈ level / 4`,
Zen `2.5 × level … 7.5 × level`. Spider giữ nguyên `KB_CONFIG §4`.

| id | Tên | Map | Cấp | HP | Sát thương | Thủ | attackRate / defenseRate | EXP | Zen | Đi (ô/s) | Tầm đánh | Hồi sinh (s) | Số con | Ghi chú |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `spider` | Spider | Lorencia | 2 | 30 | 8–14 | 1 | 10 / 3 | 10 | 5–15 | 3 | 1 | 8 | 10 | KB_CONFIG §4, giữ nguyên |
| `budge_dragon` | Budge Dragon | Lorencia | 4 | 66 | 30–44 | 1 | 20 / 6 | 28 | 10–30 | 3 | 1 | 10 | 8 | |
| `bull_fighter` | Bull Fighter | Lorencia | 6 | 65 | 30–44 | 2 | 30 / 9 | 51 | 15–45 | 3 | 1 | 10 | 8 | |
| `hound` | Hound | Lorencia | 9 | 73 | 31–47 | 2 | 45 / 14 | 95 | 23–68 | **4** | 1 | 10 | 8 | nhanh |
| `lich` | Lich | Lorencia | 11 | 92 | 47–71 | 3 | 55 / 17 | 128 | 28–83 | 3 | **4** | 12 | 5 | **đánh xa**, máu ×0,8 |
| `elite_bull_fighter` | Elite Bull Fighter | Lorencia | 13 | 117 | 47–70 | 3 | 65 / 20 | 164 | 33–98 | 3 | 1 | 12 | 4 | |
| `goblin` | Goblin | Noria | 12 | 115 | 47–70 | 3 | 60 / 18 | 145 | 30–90 | 3 | 1 | 10 | 10 | |
| `chain_scorpion` | Chain Scorpion | Noria | 15 | 117 | 48–72 | 4 | 75 / 23 | 203 | 38–113 | 3 | 1 | 10 | 8 | |
| `beetle_monster` | Beetle Monster | Noria | 18 | 105 | 49–74 | 7 | 90 / 27 | 267 | 45–135 | 3 | 1 | 12 | 8 | thủ ×1,6 |
| `hunter` | Hunter | Noria | 20 | 98 | 51–77 | 5 | 100 / 30 | 313 | 50–150 | 3 | **4** | 12 | 6 | **đánh xa**, máu ×0,8 |
| `forest_monster` | Forest Monster | Noria | 23 | 125 | 51–77 | 6 | 115 / 35 | 386 | 58–173 | 3 | 1 | 12 | 6 | |
| `agon` | Agon | Noria | 26 | 124 | 53–80 | 7 | 130 / 39 | 464 | 65–195 | 3 | 1 | 15 | 5 | sát thương ×1,15 |
| `stone_golem` | Stone Golem | Noria | 29 | 155 | 51–77 | 12 | 145 / 44 | 547 | 73–218 | **2** | 1 | 20 | 4 | chậm, máu ×1,5, thủ ×1,6 |

Chung: `aggroRange` 5 (Stone Golem 3), `leashRange` 12, AI như Phase 1 (IDLE → CHASE → ATTACK →
RETURN). Quái đánh xa (`attackRange` 4) đứng cách 4 ô đánh — triệt lợi thế cung/phép.

### 1.1. Ước lượng khi đánh quái ngang cấp

| Quái (cấp) | DK: giây/con · con/thanh máu | DW · | ELF · |
|---|---|---|---|
| Budge Dragon (4) | 5,7 s · 8,4 | 6,0 s · 1,7 | 5,4 s · 4,0 |
| Hound (9) | 5,7 s · 8,4 | 4,9 s · 2,0 | 5,3 s · 3,6 |
| Lich (11, xa) | 4,6 s · 7,5 | 4,3 s · 1,4 | 4,8 s · 2,5 |
| Goblin (12) | 5,7 s · 6,8 | 4,5 s · 1,8 | 5,8 s · 2,5 |
| Hunter (20, xa) | 4,6 s · 8,2 | 3,4 s · 1,9 | 4,3 s · 2,8 |
| Agon (26) | 5,7 s · 7,1 | 4,0 s · 2,3 | 5,2 s · 2,9 |
| Stone Golem (29) | 8,5 s · 6,2 | 5,2 s · 2,2 | 7,4 s · 2,6 |

DW / ELF mỏng hơn (đúng vai pháp sư / cung thủ): sống nhờ đánh xa (chưa tính thả diều), potion, Heal
của Elf, hồi MP. Lên cấp 1 → 30 đánh quái ngang cấp: ~850 con ≈ 1,5–2 giờ. **Số thật** chạy bằng
simulator mở rộng (quái theo map, skill DW, potion) ở P2-M4 rồi chỉnh tiếp.

### 1.1b. Simulator thật sau P2-M4 (`mix mu.simulate --runs 10 --monster auto --progress --skills`)

| Class (cộng điểm) | Tới cấp 10 | Tới cấp 20 | Tới cấp 30 | Potion tới cấp 30 | Chết |
|---|---|---|---|---|---|
| DK (balanced) | 298 con, 33 phút | 604 con, 71 phút | 907 con, 115 phút | 330 | 0 |
| DW (ene) | 26 phút | 51 phút | 72 phút | 725 | 0 |
| ELF (agi) | 27 phút | 52 phút | 76 phút | 260 | 0 |

Giả định: đứng đánh (không thả diều), chỉ potion HP nhỏ, không Heal. Zen tới cấp 30 ≈ 63.000.

### 1.2. Sprite

DCSS (CC0) như DEC-52: mỗi quái một hình tĩnh, chọn lúc làm, kiểm từng file với
`TILES_UNDER_UNKNOWN_LICENSE.md` + hash, ghi `mapping.json` / `CREDITS.md`.

## 2. P2-10 — Map Noria + cổng chuyển map

| Mục | Đề xuất |
|---|---|
| Map mới | **Noria** 64×64, em tự dựng (rừng: cỏ, cây, nước, đá — tile DCSS); `levelRequired` 10 (KB_CONFIG §3) |
| Bố cục Noria | Thị trấn (safe zone) ở giữa-nam, `playerSpawn` trong thị trấn; 7 vùng quái quanh thị trấn, cấp tăng dần theo khoảng cách |
| Bố cục Lorencia mới | Spider: đông (như cũ); Budge Dragon: ~~tây bắc~~ đông bắc (DEC-72); Bull Fighter: đông bắc; Hound: tây nam; Lich + Elite Bull Fighter: đông nam |
| Cổng | Lorencia `(15,8)`–`(16,8)` (đầu đường đất phía bắc) → Noria, đứng ở ô cạnh cổng về Lorencia; Noria cổng nam → Lorencia `(15,9)` |
| Định dạng | `portals: [{x, y, w, h, to: mapId, toX, toY, levelRequired}]` trong `priv/maps/<id>.json` (đã có trường `portals: []`) |
| Đi qua cổng | Bước vào ô cổng = chuyển map ngay (server kiểm cấp; thiếu cấp → `REQUIREMENT_NOT_MET`, client báo "Cần cấp 10 để vào Noria", đứng lại) |
| Chết | Hồi sinh ở `playerSpawn` của **map đang đứng** (§11 "safe zone của map") |
| Lưu | `characters.map_id` + vị trí (cột đã có) |
| **Protocol** | Event mới server → client `map_change {map, player, entityId}` (cùng dữ liệu `map`/`player` như reply join); kênh đổi topic PubSub sang map mới, client dựng lại thế giới. Cần `CHANGE_REASON` trong `KB_TECHNICAL §5` → **anh duyệt** (phương án khác: bắt client join lại kênh — chậm hơn, mất trạng thái tự đánh) |

## 3. P2-6 bổ sung — đồ t1 (cấp 10) + potion vừa

Số tạm (như P2-M2) tới khi có Item.txt (E6); **icon placeholder `custom/…`** vì chưa đối chiếu được index.

| templateId | Tên | Class | Chỉ số | Yêu cầu | Giá mua |
|---|---|---|---|---|---|
| `sword_t1` | Rapier | DK, ELF | Dmg 9–15, speed 20 | cấp 10, STR 40 | 3000 |
| `staff_t1` | Angelic Staff | DW | Dmg 7–12, speed 20 | cấp 10, ENE 40 | 3000 |
| `bow_t1` | Bow | ELF | Dmg 6–11, speed 20 (hai tay) | cấp 10, AGI 40 | 3000 |
| `shield_t1` | Horn Shield | DK, DW, ELF | Def 4 | cấp 10, STR 35 | 2400 |
| `bronze_{helm,armor,pants,gloves,boots}_t1` | Bronze … | DK | Def 8 / 16 / 12 / 4 / 4 (tổng 44; Leather 26) | cấp 10, STR 40 | 1500 / 3000 / 2100 / 1200 / 1200 |
| `bone_{…}_t1` | Bone … | DW | Def 5 / 10 / 7 / 2 / 2 (tổng 26; Pad 15) | cấp 10, ENE 40 | như trên |
| `silk_{…}_t1` | Silk … | ELF | Def 6 / 13 / 9 / 3 / 3 (tổng 34; Vine 21) | cấp 10, AGI 40 | như trên |
| `hp_potion_medium` | Healing Potion | mọi class | hồi 120 HP, stack 99 | — | 300 |
| `mp_potion_medium` | Mana Potion | mọi class | hồi 60 MP, stack 99 | — | 350 |

Đồ t2 (cấp 20+) để sau (cần Item.txt hoặc bảng số mới) — trong Phase 2 cấp 20–30 dùng t1.

## 4. Drop table

| Nhóm | Quái cấp < 10 (Lorencia trừ Lich/EBF) | Quái cấp ≥ 10 |
|---|---|---|
| Zen | theo bảng §1 | theo bảng §1 |
| `potions` (chance 0,15) | HP nhỏ 80 / MP nhỏ 20 | HP vừa 60 / MP vừa 25 / HP nhỏ 15 |
| `equipment` (chance 0,04; Spider giữ 0,06) | mọi món t0 của **cả 3 class** + `ring_hp_t0` (weight bằng nhau) | mọi món t1 (weight 3) + t0 (weight 1) |

Đồ rơi +0, không option (G17). Spider thêm đồ t0 của DW/Elf (gỡ P2M2-4: hiện chỉ có đồ DK).

## 5. P2-11 — NPC / Shop

| NPC | Map, vị trí | Bán |
|---|---|---|
| `lorencia_potion_merchant` (có sẵn) | Lorencia (11,25) | HP nhỏ, MP nhỏ |
| `lorencia_weapon_merchant` "Weapon Merchant" | Lorencia (11,37) | mọi món t0 (3 class) + `shield_t0`; không bán nhẫn |
| `noria_potion_merchant` "Potion Merchant" | Noria, trong thị trấn | HP/MP nhỏ + vừa |
| `noria_weapon_merchant` "Weapon Merchant" | Noria, trong thị trấn | mọi món t1 |

Giá mua = `buyPrice`, bán lại = `floor(buyPrice × economy.sellRatio)` như hiện tại.

## 6. Việc kèm theo khi làm P2-M4

- `monsters.json`, `drops.json`, `items` (data/items/phase2.json), `shop.json`, `priv/maps/noria.json` + collision, sửa `lorencia.json` (vùng quái, cổng, NPC).
- MapServer cho Noria (đã có Registry theo map), chuyển map giữa hai MapServer, Session lưu `map_id`.
- Simulator: quái theo map, DW dùng skill, uống potion; báo số thật như `ACCEPTANCE.md §3`.
- Client: dựng lại thế giới khi `map_change`, vẽ ô cổng, tên map ở HUD; sprite quái + NPC mới.
- Test: dữ liệu (mọi quái có drop, mọi item trong drop/shop tồn tại, cổng hai chiều nằm trên ô đi được), chuyển map + thiếu cấp, hồi sinh đúng map, quái đánh xa, e2e đi Lorencia → Noria.
- **G26** (bầy Spider) vẫn chờ anh; mật độ quái Lorencia tăng (≈ 43 con) nên nên chốt cùng lúc.
