# PHASE5_PLAN — Kế hoạch Phase 5 "Economy" (bước lập kế hoạch, chưa code)

> Scope duy nhất là dòng Phase 5 trong `docs/kb/KB_00_RULES.md §7`:
> **Trading, Jewels, Upgrade, serial/anti-dupe audit.**
> Ràng buộc phụ thuộc (`§7`): Upgrade cần Jewel; Trading cần item serial + ownership validation (đã
> có từ Phase 1). Chaos Machine (Phase 6) cần Upgrade + Jewel, nên Phase 5 phải xong trước.
> Câu hỏi mở ở `docs/OPEN_QUESTIONS.md` mục **P5**. Milestone nào có ⛔ thì chờ anh duyệt bảng đề xuất.

## 0. `CLAUDE.md`

Quy tắc 3 vẫn ghi "Chỉ làm Phase 1" (B-9). Em không tự sửa `CLAUDE.md`. Câu đề xuất (anh sửa hoặc
nói rõ "cho em sửa"):

> 3. **Chỉ làm phase đang mở** (hiện tại: **Phase 5**, `KB_00_RULES §7`). Không thêm tính năng
> `LATER_VERSION` hoặc phase sau, kể cả khi repo nền đã có sẵn.

## 1. KB có gì / thiếu gì

| Hạng mục | KB có | Thiếu / cần anh quyết |
|---|---|---|
| **Jewels** | `KB_ITEM_REFERENCE`: Bless 14/13, Soul 14/14, Life 14/16 là Phase 5; **Creation 14/22 = `LATER_VERSION`**. Group 14 stack được (từng template). `KB_ASSETS §6.2`: "1 jewel" icon là nice-to-have | Jewel rơi từ đâu, tỉ lệ bao nhiêu; có bán ở NPC không, giá bán lại; số stack tối đa (P5-2). Jewel of Life làm gì — cần cột "option" mà §9 **chưa có** (P5-4) |
| **Upgrade** | `KB_CONFIG §5`: bảng +0 → +9 (Bless 100 % tới +6; Soul +7 70 %, +8 60 %, +9 50 %, hỏng thì **giảm 1 cấp**). `onFailure ∈ {DECREASE, UNCHANGED, DESTROY}`. Trên +9 = `LATER_VERSION`. `items.item_level` đã có (§9). Icon theo bucket cấp đã có (`KB_ITEM_REFERENCE §4.2`) | **+N cộng chỉ số bao nhiêu** — KB không có công thức (hiện Engine bỏ qua `item_level`) (P5-3). Thao tác thế nào (kéo jewel lên đồ?), đồ đang mặc có ép được không, có tốn Zen không (P5-3) |
| **Trading** | `KB_TECHNICAL §10`: mỗi trade một process `TradeSettlement` dưới `DynamicSupervisor: Trade`; chỉ khi cả hai confirm mới chạy **một** DB transaction; lock `item_locations` / `items` sắp theo `item_id`, kiểm `version` khi đổi Zen; một bên mất kết nối → hủy ngay. `KB_GAME_DESIGN §17`: hai bên xác nhận, khóa slot, atomic, log đầy đủ | Mời / nhận thế nào, tầm cách, bao nhiêu ô, có trade Zen không, hai bước xác nhận (khóa → chốt), ai không được trade (đang duel, MURDERER…), UI (P5-5) |
| **Serial / anti-dupe audit** | §9: serial ULID unique do server sinh, `item_locations.item_id` PK (một chỗ duy nhất), `item_audit_log` không FK (sống lâu hơn item), orphan dọn mỗi giờ. §10: "audit log mọi chuyển owner → phát hiện dupe". §17: "Theo dõi tổng cung Zen" | **Không có bảng audit Zen** (đã gặp ở P4M3-1). "Audit" cụ thể là kiểm gì, chạy khi nào, báo ai (P5-6) |
| **Mâu thuẫn KB** | `KB_00_RULES` S6: "Wings, Harmony, Guardian, Creation: `LATER_VERSION`, tắt mặc định, **bật ở Phase 5**". `§7` (nguồn duy nhất về scope) đặt Wings ở Phase 6 và Phase 5 không nhắc Harmony / Guardian / Creation; `KB_CONFIG §5` ghi upgrade trên +9 là `LATER_VERSION` | Đề xuất làm theo `§7`: **giữ tắt** cả bốn trong Phase 5 (P5-1) |
| **Protocol** | Chưa có act / event nào cho Phase 5 trong `KB_TECHNICAL §5` | Đề xuất ở P5-7; anh bổ sung KB sau khi chốt |

## 2. Milestone đề xuất

| Milestone | Nội dung | Chặn bởi |
|---|---|---|
| **P5-M1 Jewel + chỉ số theo cấp đồ** ✅ | Template Bless / Soul / Life (stack 20, NPC mua lại 10 000 / 15 000 / 15 000). Nhóm drop `jewels` 0,6 % cho quái cấp ≥ 10. Engine cộng chỉ số theo `item_level` (vũ khí +3 đòn, giáp +3 / khiên +2 thủ mỗi cấp). Tooltip / tên / ô đồ hiện "+N". Simulator: 5,0–5,3 jewel / giờ (DK 2,6) (DEC-140 … DEC-144). Không chạy E2E (chạy ở M2) | xong |
| **P5-M2 Upgrade** ✅ | Ép Bless / Soul theo bảng `KB_CONFIG §5`, Jewel of Life (cột `option_level`, +4 / cấp, tối đa 4) — một transaction, audit `UPGRADE` / `JEWEL_USE`; kéo jewel thả lên đồ hoặc [Ép lên…] (mobile); event `upgrade`; SYSTEM cả map khi lên +7 trở lên (DEC-145 … DEC-148). E2E `upgrade.mjs` viết sẵn, **chạy ở P5-M5** (DEC-149) | xong |
| **P5-M3 Audit Zen + anti-dupe** ✅ | Bảng `zen_audit_log` (+ `BASELINE`), ghi trong cùng transaction mọi đổi Zen (`BUY`, `SELL`, `MAIL`, `MONSTER`, `GUILD_CREATE`, `START`, `ADMIN`); `mix mu.audit` (serial trùng, item không chỗ, chủ lệch audit, Zen lệch log, cung Zen theo ngày, exit 1 khi sai lệch); test bán / ép song song chỉ một lần thành công (DEC-150 … DEC-153) | xong |
| **P5-M4 Trading** ✅ | `Mu.Trade` + `TradeSettlement` (1 process / giao dịch) theo KB §10: mời / nhận / từ chối (30 s, ≤ 5 ô), bàn tối đa 16 món + Zen, [Khóa] → [Đồng ý], mọi thay đổi bỏ khóa; chốt một transaction khóa theo id, audit `TRADE` đồ + Zen; chốt hỏng giữ giao dịch mở; hủy khi xa > 10 ô / đổi map / chết / mất kết nối / 3 phút; test cố dupe (chốt song song với bán) (DEC-154 … DEC-159). E2E `trade.mjs` viết sẵn, **chạy ở P5-M5** | xong |
| **P5-M5 Nghiệm thu Phase 5** | Danh sách nghiệm thu (P5-9, em soạn), toàn bộ E2E, soak có trade / upgrade, `mix mu.audit` sạch sau soak, báo cáo | P5-9 |

Thứ tự: P5-M1 → P5-M2 → P5-M3 → P5-M4 → P5-M5. Audit Zen làm **trước** Trading để trade ghi audit
ngay từ đầu.

## 3. Thiết kế kỹ thuật dự kiến (không đổi gameplay, để anh nắm)

- **Upgrade** là hàm thuần `Mu.Game.Upgrade` (bảng `KB_CONFIG §5`, RNG có seed, test từng dòng
  bảng). Session gọi, `Mu.Game.Items` làm transaction (khóa nhân vật như mọi thao tác item).
- **Chỉ số theo +N**: Engine đọc hệ số từ config (`items.levelBonus`, P5-3); không hard-code.
- **Trading** theo đúng `KB_TECHNICAL §10`: state chỉ trong `TradeSettlement`, Session hai bên
  không giữ state trade; Session tắt / mất kết nối → monitor → hủy trade ngay. Chốt trade khóa
  item theo thứ tự `item_id`, kiểm từng món vẫn ở đúng chỗ đã khóa, kiểm chỗ trống túi bên nhận,
  đổi Zen kèm `version` hai nhân vật — sai bất kỳ điểm nào thì rollback, báo hai bên.
- **Item đang trade** không bị khóa trong DB (KB không có location `TRADE`); nếu chủ di chuyển /
  vứt / bán món đã đặt lên bàn thì `TradeSettlement` gỡ món đó và **bỏ xác nhận** của cả hai bên.
- **Audit Zen** ghi trong cùng transaction với thay đổi Zen (không ghi riêng sau).
- **AOI, Party, Guild** không đổi.

## 4. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Dupe qua trade (hai tab, mất kết nối đúng lúc chốt, đồ đổi chỗ giữa khóa và chốt) | Một transaction, lock theo `item_id`, kiểm lại vị trí lúc chốt, `item_locations.item_id` PK; test song song có chủ đích; `mix mu.audit` sau soak |
| Lạm phát đồ +N làm lệch cân bằng PvE / PvP | Jewel hiếm (P5-2); simulator đo thời gian lên cấp khi có đồ +N; sát thương PvP vẫn × 0,5 |
| Lừa đảo khi trade (đổi món phút chót) | Thêm / bớt món → bỏ xác nhận cả hai; bước "khóa" rồi mới "chốt"; hiện rõ +N trên cả hai bàn |
| Audit Zen làm chậm thao tác item | Một `INSERT` trong transaction có sẵn; đo bằng soak |
