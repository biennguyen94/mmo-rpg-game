# Câu hỏi đang chờ anh — Hắc Long

> Câu hỏi ảnh hưởng cân bằng, dữ liệu lưu, giao thức hoặc cách chơi mà em không tự chốt. Anh trả lời xong thì em chuyển
> câu đó xuống mục **Đã chốt** (ghi ngày + câu trả lời) và làm theo.
> Câu hỏi thiết kế chi tiết của từng phase vẫn ghi ở `INTEGRATION_PLAN.md` / `PHASE_PLAN.md`; file này gom lại để dễ theo dõi.

## Đang chờ

| # | Phase | Câu hỏi | Đề xuất của em |
|---|---|---|---|
| 10-A … 10-D | 6 | Ghép đồ từ Item.txt vào game (chọn món cho vùng / cửa hàng, giá, yêu cầu chỉ số) — `INTEGRATION_PLAN.md §10` | Chờ anh gửi Item.txt rồi chốt |
| KD-1 | Kho Đồ | Tiên Nữ **bậc 9 không có bộ giáp** (bậc 8 Linh Hồn Đỏ cấp 32 → bậc 10 Tia Tiên cấp 48) và **bậc 10 chỉ có Chùy Băng Giá**, không có cung / nỏ (dữ liệu Item.txt đang chọn). Bổ sung thế nào? | Anh chọn món trong Item.txt (bộ giáp Tiên Nữ khoảng cấp 40, một cung / nỏ cấp ~42–48); em không tự thêm |
| 15f-A | 15f | Trái Cây kiểu MU (dùng → +điểm tiềm năng vĩnh viễn, có trần mỗi nhân vật) cần thêm cột `fruits` vào bảng `characters` (migration). Có làm không? | Làm: Máy Hỗn Nguyên ra Trái Cây (1 Hỗn Nguyên + 1 Ước Nguyện + 1 Tâm Linh), mỗi trái +2 điểm, tối đa 20 trái |
| DS-6 | Đánh người | Đã làm bước 1, 2a, 2b, (c) `pvp.heal_mult` 0.5. (d) `scripts/pvp/tune.exs` tự chỉnh `class_taken` trên đồ giống nhau theo mốc (thắng gộp = 2/3 đồ sát có bình + 1/3 PK cược, N=24/cặp, kiểm lại trên seed khác N=48). Bảng hiện tại (dk 1.08 / dw 0.86 / elf 1.06 / mg 0.75) lệch tối đa 30–49% mỗi mốc. **Một bộ chung tốt nhất** (dk 1.07 dw 0.79 elf 1.02 mg 0.86) vẫn lệch TB 34% (21–44%). **Gộp 4 nhóm mốc** (0–3, 4–5, 6–8, 9–10) lệch TB 20%, tối đa 38%. **Bảng riêng từng mốc** lệch 3–7% (seed mới): r0 0.99/0.85/0.97/0.90, r1 1.01/0.85/0.99/0.88, r2 0.96/0.82/1.06/0.88, r3 0.97/0.83/1.11/0.82, r4 1.20/0.74/1.13/0.73, r5 1.21/0.76/1.12/0.72, r6 1.08/0.69/0.98/1.00, r7 1.10/0.68/0.97/1.01, r8 1.15/0.72/0.98/0.91, r9 1.39/0.63/1.06/0.80, r10 1.16/0.85/0.91/0.82 (dk/dw/elf/mg). Lưu ý: (1) cùng một bảng, đồ sát và PK cược vẫn lệch nhau (vd r4 Kiếm Sĩ 28% / 75%, r6 Phù Thủy 66% / 22%) — muốn cân cả hai phải có bảng riêng mỗi chế độ; (2) đồ giống hệt nhau nên trận gần như tất định, tỉ lệ thắng nhảy rất mạnh theo hệ số (Đấu Sĩ 0.75 → 99%, 0.97 → 19%), người thật đồ khác nhau nên con số theo mốc chỉ là hướng. | Anh chọn: (A) bảng `class_taken` theo số lần chuyển sinh của người bị đánh (11 dòng trên), (B) A + tách đồ sát / PK cược, (C) một bộ chung (dk 1.07 dw 0.79 elf 1.02 mg 0.86), hoặc giữ bảng hiện tại |

## Đã chốt

| # | Ngày | Câu hỏi | Trả lời |
|---|---|---|---|
| B41-A | 2026-10-24 | Cầm 2 vũ khí 1 tay: lớp nào, sát thương tính thế nào? | Kiếm Sĩ, Phù Thủy, Đấu Sĩ; cộng thẳng 2 vũ khí (k = 1), đo rồi mới quyết (DECISIONS B-42) |
| 9-A | 2026-10-04 | Dịch tin từ server tới đâu? | Giao diện + dữ liệu + tin hay gặp trước, tin hiếm làm dần |
| 9-B | 2026-10-04 | 20 bản đồ mới đặt ở đâu? | Bản đồ phụ, cổng vào từ các bản đồ hiện có, cấp 1–50 rải đều, **không liên quan Hắc Long** |
| 9-C | 2026-10-04 | Giá dịch chuyển? | 20 + 4 × cấp quái thấp nhất; Làng / Nhà miễn phí; đá dịch chuyển vẫn miễn phí |
| 9-D, 9-E | 2026-10-04 | Phím Menu; thứ tự làm | Tab; sửa B1, B2 → Phase 9 → Phase 10 → Phase 6 |
| 7-A | 2026-10-04 | Lịch Golden Invasion? | Mỗi 2 giờ (0h, 2h, 4h… giờ Việt Nam), 15 phút |
| 7-B | 2026-10-04 | Trùm vàng cuối đợt? | Có: hạ hết quái vàng một bản đồ thì trùm vàng vùng đó xuất hiện |
| 5-C, 5-D | 2026-10-04 | Giới hạn PK cược vàng? | Cược 100 – 1 000 000, **không phí**, **không giới hạn chênh cấp**, 10 trận cược / ngày |
| 5-G | 2026-10-04 | Trận cược đánh thế nào? | Tự đánh giữa hai bản sao, xong ngay |
| 5-E | 2026-10-04 | Thưởng chiến bang? | Quỹ bang thắng +5 000; thành viên có ≥ 1 điểm nhận 500 vàng qua thư |
| 5-F, 5-H, 5-I, 6-A | 2026-10-04 | Tổ đội, `/w`, thư hết hạn, bảng theo lớp | Giữ × 1,2 / n; `/w` chỉ bạn bè; thư còn quà không hết hạn; top 50, 60 s |
| 4-A | 2026-10-04 | Ép ngọc ở đâu? | Vẫn cạnh Thợ Rèn (nút Ép trong tooltip chọn món) |
| 4-B | 2026-10-04 | Tủ Đồ ở Nhà chứa bao nhiêu? | 40 loại đồ thường + 20 đồ hiếm; mở rộng +10 đồ hiếm × 3 lần (5 000 / 15 000 / 40 000 vàng) |
| 4-C | 2026-10-04 | Trần mỗi thư quản trị? | 1 000 000 vàng, 1 000 000 EXP |
| 4-D, 4-F | 2026-10-04 | Ngọc Sinh Mệnh lên cánh? Tỉ lệ rơi? | Cánh **được**; trọng số **10** trong bảng ngọc |
| 4-E | 2026-10-04 | Tách chồng? | **Không làm** |
| 3-A … 3-D | 2026-10-04 | Công thức chiến đấu (`INTEGRATION_PLAN §11.5`) | Theo đề xuất: trúng chỉ khi người đánh quái, sàn mềm 20 %, phạt EXP chỉ quái thường, công ±10 % |
| 3-E | 2026-10-04 | Kỹ năng có thể trượt không? | **Không**: kỹ năng luôn trúng |
| P1-Q1 | 2026-10-04 | Danh sách từ cấm cơ bản em lập có cần thêm / bớt? | OK, giữ nguyên |
| P1-Q2 | 2026-10-04 | Công cụ quản trị đổi tên nhân vật / bang? | Không cần |
| 5-A | 2026-10-04 | Soak: bao nhiêu bot, bao lâu? | Theo đề xuất (anh bảo làm hết Phase 2): 30 bot / 10 phút chạy tay; CI tự chạy 10 bot / 2 phút |
| 5-B | 2026-10-04 | e2e chạy trên CI khi nào? | Theo đề xuất: chỉ khi sửa `reference/rpg-game/**` (workflow riêng `hac-long-e2e.yml`) |
| 1-A | 2026-10-04 | Danh sách từ cấm: anh gửi hay em lập? | Em lập danh sách cơ bản |
| 1-B | 2026-10-04 | Tách `priv/game_data.json` thành thư mục `priv/game_data/`? | Đồng ý |
| H7/H8, C15, D4, M7 | 2026-10-04 | Xem `FEATURE_CATALOG.md` mục "Kiểm tra lựa chọn của anh" | Đồng ý tất cả |
