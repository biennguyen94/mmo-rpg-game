# Kế hoạch tích hợp tính năng MU Web vào Hắc Long

> Tài liệu thiết kế (chưa code). Mỗi tính năng ghi:
>
> - Hắc Long đang có gì;
> - lấy gì từ MU Web;
> - thiết kế cụ thể (file, bảng, lệnh);
> - test;
> - **câu hỏi cần anh chốt** (đánh dấu ⛔).
>
> Bản đồ code chi tiết (vàng, đồ, quản trị, xếp hạng, vẽ, test): `docs/CODEBASE_NOTES.md`.
> Danh mục đầy đủ mọi tính năng MU Web có thể mang sang (để chọn thêm): `docs/FEATURE_CATALOG.md`.
>
> Số dòng code dẫn theo bản hiện tại của `reference/rpg-game` (gốc commit `5c514b7`, xem `reference/COMMIT`).

## Mục lục

0. [Nguyên tắc chung](#0-nguyên-tắc-chung)
1. [Nhật ký vàng + kiểm tra gian lận](#1-nhật-ký-vàng--kiểm-tra-gian-lận)
2. [Lệnh quản trị bổ sung](#2-lệnh-quản-trị-bổ-sung)
3. [Ép đồ bằng ngọc +6 → +11](#3-ép-đồ-bằng-ngọc-6--11) (tính năng số 4 trong danh sách gợi ý)
4. [Máy Hỗn Nguyên + Cánh](#4-máy-hỗn-nguyên--cánh) (số 5)
5. [Test giao diện tự động + soak](#5-test-giao-diện-tự-động--soak) (số 6)
6. [Bảng xếp hạng theo lớp](#6-bảng-xếp-hạng-theo-lớp) (số 7)
7. [Thứ tự làm và khối lượng](#7-thứ-tự-làm-và-khối-lượng)
8. [Tổng hợp câu hỏi cần chốt](#8-tổng-hợp-câu-hỏi-cần-chốt)

---

## 0. Nguyên tắc chung

- **Làm thẳng trong `reference/rpg-game`**, không đụng repo gốc Hắc Long.
  - Ghi thêm vào `reference/COMMIT` một dòng: "đã sửa sau commit gốc, xem `docs/INTEGRATION_PLAN.md`".
    Như vậy `KB_BASE_REPO` / `REUSE_LOG` của MU vẫn biết bản gốc là commit nào.
- **Giao diện (anh chốt 2026-10-04):** giữ nguyên giao diện Hắc Long (trang chính, bản đồ, trận, HUD, thanh tab, phong cách).
  Chỉ làm lại **túi đồ** và **phần nhân vật** (ô trang bị, chỉ số, cộng điểm) cho đẹp hơn kiểu MU. Được gộp / tách / chuyển các phần có sẵn
  (vd Thành tựu ra khỏi Nhân vật). Chi tiết: `docs/FEATURE_CATALOG.md` mục Q.
  - Ô cánh (mục 4): đặt trong bố cục mới của tab Nhân vật (Q1), hình cánh vẽ thêm vào `doll.js` như đã thiết kế.
- **Viết theo kiểu Hắc Long**, không chép nguyên file MU:
  - module `HacLong.*`, dữ liệu trong `priv/game_data.json`;
  - logic thuần ở `HacLong.Game.*`, lệnh đi qua `Commands` → `Session` (mỗi tài khoản một tiến trình);
  - lưu nguyên dòng bằng `Characters.save!/2`.
- **Số gameplay mới đặt trong `priv/game_data.json`** (khóa mới), không đặt cứng trong module.
  Lưu ý: file này được nạp lúc biên dịch (`data.ex:31-59`), đổi số phải khởi động lại server.
- **Chất lượng:** mỗi bước giữ `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test` xanh.
  - Đổi cân bằng (mục 3, 4) thì chạy thêm `mix hac_long.simulate`.
- **CI:** đã thêm job `hac-long` vào `.github/workflows/ci.yml` của repo ngoài (Đợt 1, N4); file workflow trong thư mục này GitHub không chạy.

---

## 1. Nhật ký vàng + kiểm tra gian lận

### 1.1 Hiện trạng

- **Không có bảng log nào.** Thao tác quản trị chỉ ghi Logger (`game_channel.ex:375`).
- Nhân vật lưu **cả dòng**: `Characters.save!/2` dùng `insert … on_conflict replace` (`characters.ex:23-43`).
  Không có cột `version`, không khóa lạc quan.
- Lệnh thường **không chạy trong transaction**: hàm thuần trên map trong RAM rồi lưu cả dòng (`session.ex:397-421, 723-726`).
- Vàng đổi ở khoảng **30 chỗ**, chia 3 nhóm:

| Nhóm | Ví dụ | Cách lưu |
|---|---|---|
| (a) Hàm thuần qua Session | quái rơi (`engine.ex:756`), chết mất 10 % (`engine.ex:896`), mua / bán (`engine.ex:1058-1092`), trọ, ép đồ, rèn, rương, việc hằng ngày, nhiệm vụ, tháp, lễ hội, thú cưng, nội thất | `Characters.save!` sau lệnh |
| (b) Ở Session | trùm thế giới (`session.ex:278`), đấu trường (`session.ex:644-645`), đánh tổ đội (`session.ex:556`), **giao dịch** (`trade_offer.ex:115, 125`) | `Characters.save!` |
| (c) Trong `Repo.transaction` | nhận thư (`mailbox.ex:131-156`), lập bang / góp quỹ (`guilds.ex:230, 276-312`), **chợ** đăng / mua / hủy (`market.ex:172-261`) | transaction + callback `save` |

- **Rủi ro đã thấy khi đọc code:**
  - **Giao dịch hai pha, không chung transaction** (`trade.ex:182-200`): lấy của A, lấy của B (lỗi thì trả A), rồi trao chéo.
    Nếu tiến trình chết giữa chừng, đồ / vàng có thể mất hoặc nhân đôi.
  - **`Market.commit/4` bỏ qua kết quả transaction** (`market.ex:172-179`), luôn trả `{:ok, …}` kể cả khi rollback.
    → **lỗi thật**, sửa luôn ở bước này.
  - Không có trần vàng trong thư quản trị.

### 1.2 Lấy từ MU Web

| MU Web | Hắc Long |
|---|---|
| `zen_audit_log` + `ZenAudit.log/5` (ghi cùng transaction với thay đổi) | bảng `gold_log` |
| `Mu.Audit.run/1`: `zen_mismatch` + `supply` theo ngày | `HacLong.Audit.run/1` |
| `mix mu.audit` (exit 1 khi lệch) | `mix hac_long.audit` |
| Migration ghi `BASELINE` cho dữ liệu cũ | như vậy |

Phần kiểm item theo serial (`serial_dup`, `owner_mismatch`) **không mang sang được**: đồ Hắc Long là map đếm số (`inv`)
và mảng `gear` trong dòng nhân vật, không có serial. Xem câu hỏi 1-C.

### 1.3 Thiết kế

**Bảng mới** (migration `…_create_gold_log.exs`):

```sql
CREATE TABLE gold_log (
  id BIGSERIAL PRIMARY KEY,
  character_id BIGINT NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  delta BIGINT NOT NULL,          -- + nhận, − mất
  balance BIGINT NOT NULL,        -- số dư sau thay đổi
  reason VARCHAR(20) NOT NULL,    -- MONSTER, BUY, SELL, INN, UPGRADE, TRADE, MARKET, MAIL, GUILD, DEATH, ...
  ref TEXT,                       -- id thư / tin chợ / người giao dịch / lệnh
  at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON gold_log (character_id, at);
-- dữ liệu cũ: một dòng BASELINE = vàng hiện có của từng nhân vật
INSERT INTO gold_log (character_id, delta, balance, reason) SELECT id, gold, gold, 'BASELINE' FROM characters;
```

(Kiểu khóa `character_id` theo bảng `characters` hiện tại, kiểm lại khi code.)

**Ghi log ở đâu** (một chỗ cho mỗi nhóm, không sửa 30 chỗ):

1. **Nhóm (a), (b):** trong `Session.save/2` (`session.ex:723`).
   - So `old.gold` với `new.gold`; khác nhau thì `Repo.transaction(fn -> Characters.save!(…); GoldLog.log(…) end)`.
   - `reason` lấy từ **tên lệnh** đang chạy (`act`) theo bảng ánh xạ, vd `"buy" → BUY`, `"attack"` thắng → `MONSTER`,
     thua → `DEATH`, `"rest" → INN`, `"upgrade" → UPGRADE`. Lệnh lạ → `OTHER` (vẫn ghi, không mất dấu).
   - Session tự cộng vàng (trùm thế giới, đấu trường, tổ đội, giao dịch): truyền `reason` rõ (`WORLD_BOSS`, `ARENA`, `PARTY`, `TRADE`).
   - Một lệnh có thể đổi vàng nhiều lần (vd thắng trận + thưởng sổ tay quái): chỉ ghi **tổng delta** của lệnh đó, đủ để đối soát.
2. **Nhóm (c):** callback `save` truyền vào `Mailbox` / `Guilds` / `Market` đổi thành `&save_with_log(uid, &1, reason, ref)`.
   Ghi trong **cùng transaction** sẵn có.
3. **Giao dịch:** mỗi bên ghi `TRADE` với `ref` = tên người kia. Giữ luồng hai pha như cũ; audit sẽ bắt lệch nếu có sự cố.
   Viết lại thành một transaction là việc lớn hơn, đưa vào câu hỏi 1-B.

**Kiểm tra** (`HacLong.Audit.run(days: 7)`, chỉ đọc):

| Kiểm | Nghĩa |
|---|---|
| `gold_mismatch` | `characters.gold` ≠ tổng `delta` của nhân vật đó |
| `market_orphan` | tin chợ chưa bán mà người bán không còn |
| `mail_gold_unclaimed` | (thống kê) tổng vàng còn nằm trong thư chưa nhận |
| `supply` | tổng vàng server; theo ngày × `reason`: vàng sinh ra / mất đi |

- Lệnh: `mix hac_long.audit [--days 30]` (exit 1 nếu lệch), bản release: `bin/hac_long rpc 'IO.inspect(HacLong.Audit.run().problems)'`.
- Thêm vào tab Quản trị: nút "Kiểm tra vàng" hiện số lỗi + bảng vàng theo ngày.

### 1.4 Test

- Mỗi `reason` chính (quái, mua, bán, chết, trọ, thư, chợ mua / bán / hủy, góp quỹ, giao dịch, đấu trường) → có đúng một dòng log, `balance` khớp.
- Sửa vàng thẳng bằng SQL → `Audit.run` báo `gold_mismatch`.
- `Market.commit` rollback → trả lỗi (test cho lỗi đã sửa).
- Hiệu năng: `Session.save` chỉ thêm 1 `INSERT` khi vàng đổi (di chuyển không đổi vàng, không ghi).

### 1.5 ⛔ Câu hỏi

- **1-A** Giữ log bao lâu? Đề xuất: **giữ hết**; thêm `mix hac_long.audit --prune 180` xóa dòng cũ hơn 180 ngày (gộp thành một dòng BASELINE mới).
- **1-B** Có viết lại giao dịch trực tiếp thành **một transaction** khóa hai nhân vật (như `Items.trade` của MU) không?
  Đề xuất: **có, nhưng ở bước sau**. Bước này chỉ ghi log để phát hiện.
- **1-C** Có làm luôn **log đồ** (đồ đi đâu: chợ, giao dịch, thư, bán) không? Không có serial nên chỉ log được "ai nhận / mất món gì".
  Đề xuất: log riêng đồ ngẫu nhiên (`gear`, có `uid`) vì đó là thứ đáng tiền nhất; đồ thường để sau.

---

## 2. Lệnh quản trị bổ sung

### 2.1 Hiện trạng

- Cờ `users.admin`, gán lúc kết nối socket (`user_socket.ex:10`); cấp quyền bằng `mix hac_long.admin USER`.
- Lệnh kênh `"admin"` (`game_channel.ex:555-619`): báo cáo, tra người chơi, cấm chat, khóa, thông báo,
  tặng quà qua thư (vàng, xp, đồ thường; cho một người hoặc tất cả), gọi trùm thế giới.
- Tab Quản trị trong game (`ui.js:142-203`).
- **Chưa có:**
  - nâng cấp / chỉnh nhân vật tức thì (chỉ tặng qua thư, người chơi phải bấm nhận);
  - tặng **đồ ngẫu nhiên** (thư không chứa được `gear`) hoặc đồ đã nâng cấp;
  - **log thao tác admin** (chỉ có Logger, mất khi xoay log).

### 2.2 Lấy từ MU Web

`Mu.Admin` (DEC-187/188): `give_exp`, `set_level`, `give_item(level:, option:)`, `add_zen`, `add_stats`, `log`, bảng `admin_log`.
Chạy **trong Session** của tài khoản, nên người đang online thấy ngay và không bị ghi đè.

### 2.3 Thiết kế

**Bảng `admin_log`:** `id, admin_user_id (NULL = từ dòng lệnh), action, target_user_id, target_name, detail JSONB, reason, at`.
Mọi lệnh quản trị **cũ và mới** đều ghi vào đây (cấm chat, khóa, thông báo, tặng quà, gọi trùm…).

**Module `HacLong.Admin`** (gọi được từ tab Quản trị và từ `bin/hac_long rpc`):

| Hàm | Làm gì | Ghi chú |
|---|---|---|
| `give_xp(name, n, reason)` | cộng XP, lên cấp liên tiếp theo luật sẵn có | dùng hàm lên cấp của `Engine` (tách ra nếu đang nằm trong `win`) |
| `set_level(name, lv, reason)` | nâng tới cấp `lv` (chỉ nâng) | điểm tiềm năng +3 / cấp như lên cấp thường |
| `add_gold(name, n, reason)` | ± vàng | ghi `gold_log` lý do `ADMIN` (cần mục 1) |
| `give_item(name, id, qty, up: n)` | đồ thường vào `inv`, kèm cấp nâng `up` | `up` ≤ cấp tối đa (5, hoặc 11 nếu làm mục 3) |
| `give_gear(name, base, rarity, bonus)` | tạo **đồ ngẫu nhiên** chỉ định chỉ số | theo `Gear` (`gear.ex:133-150`), túi `gear` tối đa 20 |
| `add_points(name, n)` / `add_stats(name, %{str:…})` | cộng điểm tiềm năng / chỉ số | |
| `rebirth(name)` | ép chuyển sinh | tùy chọn |
| `log(name \\ nil)` | xem lịch sử thao tác | |

**Cách chạy:**
- `Session` thêm `handle_call({:admin, fun})`: nhân vật đang online thì sửa bản trong RAM rồi `save` + đẩy trạng thái;
  offline thì đọc DB, sửa, `save!`.
- Kênh `"admin"` thêm `op`: `xp`, `level`, `gold`, `item`, `gear`, `points`, `log`.
- Tab Quản trị: trong thẻ người chơi (sau khi tra) thêm khối "Chỉnh nhân vật".
  - Ô số XP / cấp / vàng / điểm.
  - Chọn đồ + cấp nâng, nút "Tạo đồ ngẫu nhiên".
  - Danh sách "Lịch sử quản trị" của người đó.

**Tài liệu:** `docs/ADMIN_GUIDE.md` cho Hắc Long, viết theo mẫu `ADMIN_GUIDE.md` của MU. Có công thức dựng
"nhân vật admin" (cấp tối đa, đồ +tối đa, vàng, chỉ số) để copy.

### 2.4 Test

- Từng hàm, cả lúc nhân vật online (kênh nhận trạng thái mới) và offline.
- Người không có cờ admin gọi `op` mới → "Không có quyền.".
- Mỗi thao tác đều có dòng `admin_log`. `add_gold` có dòng `gold_log` `ADMIN`, nên `Audit.run` vẫn sạch.

### 2.5 ⛔ Câu hỏi

- **2-A** Có cho admin tặng **đồ không rơi được** (Thánh Tích `relic`, Khiên Rồng `dragonshield`) không? Đề xuất: **có**, vì có log.
- **2-B** Có cần **nhiều cấp quyền** (moderator chỉ cấm chat / khóa; admin mới được tặng đồ) không?
  Đề xuất: **có**, đổi `users.admin` boolean thành `users.role` (`player` / `mod` / `admin`), migration giữ admin cũ.

---

## 3. Ép đồ bằng ngọc +6 → +11

### 3.1 Hiện trạng

- Thợ Rèn nâng đồ **đang mặc** (vũ khí / giáp / khiên) tới **+5** (`@max_upgrade 5`, `engine.ex:20, 986-1027`).
  - Tốn quặng (`ore` / `ore_rare`) + vàng; +5 cần thêm 1 Vảy Rồng.
  - **Luôn thành công.**
- Cấp nâng lưu **theo loại đồ** (`upgrades: %{id => cấp}`; đồ ngẫu nhiên theo `uid`). Bán cái cuối cùng thì mất cấp (`engine.ex:1094`).
- Mỗi cấp cộng `max(1, round(atk_hoặc_def × 0.08))` (`engine.ex:962-968`).
- Quái **không rơi nguyên liệu** (nguyên liệu chỉ đến từ điểm thu thập, `world.ex:205-210`).
- Người chơi cấp cao đã +5 hết thì **không còn mục tiêu** để cày đồ.

### 3.2 Lấy từ MU Web

| MU Web | Hắc Long |
|---|---|
| `upgrade.levels` (bảng từng bước: ngọc, tỉ lệ, thất bại) | khóa mới `UPGRADE` trong `game_data.json` |
| `Mu.Game.Upgrade.apply/5` (hàm thuần, RNG truyền vào) | `HacLong.Game.Upgrade` |
| Ngọc rơi hiếm từ quái cấp cao | thêm vào `Engine.win` |
| Thông báo toàn server khi ép thành công từ +7 | `Chat.system` |
| +10 / +11 cộng gấp đôi (`items.highLevel`) | như vậy |

### 3.3 Thiết kế (số trong bảng là **đề xuất**, chờ chốt)

**Ngọc mới** (thêm vào `ITEMS`, `slot: "material"`, giữ ở `inv`, bán được, giao dịch / chợ được):

| id | Tên | Dùng | Giá bán NPC (đề xuất) |
|---|---|---|---|
| `jewel_bless` | Ngọc Phúc Lành | +5 → +6 | 400 |
| `jewel_soul` | Ngọc Linh Hồn | +6 → +9 | 600 |
| `jewel_chaos` | Ngọc Hỗn Nguyên | +9 → +11, Máy Hỗn Nguyên (mục 4) | 500 |

**Bảng `UPGRADE`** (mới; +1 → +5 giữ nguyên Thợ Rèn hiện tại):

| Bước | Cần | Thành công | Thất bại |
|---|---|---|---|
| +5 → +6 | 1 Ngọc Phúc Lành + vàng | 100 % | – |
| +6 → +7 | 1 Ngọc Linh Hồn + vàng | 70 % | tụt 1 cấp |
| +7 → +8 | 1 Ngọc Linh Hồn + vàng | 60 % | tụt 1 cấp |
| +8 → +9 | 1 Ngọc Linh Hồn + vàng | 50 % | tụt 1 cấp |
| +9 → +10 | 1 Ngọc Hỗn Nguyên + vàng | 50 % | **mất đồ** |
| +10 → +11 | 1 Ngọc Hỗn Nguyên + vàng | 45 % | **mất đồ** |

- Ngọc mất cả khi thất bại; vàng theo công thức `upgrade_cost` hiện có (n = cấp mới).
- Từ +10 mỗi cấp cộng **gấp đôi**: +11 tương đương 13 cấp × `round(chỉ_số × 0.08)`.
- **"Mất đồ"** với cấp lưu theo loại: xóa món đang mặc khỏi `equip` (và 1 cái khỏi `inv` / `gear`), cấp của loại đó về 0.
  Vũ khí rơi về `club` (như lúc mới tạo), giáp về `vest`, khiên trống.
- Ép từ **+7** thành công → `Chat.system("📢 X đã ép Đại Đao +8!")`.

**Ngọc rơi ở đâu:**
- Quái thường cấp ≥ 12: 0,6 %, tỉ lệ trong nhóm ngọc Phúc Lành 50 / Linh Hồn 35 / Hỗn Nguyên 15.
- Trùm vùng: 30 %. Trùm thế giới: top 3 sát thương mỗi người 1 viên.
- Tháp Vô Tận: mỗi 10 tầng 1 viên.
- Rương Báu: thêm vào bảng ra đồ.

**Code:**
- `HacLong.Game.Upgrade` (thuần) và `Engine.upgrade/2` gọi vào khi cấp hiện tại ≥ 5.
- `@max_upgrade` đọc từ `UPGRADE`.
- Lệnh vẫn là `"upgrade"` ở Thợ Rèn. Client (`forgeCard`, `ui.js:1308-1327`) hiện tỉ lệ, rủi ro (đỏ khi "mất đồ") và xác nhận hai bước khi +9 trở lên.
- Chợ / giao dịch vẫn mang `up` cho đồ ngẫu nhiên (`market.ex:155-161`, `trade_offer.ex:112-133`). Giới hạn `up ≤ 11`.
- Simulator: mode `+upgrade` dùng bảng mới; báo thêm "số ngọc nhặt được / người", "cấp đồ trung bình lúc hạ Hắc Long".

### 3.4 Test

- Hàm thuần với RNG có seed: thành công, tụt cấp, mất đồ, đúng ngọc / sai ngọc, đã +11.
- Kênh: ép +6 → +11, thông báo hệ thống từ +7, mất đồ thì `equip` về đồ mặc định.
- `mix hac_long.simulate 20` trước / sau: số trận hạ Hắc Long không giảm quá X % (anh chốt X).

### 3.5 ⛔ Câu hỏi

- **3-A** Bảng tỉ lệ / thất bại ở trên có dùng luôn không? Hay +10 / +11 thất bại chỉ **về +0** thay vì mất đồ (nhẹ tay hơn)?
- **3-B** Tỉ lệ rơi ngọc và chỗ rơi: theo đề xuất?
- **3-C** Có làm **Ngọc Sinh Mệnh** (dòng tùy chọn +4 công / thủ, tối đa 4 dòng, như Jewel of Life) không? Đề xuất: **để sau**.
- **3-D** Tên tiếng Việt của ngọc.

---

## 4. Máy Hỗn Nguyên + Cánh

### 4.1 Hiện trạng

- **Chỉ có 3 ô trang bị** `weapon / armor / shield`, cố định ở nhiều chỗ:
  - `characters.ex:67`, `engine.ex:1109` (chỉ nhận 3 ô), `engine.ex:1128-1134` (chỉ tháo được khiên);
  - `Engine.look` (`engine.ex:940-950`);
  - giao diện: thẻ Trang bị (`ui.js:1099-1110`), Thợ Rèn (`ui.js:1308-1327, 1373`), xem đồ người khác (`ui.js:310`);
  - `market.ex`, `trade_offer.ex`.
- Hình nhân vật (`doll.js`) ghép các lớp PNG 32×32 (tile Dungeon Crawl):
  thân → giáp → tóc → vũ khí → khiên (`doll.js:9, 15`), giá trị lấy từ trường `doll` của món đồ.
- Đã có **công thức** (`RECIPES`, Bác Đầu Bếp / Thợ Rèn) nhưng là nấu / rèn chắc chắn, không có ghép may rủi.
- Chỗ cắm % sát thương / % giảm sát thương:
  - đòn người chơi: `mult` ở `engine.ex:444`;
  - đòn quái: hệ số `guard` ở `engine.ex:614`;
  - đấu trường dựng đối thủ từ `Engine.derived` (`arena.ex:74-96`).

### 4.2 Lấy từ MU Web

- `chaos.json` (công thức: đầu vào theo loại / cấp / số lượng, phí vàng, tỉ lệ cơ bản + cộng theo cấp đồ, trần 60 %).
- `Mu.Game.Chaos` (khớp công thức, tung tỉ lệ, kết quả theo lớp).
- Cánh: ô thứ 4, `damageIncrease` / `absorb` %, ép +N mỗi cấp +2 %.
- MU vẽ cánh **bằng code trên canvas** (2 lớp, cánh cấp 2 to hơn), không cần ảnh.

### 4.3 Thiết kế (số là đề xuất)

**Ô trang bị thứ 4 `wing`:**
- Thêm vào mọi chỗ liệt kê ở 4.1; `equip` cũ không có `wing` thì coi là `nil` (không cần migration, cột `equip` là map).
- Cánh tháo / mặc tự do như khiên. Không bán ở cửa hàng.
- Mang qua chợ / giao dịch được (kèm `up`).

**Cánh** (thêm vào `ITEMS`, `slot: "wing"`):

| id | Tên | Lớp | Cấp mặc | Thủ | +% sát thương | −% sát thương nhận |
|---|---|---|---|---|---|---|
| `wing_warrior_1` | Cánh Chiến Thần | Chiến Binh | 20 | 6 | 10 % | 10 % |
| `wing_rogue_1` | Cánh Bóng Đêm | Thích Khách | 20 | 6 | 10 % | 10 % |
| `wing_knight_1` | Cánh Thánh Quang | Hiệp Sĩ | 20 | 6 | 10 % | 10 % |
| `wing_*_2` | Cánh … cấp 2 | từng lớp | 35 | 12 | 18 % | 18 % |

- Cánh nâng cấp được (Thợ Rèn / ngọc mục 3): mỗi cấp +1 thủ, +2 % / +2 %.
- Áp vào combat:
  - `mult *= 1 + wing_dmg` (`engine.ex:444`);
  - đòn quái nhận `× (1 − wing_absorb)` (`engine.ex:614`), **sau** guard;
  - đấu trường dùng cùng `derived`, nên tự áp dụng.
- `Engine.derived` trả thêm `wingDmg`, `wingAbsorb` để client hiện trong bảng chỉ số.

**NPC mới "Lão Hỗn Nguyên"** ở Làng (thêm vào `priv/maps/village.json`), mở panel **Máy Hỗn Nguyên**.

**Công thức** (khóa mới `CHAOS` trong `game_data.json`):

| Công thức | Đầu vào | Phí | Tỉ lệ | Kết quả |
|---|---|---|---|---|
| Cánh cấp 1 | 1 vũ khí / giáp / khiên **+5 trở lên** + 1 Ngọc Hỗn Nguyên | 20 000 vàng | 10 % + 5 % mỗi cấp trên +5, tối đa 60 % | cánh cấp 1 **đúng lớp** người ghép |
| Cánh cấp 2 | cánh cấp 1 **+5↑** + 5 Phúc Lành + 5 Linh Hồn + 2 Hỗn Nguyên | 200 000 vàng | 20 % + 5 % mỗi cấp trên +5, tối đa 60 % | cánh cấp 2 đúng lớp |
| Ngọc Hỗn Nguyên | 10 Quặng Hiếm + 1 Vảy Rồng | 5 000 vàng | 70 % | 1 Ngọc Hỗn Nguyên (cho người không gặp may khi nhặt) |

- Thất bại: **mất hết đầu vào và phí** (như MU).
- Đồ đầu vào lấy từ `inv` / `gear`. Đồ đang mặc phải tháo ra trước, tránh mất nhầm.
- Toàn bộ trong `Session` (một tiến trình / tài khoản nên không chạy đồng thời).
- Ghi `gold_log` `CHAOS` (mục 1), và log đồ nếu làm 1-C.

**Hình cánh:** vẽ bằng code trên canvas trong `doll.js`, lớp **dưới thân** (trước `base`).
- Cánh cấp 1: một lớp, màu theo lớp (đỏ / tím / vàng).
- Cánh cấp 2: to hơn 1,4 lần, hai lớp.
- Không cần thêm ảnh, không phải lo bản quyền. `Engine.look` thêm `wing`.

### 4.4 Test

- `Chaos` thuần (seed): khớp / không khớp công thức, tỉ lệ theo cấp đồ, trần 60 %, kết quả theo lớp.
- Kênh: ghép thành công / thất bại (mất đầu vào), mặc / tháo cánh, chỉ số hiện đúng.
- Combat: thắng nhanh hơn / mất ít máu hơn đúng % với RNG cố định; đấu trường áp dụng cánh.
- Nhân vật cũ (không có `wing`) vào game bình thường.
- Simulator có mode `+wings`.

### 4.5 ⛔ Câu hỏi

- **4-A** Cấp mặc 20 / 35 và chỉ số cánh: theo đề xuất? (Hắc Long cấp tối đa 50 + chuyển sinh.)
- **4-B** Cánh mang qua **chợ / giao dịch** được không? Đề xuất **được** (như MU).
- **4-C** Có công thức "ra Ngọc Hỗn Nguyên" (dòng 3 bảng công thức) không, hay ngọc chỉ rơi từ quái?
- **4-D** Tên NPC / tên cánh tiếng Việt.

---

## 5. Test giao diện tự động + soak

### 5.1 Hiện trạng

- 22 file `*_test.exs`; riêng `game_channel_test.exs` 1 294 dòng.
- **Không có** `package.json`, test JS hay test giao diện thật.
- CI của Hắc Long không chạy (thư mục con, mục 0).

### 5.2 Lấy từ MU Web

- `client/e2e/*.mjs`: Playwright, Chromium có sẵn ở `/opt/pw-browsers/chromium`, mỗi kịch bản in `PASS / FAIL` + chụp màn hình.
- Script seed dữ liệu cho test (`scripts/e2e_*.exs`).
- Soak test: nhiều bot cùng lúc, đo độ trễ và lỗi, kèm audit sau khi chạy.
- Bước CI chạy e2e với server thật.

### 5.3 Thiết kế

**Thư mục mới:** `reference/rpg-game/e2e/`.

```
e2e/
  package.json        # playwright, phoenix (client socket cho soak)
  lib.mjs             # mở trang, đăng ký, tạo nhân vật, chờ trạng thái, chụp màn hình
  smoke.mjs           # đăng ký → tạo nhân vật → đi → đánh quái → mua / bán ở Thợ Rèn → nghỉ trọ
  social.mjs          # 2 trình duyệt: tổ đội, giao dịch, bạn bè + tin nhắn, chợ đăng / mua
  progress.mjs        # nhiệm vụ, việc hằng ngày, nâng cấp, rương, câu cá
  admin.mjs           # tab Quản trị: tra người, cấm chat, tặng quà; lệnh mới ở mục 2
  mobile.mjs          # khung 360 px: không tràn ngang, nút bấm đủ lớn
  soak.mjs            # N bot (mặc định 30) qua WebSocket, chạy 10 phút
  screenshots/        # ảnh kết quả (không commit, chỉ giữ ảnh chọn lọc ở docs/screenshots)
scripts/e2e_seed.exs  # tạo sẵn nhân vật cấp cao / vàng / đồ để test nhanh (qua HacLong.Admin)
```

- Mỗi kịch bản dùng **tài khoản ngẫu nhiên**, chạy độc lập.
- Có hook test trong client: `window.__hl` = trạng thái người chơi, vị trí, trận đánh.
  Chỉ bật khi `?test=1`, để test không phải đoán trên ảnh.
- Kiểm thêm: không có lỗi JS trên trang (`pageerror`).

**Soak test:**
- Mỗi bot đăng nhập, đi ngẫu nhiên, đánh quái, mua bình, thỉnh thoảng chat / chợ / giao dịch theo cặp.
- Đo: độ trễ trả lời lệnh (p50 / p95 / max), số lỗi, số tiến trình, bộ nhớ BEAM.
- Sau khi chạy: `mix hac_long.audit` phải sạch (cần mục 1).
- Ngưỡng đạt (đề xuất): p95 < 150 ms, 0 lỗi 5xx / crash, audit sạch.

**CI** (job mới trong `.github/workflows/ci.yml` của repo ngoài):
1. `working-directory: reference/rpg-game`, Postgres 16.
2. `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`.
3. Bật server, chạy `smoke.mjs` và `social.mjs`; soak chỉ chạy tay hoặc theo lịch.

### 5.4 ⛔ Câu hỏi

- **5-A** Số bot và thời gian soak mục tiêu (đề xuất 30 bot / 10 phút; tối đa 100 bot chạy tay)?
- **5-B** Chạy e2e trên **mọi push** hay chỉ khi sửa `reference/rpg-game/**`? Đề xuất: **chỉ khi sửa thư mục đó** (`paths:` filter).

---

## 6. Bảng xếp hạng theo lớp

### 6.1 Hiện trạng

- `HacLong.Leaderboard` (`leaderboard.ex:16-81`): `level`, `kills`, `dragon`, `tower`, top 10, truy vấn thẳng **mỗi lần**, không cache.
- Kênh `"leaderboard"` gộp thêm bang, bang diệt Cổ Long, đấu trường, hạng của mình (`game_channel.ex:135-153`), giới hạn 20 lần / phút.
- Client: 7 nút trong tab Làng (`ui.js:598-625`), tự làm mới tối đa 30 giây một lần.

### 6.2 Lấy từ MU Web

`Mu.Leaderboard`: bảng theo lớp, **cache** làm mới theo chu kỳ, hạng của mình theo từng bảng.

### 6.3 Thiết kế

- Thêm loại `level_warrior`, `level_rogue`, `level_knight` (lọc `cls`, cùng thứ tự: chuyển sinh → cấp → xp).
- **Cache:** `HacLong.Leaderboard` thành GenServer giữ kết quả mọi bảng trong ETS, làm mới mỗi 60 giây.
  Kênh đọc từ ETS, không truy vấn DB mỗi lần. Server đông người thì đây là phần có lợi nhất.
- Hạng của mình: thêm hạng trong lớp (`level_rank` có lọc `cls`).
- Index mới: `(cls, rebirths DESC, level DESC, xp DESC)`.
- Client: dưới nút "Cấp cao" thêm hàng chọn **Tất cả / Chiến Binh / Thích Khách / Hiệp Sĩ** (dùng `icon` của lớp).
  Hiện "Hạng của bạn trong lớp: #n".
- Tùy chọn: bảng "Giàu nhất" (vàng). Đề xuất **không**, vì lộ thông tin cho kẻ lừa đảo trên chợ.

### 6.4 Test

- Thứ hạng từng lớp đúng, hòa cấp thì xp phân định.
- Cache làm mới đúng chu kỳ (đồng hồ giả trong test).
- Kênh trả đủ bảng.

### 6.5 ⛔ Câu hỏi

- **6-A** Top 10 hay top 50 cho bảng theo lớp? Chu kỳ làm mới 60 giây được không?

---

## 7. Thứ tự làm và khối lượng

| Bước | Tính năng | Khối lượng | Phụ thuộc | Ghi chú |
|---|---|---|---|---|
| 1 | **Nhật ký vàng + audit** (mục 1) | vừa | – | Làm trước: mục 2, 3, 4 sinh vàng / đồ mới cần có log. Sửa luôn lỗi `Market.commit` |
| 2 | **Bảng xếp hạng theo lớp** (mục 6) | nhỏ | – | Nhanh, thấy ngay |
| 3 | **Quản trị bổ sung** (mục 2) | vừa | 1 | Có lệnh dựng nhân vật admin để thử 4, 5 |
| 4 | **Test giao diện + soak + CI** (mục 5) | vừa | 1, 3 | Lưới an toàn trước khi đổi cân bằng |
| 5 | **Ép đồ +6 → +11** (mục 3) | vừa | 1, 4 | Đổi cân bằng: chạy simulator trước / sau |
| 6 | **Máy Hỗn Nguyên + Cánh** (mục 4) | lớn | 5 (ngọc), 1 | Đụng nhiều chỗ (ô trang bị thứ 4, doll, combat, chợ) |

- Mỗi bước: một commit, chạy đủ format / compile / test, rồi **dừng báo cáo** chờ anh duyệt bước sau.
- Bước 5, 6 kèm số liệu simulator trước / sau.

## 8. Tổng hợp câu hỏi cần chốt

| Mã | Câu hỏi | Đề xuất của em |
|---|---|---|
| 1-A | Giữ log vàng bao lâu | giữ hết, có lệnh dọn > 180 ngày |
| 1-B | Viết lại giao dịch thành một transaction | có, nhưng sau bước 1 |
| 1-C | Log đồ | chỉ đồ ngẫu nhiên (`gear`) |
| 2-A | Admin tặng đồ không rơi được | có |
| 2-B | Phân quyền mod / admin | có (`users.role`) |
| 3-A | Tỉ lệ / thất bại +6 → +11 | theo bảng 3.3 (mất đồ ở +10 / +11) |
| 3-B | Tỉ lệ / chỗ rơi ngọc | theo 3.3 |
| 3-C | Ngọc Sinh Mệnh (dòng tùy chọn) | để sau |
| 3-D | Tên ngọc | Phúc Lành / Linh Hồn / Hỗn Nguyên |
| 4-A | Cấp / chỉ số cánh | 20 / 35; 10 % / 18 % |
| 4-B | Cánh qua chợ / giao dịch | được |
| 4-C | Công thức ra Ngọc Hỗn Nguyên | có |
| 4-D | Tên NPC / cánh | như 4.3 |
| 5-A | Quy mô soak | 30 bot / 10 phút |
| 5-B | Khi nào chạy e2e trên CI | chỉ khi sửa `reference/rpg-game/**` |
| 6-A | Top N, chu kỳ cache | top 10, 60 giây |
