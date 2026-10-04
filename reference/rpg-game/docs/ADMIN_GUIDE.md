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
9. [Ép đồ, Máy Hỗn Nguyên, khóa đồ (Đợt 3)](#9-ép-đồ-máy-hỗn-nguyên-khóa-đồ-đợt-3)
10. [Hình đồ theo cấp và Item.txt](#10-hình-đồ-theo-cấp-và-itemtxt)
11. [Chỉnh số luật chơi, từ cấm khi đặt tên](#11-chỉnh-số-luật-chơi-từ-cấm-khi-đặt-tên)

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
| Chỉ số | `add_stats` | `str`, `agi`, `vit`, `ene` (âm để trừ) | cộng thẳng vào chỉ số, không dưới 1 |
| Đồ thường | `give_item` | `id`, `count` 1..9999, `up` 0..11 | **mọi** món trong `priv/game_data/items.json`, cả đồ không bán / chỉ rơi từ trùm (`relic`, `dragonshield`), ngọc (`jewel_bless`, `jewel_soul`, `jewel_chaos`), cánh (`wing_<lớp>_1`, `wing_<lớp>_2`). Có `up` (vũ khí / giáp / khiên / cánh) hoặc là cánh thì mỗi món là một **bản riêng** trong túi đồ hiếm (cần chỗ trống) |
| Đồ hiếm | `give_gear` | `base`, `rarity` 1..3, `bonus` `{str, agi, vit, ene}`, `up` | tạo một món chỉ số ngẫu nhiên với chỉ số chọn sẵn; để 0 cả bốn ô thì tự lấy `rarity` dòng đầu với mức cao nhất đồ rơi ở cấp đó có thể có. Túi đồ hiếm đầy (20) thì báo lỗi |
| Hồi đầy máu | `heal` | | |

- Lệnh chạy **trong tiến trình Session** của người đó, nên không đè lên lệnh người chơi đang gửi.
- Mỗi lệnh ghi một dòng `admin_log` (cả khi lỗi) và ghi nhật ký vàng / đồ hiếm với lý do `ADMIN`, `ref = admin:<mã dòng admin_log>`.
- Từ Đợt 3, cấp nâng lưu theo **từng món** (`upgrades[uid]`): đồ thường được tách thành bản riêng (độ hiếm 0) khi
  nâng cấp, khóa, hoặc khi admin tặng kèm `up`. Dữ liệu cũ (cấp theo loại) tự tách lúc người chơi vào game.

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
await A('add_stats', { str: 200, agi: 150, vit: 200, ene: 150 });   // STR / AGI / VIT / ENE như MU

// đồ hiếm Sử Thi tự chọn chỉ số, nâng tối đa (+11, từ +10 mỗi cấp tính gấp đôi)
await A('give_gear', { base: 'relic', rarity: 3, bonus: { str: 30, agi: 20, vit: 20 }, up: 11 });       // Thánh Kiếm Diệt Long
await A('give_gear', { base: 'breastplate', rarity: 3, bonus: { vit: 30, agi: 30, str: 10 }, up: 11 }); // Giáp Ngực Thép
await A('give_gear', { base: 'dragonshield', rarity: 3, bonus: { ene: 30, vit: 30, agi: 10 }, up: 11 }); // Khiên Vảy Rồng

// cánh cấp 2 đúng lớp, +11 (dk / dw / elf / mg); cấp mặc 35
const cls = (await Net.send({ act: 'title_set', id: null })).player.cls;
await A('give_item', { id: `wing_${cls}_2`, count: 1, up: 11 });

// ngọc để tự ép / ghép thêm
await A('give_item', { id: 'jewel_bless', count: 20 });
await A('give_item', { id: 'jewel_soul', count: 20 });
await A('give_item', { id: 'jewel_chaos', count: 20 });

// bình máu, nguyên liệu nâng cấp / nấu ăn
await A('give_item', { id: 'potion_l', count: 200 });
await A('give_item', { id: 'ore_rare', count: 100 });
await A('give_item', { id: 'dragon_scale', count: 20 });
await A('give_item', { id: 'mam_co', count: 20 });

await A('heal');
```

Sau đó mở tab **Túi đồ** (phím `I`), kéo vũ khí / giáp / khiên / cánh vào ô trang bị (hoặc bấm món → **Trang bị**).
Nên bấm **🔒 Khóa** cho từng món để không lỡ bán / rao chợ / bỏ vào máy ghép. Kiểm lại: tab Quản trị →
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

## 9. Ép đồ, Máy Hỗn Nguyên, khóa đồ (Đợt 3)

Số liệu ở `priv/game_data/upgrade.json` (`UPGRADE`, `JEWELS`), `chaos.json` (`CHAOS`), `items.json` (các món `jewel_*`, `wing_*`), `rules.json` (`RULES.upgrade`: giá, % cộng mỗi cấp); sửa xong phải build lại.

- **Thợ Rèn:** +1 → +5 bằng quặng (chắc chắn). +6 bằng Ngọc Phúc Lành (100 %); +7 / +8 / +9 bằng Ngọc Linh Hồn
  (70 / 60 / 50 %, thất bại tụt 1 cấp); +10 / +11 bằng Ngọc Hỗn Nguyên (50 / 45 %, thất bại **vỡ đồ**: vũ khí về Gậy Gỗ,
  giáp về Áo Da Mỏng, khiên / cánh trống). Ép thành công từ +7 thì báo cả server.
- **Ngọc rơi:** quái cấp ≥ 12 (0,6 %), trùm vùng (30 %; trùm trong tháp tính như quái thường), top 3 trùm thế giới
  (1 viên), Tháp Vô Tận mỗi 10 tầng (chỉ lần đầu lên tới tầng đó), Rương Báu (3 / 8 / 15 %).
- **Máy Hỗn Nguyên** (Lão Hỗn Nguyên, Làng): cánh cấp 1 (đồ +5↑ + 1 Hỗn Nguyên + 20 000 vàng, 10 % + 5 % mỗi cấp trên +5,
  tối đa 60 %), cánh cấp 2 (cánh cấp 1 +5↑ + 5/5/2 ngọc + 200 000 vàng, 20 % + …), Ngọc Hỗn Nguyên (10 Mithril + 1 Vảy
  Cổ Long + 5 000 vàng, 70 %). Thất bại mất hết. Ghép cánh thành công thì báo cả server.
- **Khóa đồ:** người chơi khóa / mở khóa trong bảng chi tiết món đồ. Đồ khóa không bán, rao chợ, giao dịch, bỏ vào máy được.
- Người chơi mất đồ do ép / ghép thất bại: đó là luật chơi. Muốn đền thì tra `gear_log` theo `uid` (lý do `UPGRADE` /
  `CHAOS`, hành động `out`) rồi tặng lại bằng `give_gear` / `give_item` kèm `up`.

### Ngọc Sinh Mệnh, Tủ Đồ, vứt đồ, trần thư (Phase 4)

- **Ngọc Sinh Mệnh** (`jewel_life`): ép ở Thợ Rèn, mỗi dòng +4 tấn công (vũ khí) / phòng thủ (giáp, khiên, cánh), tối đa 4
  dòng, 50 %; thất bại mất một dòng. Số ở `RULES.upgrade.life`; tỉ lệ rơi theo `JEWELS.weights.jewel_life` (`upgrade.json`).
- **Tủ Đồ** ở Nhà: 40 loại đồ thường + 20 đồ hiếm, mở rộng +10 đồ hiếm × 3 lần bằng vàng (`RULES.storage`). Đồ hiếm đang cất
  vẫn thuộc danh sách đồ của nhân vật (cờ `stored`); cất / lấy không ghi `gear_log`.
- **Vứt đồ:** đồ hiếm vứt đi ghi `gear_log` `out` lý do `DISCARD`; muốn trả lại thì tra `uid` như đồ vỡ khi ép.
- **Thư quản trị** (`gift`, cả "gửi mọi người"): mỗi thư tối đa `RULES.mail.max_gold` vàng và `max_xp` EXP (1 000 000).
  Vượt thì báo "Mỗi thư tối đa … vàng." và không gửi. Thư hệ thống (bán chợ, quà bang) không bị giới hạn.

### Golden Invasion (Phase 7)

- Tự chạy mỗi 2 giờ (0h, 2h… giờ Việt Nam), 15 phút. Tab Quản trị → "Golden Invasion" → **Bắt đầu ngay** để chạy thử / bù.
- Chỉnh ở `rules.json` → `RULES.invasion`: `every_hours`, `minutes`, `maps` (bản đồ → số quái vàng), `strength_mult`,
  `reward_mult`, `jewel_chance`, `boss`, `boss_jewel_chance`. Build lại sau khi sửa.

### Xã hội, PK cược vàng, chiến bang (Phase 5)

- **Đang online:** tab Quản trị → "Đang online" → Xem (tên, lớp, cấp, bản đồ; Tra để mở thông tin). Mod cũng xem được.
- **PK cược vàng:** cược 100 – 1 000 000 vàng (`RULES.pk`), không phí, 10 trận / ngày. Mỗi trận một dòng ở bảng `pk_matches`
  (người mời, người nhận, cược, người thắng; `winner_id` trống = hòa); nhật ký vàng lý do `PK_BET`, ref `pk:<id>`. Không phí và
  không giới hạn cấp nên cược cũng là một đường chuyển vàng giữa hai tài khoản (như giao dịch): tra `gold_log` theo `PK_BET`
  nếu nghi chuyển vàng cho nick phụ.
- **Chiến bang:** bảng `guild_wars` (`result` trống = đang chiến; `a` / `b` / `draw`). Thưởng (`RULES.guild_war`): quỹ bang thắng
  +5 000, người có điểm nhận 500 vàng qua thư "Thưởng chiến bang".
- **Hộp thư:** giữ 100 thư, thư quá 30 ngày tự xóa trừ thư còn quà chưa nhận (`RULES.mail.keep`, `expire_days`).
- **Giao dịch:** lời mời 30 s, mở tối đa 180 s, hai người cách ≤ 8 ô cùng bản đồ (`RULES.trade`).

## 10. Hình đồ theo cấp và Item.txt

Dữ liệu của anh đặt ở `reference/rpg-game/assets_src/items/` (đưa vào git bình thường):

```
assets_src/items/
  Item.txt          ← bảng đồ
  icons/            ← hình đồ (PNG / WebP)
```

### 10.1 Thay hình đồ (dùng được ngay)

1. Đặt hình vào `assets_src/items/icons/`, tên theo mẫu:

   | Tên file | Dùng cho |
   |---|---|
   | `{id}_{N}.png` | đồ Hắc Long hiện có, từ cấp **+N** trở lên (vd `broadsword_0.png`, `broadsword_5.png`, `broadsword_10.png`) |
   | `{id}.png` | đồ Hắc Long, mọi cấp |
   | `item_{nhóm}_{số}_{N}.png`, `item_{nhóm}_{số}.png` | đồ có `"ref": "nhóm/số"` (dòng trong Item.txt) |

   `id` là khóa món đồ trong `priv/game_data/items.json` (`club`, `broadsword`, `relic`, `wing_dk_1`, `jewel_bless`…).
2. Chạy `mix hac_long.icons` (trong `reference/rpg-game`). Lệnh in số hình đã nhận, file bị bỏ qua (sai tên) và danh sách
   đồ chưa có hình riêng.
3. Tải lại trang. Game chọn hình có mốc **lớn nhất ≤ cấp nâng** của món: có `_0`, `_5`, `_10` thì +0…+4 dùng `_0`,
   +5…+9 dùng `_5`, +10, +11 dùng `_10`. Mốc tùy anh. Thiếu hình thì dùng icon cũ, không lỗi.
4. Deploy: commit `assets_src/items`, `priv/static/assets/items`, `priv/static/assets/item_icons.json` rồi làm như
   `docs/DEPLOY.md` (bản Docker không chạy được `mix`).

Thư mục khác: `mix hac_long.icons --src ~/hinh-do` hoặc biến `HL_ITEM_ICONS_DIR`.

### 10.2 Đọc Item.txt (nháp, chưa thay đồ trong game)

```bash
mix hac_long.items.import                 # mặc định assets_src/items/Item.txt
mix hac_long.items.import đường/dẫn/Item.txt
```

- Ghi `priv/items_raw.json` (nguyên số trong file) và `priv/items_from_txt.json` (đồ dạng Hắc Long: `id item_{nhóm}_{số}`,
  `ref`, ô, đòn thấp / cao, phòng thủ, cấp, yêu cầu STR / AGI / VIT / ENE, lớp mặc được).
- In số món theo nhóm và cảnh báo dòng hỏng (thiếu cột, chữ ở chỗ số…).
- Đưa đồ này vào game (cửa hàng, rơi theo vùng, đồ theo lớp, đủ 10 ô trang bị) là **Phase 6** trong `docs/PHASE_PLAN.md`.

## 11. Chỉnh số luật chơi, từ cấm khi đặt tên

Từ Phase 1, dữ liệu game nằm ở thư mục `priv/game_data/` (mỗi loại một file), số luật chơi ở
`priv/game_data/rules.json` (khóa `RULES`). Sửa xong phải **build lại** (`mix compile` / deploy lại), như sửa đồ hay quái.

| Muốn chỉnh | Chỗ sửa trong `rules.json` |
|---|---|
| Cấp tối đa, vàng / bình máu lúc tạo nhân vật, chuyển sinh, giá nghỉ trọ, phạt khi chết | `character` |
| EXP cần lên cấp (`coef × cấp^exp + base`); phạt EXP khi cao hơn quái thường > 10 cấp | `xp`, `xp.penalty` |
| Chí mạng, hệ số chí mạng, né theo Nhanh nhẹn; % hồi MP mỗi lượt; tỉ lệ bỏ chạy; đòn thấp ~ cao (`damage_spread`), sàn mềm (`soft_floor`), tỉ lệ trúng quái (`hit`) | `combat` |
| Sức mạnh kỹ năng (hệ số đòn, số lượt, % hiệu ứng) | `skill_effects` (theo kiểu tác dụng, xem `effect` của kỹ năng trong `classes.json`) |
| Chỉ số quái theo cấp, hệ số trùm | `monster` |
| Tỉ lệ rơi bình máu / đồ hiếm, độ hiếm | `loot` |
| Giá bán lại (40 %) | `shop.sell_ratio` |
| Rương, rèn, tháp, thú cưng, sổ quái, nhà, lễ hội, việc hằng ngày, câu cá | `chests`, `crafting`, `tower`, `pets`, `bestiary`, `home`, `events`, `daily`, `fishing` |
| Bang (giá lập, mốc quỹ, thưởng nhiệm vụ tuần), chợ (phí, số món), đấu trường, tổ đội | `guild`, `market`, `arena`, `party` |
| Từ cấm khi đặt tên nhân vật / bang | `names` |
| Ngọc Sinh Mệnh; sức chứa Tủ Đồ và giá mở rộng; trần vàng / EXP mỗi thư quản trị | `upgrade.life`, `storage`, `mail` |
| PK cược vàng, chiến bang, tổ đội (chia thưởng, hạn mời), giao dịch tự hủy, hộp thư (giữ / hết hạn), xếp hạng (top, cache), phó bang tối đa, hạn đơn xin vào | `pk`, `guild_war`, `party`, `trade`, `mail`, `leaderboard`, `guild.max_officers`, `guild.request_days` |

- **Gõ nhầm id** (món đồ, quái, lớp…) ở bất kỳ file nào trong `priv/game_data/` hay `priv/maps/` thì build **dừng** và in
  danh sách lỗi, vd `shop.json: SHOP có món "daggerr" không có trong ITEMS`. Sửa đúng id rồi build lại.
- Đổi số cân bằng thì chạy `mix hac_long.simulate 20 --seed 1` trước và sau để so (cùng seed → cùng kết quả nếu số không đổi).

**Từ cấm** (`names`):

- `banned_words`: khớp **nguyên từ**, không phân biệt hoa thường và dấu (`"quan tri"` chặn "Quản Trị", "QUAN TRI"; số và
  ký hiệu là chỗ ngắt từ nên `"gm"` chặn "GM01" nhưng `"lon"` không chặn "Thiên Long"). Viết không dấu, chữ thường; cụm
  nhiều từ được.
- `banned_parts`: khớp **một phần** tên viết liền (bỏ khoảng trắng, đổi số kiểu `4dm1n` → `admin`). Chỉ để từ dài, rõ
  nghĩa, nếu không sẽ chặn nhầm tên thường.
- Áp dụng khi tạo nhân vật mới, lập bang mới (tên và ký hiệu). Tên đã có không bị đổi.
