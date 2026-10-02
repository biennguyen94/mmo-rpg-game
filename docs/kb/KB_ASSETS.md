# KB_ASSETS — Asset 2D, nguồn, định dạng

## 1. Nguyên tắc pháp lý

- **Không dùng asset trích từ client MU gốc** cho bản public/kiếm tiền (bản quyền Webzen). Chỉ cho prototype riêng tư nếu bạn chấp nhận rủi ro.
- Chỉ dùng asset có license rõ ràng; ghi vào `CREDITS.md` (tên, tác giả, license, URL) cho **mọi** asset.
- Nếu public: đổi tên/thiết kế item, monster, class để không trùng IP MU.
- Kiểm tra license từng gói: CC0 (không cần credit), CC-BY (phải credit), CC-BY-SA/GPL (ràng buộc share-alike, đọc kỹ trước khi dùng).

## 2. Nguồn gợi ý

| Loại | Nguồn | License (kiểm tra lại) |
|---|---|---|
| Monster, tile dungeon/map | Dungeon Crawl Stone Soup tiles (repo mẫu dùng) | CC0 |
| Icon item/skill | game-icons.net (repo mẫu dùng) | CC BY 3.0 (cần credit) |
| Tile, UI, icon, SFX | Kenney.nl | CC0 |
| Đa dạng | OpenGameArt.org, itch.io | Tuỳ gói |
| Nhân vật nhiều lớp trang bị | Liberated Pixel Cup / LPC generator | Tuỳ asset (CC-BY-SA/GPL): đọc kỹ |
| SFX | freesound.org, Kenney audio | Tuỳ file |
| Nhạc | OpenGameArt, Incompetech, hoặc tự tổng hợp Web Audio như repo mẫu | Tuỳ |
| Tự làm | Aseprite (sprite), Tiled (map) | — |

### 2.1. Nguồn theo nhóm asset (chốt cho dự án)

> Bảng trên là gợi ý chung. Bảng này **ưu tiên hơn** khi có mâu thuẫn.

| Nhóm | Nguồn |
|---|---|
| Trang bị nhân vật (layer: mũ, giáp, vũ khí, khiên, cánh, …) | **Do dự án cung cấp** (source images). Định dạng: xem A4 |
| Item icon | **Do dự án cung cấp**, đặt tên `item_{group}_{index}[_{bucket}][_e].png`, tra qua `icon_map.json` (`KB_ITEM_REFERENCE §2, §4`). **Coi là asset MU-derived (§2.2): để ngoài git**, chỉ ở máy dev. Vị trí chính xác: §2.2 |
| Map tile, monster, NPC | **DCSS tiles** — repo `crawl/tiles`; nếu không có độc lập thì thư mục `crawl-ref/source/rltiles` của repo `crawl/crawl` |
| UI, effect | Do dự án cung cấp, hoặc CC0 (Kenney) |
| Audio | Do dự án cung cấp, hoặc CC0. **Không** lấy từ DCSS tiles (repo chỉ có tile) |

**Agent được tự quyết với asset DCSS:**
- Chọn tile/sprite gần nhất với terrain, monster, NPC trong `data/`.
- Scale chỉ theo bội số nguyên (×1, ×2). Không scale lẻ.
- Thiếu tile phù hợp: dùng placeholder (ô màu hoặc tile mặc định), ghi log cảnh báo, **không crash**.
- Ghi mỗi lựa chọn vào `priv/static/assets/mapping.json` (id trong `data/` → file gốc trong repo) để developer kiểm tra và thay thế.

**Agent phải làm:** đọc file license trong repo và chỉ dùng tile xác nhận được là CC0 (không dựa vào wiki hay nguồn thứ cấp); tile khác license thì bỏ qua; ghi `CREDITS.md` ngay khi thêm asset.

**Agent KHÔNG được:**
- Đổi tile size mặc định 32×32.
- Dùng asset DCSS cho trang bị nhân vật hoặc item icon.
- Trộn tile khác style/palette vào cùng một map mà chưa kiểm tra (xem §3 Palette).

### 2.2. Asset MU-derived (icon item, layer trang bị, mọi thứ lấy từ client MU) — ngoài git

> Mặc định pháp lý theo §1: chưa xác nhận nguồn/license (A5) thì coi là **chỉ dùng riêng tư, không commit, không đưa lên repo công khai hay image Docker/production**.

| Loại | Vị trí | Git | Ai tạo |
|---|---|---|---|
| **Input** icon item gốc (phẳng, không thư mục con, tên nguyên bản `item_{g}_{i}…png`) | `assets_src/private/item_icons/` | **gitignore** | Developer đặt tay |
| **Input** layer trang bị nhân vật (khi có, A4) | `assets_src/private/equip_layers/` | **gitignore** | Developer |
| **Output** icon đã chép để client phục vụ | `priv/static/assets/icons/items/` | **gitignore** | `mix mu.icons.index` |
| **Output** bảng tra | `priv/static/assets/icon_map.json` | **gitignore** (sinh lại khi build) | `mix mu.icons.index` |
| Icon do dự án tự làm (vd `ring_hp_t0`) | `priv/static/assets/icons/custom/{templateId}.png` | **commit** | Dự án |
| Silhouette slot trống, placeholder | `priv/static/assets/icons/ui/`, `priv/static/assets/icons/placeholder.png` | **commit** | Dự án |

Lý do tách: `assets_src/private/` là nguồn gốc không nên lộ; `priv/static/assets/icons/items/` là bản sao sinh tự động nên bỏ qua git để lỡ có commit nhầm thì chỉ là output. Tách hai thư mục `items/` (MU) và `custom/` (dự án) để chỉ ignore đúng phần MU.

`.gitignore` và `.dockerignore` (agent thêm ở M1):

```
assets_src/private/
priv/static/assets/icons/items/
priv/static/assets/icon_map.json
```

**Quy tắc cho agent:**
- Không bao giờ `git add` hoặc `COPY` các đường dẫn trên; CI kiểm tra không có file nào dưới các đường dẫn này nằm trong git (`git ls-files` rỗng).
- `mix mu.icons.index` chạy **được khi thư mục input rỗng hoặc không tồn tại**: sinh `icon_map.json` trỏ toàn bộ sang `placeholder.png`, in cảnh báo, **exit 0**.
- Script ghi `docs/ICON_REPORT.md` (gitignored hoặc commit tùy; không chứa ảnh): số file, phân bố kích thước pixel (giúp trả lời A6), danh sách icon Phase 1 còn thiếu, file có tên không parse được.
- Production/Docker: không chứa các thư mục trên trừ khi developer quyết định (A2); khi đó client hiển thị placeholder.
- Nếu dung lượng input lớn (hàng trăm MB), để ở repo riêng **private** (hoặc Git LFS) và đặt đường dẫn bằng biến môi trường `ITEM_ICONS_DIR` (mặc định `assets_src/private/item_icons`).

**10 icon Phase 1 cần có trong input** (một trong hai dạng tên; script tự thử cả hai, xem `KB_ITEM_REFERENCE §4.3`):

| templateId | Tên file input |
|---|---|
| `sword_t0` | `item_0_1_0.png` hoặc `item_0_1.png` |
| `shield_t0` | `item_6_0_0.png` / `item_6_0.png` |
| `helm_t0` | `item_7_5_0.png` / `item_7_5.png` |
| `armor_t0` | `item_8_5_0.png` / `item_8_5.png` |
| `pants_t0` | `item_9_5_0.png` / `item_9_5.png` |
| `gloves_t0` | `item_10_5_0.png` / `item_10_5.png` |
| `boots_t0` | `item_11_5_0.png` / `item_11_5.png` |
| `hp_potion_small` | `item_14_1_0.png` / `item_14_1.png` |
| `mp_potion_small` | `item_14_4_0.png` / `item_14_4.png` |
| `ring_hp_t0` | **Không từ MU**: dự án tự làm → `icons/custom/ring_hp_t0.png` (commit), chưa có thì placeholder |

## 3. Quyết định kỹ thuật (đề xuất)

| Mục | Giá trị |
|---|---|
| Góc nhìn | Top-down 3/4 (như DCSS) cho Phase 1; isometric để sau nếu cần |
| Tile size | 32×32 px |
| Sprite nhân vật | 32×48 hoặc 48×48, 4 hướng (có thể 8 sau) |
| Item icon | 32×32 (tooltip lớn 64×64) |
| Format | PNG (sprite sheet / atlas) + JSON atlas (Phaser/TexturePacker) |
| Palette | Thống nhất 1 bộ; tránh trộn nhiều style pixel khác nhau |
| Audio | `.ogg` (+ `.mp3` fallback), nhạc loop, SFX < 100 KB |

## 4. Nhân vật & trang bị

- Nguồn: source images do dự án cung cấp (xem §2.1). Định dạng chi tiết chưa chốt (A4).
- **Layered sprite**: body + hair + armor + weapon + shield (+ pet) vẽ chồng theo `look` từ server (repo mẫu cũng trả `view.look`). Mỗi layer cùng khung/anchor.
- Animation: `idle (2–4f)`, `walk (4–6f)`, `attack (4f)`, `skill (4–6f)`, `hit (1–2f)`, `die (4f)`.
- Quy ước anchor: chân nhân vật ở giữa-dưới ô.

## 5. Quy ước đặt tên & thư mục

```
priv/static/assets/
├── sprites/
│   ├── characters/{class}/{layer}_{anim}_{dir}.png
│   ├── monsters/{monster_id}.png            (atlas: idle/walk/attack/die)
│   └── npcs/{npc_id}.png
├── tiles/{map_id}_tileset.png
├── icons/
│   ├── items/ (MU-derived, gitignore, sinh bởi mix mu.icons.index — §2.2)
│   ├── custom/{templateId}.png (item tự tạo, commit)
│   ├── skills/{id}.png   └── ui/ (silhouette…)
├── icon_map.json         (sinh, gitignore)
├── effects/{skill_id}.png
├── ui/ (frames, bars, buttons, cursors)
└── audio/{bgm,sfx}/
```

ID asset **trùng ID trong `data/`** (`spider.png` ↔ monster `spider`). Thiếu asset → fallback placeholder, không crash.
**Ngoại lệ — icon item:** file theo `item_{group}_{index}…` (không theo `templateId`); template trỏ tới icon bằng `iconRef`, tra qua `icon_map.json` do script sinh. Item tự tạo: `icons/custom/{templateId}.png`.

## 6. Danh sách tối thiểu cho Phase 1

> Scope Phase 1 chốt tại `KB_00_RULES §7`: **1 class (DK), 1 map (Lorencia), 1 monster (Spider), 1 NPC shop**.

### 6.1. Bắt buộc (Phase 1)

| Nhóm | Số lượng | Ghi chú |
|---|---|---|
| Nhân vật DK | 1 class, anim đủ 6 loại (idle, walk, attack, skill, hit, die) × 4 hướng | 1 bộ armor + 1 vũ khí (sword) + 1 shield |
| Monster — Spider | 1 | idle/walk/attack/die |
| NPC | 1: `lorencia_potion_merchant` | idle 2-4 frame + icon minimap |
| Item icon | 10 | hp_potion_small, mp_potion_small, sword_t0, shield_t0, helm_t0, armor_t0, pants_t0, gloves_t0, boots_t0, ring_hp_t0 |
| Tileset Lorencia | 1 map | cỏ, đường, nước, tường/nhà, cây, đá, safe-zone marker |
| Effect | 4 | hit spark, level-up, heal, twisting_slash |
| UI | 1 bộ | HP/MP/EXP bar, dock 4 tab, panel (Character, Inventory, Thông báo, Shop), context menu quái, nút mobile (HP/MP/Nhặt), tooltip, cursor |
| Audio | 1 BGM + 5 SFX | BGM Lorencia; SFX: hit, miss, pickup, level up, click |

Icon item vẽ 32×32, hiển thị ×1 ở cả equipment lẫn túi; tooltip 64×64 (×2). Cần thêm 10 icon mờ (silhouette) 32×32 cho slot trống.
Phase 1 chưa có cường hóa nên chỉ cần biến thể +0 (bucket 0 hoặc không bucket). Biến thể `_e` cần từ khi drop có Excellent; bucket 3–9 cần từ Phase 5 (`KB_ITEM_REFERENCE §4.2`).

### 6.2. Nice-to-have (không block Phase 1)

- Monster phụ: Bull Fighter, Hound (tên đổi nếu public)
- NPC phụ: weapon merchant, safe-zone guard
- Item icon mở rộng: Zen, 1 jewel

## 7. Mức Phase 2 trở đi (ước lượng)

DW + Elf (layers + vũ khí staff/bow), 6–10 monster mỗi map mới, tileset Noria/Devias/Dungeon…, 60–100 item icon, party/guild UI, effect skill từng class, thêm BGM theo map.

## 8. Pipeline

1. Vẽ/chọn asset → `assets_src/` (Aseprite, Tiled). Asset MU-derived chỉ vào `assets_src/private/` (§2.2).
2. Xuất PNG + pack atlas (TexturePacker hoặc free-tex-packer) → `priv/static/assets/`.
3. Map: Tiled `.tmj` → script convert sang `maps/<id>.json` + collision (test kiểm portal/spawn như repo mẫu).
4. Cập nhật `CREDITS.md` ngay khi thêm asset.
5. Preload theo map (không tải hết lúc đầu); nén PNG (pngquant), bật cache header.

## 9. Open questions

| # | Câu hỏi |
|---|---|
| A1 | Tự vẽ, dùng asset free, hay thuê artist? |
| A2 | Có public/kiếm tiền không? (quyết định mức độ phải đổi IP) |
| A3 | Style: pixel art 32px như DCSS hay hand-drawn? |
| A5 | Icon item / layer trang bị do ai làm? Có trích từ client MU không? (quyết định được public hay không, xem §1). **Tạm coi là MU-derived → §2.2** |
| A6 | Kích thước pixel của icon item thật? Có tỉ lệ khác nhau theo kích thước ô túi gốc (`cells` = `X×Y` trong Item.txt, vd kiếm 1×3, giáp 2×2) không? |
| A4 | Source images trang bị nhân vật: ảnh rời hay sprite sheet? Cỡ frame, số hướng, số frame mỗi animation, anchor? (cần chốt trước khi code phần nhân vật) |
