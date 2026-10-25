# Cân bằng lớp khi đồ sát (`scripts/pvp/`)

Hệ số nhận sát thương theo lớp khi đánh người nằm ở `priv/game_data/rules.json` → `pvp.class_taken_by_rebirth`:
một dòng cho mỗi số lần chuyển sinh (0–10), mỗi dòng một hệ số cho từng lớp. Khi bị đánh (Đồ sát, Đấu trường), sát
thương lên người = sát thương đòn × `pvp.dmg_mult` × hệ số của **lớp và số lần chuyển sinh của người bị đánh**
(quá 10 lần dùng dòng 10). Trên 1: nhận đòn đau hơn (lớp đang mạnh); dưới 1: nhẹ hơn (lớp đang yếu).

Bảng được chỉnh tự động bằng mô phỏng, nên **sau mỗi lần đổi gameplay** (chỉ số lớp, kỹ năng, đồ, cánh, luật đánh
người…) chỉ cần chạy lại các lệnh dưới.

## Ba lệnh

Chạy trong thư mục dự án (`reference/rpg-game`), không cần server hay database.

| Lệnh | Làm gì | Thời gian |
|---|---|---|
| `mix run --no-start scripts/pvp/tune.exs` | **Kiểm tra** bảng hiện tại: in tỉ lệ thắng 4 lớp ở từng mốc, đánh dấu ✓ / ✗. Mốc nào lệch quá 10% thì báo "CẦN CHỈNH" và thoát mã 1. | ~5–7 phút |
| `TUNE=1 mix run --no-start scripts/pvp/tune.exs` | **Tự chỉnh** những mốc lệch quá 10%, kiểm lại trên bộ số ngẫu nhiên khác, in **bảng gợi ý** (mốc nào không tốt hơn thì giữ). Không sửa file. | 10–30 phút |
| `TUNE=1 WRITE=1 mix run --no-start scripts/pvp/tune.exs` | Như trên rồi **ghi bảng gợi ý vào rules.json** (chỉ thay khối `class_taken_by_rebirth`). | 10–30 phút |
| `mix test --only balance` | Test ExUnit: lỗi nếu mốc nào lệch quá 15% (`BALANCE_N`, `BALANCE_TOL` để đổi). Không chạy cùng `mix test` thường. | ~2–3 phút |

Kết quả còn được ghi ở `tmp/pvp_tune/report.md` (bảng) và `tmp/pvp_tune/suggest.json` (bảng gợi ý), thư mục `tmp/`
không vào git.

Quy trình gợi ý sau khi đổi gameplay:

1. `mix run --no-start scripts/pvp/tune.exs` → nếu ĐẠT thì xong.
2. Chưa đạt: `TUNE=1 mix run --no-start scripts/pvp/tune.exs`, xem bảng gợi ý.
3. Đồng ý thì chạy lại với `WRITE=1` (hoặc chép tay số vào rules.json), rồi chạy lại bước 1 và `mix test`.
4. Cập nhật Kho Đồ (`bash scripts/kho_do/build.sh …`): bảng hệ số ở mục "Chỉ số, chiến đấu" đọc thẳng từ rules.json.

## Biến tùy chọn

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `KS` | `0,1,…,10` | Mốc cần đo, ví dụ `KS=4,5` |
| `N` | 48 (kiểm) / 32 (chỉnh) | Số trận mỗi chiều cho mỗi cặp lớp. Nhiều hơn thì chính xác hơn nhưng lâu hơn |
| `N_VERIFY` | 48 | Số trận khi kiểm lại bảng gợi ý |
| `TOL` | `0.10` | Lệch cho phép so với 50% |
| `ITERS` | 8 | Số vòng chỉnh tối đa mỗi mốc |
| `STEP` | `0.3` | Độ mạnh mỗi bước chỉnh (vọt lố thì tự giảm nửa) |

## Cách đo (để đọc đúng con số)

- Mỗi mốc k dựng 4 nhân vật cấp 50, k lần chuyển sinh, **đồ giống hệt nhau theo một công thức** (`Max.tier/2` trong
  `build.exs`): ép +≈1.1k (tối đa +11), k/2 dòng cộng thêm (tối đa 4), May mắn từ k ≥ 2, ⌈k/2⌉ dòng Excellent
  (tối đa 6), cánh cấp 1 (k 1–3) / 2 (4–6) / 3 (7+), tháp 10 + 5k, thông thạo kỹ năng 6 + k, không thú cưng.
- Mỗi cặp lớp đánh Đồ sát cả hai chiều (người tấn công đi trước), đúng đường server (`sim.exs`): tự dùng kỹ năng mạnh
  nhất, uống bình máu khi dưới 50% máu, bình mana khi hết MP.
- **Tỉ lệ thắng của một lớp** = số trận thắng / số trận của lớp đó với 3 lớp kia (cả tấn công lẫn bị đánh), không tính
  hòa. **Lệch** = lớp xa 50% nhất.
- Chỉnh: lớp thắng nhiều thì tăng hệ số, thắng ít thì giảm; mỗi dòng giữ trung bình nhân như cũ (mức sát thương chung
  không đổi).

Lưu ý:
- Đồ giống hệt nhau nên trận gần như tất định, tỉ lệ thắng nhảy mạnh theo hệ số; ±5–10% giữa hai lần chạy là bình thường.
- Nếu đổi cách người chơi lên đồ theo mốc (ví dụ thêm loại đồ, đổi mốc có cánh), sửa hồ sơ `Max.tier/2` cho khớp
  rồi mới chỉnh, vì bảng chỉ đúng với hồ sơ đó.
- Bảng chỉ làm các lớp ngang nhau **khi cùng mốc, đồ ngang nhau**. Người mốc cao hơn vẫn gần như luôn thắng người mốc thấp.

## Các script khác

- `sim.exs`: mô phỏng một trận đồ sát (`SlaySim.fight/2`); biến `POT`, `CROSS`, `NO_STUN`, `FIRST_MULT`… để thử luật.
- `build.exs`: dựng nhân vật tối đa (`Max.build/2`) và theo mốc (`Max.tier/2`).
- `balance.exs`: đo / chỉnh / ghi bảng (dùng chung cho `tune.exs` và test).
- `run.exs`: đồ sát chéo 4 lớp nhân vật tối đa.
- `journey_pk.exs`: đồ sát chéo với nhân vật chơi thật (`Journey`) hoặc `SRC=tier`.
- `why.exs`: tìm nguyên nhân lệch (chỉ số, sát thương / lượt, hồi máu, số lượt để hạ).
