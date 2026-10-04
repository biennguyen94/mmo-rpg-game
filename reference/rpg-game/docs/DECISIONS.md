# Quyết định nhỏ đã tự chốt — Hắc Long

> Những điều anh không nói tới mà em phải chọn khi làm, kèm lý do. Quyết định ảnh hưởng cân bằng / dữ liệu lưu / giao thức
> thì **không** tự chốt mà ghi vào `OPEN_QUESTIONS.md` để hỏi. Anh thấy chỗ nào không hợp thì báo, em đổi lại.
>
> Mỗi dòng: ngày · phase / đợt · quyết định · lý do.

## Phase 1 — Nền dữ liệu và cấu hình (2026-10-04)

| # | Quyết định | Lý do |
|---|---|---|
| P1-1 | Tách dữ liệu thành 12 file `priv/game_data/*.json`; mỗi file vẫn là object các **khóa lớn cũ** (`CLASSES`, `ZONES`…), không đổi tên khóa. `BOSS_DROPS` đi cùng `zones.json`, `JEWELS` cùng `upgrade.json`. | Sửa ít nhất có thể; client và code đọc khóa như cũ; nhóm theo chỗ dùng. |
| P1-2 | Hai file trùng khóa lớn → lỗi biên dịch (không ghi đè). | Tránh sửa nhầm một bản mà bản kia thắng âm thầm. |
| P1-3 | `RULES` nạp **lúc biên dịch** như mọi dữ liệu khác (không đọc lúc chạy). | Giữ kiểu Hắc Long (dữ liệu là hằng số biên dịch, nhanh); đổi số thì build lại như sửa đồ / quái. |
| P1-4 | Khóa trong `rules.json` viết `snake_case` (như `double_from`, `chest_chance` có sẵn); client nhận một số ở `GAME_DATA.RULES` kiểu `camelCase` như trước. | Thống nhất với dữ liệu server có sẵn, không đổi tên khóa client đang dùng. |
| P1-5 | Số chuyển sang `RULES` giữ **đúng giá trị và thứ tự phép tính** (vd `xp / 3` vẫn là chia 3 — `xp_div`, không đổi thành nhân 0,333). | Simulator cùng seed phải giống hệt trước / sau (đã kiểm: giống hệt). |
| P1-6 | Thông số của kỹ năng nằm ở `RULES.skill_effects` theo **kiểu tác dụng** (`cleave`, `holy`…), không nằm ở từng kỹ năng trong `classes.json`. | Nhiều kỹ năng dùng chung một kiểu tác dụng (`fire_ball`, `stun_bash`); sửa một chỗ. Câu thông báo trong trận (`+40%`…) tính từ số này. |
| P1-7 | **Để lại trong code** (không phải số cân bằng): thời gian (`@flush_ms`, `@hold_ms`, câu cá chờ / cửa sổ giật), giới hạn tần suất lệnh, kích thước tháp 13×11, độ dài tên 2–16 / bang 3–20 / chat 120, số dòng nhật ký, giới hạn quản trị, giới hạn chống lạm dụng của giao dịch (8 dòng, 10 triệu vàng), bạn bè (50), hộp thư (50). | Là giới hạn kỹ thuật / an toàn, không phải luật chơi; để trong code tránh sửa nhầm làm hỏng server. |
| P1-8 | **Để lại trong code, chuyển sau nếu cần:** danh sách thành tựu (`achievements.ex`), các bước hướng dẫn (`tutorial.ex`, chỉ quà đã sang `RULES.tutorial`), trùm thế giới (`world_boss.ex`). | Là nội dung có cấu trúc riêng (điều kiện là atom / hàm), chuyển sang JSON cần thêm bước dịch; chưa có nhu cầu chỉnh. |
| P1-9 | Kiểm dữ liệu (J2) chạy trong `Data` và `Maps` lúc biên dịch; lỗi gom hết rồi báo một lần, mỗi dòng có tên file + id. Danh sách `role` NPC và kỹ năng thú hợp lệ nằm trong `DataCheck` (code xử lý chúng ở đó). | Gõ nhầm id không lọt ra lúc chơi; thấy mọi lỗi một lượt thay vì sửa từng cái. |
| P1-10 | Từ cấm (B9): hai danh sách. `banned_words` khớp **nguyên từ** (sau bỏ dấu, chữ thường; số / ký hiệu là chỗ ngắt từ) để từ ngắn như `gm`, `dm`, `lon` không chặn nhầm "Thiên **Lon**g". `banned_parts` khớp **một phần** tên viết liền (có đổi `4dm1n` → `admin`), chỉ để từ dài, không lẫn. Bỏ `cac` khỏi danh sách vì trùng chữ "các". | Chặn được cách lách thường gặp mà ít chặn nhầm tên tiếng Việt. Anh sửa danh sách ở `rules.json` → `RULES.names`. |
| P1-11 | Từ cấm áp dụng cho tên nhân vật **mới**, tên và ký hiệu bang **mới**; tên đã có không bị đổi. | Đổi tên người đang chơi là việc của quản trị (chưa có công cụ đổi tên). |
| P1-12 | Vị trí lưu hỏng (B11): coi là hỏng khi bản đồ không còn, ô không đi được, **hoặc** bị bít cả bốn phía. Về **điểm vào của chính bản đồ đó** (cạnh đá dịch chuyển; không có thì chỗ đứng khi qua cổng vào), không được thì về Nhà. | Sau khi sửa bản đồ, người chơi vẫn ở vùng của mình thay vì bị đá về Nhà. |
| P1-13 | `mix hac_long.simulate` thêm `--seed`; tên bot lấy từ số ngẫu nhiên có seed (trước dùng `System.unique_integer`, làm việc hằng ngày đổi theo lần chạy). | Cần kết quả lặp lại được để so trước / sau khi đổi số. |
