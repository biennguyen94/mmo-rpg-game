# CHANGELOG (không thuộc KB — AI Agent không cần đọc)

## v3 (so với v2)

**Cấu trúc**
- Tách thành 5 file: RULES, REFERENCE, GAME_DESIGN, CONFIG, TECHNICAL. Changelog tách riêng.
- Một thứ tự ưu tiên duy nhất (trước đây §0.2 và §36 mâu thuẫn).
- Một bảng phase duy nhất, có ràng buộc phụ thuộc (Party/Warehouse/Trading không còn trùng).
- Mọi bản ghi có `sourceType`, `version`, `verified`, `source`.

**Scope**
- MG: chuyển thành IMPLEMENTATION (không khẳng định thuộc 0.97d). maxLevel 400 = CONFIG.
- Wings/Harmony/Guardian: `LATER_VERSION`, tắt bằng feature flag. Bỏ `Wings of Elf lv180` khỏi REFERENCE.
- Lost Tower: đánh dấu mâu thuẫn 7/8 tầng thay vì khẳng định 8. Level map (trừ Tarkan) ghi rõ là xấp xỉ.

**Công thức**
- Damage: thống nhất thứ tự pipeline và code; thêm `minDamageRatio` để defense cao không biến mọi đòn thành 1.
- Hit chance: đánh dấu IMPLEMENTATION, thêm clamp min/max.
- Attack speed: công thức `base / (1 + speed/100)` kèm bảng ví dụ.
- Tick: simulation 20 Hz, AI 10 Hz, snapshot 10 Hz, kèm interpolation.

**Bổ sung**
- Drop system, death/respawn/EXP loss, pathfinding, AOI, session/reconnect, versioning client, naming rules, economy sink/source, guild.
- DB: `free_stat_points`, `character_skills`, `excellent_options JSONB`, tách `character_items`/`warehouse_items` (có FK + unique slot), `item_audit_log`, optimistic locking, serial ULID do server sinh, class CHECK.

**Còn mở** (xem KB_00_RULES §6): Q1–Q5. Chưa có số liệu HP/Mana growth, EXP table, level từng map, drop table thật cho 0.97d.

## v3.1 (so với v3)

- KB_GAME_DESIGN: thêm §4.1 per-class stat mapping (IMPLEMENTATION) cho DK/DW/ELF/MG.
- KB_CONFIG: `experience.formulaSemantics`; §2 thêm HP/Mana growth; §5 đủ upgrade +0→+9 (Q6); thêm §6 equipment slot mapping.
- KB_TECHNICAL: banner override ở §1; bỏ Redis ở §2 và §10.
- KB_TECH_STACK: banner nêu rõ phạm vi override.
- KB_00_RULES: §7 là nguồn duy nhất cho scope Phase 1 (JSON chi tiết + acceptance); thêm Q6.
- KB_ASSETS: §6 đồng bộ scope Phase 1 (1 monster, 1 NPC, 10 item icon).
- KB_TECHNICAL: §1 vẽ lại theo Phoenix/OTP; §5 là protocol duy nhất (`cmd` + chat + error codes); §8 pipeline Tiled duy nhất; §9 thêm `items.quantity` (serial theo stack), gộp thành `item_locations` (PK item_id, CHECK owner/slot, partial unique index), CHECK tên ASCII, quy tắc ground/trade/orphan; §10 trade cross-account (TradeSettlement, lock theo item_id).
- KB_TECH_STACK §5 chỉ tham chiếu KB_TECHNICAL §5. KB_CONFIG §6 thêm WAREHOUSE (placeholder). KB_GAME_DESIGN §8 thêm `quantity`.
- Lượt review v3.1: Phase 1 acceptance tách persistence/broadcast đơn giản khỏi reconnect/AOI (Phase 3); min damage còn 2 lớp (`minDamageRatio` + `hardFloor`); flow auth bỏ JWT (token opaque hash trong DB → WS ticket trong ETS); trade state nằm ở `TradeSettlement`; `clientVersion` trong join payload; bỏ `character_skills` ở Phase 1 (skill tự học theo level); error event `{rid, error}`; ghi chú audit log không FK; bỏ trùng KB_ASSETS 6.3/7.
- KB_GAME_DESIGN: thêm §19 UI túi đồ & trang bị (Phase 1). KB_TECHNICAL §5: thêm act `unequip`, `move_item`, `split`, `drop`, `npc_open`, `buy`, `sell`, event `shop`, error `NOT_ENOUGH_ZEN`.
- KB_GAME_DESIGN §19 viết lại: panel xếp ngang, equipment nằm trong Inventory (5+5), Character có derived stats, Q/W = HP/MP potion tự gán, min 1280px. KB_CONFIG: thêm `combat.potionCooldownMs`.
- KB_GAME_DESIGN §19.4: equipment silhouette 5×4 (10 slot, đối xứng trái/phải), giữ lưới túi 8×8 có icon; §19.5 thêm cách click-chọn rồi click-đích.
- KB_GAME_DESIGN §19 (v3.2 review): panel đặt vị trí cố định theo loại; equipment 3×4 đối xứng; split = ceil(n/2); định nghĩa drop/sell; debounce alloc; min width <1280 hiện thông báo; Shop tự mở Inventory + đóng Character; Q/W tính tổng mọi stack. KB_TECHNICAL §9: `potionType`, `effect`. KB_ASSETS §6.1: icon 64×64 + 10 icon silhouette. (Min width đã đổi 1024→1280 ở lượt trước.)
- KB_ASSETS: thêm §2.1 nguồn theo nhóm asset (trang bị nhân vật + item icon do dự án cung cấp; map/monster/NPC từ DCSS tiles) và quy tắc agent được/không được; thêm A4; icon item về 32×32 ×1 (KB_GAME_DESIGN §19.4 khung slot 40px/36px, panel ~540px).
- KB_GAME_DESIGN §19 viết lại theo hướng panel full-screen (một panel tại một thời điểm), dock 5 tab, hỗ trợ desktop + mobile, context menu khi click quái (bỏ skill bar và hotkey 1–6), thêm panel Hộp thư/Thông báo/Map/Menu. Thay thế bản panel xếp ngang trước đó.
- Chốt phạm vi UI Phase 1: Hộp thư và panel Map dời sang Phase 2 (dock 4 tab); Inventory desktop 2 cột, mobile cuộn dọc; Shop chỉ hiện lưới túi; thêm hành vi tự đánh liên tục khi chọn "Tấn công thường"; sửa mâu thuẫn icon 📬 và legend minimap. Cập nhật KB_00_RULES §7 (features `mail`, `mapPanel` = false, thêm acceptance UI, Phase 2 thêm Hộp thư/Map), KB_ASSETS §6.1 (UI), KB_TECH_STACK §6 (mobile).
- KB_GAME_DESIGN §19.4 viết lại: túi đồ dạng danh sách trang bị + nút [Trang bị] (bỏ lưới 8×8 và kéo thả ở Phase 1), thêm [Tháo] ở slot đang mặc, [Bán] trong Shop. Cập nhật §19.5–19.7, KB_CONFIG §6, KB_TECHNICAL §5 (ghi chú).
- KB_GAME_DESIGN §19.4: desktop chia 2 cột (equipment | danh sách), thêm thanh dưới cố định (Zen, Túi n/64, số potion Q/W, gợi ý chung "NPC bán hàng"); Top HUD desktop hiện số potion cạnh thanh HP/MP; §19.6 cập nhật.
- Thêm KB_BASE_REPO.md: repo nền Hắc Long RPG (biennguyen94/rpg-game) — bảng REUSE/ADAPT/REWRITE/SKIP theo module và phase, quy tắc cho AI, điều kiện license. Liên kết từ KB_00_RULES và KB_TECH_STACK.

## v3.3 (review bộ KB v3.1 + mapping Item.txt → icon)

**Mới:** `KB_ITEM_REFERENCE.md` — viết lại từ bản nháp mapping Item.txt. Sửa các lỗi của bản nháp:
- Bucket icon dùng `ItemLvl` của Item.txt (level gốc của loại item) → sửa thành **level cường hóa của instance**; bỏ ví dụ Wings lvl 100 → bucket 15.
- Quy tắc tên file mâu thuẫn với ví dụ (`item_0_1.png` hay `item_0_1_0.png` cho +0) → chuỗi fallback hai dạng, resolve lúc build vào `icon_map.json`, không dò file lúc runtime.
- Dấu gạch dưới bị markdown nuốt trong mẫu `item_{group}_{index}_{variant}`.
- Index giả `13/100` cho Ring HP → namespace `custom/{templateId}`.
- `stackable` suy từ group → đặt theo từng template; `potionType`/`effect` ghi tường minh, không suy từ tên/`Valor`.
- "chia 5" cho Speed → `items.speedScale` (mặc định 1.0). Với thang cooldown 0–300 của `KB_GAME_DESIGN §6`, speed 4 chỉ giảm ~4% cooldown.
- Cờ class có thể là bậc tiến hóa → dùng khi giá trị == 1 (chờ Q8).
- `X`,`Y` nhiều khả năng là kích thước ô túi, không phải pixel icon (Q11/A6).
- Bỏ câu "~10% dữ liệu cần cho MMO" (không có căn cứ).
- Thêm cảnh báo pháp lý/version (Season 6+, `s6+`), quy tắc `reference.adjusted` → `IMPLEMENTATION`, test bắt buộc, task Elixir.

**Cân bằng Phase 1 (số liệu tính được):**
- DK lvl 1 có `defense = 5`, Spider 3–6 chỉ gây 1 sát thương → potion vô nghĩa. Spider đổi thành 8–14.
- EXP `100 × level^2.2`: tới level 10 cần ~4.189 Spider, level 30 cần ~165.000 EXP chỉ bước 29→30. Đổi exponent 1.5 (~1.110 Spider tới level 10); `maxLevel` Phase 1 = 10.

**Đồng bộ chéo:**
- `KB_00_RULES`: thêm S9 (D1 = real-time lưới), S10, Q7–Q13; acceptance thêm icon item; `maxLevel` Phase 1 = 10.
- `KB_CONFIG`: `features` đủ key (`party`, `quest`, `mail`, `mapPanel`), thêm `items`, `account.maxCharacters`.
- `KB_GAME_DESIGN`: §4 đổi tên biến `floor` → `softFloor`; sửa quy tắc làm tròn (mâu thuẫn "floor sau mỗi bước"); §8 thêm quy tắc template/icon; §10 ví dụ drop khớp `sword_t0` và zen Spider; §19 ghi chú số trong hình chỉ là minh họa (lệch §4.1); §19.4 icon theo `icon_map.json`.
- `KB_ASSETS`: icon item theo `iconRef` (ngoại lệ quy tắc "ID asset = ID data"), A5, A6, ghi chú biến thể Phase 1.
- `KB_TECHNICAL`: sửa lỗi `- -`; `accounts.username` unique không phân biệt hoa thường; index `item_audit_log`; không log query string của WS ticket, ETS theo node; §11 trỏ về `KB_TECH_STACK §7`.
- `KB_TECH_STACK`: D1 đã chốt A; thêm mix task và `priv/reference/`.
- `KB_BASE_REPO`: sửa byte hỏng ("Mục"). B4 (`CREDITS.md`) vẫn chưa đọc được.

**Còn mở:** Q1–Q13, A1–A6, B1–B4. `KB_REFERENCE.md` không nằm trong lần upload này nên chưa được rà soát; bản trong thư mục là bản cũ.

## v3.4 (đã có `Item.txt` thật)

- **Sinh dữ liệu:** `priv/reference/items_raw.json` (group 0–11, 13, 14; 394 item; bỏ group 12 và 15) và `data/items/phase1.json` (10 template Phase 1), đều sinh bằng script từ `Item.txt`.
- **Điền các template còn TBD:** shield = Small Shield (6/0), helm/armor/pants/gloves/boots = bộ Bronze (7–11/0). DK level 1 equip được cả 10 món (đã kiểm tra).
- **Sửa theo dữ liệu thật:**
  - Version: `Item.txt` có `//Season5` và Seed → `s5+`, thay cho `s6+` (đoán sai ở v3.3).
  - `X`,`Y` = kích thước ô túi (Short Sword 1×3, giáp 2×2): xác nhận, lưu thành `cells`.
  - Cờ class có giá trị 0/1/2/3 (không phải boolean): ủng hộ giả thuyết bậc tiến hóa (Q8). Short Sword dùng được cho cả 4 class (bản nháp ghi `["DK","MG"]` không có căn cứ). MG = 0 ở cả 47 helm: khớp rule "MG không đội mũ".
  - `Valor`: nhiều khả năng là *value* (comment viết tiếng Tây Ban Nha); vẫn không dùng.
  - `DefRate` mang nghĩa khác nhau ở shield/gloves/boots, chưa rõ (Q15); không dùng trong combat.
  - `requirementScale` mặc định 0.35 (Bronze 80 → 28 = STR khởi điểm DK), dùng lúc import.
- **Parser:** phải chịu được dòng thụt lề bằng khoảng trắng (dòng 700–708) và 1 dòng group 13 thiếu cột (dòng 611) → §1.3 của `KB_ITEM_REFERENCE`.
- **Cân bằng (Q14):** bộ Bronze + Small Shield có tổng Def 42 → Spider (8–14) chỉ còn gây 1 sát thương khi DK mặc đủ. Ghi nhận, chưa sửa.
- `KB_CONFIG §4`: thêm drop table Spider (6% trang bị, 15% potion). `KB_00_RULES`: S10 → `s5+`, thêm Q14, Q15, cập nhật Q8, Q9, Q12.

## v3.4 (sau khi có Item.txt)

**Dữ liệu thật:** parse `Item.txt` (663 item). Raw chuẩn: `priv_reference/items_raw.json` (552 item, bỏ group 12/15); `scripts/parse_items.py` là parse độc lập đủ 16 group, kiểm chéo khớp 552/552 về tên và số liệu. `data/items/phase1.json` (10 template).
- `KB_ITEM_REFERENCE` viết lại theo dữ liệu: version `s5+` (không phải s6+); cột sau tên **không cố định vị trí** (padding tab thay đổi, 1 dòng dùng dấu cách); header khác nhau theo group (shield/giáp không có Speed/MagicDur/MagicPwr).
- Trả lời Q8: cờ class = **bậc tiến hóa tối thiểu** (DK có 213 mục =1, 30 mục =2). Q9 = Season 5+. `X`,`Y` = **kích thước ô túi** (Kris 1×2, Light Saber 2×4).
- `RequiredLvl` gần như luôn 0 (vũ khí 0/124): yêu cầu thật nằm ở Str/Agi/Ene/Vit. `ItemSlot` MU và số item theo group đã ghi lại; Zen là item 14/15 nhưng KB giữ là số dư.
- Bản nháp sai chỗ: Short Sword không chỉ DK/MG (cả DW/Elf cũng được); Bronze Helm đổi sang Leather Helm (tier thấp nhất, AGI 0); `items.speedScale` mặc định 1.0.
- **`requirementScale` đổi 1.0 → 0.35**: mọi giáp DK cần STR ≥ 80, DK level 1 có STR 28. Với 1.0 hoặc 0.5 chỉ equip được 1/8 slot; 0.35 → 8/8. Scale áp **lúc import** (khớp `KB_CONFIG §1`): template lưu `requirements` đã scale, `reference.requirementsRaw` giữ gốc, bản ghi là `IMPLEMENTATION`.
- **Cảnh báo cân bằng:** chỉ Leather Armor (Def 10 + 5 gốc = 15) là Spider (tối đa 14) chỉ còn gây 1 sát thương, potion mất tác dụng. Chưa đổi số; cần simulator. Acceptance "dùng potion" phải test trước khi mặc áo.
- Đồng bộ: `KB_00_RULES` (S10, Q8/Q9/Q11/Q12), `KB_CONFIG` (`requirementScale`), `KB_GAME_DESIGN §8`, `KB_ASSETS` A6, `KB_TECH_STACK §7`.

**Còn mở:** Q7 (`Valor`), Q11/A5/A6 (nguồn + kích thước icon thật), Q12 (chờ xác nhận 0.35), mọi Q1–Q6, B1–B4. Chưa có icon thật nên `icon_map.json` chưa sinh được.

## v3.5

- `KB_BASE_REPO §0` viết lại: chủ repo xác nhận **toàn quyền dùng lại code** (B1 đóng). Tách rõ code của chủ repo (tự do) với asset/thư viện bên thứ ba (vẫn theo license: DCSS CC0, game-icons.net CC BY 3.0 phải ghi tên). §1 quy tắc 3–4 và §3.4 cập nhật; `REUSE_LOG` chỉ để theo dõi nguồn gốc, không còn là thủ tục xin phép. Vẫn bắt buộc đọc source/test trước khi chọn REUSE/ADAPT/REWRITE (B3).
- Đã đọc lại README của repo (51 commit, không có `LICENSE`); thêm B5 (người đóng góp khác), B6 (nên thêm `LICENSE`). B4 (`CREDITS.md`) vẫn lỗi 503.

## v3.6

- Vị trí icon item (MU-derived): input `assets_src/private/item_icons/` (hoặc `ITEM_ICONS_DIR`), output sinh `priv/static/assets/icons/items/` + `icon_map.json`, **cả ba gitignore/dockerignore**; icon tự làm ở `icons/custom/`, placeholder/silhouette ở `icons/ui/` (commit). Thêm `KB_ASSETS §2.2`, S11, bảng 10 icon Phase 1 với tên file input, `docs/ICON_REPORT.md` (đo kích thước thật → trả lời A6). `icon_map.json` dùng đường dẫn tương đối; script chạy được khi thiếu input.
- Đồng bộ: `KB_ITEM_REFERENCE §4.1/4.4`, `KB_TECH_STACK §7`, `CLAUDE.md` quy tắc 7, `PROMPT_PHASE1` (quyết định + checklist).
