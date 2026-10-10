# Phase 15b — Đồ từ Item.txt (ghi chú để đổi sau)

> Anh chốt 2026-10-10: tải Item.txt + hình từ `afrokick/muonlinejs`, **không vào git**; lấy theo bậc (không lấy hết);
> yêu cầu chỉ số × 0,35. Mọi lựa chọn và con số nằm trong **một file**: `priv/game_data/item_pick.json`.
> Bảng xem trước (tự sinh): [`docs/ITEMS_PICK.md`](ITEMS_PICK.md).

## 1. Quy trình (mỗi máy chạy một lần)

```bash
cd reference/rpg-game
mix hac_long.items.fetch            # Item.txt → assets_src/private/items/Item.txt
mix hac_long.items.import           # → assets_src/private/items/items_raw.json, items_from_txt.json
mix hac_long.items.build --preview  # → docs/ITEMS_PICK.md (xem trước, không đổi game)
mix hac_long.items.build            # → priv/game_data/items_mu.json (đồ trong game) + tên tiếng Anh + ITEMS_PICK.md
# hình: clone repo hình của anh (riêng tư) cạnh repo này rồi chép hình của đồ đang có trong game
git clone --depth 1 https://github.com/biennguyen94/mmo-rpg-game-items ../../../mmo-rpg-game-items
mix hac_long.items.fetch --icons-from ../../../mmo-rpg-game-items/item_ref/items   # → assets_src/private/item_icons/
mix hac_long.icons                  # cắt viền trong suốt (ImageMagick) → priv/static/assets/mu_items/ + item_icons.json
```

| Đường dẫn | Nội dung | Git / Docker |
|---|---|---|
| `assets_src/private/items/` | Item.txt gốc + nháp đọc được | **bỏ qua** |
| `assets_src/private/item_icons/` | hình đồ gốc | **bỏ qua** |
| `priv/static/assets/mu_items/`, `priv/static/assets/item_icons.json` | hình đã chép + bảng tra cho client | **bỏ qua** |
| `priv/game_data/item_pick.json` | bảng chọn + hệ số (của mình, không chứa số gốc) | có |
| `priv/game_data/items_mu.json` | đồ dựng ra (khóa `ITEMS_MU`), game đọc file này | có |
| `docs/ITEMS_PICK.md` | bảng xem trước sinh tự động | có |

CI (`.github/workflows/ci.yml`, job `private-assets`) báo lỗi nếu file trong ba đường dẫn bị bỏ qua lọt vào git.
Máy chủ không có hình thì client dùng icon cũ, không lỗi.

**Nguồn hình:** repo riêng `biennguyen94/mmo-rpg-game-items`, thư mục `item_ref/items` (8 144 PNG, tên
`item_{nhóm}_{số}_{+N}.png`, biến thể `_e` Excellent; `item_ref/Item.txt` trùng bản đã tải). `--icons-from` chỉ chép
hình của đồ đang có trong game (≈ 1 600 hình, 12 MB), bỏ `_e`. Hình gốc để món đồ nhỏ giữa khung trong suốt lớn, nên
`mix hac_long.icons` cắt viền bằng ImageMagick (`convert -trim`; không có thì chép nguyên, `--no-trim` để tắt).

**Đổi nguồn Item.txt:** `mix hac_long.items.fetch --url <URL>` hoặc biến `HL_ITEM_TXT_URL`.

**Máy chủ / Docker:** hình không nằm trong image. Sau khi triển khai, chạy ba lệnh hình ở trên trong thư mục ứng
dụng (hoặc gắn sẵn `priv/static/assets/mu_items/` + `item_icons.json` bằng volume); bảng tra đọc lúc mở trang, không
cần build lại. Thiếu hình thì game dùng icon tạm.

## 2. Nguyên tắc

**Item.txt quyết định "là món gì"** (tên gốc, hình `ref`, lớp được dùng, tỉ lệ đòn thấp ~ cao, tỉ lệ thủ giữa các
món trong bộ, yêu cầu chỉ số). **Hắc Long quyết định "mạnh cỡ nào"** (bậc → cấp, công, thủ, giá) để đổi đồ không làm
lệch cân bằng đã chỉnh (simulator 4 lớp hạ Hắc Long khoảng cấp 35). Muốn dùng nguyên số MU: xem §4.

## 3. Từng khóa trong `item_pick.json`

| Khóa | Mặc định | Ý nghĩa | Đổi thì |
|---|---|---|---|
| `req_mult` | `0.35` | Yêu cầu STR/AGI/VIT/ENE = số trong Item.txt × hệ số, làm tròn | `1.0` = như MU (khó mặc hơn nhiều); `0` = bỏ yêu cầu |
| `no_req_tiers` | `[1]` | Bậc vũ khí / bộ giáp không đòi chỉ số (đồ khởi đầu: cung bậc 1 MU đòi AGI 28 > 25 của Tiên Nữ mới tạo) | `[]` = bậc nào cũng đòi |
| `levels.weapon` | `[1,3,7,12,17,22,27]` | Cấp nhân vật cần cho vũ khí bậc 1…7 (= cấp vũ khí Hắc Long cũ) | thêm / bớt phần tử = thêm / bớt bậc |
| `levels.set` | `[1,3,7,12,17,22]` | Cấp cho bộ giáp bậc 1…6 | |
| `levels.shield` | `[4,10,17]` | Cấp cho khiên bậc 1…3 | |
| `stats.weapon_mode` | `"raw"` | Vũ khí: công = trung bình `DmgMin~DmgMax` của file. Món được chọn sao cho khớp đường cong cũ (3, 7, 13, 21, 31, 44, 60) | từng món có thể ghi `"mode": "staff"` |
| `stats.staff_atk` | `[3,7,13,21,31,44,60]` | Công gậy phép (món có `"mode": "staff"`) theo bậc. Gậy MU sát thương vật lý rất thấp (sức mạnh nằm ở phép), nên dùng đường cong; khoảng thấp ~ cao lấy tỉ lệ của file | tăng để Phù Thủy mạnh hơn |
| `stats.set_def` | `[2,5,10,16,24,34]` | **Tổng** thủ của cả bộ (mũ + giáp + quần + găng + giày) theo bậc = thủ giáp cũ cùng cấp; chia cho từng món theo tỉ lệ `Def` trong file, tối thiểu 1 | |
| `stats.set_def_mult` | `1.0` | Nhân tổng thủ bộ giáp (vì giờ 5 món thay 1) | `1.3` = bộ đủ mạnh hơn giáp cũ 30 % |
| `stats.shield_def` | `[3,7,12]` | Thủ khiên theo bậc (= khiên cũ) | |
| `prices.weapon` / `set` / `shield` | giá đồ cũ cùng bậc | Giá mua ở Thợ Rèn; bậc giá 0 = không bán (đồ khởi đầu) | |
| `prices.piece_weight` | `"def"` | Giá món trong bộ: `"def"` = giá bậc × tỉ lệ thủ của món (mua đủ bộ = giá giáp cũ cùng bậc); hoặc map trọng số từng ô, vd `{"armor": 1, "helm": 0.6, …}` (đủ bộ đắt hơn) | |
| `legacy.weapon` / `armor` / `shield` | đồ cũ theo bậc | Đồ cũ được thay: thôi bán / rơi, nạp nhân vật thì đổi sang đồ mới cùng ô, cùng bậc (thứ tự trong danh sách = bậc), đúng lớp; mượn icon / hình nhân vật của đồ cũ cùng bậc | bỏ một id = giữ đồ đó như cũ |
| `icons` | mũ, quần, găng, giày | Icon tạm cho 4 ô mới (tên file trong `priv/static/assets/icons/`) tới khi có hình gốc | |
| `pieces` | Mũ, Giáp, Quần, Găng, Giày | Chữ đứng trước tên bộ ("Giáp Da") | |
| `no_helm` | `["mg"]` | Lớp không đội mũ (Đấu Sĩ, như MU) | `[]` |
| `weapons.<lớp>` | 7 món / lớp | Danh sách theo bậc: `ref` = `nhóm/số` trong Item.txt, `name` = tên tiếng Việt, `mode` tùy chọn. `"mg": "dk"` = dùng chung danh sách DK | đổi `ref` để đổi món |
| `shields` | 3 món | Khiên dùng chung mọi lớp | |
| `sets.<lớp>` | 6 bộ / lớp | `index` = số thứ tự bộ trong nhóm 7–11 (mũ 7, giáp 8, quần 9, găng 10, giày 11 cùng số), `name` = tên bộ | |
| `sourceType`, `version`, `verified` | `MU_ITEM_TXT`, 1, false | Gắn vào từng món dựng ra (CLAUDE.md §4) | tăng `version` khi đổi bảng |

Tên gốc tiếng Anh của từng món (`mu_name`) được `mix hac_long.items.build` ghi làm bản tiếng Anh (`priv/static/i18n/en.json`).

Ngoài file này, `RULES.loot` (`rules.json`) có:

| Khóa | Mặc định | Ý nghĩa |
|---|---|---|
| `gear_slots` | vũ khí 40 %, bộ giáp 45 %, khiên 15 % | Loại đồ ngẫu nhiên rơi từ quái; `"set"` = một món bất kỳ của bộ giáp (mũ / giáp / quần / găng / giày) |
| `gear_own_class` | `true` | Đồ rơi từ quái hợp lớp người hạ (như trước khi có đồ theo lớp). `false` = rơi đồ mọi lớp (kiểu MU, để giao dịch) |

**Quay lại đồ cũ:** xóa `priv/game_data/items_mu.json` rồi biên dịch lại thì đồ cũ bán / rơi lại như trước. Chỉ làm
khi chưa mở cho người chơi: nhân vật đã đổi sang đồ mới sẽ mất các món đó (không còn định nghĩa).

## 4. Các lựa chọn đã cân nhắc (đổi được)

| Chỗ | Đang chọn | Phương án khác |
|---|---|---|
| Độ mạnh | Đường cong Hắc Long | Nguyên số MU: `weapon_mode: "raw"` cho cả gậy, `set_def` = tổng `Def` thật (DK bộ Da 26 thay vì 2) — cần chỉnh lại máu / công quái |
| Số món | 114 (vũ khí 21, khiên 3, giáp 5 × 18 bộ) | Bớt bậc giáp (vd 4 bộ / lớp) = sửa `sets` + `levels.set` |
| Bộ Đấu Sĩ | Dùng chung bộ DK, không mũ | Bộ riêng MG (Storm Crow…) cấp MU 70+ |
| Bậc 7 giáp | Không có (giáp cũ chỉ tới cấp 22) | Thêm Black Dragon / Ancient / Iris…, thêm `levels.set` 27 |
| Đồ trùm cũ | Thánh Kiếm Diệt Long, Khiên Vảy Rồng, cánh giữ nguyên | Gắn `ref` hình MU cho chúng |

## 5. Các bước

- **M1 (xong 2026-10-10):** chặn git/Docker + CI, `items.fetch`, đường dẫn private, `ItemBuild` + test, `items.build --preview`, tài liệu này.
- **M2 (xong 2026-10-10):**
  - 8 ô (thêm mũ, quần, găng, giày; tháo được, vũ khí / giáp thì thay); thủ = tổng mọi ô phòng thủ.
  - `Engine.can_wear/2`: cấp, lớp (`classes`; cánh vẫn theo `cls`), yêu cầu chỉ số so với **chỉ số gốc đã cộng điểm**
    (không tính điểm cộng từ đồ). Chỉ kiểm lúc mặc: tẩy điểm / chuyển sinh làm thiếu chỉ số thì đồ đang mặc vẫn giữ.
  - Đồ khởi đầu theo lớp (bậc 1 mọi ô trừ khiên); đồ vỡ khi ép → đồ khởi đầu của lớp.
  - Cửa hàng (`Data.shop/0`, hàng Thợ Rèn `Data.stock/1`): bỏ đồ cũ, thêm đồ mới có giá; chỉ hiện / bán đồ đúng lớp.
  - Rơi đồ (`Gear.roll`): bỏ đồ cũ; theo lớp (`gear_own_class`); ô bốc được chưa có đồ hợp cấp thì thử ô khác.
    Rèn "giáp" ở Thợ Rèn ra một món bất kỳ của bộ giáp đúng lớp. Đồ trùm lần đầu đã theo lớp từ trước.
  - **Đổi đồ cũ** (`Engine.migrate_items/1`, mỗi lần nạp nhân vật): đang mặc, túi, đồ hiếm (`gear.base`, giữ `uid`, độ
    hiếm, chỉ số cộng, +N, khóa, Ngọc Sinh Mệnh), cấp nâng đồ thường, Tủ Đồ; ô mới còn trống nhận đồ khởi đầu.
    Đã thử trên 484 nhân vật của database dev: nạp được hết, không còn đồ cũ.
  - Bot (`Brain`) và simulator mặc / mua / ép đủ 7 ô, có kiểm lớp và chỉ số.
  - Giao diện tối thiểu: mở 4 ô, tooltip có "Dùng cho" và "Cần <chỉ số>" (đỏ khi thiếu), cửa hàng chỉ hiện đồ đúng lớp.
  - Cân bằng (simulator 5 ván × 4 lớp × 5 cách chơi, trước → sau): mọi lớp vẫn hạ Hắc Long 5/5 ở cấp 35; số trận lệch
    ≤ 3 %; chết ≤ 1. Vàng cuối game của Kiếm Sĩ thấp hơn (mua / ép nhiều ô hơn).
- **M3 (xong 2026-10-10):**
  - Hình gốc theo `ref` cho 114 món + cánh, Thánh Kiếm, Khiên Vảy Rồng (`ITEM_PICK.refs`: cánh MU cùng tên — Fairy,
    Angel, Satan, Spirit, Soul, Dragon, Darkness; Cánh Hủy Diệt = Wing of Despair; Thánh Kiếm = Sword of Archangel;
    Khiên Vảy Rồng = Dragon Shield). Hình đổi theo +N (mức lớn nhất ≤ cấp nâng); viền sáng +7 / +9 / +11 có từ Đợt 3.
  - Bảng chi tiết có tên gốc (`mu_name`); Thợ Rèn: "Ép đồ" liệt kê đủ 8 ô với hình gốc, "Rèn đồ" ghi rõ bộ giáp.
  - e2e `items.mjs` (11 mục, trong `run.mjs`): đồ khởi đầu theo lớp, 4 ô mới, hình tải được (khi có hình), yêu cầu
    chỉ số (tooltip đỏ, nút khóa, server từ chối), tháo / mặc mũ, Thợ Rèn chỉ bày đồ đúng lớp, mua đồ lớp khác bị từ chối.
  - Chưa làm: hình trên nhân vật (doll) cho cung / gậy — chưa có sprite, đang mượn sprite kiếm / rìu của bậc cũ.

## 6. Phase 15c (2026-10-10): bậc 7–8, nhẫn / dây chuyền, thưởng đủ bộ, Excellent, hình cung / gậy, script

### 6.1 Khóa mới (đổi được)

| Ở đâu | Khóa | Mặc định | Ý nghĩa |
|---|---|---|---|
| `item_pick.json` | `levels.weapon` / `levels.set` thêm phần tử thứ 8 / 7–8 | vũ khí bậc 8 cấp 32; bộ bậc 7 cấp 27, bậc 8 cấp 32 | thêm bậc = thêm phần tử ở mọi mảng theo bậc (`levels`, `stats.staff_atk`, `stats.set_def`, `prices`) và thêm món ở `weapons` / `sets` |
| `item_pick.json` | `stats.set_def` bậc 7–8 | 46, 60 | tổng thủ bộ |
| `item_pick.json` | `jewelry.ring` / `jewelry.pendant` | 6 nhẫn, 5 dây chuyền | `ref`, `name`, `mu_name`, `level`, `price` (giá bán lại), chỉ số cho tay: `hp` (máu tối đa), `def`, `atk`. Không bán ở cửa hàng, chỉ rơi |
| `item_pick.json` | `weapons.*[].doll` | cung / nỏ / gậy | hình trên nhân vật (`priv/static/assets/doll/…`); không ghi thì mượn của đồ cũ cùng bậc |
| `item_pick.json` | `mu_name_fix` | 3 lỗi chính tả | thay chuỗi con trong tên gốc (bản tiếng Anh) |
| `item_pick.json` | `refs` | cánh, Thánh Kiếm, Khiên Vảy Rồng | đồ riêng Hắc Long mượn hình gốc theo `ref` |
| `rules.json` | `loot.gear_slots` | vũ khí 38 %, bộ giáp 43 %, khiên 13 %, `jewelry` 6 % | loại đồ ngẫu nhiên rơi; `jewelry` = nhẫn hoặc dây chuyền |
| `rules.json` | `set_bonus.min_tier` | 2 | bộ dưới bậc này (bộ khởi đầu) không có thưởng |
| `rules.json` | `set_bonus.def_pct` / `atk_pct` / `hp_per_tier` | 0,1 / 0,03 / 15 | thưởng khi mặc đủ bộ (Đấu Sĩ: 4 món vì không mũ): +10 % phòng thủ, +3 % tấn công, +15 máu × bậc bộ |
| `rules.json` | `excellent.chance` | thường 4 %, đêm 8 %, tinh anh 12 %, trùm 20 % | tỉ lệ một món **đã rơi** là Excellent |
| `rules.json` | `excellent.lines` | 1 dòng 70 %, 2 dòng 25 %, 3 dòng 5 % | số dòng |
| `rules.json` | `excellent.options.weapon` | sát thương +5 %, chí mạng +4 %, hạ quái hồi 6 % máu, hồi 10 % MP | dòng cho vũ khí, dây chuyền |
| `rules.json` | `excellent.options.armor` | máu tối đa +4 %, giảm sát thương nhận 3 %, vàng +15 % | dòng cho khiên, bộ giáp, nhẫn |
| `rules.json` | `excellent.max_dmg_red` | 0,2 | trần tổng giảm sát thương từ Excellent |
| `rules.json` | `excellent.price_mult` | 2 | đồ Excellent bán lại gấp đôi |

### 6.2 Cách chạy

- **Ô trang bị:** 11 ô, thêm `ring1`, `ring2`, `pendant`. Món nhẫn có loại `ring` và vào ô nhẫn còn trống (đủ hai thì
  thay `ring1`). Dây chuyền cộng tấn công, nhẫn cộng máu / thủ; ép +N được như đồ khác.
- **Thưởng đủ bộ** (`Engine.set_bonus/1`): xét bộ có nhiều món đang mặc nhất; hiện ở tab Túi đồ ("Bộ Lụa 5/5 ✓ …").
- **Excellent** (`Gear.excellent/2`, `Gear.exc_stats/1`): món đồ hiếm có trường `exc: ["atk_pct", …]`, lưu cùng đồ;
  tên xanh lục, bảng chi tiết liệt kê dòng, hình `_e`. Áp cho đồ rơi từ quái và đồ trùm lần đầu (không áp cho rương,
  rèn, sự kiện). Quản trị tặng được: `give_gear` với `exc`.
- **Hình nhân vật:** cung, nỏ, gậy phép tự vẽ (`scripts/doll_weapons.py`, CC0).
- **Máy chủ:** `sh scripts/setup_items.sh` (clone / cập nhật repo hình, chép Item.txt, import, chép hình, cắt viền).

### 6.3 Cân bằng (simulator 5 ván × 4 lớp × 5 cách chơi)

Cả 4 lớp vẫn hạ Hắc Long 5/5 ở cấp 35; số trận như trước (± 1 %); chết ≤ 1. Simulator chỉ tự mặc dây chuyền rơi được
(không mặc nhẫn), nên người chơi thật mạnh hơn simulator một chút khi gom đủ nhẫn / Excellent.

## 7. Phase 15d (2026-10-10): dòng phụ May mắn / Kỹ năng

Anh chốt 2026-10-10: Kỹ năng = chiêu +10 % sát thương (phương án a); giáp / trang sức May mắn chỉ giúp ép ngọc, không
cộng chí mạng (như MU, tránh chí mạng cộng dồn).

### 7.1 Khóa mới (`rules.json` → `luck_skill`, đổi được)

| Khóa | Mặc định | Ý nghĩa |
|---|---|---|
| `luck_chance` | thường 10 %, đêm 15 %, tinh anh 20 %, trùm 35 % | tỉ lệ một món **đã rơi** có May mắn (mọi loại trừ cánh) |
| `skill_chance` | 15 % | tỉ lệ một **vũ khí** đã rơi có Kỹ năng |
| `luck_crit` | 0,05 | chí mạng cộng thêm khi **vũ khí** đang cầm có May mắn |
| `luck_upgrade` | 0,25 | tỉ lệ ép ngọc +7..+11 cộng thêm khi món có May mắn (bước +6 vốn 100 %) |
| `luck_max_rate` | 0,95 | trần tỉ lệ ép ngọc sau khi cộng May mắn |
| `skill_dmg` | 0,1 | sát thương **chiêu** cộng thêm khi vũ khí có Kỹ năng (đánh thường không cộng) |
| `price_mult` | 1,25 | giá bán lại nhân thêm cho mỗi dòng (có cả hai: × 1,5625) |

### 7.2 Cách chạy

- Món đồ hiếm có trường `luck: true` / `skill: true`, lưu cùng đồ (giữ khi giao dịch, rao chợ, cất Tủ Đồ).
- Rơi: `Gear.luck_skill/2` sau `Gear.excellent/2`, cho đồ rơi từ quái và đồ trùm lần đầu (không cho đồ cửa hàng,
  rèn, rương, sự kiện; đấu trường / trùm thế giới không bốc).
- Chỉ số: `Gear.luck_skill_stats/1` → `Engine.derived` (`crit` cộng `luck_crit`, trường mới `skillDmg`).
- Ép ngọc: `Gear.luck_rate/2` trong `Engine.upgrade_cost/2`, nên Thợ Rèn hiện luôn tỉ lệ đã cộng.
- Tooltip: chữ xanh dương "May mắn (chí mạng +5 %, ép ngọc +25 %)" (vũ khí) / "May mắn (ép ngọc +25 %)" (đồ khác),
  "Kỹ năng (sát thương chiêu +10 %)"; số lấy từ `RULES.luckSkill` (page_controller).
- Quản trị: `give_gear` nhận `luck: true`, `skill: true` (Kỹ năng chỉ vũ khí).

### 7.3 Cân bằng

Simulator 5 ván × 4 lớp × 5 cách chơi: cả 4 lớp vẫn hạ Hắc Long 5/5 ở cấp 35, số trận như trước, chết ≤ 1.

## 8. Phase 15e (2026-10-10): cánh cấp 3 + dòng phụ của cánh

Anh chốt 2026-10-10: làm cả cánh cấp 3 và dòng phụ ngẫu nhiên (phương án c).

### 8.1 Cánh cấp 3 (`items.json`, `chaos.json`, `item_pick.json` → `refs`)

| Lớp | id | Tên | Hình gốc (`ref`) | Tên gốc |
|---|---|---|---|---|
| Kiếm Sĩ | `wing_dk_3` | Cánh Bão Tố | `12/36` | Wing of Storm |
| Phù Thủy | `wing_dw_3` | Cánh Không Gian | `12/37` | Wing of Space Time |
| Tiên Nữ | `wing_elf_3` | Cánh Ảo Ảnh | `12/38` | Wing of Illusion |
| Đấu Sĩ | `wing_mg_3` | Cánh Cuồng Phong | `12/39` | Wings of Hurricane |

- Chỉ số (đổi trong `items.json`): cấp 45, phòng thủ 22, sát thương +25 %, nhận sát thương −25 % (cấp 2: 12 / 18 % / 18 %);
  mỗi cấp nâng vẫn +2 % (`combat.wing_per_level`).
- Công thức `wing3` (đổi trong `chaos.json`): 1 cánh cấp 2 **+9** trở lên + 10 Phúc Lành + 10 Linh Hồn + 3 Hỗn Nguyên +
  3 Sinh Mệnh + 500 000 vàng; tỉ lệ 15 %, +5 % mỗi cấp trên +9, tối đa 50 %. Thất bại mất hết (như cánh cấp 1, 2).
- Hình trên nhân vật: vẽ bằng code (`doll.js`), cấp 3 to nhất, có viền sáng.
- Hình trong túi: hình gốc theo `ref`. Máy chủ chạy lại `scripts/setup_items.sh` (hoặc `mix hac_long.items.fetch
  --icons-from …` rồi `mix hac_long.icons`) để chép thêm 4 hình này.

### 8.2 Dòng phụ của cánh (`rules.json` → `wing_options`)

Ghép **thành công** cánh cấp 2 hoặc 3 ở Máy Hỗn Nguyên thì bốc đều 1 trong 3 dòng (trường `wopt` của món):

| Dòng | Cấp 2 | Cấp 3 | Tác dụng |
|---|---|---|---|
| `hp` | +60 | +120 | máu tối đa |
| `mp` | +40 | +80 | MP tối đa |
| `ignore_def` | 3 % | 5 % | bỏ qua phần phòng thủ của đối thủ khi đánh (quái, đấu trường, đồ sát) |

- Đổi số ở `wing_options.by_tier`; bỏ một bậc khỏi `by_tier` thì cánh bậc đó không có dòng.
- Cánh cấp 2 đã có từ trước (ghép trước Phase 15e) không có dòng; cánh cấp 1 không có dòng.
- Tooltip: "Dòng cánh: Máu tối đa +120"; bảng Nhân vật có dòng "Bỏ qua phòng thủ" khi có.
- Quản trị: `give_item` cánh nhận `wopt` (`hp` / `mp` / `ignore_def`).
- Code: `Gear.wing_option/1` (bốc), `Gear.wing_stats/1` (cộng vào `Engine.derived`: `maxHp`, `maxMp`, `ignoreDef`),
  `Chaos.success/4`.

### 8.3 Cân bằng

Cánh cấp 3 dùng từ cấp 45, sau Hắc Long (cấp 35), cho bản đồ phụ cấp 45–50. Simulator (đánh tới Hắc Long) không ghép
cánh, nên kết quả không đổi.

## 9. Phase 15f (2026-10-10): Máy Hỗn Nguyên pha đồ (mục 4)

Hai công thức mới trong `chaos.json` có `mode` (không có `out`): thành công thì **chính món đồ** bỏ vào được thêm dòng,
giữ nguyên uid, cấp nâng và các dòng cũ; thất bại mất món, nguyên liệu, vàng (như mọi công thức của máy).

| id | Tên | Nhận | Nguyên liệu | Tỉ lệ | Kết quả |
|---|---|---|---|---|---|
| `add_exc` | Pha Excellent | vũ khí, khiên, bộ giáp, nhẫn, dây chuyền **+5** trở lên, chưa đủ 3 dòng | 1 Hỗn Nguyên + 2 Sinh Mệnh + 100 000 vàng | 30 %, +5 %/cấp trên +5, tối đa 60 % | thêm 1 dòng Excellent chưa có (ngẫu nhiên đều) |
| `add_luck` | Pha May mắn | như trên, **+3** trở lên, chưa có May mắn | 1 Hỗn Nguyên + 3 Phúc Lành + 50 000 vàng | 50 %, +5 %/cấp trên +3, tối đa 75 % | thêm May mắn |

- Đổi số trong `chaos.json` (`items`, `gold`, `rate`, `per_up`, `max_rate`, `gear.slots`, `gear.min_up`).
- Code: `Chaos.transform/4`, `Gear.add_exc_line/1`, `Gear.exc_pool/1`. Giao diện máy tự lọc món còn thêm được dòng.
- **Không làm Trái Cây** (cộng điểm vĩnh viễn kiểu MU): cần thêm cột đếm số trái đã ăn vào bảng `characters` (đổi schema)
  — để anh quyết sau (`docs/OPEN_QUESTIONS.md`).

## 10. Phase 15g (2026-10-10): đồ Bộ Thần (mục 6)

Món **bộ giáp** (mũ, giáp, quần, găng, giày) rơi từ quái có xác suất thành **đồ Thần** (trường `anc: true`), tên màu cam.

| Khóa `rules.json` → `ancient` | Mặc định | Ý nghĩa |
|---|---|---|
| `chance` | thường 1 %, đêm 2 %, tinh anh 4 %, trùm 8 % | tỉ lệ một món bộ giáp **đã rơi** là đồ Thần |
| `piece_def_pct` | 0,2 | phòng thủ của món Thần +20 % |
| `bonus` | 2 món: +3 % tấn công; 3 món: +5 % phòng thủ; đủ bộ: +5 % tấn công, +5 % phòng thủ, +150 máu | thưởng theo số món Thần **cùng bộ** đang mặc, cộng dồn các mức đã đạt (`"full"` = đủ bộ, Đấu Sĩ 4 món) |
| `price_mult` | 3 | giá bán lại nhân thêm |

- Cộng dồn với thưởng đủ bộ thường (`set_bonus`): mặc đủ 5 món Thần bộ Đồng có cả hai.
- Áp cho đồ rơi từ quái và đồ trùm lần đầu (không cho cửa hàng, rèn, rương, sự kiện).
- Tooltip: "✦ Đồ Thần: phòng thủ +20 % …"; tab Túi đồ có dòng "Bộ Thần Đồng 3/5 +3 % tấn công, +5 % phòng thủ".
- Quản trị: `give_gear` nhận `anc: true` (chỉ món bộ giáp).
- Code: `Gear.ancient/2`, `Gear.anc_chance/1`, `Engine.ancient_bonus/1` (vào `derived`: `maxHp`, `atk`, `def`).

## 11. Phase 15h (2026-10-10): chợ giữ đủ dòng đồ, lọc / sắp xếp (mục 7)

- **Sửa lỗi:** trước đây rao đồ hiếm lên chợ chỉ lưu `uid / base / độ hiếm / chỉ số cộng / cấp nâng`, nên khi bán / rút về
  món đồ **mất** dòng Ngọc Sinh Mệnh, Excellent, May mắn / Kỹ năng, Bộ Thần, dòng cánh. Nay lưu cả món (trừ cờ khóa / cất tủ)
  và đọc lại qua `Gear.load/1`. Hàng **đã rao trước bản này** vẫn thiếu các dòng đó (không khôi phục được). Giao dịch trực
  tiếp (`Trade`) vốn giữ đủ, không đổi.
- Chợ hiện đủ dòng của món (tên màu theo loại: cam đồ Thần, xanh lục Excellent), thêm **lọc** (Tất cả / Đồ hiếm /
  Excellent / Đồ Thần / May mắn, Kỹ năng / Cánh / Đồ thường, ngọc) và **sắp xếp** (Mới nhất / Rẻ nhất / Đắt nhất) ở tab Mua.
  Lọc chạy ở client (`logic.js` `marketFilter`, có test), không đổi giao thức.
- Phí chợ, số món rao tối đa, giá tối đa vẫn ở `RULES.market` như cũ.
