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
| `mix test --only balance` | Test ExUnit: lỗi nếu mốc nào lệch quá 15% (`BALANCE_N` mặc định 48, `BALANCE_TOL` mặc định 0.15). Không chạy cùng `mix test` thường. | ~4–5 phút |

Kết quả còn được ghi ở `tmp/pvp_tune/report.md` (bảng) và `tmp/pvp_tune/suggest.json` (bảng gợi ý), thư mục `tmp/`
không vào git.

Quy trình gợi ý sau khi đổi gameplay:

0. Đổi thứ ảnh hưởng **người chơi lên đồ thế nào** (rơi đồ, giá, ép đồ, cánh, quái, bản đồ, nhiệm vụ…): tạo lại hồ sơ
   đồ theo mốc `FRESH=1 mix run --no-start scripts/pvp/profile.exs` (~5 phút, xem mục dưới). Chỉ đổi luật đánh / kỹ
   năng / chỉ số lớp thì bỏ qua bước này.
1. `mix run --no-start scripts/pvp/tune.exs` → nếu ĐẠT thì xong.
2. Chưa đạt: `TUNE=1 mix run --no-start scripts/pvp/tune.exs`, xem bảng gợi ý.
3. Đồng ý thì chạy lại với `WRITE=1` (hoặc chép tay số vào rules.json), rồi chạy lại bước 1 và `mix test`.
4. Cập nhật Kho Đồ (`bash scripts/kho_do/build.sh …`): bảng hệ số ở mục "Chỉ số, chiến đấu" đọc thẳng từ rules.json.

## Hồ sơ đồ theo mốc (`tier_profile.json`)

Nhân vật dùng để đo không phải đồ max mà là **đồ của người chơi thật vừa đạt mốc đó**, lấy từ hành trình mô phỏng
(`HacLong.Game.Journey`, như `mix hac_long.journey`):

- `profile.exs` chạy 4 lớp × `SEEDS` (mặc định 3) hành trình 10 lần chuyển sinh, lấy nhân vật ở mỗi mốc (vừa đạt cấp
  tối đa, trước khi chuyển sinh), tính chung cho 4 lớp: **cấp đồ** (trung vị) của vũ khí, giáp, trang sức; ép +N,
  dòng cộng thêm, Excellent (trung bình); May mắn, đồ có kỹ năng (đa số); cánh (trung vị bậc), tháp, thông thạo
  (trung bình); thú cưng (nếu đa số có). Số không giảm theo mốc.
- Ghi `scripts/pvp/tier_profile.json` (vào git). **Sửa tay được**, ví dụ muốn đo người chơi cày kỹ hơn: tăng `up`,
  `armor_level`, `wing`… của mốc đó, rồi chạy `TUNE=1`.
- `Max.tier/2` (`build.exs`) dựng 4 lớp cùng hồ sơ: mỗi ô mặc **món tốt nhất của lớp** (công / thủ cao nhất) có cấp
  đồ ≤ cấp trong hồ sơ, mặc được theo chỉ số; Kiếm Sĩ / Phù Thủy / Đấu Sĩ cầm 2 vũ khí 1 tay, Tiên Nữ 1 vũ khí; điểm
  chia theo tỉ lệ cố định của lớp.
- **Mốc 10 (cuối)** có `"max": true`: dùng nhân vật tối đa (`Max.build/2`: +11 full Excellent, cánh 3, Long Vương),
  vì người chơi ở mốc cuối lâu và lên dần tới đồ tối đa. `profile.exs` tự đặt cờ này (`MAX_LAST=0` để tắt); đặt
  `"max": true` cho mốc khác cũng được.
- Hành trình đã chạy lưu ở `tmp/journey_tiers/` (dùng lại; `FRESH=1` để chạy mới).

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

- Mỗi mốc k dựng 4 nhân vật cấp 50, k lần chuyển sinh, **đồ ngang nhau theo hồ sơ mốc** (`tier_profile.json`, mục trên).
- Mỗi cặp lớp đánh Đồ sát cả hai chiều (người tấn công đi trước), đúng đường server (`sim.exs`): tự dùng kỹ năng mạnh
  nhất, uống bình máu khi dưới 50% máu, bình mana khi hết MP.
- **Tỉ lệ thắng của một lớp** = số trận thắng / số trận của lớp đó với 3 lớp kia (cả tấn công lẫn bị đánh), không tính
  hòa. **Lệch** = lớp xa 50% nhất.
- Chỉnh: lớp thắng nhiều thì tăng hệ số, thắng ít thì giảm; mỗi dòng giữ trung bình nhân như cũ (mức sát thương chung
  không đổi).

Lưu ý:
- Đồ giống hệt nhau nên trận gần như tất định, tỉ lệ thắng nhảy mạnh theo hệ số; ±5–10% giữa hai lần chạy là bình thường.
- Bảng chỉ đúng với hồ sơ đồ đang dùng: đổi cách người chơi lên đồ thì tạo lại hồ sơ (`profile.exs`) rồi mới chỉnh.
- Nhân vật tối đa là mốc 10 của bảng; `run.exs` đo thêm đồ sát chéo chi tiết từng cặp lớp.
- Bảng chỉ làm các lớp ngang nhau **khi cùng mốc, đồ ngang nhau**. Người mốc cao hơn vẫn gần như luôn thắng người mốc thấp.

## Các script khác

- `sim.exs`: mô phỏng một trận đồ sát (`SlaySim.fight/2`); biến `POT`, `CROSS`, `NO_STUN`, `FIRST_MULT`… để thử luật.
- `build.exs`: dựng nhân vật tối đa (`Max.build/2`) và theo mốc (`Max.tier/2`, đọc `tier_profile.json`).
- `profile.exs`: tạo `tier_profile.json` từ hành trình chơi thật.
- `balance.exs`: đo / chỉnh / ghi bảng (dùng chung cho `tune.exs` và test).
- `run.exs`: đồ sát chéo 4 lớp nhân vật tối đa.
- `cross.exs`: đồ sát giữa hai người khác mốc chuyển sinh (`PAIRS=0-1,3-7`).
- `arena.exs`: Đấu trường chéo 4 lớp theo mốc (đối thủ máy như người thật; `POT=0` không uống bình).
- `journey_pk.exs`: đồ sát chéo với nhân vật chơi thật (`Journey`) hoặc `SRC=tier`.
- `why.exs`: tìm nguyên nhân lệch (chỉ số, sát thương / lượt, hồi máu, số lượt để hạ).
