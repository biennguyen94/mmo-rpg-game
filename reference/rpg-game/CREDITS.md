# Credits

## Hình quái vật, nhân vật, nền và ô bản đồ (`priv/static/assets/monsters/`, `floors/`, `tiles/`, `npcs/`, `nodes/`)

Lấy từ bộ tile của **Dungeon Crawl Stone Soup**, đóng gói tại
https://github.com/crawl/tiles (bản `releases/Nov-2015`).

Giấy phép: **CC0 1.0** (public domain). Không bắt buộc ghi tên, nhưng chúng tôi vẫn cảm ơn
các họa sĩ của Dungeon Crawl Stone Soup và dự án RLTiles.
Danh sách họa sĩ: https://github.com/crawl/tiles/blob/master/ARTISTS.md

Ba hình quái xâm lăng (B-20) là hình trên tô lại màu bằng `e2e/tint_sprites.mjs` (vẫn CC0): `red_dragon.png` (từ
`golden_dragon`), `white_wizard.png` (từ `ancient_lich`), `orc_soldier.png` (từ `orc_warrior`). `nodes/ore_rare.png` (Quặng Mithril) cũng tô lại từ `nodes/ore.png` cùng script. `tiles/blessing.png` (Đài Phúc Lành) tô lại từ `tiles/waystone.png`. 40 hình quái vùng đất chuyển sinh `monsters/r1_…` → `r10_…` (Phase 6) tô lại từ các hình quái CC0 ở trên, danh sách ở `priv/game_data/realms.json` (`REALM_TINTS`).

Icon ứng dụng (`priv/static/app/`, `priv/static/favicon.ico`): hình trùm Hắc Long `monsters/shadow_dragon.png` (CC0, bộ trên) phóng to trên nền vẽ bằng `e2e/app_icons.mjs`.

Phase 15a (bản đồ phụ): thêm 52 hình quái từ cùng bộ tile (`mon/animals`, `mon/amorphous`, `mon/aquatic`,
`mon/undead`, `mon/fungi_plants`, `mon/nonliving`, `mon/dragons`, `mon/demons` và vài hình ở `mon/`), chép bằng
`scripts/side_monsters.py`; danh sách trong `priv/game_data/side.json`. Không dùng hình nào trong
`TILES_UNDER_UNKNOWN_LICENSE.md` của bộ tile.

## Bộ hình đồ "Pixel" (`priv/static/assets/pixel/`, Phase 7)

Cũng từ bộ tile Dungeon Crawl Stone Soup ở trên (CC0, `releases/Nov-2015`): vũ khí (`item/weapon`, `item/weapon/ranged`),
gậy / quyền trượng / sách (`item/staff`, `item/rod`, `item/book`), khiên, mũ, giáp, găng, giày (`item/armour`), nhẫn và dây
chuyền (`item/ring`, `item/amulet`), bình (`item/potion`), vé / bản đồ (`item/scroll`), ngọc (`item/misc/runes`), đồ vật
(`item/misc`).
Hình quần: **CC0 Leggings Icons** của AntumDeluge (https://opengameart.org/content/cc0-leggings-icons, giấy phép
**CC0**), gom từ bộ hình Flare (https://opengameart.org/node/12815, /node/13879, /node/12818) và các bộ
https://opengameart.org/node/108781, /node/108295, /node/108448; bản 32×32 để ở `assets_src/pixel_extra/leggings/`
(nguồn từng file trong `SOURCES.md` cùng thư mục).
Hình cánh: đôi cánh Draconian của bộ tile Dungeon Crawl ở trên (`player/drcwing`, CC0), đã ghép sát hai cánh và căn giữa,
để ở `assets_src/pixel_extra/wings/`.
Chọn và chép bằng `scripts/pixel_icons.py` (bảng tra `priv/static/assets/pixel_icons.json`); script tự bỏ mọi file có
trong `TILES_UNDER_UNKNOWN_LICENSE.md`. Không dùng hình MU nào.

## Hình đồ uống (`priv/static/assets/food/bia_thao_duoc.png`, `ruou_thuoc.png`, `ruou_linh_chi.png`, `ruou_long_huyet.png`)

Chai thuốc của bộ tile Dungeon Crawl Stone Soup ở trên (CC0, `releases/Nov-2015/item/potion/`: `brown`, `murky`, `golden`,
`puce`), không sửa.

## Icon (`priv/static/assets/icons/`)

Lấy từ **game-icons.net** (https://github.com/game-icons/icons), đã đổi màu và bỏ nền đen.

Giấy phép: **CC BY 3.0** (https://creativecommons.org/licenses/by/3.0/). Bắt buộc giữ phần
ghi tên này khi phát hành game.

Tác giả:
- **Lorc** (http://lorcblog.blogspot.com): anvil, backstab, battle-axe, breastplate, broad-dagger,
  broadsword, campfire, checked-shield, crossed-swords, crowned-skull, dragon-breath,
  dripping-knife, envelope, hammer-drop, lamellar, laurels, leather-vest, medal, open-book,
  relic-blade, scale-mail, scroll-unfurled, shield-reflect, shouting, skull-crossed-bones,
  spiked-mace, sprint, star-cycle, sword-clash, sword-spin, trophy, visored-helm, winged-sword
- **Delapouite** (https://delapouite.com): backpack, cave-entrance, dragon-shield, dungeon-gate,
  fishing-pole, forest, health-potion, hill-fort, leather-armor, magic-potion, mountain-cave,
  person, shield-bash, shop, speaker, speaker-off, spiked-shield, two-coins, two-handed-sword,
  village, walk, war-axe, wood-club
- **Willdabeast** (http://wjbstories.blogspot.com): chain-mail, round-shield
- Tự vẽ cho game này (CC0, Đợt 3): gem-bless, gem-soul, gem-chaos, feathered-wing, padlock,
  chaos-machine. NPC Lão Hỗn Nguyên (`npcs/chaos.png`) cũng tự vẽ (CC0). Cánh trên nhân vật vẽ bằng
  code trong `doll.js`, không dùng ảnh.
- Tự vẽ cho game này (CC0, Phase 4): gem-life (Ngọc Sinh Mệnh). NPC Tủ Đồ (`npcs/wardrobe.png`) cũng
  tự vẽ (CC0).

## Nhân vật mặc đồ, thú cưng, đồ trang trí (`priv/static/assets/doll/`, `pets/`, `decor/`)

Cũng từ bộ tile Dungeon Crawl Stone Soup ở trên (CC0): các lớp nhân vật trong `player/` (thân,
quần, giày, tóc, giáp, vũ khí, khiên), thú (`mon/animals`, `mon/hippogriff`), tượng, đài phun
nước, cây, đồ vật (`dngn/`, `item/misc`, `mon/fungi_plants`), NPC Thợ Mộc (`deep_dwarf`) và
Người Nuôi Thú (`halfling`). Hình dự phòng cho 6 thú theo MU (`pets/panda`, `raven`, `angel`, `satan`, `spirit`,
`daemon`): `mon/animals/black_bear`, `mon/animals/caustic_shrike`, `mon/holy/cherub`, `mon/demons/red_devil`,
`mon/nonliving/insubstantial_wisp`, `mon/demons/crimson_imp` (hình MU thật của anh nằm ở `assets_src/private/`, không vào git). Đã đối chiếu từng file với danh sách chưa rõ giấy phép
(`TILES_UNDER_UNKNOWN_LICENSE.md`) và chỉ dùng file không có trong danh sách đó.

## Món ăn, quà lễ hội, NPC mới (`food/`, `items/`, `decor/`, `npcs/`)

Cũng từ bộ tile Dungeon Crawl Stone Soup ở trên (CC0), đã đối chiếu với danh sách chưa rõ giấy
phép: món ăn (`item/food`: meat_ration, bread_ration, pizza, fruit), quà lễ hội
(`item/food/lump_of_royal_jelly`, `item/food/orange`, `item/misc/misc_box`, `item/food/apple`),
đồ trang trí lễ hội (`item/misc/misc_lamp`, `dngn/statues/statue_snail`,
`dngn/statues/statue_elephant`, `dngn/sparkling_fountain`), NPC Bác Đầu Bếp (`mon/human`) và
Người Tổ Chức Hội (`mon/unique/eustachio`).

## Hình cá, rương (`priv/static/assets/items/`)

- `fish_gold.png` (giant_goldfish), `fish_eel.png` (electric_eel), `old_boot.png` (boots1_brown):
  từ bộ tile Dungeon Crawl Stone Soup ở trên (CC0).
- `fish_small.png`, `fish_carp.png`, `chest_wood.png`, `chest_silver.png`, `chest_gold.png`
  (và `npcs/home_chest.png`): tự vẽ cho game này (CC0).

## Lá bài Tiến Lên (`priv/static/assets/cards/`, Phase 17)

52 lá và mặt sau (`1B.svg`) của **Adrian Kennard** (https://www.me.uk/cards/), phát hành
**CC0** (public domain); lấy từ repo `biennguyen94/Tien-Len-Mien-Nam` (cũng dùng bộ này).
NPC Bà Chủ Sòng (`npcs/dealer.png`) và icon `icons/card-fan.svg`: tự vẽ cho game này (CC0).

## Âm thanh

Không dùng file âm thanh: mọi hiệu ứng được tổng hợp trong trình duyệt bằng Web Audio
(`priv/static/js/sound.js`).

Hình nhân vật cầm cung, nỏ, gậy phép (`doll/hand1/bow.png`, `crossbow.png`, `staff.png`, Phase 15c): tự vẽ cho game này
bằng `scripts/doll_weapons.py` (CC0). Hình đồ gốc MU (`mu_items/`) không nằm trong repo, xem `docs/ITEMS_PHASE15B.md`.
