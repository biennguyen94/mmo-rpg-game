# CLAUDE.md — quy tắc làm việc cho dự án MU Web (Phase 1)

## Nguồn sự thật
Toàn bộ đặc tả nằm ở `docs/kb/`. **Đọc `docs/kb/KB_00_RULES.md` đầu tiên**, rồi theo thứ tự:
`KB_TECH_STACK` → `KB_TECHNICAL` → `KB_CONFIG` → `KB_GAME_DESIGN` → `KB_ITEM_REFERENCE` → `KB_ASSETS` → `KB_BASE_REPO`.
`KB_REFERENCE.md` chỉ là tham chiếu MU, không phải yêu cầu.

## Quy tắc cứng
1. **KB thắng repo nền** khi mâu thuẫn. Thứ tự ưu tiên dữ liệu: `KB_00_RULES §3`.
2. **Không bịa.** Thiếu dữ liệu hoặc KB mâu thuẫn → ghi vào `docs/OPEN_QUESTIONS.md` rồi hỏi. Không tự sửa file trong `docs/kb/`.
3. **Chỉ làm Phase 1** (`KB_00_RULES §7`). Không thêm tính năng `LATER_VERSION` hoặc phase sau, kể cả khi repo nền đã có sẵn.
4. **Không hard-code số gameplay.** Đọc từ `priv/game_data/` và config (`KB_CONFIG`). Mọi bản ghi dữ liệu giữ `sourceType`, `version`, `verified`.
5. **Server-authoritative.** Client chỉ gửi ý định (`cmd`); không tin damage, EXP, Zen, item, giá, vị trí, tốc độ, cooldown.
6. Protocol chỉ theo `KB_TECHNICAL §5`. Schema chỉ theo `KB_TECHNICAL §9`. Đổi → ghi `CHANGE_REASON`.
7. **Asset:** không tải/scrape asset MU. Icon item MU-derived do developer đặt tay ở `assets_src/private/item_icons/` (có thể `ITEM_ICONS_DIR`) và **không bao giờ vào git/Docker** (`KB_ASSETS §2.2`; thêm `.gitignore`/`.dockerignore`, CI kiểm `git ls-files`). Chưa có icon/sprite thật thì dùng placeholder + cảnh báo build, **không crash, exit 0**. Asset bên thứ ba ghi vào `CREDITS.md`.
8. Mỗi module lấy từ repo nền ghi một dòng vào `docs/REUSE_LOG.md` (file nguồn, commit, REUSE/ADAPT/REWRITE, lý do).
9. Quyết định nhỏ KB không nói tới: tự quyết và ghi vào `docs/DECISIONS.md`. Quyết định ảnh hưởng gameplay/schema/protocol: hỏi.

## Chất lượng
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test` phải xanh trước mỗi commit.
- Engine là hàm thuần, test với RNG có seed. Thao tác item/Zen trong một DB transaction.
- Mỗi milestone một nhánh/commit rõ ràng; **dừng và báo cáo** cuối milestone, chờ "OK" mới sang milestone sau.
