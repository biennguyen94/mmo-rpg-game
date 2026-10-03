# CREDITS — Asset bên thứ ba

## Dungeon Crawl Stone Soup tiles — CC0 1.0

Sprite và tile trong `priv/static/assets/sprites/` và `priv/static/assets/tiles/` lấy từ
**Dungeon Crawl Stone Soup** qua https://github.com/crawl/tiles (thư mục `releases/Nov-2015`,
commit `a6ea1655db5c044829d9eea19a232fa6fcac87b0`).

- Giấy phép: **CC0 1.0** (https://creativecommons.org/publicdomain/zero/1.0/), theo README của repo.
- Đã đối chiếu ngày 2026-10-03: tên file và đường dẫn gốc của **từng** file không nằm trong
  `TILES_UNDER_UNKNOWN_LICENSE.md`; mỗi file trùng từng byte (git blob hash) với bản trong repo.
  Bảng đầy đủ (file trong game → file gốc → hash): `priv/static/assets/mapping.json`.
- Cảm ơn các họa sĩ của Dungeon Crawl Stone Soup và RLTiles:
  https://github.com/crawl/tiles/blob/master/ARTISTS.md
- Không dùng DCSS cho lớp trang bị nhân vật (KB_ASSETS §2.1): mỗi class một hình cố định — DK
  thân người (`player/base/human_m.png`), DW `mon/necromancer.png`, ELF `mon/deep_elf_master_archer.png`
  (thêm ở P2-M2, cùng commit và cùng cách đối chiếu).

## Do dự án tự làm

- `priv/static/assets/icons/placeholder.png` (32×32, vẽ bằng script).
- Âm thanh: tổng hợp bằng Web Audio trong code (`client/src/audio/sound.ts`), không có file âm thanh.

## Thư viện

- Phoenix (MIT) — `phoenix.mjs` phục vụ từ dependency Elixir.
- Game view vẽ bằng Canvas 2D của trình duyệt (không dùng thư viện vẽ). Phaser 3 để phase sau (`docs/BACKLOG.md`).

## Không có trong repo

Icon item MU-derived (`assets_src/private/`, `priv/static/assets/icons/items/`, `icon_map.json`)
không bao giờ vào git/Docker (KB_ASSETS §2.2).
