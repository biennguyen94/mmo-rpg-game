# KB_ITEM_REFERENCE — Item.txt + icon → dữ liệu item của game

> Nguồn: `Item.txt` do developer cung cấp (**663 item**, 16 group, không trùng `(group, index)`; hai lần parse độc lập khớp nhau về tên và số liệu trên 552 item so sánh được) + bộ icon đặt tên `item_{group}_{index}…`.
> **Version: `s5+`.** File có comment `//Season5`, Jewel of Creation (14/22), Dark Raven, cột Summoner → thuộc Season 5 trở lên, **không phải** `0.97d` (`KB_00_RULES` S1, S10). Mọi bản ghi lấy từ file này mang `version: "s5+"`, `verified: false` (= chưa đối chiếu với 0.97d; việc parse đã được kiểm tra).
> Dùng làm **seed** để viết `data/items/*.json`, không phải sự thật Season 1.
> Phạm vi: tra cứu dữ liệu + chọn icon. Luật equip/combat: `KB_GAME_DESIGN §4.1, §8`; schema DB: `KB_TECHNICAL §9`.

## 0. Pháp lý

- `Item.txt` và icon đặt theo `item_{group}_{index}` là dữ liệu MU của Webzen. Nếu icon trích từ client MU thì áp dụng `KB_ASSETS §1`: **chỉ prototype riêng tư**, không public/kiếm tiền (Q11, A5).
- Nếu sau này public: đổi tên + icon; item tự tạo dùng `iconRef.custom` nên thay asset không đổi `templateId`.

## 1. Định dạng file (đã kiểm chứng)

- Phân cách bằng **tab**, nhưng số tab đệm giữa tên item và cột `ItemLvl` **không cố định** (0–3 tab). **Không được đọc theo vị trí cột cố định**: lấy các trường không rỗng sau tên. Tên nằm trong dấu `"…"`.
- Một dòng (group 12, index 39 "Wings of Hurricane") dùng **dấu cách** thay vì tab trong phần số → tách bằng khoảng trắng (`str.split()`), không `split('\t')`.
- Mỗi group: comment header, dòng `<group_id>`, các item, `end`. Group 0 không có comment tên. Index có khoảng trống (vd group 0 nhảy 28 → 31): không giả định liên tục.
- File ASCII sạch, nhưng vẫn đọc `utf-8` tường minh, `errors="replace"`, và ghi cảnh báo nếu có thay thế.
- Raw chuẩn: `priv_reference/items_raw.json` (= `priv/reference/` khi vào dự án Phoenix; **bỏ group 12 và 15**, chỉ có 552 item). Script `scripts/parse_items.py` là bản parse độc lập, đọc đủ cả 16 group (663 item); dùng để kiểm chéo hoặc khi cần Wing/Scroll. Không giữ hai file raw song song trong dự án.

### 1.1. Số item theo group

| Group | Loại | Số item | Group | Loại | Số item |
|---|---|---|---|---|---|
| 0 | Sword | 30 | 8 | Armor | 54 |
| 1 | Axe | 9 | 9 | Pants | 54 |
| 2 | Scepter | 19 | 10 | Gloves | 54 |
| 3 | Spear | 12 | 11 | Boots | 54 |
| 4 | Bow/Crossbow | 25 | 12 | Wing/Orb/Seed | 81 |
| 5 | Staff | 29 | 13 | Pet/Ring/Pendant | 63 |
| 6 | Shield | 22 | 14 | Potion/Jewel/Quest | 80 |
| 7 | Helm | 47 | 15 | Skill Scroll | 30 |

### 1.2. Cột theo group (đã đối chiếu với header trong file)

| Group | Cột sau tên (theo thứ tự) |
|---|---|
| 0–5 | ItemLvl, DmgMin, DmgMax, Speed, Durability, MagicDur, MagicPwr, ReqLvl, Str, Agi, Ene, Vit, Command, Type, + 6 cờ class |
| 6–11 | ItemLvl, **Def, DefRate**, Durability, ReqLvl, Str, Agi, Ene, Vit, Command, Type, + 6 cờ class (**không có** Speed/MagicDur/MagicPwr) |
| 12 | Lvl, Def, Dur, ReqLvl, Ene, Str, Agi, Comm, Zen |
| 13 | Lvl, Dur, Ice, Poison, Light, Fire, Earth, Wind, Water, Type |
| 14 | Valor, ItemLvl |
| 15 | Lvl, ReqLvl, Energy, Zen |

Trước tên: `Index, ItemSlot, Skill, X, Y, Serial, Option, Drop`. 6 cờ class theo thứ tự `DW, DK, ELF, MG, DL, SUM`.

### 1.3. Điều đã xác định từ dữ liệu (đóng các câu hỏi cũ)

| Điều | Kết luận | Bằng chứng |
|---|---|---|
| **Cờ class (Q8)** | **Bậc tiến hóa tối thiểu**, không phải bitmask. 0 = không dùng; 1 = class gốc trở lên; 2 = chỉ bản tiến hóa; 3 = bản tiến hóa 3 | DK có 213 mục =1, 30 mục =2 (vd Dark Breaker, Knight Blade), 340 mục =0 |
| **`X`, `Y`** | **Kích thước item tính bằng ô túi** (rộng × cao), không phải pixel | Kris 1×2, Short Sword 1×3, Light Saber 2×4, Small Shield 2×2, Bronze Helm 2×2, Dragon Armor 2×3, potion/ring 1×1 |
| **`RequiredLvl`** | **Hầu như luôn 0**: vũ khí 0/124, potion 0, shield 4/22; chỉ set cao cấp (vd Brave = 380) và vài wing có giá trị. Yêu cầu thực tế nằm ở **Str/Agi/Ene/Vit** | Đếm theo group |
| **`ItemSlot`** | Group 0–3, 5 (phần lớn): 0; bow (group 4) 1 hoặc 0; shield 1; helm 2; armor 3; pants 4; gloves 5; boots 6; wing 7; pet 8; pendant 9; ring 10 | Đếm theo group; xem §2 |
| `Valor` (group 14) | **Chưa rõ (Q7).** Quan sát: Apple 5, Small/Healing/Large Potion 10/20/30, Jewel of Bless/Soul 150, nhiều quest item 0 → có vẻ là hệ số giá/giá trị theo cấp phẩm. Chỉ là phỏng đoán | |
| `Type` | Nhóm 0–4 tùy group; **không** liên quan class. Bỏ qua | |
| Tên | Có lỗi chính tả gốc: "Sword of Assassain", "Lighting Sword", "//Hemls". Giữ nguyên `name` trong raw; `displayName` sửa tay khi cần | |

## 2. Group → slot trong KB

Cột "MU slot" là **quan sát từ file**; chỉ dùng cột "Slot KB" (`KB_CONFIG §6`). Không copy số slot MU.

| Group | Loại | MU slot (quan sát) | Slot KB |
|---|---|---|---|
| 0, 1, 2, 3 | Sword, Axe, Scepter, Spear | 0 | WEAPON |
| 4 | Bow/Crossbow | 14 mục slot 1, 11 mục slot 0 | WEAPON (Phase 2; chưa có quy tắc "cung chiếm slot khiên") |
| 5 | Staff | 26 mục slot 0, 3 mục slot 1 | WEAPON (3 mục slot 1: sách/phụ kiện DW, bỏ qua tới Phase 2) |
| 6 | Shield | 1 | SHIELD |
| 7–11 | Helm, Armor, Pants, Gloves, Boots | 2, 3, 4, 5, 6 | HELM, ARMOR, PANTS, GLOVES, BOOTS |
| 12 | Wing/Orb/Seed | 15 mục slot 7 (cánh), 66 mục slot -1 | WING (khóa khi `features.wings=false`) / MISC |
| 13 | Pet/Ring/Pendant | pet 8 (15), pendant 9 (6), **ring 10 (18)**, 2 mục lạ (slot 1, 7), 22 mục -1 | RING1/RING2 (ring) / MISC |
| 14 | Potion/Jewel/Quest | -1 | POTION / MISC |
| 15 | Scroll | -1 | MISC |

> `Zen` là một **item** trong file (14/15, 1×1). KB xử lý Zen là số dư trong `characters.zen` (`KB_TECHNICAL §9`), không phải item; không nhập 14/15 vào template.
> Jewel: Bless 14/13, Soul 14/14, Life 14/16 (Phase 5); **Creation 14/22 = `LATER_VERSION`**.

## 3. Từ Item.txt sang template của game

### 3.1. Quy tắc

1. Template là bản ghi do dự án viết (`data/items/*.json`). `templateId` là khóa của game; `group/index` chỉ nằm trong `reference` và `iconRef`.
2. Giá trị lấy nguyên từ Item.txt → `sourceType: "REFERENCE"`, `version: "s5+"`.
3. **Yêu cầu stat nhân `items.requirementScale` lúc import** (KB_CONFIG §1: không đọc lúc runtime). Template lưu `requirements` đã scale; giá trị gốc ở `reference.requirementsRaw`; `reference.adjusted` ghi cách scale. Vì chỉ số đã bị điều chỉnh nên bản ghi là `IMPLEMENTATION` (quy tắc 5).
4. Trường do dự án thêm (`buyPrice`, `effect`, `potionType`, `maxStack`, …) liệt kê trong `implementationFields`. Nếu **cả bản ghi** là tự tạo (vd `ring_hp_t0`) → `sourceType: "IMPLEMENTATION"`, `reference: null`.
5. Nếu chỉnh một chỉ số gốc (damage, defense…) → bản ghi thành `IMPLEMENTATION` và ghi giá trị gốc trong `reference.adjusted`.
6. `classes` lấy từ cờ **==1** của 4 class trong scope (`DW, DK, ELF, MG`); bỏ DL, SUM (`KB_00_RULES` S4). Không tự thu hẹp (bản nháp cũ giới hạn Short Sword còn `["DK","MG"]` nhưng dữ liệu cho cả DW/Elf).

### 3.2. Quy đổi cần chốt (Q12) — đã tính số

DK level 1 có **STR 28, AGI 20, ENE 10, VIT 25**. Mọi bộ giáp/mũ/găng/giày/quần cho DK trong file yêu cầu **STR ≥ 80** (Leather: 80/0; Bronze: 80/20). Số món Phase 1 DK level 1 equip được (8 slot có yêu cầu) theo `requirementScale`:

| `requirementScale` | Equip được |
|---|---|
| 1.0 | 1 / 8 (chỉ ring) |
| 0.5 | 1 / 8 (STR 80 → 40 > 28) |
| **0.35** | **8 / 8** (80 → 28) |

→ Default **`items.requirementScale = 0.35`** (áp lúc import, làm tròn half-up cho STR/AGI/ENE/VIT, không áp cho `level`; xem `KB_CONFIG §1`). Đổi scale = chạy lại import. Hệ quả: một món cần 80 STR gốc tương đương 28 STR trong game; set Dragon (120/30) tương đương 42/11 → DK cấp ~4 (cộng điểm) mới mặc được. Đây là quyết định cân bằng (IMPLEMENTATION), chỉnh bằng config.

`Speed`: dùng nguyên (`items.speedScale = 1.0`). Với DK level 1 (`attackSpeed = agility/15 + weapon.speed`): Short Sword (speed 20) → 21 → cooldown ≈ **826 ms**; Kris (50) → 51 → ≈ **654 ms**. Bản nháp cũ "chia 5" cho speed 4 → cooldown 962 ms, gần như không khác không vũ khí.

### 3.3. Trường phải tự thêm

`templateId`, `buyPrice`, `sellPrice` (= `buyPrice × economy.sellRatio`), `stackable`, `maxStack`, `potionType`, `effect`, `iconRef`. `stackable` đặt từng template (group 14 gồm cả potion, jewel, quest). `potionType`/`effect` ghi tường minh, không suy từ tên hay `Valor`. `excellentOptions`, `luck`, `skill`: random lúc drop (`KB_GAME_DESIGN §10`).

## 4. Chọn icon

### 4.1. Nguyên tắc

- Biến thể icon phụ thuộc **instance** (level cường hóa, Excellent). Server gửi `templateId`, `level`, `excellentOptions`; **client tra `icon_map.json`**, server không gửi tên file.
- **Không dò file lúc runtime** (tránh hàng loạt 404). Script `mix mu.icons.index` quét **`assets_src/private/item_icons/`** (hoặc `ITEM_ICONS_DIR`), chép các file dùng được sang `priv/static/assets/icons/items/` và sinh `priv/static/assets/icon_map.json`. Cả hai đường dẫn đầu ra **gitignore** (`KB_ASSETS §2.2`). Input rỗng/thiếu → toàn bộ trỏ placeholder, exit 0.

### 4.2. Dùng level cường hóa, không dùng `ItemLvl`

```
bucket(level) = max(b ∈ {0,3,5,7,9,11,13,15} : b <= min(level, 15))
```

`level` = level cường hóa của instance (`Item.level`, +0…+9 ở Phase 5). Cột `ItemLvl` của Item.txt là level gốc của loại item (Short Sword 3, Kris 6…) — **không** dùng cho icon. Phase 1 không có cường hóa → bucket 0.

### 4.3. Thứ tự thử (chạy lúc build)

Với `(group, index, level, excellent)`, `ex = excellent ? "_e" : ""`:

1. `item_{g}_{i}_{bucket}{ex}.png`
2. `item_{g}_{i}_{bucket}.png`
3. Các bucket nhỏ hơn (lớn → nhỏ), mỗi bucket thử có `_e` rồi không `_e`
4. `item_{g}_{i}{ex}.png`
5. `item_{g}_{i}.png`
6. Placeholder; ghi cảnh báo build, **không crash**

`_a` (Ancient) bỏ khi `items.ancientVariants=false`. Bộ icon quan sát được có **cả** dạng không bucket (`item_0_0.png`) lẫn có bucket 0 (`item_0_2_0.png`); không giả định mọi item có đủ biến thể.

### 4.4. `icon_map.json`

```json
{
  "0/1":  { "0": "items/item_0_1_0.png", "9": "items/item_0_1_9.png", "9e": "items/item_0_1_9_e.png" },
  "14/1": { "0": "items/item_14_1.png" },
  "custom/ring_hp_t0": { "0": "custom/ring_hp_t0.png" },
  "_placeholder": "placeholder.png"
}
```

Giá trị là đường dẫn **tương đối** so với `priv/static/assets/icons/`. Khóa `group/index` cho item lấy từ MU; `custom/{templateId}` cho item tự tạo (**không** đặt index giả như 13/100). Tra ngược: parse tên file → `group, index, bucket, excellent`.

### 4.5. Kích thước ô túi (`X×Y`)

Item.txt cho kích thước ô (§1.3). UI Phase 1 là danh sách, mỗi item 1 dòng → **không dùng**. Nếu bộ icon thật có tỉ lệ theo `X×Y` (vd kiếm 1×3 = cao gấp 3), khung hiển thị phải **căn giữa, không kéo giãn** (`KB_GAME_DESIGN §19.4`). Lưu `reference.cells: [x, y]` để dùng khi làm lưới túi (Phase 2+).

## 5. Template Phase 1 (10 món — đã tra từ Item.txt)

File: `data/items/phase1.json`. Cột "Raw" là yêu cầu gốc (`reference.requirementsRaw`); "Game" = `requirements` sau scale 0.35.

| templateId | Item.txt | Chỉ số gốc | Raw STR/AGI | Game STR/AGI | Ghi chú |
|---|---|---|---|---|---|
| `hp_potion_small` | 14/1 Small Healing Potion | `Valor 10, ItemLvl 10` | — | — | `potionType HP`, `effect.hp 50`, `maxStack 99` (IMPLEMENTATION) |
| `mp_potion_small` | 14/4 Small Mana Potion | `Valor 10, ItemLvl 10` | — | — | `effect.mp 20`; chỉ có qua drop ở Phase 1 |
| `sword_t0` | 0/1 Short Sword | Dmg 3–7, Speed 20, Dur 22 | 60/0 | 21/0 | Class DW, DK, ELF, MG |
| `shield_t0` | 6/0 Small Shield | Def 1, DefRate 3, Dur 22 | 70/0 | 25/0 | |
| `helm_t0` | 7/5 Leather Helm | Def 5, Dur 30 | 80/0 | 28/0 | Chọn Leather thay Bronze: tier thấp nhất DK dùng được và AGI yêu cầu 0 |
| `armor_t0` | 8/5 Leather Armor | Def 10, Dur 30 | 80/0 | 28/0 | |
| `pants_t0` | 9/5 Leather Pants | Def 7, Dur 30 | 80/0 | 28/0 | |
| `gloves_t0` | 10/5 Leather Gloves | Def 2, DefRate 8, Dur 30 | 80/0 | 28/0 | |
| `boots_t0` | 11/5 Leather Boots | Def 2, DefRate 12, Dur 30 | 80/0 | 28/0 | |
| `ring_hp_t0` | **Không có** | `hpBonus 20` | — | — | IMPLEMENTATION; icon `custom` (placeholder) |

Sửa so với bản nháp: **Pad Helm (7/2) DK=0** — xác nhận đúng; **Bronze Helm** dùng được nhưng đòi AGI 20 và là tier cao hơn nên đổi sang Leather Helm. Giá (`buyPrice`) là placeholder IMPLEMENTATION, cần cân bằng.

### 5.1. Cảnh báo cân bằng (đã tính)

Defense DK level 1 = `agility/4 = 5`. Spider (damage 8–14, `KB_CONFIG §4`) gây:

| Trang bị | Defense tổng | Sát thương Spider nhận (8 / 11 / 14) |
|---|---|---|
| Không | 5 | 3 / 6 / 9 |
| **Chỉ Leather Armor** | 15 | **1 / 1 / 1** |
| Full Leather + Shield | 32 | 1 / 1 / 1 |

→ Chỉ cần **một** món áo là Spider hết đe dọa (defense 15 > damage tối đa 14), potion mất tác dụng. Với Phase 1 thì chấp nhận được (Spider là quái cấp 2), nhưng acceptance "dùng potion OK" phải test **trước khi** mặc áo. Cân bằng lại bằng simulator (`KB_TECH_STACK §8`).

## 6. Quy trình & test

```
1. mix mu.items.import  → priv/reference/items_raw.json   (hoặc scripts/parse_items.py để kiểm chéo)
2. data/items/phase1.json                                          (đã viết)
3. mix mu.icons.index  → priv/static/assets/icon_map.json          (cần icon thật)
4. mix test
```

Test bắt buộc:
- `templateId` duy nhất; mọi `iconRef` ra được file hoặc có `iconPlaceholder: true`.
- Mọi template có `reference` phải khớp dòng gốc trong `items_raw.json` (name, stats).
- Template có `reference.adjusted` phải là `IMPLEMENTATION`; `requirements` phải bằng `round(requirementsRaw × requirementScale)` (trừ `level`).
- DK level 1 (STR 28 / AGI 20) equip được ít nhất 1 template mỗi slot sau khi áp `requirementScale`.
- Không template nào dùng group 12 khi `features.wings=false`.

## 7. Open questions

| # | Câu hỏi | Trạng thái |
|---|---|---|
| Q7 | `Valor` (group 14) nghĩa là gì? | **Mở.** Phỏng đoán: hệ số giá/cấp phẩm. Không dùng; `effect` ghi tường minh |
| Q8 | Cờ class là gì? | **Đã trả lời:** bậc tiến hóa tối thiểu (§1.3). Dùng khi ==1 |
| Q9 | Version của Item.txt? | **Đã trả lời:** Season 5+ (`s5+`) |
| Q10 | Ring HP không có trong Item.txt | Template tự tạo, `iconRef.custom` |
| Q11 | Icon do ai làm / license / kích thước pixel? | **Mở** (cần icon thật; `KB_ASSETS` A5, A6). `X×Y` đã rõ là ô túi |
| Q12 | Quy đổi Speed và yêu cầu stat | **Đề xuất:** `speedScale 1.0`, `requirementScale 0.35` (§3.2). Chờ developer xác nhận |
