# BACKLOG — Việc để lại sau Phase 1

> Gom mọi việc đã biết nhưng **không làm ở Phase 1** (hoặc chờ anh/chờ môi trường), để phase sau
> bắt đầu từ đây. Scope các phase vẫn theo `docs/kb/KB_00_RULES.md §7`; file này không thêm scope.
> Trạng thái cuối Phase 1: `docs/ACCEPTANCE.md`. Câu hỏi mở: `docs/OPEN_QUESTIONS.md`.

## 1. Chuyển game view sang Phaser 3 (DEC-53)

**Vì sao chưa làm:** `registry.npmjs.org` bị gateway của môi trường cloud chặn
(`403`, `x-deny-reason: host_not_allowed`) suốt M5–M6 dù đã thêm vào allowlist. Anh chọn phương án
(b): Phase 1 dùng Canvas 2D (`client/src/view/canvas_view.ts`), Phaser để sau.

**Điều kiện bắt đầu:** `curl -sS -D - -o /dev/null https://registry.npmjs.org/phaser` trả `200`
trong môi trường làm việc (hoặc làm trên máy local).

**Những gì KHÔNG phải đổi:** luật, protocol, server, UI DOM (§19), logic client
(`game/`, `logic/`, `state/`, `net/`) — tất cả nói chuyện với phần vẽ qua interface
`GameView` (`client/src/view/view.ts`). Asset đã sẵn và cùng đường dẫn
(`/assets/sprites/...`, `/assets/tiles/{mapId}/{legend}.png`, `mapping.json`).

**Các bước:**
1. `cd client && npm install phaser@3` (ghim đúng bản 3.x cuối cùng lúc đó; Phaser 4 khác API) →
   sinh và commit `package-lock.json`; Dockerfile đổi `npm install` → `npm ci`.
2. Phục vụ thư viện cho trình duyệt: thêm lại bước chép `node_modules/phaser/dist/phaser.esm.js`
   → `priv/static/vendor/` (gitignore) + `Plug.Static` `/vendor` từ `{:mu, "priv/static/vendor"}`
   + `"phaser": "/vendor/phaser.esm.js"` trong import map `priv/static/index.html`
   (xem commit `764d357` — đã có rồi gỡ ở DEC-53).
3. Viết `client/src/view/phaser_view.ts` cài đặt `GameView`: tilemap từ `MapData.tiles` + legend,
   sprite theo `kind`/`templateId`, camera theo nhân vật, nội suy bằng `entity.interp.at(clock())`,
   số sát thương bay lên, marker click, `onGround`/`onEntity` từ pointer.
4. `client/src/main.ts`: đổi `createCanvasView` → `createPhaserView` (có thể giữ Canvas làm dự phòng
   khi Phaser lỗi tải).
5. Chạy lại `client/e2e/smoke.mjs` (24 mục) và `client/e2e/acceptance.mjs` (19 mục): hai bộ này
   dùng `[data-test="game-canvas"]` + `window.__mu` — giữ hai thứ đó trong PhaserView.
6. Cập nhật `CREDITS.md` (Phaser, MIT), DEC mới thay DEC-53.

**Lợi ích khi chuyển:** animation sprite sheet (KB_ASSETS §4: idle/walk/attack/skill/hit/die × 4
hướng), tilemap Tiled (`.tmj`, KB_TECHNICAL §8), hiệu ứng skill, scale/zoom.

## 2. Asset còn thiếu (KB_ASSETS §6.1)

| Thứ | Hiện tại | Cần |
|---|---|---|
| Nhân vật DK | 1 khung tĩnh DCSS `human_m` (không vẽ trang bị, KB_ASSETS §2.1) | 6 animation × 4 hướng + lớp trang bị (A4: nguồn/định dạng chưa chốt) |
| Spider, NPC | 1 khung tĩnh DCSS | idle/walk/attack/die |
| Tileset | 7 tile DCSS rời (`tiles/lorencia/*.png`) | tileset + pipeline Tiled → JSON/collision (KB_TECHNICAL §8) |
| Effect | Số sát thương bay lên | hit spark, level-up, heal, twisting_slash |
| Âm thanh | 7 SFX tổng hợp Web Audio | 1 BGM Lorencia |
| Icon item | Placeholder 32×32 (`docs/ICON_REPORT.md`: 10/10) | Icon thật đặt ở `assets_src/private/item_icons/` (Q11/A6, không vào git) + 10 silhouette slot trống |

## 3. Chờ anh quyết (cân bằng, `docs/ACCEPTANCE.md §3`)

- **G26** bầy Spider aggro (a: `aggroRange` 3 / b: giãn vùng sinh / c: giữ — hiện giữ).
- **Q14** một món áo làm Spider vô hại.
- **E-2** Twisting Slash cần cấp 10 = maxLevel.
- Xác nhận các lệch protocol/schema M1-1 … M5-4 (`docs/OPEN_QUESTIONS.md`).

## 4. Hạ tầng / kiểm thử còn treo

| Việc | Ghi chú |
|---|---|
| Soak 1 giờ | Cloud chỉ chạy 10 phút; lệnh ở `docs/RUN_LOCAL.md` §6 |
| Build Docker image | Docker Hub bị chặn trong cloud; đã kiểm `mix release` + migrate |
| `priv/reference/items_raw.json` (E6) | Bật lại test đối chiếu template (đang `@tag :skip`) |
| ~~Watcher client~~ | **Xong** (DEC-54): `mix phx.server` chạy `client/watch.mjs` (`tsc --watch`, dừng cùng server) |
| ~~CI e2e~~ | **Xong** (DEC-55): job `e2e` trong `.github/workflows/ci.yml` (smoke + nghiệm thu, upload ảnh/log). Chưa chạy trên GitHub — lần đầu sẽ chạy khi có PR |

## 5. Scope các phase sau (nhắc lại từ KB_00_RULES §7, không làm ở Phase 1)

- **Phase 2:** (kế hoạch: `docs/PHASE2_PLAN.md`) DW, Elf, túi đồ kéo thả (`move_item`, `split`, `drop`), skill theo class,
  drop table mở rộng, chat, Hộp thư hệ thống (§19.10), panel Bản đồ (§19.12).
- **Phase 3:** AOI (KB_TECHNICAL §3, đã có `aoiCellSize` trong config), reconnect giữ phiên
  (`reconnectGraceSeconds`), party, warehouse (bảng `item_locations` đã có `WAREHOUSE`), MG
  (`account.maxCharacters` 4).
- **Phase 4–6:** PvP/guild, trading/jewel/upgrade, quest/chaos machine/wings/events.
