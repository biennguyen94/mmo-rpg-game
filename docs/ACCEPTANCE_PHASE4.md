# ACCEPTANCE_PHASE4 — Nghiệm thu Phase 4 "PvP & Social" (P4-M5)

> **Danh sách nghiệm thu = P4-9.** Em soạn theo scope `KB_00_RULES §7` Phase 4 (Duel, PK,
> Self-defense, Guild, Guild war) và các đề xuất đã duyệt P4-2 … P4-8; anh cho làm 2026-10-03.
> Ngày chạy: 2026-10-03, môi trường Claude Code cloud (Elixir 1.17.3 / OTP 25, Postgres 16, Chromium).
>
> Bằng chứng 3 lớp như Phase 1–3:
> - **ExUnit:** `mix test`, 327 test, 0 lỗi (1 skip có sẵn từ trước). Test client `npm test` 21 / 21.
> - **E2E:** trình duyệt thật trên server thật, **15 bộ / 213 mục** trong `client/e2e/`, chạy
>   **trong lúc soak**. `guildwar.mjs` chạy lần đầu ở đây (P4-M4 dồn E2E sang M5 — DEC-137).
> - **Soak:** 20 bot × 10 phút, có nhóm **và guild war** (bot cấp 20 đánh nhau ngoài thị trấn).

## 1. Danh sách nghiệm thu P4-9 và kết quả

| # | Mục (scope Phase 4) | Kết quả | Bằng chứng |
|---|---|---|---|
| 1 | **Tấn công người chơi** (P4-2, §13 state machine — không có boolean `isPvP`): cả hai cấp ≥ 6, không ai trong safe zone, sát thương × 0,5, AOE chỉ trúng quái (trừ đối thủ duel / guild địch), không đánh người cùng nhóm, kẻ giết không nhận EXP / Zen | ✅ PASS | ExUnit `pvp_test.exs` 8 (bảng quyết định thuần), `pvp_channel_test.exs` 5. E2E `pvp.mjs` 14/14 (trong thị trấn không có nút; ngoài thị trấn có; cấp 5 không có) |
| 2 | **PK** (P4-3): NORMAL → WARNING (1) → MURDERER (2); giết người NORMAL +1 (ghi DB ngay); giảm 1 điểm / 60 phút giờ thực; MURDERER bị NPC từ chối; rơi đồ khi bị giết (WARNING 10 %, MURDERER 50 %, loot protect cho kẻ giết); màu tên | ✅ PASS | ExUnit (`pvp_test` giảm điểm / tỉ lệ rơi; kênh: +1 PK, ghi DB, `spawn` cam, MURDERER `npc_open` FORBIDDEN, vào lại sau 2 giờ về 0, rơi đồ). E2E `pvp.mjs`: xác nhận lần đầu, WARNING + thông báo + panel "Cảnh báo (1)", MURDERER bị NPC từ chối. Ảnh `p4-pvp-confirm.png`, `p4-pvp-warning.png` |
| 3 | **Self-defense** (P4-3): bị đánh trước được đánh trả 30 s không bị PK; kẻ gây sự nhấp nháy cam | ✅ PASS | ExUnit `pvp_test` (quyền đánh trả, làm mới, đánh trả không thành kẻ gây sự), kênh (giết khi tự vệ không PK). E2E `pvp.mjs` (B thấy A `aggressor`) |
| 4 | **Duel** (P4-4): mời / nhận / từ chối / hủy / đầu hàng; "vùng riêng" (người ngoài không xen vào); 1 HP thì thua (không chết, không PK, không rơi đồ); hết 3 phút hòa; đi xa > 20 ô / rời map / mất kết nối thì thua | ✅ PASS | ExUnit `duel_test.exs` 5, `duel_channel_test.exs` 5. E2E `duel.mjs` 14/14. Ảnh `p4-duel-ask.png`, `p4-duel-bar.png` |
| 5 | **Guild** (P4-5): tạo (cấp 20 + 10 000 Zen, một transaction), tên 3–8 ký tự không trùng, tối đa 20 người / 2 phó guild; quyền master / assistant / member; mời / nhận / từ chối / rời / đuổi / phong / hạ / giải tán; chat `/g`; `<Tên guild>` dưới tên nhân vật; lưu DB (migration có CHANGE_REASON) | ✅ PASS | ExUnit `guilds_test.exs` 3 (DB, lỗi không trừ Zen), `guild_channel_test.exs` 6. E2E `guild.mjs` 24/24. Ảnh `p4-guild-panel.png`, `p4-guild-invite.png`, `p4-guild-create-mobile.png`, `p4-guild-panel-mobile.png` |
| 6 | **Guild war** (P4-6): master tuyên chiến, master bên kia nhận trong 60 s; mỗi guild một war; thành viên hai guild đánh nhau ngoài safe zone, AOE trúng địch, không PK, không rơi đồ, +1 điểm / kill; kết thúc ở 20 điểm / 30 phút / đầu hàng / giải tán; tên địch tím; báo SYSTEM; chỉ trong RAM | ✅ PASS | ExUnit `guild_war_test.exs` 4 (thuần), `guild_war_channel_test.exs` 6 (đủ điểm thắng, AOE, hết giờ hòa, giải tán = đầu hàng, vào game giữa war). E2E `guildwar.mjs` 13/13 (lần đầu chạy). Soak: war chạy suốt 10 phút, 3 kill tính điểm. Ảnh `p4-war-ask.png`, `p4-war-bar.png` |
| 7 | **Server-authoritative / protocol** cho act mới (P4-7): `attack p_…`, `duel_*`, `guild_*`, `guild_war_*` đều kiểm ở server; client chỉ ẩn / hiện nút | ✅ PASS | ExUnit: `FORBIDDEN` (sai quyền, safe zone, cùng nhóm, đang duel người khác, đầy, đã war), `INVALID_TARGET`, `REQUIREMENT_NOT_MET`, `NOT_ENOUGH_ZEN`, `OUT_OF_RANGE`; `config_test` mọi act mới có nhóm rate-limit |
| 8 | **Tải nhiều người có PvP:** 20 người chơi 10 phút (nhóm + guild war, 1/4 ở thị trấn) cùng 15 bộ E2E | ✅ PASS | Soak §2 |
| 9 | **Không hồi quy Phase 1–3** | ✅ PASS | E2E `smoke` 24/24, `acceptance` 24/24, `classes` 6/6, `skills` 7/7, `maps` 8/8, `chat` 7/7, `mail_map` 10/10, `reconnect` 11/11, `warehouse` 12/12, `party` 13/13, `mg` 12/12 (chạy trong lúc soak). Simulator DK / DW / ELF / MG ra **đúng số Phase 3** (§4) |
| 10 | **DB:** chỉ thêm hai bảng `guilds`, `guild_members` (migration `20261005000000_create_guilds.exs`, CHANGE_REASON); PK dùng cột có sẵn; duel / lời mời / war chỉ trong RAM | ✅ PASS | `git diff` Phase 4 trên `priv/repo/migrations/`: 1 file |
| 11 | **UI desktop + mobile** cho menu người chơi (Tấn công / Thách đấu / Mời vào guild), thanh duel / war, hộp lời mời, panel Guild | ⚠️ PASS tự động, **cần anh xem bằng mắt ở local** | E2E desktop 1280px; panel Guild 390px không tràn ngang (ảnh `p4-guild-*-mobile.png`) |
| 12 | **Asset:** không có file MU-derived trong git; Phase 4 không thêm sprite mới | ✅ PASS | `git ls-files`: 0 file `assets_src/private`, `icons/items`, `icon_map.json` |

## 2. Soak test (20 bot × 10 phút, 11:30 → 11:40 UTC)

**Thiết lập:**
- Server: `TRUSTED_PROXIES=127.0.0.1 elixir --sname mu -S mix phx.server`.
- Soak: `SOAK_PARTY=5 SOAK_WAR=1 SOAK_EVENTS=1 node client/e2e/soak.mjs … 20 10 0.25`.
  - Mọi bot lên cấp 20 + 20 000 Zen trước khi vào game (`scripts/e2e_soak_seed.exs`), cộng hết điểm
    vào STR.
  - 5 bot đi lại trong thị trấn; 15 bot săn chia hai guild (master lập guild, mời người, guild A
    tuyên chiến guild B, B nhận). Bot săn đánh người guild địch đứng gần trong dải đường + vùng
    Spider; 4 nhóm × 5 người (có một nhóm gồm người của cả hai guild — không đánh nhau được, P4M4-2).
- Probe mỗi phút từ node khác (`scripts/soak_probe.exs`, nay đo thêm hàng đợi `Mu.Guild`, số người
  online đăng ký với guild, số war).
- **Cùng lúc chạy 15 bộ E2E.**

| Chỉ số | Phase 4 | Phase 3 (để so) |
|---|---|---|
| Nhịp mô phỏng | **1 200 tick / phút** mọi phút (12 001 tick / 600 s = **20,0 Hz**) | 20,0 Hz |
| `max_drift` | 30 ms phút đầu, **41 ms** từ phút 3 (lúc chạy E2E), sau đó không tăng | 38–59 ms |
| Hàng đợi MapServer / `Mu.Party` / `Mu.Guild` | **0 / 0 / 0** mọi lần đo | 0 / 0 / — |
| RAM VM | 57–62 MB, không tăng dần; state MapServer 161–418 KB; ~590 process | 55–57 MB |
| Snapshot tới bot | p50 100 ms, p99 201 ms, max 600 ms | 100 / 200 / 400 |
| Kết nối | 20/20 online suốt 10 phút, **0** lần WS đóng bất thường | 0 |
| Lệnh | 6 220 `cmd`, **89,5 % ok** (§2.1) | 97,9 % |
| Log server | **0** `[error]`, **0** `[warning]` | 0 / 0 |
| Nhóm | 4 nhóm đủ 5 người suốt 10 phút | như cũ |
| Guild war | 2 guild, **1 war chạy suốt 10 phút** (thêm war của E2E `guildwar` lúc 11:35), 171 lượt bot đánh người, **3 kill tính điểm** (3 bot chết vì người, không ai bị PK) | — |
| Gameplay bot | 195 lần hạ quái, 79 lần chết (60 do Goblin — bot cấp 20 lang thang sát vùng Goblin; 3 do người) | 750 hạ / 40 chết |

### 2.1 Lỗi lệnh (đều đúng luật)

- `INVALID_TARGET` 459: quái / người vừa chết, người guild địch vừa chạy khỏi tầm.
- `FORBIDDEN` 103: đánh người vừa bước vào thị trấn (safe zone), lệnh gửi lúc đang chết.
- `OUT_OF_RANGE` 74, `COOLDOWN` 12, `NOT_OWNER` 2 (nhặt đồ của người khác).
- `RATE_LIMITED` 5: master mời 7 người liền nhau, vượt nhóm `guild` 5 lệnh / giây. Đúng luật
  nhưng làm chỉ 8/13 bot vào guild — **bot đã sửa** mời cách 250 ms (A-6).

Tỉ lệ ok thấp hơn Phase 3 vì bot đánh người: mục tiêu là người chơi di chuyển, uống potion và chạy
vào thị trấn, nên nhiều lệnh bị từ chối đúng luật hơn đánh quái.

## 3. Băng thông

Byte nhận mỗi bot / giây, tính trên tổng 10 phút:

| Nguồn | Bot săn (15) | Bot thị trấn (5) |
|---|---|---|
| `snapshot` | 3,42 KB/s | 4,30 KB/s |
| `party` | 1,19 KB/s | 1,20 KB/s |
| `spawn` + `despawn` | 0,42 KB/s | 0,65 KB/s |
| `combat` | 0,24 KB/s | 0,22 KB/s |
| `guild` + `guild_war` + `guild_invite` | **0,002 KB/s** | 0,000 KB/s |
| **Tổng** | **5,42 KB/s** | **6,45 KB/s** |

Event guild / war rất nhẹ: chỉ đẩy khi có thay đổi (vào / ra, online, điểm). Event `party` vẫn
~1,2 KB/s/bot (B-7, chưa đổi).

## 4. Cân bằng (simulator 20 lần / class, `--monster auto --progress --skills`)

| Class (cộng điểm) | Cấp 10 | Cấp 20 | Cấp 30 | Potion tới cấp 30 | Chết |
|---|---|---|---|---|---|
| DK (balanced) | 32,5 phút | 71,1 phút | 114,5 phút | 331 | 0 |
| DW (ene) | 26,0 phút | 50,5 phút | 72,2 phút | 731 | 0 |
| ELF (agi) | 26,5 phút | 52,5 phút | 76,3 phút | 262 | 0 |
| MG (ene) | 25,2 phút | 48,3 phút | 69,7 phút | 574 | 0 |

**Giống hệt Phase 3** — Phase 4 không đổi công thức PvE.

## 5. Phát hiện khi nghiệm thu và việc chờ anh

### 5.1 Lỗi tìm ra và đã sửa trong P4-M5 (đều ở công cụ test, không phải lỗi game)

| # | Vấn đề | Đã làm |
|---|---|---|
| A-3 | 15 bộ E2E chạy liền nhau đăng nhập > 30 lần / 5 phút từ 127.0.0.1 → `rateLimit.login.perIp` (KB) trả 429, `guild.mjs` không vào được game | Các bộ Phase 4 (`pvp`, `duel`, `guild`, `guildwar`) cho mỗi trình duyệt một `X-Forwarded-For` riêng (như cách đăng ký). Không đổi config |
| A-4 | Chạy cùng soak: bot thị trấn đứng chen ô người cần bấm → `guild.mjs` mở nhầm menu | Bấm lại tối đa 5 lần tới khi đầu menu đúng tên |
| A-5 | Lần soak đầu: bot đánh người cùng nhóm khác guild bị `FORBIDDEN` liên tục (1 224 lỗi); bot cấp 20 chưa cộng điểm nên không giết được ai; bot đuổi địch ra vùng Goblin | Bot bỏ người cùng nhóm, gặp lỗi thì thôi đánh, cộng điểm STR, chỉ đuổi trong dải đường + vùng Spider. Server đúng luật (P4M4-2) |
| A-6 | `RATE_LIMITED` khi master mời liền 7 người | Bot mời cách 250 ms |
| A-7 | Lần soak đầu `smoke` hỏng "nhận EXP" (bot cấp 20 tranh Spider) | Bot war săn ít hơn (40 % thay vì 80 %); lần chạy chính `smoke` 24/24 |

### 5.2 Chờ anh quyết (không chặn nghiệm thu)

| # | Vấn đề | Đề xuất |
|---|---|---|
| B-11 | **KB cần anh bổ sung** (P4-10, em không sửa `docs/kb/`): §5 act `attack p_…`, `duel_*`, `guild_*`, `guild_war_*`; event `duel`, `guild`, `guild_invite`, `guild_war`; `spawn` thêm `pkState` / `aggressor` / `dueling` / `guild`; `player.view.pkPoints / pkState`; join `config.pvp / guild`; §9 bảng `guilds`, `guild_members`; config `pvp`, `pk`, `duel`, `guild`, `guildWar` | Chi tiết ở `OPEN_QUESTIONS` P4M1-4, P4M2-4, P4M3-6, P4M4-5 |
| B-12 | P4M4-1 … P4M4-4 (cấp tối thiểu trong war, cùng nhóm khác guild, tuyên chiến khi master offline, nuôi điểm bằng nick phụ) | Đang làm theo đề xuất; anh xác nhận hoặc đổi |
| B-9 | `CLAUDE.md` quy tắc 3 vẫn ghi "Chỉ làm Phase 1" | Câu đề xuất ở `PHASE4_PLAN.md §0` |
| B-7 | Event `party` ~1,2 KB/s/bot | Như Phase 3 |
| B-10 | Còn mở từ trước: B-2, B-3, B-5, B-6, P3M5-1 | — |

## 6. Chạy lại

```bash
mix test && (cd client && npm test)
TRUSTED_PROXIES=127.0.0.1 elixir --sname mu -S mix phx.server &
SOAK_PARTY=5 SOAK_WAR=1 SOAK_EVENTS=1 node client/e2e/soak.mjs http://localhost:4000 20 10 0.25 &
elixir --sname probe scripts/soak_probe.exs mu@$(hostname -s) 12 60 &
for f in smoke acceptance classes skills maps chat mail_map reconnect warehouse party mg pvp duel guild guildwar; do
  node client/e2e/$f.mjs http://localhost:4000 docs/screenshots
done
for c in "DK --strategy balanced" "DW --strategy ene" "ELF --strategy agi" "MG --strategy ene"; do
  mix mu.simulate --runs 20 --class $c --monster auto --progress --skills
done
```

`smoke`, `acceptance`, `classes` đăng ký từ 127.0.0.1 (giới hạn 5 tài khoản / giờ / IP): chạy lại
lần hai thì khởi động lại server. Các bộ khác dùng `X-Forwarded-For` riêng nên server cần
`TRUSTED_PROXIES`.
