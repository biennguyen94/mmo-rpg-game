# Hướng dẫn quản trị Hắc Long

Tài liệu cho người vận hành server: cấp quyền, dùng tab **Quản trị** trong game, lệnh dòng lệnh,
nhật ký vàng / đồ hiếm / quản trị, và công thức dựng nhân vật admin.

> Viết theo mẫu `docs/ADMIN_GUIDE.md` của MU Web. Thiết kế: `docs/INTEGRATION_PLAN.md` mục 1–2;
> code: `lib/hac_long/admin.ex`, `lib/hac_long/audit.ex`, `game_channel.ex` (phần `# ---------- Quản trị`).

## Mục lục

1. [Vai trò và cấp quyền](#1-vai-trò-và-cấp-quyền)
2. [Tab Quản trị](#2-tab-quản-trị)
3. [Chỉnh nhân vật](#3-chỉnh-nhân-vật)
4. [Nhật ký và kiểm tra vàng](#4-nhật-ký-và-kiểm-tra-vàng)
5. [Dòng lệnh](#5-dòng-lệnh)
6. [Công thức: nhân vật admin tối đa](#6-công-thức-nhân-vật-admin-tối-đa)
7. [Giao dịch trực tiếp an toàn (cho người vận hành)](#7-giao-dịch-trực-tiếp-an-toàn-cho-người-vận-hành)
8. [Xử lý sự cố](#8-xử-lý-sự-cố)

---

## 1. Vai trò và cấp quyền

Mỗi tài khoản có một vai trò (`users.role`):

| Vai trò | Thấy tab Quản trị | Được làm |
|---|---|---|
| `player` | không | chơi bình thường |
| `mod` | có | xem / xử lý báo cáo chat (bỏ qua, cấm chat; **không** khóa), tra cứu người chơi, cấm / bỏ cấm chat, thông báo toàn server |
| `admin` | có | tất cả: thêm khóa / mở khóa tài khoản, tặng quà qua thư, gọi trùm thế giới, **chỉnh nhân vật**, kiểm tra vàng, xem nhật ký |

Tài khoản `admin = true` cũ được migration `20261027000000` chuyển thành `admin`.

**Cấp quyền** (người đó tải lại trang để thấy tab):

```bash
# máy dev
mix hac_long.admin ten_dang_nhap               # admin
mix hac_long.admin ten_dang_nhap --role mod    # mod
mix hac_long.admin ten_dang_nhap --revoke      # về player

# bản release / Docker
docker compose exec app bin/hac_long eval 'HacLong.Release.admin("ten_dang_nhap")'
docker compose exec app bin/hac_long eval 'HacLong.Release.role("ten_dang_nhap", "mod")'
docker compose exec app bin/hac_long eval 'HacLong.Release.admin("ten_dang_nhap", false)'
```

Mod gọi lệnh chỉ dành cho admin → "Cần quyền quản trị viên."; người chơi thường → "Không có quyền.".

## 2. Tab Quản trị

Thứ tự các khối trong tab:

1. **Báo cáo chưa xử lý**: tin chat bị báo cáo. Nút *Bỏ qua*, *Cấm chat 1 giờ*, *Khóa 1 ngày* (chỉ admin).
2. **Tra cứu người chơi**: gõ tên nhân vật hoặc tên đăng nhập. Thẻ kết quả: cấp, vàng, số quái, số lần bị báo cáo,
   trạng thái khóa / cấm chat, các nút cấm chat / khóa, và **gửi quà qua thư** (admin).
3. **Chỉnh nhân vật** (admin, hiện dưới thẻ tra cứu): xem mục 3.
4. **Thông báo cho cả server**: hiện trong chat của mọi người.
5. **Quà cho mọi người** (admin): thư kèm vàng / kinh nghiệm / đồ vào hộp thư mọi nhân vật.
6. **Trùm thế giới** (admin): gọi Cổ Long xuất hiện ngay.
7. **Kiểm tra vàng** (admin): xem mục 4.
8. **Nhật ký quản trị** (admin): 50 thao tác mới nhất.

Quà qua thư và chỉnh nhân vật khác nhau: quà nằm trong hộp thư, người chơi phải bấm nhận; chỉnh nhân vật đổi
ngay (người đang online thấy liền), kể cả khi người đó offline.

## 3. Chỉnh nhân vật

Mỗi dòng trong khối là một lệnh (`op` của kênh `"admin"`, xem `HacLong.Admin`):

| Dòng | `op` | Tham số | Ghi chú |
|---|---|---|---|
| Kinh nghiệm | `give_xp` | `xp` 1..1 000 000 000 | lên cấp như đánh quái (mỗi cấp +3 điểm tiềm năng), dừng ở cấp tối đa 50 |
| Đặt cấp | `set_level` | `level` 1..50 | xp về 0; điểm tiềm năng ± 3 × số cấp đổi (không dưới 0); hồi đầy máu |
| Vàng | `add_gold` | `amount` (âm để trừ) | không xuống dưới 0 |
| Điểm tiềm năng | `add_points` | `n` (âm để trừ) | |
| Chỉ số | `add_stats` | `str`, `vit`, `agi`, `def` (âm để trừ) | cộng thẳng vào chỉ số, không dưới 1 |
| Đồ thường | `give_item` | `id`, `count` 1..9999, `up` 0..5 | **mọi** món trong `game_data.json`, cả đồ không bán / chỉ rơi từ trùm (`relic`, `dragonshield`); `up` là cấp nâng (chỉ vũ khí / giáp / khiên) |
| Đồ hiếm | `give_gear` | `base`, `rarity` 1..3, `bonus` `{str, vit, agi, def}`, `up` | tạo một món chỉ số ngẫu nhiên với chỉ số chọn sẵn; để 0 cả bốn ô thì tự lấy `rarity` dòng đầu với mức cao nhất đồ rơi ở cấp đó có thể có. Túi đồ hiếm đầy (20) thì báo lỗi |
| Hồi đầy máu | `heal` | | |

- Lệnh chạy **trong tiến trình Session** của người đó, nên không đè lên lệnh người chơi đang gửi.
- Mỗi lệnh ghi một dòng `admin_log` (cả khi lỗi) và ghi nhật ký vàng / đồ hiếm với lý do `ADMIN`, `ref = admin:<mã dòng admin_log>`.
- Đồ thường nâng cấp: cấp nâng lưu theo **loại đồ** (`upgrades[id]`), nên tặng `relic +5` thì mọi Thánh Kiếm của người đó đều +5.

## 4. Nhật ký và kiểm tra vàng

### 4.1 Ba bảng nhật ký

| Bảng | Ghi gì | Ghi lúc nào |
|---|---|---|
| `gold_log` | `user_id, delta, balance, reason, ref, inserted_at` | mỗi lần vàng của nhân vật đổi, **cùng transaction** với lần lưu nhân vật (`Characters.save!/4`) |
| `gear_log` | `user_id, uid, base, rarity, action (in/out), reason, ref` | đồ hiếm (`uid` bắt đầu bằng `#`) vào / ra nhân vật, cùng transaction |
| `admin_log` | `admin_id, admin_name, op, target_id, params, result` | mọi thao tác quản trị có thay đổi dữ liệu (tra cứu, xem báo cáo, xem nhật ký thì không ghi) |

`reason` của `gold_log` / `gear_log`:

- Lệnh người chơi: tên lệnh viết hoa, vd `ATTACK` (đánh quái), `SELL`, `BUY`, `REST`, `UPGRADE`, `MARKET_BUY`, `MAIL_CLAIM`, `GUILD_DONATE`, `CREATE`.
  `ref` là `id` / `listing` / `uid` của lệnh nếu có (vd `SELL` + `dagger`).
- Do server: `TRADE` (giao dịch trực tiếp, `ref = trade:<A>-<B>-<thời điểm>` giống nhau ở hai bên), `WORLD_BOSS`, `PARTY`,
  `ADMIN`, `MOVE` (ghi dồn vị trí), `DELETE` / `RESET` (xóa nhân vật).
- Dữ liệu cũ: `BASELINE` (vàng / đồ hiếm lúc chạy migration). Dọn nhật ký: `CARRY` (mục 4.3).

Tổng `delta` của một tài khoản luôn bằng vàng hiện có. Đó là điều kiện đối soát.

### 4.2 Kiểm tra vàng

Trong game: tab Quản trị → **Kiểm tra vàng** → *1 ngày* / *7 ngày*. Dòng lệnh: `mix hac_long.audit [--days 7]`.

Lỗi (dòng lệnh thoát mã 1, hợp cho cron):

| Lỗi | Nghĩa | Làm gì |
|---|---|---|
| `gold_mismatch` | vàng nhân vật ≠ tổng nhật ký | có chỗ sửa thẳng database, hoặc code mới ghi nhân vật không qua `Characters.save!`. Xem `gold_log` của người đó |
| `gear_duplicate` | cùng `uid` đồ hiếm ở hai chỗ (hai nhân vật, hoặc nhân vật và chợ) | **dấu hiệu nhân đồ**. Tra `gear_log` theo `uid` để thấy đồ đi đường nào |
| `gear_unlogged` | đồ hiếm đang ở nhân vật nhưng dòng nhật ký cuối của nó không phải `in` cho người đó | thường đi kèm `gear_duplicate` |

Thống kê (không phải lỗi): vàng vào / ra theo lý do và 10 người nhận nhiều vàng nhất trong N ngày.
Một lý do tăng vọt bất thường (vd `SELL` gấp 10 lần mọi ngày) là chỗ nên xem trước.

Xem nhật ký một người: thẻ tra cứu → **Nhật ký vàng** (50 dòng mới nhất) / **Nhật ký quản trị**.
Tra đồ hiếm bằng SQL:

```sql
SELECT * FROM gear_log WHERE uid = '#ABCDEFGH' ORDER BY id;
SELECT * FROM gold_log WHERE user_id = 42 ORDER BY id DESC LIMIT 100;
```

### 4.3 Dọn nhật ký cũ

```bash
mix hac_long.audit --prune 180
docker compose exec app bin/hac_long eval 'HacLong.Release.prune_logs(180)'
```

- `gold_log`: dòng cũ hơn 180 ngày của mỗi tài khoản gộp thành **một dòng `CARRY`**, nên tổng vẫn khớp.
- `gear_log`: xóa dòng cũ, nhưng giữ dòng cuối cùng của mỗi `uid` (đối soát cần biết đồ đang ở đâu).
- Không bắt buộc: mặc định giữ hết.

### 4.4 Cron gợi ý

```cron
# 4 giờ sáng: đối soát; có lỗi thì in ra stderr và thoát mã 1 (cron gửi mail)
0 4 * * *  cd /srv/hac_long && docker compose exec -T app bin/hac_long eval 'HacLong.Release.audit(1)'
# Chủ nhật: dọn nhật ký > 180 ngày
0 5 * * 0  cd /srv/hac_long && docker compose exec -T app bin/hac_long eval 'HacLong.Release.prune_logs(180)'
```

## 5. Dòng lệnh

Trên server đang chạy (bản release), `rpc` chạy **trong** node đang chạy nên thấy Session của người đang online:

```bash
# chỉnh nhân vật (người ra lệnh ghi là "console" trong admin_log)
docker compose exec app bin/hac_long rpc 'HacLong.Admin.console("Tên Nhân Vật", "give_xp", %{"xp" => 50000}) |> IO.inspect()'
docker compose exec app bin/hac_long rpc 'HacLong.Admin.console("ten_dang_nhap", "add_gold", %{"amount" => 100000}) |> IO.inspect()'

# xem 20 thao tác quản trị mới nhất
docker compose exec app bin/hac_long rpc 'HacLong.Admin.recent(20) |> IO.inspect()'

# đối soát (eval: node riêng, có lỗi thì thoát mã 1)
docker compose exec app bin/hac_long eval 'HacLong.Release.audit(7)'
```

`rpc` chạy trong server đang chạy (dùng cho lệnh sửa nhân vật, để Session của người đang online thấy ngay);
`eval` mở node riêng (dùng cho đối soát, dọn nhật ký, cấp quyền). Đừng gọi `System.halt` qua `rpc`: nó tắt server.

Máy dev (server đang chạy bằng `mix phx.server`): dùng tab Quản trị, hoặc console trình duyệt (mục 6).
`mix hac_long.audit` chạy được song song với server (chỉ đọc database).

Lệnh kênh `"admin"` đầy đủ (cho người viết công cụ): xem bảng giao thức trong `README.md`.

## 6. Công thức: nhân vật admin tối đa

Đăng nhập tài khoản admin, mở console trình duyệt (F12 → Console), dán cả khối. `Net.userId` là tài khoản đang
đăng nhập; đổi thành id người khác nếu muốn dựng cho họ (id lấy ở thẻ tra cứu hoặc `Net.admin('lookup', {name})`).

```js
const uid = Net.userId;
const A = async (op, p = {}) => { try { const r = await Net.admin(op, { uid, ...p }); console.log(op, r.msg); } catch (e) { console.warn(op, e.msg); } };

// cấp tối đa (50): +3 điểm tiềm năng mỗi cấp
await A('set_level', { level: 50 });

// vàng, điểm tiềm năng, chỉ số
await A('add_gold', { amount: 100000000 });
await A('add_points', { n: 300 });
await A('add_stats', { str: 200, vit: 200, agi: 100, def: 150 });

// vũ khí / giáp / khiên tốt nhất, nâng tối đa (+5)
await A('give_item', { id: 'relic', count: 1, up: 5 });        // Thánh Kiếm Diệt Long (chỉ rơi từ trùm)
await A('give_item', { id: 'breastplate', count: 1, up: 5 });  // Giáp Ngực Thép
await A('give_item', { id: 'dragonshield', count: 1, up: 5 }); // Khiên Vảy Rồng (chỉ rơi từ trùm)

// đồ hiếm Sử Thi tự chọn chỉ số (mặc thay đồ thường nếu muốn)
await A('give_gear', { base: 'relic', rarity: 3, bonus: { str: 30, agi: 20, vit: 20 }, up: 5 });
await A('give_gear', { base: 'breastplate', rarity: 3, bonus: { vit: 30, def: 30, str: 10 }, up: 5 });
await A('give_gear', { base: 'dragonshield', rarity: 3, bonus: { def: 30, vit: 30, agi: 10 }, up: 5 });

// bình máu, nguyên liệu nâng cấp / nấu ăn
await A('give_item', { id: 'potion_l', count: 200 });
await A('give_item', { id: 'ore_rare', count: 100 });
await A('give_item', { id: 'dragon_scale', count: 20 });
await A('give_item', { id: 'mam_co', count: 20 });

await A('heal');
```

Sau đó mở tab **Túi đồ** (phím `I`), kéo vũ khí / giáp / khiên vào ô trang bị. Kiểm lại: tab Quản trị →
tra chính mình → **Nhật ký quản trị** có đủ các dòng; **Kiểm tra vàng** vẫn "Không có lỗi".

Không có trong công thức (Hắc Long chưa có lệnh quản trị cho): chuyển sinh, thú cưng, kỹ năng (kỹ năng mở theo cấp,
cấp 50 là đủ), thành tựu, nhiệm vụ.

## 7. Giao dịch trực tiếp an toàn (cho người vận hành)

Từ Đợt 2, giao dịch trực tiếp giữa hai người ghi **cả hai nhân vật trong một transaction** (`HacLong.Trade.execute/1`):

1. Giữ Session người A rồi người B (`Session.hold/1`). Trong lúc giữ, mọi lệnh khác của hai người xếp hàng đợi
   (thường vài mili giây), Session không tự ghi vị trí.
2. Lấy đồ hai bên, trao chéo bằng hàm thuần; ghi hai nhân vật trong một `Repo.transaction` (nhật ký `TRADE`, cùng `ref`).
3. Nhả hai Session với nhân vật mới (`Session.release/3`); lỗi ở bất kỳ bước nào thì nhả mà **không ai đổi gì**.

Giữ quá 3 giây (tiến trình giao dịch chết giữa chừng) thì Session tự nhả, log `warning` "giao dịch giữ quá 3000 ms".
Thấy dòng này thường xuyên là có vấn đề, nên báo lập trình viên.

## 8. Xử lý sự cố

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| Không thấy tab Quản trị | chưa tải lại trang sau khi cấp quyền; vai trò vẫn `player` | `SELECT username, role FROM users WHERE username = '...'`, cấp lại, tải lại trang |
| "Cần quyền quản trị viên." | tài khoản là `mod` | cấp `admin` nếu cần |
| "Người này chưa có nhân vật." | tài khoản chưa tạo nhân vật / đã xóa | |
| "Túi đồ hiếm đã đầy (20 món)." | `give_gear` khi túi đủ 20 món chưa mặc | bảo người chơi bán bớt, hoặc tặng đồ thường |
| `gold_mismatch` sau khi sửa SQL tay | sửa vàng thẳng database không có dòng nhật ký | đừng sửa tay; dùng `add_gold`. Đã lỡ thì thêm một dòng `gold_log` (`reason = 'MANUAL'`, `delta` = phần chênh) |
| Kiểm tra vàng chậm | bảng nhật ký lớn | dọn `--prune 180` |
