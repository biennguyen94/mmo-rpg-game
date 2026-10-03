# ACCEPTANCE_PHASE5_6 — Nghiệm thu chung Phase 5 "Economy" + Phase 6 "Advanced" (P6-M6)

> **Danh sách nghiệm thu = P5-9 + P6-9.** Anh chọn (A) gộp nghiệm thu Phase 5 vào cuối Phase 6
> (DEC-160) và cho làm liền P6-M1 → M5 theo đề xuất, không chạy E2E giữa chừng (DEC-162).
> Scope theo `KB_00_RULES §7`:
> - Phase 5: Upgrade, Jewel, serial / anti-dupe audit, Trading.
> - Phase 6: Quest, Chaos Machine, Wings, Events, Bosses, Ranking.
>
> Chạy ngày 2026-10-03, môi trường Claude Code cloud (Elixir 1.17.3 / OTP 25, Postgres 16, Chromium).
>
> Bằng chứng gồm 3 lớp như Phase 1–4:
> - **ExUnit:** `mix test` 376 test, 0 lỗi (1 skip có sẵn). Trong 6 lần chạy có **1 lần 1 test
>   lỗi ngẫu nhiên**; lần đó không lưu tên test, 5 lần chạy lại đều xanh (xem §5). Test client
>   `npm test` 26 / 26.
> - **E2E:** **21 bộ / 261 mục**, tất cả PASS (§3). Thêm 4 bộ mới: `quest`, `chaos`, `events`,
>   `ranking`. `upgrade` / `trade` đã có từ Phase 5.
> - **Soak:** 20 bot × 15 phút. Bot có nhóm, guild war, quest, ép đồ, giao dịch; world boss và
>   Golden Invasion bật (§2).

## 1. Danh sách nghiệm thu và kết quả

### Phase 5 (P5-9)

| # | Mục | Kết quả | Bằng chứng |
|---|---|---|---|
| 1 | **Jewel** (P5-2): Bless / Soul / Life (+ Chaos ở P6) stack 20, NPC mua lại; rơi 0,6 % từ quái cấp ≥ 10 (Bless 45 / Soul 30 / Life 12 / Chaos 13) | ✅ PASS | ExUnit `drops_test` (200 000 lần roll), `item_import_test`. Simulator 2,5–3,5 jewel / giờ (§4) |
| 2 | **Upgrade** (P5-3, P5-4, `KB_CONFIG §5`): +0 → +6 Bless 100 %, +6 → +9 Soul 70 / 60 / 50 % (hỏng giảm 1 cấp), Life +option (50 %, tối đa 4); một transaction, audit; báo SYSTEM từ +7 | ✅ PASS | ExUnit `upgrade_test`, kênh. E2E `upgrade.mjs` 10/10. Soak: **125 lần ép, 111 thành công** |
| 3 | **Serial / anti-dupe audit** (P5-6): `zen_audit_log` ghi trong cùng transaction mọi đổi Zen; `mix mu.audit` kiểm serial trùng, orphan, chủ vs audit, Zen vs log | ✅ PASS | **`mix mu.audit` sau soak + toàn bộ E2E: "Không có sai lệch"** trên 1 411 nhân vật, Zen 2 843 043. Đã đủ các lý do Zen: ADMIN, BASELINE, BUY, CHAOS, GUILD_CREATE, MAIL, MONSTER, QUEST, SELL, TRADE. ExUnit cố dupe song song (`audit_test`: bán / ép song song; `trade_channel_test`: chốt giao dịch song song với bán) |
| 4 | **Trading** (P5-5, `KB_TECHNICAL §10`): mời / nhận / từ chối, bàn 16 món + Zen, khóa → đồng ý, chốt một transaction; hủy khi xa / đổi map / chết / mất kết nối | ✅ PASS | ExUnit `trade_channel_test` 6. E2E `trade.mjs` 12/12. Soak: **35 lần mời, 5 lần chốt** (các lần còn lại bị hủy đúng luật: bot chưa tới chỗ, quá 8 s thì bot tự hủy) |

### Phase 6 (P6-9)

| # | Mục | Kết quả | Bằng chứng |
|---|---|---|---|
| 5 | **Ranking** (P6-7): bảng cấp (tất cả + 4 class), bảng guild; top 50; cache 5 phút; hạng của mình | ✅ PASS | ExUnit `ranking_channel_test`. E2E `ranking.mjs` 6/6. Ảnh `p6-ranking.png` |
| 6 | **Quest** (P6-2): bảng `character_quests` (migration có CHANGE_REASON); 10 quest; Quest Master ở Lorencia + Noria; mục tiêu kill / collect / level; trả quest một transaction (EXP, Zen + đồ audit `QUEST`); tối đa 5 quest; bỏ quest | ✅ PASS | ExUnit `quests_test` 5, `quest_channel_test` 4 (thưởng, `rid` trả lại, nộp nhiều stack, xa NPC, đủ 5, tiến độ còn sau khi tắt Session). E2E `quest.mjs` 13/13. Soak: 27 lần nhận, 1 lần trả. Ảnh `p6-quest-master.png`, `p6-quest-panel.png` |
| 7 | **Chaos Machine** (P6-3): Jewel of Chaos; Chaos Goblin (Noria); xem trước công thức / tỉ lệ / phí; tạo cánh = đồ +4↑ + Chaos + 20 000 Zen, 10 % + 5 % / cấp (+2 % / option); thất bại mất đầu vào; một transaction, audit `CHAOS_IN` / `CHAOS_OUT` | ✅ PASS | ExUnit `chaos_wings_test` (khớp, tỉ lệ, RNG seed ra đều 3 cánh), `chaos_channel_test` 4. E2E `chaos.mjs` 9/9. Ảnh `p6-chaos-machine.png` |
| 8 | **Wings** (P6-4): 3 cánh cấp 1 (Elf / Heaven / Satan), cấp 15, ô cánh mở; +12 % sát thương, −12 % sát thương nhận, thủ 10; +N thêm 2 % / 2 % / 1; không ép Life; vẽ cánh hình học; người khác thấy cánh | ✅ PASS | ExUnit (pipeline sát thương, leveled, Upgrade từ chối Life, mặc cần cấp 15 + đúng class, spawn có `wing`). E2E `chaos.mjs` (mặc cánh, `wing` trên spawn). Simulator: cánh giảm sát thương nhận. Ảnh `p6-wings.png` |
| 9 | **Events — Golden Invasion** (P6-5): mỗi 3 giờ UTC, 15 phút; 8 quái vàng Lorencia + 8 Noria (× 5, jewel 10 %); SYSTEM báo trước 5 phút / bắt đầu / kết thúc; `mix mu.event` | ✅ PASS | ExUnit `world_events_test` (lịch + đồng hồ giả, qua ngày), `boss_test` (sinh / thu, không hồi sinh). E2E `events.mjs` (bật / tắt bằng lệnh quản trị, thanh event, SYSTEM). Soak: chạy suốt 15 phút, **45 bot chết vì Golden Goblin** (bot săn đi lạc sang Noria) |
| 10 | **Boss** (P6-6): Bull Fighter Lord (HP 20 000), đánh vùng bán kính 2 tối đa 6 người mỗi 3 s; chia EXP 6 000 / Zen 30 000 theo sát thương (≥ 1 %); top 3 có jewel riêng; hết 20 phút thì biến mất; người vào giữa event vẫn thấy | ✅ PASS | ExUnit `boss_test` (đúng 6 người trúng, nhịp 3 s, chia thưởng, d < 1 % không có phần, jewel có chủ). E2E `events.mjs` 12/12. Soak: boss sống suốt event, bot đánh 33 đòn, 2 bot chết vì boss. Ảnh `p6-world-boss.png` |
| 11 | **Protocol / server-authoritative** (P6-8): act mới (`ranking`, `quest_*`, `chaos_*`) kiểm ở server, có nhóm rate-limit; client chỉ gửi ý định | ✅ PASS | `config_test` (mọi act có nhóm rate-limit). Kiểm lỗi `FORBIDDEN` / `INVALID_TARGET` / `OUT_OF_RANGE` / `REQUIREMENT_NOT_MET` / `NOT_ENOUGH_ZEN` / `NOT_OWNER` |
| 12 | **DB**: Phase 5–6 thêm `items.option_level`, `zen_audit_log`, `character_quests` — mỗi migration có CHANGE_REASON | ✅ PASS | `priv/repo/migrations/2026100[678]*` |
| 13 | **Tải**: 20 người chơi 15 phút có mọi tính năng mới, cùng lúc chạy E2E | ✅ PASS | §2 |
| 14 | **Không hồi quy Phase 1–4** | ✅ PASS | 17 bộ cũ PASS (§3). Simulator như Phase 4 (§4) |
| 15 | **Asset**: không file MU-derived trong git; NPC / quái mới dùng lại file DCSS đã có (`mapping.json`, `CREDITS.md`) | ✅ PASS | `git ls-files`: 0 file `assets_src/private`, `icons/items`, `icon_map.json` |
| 16 | **UI desktop + mobile** cho panel Nhiệm vụ / Chaos Machine / Xếp hạng, thanh event, cánh | ⚠️ PASS tự động, **cần anh xem bằng mắt ở local** | E2E desktop 1280px; ảnh `p6-*.png` |

## 2. Soak test (20 bot × 15 phút)

**Thiết lập:**
- Server: `TRUSTED_PROXIES=127.0.0.1 elixir --sname mu -S mix phx.server`.
- Lệnh soak: `SOAK_PARTY=5 SOAK_WAR=1 SOAK_P56=1 SOAK_BOSS=1 SOAK_EVENTS=1 node client/e2e/soak.mjs … 20 15 0.25`.
- Mọi bot lên cấp 20, có 20 000 Zen, khiên + 6 Bless + 3 Soul (`scripts/e2e_soak_seed.exs … p56`).
- 5 bot ở thị trấn. 15 bot săn:
  - chia 2 guild đánh guild war, lập 4 nhóm × 5 người;
  - nhận / trả quest ở Quest Master, ép jewel lên khiên mỗi ~90 s;
  - từng cặp bot giao dịch Zen ở phút 1,5 / 4,5 / 7,5 / ….
- Phút 1: bật world boss + Golden Invasion bằng `mix mu.event`.
- Probe mỗi phút (`scripts/soak_probe.exs`). Probe nay đo thêm Noria, hàng đợi `Mu.WorldEvents`
  và số giao dịch đang mở.
- Trong 6 phút đầu chạy kèm 7 bộ E2E.

| Chỉ số | Phase 5 + 6 | Phase 4 (để so) |
|---|---|---|
| Nhịp mô phỏng | 1 200 tick / phút mọi phút (20,0 Hz). Tick thiếu so với uptime VM ổn định 18–19 (lúc khởi động) | 20,0 Hz |
| `max_drift` Lorencia / Noria | 35 ms trong 7 phút đầu (có E2E, boss, quái vàng), **93 ms** lớn nhất trong cả 15 phút | 41 ms |
| Hàng đợi MapServer / Party / Guild / WorldEvents | **0 / 0 / 0 / 0** mọi lần đo | 0 / 0 / 0 |
| RAM VM | 59–64 MB, không tăng dần; khoảng 600 process | 57–62 MB |
| Snapshot tới bot | p50 100 ms, p99 201 ms, max 699 ms | 100 / 201 / 600 |
| Kết nối | 20/20 online suốt 15 phút, **0** lần WS đóng bất thường (19 lần đóng ở cuối là bot tự thoát) | 0 |
| Lệnh | 8 602 `cmd`, **83,4 % ok** (§2.1) | 89,5 % |
| Phase 5 / 6 | 125 lần ép (111 thành công), 27 lần nhận quest / 1 lần trả, 35 lần mời giao dịch / 5 lần chốt, 33 đòn vào boss, world_event tới mọi bot | — |
| Băng thông (trung bình mọi bot) | 5,1 KB/s/bot (16,4 tin/s) | 5,4 KB/s bot săn / 6,5 KB/s bot thị trấn |

### 2.1 Lỗi lệnh

Các mã lỗi bên dưới đều đúng luật:

- `INVALID_TARGET` 1 047: quái / người vừa chết; bot đánh xác quái vàng chưa bị thu.
- `FORBIDDEN` 235: đánh người cùng nhóm / trong safe zone; giao dịch khi bên kia đang giao dịch.
- `RATE_LIMITED` 64: bot giao dịch gửi `trade_zen` / `trade_lock` / `trade_confirm` liền nhau.
- Còn lại: `OUT_OF_RANGE` 69, `COOLDOWN` 13, `NOT_OWNER` 4 (đồ vừa bị ép hỏng / đã giao dịch).

Tỉ lệ ok thấp hơn Phase 4 vì bot thêm việc mới; không có lỗi phía server.

### 2.2 Không có

**Log server của lần soak này không được giữ lại.** Worker của phiên làm việc khởi động lại sau
khi soak xong (16:44). Lần chạy server sau ghi đè log, nên em không có số `[error]` / `[warning]`
của lần soak. Lần chạy lại toàn bộ 21 bộ E2E sau đó có **0 `[error]`, 0 `[warning]`**.

## 3. E2E (21 bộ)

**17 bộ cũ (Phase 1–4):**

| Bộ | Kết quả | Bộ | Kết quả | Bộ | Kết quả |
|---|---|---|---|---|---|
| smoke | 24/24 | acceptance | 24/24 | classes | 6/6 |
| skills | 7/7 | maps | 8/8 | chat | 7/7 |
| mail_map | 10/10 | reconnect | 11/11 | warehouse | 12/12 |
| party | 13/13 | mg | 12/12 | pvp | 14/14 |
| duel | 14/14 | guild | 24/24 | guildwar | 13/13 |
| upgrade | 10/10 | trade | 12/12 | | |

**4 bộ mới (Phase 6):** ranking 6/6, quest 13/13, chaos 9/9, events 12/12.

**Lỗi tìm ra khi chạy và đã sửa:**

- **Quest:** tên mục tiêu kill không gửi cho client (dòng theo dõi hiện "spider" thay vì "Spider").
  Đã sửa và thêm test.
- **Chaos Machine:** lưới đồ phóng icon hết khung (cùng lỗi panel giao dịch trước đây). Đã sửa CSS.
- **Vị trí boss:** boss lúc đầu đặt cạnh đường ra cổng đông. Vùng aggro 6 ô trùm đường, giết người
  chơi cấp thấp đi ngang. Lỗi này lộ ra khi `pvp.mjs` chạy trong lúc soak: B bị boss giết, không
  phải A giết. Đã dời boss xuống mép nam bãi Spider (DEC-174).
- **Test cũ:**
  - `maps.mjs` đếm cứng số NPC và danh sách quái; đã cập nhật cho NPC / quái mới.
  - `party.mjs` có đua thời gian khi đọc khung nhóm bên kia; đã sửa để chờ.
  - `smoke.mjs` mobile bị chặn tap một lần lúc tải nặng; chạy lại PASS.
- **Sự cố khi nghiệm thu (lỗi thao tác của em, không phải lỗi game):** em sửa `config.json` lúc
  server dev đang chạy. Sau đó e2e gọi `mix run`, biên dịch lại vào cùng `_build` → server dev mất
  module và tắt. Em đã chạy lại toàn bộ từ đầu.

## 4. Simulator

`mix mu.simulate --monster auto --progress --skills --runs 20`, cùng cách cộng điểm như Phase 4.

| Class (cộng điểm) | Cấp 10 | Cấp 20 | Cấp 30 | Potion tới cấp 30 | Chết | Jewel / giờ | Phase 4 (cấp 10 / 20 / 30) |
|---|---|---|---|---|---|---|---|
| DK (balanced) | 32,5 phút | 71,2 phút | 114,3 phút | 331 | 0 | 1,81 | 32,5 / 71,1 / 114,5 |
| DW (ene) | 26,0 phút | 50,4 phút | 71,8 phút | 723 | 0 | 3,26 | 26,0 / 50,5 / 72,2 |
| ELF (agi) | 26,5 phút | 52,4 phút | 76,1 phút | 260 | 0 | 3,47 | 26,5 / 52,5 / 76,3 |
| MG (ene) | 25,2 phút | 48,3 phút | 69,6 phút | 574 | 0 | 3,19 | 25,2 / 48,3 / 69,7 |

**Như Phase 4** (lệch ≤ 0,4 phút do jewel / Chaos rơi làm đổi thứ tự RNG) — Phase 5–6 không đổi
công thức PvE thường. Quest / boss / Golden Invasion là nguồn EXP thêm, simulator chưa tính.
Mặc định (Spider, không trang bị) vẫn 1 111 con / 130 phút tới cấp 10. Cánh: `chaos_wings_test` so
bộ t1 với t1 + cánh — sát thương nhận / con không tăng.

## 5. Còn lại / cần anh

1. **Test ExUnit lỗi ngẫu nhiên:** 1 lần trong 6 lần chạy `mix test`. Em chưa xác định được test
   nào vì lần đó không in tên; 5 lần sau đều 376 / 0. Em ghi P6M6-1 để theo dõi.
2. **Cần anh xem bằng mắt (§1 mục 16):**
   - cánh vẽ hình học;
   - boss to 1,5 lần;
   - thanh event;
   - cửa sổ Chaos Machine và panel Nhiệm vụ trên mobile.
3. **Số do em tự đặt** (anh duyệt hoặc sửa trong data):
   - giá NPC mua cánh 50 000;
   - attackRate / defenseRate / tốc độ của boss;
   - vị trí boss / quái vàng;
   - 10 quest (`quests.json`).
4. **`CLAUDE.md` quy tắc 3 vẫn ghi "Chỉ làm Phase 1"** (B-9). Em không tự sửa; câu đề xuất ở
   `docs/PHASE6_PLAN.md §0`.
