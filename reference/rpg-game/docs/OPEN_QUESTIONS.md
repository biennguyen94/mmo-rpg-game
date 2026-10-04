# Câu hỏi đang chờ anh — Hắc Long

> Câu hỏi ảnh hưởng cân bằng, dữ liệu lưu, giao thức hoặc cách chơi mà em không tự chốt. Anh trả lời xong thì em chuyển
> câu đó xuống mục **Đã chốt** (ghi ngày + câu trả lời) và làm theo.
> Câu hỏi thiết kế chi tiết của từng phase vẫn ghi ở `INTEGRATION_PLAN.md` / `PHASE_PLAN.md`; file này gom lại để dễ theo dõi.

## Đang chờ

| # | Phase | Câu hỏi | Đề xuất của em |
|---|---|---|---|
| 5-A | 2 | Soak test: bao nhiêu bot, chạy bao lâu? | 30 bot / 10 phút |
| 5-B | 2 | e2e chạy trên CI khi nào? | Chỉ khi sửa `reference/rpg-game/**` |
| 10-A … 10-D | 6 | Ghép đồ từ Item.txt vào game (chọn món cho vùng / cửa hàng, giá, yêu cầu chỉ số) — `INTEGRATION_PLAN.md §10` | Chờ anh gửi Item.txt rồi chốt |
| P1-Q1 | – | Danh sách từ cấm cơ bản (`RULES.names` trong `priv/game_data/rules.json`) em tự lập: tên quản trị giả mạo (admin, GM, mod, quản trị, hệ thống…) và chửi thề phổ biến (tiếng Việt không dấu + tiếng Anh). Anh xem có cần thêm / bớt từ nào không? | Dùng tạm danh sách hiện tại; anh sửa trực tiếp file, build lại là có hiệu lực |
| P1-Q2 | – | Có cần công cụ quản trị **đổi tên** nhân vật / bang (cho tên đặt trước khi có lọc từ cấm)? | Làm cùng Phase 5 (xã hội) nếu anh cần |

## Đã chốt

| # | Ngày | Câu hỏi | Trả lời |
|---|---|---|---|
| 1-A | 2026-10-04 | Danh sách từ cấm: anh gửi hay em lập? | Em lập danh sách cơ bản |
| 1-B | 2026-10-04 | Tách `priv/game_data.json` thành thư mục `priv/game_data/`? | Đồng ý |
| H7/H8, C15, D4, M7 | 2026-10-04 | Xem `FEATURE_CATALOG.md` mục "Kiểm tra lựa chọn của anh" | Đồng ý tất cả |
