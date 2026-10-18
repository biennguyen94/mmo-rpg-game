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
12. [Đợt 8 phase 2026-10: tự đánh, bot mua bình, bộ hình Pixel, vùng chuyển sinh](#12-đợt-8-phase-2026-10)

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
   trạng thái khóa / cấm chat, các nút cấm chat / khóa. (Bỏ "gửi quà" riêng từ Phase 11: dùng **Chỉnh nhân vật**.)
3. **Chỉnh nhân vật** (admin, hiện dưới thẻ tra cứu): xem mục 3.
4. **Thông báo cho cả server**: hiện trong chat của mọi người.
5. **Quà cho mọi người** (admin, Phase 2): thư kèm vàng / kinh nghiệm và **nhiều món** (bấm **+ Thêm** cho từng đồ thường
   hoặc trang bị riêng: 0–4 dòng cộng thêm, +0…+11, ×1…10; **✕** để bỏ khỏi giỏ).
   - **Người nhận:** bỏ trống là mọi nhân vật (không tính bot); lọc được theo cấp từ / đến, số lần chuyển sinh tối thiểu,
     chỉ người đang online.
   - **Xem trước và gửi:** hiện số người khớp bộ lọc và nội dung thư, xác nhận rồi mới gửi.
   - **Lịch sử gửi:** 20 đợt gần nhất (lúc gửi, người gửi, tiêu đề, quà, bộ lọc, kết quả).
   - Túi đồ hiếm không đủ chỗ thì người nhận chưa mở được thư.
6. **Sự kiện** (admin): gọi trùm thế giới Cổ Long, bắt đầu Golden Invasion, **mở ngay Quảng Trường Quỷ / Lâu Đài Máu** (một đợt ngoài lịch, cho vào trong `entry_minutes` = 10 phút, báo cả server; người chơi vẫn cần vé và đủ cấp, ai đã vào đợt thường vẫn vào được; giữ trong bộ nhớ — khởi động lại server là mất). **⚔ Mở Hỗn Chiến Thành** mở một lượt ngay (cho vào 5 phút rồi hỗn chiến 10 phút). **🐲 Rồng Đỏ / 🧙 Phù Thủy Trắng xâm lăng** bắt đầu ngay ở bản đồ ngẫu nhiên. Lệnh: `world_boss`, `invasion`, `open_ds`, `open_bc`, `open_cc`, `raid_red_dragon`, `raid_white_wizard`, `lake_summon` (**🐉 Gọi Long Vương nổi**: Ngài nổi ngay ở một ô nước ngẫu nhiên của Hồ Long Vương trong 3 phút, như lần nổi theo giờ), `lake_school` (**✨ Gọi Đàn Cá Vàng**: hiện ngay 2 phút), `open_cs` (**🏰 Mở Công Thành Chiến**: bắt đầu ngay, mọi bang vào được, kết quả Chủ Thành tính thật).
7. **Kiểm tra vàng** (admin): xem mục 4.
8. **Nhật ký quản trị** (admin): 50 thao tác mới nhất.

Quà qua thư và chỉnh nhân vật khác nhau: quà nằm trong hộp thư, người chơi phải bấm nhận; chỉnh nhân vật đổi
ngay (người đang online thấy liền), kể cả khi người đó offline.

## 3. Chỉnh nhân vật

Mỗi dòng trong khối là một lệnh (`op` của kênh `"admin"`, xem `HacLong.Admin`):

| Dòng | `op` | Tham số | Ghi chú |
|---|---|---|---|
| Kinh nghiệm | `give_xp` | `xp` 1..1 000 000 000 | lên cấp như đánh quái (mỗi cấp +5 điểm tiềm năng, Thuật Sĩ Kiếm +7), dừng ở cấp tối đa 50 |
| Đặt cấp | `set_level` | `level` 1..50 | xp về 0; điểm tiềm năng ± điểm mỗi cấp × số cấp đổi (không dưới 0, **cộng vào** điểm đang có); hồi đầy máu |
| Vàng | `add_gold` | `amount` (âm để trừ) | không xuống dưới 0 |
| Điểm tiềm năng | `add_points` | `n` (âm để trừ) | |
| Chỉ số | `add_stats` | `str`, `agi`, `vit`, `ene` (âm để trừ) | cộng thẳng vào chỉ số, không dưới 1 |
| Đặt lại chỉ số | `reset_stats` | | chỉ số về **gốc của lớp**; điểm tiềm năng **đặt** đúng như người chơi thật ở cấp / số lần chuyển sinh hiện tại, chưa cộng: (cấp − 1) × điểm mỗi cấp + số lần chuyển sinh × 25 (`rules.json` `rebirth_points`). Bỏ hết điểm đã cộng / `add_points` / `add_stats` trước đó. Nút **Đặt lại chỉ số** (cạnh Hồi đầy máu, có hỏi xác nhận) |
| Đồ thường (xếp chồng) | `give_item` | `id`, `count` 1..9999, `up` 0..11, `wopt` (cánh cấp 2 / 3, Phase 15e: `hp` / `mp` / `ignore_def`) | **mọi** món trong `priv/game_data/items.json`, cả đồ không bán / chỉ rơi từ trùm (`relic`, `dragonshield`), ngọc (`jewel_bless`, `jewel_soul`, `jewel_chaos`), cánh (`wing_<lớp>_1`, `wing_<lớp>_2`, `wing_<lớp>_3`). Trang bị (vũ khí, giáp, khiên, trang sức, cánh) luôn thành **món riêng** 0 dòng trong túi trang bị, mỗi món một chỗ (cần chỗ trống). Tab Quản trị: mục **Đồ thường** chỉ liệt kê bình, ngọc, nguyên liệu, vé…; trang bị tặng ở mục **Trang bị** |
| Trang bị | `give_gear` | `anc` (tuỳ chọn, Phase 15g: `true` = đồ Bộ Thần, chỉ món bộ giáp), `luck` / `skill` (tuỳ chọn, Phase 15d: `true` để có dòng May mắn / Kỹ năng; Kỹ năng chỉ vũ khí), `exc` (tuỳ chọn, Phase 15c: dòng Excellent, B-16 đủ 6 dòng: vũ khí / dây chuyền `atk_pct crit heal_kill mp_kill atk_lvl ar_pct`, đồ khác `hp_pct dmg_red gold_pct mp_pct reflect def_rate`, cánh không có Excellent; trên trang Quản trị là các ô tick, chỉ hiện nhóm hợp món đang chọn — Kỹ năng chỉ hiện với vũ khí, Đồ Thần chỉ với món thuộc bộ), `wopt` (tuỳ chọn, chỉ cánh bậc 2–3: `hp` / `mp` / `ignore_def`), `base` (mọi loại kể cả cánh; id đồ Item.txt `item_<nhóm>_<số>`, xem `docs/ITEMS_PICK.md`), `opt` 0..4 (dòng cộng thêm, mỗi dòng +4; B-15 bỏ `rarity` / `bonus`), `up` | tạo một món riêng kiểu MU. Túi trang bị đầy (40, `rules.json` `loot.gear_bag`) thì báo lỗi |
| Thú cưng | `give_pet` | `id` (thú trong `priv/game_data/pets.json`, kể cả thú hiếm `long_vuong`), `level` 1..20 | tặng thú, đặt cấp thú (cấp 5 / 15 / 20 mở kỹ năng), dắt theo luôn; đã có thì chỉ đặt lại cấp. Tab Quản trị: mục **Thú cưng** (🐉 Long Vương ở đầu danh sách). Không ghi Bia Long Vương |
| Kỷ lục tháp | `set_tower` | `floor` 0..1000 | đặt kỷ lục Tháp Thử Thách (Phase 3: mở kỹ năng tháp ở tầng 10, 20, … 100) |
| Chuyển sinh | `set_rebirths` | `n` 0..10 | đặt số lần chuyển sinh (Phase 6: mở vùng đất chuyển sinh), không đổi cấp / điểm |
| Hủy trang bị trong túi | `clear_bag` | | xóa **mọi** trang bị trong túi trang bị (cả món khóa, kèm cấp ép); đồ đang mặc và đồ cất Tủ Đồ giữ nguyên; bình, ngọc, nguyên liệu không đụng. Nút **Hủy trang bị trong túi** (đỏ, hỏi xác nhận). Không hoàn tác |
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

Đăng nhập tài khoản admin (lớp nào cũng được), mở console trình duyệt (F12 → Console), sửa dòng `NAME` rồi dán cả
khối. `NAME` là **tên nhân vật hoặc tên đăng nhập** của người cần dựng (để trống = chính mình). Lớp, bộ đồ và tỉ lệ
chia điểm lấy theo **nhân vật được dựng**, không theo admin; người đó đang online hay không đều được (đang online thì
thấy ngay). Dòng đầu console ghi "Dựng cho: …" để kiểm đúng người trước khi xem kết quả.

```js
const NAME = '';   // tên nhân vật / tên đăng nhập cần dựng; để trống = chính mình
const who = (await Net.admin('lookup', { name: NAME || window.__hl.player().name })).user;
const uid = who.id, cls = who.character.cls;   // dk / dw / elf / mg
console.log(`Dựng cho: ${who.character.name} (${cls}), tài khoản ${who.username}`);
const A = async (op, p = {}) => { try { const r = await Net.admin(op, { uid, ...p }); console.log(op, r.msg); return r; } catch (e) { console.warn(op, e.msg); } };

// chuyển sinh 10 lần: mở đủ 10 vùng đất chuyển sinh (Phase 6); lệnh này chỉ đặt số lần, không về cấp 1
await A('set_rebirths', { n: 10 });
// cấp tối đa (50)
await A('set_level', { level: 50 });
// kỷ lục Tháp Thử Thách 100: mở đủ 10 kỹ năng tháp (Phase 3); chọn bộ kỹ năng ở Menu → Kỹ năng → ⚙
await A('set_tower', { floor: 100 });
// đặt lại chỉ số (chạy SAU set_rebirths / set_level): chỉ số gốc của lớp, điểm tiềm năng đúng như người chơi thật
// cấp 50 chuyển sinh 10 lần: 49 × 5 + 10 × 25 = 495 (Đấu Sĩ 49 × 7 + 250 = 593). Điểm đã cày / cộng trước đó bỏ hết.
const pts = Number((await A('reset_stats')).msg.match(/(\d+) điểm/)[1]);

// vàng
await A('add_gold', { amount: 100000000 });

// chia hết điểm tiềm năng theo tỉ lệ gợi ý của lớp (lệnh quản trị, chạy được cho cả người khác); điểm lẻ vào chỉ số đầu
const SHARE = {
  dk:  [['str', 0.45], ['agi', 0.2], ['vit', 0.25], ['ene', 0.1]],
  dw:  [['ene', 0.5], ['agi', 0.2], ['vit', 0.2], ['str', 0.1]],
  elf: [['agi', 0.45], ['str', 0.2], ['vit', 0.25], ['ene', 0.1]],
  mg:  [['str', 0.4], ['ene', 0.25], ['agi', 0.2], ['vit', 0.15]],
}[cls];
const add = Object.fromEntries(SHARE.map(([k, r]) => [k, Math.floor(pts * r)]));
add[SHARE[0][0]] += pts - Object.values(add).reduce((a, b) => a + b, 0);
await A('add_stats', add);
await A('add_points', { n: -pts });

// đồ tốt nhất từng lớp (cấp 47–48): vũ khí, khiên, bộ giáp 5 món (Đấu Sĩ không mũ), 2 nhẫn, dây chuyền, cánh cấp 3
const SET = {
  dk:  { weapon: 'item_0_19', shield: 'item_6_18', set: ['item_7_33', 'item_8_33', 'item_9_33', 'item_10_33', 'item_11_33'] }, // Kiếm Tổng Lãnh Thiên Thần, bộ Ánh Dương
  dw:  { weapon: 'item_5_11', shield: 'item_6_18', set: ['item_7_30', 'item_8_30', 'item_9_30', 'item_10_30', 'item_11_30'] }, // Gậy Kundun, bộ Sương Độc
  elf: { weapon: 'item_4_24', set: ['item_7_31', 'item_8_31', 'item_9_31', 'item_10_31', 'item_11_31'] },                       // Cung Air Lyn, bộ Tia Tiên
  mg:  { weapon: 'item_0_28', set: ['item_8_29', 'item_9_29', 'item_10_29', 'item_11_29'] },                                    // Kiếm Đế Vương, bộ Long Kỵ Sĩ
}[cls];
const EXC_W = ['atk_pct', 'crit', 'heal_kill', 'mp_kill', 'atk_lvl', 'ar_pct'];   // vũ khí / dây chuyền
const EXC_A = ['hp_pct', 'dmg_red', 'gold_pct', 'mp_pct', 'reflect', 'def_rate']; // giáp / khiên / nhẫn
// "+N" là cấp ép (tối đa +11); opt 4 = 4 dòng cộng thêm (+16 tấn công / phòng thủ), luck = May mắn
await A('give_gear', { base: SET.weapon, opt: 4, luck: true, skill: true, up: 11, exc: EXC_W });
if (SET.shield) await A('give_gear', { base: SET.shield, opt: 4, luck: true, up: 11, exc: EXC_A });
for (const base of SET.set) await A('give_gear', { base, opt: 4, luck: true, up: 11, exc: EXC_A });
// Đồ Thần thay cho Excellent (chọn một trong hai cho bộ giáp): await A('give_gear', { base, opt: 4, luck: true, up: 11, anc: true });
await A('give_gear', { base: 'item_13_24', opt: 4, luck: true, up: 11, exc: EXC_A });   // Nhẫn Phép × 2
await A('give_gear', { base: 'item_13_24', opt: 4, luck: true, up: 11, exc: EXC_A });
await A('give_gear', { base: 'item_13_27', opt: 4, luck: true, up: 11, exc: EXC_W });   // Dây Chuyền Nước
// cánh cấp 3 đúng lớp (cấp mặc 45): 4 dòng cộng thêm (phòng thủ), May mắn, dòng phụ cánh hp / mp / ignore_def
await A('give_gear', { base: `wing_${cls}_3`, opt: 4, luck: true, up: 11, wopt: 'ignore_def' });

// ngọc để tự ép / ghép thêm
await A('give_item', { id: 'jewel_bless', count: 50 });
await A('give_item', { id: 'jewel_soul', count: 50 });
await A('give_item', { id: 'jewel_chaos', count: 50 });
await A('give_item', { id: 'jewel_life', count: 50 });

// bình máu / mana, nguyên liệu nâng cấp / nấu ăn, vé sự kiện
await A('give_item', { id: 'potion_l', count: 500 });
await A('give_item', { id: 'mana_l', count: 500 });
await A('give_item', { id: 'ore_rare', count: 100 });
await A('give_item', { id: 'dragon_scale', count: 20 });
await A('give_item', { id: 'mam_co', count: 20 });
for (const id of ['ds_ticket', 'bc_ticket', 'cc_ticket', 'lost_map']) await A('give_item', { id, count: 10 });

// thú hiếm Long Vương cấp tối đa (đủ 3 kỹ năng), dắt theo luôn; Mồi Rồng để câu ở Hồ Long Vương
await A('give_pet', { id: 'long_vuong', level: 20 });
await A('give_item', { id: 'dragon_bait', count: 100 });

await A('heal');
```

Cần 13 chỗ trong túi trang bị (tối đa 40): dọn túi trước. Đồ tặng nằm trong túi, chưa mặc.

Sau đó mở tab **Túi đồ** (phím `I`), kéo vũ khí / giáp / khiên / cánh vào ô trang bị (hoặc bấm món → **Trang bị**).
Nên bấm **🔒 Khóa** cho từng món để không lỡ bán / rao chợ / bỏ vào máy ghép. Kiểm lại: tab Quản trị →
tra chính mình → **Nhật ký quản trị** có đủ các dòng; **Kiểm tra vàng** vẫn "Không có lỗi".

Chạy lại công thức nhiều lần vẫn ra cùng chỉ số / điểm (nhờ `reset_stats`); riêng **vàng** (`add_gold`) và **đồ / ngọc**
(`give_gear`, `give_item`) vẫn cộng thêm vào cái đang có.

Thú Long Vương tặng bằng `give_pet` **không** ghi lên Bia Long Vương và không báo cả server (bia chỉ ghi người tự câu được);
danh hiệu Long Vương Chủ thì có (thành tựu tính theo thú đang có).

Không có trong công thức (Hắc Long chưa có lệnh quản trị cho): kỹ năng (kỹ năng thường mở theo cấp, cấp 50 là đủ;
kỹ năng tháp mở bằng `set_tower`), thành tựu, nhiệm vụ.

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
| "Túi trang bị đã đầy (40 món)." | `give_gear` khi túi đủ 40 món chưa mặc | bảo người chơi bán bớt, hoặc tặng đồ thường |
| Người chơi báo "đồ rơi biến mất" khi túi đồ hiếm đầy | từ Phase 1 đồ rơi lúc túi đầy được **gửi Hộp thư** (mỗi món một thư, cùng transaction với lần lưu nhân vật) | bảo người chơi mở Hộp thư; tra `gear_log` lý do lưu của trận đó |
| Bot đứng yên, không đánh quái | (đã sửa ở Phase 5) mốc nghỉ của bot so với đồng hồ đơn điệu có thể âm | cập nhật bản mới; kiểm `characters.updated_at` của tài khoản `bot_*` có đổi sau vài phút |
| Tự đánh tự tắt | hết bình máu, có người tên đỏ, bị đồ sát, gục / bỏ chạy, rời bản đồ, đóng hết tab | đúng thiết kế (B-31); thông báo lý do hiện ở góc màn hình người chơi |
| `gold_mismatch` sau khi sửa SQL tay | sửa vàng thẳng database không có dòng nhật ký | đừng sửa tay; dùng `add_gold`. Đã lỡ thì thêm một dòng `gold_log` (`reason = 'MANUAL'`, `delta` = phần chênh) |
| Kiểm tra vàng chậm | bảng nhật ký lớn | dọn `--prune 180` |

## 9. Ép đồ, Máy Hỗn Nguyên, khóa đồ (Đợt 3)

Số liệu ở `priv/game_data/upgrade.json` (`UPGRADE`, `JEWELS`), `chaos.json` (`CHAOS`), `items.json` (các món `jewel_*`, `wing_*`), `rules.json` (`RULES.upgrade`: giá, % cộng mỗi cấp); sửa xong phải build lại.

- **Thợ Rèn:** +1 → +5 bằng quặng (chắc chắn). +6 bằng Ngọc Ước Nguyện (100 %); +7 / +8 / +9 bằng Ngọc Tâm Linh
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

- Tự chạy mỗi 2 giờ (0h, 2h… giờ Việt Nam), 15 phút. Tab Quản trị → khung **Sự kiện** → **✨ Golden Invasion** để chạy thử / bù.
- Chỉnh ở `rules.json` → `RULES.invasion`: `every_hours`, `minutes`, `maps` (bản đồ → số quái vàng), `strength_mult`,
  `reward_mult`, `jewel_chance`, `boss`, `boss_jewel_chance`. Build lại sau khi sửa.

### Tiến Lên (Phase 17)

- Mỗi bàn một tiến trình (`HacLong.TienLen.RoomServer`), tối đa `RULES.tienlen.max_rooms` bàn, cược tối đa
  `RULES.tienlen.stake_max`. Vàng trả qua `HacLong.TienLen.Gold`: nhật ký vàng lý do `TIENLEN` (ref
  `room:<mã>:game:<n>:end` / `:chain:<k>`), ném đồ `TIENLEN_THROW`. Mỗi lần trả một khóa ở bảng
  `tienlen_settlements` nên không trả hai lần.
- Ván đã chơi ở bảng `tienlen_games` (người thật trong `player_ids`, `replay` để xem lại).

### Xã hội, PK cược vàng, chiến bang (Phase 5)

- **Đang online:** tab Quản trị → "Đang online" → Xem (tên, lớp, cấp, bản đồ; Tra để mở thông tin). Mod cũng xem được.
- **Đồ sát** (thay PK cược vàng từ 2026-10-10, `RULES.slay`, `DECISIONS.md` P18): không cần đồng ý, luân phiên lượt 10 giây, người thua mất `death_gold_loss` vàng cho người thắng (nhật ký vàng lý do `SLAY`). PK cược cũ (`RULES.pk`): mời cược đã tắt. Mỗi trận một dòng ở bảng `pk_matches`
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
| Tỉ lệ rơi bình máu / đồ, số dòng cộng thêm (`gear_weights`) | `loot` |
| Giá bán lại (40 %) | `shop.sell_ratio` |
| Rương, rèn, tháp, thú cưng, sổ quái, nhà, lễ hội, việc hằng ngày, câu cá | `chests`, `crafting`, `tower`, `pets`, `bestiary`, `home`, `events`, `daily`, `fishing` |
| Bang (giá lập, mốc quỹ, thưởng nhiệm vụ tuần), chợ (phí, số món), đấu trường, tổ đội | `guild`, `market`, `arena`, `party` |
| Từ cấm khi đặt tên nhân vật / bang | `names` |
| Ngọc Sinh Mệnh; sức chứa Tủ Đồ và giá mở rộng; trần vàng / EXP mỗi thư quản trị | `upgrade.life`, `storage`, `mail` |
| PK cược vàng, chiến bang, tổ đội (chia thưởng, hạn mời), giao dịch tự hủy, hộp thư (giữ / hết hạn), xếp hạng (top, cache), phó bang tối đa, hạn đơn xin vào | `pk`, `guild_war`, `party`, `trade`, `mail`, `leaderboard`, `guild.max_officers`, `guild.request_days` |
| Đài Phúc Lành (số trận phúc lành, % cộng thêm) | `blessing` |
| Nguyên tố (vòng khắc, % mạnh / yếu, nguyên tố quái theo cấp) | `elements` |
| Kỹ năng Tháp Thử Thách (số kỹ năng mang vào trận, kháng choáng của trùm); số từng kỹ năng ở `classes.json` → `tower_skills` | `tower_skills` |
| Vùng đất chuyển sinh (cấp vào, hệ số sức mạnh quái, rơi đồ / ngọc thêm); quái từng vùng ở `realms.json` | `realms` |
| Né tối đa (`combat.dodge.max_total`), dòng Excellent theo cấp (`excellent.options.weapon.atk_lvl`) | `combat`, `excellent` |
| Tự đánh: nhịp ra lệnh, % uống bình mặc định / giới hạn, số dòng cộng thêm để giữ đồ khi lọc "chỉ đồ quý" | `auto` |
| Bot: số bot, thời gian nghỉ sau khi gục, ngưỡng mua bình (`potion_min` / `potion_buy` / `mana_min` / `mana_buy`), loại bình (`potion_heal_min`), nghỉ trọ (`inn_gold_mult`) | `bots` |

- **Gõ nhầm id** (món đồ, quái, lớp…) ở bất kỳ file nào trong `priv/game_data/` hay `priv/maps/` thì build **dừng** và in
  danh sách lỗi, vd `shop.json: SHOP có món "daggerr" không có trong ITEMS`. Sửa đúng id rồi build lại.
- Đổi số cân bằng thì chạy `mix hac_long.simulate 20 --seed 1` trước và sau để so (cùng seed → cùng kết quả nếu số không đổi).
- Xem cả hành trình một nhân vật tới chuyển sinh và vùng chuyển sinh: `scripts/balance/journey.sh --cls dk --rebirths 10 --seed 42`
  (báo cáo ở `tmp/journey/`, tùy chọn: `mix help hac_long.journey`).

**Từ cấm** (`names`):

- `banned_words`: khớp **nguyên từ**, không phân biệt hoa thường và dấu (`"quan tri"` chặn "Quản Trị", "QUAN TRI"; số và
  ký hiệu là chỗ ngắt từ nên `"gm"` chặn "GM01" nhưng `"lon"` không chặn "Thiên Long"). Viết không dấu, chữ thường; cụm
  nhiều từ được.
- `banned_parts`: khớp **một phần** tên viết liền (bỏ khoảng trắng, đổi số kiểu `4dm1n` → `admin`). Chỉ để từ dài, rõ
  nghĩa, nếu không sẽ chặn nhầm tên thường.
- Áp dụng khi tạo nhân vật mới, lập bang mới (tên và ký hiệu). Tên đã có không bị đổi.


## Người chơi AI (Phase 16)

- Server chạy sẵn **20 người chơi AI** (tài khoản `bot_01` … `bot_20`, vai trò `bot`): đi lại, đánh quái, lên cấp, nói vài câu
  trong chat. Người chơi không thấy dấu hiệu bot; bot không có trên bảng xếp hạng, không nhận giao dịch, từ chối cược đấu.
- Đổi số bot: biến môi trường `HL_BOTS` khi khởi động (deploy: ghi `HL_BOTS=5` vào `.env` rồi `docker compose up -d`; `HL_BOTS=0` để tắt). Mặc định `RULES.bots.count` = 0 (không có bot).
- Tài khoản bot có trong tab Quản trị như người chơi thường (tra cứu, chỉnh nhân vật, khóa…). Xóa hẳn: tắt bot (`HL_BOTS=0`)
  rồi xóa tài khoản trong database.

## Quảng Trường Quỷ (Phase 18)

- Lịch, vé, thưởng: `RULES.devil_square` (`priv/game_data/rules.json`), giải thích ở `docs/EVENTS_PHASE18.md`.
- Thử ngoài giờ: khởi động với `HL_DS_OPEN=1` (luôn mở; vẫn mỗi người một lần mỗi đợt).
- Tặng vé: `give_item` với `id: "ds_ticket"`.
- Gửi thưởng top 3 một ngày bằng tay (vd. server khởi động lại trước 0h05): trong iex
  `HacLong.DevilSquareBoard.payout("2026-10-10")`. Bảng xếp hạng ngày giữ trong bộ nhớ, khởi động lại thì mất bảng hôm đó.

## Lâu Đài Máu (Phase 18 M2)

- Lịch, vé, thưởng: `RULES.blood_castle`, giải thích ở `docs/EVENTS_PHASE18.md` §M2. `HL_DS_OPEN=1` mở luôn cả Lâu Đài.
- Tặng vé: `give_item` với `id: "bc_ticket"`; tặng lông vũ (bù lỗi): `id: "condor_feather"`.

## 12. Đợt 8 phase 2026-10

Chi tiết từng quyết định ở `docs/DECISIONS.md` B-25 … B-33; bảng công thức ở `docs/FORMULA_AUDIT.md`.

| Phase | Nội dung | Việc của người vận hành |
|---|---|---|
| 1 | Sửa lỗi: tháp quay vòng có tiền tố tên, quái giữ máu sau khi người chơi bỏ chạy, đồ rơi lúc túi đầy gửi Hộp thư, `give_gear` tặng được cánh và dòng phụ cánh | Không |
| 2 | Giao diện: bấm avatar mở hồ sơ, nút Hủy đồ rơi, Thợ Rèn ép đồ trong túi, Đài Phúc Lành thay Đá dịch chuyển, quà cho mọi người nhiều món + lịch sử | Migration `add_blessing` |
| 8 | Rà công thức (B-28): Excellent "tấn công theo cấp" 0,6, né tối đa 60 %, ép nhẫn máu cộng máu, quái không né; PvP dùng đúng chỉ số | Không |
| 3 | 10 kỹ năng Tháp Thử Thách mỗi lớp, nguyên tố, bộ 4 kỹ năng (Menu → Kỹ năng → ⚙) | Migration `add_skill_set`; quản trị `set_tower` |
| 6 | 10 vùng đất chuyển sinh (cấp quái 52–150), tháp tầng 61–160 | Quản trị `set_rebirths`; sinh lại dữ liệu: `python3 scripts/gen_realms.py` rồi `node e2e/tint_sprites.mjs` |
| 4 | Tự đánh khi online (thanh 🤖 dưới bản đồ) | Không; chỉnh số ở `RULES.auto` |
| 5 | Bản đồ động; bot mua bình / nghỉ trọ; sửa lỗi bot đứng yên | Chỉnh số ở `RULES.bots` |
| 7 | Bộ hình đồ Pixel CC0 (Menu → Cài đặt → Hình đồ) | Không; xem mục 12.3 |

### 12.1 Tự đánh (Phase 4, B-31)

- Chạy **trong Session của người chơi** khi còn ít nhất một tab mở; đóng hết tab là tắt. Không có tự đánh offline, không thêm cột
  database (cài đặt nằm trong bộ nhớ `player.auto`).
- Mỗi nhịp server tự chọn lệnh và chạy qua đúng đường lệnh client (cùng luật, giới hạn tốc độ, nhật ký vàng / đồ). Lý do lưu
  trong `gold_log` / `gear_log` vẫn là tên lệnh (`ATTACK`, `SKILL`, `DISCARD`…).
- Không bật được ở Làng, Nhà, bản đồ sự kiện riêng, Tháp, Hỗn Chiến Thành, Công Thành Chiến.
- Lọc "chỉ đồ quý" hủy đồ thường vừa nhặt; người chơi khiếu nại mất đồ thì tra `gear_log` lý do `DISCARD` quanh giờ đó.

### 12.2 Người chơi AI (Phase 5, B-32)

- Còn ít bình thì về Làng mua ở Bà Lang; máu thấp, hết bình mà đủ vàng thì nghỉ ở Quán Trọ, không thì về Nhà uống giếng.
- Kiểm tra bot có chạy: `SELECT c.name, c.map_id, c.gold, c.updated_at FROM characters c JOIN users u ON u.id = c.user_id
  WHERE u.role = 'bot' ORDER BY c.updated_at DESC;` — `updated_at` phải đổi sau vài phút.

### 12.3 Bộ hình đồ Pixel (Phase 7, B-33)

- Người chơi chọn ở Menu → Cài đặt → **Hình đồ**: MU (chỉ hiện khi máy chủ có hình MU, mục 10.1) / Pixel / Biểu tượng.
  Mặc định MU nếu có, không thì Pixel.
- Hình Pixel (CC0, Dungeon Crawl Stone Soup) **có sẵn trong git**: `priv/static/assets/pixel/` và bảng tra
  `priv/static/assets/pixel_icons.json`. Thêm đồ mới thì chạy lại (xem README → "Chỉnh sửa game"):
  `python3 scripts/pixel_icons.py <crawl/tiles>/releases/Nov-2015` (hình quần lấy sẵn từ `assets_src/pixel_extra/leggings/`). Món chưa có hình Pixel
  (đồ ăn) dùng hình cũ; cánh dùng đôi cánh Draconian của Dungeon Crawl (`assets_src/pixel_extra/wings/`).
- Hình MU vẫn **không bao giờ** vào git / Docker (mục 10.1).
