# PROMPT — Claude Code (cloud): Phase 1 (vertical slice)

> Bản chỉnh của `PROMPT_PHASE1.md` để chạy trên **Claude Code cloud** (claude.ai/code, app Claude, hoặc `claude --cloud`).
> Khác biệt chính: phiên chạy trên VM của Anthropic, chỉ thấy những gì **đã commit trên GitHub**, mạng bị giới hạn theo allowlist, và VM không giữ tiến trình nền giữa các lượt.
> Các chi tiết về cloud lấy từ tài liệu Claude Code (cloud environments), kiểm tra lại khi nền tảng đổi.

## A. Chuẩn bị (bạn làm, một lần)

### A1. Repo GitHub (bắt buộc)
1. Tạo repo GitHub riêng (private được) cho dự án, `git init` rồi push.
2. Cho Claude truy cập repo: cài **Claude GitHub App** lên repo, hoặc chạy `/web-setup` trong terminal để gửi token `gh`. Cần gói Pro/Max/Team (hoặc Enterprise có seat phù hợp).
3. Đưa mã repo nền vào repo dự án để phiên cloud đọc được mà không cần quyền sang repo khác:
   `reference/rpg-game/` (copy nguyên cây, bỏ `.git`) + file `reference/rpg-game/COMMIT` ghi hash commit đã lấy. Đã được bạn cho phép dùng toàn quyền (bạn là chủ repo).
4. Chép bộ file vào đúng chỗ rồi **commit và push**:
   - `CLAUDE.md` → gốc repo (cloud tự đọc)
   - `KB_*.md` + `CHANGELOG.md` → `docs/kb/`
   - `data/items/phase1.json`, `priv/reference/items_raw.json`, `scripts/parse_items.py`
   - `docs/PROMPT_PHASE1.md` ← nội dung khung prompt ở mục C
   - `scripts/cloud_session_start.sh` và `.claude/settings.json` ← mục A3
5. **Không commit** icon MU-derived. Thư mục `assets_src/private/item_icons/` bị gitignore nên **không có trong cloud**: ở phiên cloud agent luôn dùng placeholder (xem mục C). Muốn icon thật thì thêm lúc chạy local sau.

### A2. Cloud environment (tạo ở claude.ai/code → chọn môi trường → Add cloud environment)
- **Tên:** `mu-web-phase1`
- **Network access:** `Custom`, tick *Also include default list of common package managers*, thêm 2 dòng:
  ```
  repo.hex.pm
  builds.hex.pm
  ```
  Danh sách mặc định có `hex.pm` nhưng theo tôi biết Hex tải gói từ `repo.hex.pm` và bản dựng từ `builds.hex.pm`. Nếu `mix deps.get` báo chặn domain khác, thêm domain đó vào.
- **Environment variables:**
  ```
  BASH_DEFAULT_TIMEOUT_MS=600000
  BASH_MAX_TIMEOUT_MS=600000
  MIX_ENV=dev
  ```
  (đặt timeout mặc định 10 phút để `mix test` không bị chuyển xuống nền giữa chừng). Đừng đặt bí mật vào đây: ai dùng môi trường đều đọc được.
- **Setup script** (VM mặc định có Node 22, PostgreSQL 16, Docker nhưng **không có Elixir/Erlang**):
  ```bash
  #!/bin/bash
  # Chạy khi tạo môi trường, kết quả được cache; phải exit 0 và xong trong ~5 phút.
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y || true
  apt-get install -y elixir erlang inotify-tools || true
  mix local.hex --force || true
  mix local.rebar --force || true
  # Đặt mật khẩu postgres/postgres để khớp config dev/test
  service postgresql start || true
  su postgres -c "psql -c \"ALTER USER postgres PASSWORD 'postgres';\"" || true
  service postgresql stop || true
  elixir --version || echo "WARN: elixir chua cai duoc"
  exit 0
  ```
  Apt trên Ubuntu 24.04 cho Elixir ~1.14 / OTP ~25 (khớp yêu cầu "Elixir ≥ 1.14, OTP ≥ 25" ở bản gốc). **Chưa kiểm chứng**: agent kiểm ở M0 và đối chiếu `mix.exs` của repo nền. Cần bản mới hơn thì sửa script và nhớ rằng tải release từ GitHub của repo khác bị proxy chặn (403) với tiến trình không gắn vào phiên.

### A3. Hai file commit trong repo
`.claude/settings.json`:
```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume",
        "hooks": [ { "type": "command",
                     "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/cloud_session_start.sh" } ] }
    ]
  }
}
```
`scripts/cloud_session_start.sh`:
```bash
#!/bin/bash
[ "$CLAUDE_CODE_REMOTE" = "true" ] || exit 0
# Tiến trình nền không được cache: bật lại Postgres mỗi phiên
service postgresql start || true
cd "$CLAUDE_PROJECT_DIR" || exit 0
[ -f mix.exs ] && mix deps.get || true
exit 0
```

### A4. Bắt đầu phiên
- Chọn repo + môi trường `mu-web-phase1`, chế độ quyền cho phép sửa file (**đừng dùng Plan mode**: M0 cần ghi `docs/`).
- Gửi một dòng: `Đọc docs/PROMPT_PHASE1.md và làm M0.`
- Hoặc từ terminal: `claude --cloud "Đọc docs/PROMPT_PHASE1.md và làm M0."` (nhớ push trước, VM clone từ GitHub chứ không lấy checkout local).
- Sau mỗi milestone phiên dừng và chờ bạn. Bạn trả lời được sau đó; nếu VM bị thu hồi, mở lại phiên là có VM mới và lịch sử hội thoại (tiến trình nền không được khôi phục).
- Muốn chạy thử game: VM không mở ra ngoài. Pull nhánh về máy bạn hoặc `claude --teleport` rồi chạy local theo `docs/RUN_LOCAL.md`.

## B. Việc không làm được trên cloud (so với bản gốc)

| Bản gốc | Cloud |
|---|---|
| Plan mode ở M0 | Dùng chế độ sửa file; M0 vẫn cấm viết code |
| Cài Elixir/Postgres tự quản | Setup script + hook ở trên |
| Icon đặt tay ở `assets_src/private/` | Không có trong cloud → placeholder |
| Soak test 1 giờ ở M6 | Giới hạn thời gian lệnh (nền tối đa ~30 phút): chạy ≤ 25 phút trong cloud, 1 giờ bạn chạy local |
| Ảnh chụp màn hình làm bằng chứng | Chưa chắc có trình duyệt headless; ưu tiên test tự động. M0 kiểm tra |
| Binary tải từ GitHub Releases (ví dụ gói `tailwind` của Phoenix) | Bị proxy GitHub chặn với repo không gắn vào phiên → dùng npm (esbuild/Vite) |

## C. Prompt (đã lưu ở `docs/PROMPT_PHASE1.md`)

```
Bạn là kỹ sư chính của dự án "MU Web": web MMORPG 2D lấy cảm hứng MU Online cổ điển, server Elixir + Phoenix + PostgreSQL, client Phaser 3 + TypeScript. Bạn đang chạy trong phiên Claude Code cloud (VM Ubuntu 24.04, 4 vCPU/16 GB, mạng theo allowlist, chỉ thấy file đã commit).

NGUỒN SỰ THẬT
- Đặc tả nằm ở docs/kb/. Đọc CLAUDE.md, rồi docs/kb/KB_00_RULES.md đầu tiên, sau đó KB_TECH_STACK, KB_TECHNICAL, KB_CONFIG, KB_GAME_DESIGN, KB_ITEM_REFERENCE, KB_ASSETS, KB_BASE_REPO.
- Dữ liệu item đã chuẩn bị: data/items/phase1.json (10 template), priv/reference/items_raw.json, scripts/parse_items.py.
- Phạm vi: CHỈ Phase 1 (KB_00_RULES §7, kể cả JSON scope và danh sách acceptance). Không làm gì ngoài phạm vi, kể cả khi repo nền đã có.
- Quy tắc ưu tiên: KB thắng repo nền. Thiếu dữ liệu hoặc KB mâu thuẫn → ghi docs/OPEN_QUESTIONS.md và hỏi tôi; không bịa, không tự sửa docs/kb/.

REPO NỀN
- Mã repo nền (Hắc Long RPG, Elixir/Phoenix, theo lượt) nằm ở reference/rpg-game/ (hash trong reference/rpg-game/COMMIT). Tôi là chủ repo và cho phép toàn quyền copy/sửa code. Không sửa reference/, không clone repo khác. Asset bên thứ ba (DCSS CC0, game-icons.net CC BY 3.0) theo license riêng, ghi CREDITS.md.
- Tạo dự án trong thư mục gốc dựa trên reference/rpg-game: đổi namespace HacLong → Mu / HacLongWeb → MuWeb, bỏ mọi tính năng ngoài Phase 1 (tháp, câu cá, thú cưng, chợ, bang…) thay vì giữ lại.
- README repo nền chỉ là nguồn thứ cấp: ĐỌC source và test thật của từng module trước khi quyết định REUSE / ADAPT / REWRITE (bảng ở KB_BASE_REPO §3). Chiến đấu của repo nền theo lượt, còn dự án này real-time (20 Hz, lưới ô): Engine, movement, monster AI phải viết lại.

QUYẾT ĐỊNH ĐÃ CHỐT (không hỏi lại)
- Real-time, lưới ô, tick 20 Hz, AI 10 Hz, snapshot 10 Hz (KB_00_RULES S9, KB_CONFIG).
- Không Redis; OTP (Session / MapServer / Registry / ETS). Auth: token opaque băm trong DB + WS ticket 1 lần trong ETS; Argon2id.
- Phase 1: 1 class DK, 1 map Lorencia, 1 quái Spider, 1 NPC shop, 10 item, maxLevel 10, 1 nhân vật/tài khoản.
- items.requirementScale = 0.35 áp lúc import (đã có trong phase1.json).
- Icon item: trong cloud KHÔNG có icon thật (assets_src/private/ bị gitignore). Ở M1 thêm .gitignore/.dockerignore theo KB_ASSETS §2.2; ở M4–M5 viết mix mu.icons.index (input rỗng vẫn chạy, ra placeholder, ghi docs/ICON_REPORT.md). Không commit icon MU-derived.
- Chưa có sprite nhân vật, tileset Lorencia, âm thanh thật: dùng placeholder (hình học/ô màu, sprite DCSS CC0 nếu lấy được qua allowlist, âm thanh tổng hợp Web Audio như repo nền). Không tải/scrape asset MU.
- Map Phase 1: tự viết map Lorencia nhỏ (~64×64) dạng JSON + collision theo KB_TECHNICAL §8, kèm test (spawn hợp lệ, vùng safe zone). Pipeline Tiled để sau.
- Client build: TypeScript → priv/static bằng esbuild hoặc Vite QUA NPM. Không dùng gói tải binary từ GitHub Releases (ví dụ tailwind của Phoenix): proxy chặn. Ghi lý do vào docs/DECISIONS.md.

M�I TRƯỜNG CLOUD
- Đầu mỗi phiên: kiểm tra elixir --version, mix --version, psql --version và Postgres đã chạy (hook SessionStart đã bật). Thiếu gì → ghi docs/OPEN_QUESTIONS.md kèm lệnh lỗi; không tự đổi cấu hình môi trường.
- Lệnh bị chặn mạng (403/timeout): ghi domain vào docs/OPEN_QUESTIONS.md và hỏi tôi thêm vào allowlist. Không dùng cách lách proxy.
- File chưa commit và tiến trình nền không chắc còn sau khi VM bị thu hồi. Cuối mỗi milestone: commit + git push lên nhánh của phiên (chỉ nhánh hiện tại), báo hash.
- Không chạy lệnh foreground quá 10 phút. Test dài chạy nền và có timeout rõ ràng. Soak test M6 trong cloud tối đa ~25 phút; bản 1 giờ tôi chạy local theo docs/RUN_LOCAL.md (bạn viết file này).
- Không có màn hình/trình duyệt đảm bảo: kiểm thử bằng test tự động (ExUnit, Channel test, test client bằng vitest/node). Nếu có trình duyệt headless dùng được thì nói rõ, nếu không ghi vào báo cáo.

CÁCH LÀM — theo milestone, DỪNG và báo cáo sau mỗi milestone, chờ tôi nói "OK" mới tiếp:
M0  Đọc & lập kế hoạch (CHƯA viết code): đọc KB + source reference/rpg-game; kiểm tra môi trường cloud; ghi docs/PHASE1_PLAN.md (quyết định REUSE/ADAPT/REWRITE từng module, cấu trúc thư mục, rủi ro), docs/REUSE_LOG.md, docs/OPEN_QUESTIONS.md (mâu thuẫn/thiếu sót trong KB, vấn đề môi trường), docs/CLOUD_CHECK.md (Elixir/OTP/Postgres/Node version, mạng, có trình duyệt headless không). Commit + push.
M1  Khung: dự án Phoenix, namespace Mu, Docker/CI, accounts + token + WS ticket, rate-limit, channel "game" (join có clientVersion), migration Phase 1 theo KB_TECHNICAL §9, tạo nhân vật DK. Test.
M2  World: MapServer Lorencia (tick 20 Hz), move_to + A*, validate di chuyển, snapshot, 2 người chơi thấy nhau (broadcast đơn giản, chưa AOI). Test.
M3  Combat: Engine hàm thuần theo KB_GAME_DESIGN §4–§6 và §4.1 (DK), hit/crit/cooldown, Spider AI (IDLE→CHASE→ATTACK→RETURN, respawn), EXP/level up/alloc stat, drop (spider), death/respawn. Test với RNG seed; chạy simulator mức cơ bản.
M4  Items: import template từ data/items/phase1.json, items + item_locations + item_audit_log, serial ULID, pickup/equip/unequip/use_item/buy/sell/npc_open, validate yêu cầu và class, giá/ownership. Test, gồm test hai Session thao tác cùng item không nhân đôi.
M5  Client Phaser: login/tạo nhân vật, render map, click-to-move/attack có interpolation, UI Phase 1 theo KB_GAME_DESIGN §19 (dock 4 tab, panel Nhân vật/Túi đồ/Thông báo/Shop, context menu quái, nút mobile), icon_map + placeholder. Desktop ≥1280px và mobile ≥360px. Viết docs/RUN_LOCAL.md để tôi chạy và xem bằng mắt.
M6  Nghiệm thu: chạy từng mục acceptance trong KB_00_RULES §7, báo bảng pass/fail kèm bằng chứng (test, log). Mục cần mắt người (giao diện, mobile) đánh dấu "cần tôi kiểm tra local". Soak test ≤25 phút trong cloud. Liệt kê cân bằng lệch (đã biết: Q14 — Leather Armor làm Spider vô hại).

M��I MILESTONE
- Trước khi code: nêu ngắn bạn sẽ làm gì và file nào bị ảnh hưởng.
- mix format --check-formatted, mix compile --warnings-as-errors, mix test phải xanh.
- Commit riêng cho milestone, push nhánh phiên. Báo cáo cuối: đã làm gì, test nào, lệch KB ở đâu (CHANGE_REASON), câu hỏi mở.

Bắt đầu ngay M0. Chưa viết code trước khi tôi duyệt kế hoạch.
```

## D. Sau M0 (bạn kiểm)
1. Đọc `docs/CLOUD_CHECK.md`: Elixir/OTP đủ version chưa? Hex có tải được không? Có trình duyệt headless không?
2. Đọc `docs/PHASE1_PLAN.md` và `docs/OPEN_QUESTIONS.md`, rồi mới nói "OK".
3. Cuối mỗi milestone, merge/pull nhánh phiên về máy nếu muốn chạy thử; sau M5 chạy local theo `docs/RUN_LOCAL.md`.
