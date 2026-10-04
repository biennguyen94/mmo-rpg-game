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
> Kế hoạch các phase tiếp theo (từ các mục đã chọn): `docs/PHASE_PLAN.md`.
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
9. [Bốn lớp nhân vật MU](#9-bốn-lớp-nhân-vật-mu) (đã làm 2026-10-04)
10. [Đồ từ Item.txt + hình đổi theo cấp](#10-đồ-từ-itemtxt--hình-đổi-theo-cấp) (công cụ đã có, chờ file)

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
  - module `HacLong.*`, dữ liệu trong `priv/game_data/*.json` (trước Phase 1 là một file `priv/game_data.json`);
  - logic thuần ở `HacLong.Game.*`, lệnh đi qua `Commands` → `Session` (mỗi tài khoản một tiến trình);
  - lưu nguyên dòng bằng `Characters.save!/2`.
- **Số gameplay mới đặt trong `priv/game_data/`** (số luật chơi vào `rules.json` → `RULES`), không đặt cứng trong module.
  Lưu ý: file này được nạp lúc biên dịch (`data.ex:31-59`), đổi số phải khởi động lại server.
- **Chất lượng:** mỗi bước giữ `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test` xanh.
  - Đổi cân bằng (mục 3, 4) thì chạy thêm `mix hac_long.simulate`.
- **CI:** đã thêm job `hac-long` vào `.github/workflows/ci.yml` của repo ngoài (Đợt 1, N4); file workflow trong thư mục này GitHub không chạy.

---

## 1. Nhật ký vàng + kiểm tra gian lận

> **Đã làm (Đợt 2, 2026-10-04).** Khác thiết kế dưới đây:
>
> - Bảng `gold_log` khóa theo `user_id` (không khóa ngoại; xóa nhân vật vẫn giữ lịch sử), thêm `gear_log` cho đồ hiếm (1-C).
> - Ghi ở **một chỗ**: `Characters.save!/4` (trong transaction, `SELECT … FOR UPDATE` dòng cũ rồi so). Mọi nhóm (a), (b), (c) đều đi qua đó.
>   Lý do = tên lệnh viết hoa (đặt trong `Session.handle_call`), không dùng bảng ánh xạ.
> - Giao dịch viết lại thành **một transaction** luôn (1-B), không chờ bước sau.
> - Dọn nhật ký (1-A) gộp thành dòng `CARRY`. Kiểm `market_orphan`, `mail_gold_unclaimed` chưa làm; thêm `gear_duplicate`, `gear_unlogged`.
> - Chi tiết code: `CODEBASE_NOTES.md §9c`; vận hành: `docs/ADMIN_GUIDE.md`.

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

> **Đã làm (Đợt 2, 2026-10-04).** Khác thiết kế dưới đây:
>
> - Tên `op`: `give_xp`, `set_level`, `add_gold`, `add_points`, `add_stats`, `give_item`, `give_gear`, `heal`; xem `audit`, `gold_log`, `admin_log`.
> - `set_level` cho cả hạ cấp (điểm tiềm năng trừ tương ứng, không dưới 0). Chưa làm `rebirth`.
> - `admin_log`: `admin_id, admin_name, op, target_id, params, result` (không có cột `reason` riêng).
> - Vai trò `users.role` (2-B), admin tặng được đồ không rơi (2-A). Dòng lệnh: `HacLong.Admin.console/3`.
> - Hướng dẫn: `docs/ADMIN_GUIDE.md` (có công thức nhân vật admin tối đa).

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

> **Đã làm (Đợt 3, 2026-10-04)** theo bảng 3.3. Khác thiết kế:
>
> - Làm trước C10 (cấp nâng theo từng món): "mất đồ" xóa đúng món đang mặc, không ảnh hưởng món cùng loại khác.
> - Bước có thể vỡ đồ: server đòi `confirm: true` (client hỏi lại), không chỉ client.
> - Tháp chỉ cho ngọc lần đầu lên tới tầng (tránh leo lại để cày); trùm trong tháp tính như quái thường. Rương Báu 3 / 8 / 15 %.
> - Simulator: bot vẫn không qua +5 (cần Vảy Cổ Long), nên chỉ báo số ngọc nhặt được (~3–4 / ván); số trận hạ Hắc Long
>   trước / sau lệch ≤ 1 %.
> - Chi tiết code: `CODEBASE_NOTES.md §9d`.

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
| `upgrade.levels` (bảng từng bước: ngọc, tỉ lệ, thất bại) | khóa mới `UPGRADE` (nay ở `priv/game_data/upgrade.json`) |
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

> **Đã làm (Đợt 3, 2026-10-04)** theo 4.3. Khác thiết kế:
>
> - Cánh và đồ ra từ máy là bản riêng (`Gear.plain`), nằm trong túi đồ hiếm.
> - **Từ §9 (đổi lớp MU):** 8 cánh `wing_{dk,dw,elf,mg}_{1,2}`: Cánh Ác Quỷ / Cánh Rồng (Kiếm Sĩ), Cánh Thiên Đường /
>   Cánh Linh Hồn (Phù Thủy), Cánh Tiên / Cánh Tinh Linh (Tiên Nữ), Cánh Bóng Tối / Cánh Hủy Diệt (Đấu Sĩ). Bảng 4.3 bên dưới
>   là thiết kế cũ (3 lớp).
> - Đấu trường: % cánh của đối thủ gộp vào tấn công (× (1 + dmg)) và máu (÷ (1 − absorb)), vì quái không có ô cánh.
> - NPC Lão Hỗn Nguyên đứng ở Làng [20, 6], hình tự vẽ (`npcs/chaos.png`).

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

**Công thức** (khóa mới `CHAOS`, nay ở `priv/game_data/chaos.json`):

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

**Đã chốt (2026-10-04, Phase 2):** 5-A và 5-B theo đề xuất. Đã làm: `e2e/` (xem `e2e/README.md`), CI
`.github/workflows/hac-long-e2e.yml`.

---

## 6. Bảng xếp hạng theo lớp

### 6.1 Hiện trạng

- `HacLong.Leaderboard` (`leaderboard.ex:16-81`): `level`, `kills`, `dragon`, `tower`, top 10, truy vấn thẳng **mỗi lần**, không cache.
- Kênh `"leaderboard"` gộp thêm bang, bang diệt Cổ Long, đấu trường, hạng của mình (`game_channel.ex:135-153`), giới hạn 20 lần / phút.
- Client: 7 nút trong tab Làng (`ui.js:598-625`), tự làm mới tối đa 30 giây một lần.

### 6.2 Lấy từ MU Web

`Mu.Leaderboard`: bảng theo lớp, **cache** làm mới theo chu kỳ, hạng của mình theo từng bảng.

### 6.3 Thiết kế

- Thêm loại `level_dk`, `level_dw`, `level_elf`, `level_mg` (sửa theo §9) (lọc `cls`, cùng thứ tự: chuyển sinh → cấp → xp).
- **Cache:** `HacLong.Leaderboard` thành GenServer giữ kết quả mọi bảng trong ETS, làm mới mỗi 60 giây.
  Kênh đọc từ ETS, không truy vấn DB mỗi lần. Server đông người thì đây là phần có lợi nhất.
- Hạng của mình: thêm hạng trong lớp (`level_rank` có lọc `cls`).
- Index mới: `(cls, rebirths DESC, level DESC, xp DESC)`.
- Client: dưới nút "Cấp cao" thêm hàng chọn **Tất cả / Kiếm Sĩ / Phù Thủy / Tiên Nữ / Đấu Sĩ** (dùng `icon` của lớp).
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
| 1-A | Giữ log vàng bao lâu | ✅ chốt: giữ hết, có lệnh dọn > 180 ngày |
| 1-B | Viết lại giao dịch thành một transaction | ✅ chốt: có (đã làm ở Đợt 2) |
| 1-C | Log đồ | ✅ chốt: chỉ đồ ngẫu nhiên (`gear`) |
| 2-A | Admin tặng đồ không rơi được | ✅ chốt: có |
| 2-B | Phân quyền mod / admin | ✅ chốt: có (`users.role`) |
| 3-A | Tỉ lệ / thất bại +6 → +11 | ✅ chốt: theo bảng 3.3 (mất đồ ở +10 / +11) |
| 3-B | Tỉ lệ / chỗ rơi ngọc | ✅ chốt: theo 3.3 |
| 3-C | Ngọc Sinh Mệnh (dòng tùy chọn) | ✅ chốt: để sau (chưa làm) |
| 3-D | Tên ngọc | ✅ chốt: Phúc Lành / Linh Hồn / Hỗn Nguyên |
| 4-A | Cấp / chỉ số cánh | ✅ chốt: 20 / 35; 10 % / 18 % |
| 4-B | Cánh qua chợ / giao dịch | ✅ chốt: được |
| 4-C | Công thức ra Ngọc Hỗn Nguyên | ✅ chốt: có |
| 4-D | Tên NPC / cánh | ✅ chốt: như 4.3 |
| 5-A | Quy mô soak | 30 bot / 10 phút |
| 5-B | Khi nào chạy e2e trên CI | chỉ khi sửa `reference/rpg-game/**` |
| 6-A | Top N, chu kỳ cache | top 10, 60 giây |

---

## 9. Bốn lớp nhân vật MU

> **Đã làm (2026-10-04).** Anh chốt: chỉ số theo MU (STR / AGI / VIT / ENE + MP), **xóa nhân vật cũ**, Đấu Sĩ tạo tự do,
> mỗi tài khoản một nhân vật. Mục FEATURE_CATALOG: B3 (điểm / cấp theo lớp), B7 (công thức theo lớp trong data), B1 (lên cấp
> hồi đầy máu + MP), một phần B8 (MP trong bảng chỉ số).

### 9.1 Lớp

| id | Tên (MU) | STR / AGI / VIT / ENE gốc | Điểm / cấp | Tấn công theo | Kỹ năng cấp 1 / 10 / 25 (MP) |
|---|---|---|---|---|---|
| `dk` | Kiếm Sĩ (Dark Knight) | 28 / 20 / 25 / 10 | 5 | STR | Chém Xoáy (8), Trảm Choáng (14), Nộ Chiến (20) |
| `dw` | Phù Thủy (Dark Wizard) | 18 / 18 / 15 / 30 | 5 | ENE | Cầu Lửa (10), Tia Sét (16), Khiên Linh Hồn (24) |
| `elf` | Tiên Nữ (Fairy Elf) | 22 / 25 / 20 / 15 | 5 | AGI + STR | Tam Tiễn (8), Hồi Sinh Lực (14), Tăng Sức Mạnh (20) |
| `mg` | Đấu Sĩ (Magic Gladiator) | 26 / 26 / 26 / 26 | 7 | STR + ENE | Kiếm Lửa (10), Kiếm Độc Hỏa (14), Phán Quyết (22) |

- Chỉ số gốc, điểm / cấp lấy từ MU Web (`priv/game_data/classes.json`). Hệ số công / thủ / máu / MP là của Hắc Long
  (`CLASSES[lớp].derived`), chỉnh bằng simulator để 4 lớp mạnh ngang 3 lớp cũ.
- Kỹ năng giữ kiểu đánh theo lượt của Hắc Long (hồi chiêu theo lượt) + tốn MP; tác dụng dùng lại các kiểu sẵn có
  (`effect`), thêm `fire_ball` (×2.0, xuyên 30 % giáp).
- MP: hồi 5 % tối đa mỗi lượt của người chơi; đầy khi lên cấp, nghỉ trọ, uống nước giếng. Chưa có bình MP (thêm cùng §10).

### 9.2 Simulator (20 ván / lớp trước, 5 ván / lớp sau)

| | Chỉ đánh (trận / chết) | +nâng cấp (trận / chết) |
|---|---|---|
| Trước: Chiến Binh / Thích Khách / Hiệp Sĩ | 440 / 0 · 440 / 1 · 436 / 0 | 340 / 0 · 342 / 1 · 341 / 0 |
| Sau: Kiếm Sĩ / Phù Thủy / Tiên Nữ / Đấu Sĩ | 440 / 1 · 441 / 0 · 439 / 0 · 432 / 0 | 341 / 0 · 341 / 0 · 345 / 0 · 336 / 0 |

### 9.3 Chưa làm (đi cùng §10)

- **B4** đồ khởi đầu theo lớp (gậy / cung cho Phù Thủy / Tiên Nữ): Hắc Long chưa có gậy phép, cung → làm khi có đồ từ Item.txt.
- **C4** đồ theo lớp (Đấu Sĩ không đội mũ), **C3** yêu cầu chỉ số, **C1** đủ 10 ô: cần dữ liệu `classes` / `req` từ Item.txt.
- Tóc: chỉ có 3 kiểu (Kiếm Sĩ, Đấu Sĩ dùng chung). Thêm tile tóc khi có.

## 10. Đồ từ Item.txt + hình đổi theo cấp

> **Công cụ đã có (2026-10-04)**, chờ anh đặt `Item.txt` và bộ hình vào `assets_src/items/` (xem README trong đó).
> `Item.txt` và icon `item_{group}_{index}` là dữ liệu của anh. Định dạng file: `docs/kb/KB_ITEM_REFERENCE.md §1` (repo ngoài).

### 10.1 Hình đổi theo cấp +N (dùng được ngay)

- Đặt hình vào `assets_src/items/icons/`:
  - `item_{nhóm}_{số}_{N}.png` cho đồ Item.txt;
  - `{id}_{N}.png` cho đồ Hắc Long hiện có, vd `broadsword_0.png`, `broadsword_5.png`, `broadsword_10.png`.
- Chạy `mix hac_long.icons` → chép sang `priv/static/assets/items/`, ghi `priv/static/assets/item_icons.json`.
- Game chọn mức lớn nhất ≤ cấp nâng; thiếu hình thì dùng icon cũ (không lỗi). Tải lại trang là thấy, không cần build lại.
- Gắn đồ Hắc Long với một dòng Item.txt: thêm `"ref": "nhóm/số"` vào món đó trong `priv/game_data/items.json` thì dùng hình `item_…`.

### 10.2 Thông số đồ từ Item.txt (bước tiếp theo)

- `mix hac_long.items.import` đọc `Item.txt` → `priv/items_raw.json` (nguyên số) và `priv/items_from_txt.json` (nháp đồ Hắc Long:
  `id item_g_i`, `ref`, `slot`, `atkMin` / `atkMax`, `def`, `level`, `req` STR/AGI/VIT/ENE gốc, `classes`, `cells`).
- **Chưa thay đồ trong game.** Bước ghép (đợt 4 trong FEATURE_CATALOG) sẽ:
  1. thay 18 vũ khí / giáp / khiên hiện có bằng đồ Item.txt theo từng lớp (cửa hàng Thợ Rèn, đồ rơi theo vùng, đồ trùm);
  2. mở các ô mũ / quần / găng / giày / nhẫn (C1, C2) và luật đồ theo lớp (C4), yêu cầu chỉ số (C3), đồ khởi đầu theo lớp (B4);
  3. đòn min~max (A1) nếu anh muốn, vì Item.txt có sẵn `DmgMin` / `DmgMax`;
  4. chạy simulator trước / sau.

### 10.3 ⛔ Câu hỏi (khi anh gửi Item.txt)

- **10-A** Yêu cầu chỉ số: dùng nguyên số trong file hay nhân hệ số (MU Web dùng 0,35 để nhân vật cấp thấp mặc được, xem KB §3.2)?
- **10-B** Lấy những món nào: toàn bộ (vũ khí 124 món; mũ 47, giáp / quần / găng / giày 54 món mỗi loại) hay chọn một bộ cho 6 vùng của Hắc Long (đề xuất:
  mỗi lớp 6–7 bậc đồ theo cấp vùng, phần còn lại để sau)?
- **10-C** Giá mua / bán: Item.txt không có giá → đề xuất theo cấp đồ (công thức trong `priv/game_data/rules.json`).
- **10-D** Bình MP (MU 14/4–6) và các ngọc, nhẫn, dây chuyền nhóm 13–14: thêm luôn hay để sau?


---

## 11. Công thức chiến đấu (Phase 3: A1, A2, A4)

> Viết 2026-10-04, **chờ anh chốt các câu ⛔ ở 11.5 rồi mới code**. Mục tiêu: đánh có cảm giác MU (đòn thấp ~ cao, "Trượt!",
> phạt đánh quái quá yếu) mà độ khó tổng thể giữ như hiện tại: simulator 4 lớp lệch ≤ 10 % số trận hạ Hắc Long, chết không
> tăng quá 1 lần (`PHASE_PLAN.md`, Phase 3).

### 11.1 Hiện trạng (đo 2026-10-04)

- Sát thương người → quái: `round(atk² / (atk + thủ) × ngẫu_nhiên(0,9 ~ 1,1) × hệ_số_kỹ_năng × (1 + sổ quái) × (1 + % cánh) × chí_mạng)`.
  Đòn thường bị quái **né** 3–7 % (`0,03 + cấp × 0,001`); kỹ năng luôn trúng.
- Quái → người: `atk² / (atk + thủ)` → chí mạng quái ×1,5 → × (1 − thủ thế) × (1 − % hấp thụ cánh). Người **né** theo AGI
  (`0,02 + AGI × 0,0025`, tối đa 40 %): Kiếm Sĩ / Đấu Sĩ / Phù Thủy ~7–9 %, Tiên Nữ 15 % (cấp 10) → 37 % (cấp 40).
- Tấn công người chơi lớn hơn nhiều thủ quái (cấp 20: công 230–290, thủ quái 40–50), nên công thức hiện tại gần như "ăn trọn"
  công; khoảng ngẫu nhiên chỉ ±10 %.
- Simulator gốc (`mix hac_long.simulate 20 --seed 1`, file `p3_before`): "chỉ đánh" ≈ 433–444 trận hạ Hắc Long, có nhiệm vụ /
  hằng ngày / nâng cấp / rương ≈ 330–375 trận, chết 0–1 lần, 20/20 ván thắng ở mọi lớp.

### 11.2 A1 — sát thương nhiều bước, đòn thấp ~ cao

Thứ tự (chỉ làm tròn ở bước cuối, A15):

1. **Đòn gốc** = số ngẫu nhiên trong **[công thấp, công cao]** của nhân vật.
   - Vũ khí có `atkMin` / `atkMax`. Đồ hiện có chưa có hai số này → **suy từ `atk`**: `atkMin = atk × (1 − s)`,
     `atkMax = atk × (1 + s)`, `s` trong `RULES.combat.weapon_spread` (Phase 6 lấy thẳng `DmgMin` / `DmgMax` từ Item.txt).
   - Công của nhân vật = phần chỉ số (STR / ENE / AGI theo lớp) + vũ khí + cấp ép. Đề xuất (**3-D**): khoảng ngẫu nhiên áp cho
     **toàn bộ công** (`công × (1 ± s)`), `s = 0,1` → trung bình và độ dao động giữ y như hôm nay (±10 %). Khi có đồ Item.txt thì
     phần vũ khí theo `DmgMin ~ DmgMax` thật, phần chỉ số giữ ±10 %.
2. × hệ số kỹ năng (`skill_effects.*.mult`) → **chí mạng** (× hệ số chí mạng) → × buff (cuồng nộ, suy yếu) × (1 + sổ quái)
   × (1 + % cánh).
3. **Trừ thủ**: giữ công thức mượt của Hắc Long `đòn² / (đòn + thủ)` (thủ cao vẫn ăn đòn, không có ngưỡng "0 sát thương" như MU).
4. **Sàn mềm**: không dưới `x %` đòn ở bước 2 (**3-B**, đề xuất 20 % như MU). Hiện thủ quái thấp nên sàn này chỉ có tác dụng
   khi sau này có quái thủ rất cao (Phase 6).
5. × (1 − thủ thế) × (1 − % hấp thụ cánh) (khi quái đánh người).
6. **Sàn cứng** 1, làm tròn.

Quái đánh người dùng cùng các bước: công quái ±10 % (bỏ `ngẫu_nhiên(0,9 ~ 1,1)` cũ, kết quả như cũ).

Giao diện: bảng nhân vật và tooltip vũ khí hiện **"Tấn công 207 ~ 253"** thay cho một số; số trong trận không đổi cách hiện.

### 11.3 A2 — tỉ lệ trúng

- **Người đánh quái:** `trúng = AR / (AR + DR)`, chặn **5 % ~ 95 %**.
  - `AR` (attack rate) người = `cấp × 5 + AGI × 1,5` (như MU).
  - `DR` (defense rate) quái = `cấp quái × k`, `k` trong `RULES.combat` (đề xuất **0,8**): Kiếm Sĩ cấp 10 đánh quái cấp 10 ≈ 91 %,
    cấp 20 đánh quái cấp 25 ≈ 87 %; Tiên Nữ (AGI cao) ≈ 93–95 %. Thay cho "quái né 3–7 %" hiện nay.
  - Trượt hiện **"Trượt!"** (số bay lên như hiện có). Kỹ năng: đề xuất **cũng tính trúng / trượt** như đòn thường (**3-E**).
- **Quái đánh người:** đề xuất (**3-A**) **giữ né theo AGI hiện tại** (đổi tên thành "né", số không đổi), vì đổi sang
  `AR / (AR + DR)` cho cả hai phía làm Tiên Nữ mất phần lớn né (37 % → ~15 %) → đổi cân bằng lớp lớn.
- **Đấu trường (PvP):** người đánh bản sao người khác — dùng né của đối thủ như hiện nay (không đổi).
- Hệ quả cân bằng: người chơi trúng ít hơn hiện tại ~4–9 % (tùy lớp, chênh cấp) → **chỉnh bù** bằng `k` hoặc hệ số công quái để
  simulator lệch ≤ 10 %. Số chốt bằng simulator, ghi bảng trước / sau vào đây.

### 11.4 A4 — phạt EXP chênh cấp

- Nhân vật cao hơn quái **hơn 10 cấp**: EXP × `max(10 %, 1 − 10 % × (chênh − 10))` (chênh 11 cấp: 90 %, 15 cấp: 50 %, ≥ 19 cấp: 10 %).
  Số trong `RULES.xp.penalty` (`from: 10`, `per_level: 0,1`, `min: 0,1`).
- Đề xuất (**3-C**) chỉ áp **quái thường ngoài bản đồ**; không áp trùm vùng, tháp, trùm thế giới, đấu trường, việc hằng ngày,
  nhiệm vụ. Nhật ký trận ghi "(EXP −40 % vì chênh cấp)" để người chơi hiểu.
- Không ảnh hưởng vàng / rơi đồ.

### 11.5 ⛔ Câu hỏi

| # | Câu hỏi | Đề xuất |
|---|---|---|
| **3-A** | Bỏ "né" hiện tại, thay bằng tỉ lệ trúng cho **cả hai phía**? Hay chỉ người đánh quái dùng tỉ lệ trúng, quái đánh người vẫn né theo AGI? | **Chỉ người đánh quái** dùng tỉ lệ trúng; quái đánh người giữ né theo AGI (không làm yếu Tiên Nữ) |
| **3-B** | Sàn mềm bao nhiêu % đòn gốc? | **20 %** (như MU) |
| **3-C** | Phạt EXP áp ở đâu? | **Chỉ quái thường**; không áp trùm, tháp, trùm thế giới, đấu trường |
| **3-D** | Khoảng đòn thấp ~ cao áp cho toàn bộ công (±10 % như hôm nay) hay chỉ phần vũ khí (đồ hiện có suy `atk ± 20 %`)? | **Toàn bộ công ±10 %** cho đến Phase 6; có Item.txt thì phần vũ khí theo `DmgMin ~ DmgMax` |
| **3-E** | Kỹ năng có thể trượt không (hiện luôn trúng)? | **Có**, như đòn thường (công bằng, MU cũng vậy) |

### 11.6 Làm và kiểm

- `Engine.damage/…` thành một hàm thuần nhiều bước (`Engine.hit/…` trả `{trúng?, chí_mạng?, sát_thương}`), test với số ngẫu nhiên
  cố định từng bước; số mới trong `RULES.combat`, `RULES.xp.penalty`.
- `derived/1` thêm `atkMin`, `atkMax`, `hitRate` (theo quái cùng cấp, để hiện ở bảng nhân vật).
- Simulator 20 lượt / lớp trước / sau (`--seed 1`), bảng so sánh ghi vào 11.7; e2e smoke + `mix test`.
