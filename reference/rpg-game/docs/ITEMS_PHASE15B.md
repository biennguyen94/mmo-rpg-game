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
# hình: đặt PNG vào assets_src/private/item_icons/ (tên item_{nhóm}_{số}.png), rồi:
mix hac_long.icons                  # → priv/static/assets/mu_items/ + item_icons.json
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

**Đổi nguồn:** `mix hac_long.items.fetch --url <URL>` hoặc biến `HL_ITEM_TXT_URL`. Hình chép tay (lệnh tải tự
động thư mục hình bị chặn trong môi trường của em; trên máy anh có thể `git clone --sparse` repo rồi chép `public/items`).

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
- **M3:** hình gốc theo `ref` (chờ anh cấp quyền tải / đặt hình), icon riêng cho găng / quần / giày, viền sáng
  +7 / +9 / +11 bằng CSS, hình nhân vật cho cung / gậy, tên gốc trong tooltip, e2e riêng cho đồ theo lớp.
