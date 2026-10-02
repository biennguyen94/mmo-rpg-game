# PROMPT — Claude Code: Phase 1 (vertical slice)

> Dán nội dung trong khung dưới vào Claude Code. **Bắt đầu ở Plan mode.**
> Chuẩn bị trước (bạn làm): xem "Checklist chuẩn bị" cuối file.

```
Bạn là kỹ sư chính của dự án "MU Web": web MMORPG 2D lấy cảm hứng MU Online cổ điển, server Elixir + Phoenix + PostgreSQL, client Phaser 3 + TypeScript.

NGUỒN SỰ THẬT
- Đặc tả nằm ở docs/kb/. Đọc CLAUDE.md, rồi docs/kb/KB_00_RULES.md đầu tiên, sau đó KB_TECH_STACK, KB_TECHNICAL, KB_CONFIG, KB_GAME_DESIGN, KB_ITEM_REFERENCE, KB_ASSETS, KB_BASE_REPO.
- Dữ liệu item đã chuẩn bị: data/items/phase1.json (10 template), priv_reference/items_raw.json, scripts/parse_items.py.
- Phạm vi: CHỈ Phase 1 (KB_00_RULES §7, kể cả JSON scope và danh sách acceptance). Không làm gì ngoài phạm vi, kể cả khi repo nền đã có.
- Quy tắc ưu tiên: KB thắng repo nền. Thiếu dữ liệu hoặc KB mâu thuẫn → ghi docs/OPEN_QUESTIONS.md và hỏi tôi; không bịa, không tự sửa docs/kb/.

REPO NỀN
- https://github.com/biennguyen94/rpg-game (Hắc Long RPG, Elixir/Phoenix, theo lượt). Tôi là chủ repo và cho phép toàn quyền copy/sửa code của repo. Asset bên thứ ba (DCSS CC0, game-icons.net CC BY 3.0) vẫn theo license riêng, ghi CREDITS.md.
- Tạo dự án mới trong thư mục hiện tại dựa trên repo nền: ghi lại commit hash đã dùng, đổi namespace HacLong → Mu / HacLongWeb → MuWeb, bỏ mọi tính năng ngoài Phase 1 (tháp, câu cá, thú cưng, chợ, bang…) thay vì giữ lại.
- README repo nền chỉ là nguồn thứ cấp: ĐỌC source và test thật của từng module trước khi quyết định REUSE / ADAPT / REWRITE (bảng ở KB_BASE_REPO §3). Chiến đấu của repo nền theo lượt, còn dự án này real-time (20 Hz, di chuyển theo lưới ô): Engine, movement, monster AI phải viết lại.

QUYẾT ĐỊNH ĐÃ CHỐT (không hỏi lại)
- Real-time, lưới ô, tick 20 Hz, AI 10 Hz, snapshot 10 Hz (KB_00_RULES S9, KB_CONFIG).
- Không Redis; OTP (Session / MapServer / Registry / ETS). Auth: token opaque băm trong DB + WS ticket 1 lần trong ETS; Argon2id.
- Phase 1: 1 class DK, 1 map Lorencia, 1 quái Spider, 1 NPC shop, 10 item, maxLevel 10, 1 nhân vật/tài khoản.
- items.requirementScale = 0.35 áp lúc import (đã có trong phase1.json).
- Icon item (MU-derived) do tôi đặt tay vào assets_src/private/item_icons/ (gitignore; KB_ASSETS §2.2). Ở M1 thêm .gitignore/.dockerignore theo §2.2; ở M4–M5 viết mix mu.icons.index (input rỗng vẫn chạy, ra placeholder, ghi docs/ICON_REPORT.md). Không commit icon.
- Chưa có sprite nhân vật, tileset Lorencia, âm thanh thật (và icon nếu tôi chưa đặt): dùng placeholder (hình học/ô màu, sprite DCSS CC0 nếu tìm được, âm thanh tổng hợp Web Audio như repo nền). Không tải/scrape asset MU.
- Map Phase 1: tự viết một map Lorencia nhỏ (khoảng 64×64) dạng JSON + collision theo KB_TECHNICAL §8, kèm test (spawn hợp lệ, vùng safe zone). Pipeline Tiled đầy đủ để sau.
- Client build: TypeScript → priv/static (esbuild do Phoenix quản lý, hoặc Vite nếu bạn thấy cần; ghi lý do vào docs/DECISIONS.md).

CÁCH LÀM — theo milestone, DỪNG và báo cáo sau mỗi milestone, chờ tôi nói "OK" mới tiếp:
M0  Đọc & lập kế hoạch (Plan mode): đọc KB + source repo nền; ghi docs/PHASE1_PLAN.md (quyết định REUSE/ADAPT/REWRITE từng module, cấu trúc thư mục, rủi ro), docs/REUSE_LOG.md, docs/OPEN_QUESTIONS.md (mâu thuẫn/thiếu sót trong KB). Chưa viết code.
M1  Khung: dự án Phoenix, namespace Mu, Docker/CI, accounts + token + WS ticket, rate-limit, channel "game" (join có clientVersion), migration Phase 1 theo KB_TECHNICAL §9, tạo nhân vật DK. Test.
M2  World: MapServer Lorencia (tick 20 Hz), move_to + A*, validate di chuyển, snapshot, 2 người chơi thấy nhau (broadcast đơn giản, chưa AOI). Test.
M3  Combat: Engine hàm thuần theo KB_GAME_DESIGN §4–§6 và §4.1 (DK), hit/crit/cooldown, Spider AI (IDLE→CHASE→ATTACK→RETURN, respawn), EXP/level up/alloc stat, drop (spider), death/respawn. Test với RNG seed; chạy simulator mức cơ bản.
M4  Items: import template từ data/items/phase1.json, items + item_locations + item_audit_log, serial ULID, pickup/equip/unequip/use_item/buy/sell/npc_open, validate yêu cầu và class, giá/ownership. Test, gồm test hai Session thao tác cùng item không nhân đôi.
M5  Client Phaser: login/tạo nhân vật, render map, click-to-move/attack có interpolation, UI Phase 1 theo KB_GAME_DESIGN §19 (dock 4 tab, panel Nhân vật/Túi đồ/Thông báo/Shop, context menu quái, nút mobile), icon_map + placeholder. Desktop ≥1280px và mobile ≥360px.
M6  Nghiệm thu: chạy từng mục acceptance trong KB_00_RULES §7, báo bảng pass/fail kèm bằng chứng (test, log, ảnh chụp nếu có); soak test 1 giờ; liệt kê cân bằng lệch (đã biết: Q14 — Leather Armor làm Spider vô hại).

MỖI MILESTONE
- Trước khi code: nêu ngắn bạn sẽ làm gì và file nào bị ảnh hưởng.
- mix format --check-formatted, mix compile --warnings-as-errors, mix test phải xanh.
- Commit riêng cho milestone. Báo cáo cuối: đã làm gì, test nào, lệch KB ở đâu (CHANGE_REASON), câu hỏi mở.

Bắt đầu ngay M0. Chưa viết code trước khi tôi duyệt kế hoạch.
```

## Checklist chuẩn bị (bạn làm trước)

1. Tạo thư mục dự án, `git init`.
2. Chép bộ file vào đúng chỗ:
   - `CLAUDE.md` → gốc dự án
   - các file `KB_*.md` + `CHANGELOG.md` → `docs/kb/`
   - `data/items/phase1.json` → `data/items/` (hoặc `priv/game_data/items/`, ghi trong kế hoạch M0)
   - `priv_reference/items_raw.json` → `priv/reference/items_raw.json`
   - `scripts/parse_items.py` → `scripts/`
3. Cài: Elixir ≥ 1.14 (OTP ≥ 25), PostgreSQL (`postgres`/`postgres` trên localhost), Node.js (build client), Docker (tuỳ chọn), git.
4. Cho Claude Code quyền chạy `mix`, `git`, `npm`; **đừng** để nó cài gói ngoài dự án.
5. Đặt icon item (nếu đã có) vào `assets_src/private/item_icons/` — thư mục này **không commit**. Chưa có thì bỏ qua, agent dùng placeholder.
6. Chạy `claude` trong thư mục dự án, bật Plan mode, dán prompt.
7. Sau M0: đọc `docs/PHASE1_PLAN.md` và `docs/OPEN_QUESTIONS.md` kỹ trước khi nói "OK".
