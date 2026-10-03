# PHASE3_PLAN — Kế hoạch Phase 3 "Multiplayer" (bước lập kế hoạch, chưa code)

> Scope duy nhất: `docs/kb/KB_00_RULES.md §7` dòng Phase 3:
> **AOI (tối ưu băng thông cho nhiều người), reconnect giữa phiên, Party, Warehouse, MG.**
> Câu hỏi mở: `docs/OPEN_QUESTIONS.md` mục **P3**. Milestone nào bị chặn (⛔) thì chờ anh trả lời;
> milestone không bị chặn em có thể làm ngay khi anh "OK".

## 0. `CLAUDE.md`

Quy tắc 3 vẫn ghi "Chỉ làm Phase 1". Đề xuất (anh duyệt hoặc tự sửa; em không sửa):

> 3. **Chỉ làm phase đang mở** (hiện tại: **Phase 3**, `KB_00_RULES §7`). Không thêm tính năng
> `LATER_VERSION` hoặc phase sau, kể cả khi repo nền đã có sẵn.

## 1. KB có gì / thiếu gì

| Hạng mục | KB có | Thiếu / mâu thuẫn |
|---|---|---|
| **AOI** | `KB_TECHNICAL §3`: lưới `aoiCellSize` 16 ô, nhìn ô mình + `aoiViewCells` 1 ô quanh; vào / ra tầm nhìn = `spawn` / `despawn`; delta theo AOI; "bắt buộc từ Phase 3". Config đã có `server.aoiCellSize`, `aoiViewCells` | Không thiếu số. Việc kỹ thuật: MapServer gửi riêng từng người thay cho broadcast cả map |
| **Reconnect** | `KB_TECHNICAL §4`: mất kết nối giữ nhân vật `reconnectGraceSeconds` (30, đã có trong config), vẫn bị đánh; về trong hạn thì khôi phục | Hiện tại tab cuối đóng là rời map ngay (hoặc sau 10 s nếu đang combat) → đổi theo §4. Không thiếu số |
| **Warehouse** | Schema §9 đã có location `WAREHOUSE` (`account_id`, ô 0–119), `KB_CONFIG §6` "15×8, account-wide"; protocol `move_item {itemId, to: {location, slot}}` | ⛔ Chưa có UI (§19 không vẽ), NPC nào mở kho, có cất Zen / phí không (P3-6) |
| **Party** | `KB_GAME_DESIGN §12`: Create, Invite, Accept, Leave, Kick, Disband; tối đa `maxPartySize` 5; chia EXP trong `partyRange`; đồng bộ HP + vị trí; chat party. §3: EXP chia theo số người + `partyBonus` mỗi người. §10: loot protect cho cả party. `KB_CONFIG`: `party {maxSize 5, expRange 20}`, `partyBonusPerMember 0.1` | ⛔ Act / event party **chưa có trong `KB_TECHNICAL §5`**; công thức chia EXP chi tiết; UI party (§19 không vẽ) (P3-5) |
| **MG** | `KB_GAME_DESIGN §2`: mở khi tài khoản có nhân vật đạt `mg.unlockLevel` (220), 7 stat / cấp, stat khởi điểm 26, không đội mũ; `KB_CONFIG §2` chỉ số MG; §4.1 `attackPowerMagic` / `attackSpeedMagic`; `account.maxCharacters` 4 khi bật MG (Q13) | ⛔ **Mâu thuẫn:** `maxLevel` hiện 30 → không ai đạt 220, MG không bao giờ mở (P3-2). Chưa có skill MG; chưa có màn chọn nhiều nhân vật (P3-3, P3-4) |

## 2. Milestone đề xuất

| Milestone | Nội dung | Chặn bởi |
|---|---|---|
| **P3-M1 AOI** ✅ | Kênh giữ tầm nhìn từng người (`MuWeb.Aoi`, ô 16×16, nhìn 3×3 ô; DEC-84); `spawn` / `despawn` khi vào / ra tầm nhìn; snapshot / combat lọc theo tầm nhìn; NORMAL chat vẫn cả map (P3-7). Soak 20 bot × 2 phút (nửa ở thị trấn): 6,56 → 5,21 KB/s/bot (−21 %; `combat` −80 %); cả 20 bot cùng vùng: 6,17 → 5,88 (−5 %) (map 64×64 chỉ 4×4 ô, P3M1-1) | xong |
| **P3-M2 Reconnect giữa phiên** | Mất kết nối: nhân vật ở lại map `reconnectGraceSeconds` (30 s), vẫn bị đánh; vào lại trong hạn thì giữ nguyên trạng thái (vị trí, HP/MP, buff, tự đánh dừng); quá hạn thì rời map + lưu. Client đã có tự kết nối lại | không — làm được ngay |
| **P3-M3 Warehouse** | Kho 120 ô dùng chung cho mọi nhân vật của tài khoản; NPC giữ kho; panel kho + túi; gửi / rút bằng `move_item` (1 transaction, audit) | ⛔ P3-6 |
| **P3-M4 Party** | Lập nhóm / mời / nhận / rời / đuổi / giải tán; chia EXP + bonus; loot protect cho cả nhóm; khung thành viên (HP, map); chat PARTY bật | ⛔ P3-5 (protocol + UI + công thức) |
| **P3-M5 Nhiều nhân vật + MG** | `account.maxCharacters` 4, màn chọn / tạo nhân vật; MG mở theo điều kiện; MG chỉ số 26 / 7 stat, không đội mũ, chỉ số phép | ⛔ P3-2, P3-3, P3-4 |
| **P3-M6 Nghiệm thu Phase 3** | Danh sách nghiệm thu P3 (em soạn), e2e, soak nhiều người (đo AOI), báo cáo | danh sách P3-9 |

Thứ tự gợi ý: **P3-M1 → P3-M2** (kỹ thuật, không chờ dữ liệu) trong khi anh trả lời P3-2 … P3-6.

## 3. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| AOI đổi cách gửi sự kiện (broadcast → từng người) dễ sót `spawn` / `despawn` | Test thuần cho phép tính ô / tầm nhìn; test kênh "đi ra khỏi tầm nhìn → despawn, quay lại → spawn"; chạy lại toàn bộ e2e |
| Reconnect giữ nhân vật 30 s → nhân vật có thể chết khi mất mạng | Đúng §4 ("vẫn có thể bị tấn công"); báo rõ trong thông báo khi vào lại |
| Party + AOI: thành viên ngoài tầm nhìn vẫn cần HP / vị trí | Event `party` riêng (không qua snapshot), tần suất thấp |
| MG mở ở cấp 220 không đạt được | Chờ anh chọn P3-2 |
