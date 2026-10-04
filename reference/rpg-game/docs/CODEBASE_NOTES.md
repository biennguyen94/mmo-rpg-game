# Ghi chú kỹ thuật Hắc Long (cho người / agent sửa code)

> Bản đồ nhanh của code: dữ liệu nằm đâu, luồng lệnh, chỗ vàng / đồ thay đổi, quản trị, xếp hạng, cách vẽ, test.
> Đọc file này trước, rồi mới mở code. Số dòng theo bản hiện tại (gốc commit `5c514b7`).
> **Sửa code ở chỗ nào được nhắc trong file này thì cập nhật luôn file này.**
>
> - Tổng quan cho người chơi / cách chạy: `README.md`.
> - Kế hoạch tích hợp tính năng từ MU Web: `docs/INTEGRATION_PLAN.md`; các phase tiếp theo: `docs/PHASE_PLAN.md`.

## Mục lục

1. [Luồng lệnh và lưu nhân vật](#1-luồng-lệnh-và-lưu-nhân-vật)
2. [Vàng: mọi chỗ thay đổi](#2-vàng-mọi-chỗ-thay-đổi)
3. [Đồ: lưu trữ, đồ ngẫu nhiên, nâng cấp, rơi đồ](#3-đồ-lưu-trữ-đồ-ngẫu-nhiên-nâng-cấp-rơi-đồ)
4. [Quản trị](#4-quản-trị)
5. [Bảng xếp hạng, lớp nhân vật](#5-bảng-xếp-hạng-lớp-nhân-vật)
6. [Vẽ nhân vật và giao diện trang bị](#6-vẽ-nhân-vật-và-giao-diện-trang-bị)
7. [Chiến đấu](#7-chiến-đấu)
8. [Dữ liệu game](#8-dữ-liệu-game)
9. [Test, CI, simulator](#9-test-ci-simulator) (9b Đợt 1, 9c Đợt 2, 9d Đợt 3, 9e lớp MU, 9f Phase 1, 9g Phase 2)
10. [Bẫy cần biết](#10-bẫy-cần-biết)

---

## 1. Luồng lệnh và lưu nhân vật

```
Client (priv/static/js) ──"act"──▶ HacLongWeb.GameChannel ──▶ HacLong.Game.Session (1 GenServer / tài khoản)
                                                               │ run_command_ (session.ex:397-421)
                                                               │   Commands.run → hàm thuần Engine / module tính năng
                                                               │   player đổi → save(s, player) (session.ex:723-726)
                                                               ▼
                                                   HacLong.Game.Characters.save!/4 (transaction: lưu + gold_log + gear_log)
```

- **Session tuần tự hóa** mọi lệnh của một tài khoản, kể cả nhiều tab (moduledoc `session.ex:1-17`).
- **Từ Đợt 2:** `save!(uid, player, reason \\ nil, ref \\ nil)` chạy trong transaction: `SELECT gold, gear … FOR UPDATE`,
  upsert, rồi ghi `gold_log` (vàng đổi) và `gear_log` (đồ hiếm vào / ra). `reason` bỏ trống thì lấy từ
  `Characters.put_reason/2` mà `Session.handle_call` đặt cho lệnh đang chạy (xem mục 9c). `delete!/1` cũng ghi (`DELETE`).
- **Lưu cả dòng:** `Repo.insert!(…, on_conflict: {:replace, Character.fields() ++ [:updated_at]}, conflict_target: :user_id)`.
  - Không có cột version, không có khóa lạc quan.
  - `@save_version 1` (`characters.ex:13`) chỉ là trường trong map, không phải khóa.
- **Lệnh thường không chạy trong transaction:** hàm thuần trên map trong RAM, sau đó lưu cả dòng.
- **Di chuyển** gom lại rồi ghi định kỳ: `@flush_ms 5_000` (`session.ex:36`), `mark_dirty` (`session.ex:733`).
- **Giới hạn tốc độ lệnh:** `@act_ms 80`, `@act_burst 10` (`session.ex:40-41`).
- **Schema nhân vật:** `HacLong.Game.Character` (`character.ex:5` `@fields`, `7-54`). `gold` là `:integer` (dòng 13).
- **Một tài khoản = một nhân vật** (`conflict_target: :user_id`).

## 2. Vàng: mọi chỗ thay đổi

**Từ Đợt 2 có `gold_log` / `gear_log` / `admin_log`** (mục 9c). Mọi chỗ dưới đây đổi vàng đều đi qua
`Characters.save!`, nên được ghi nhật ký mà không phải sửa từng chỗ. **Thêm chỗ ghi nhân vật mới thì phải đi qua
`Characters.save!`** (hoặc Session), nếu không đối soát sẽ báo `gold_mismatch`.

Các bảng hiện có: `users`, `user_tokens`, `characters`, `chat_reports`, `user_blocks`, `mails`, `guilds`,
`guild_members`, `guild_requests`, `pvp`, `market_listings`, `home_likes`, `friends`, `gold_log`, `gear_log`, `admin_log`.

### (a) Hàm thuần, đi qua Session rồi `Characters.save!` (không transaction)

| Lý do | Vị trí | Số |
|---|---|---|
| Nhân vật mới | `engine.ex:55` | 30 vàng |
| Hạ quái | `Engine.win` `engine.ex:756, 765` | `(3+l*2.2)*mult*rand(0.8,1.2)*(boss?6:1)` (`engine.ex:181`), × `Pets.bonus(:gold) + Crafting.food_bonus(:gold)` |
| Mốc sổ tay quái | `engine.ex:807` | `bestiary.ex:43, 48` |
| Kỹ năng thú "móc túi" | `engine.ex:502-503` | |
| Chết | `Engine.lose` `engine.ex:896-897` | mất `floor(gold*0.1)` |
| Nâng cấp đồ | `Engine.upgrade` `engine.ex:1002, 1019` | |
| Mua ở cửa hàng | `Engine.buy` `engine.ex:1058, 1063` | |
| Bán đồ ngẫu nhiên | `Engine.sell("#"<>uid)` `engine.ex:1082` | `it.sell` |
| Bán đồ thường | `Engine.sell(id)` `engine.ex:1092`, `sell_price` `1067` | `floor(price*0.4)` (giá 0 thì tính 200) |
| Nghỉ trọ | `Engine.rest` `engine.ex:1155, 1167-1171` | `level*4-4` |
| Túi đồ ngẫu nhiên đầy thì tự bán | `Gear.add` `gear.ex:156-158` | |
| Rèn đồ ngẫu nhiên | `Crafting.smith` `crafting.ex:30, 128-148` | `level*15` |
| Mua rương | `Chests.buy` `chests.ex:49, 57` | giá `chests.ex:24-35` |
| Rương nhà mỗi ngày | `Chests.open_daily` `chests.ex:73, 88` | `20+level*8` |
| Việc hằng ngày | `Daily.claim` `daily.ex:170` | `daily.ex:85-100` |
| Nhiệm vụ Trưởng Làng | `Quests.turn_in` `quests.ex:87` | |
| Tháp Vô Tận | `Tower.climb` `tower.ex:234` | `tower.ex:220` |
| Đổi quà lễ hội | `Events.give(…,"gold")` `events.ex:126-128` | `60+level*12` |
| Hướng dẫn người mới | `tutorial.ex:19, 56` | 50 |
| Mua thú cưng | `Pets.buy` `pets.ex:186-190` | |
| Thuần phục thú | `Pets.tame` `pets.ex:129-133` | |
| Mua nội thất | `Home.buy` `home.ex:44-48` | |

### (b) Ở Session (lưu cả dòng, không transaction)

| Lý do | Vị trí |
|---|---|
| Trùm thế giới (online) | `session.ex:278`; thưởng `300+5000*share (+500 người kết liễu)` (`world_boss.ex:209`) |
| Trùm thế giới (offline) | gửi thư (`session.ex:265-271`) |
| Đấu trường thắng | `30+5*max(0,delta)` (`arena.ex:127`), `battle_over` `session.ex:644` |
| Đấu trường thua | trả lại vàng / máu / số lần chết từ ảnh chụp trước trận (`session.ex:645`, chụp ở `478`) |
| Đánh chung tổ đội | vàng quái × `1.2/n` (`session.ex:556-561`) |
| Giao dịch, bên lấy | `TradeOffer.take` `trade_offer.ex:115` qua `handle({:trade_take})` `session.ex:212-222` |
| Giao dịch, bên trao | `TradeOffer.give` `trade_offer.ex:125` qua `session.ex:224-229` |

**Giao dịch** (`HacLong.Trade`, GenServer giữ trong RAM): `execute/1` (`trade.ex:182-200`) chạy 2 pha qua Session từng người:
1. lấy của A, rồi lấy của B (B lỗi thì trả A bằng `trade_give`);
2. trao chéo.

**Không có transaction chung.** Trần vàng mỗi lần giao dịch: `@max_gold 10_000_000` (`trade_offer.ex:13`).

### (c) Trong `Repo.transaction` (Session truyền callback `save = &Characters.save!(uid, &1)`)

| Lý do | Vị trí | Ghi chú |
|---|---|---|
| Nhận thư | `Mailbox.claim` `mailbox.ex:131-156` (vàng ở `:161`); gọi từ `session.ex:326-337` | `update_all … claimed_at IS NULL` để chỉ nhận một lần |
| Lập bang | `Guilds.create` `guilds.ex:220-262` (transaction ở `230`, vàng ở `247`) | `@create_cost 5000` (`guilds.ex:23`) |
| Góp quỹ bang | `Guilds.donate` `guilds.ex:276-312` (vàng ở `295`) | `@min_donate 100` (`guilds.ex:26`) |
| Chợ: đăng bán | `Market.commit/4` `market.ex:172-179` | ⚠ **bỏ qua kết quả transaction**, luôn trả `{:ok, …}` |
| Chợ: mua | `market.ex:183-231` (khóa `FOR UPDATE`, `sold_at IS NULL`; trừ vàng ở `212`) | tiền trả người bán **qua thư** `price − fee` (`215-223`), cùng transaction |
| Chợ: hủy | `market.ex:237-261` | |
| Nhiệm vụ bang tuần | `GuildQuests.complete` `guild_quests.ex:146-178` | quỹ `+3000`; mỗi thành viên nhận thư `800` vàng + xp (`guild_quests.ex:27-32, 155-160`) |
| Quà quản trị | thư (mục 4) | |

- Hằng số chợ: `@fee_pct 5`, `@max_active 10`, `@max_price 10_000_000` (`market.ex:23-25`).
- Lệnh chợ đi qua `session.ex:362-393`: phải đứng gần NPC chợ và không đang đánh.
- Chuyển sinh **giữ nguyên vàng** (`engine.ex:1183-1209`).

## 3. Đồ: lưu trữ, đồ ngẫu nhiên, nâng cấp, rơi đồ

### Lưu trữ (cột của `characters`)

| Cột | Kiểu | Nội dung |
|---|---|---|
| `inv` | map | `item_id → số lượng` (chỉ đồ thường) |
| `equip` | map | **đúng 3 ô** `weapon`, `armor`, `shield` (`characters.ex:67`); giá trị là id đồ thường hoặc `uid` đồ ngẫu nhiên |
| `gear` | mảng map | các món đồ ngẫu nhiên (kể cả món đang mặc) |
| `upgrades` | map | `id → cấp nâng` (id đồ thường = **theo loại**, hoặc `uid` đồ ngẫu nhiên) |

- Đồ khởi đầu: `equip: %{weapon: "club", armor: "vest", shield: nil}`, `inv: %{"potion_s" => 3}` (`engine.ex:58-59`).
- Chỉ nhận 3 ô khi mặc (`engine.ex:1109`). **Chỉ khiên tháo ra được** (`engine.ex:1128-1134`).
- Id đồ ngẫu nhiên: `"#" <> Base32(5 byte ngẫu nhiên)` (`gear.ex:150`); `Gear.instance?` kiểm dấu `#` (`gear.ex:26`).

### Đồ ngẫu nhiên (`HacLong.Game.Gear`, `gear.ex`)

- Dạng: `%{uid, base, rarity, bonus}`.
  - `base`: id đồ thường làm nền.
  - `rarity`: 1 Tốt / 2 Hiếm / 3 Sử Thi (`gear.ex:20`), cũng là số dòng chỉ số cộng.
  - `bonus`: `%{str|vit|agi|def => điểm}`, mỗi dòng `1+floor(rand*(1+level/6))` (`gear.ex:133`).
- Tên có hậu tố theo chỉ số cao nhất (`gear.ex:21, 54-67`).
- Giá: `base*0.4*(1+0.25*rarity) + 5*sum(bonus)` (`gear.ex:70-73`).
- Tỉ lệ độ hiếm `[{3,5},{2,25},{1,70}]`.
- Ô đồ: vũ khí 45 % / giáp 35 % / khiên 20 %.
- Nền: 2 món cửa hàng cấp cao nhất ≤ cấp quái (`gear.ex:103-137`).
- Tỉ lệ rơi: quái thường 0,04; ban đêm 0,25; trùm 0,35; tinh anh 0,5; trùm thế giới / PvP 0 (`gear.ex:88-96`).
- Tối đa `@max_bag 20` món chưa mặc (`gear.ex:18`).
- Chỉ số cộng từ đồ đang mặc: `bonus_stats` (`gear.ex:76-83`).
- DB lưu khóa chuỗi, đọc lên qua `Gear.load` (`gear.ex:167-176`).

### Nâng cấp ở Thợ Rèn (`engine.ex:952-1027`)

- Tối đa `@max_upgrade 5` (`engine.ex:20`). Chỉ nâng đồ **đang mặc** (`upgrade(p, slot)`).
- Lệnh `"upgrade"` cần đứng ở NPC `shop` (Thợ Rèn) (`commands.ex:130-131`).
- **Luôn thành công.**
- Chỉ số cộng: `level * max(1, round((atk||def)*0.08))` (`engine.ex:962-968`).
- Chi phí (`engine.ex:975-984`), với `n = cấp + 1`:
  - `n` × `ore` (đồ cấp < 17) hoặc `n` × `ore_rare`;
  - +5 cần thêm 1 `dragon_scale`;
  - vàng `round(max(price,100)*0.08*n)`.
- Bán cái cuối của đồ thường thì mất cấp nâng (`engine.ex:1094-1096`).
- Chợ / giao dịch chỉ mang `up` cho **đồ ngẫu nhiên** (`market.ex:155-161, 271-273`; `trade_offer.ex:112-116, 128-133`).

### Rơi đồ khi hạ quái (`Engine.win`, `engine.ex:752-843`)

- Bình máu 12 % (trừ trùm / trùm thế giới / PvP): cấp ≥ 20 `potion_l`, ≥ 9 `potion_m`, còn lại `potion_s` (`774-786`).
- Vật phẩm lễ hội (`726-743`).
- Đồ của trùm khi hạ lần đầu: `BOSS_DROPS` (`865-893`).
- Đồ ngẫu nhiên (`846-863`).
- **Nguyên liệu không rơi từ quái**, chỉ có ở điểm thu thập trên bản đồ (`world.ex:205-210`).

## 4. Quản trị

- **Vai trò:** cột `users.role` `player | mod | admin` (CHECK; migration `20261027000000` thay cột `admin` boolean cũ).
  - `User.admin?/1`, `User.staff?/1` (`accounts/user.ex`).
  - Gán vào socket lúc kết nối (`user_socket.ex`, `assigns.role`), **không đọc lại**: đổi quyền thì người đó phải kết nối lại.
  - Cấp / thu: `mix hac_long.admin USER [--role mod|admin] [--revoke]` → `Moderation.set_role/2` (`set_admin/2` vẫn còn,
    gọi `set_role`). Bản release: `HacLong.Release.admin/2`, `HacLong.Release.role/2`.
- **Kênh:** `handle_in("admin", %{"op" => op}, %{assigns: %{role: mod|admin}})` (`game_channel.ex`); `player` → "Không có quyền.".
  - `@mod_ops ~w(reports lookup resolve mute unmute announce)`: mod chỉ được những lệnh này (và `resolve` không được `ban`)
    → còn lại "Cần quyền quản trị viên.".
  - `@read_ops ~w(reports lookup audit gold_log admin_log)`: không ghi `admin_log`. Lệnh sửa nhân vật (`HacLong.Admin.char_ops/0`)
    tự ghi qua `HacLong.Admin.run/4`. Lệnh còn lại: `Admin.log!` trước, `Admin.set_result` sau.
- **Các `op`** (`admin/3`, `admin_char/3`):

| op | Làm gì |
|---|---|
| `reports` | `Moderation.open_reports` |
| `lookup {name}` | tìm người: id, username, `role`, nhân vật (tên, cấp, vàng, số quái), cấm / khóa, số báo cáo |
| `resolve {id, action: dismiss\|mute\|ban, minutes}` | xử lý báo cáo |
| `mute` / `unmute` / `ban` / `unban` `{uid, minutes, reason}` | `nil` phút = vĩnh viễn (`~U[9999-12-31]`); `ban` thu hồi mọi token |
| `announce {text}` | `Chat.system("📢 …")`, tối đa 200 ký tự |
| `gift {subject, body, gold, xp, items, uid \| all: true}` | `Mailbox.send` / `send_all` |
| `world_boss` | `WorldBoss.spawn_now()` |
| `give_xp`, `set_level`, `add_gold`, `add_points`, `add_stats`, `give_item`, `give_gear`, `heal` `{uid, …}` | `HacLong.Admin.run/4` → `Session.admin/3` (chạy trong Session người đó, lưu với lý do `ADMIN`, `ref = admin:<id>`) → `{msg, user}` |
| `audit {days}` | `HacLong.Audit.run/1` |
| `gold_log {uid}` / `admin_log {uid?}` | `Audit.gold_history/2` / `Admin.recent/2` |

- **`HacLong.Admin`** (`admin.ex`): `build(op, params)` trả hàm thuần `fn player -> {:ok, p, msg} | {:error, msg}`;
  `run/4`, `console/3` (dòng lệnh, `admin_name = "console"`), `log!/5`, `set_result/2`, `recent/2`.
  `give_item` nhận mọi id trong `Data.items` (cả `relic`, `dragonshield`); `give_gear` dùng `Gear.new/3`.
- **`HacLong.Moderation`** (`moderation.ex`): `block`, `unblock`, `blocked`, `report`, `open_reports`, `resolve`, `mute`, `unmute`, `ban`, `unban`, `find_user`, `info`, `set_role`, `set_admin`.
- **Thư** (bảng `mails`: `user_id, subject, body, gold, xp, items map, claimed_at`; migration `20261011000000`):
  - kiểm ở `Mailbox.row` (`mailbox.ex:44-73`): tiêu đề không rỗng; gold / xp nguyên ≥ 0; `items` = `%{id => n>0}` với id hợp lệ;
  - **chỉ chứa đồ thường**, không gửi được đồ ngẫu nhiên; **không có trần vàng**;
  - giữ 50 thư / người (`@keep`).
- **Tab Quản trị** (client): hiện khi `Net.isAdmin` (`r.admin` lúc vào kênh, tức mod hoặc admin); `Net.role` quyết định khối nào hiện
  (`isAdminRole()`). `viewAdmin` trong `ui.js`:
  - danh sách báo cáo; tra người: cấm chat, (admin) khóa / mở khóa, tặng quà;
  - (admin) **Chỉnh nhân vật** `viewCharEdit`: mỗi dòng một `<form class="adm-char" data-op>` → `onCharOp`; nút Hồi máu,
    Nhật ký vàng (`viewGoldLog`), Nhật ký quản trị (`viewAdminLog`);
  - thông báo server; (admin) quà cho tất cả, gọi trùm, **Kiểm tra vàng** (`viewAudit`), Nhật ký quản trị;
  - kết quả xem lưu ở `adm.audit`, `adm.glog`, `adm.alog`; `onAdmin` xử lý `data-adm`.
- Hướng dẫn cho người vận hành: `docs/ADMIN_GUIDE.md`.

## 5. Bảng xếp hạng, lớp nhân vật

**`HacLong.Leaderboard`** (`leaderboard.ex`):
- Các loại `[:level, :kills, :dragon, :tower]` (`16`).
- Truy vấn Ecto thẳng vào `characters`, **top 10, không cache** (`20-58`):

| Loại | Sắp theo |
|---|---|
| `level` | chuyển sinh ↓, cấp ↓, xp ↓ |
| `kills` | số quái ↓ |
| `tower` | `tower_best > 0`, ↓ |
| `dragon` | `victory_at` không null, ↑ (ai hạ Hắc Long trước) |

- `level_rank/1` đếm số người xếp trên (`61-81`).
- Index: `(level, xp)`, `kills`, `victory_at` (migration `20261005000000:10-12`).
- **Kênh** `handle_in("leaderboard")` (`game_channel.ex:135-153`):
  - giới hạn 20 lần / phút;
  - gộp thêm `guild: Guilds.top()`, `guild_boss: GuildQuests.boss_top()`, `arena: Arena.top()`, `me: level_rank`.
- **Client** `viewBoard` (`ui.js:598-625`), nằm trong tab Làng:
  - 7 nút: Cấp cao / Săn nhiều / Tháp / Diệt rồng / Bang / Bang diệt Cổ Long / Đấu trường;
  - tự làm mới tối đa 30 giây một lần (`599`).

**Lớp nhân vật** (`CLASSES`, từ 2026-10-04 là 4 lớp MU; nhân vật cũ đã xóa ở migration `20261028000000`):

| id | Tên | Gốc STR / AGI / VIT / ENE | Điểm / cấp | Kỹ năng (`effect` dùng chung) |
|---|---|---|---|---|
| `dk` | Kiếm Sĩ | 28 / 20 / 25 / 10 | 5 | twisting_slash (cleave), falling_slash (stun_bash), greater_fortitude (war_cry) |
| `dw` | Phù Thủy | 18 / 18 / 15 / 30 | 5 | fire_ball (fire_ball), lightning (stun_bash), soul_barrier (guard) |
| `elf` | Tiên Nữ | 22 / 25 / 20 / 15 | 5 | triple_shot (backstab), heal (holy), greater_damage (shadow_step) |
| `mg` | Đấu Sĩ | 26 / 26 / 26 / 26 | 7 | power_slash (fire_ball), flame_strike (venom), gigantic_storm (judgement) |

- Không còn tăng chỉ số tự động theo cấp (`growth`); chỉ có điểm tiềm năng (`points`).
- `derived` theo lớp: `atk`, `def`, `hp`, `mp` là tổng `hệ_số × (str | agi | vit | ene | level | base)` (`Engine.derived/1`);
  chí mạng / né / hệ số chí mạng theo AGI, như nhau mọi lớp. Đã chỉnh bằng simulator cho bằng sức mạnh 3 lớp cũ.
- Kỹ năng có `mp` (tốn MP) và `effect` (tác dụng trong `Engine.strike_with/6`; mới: `fire_ball` = ×2.0, xuyên 30 % giáp).
  MP hồi 5 % tối đa mỗi lượt của người chơi (`next_turn`), đầy khi lên cấp / nghỉ trọ / uống giếng. Cột `characters.mp`.
- Mỗi lớp có thêm `hair`, `icon`, `desc`, `mu` (tên tiếng Anh). Cột lớp trong `characters` là `cls`.

## 6. Vẽ nhân vật và giao diện trang bị

- **`priv/static/js/doll.js`** (54 dòng): ghép lớp **ảnh PNG 32×32** (tile Dungeon Crawl) trên canvas, từ `assets/doll/<đường dẫn>.png`.
  - Thứ tự: thân `['base/human_m','legs/pants_black','boots/short_brown2']` → giáp → tóc → vũ khí → khiên (`doll.js:9, 15`).
  - Dữ liệu `look` từ server: `Engine.look` (`engine.ex:940-950`) = `{hair, weapon, armor, shield, pet}`.
    Mỗi giá trị là trường `doll` của món đồ (đồ ngẫu nhiên lấy theo `base`).
  - API: `Doll.canvas` (cache theo khóa lớp), `Doll.url` (data URL; lỗi thì dùng `assets/monsters/hero.png`), `Doll.onReady`.
  - Dùng ở `map.js:332, 345, 459`, `ui.js:52` (`heroSprite`), `307`, `1632`.
- **Tab Nhân vật / Túi đồ / Khác (sửa 2026-10-04, theo bố cục MU Web, giữ màu / font Hắc Long):**
  - `viewHero`: bảng nhân vật kiểu MU (tên, lớp · cấp, EXP, 4 chỉ số với nút [+] **gom lệnh** — `allocAdd` / `allocFlush`,
    200 ms sau lần bấm cuối gửi một `alloc {stat, n}` mỗi chỉ số — điểm còn, chỉ số chiến đấu).
  - `viewBag`: lưới trang bị 3×4 `EQUIP_GRID` (10 ô; chỉ `SLOT_OPEN` = vũ khí / giáp / khiên hoạt động, 7 ô 🔒 chờ tính năng),
    lưới túi 8 cột **tự xếp** (`bagItems`: đồ trang bị → bình → món ăn → nguyên liệu; server không lưu vị trí ô),
    bảng chi tiết món đồ `showTip` / `hideTip` (`#itemtip`, nút Trang bị / Dùng / Ăn / Tháo), kéo thả chuột
    (`onDragStart` / `onDrop`: túi → ô trang bị = `equip`, khiên → túi = `unequip`), thanh tóm tắt `.bag-bottom`.
  - `viewMisc` (tab **Khác**): toàn bộ tab **Hành trình** cũ (`viewTown`: hồi máu, hành trình diệt rồng, bang, đấu trường,
    sổ tay quái, trùm thế giới, xếp hạng, thành tích, âm thanh, dữ liệu; màn chiến thắng nếu đã hạ Hắc Long), rồi thú cưng,
    kỹ năng, danh hiệu, thành tựu — chờ anh quyết giữ / bỏ. Tab `town` đã bỏ; xếp hạng / đấu trường tải khi mở tab `misc`.
    Thanh tab còn 5: Bản đồ · Nhân vật · Túi đồ · Nhiệm vụ · Khác (+ Quản trị cho admin).
  - **Phím tắt** (`onKey`, `goTab`, `hotkeyPotion`, `hotkeyEscape`):
    - C Nhân vật, I Túi đồ (bấm lại thì về Bản đồ), M Bản đồ;
    - Q uống bình máu nhỏ nhất (trong trận = nút Uống máu);
    - Enter gõ chat; Esc đóng bảng chi tiết → NPC → hộp thoại / thư / bang / bạn bè → về Bản đồ;
    - WASD / mũi tên vẫn đi trên bản đồ, nhưng **không hiện trên giao diện** (đã bỏ 4 nút mũi tên `.dpad` và dòng gợi ý WASD ở `map.js` `html/2`; điện thoại đi bằng cách chạm ô); không chạy khi đang gõ chữ hoặc giữ Ctrl / Alt / Cmd;
    - nút tab có gợi ý phím (`title`).
  - CSS: cuối `style.css` (`.charsheet`, `.statrow`, `.grid3`, `.slot`, `.bag`, `.cell`, `.itemtip`…).
  - Ảnh trước / sau: `docs/screenshots/ui-*.png`.
- **Ô trang bị ở chỗ khác** (vẫn 3 ô Vũ khí / Giáp / Khiên):
  - `forgeCard` (`1308-1327`), `smithCard` (`1373`);
  - xem đồ người khác (`310`).
- **Dữ liệu game cho client:** `window.GAME_DATA`, server chèn ở `page_controller.ex:12-50`
  (`CLASSES, ZONES, ITEMS, RULES, RECIPES, QUESTS, WORLD, ACHIEVEMENTS, PETS, FURNITURE`); client đọc ở `ui.js:5`.
- **Client không có công thức:** server trả `view` tính sẵn.

## 7. Chiến đấu

**Chỉ số dẫn xuất** `Engine.derived/1` (`engine.ex:90-119`):
- chỉ số = gốc + `Gear.bonus_stats`; `up` = `upgrade_bonus`;
- `pet(key)` = `1 + Pets.bonus(p, key) + Crafting.food_bonus(p, key)`;
- công thức:
  - `maxHp = (40 + vit*12 + level*10) * pet(:hp)`
  - `atk = (str*2.2 + agi*0.9 + weapon.atk + up(weapon) + level) * pet(:atk)`
  - `def = (def*1.6 + armor.def + shield.def + up(armor) + up(shield) + level*0.5) * pet(:def)`
  - (từ Đợt 4 công thức theo lớp ở `CLASSES[lớp].derived`, mục 5); chí mạng, hệ số chí mạng, né tránh theo `agi`;
  - Phase 3 thêm `ar` (attack rate = cấp × 5 + AGI × 1,5), `atkMin` / `atkMax` (công × `damage_spread`), `hitRate`
    (trúng quái cùng cấp).

**Sát thương (Phase 3, `Engine.damage/4`):** đòn gốc `công × rand(damage_spread)` → × hệ số (kỹ năng, chí mạng, sổ quái,
% cánh) → trừ thủ `đòn²/(đòn + thủ)` → sàn mềm `soft_floor` (20 %) × đòn → × `taken` (thủ thế, hấp thụ cánh) → sàn cứng 1,
chỉ làm tròn ở cuối. Số ở `RULES.combat`.

**Trúng / trượt (Phase 3):** đòn thường của người đánh quái trúng với `Engine.hit_chance(ar, cấp_quái)` =
`AR / (AR + cấp × monster_dr)`, chặn 5–95 %; kỹ năng luôn trúng; đấu trường vẫn theo `dodge` của đối thủ. Quái đánh người:
người né theo AGI như cũ (`d.dodge + evade`).

**Phạt EXP (Phase 3):** `Engine.xp_factor/2` (`RULES.xp.penalty`), chỉ quái thường ngoài bản đồ (không trùm, tháp, trùm thế
giới, đấu trường), nhật ký trận ghi "(−x% vì cao hơn quái n cấp)".

**Đòn người chơi** `act_strike` (`engine.ex:419-461`):
- `atk = d.atk*(1+power(:player,"rage"))*(1-power(:player,"weaken"))` (`433-434`);
- hệ số kỹ năng: `strike_with` (`519-590`);
- `mult *= 1 + Bestiary.mastery(p, m.id)` (+5 % ở 25 con, +10 % ở 100 con; `bestiary.ex:13, 25`);
- `dmg = damage(atk, thủ_quái, mult * (crit ? critMult : 1))`: chỗ cắm thêm % sát thương là `mult`;
- thú cưng cắn thêm (`464-484`).

**Đòn quái** `monster_turn` (`engine.ex:592-640`):
- `m_atk *= (1 - weaken)`;
- `dmg = damage(m_atk, d.def, chí_mạng ? 1.5 : 1, (1 - guard) * (1 - wingAbsorb))`:
  chỗ cắm thêm % giảm sát thương nhận là tham số `taken`;
- né = `d.dodge + evade`.

**Các hệ số % đang có:** hiệu ứng `rage / weaken / guard / evade` (lưu ở `battle.effects`), Bestiary, thú cưng / món ăn (hp / atk / def / gold / xp),
`Home.xp_bonus`, `Events.xp_bonus`.

**Các đường combat khác** cũng đi qua `derived` / `Engine.act`: đấu trường dựng đối thủ từ `Engine.derived`
(`arena.ex:74-96`); trùm thế giới và đánh tổ đội qua `Commands.run` → `Engine.act`.

## 8. Dữ liệu game

- `priv/game_data/*.json` (mỗi loại một file, `Data` ghép lại; trùng khóa là lỗi), **nạp lúc biên dịch** (`HacLong.Game.Data`,
  `@external_resource` từng file, `__mix_recompile__?` khi thêm / bớt file): sửa phải biên dịch / khởi động lại.
  `HacLong.Game.DataCheck` kiểm tham chiếu (id đồ trong cửa hàng / công thức / rơi trùm / nhiệm vụ / máy ghép / ép, `effect`
  kỹ năng, `cls` của cánh, `role` + `stock` NPC, quái và cổng trên bản đồ): sai → lỗi biên dịch có tên file + id.
- `RULES` (`rules.json`): mọi số luật chơi (Phase 1). Module đọc lúc biên dịch: `@rules Data.rules().nhóm` rồi dùng
  `@rules.khóa`. Còn trong code: hằng số kỹ thuật (thời gian, giới hạn tần suất, kích thước bản đồ / tháp, độ dài tên / chat,
  số dòng nhật ký) và nội dung có cấu trúc riêng (danh sách thành tựu, các bước hướng dẫn, trùm thế giới) — xem `docs/DECISIONS.md`.
  Truy cập qua các hàm `Data.classes/0`, `item/1`, `rules/0`… cuối `data.ex`.
- Khóa cấp cao:

| Khóa | Kiểu | Số lượng | Ghi chú |
|---|---|---|---|
| `CLASSES` | dict | 4 | `dk`, `dw`, `elf`, `mg` (mục 5) |
| `ZONES` | list | 6 | Rừng Mê, Trại Goblin, Nghĩa Địa Cổ, Núi Khổng Lồ, Đầm Lầy Rồng, Hang Hắc Long; trường `id, name, desc, icon, levels, monsters, boss` |
| `ITEMS` | dict | 50 | xem dưới |
| `BOSS_DROPS` | dict | 2 | `hill_giant → dragonshield`, `golden_dragon → relic` |
| `SHOP` | list | 17 | |
| `RECIPES` | list | 10 | |
| `QUESTS` | list | 18 | |
| `PETS` | list | 6 | |
| `FURNITURE` | list | 17 | |
| `EVENTS` | list | 4 | |
| `UPGRADE`, `JEWELS` | dict | | ép +6 → +11 (mục 9d) |
| `CHAOS` | list | | Máy Hỗn Nguyên (mục 9d) |
| `RULES` | dict | | số luật chơi (mục 9f) |

- **`ITEMS`:**
  - trường: `name, slot, price` (mọi món), `icon, level, doll, sprite, desc, def, atk, food, heal, drop`;
  - theo `slot`: material 17 (có 3 ngọc `jewel_*`), weapon 8, wing 8, armor 6, shield 4, food 4, potion 3.
  - Vũ khí (atk / giá / cấp): `club` 3 / 0 / 1, `dagger` 7 / 60 / 3, `broadsword` 13 / 220 / 7, `mace` 21 / 650 / 12,
    `battleaxe` 31 / 1600 / 17, `greatsword` 44 / 3600 / 22, `waraxe` 60 / 7500 / 27, `relic` 82 / chỉ rơi / 30.
  - Giáp: `vest, leather, chain, scale, lamellar, breastplate` (thủ 2 → 34).
  - Khiên: `round, checked, spiked, dragonshield` (chỉ rơi, cấp 24).
  - Nguyên liệu: `ore` (25), `ore_rare` (125), `dragon_scale` (1000), `herb`, `herb_rare`, `fish_*`, `old_boot`, vật phẩm lễ hội.
- **Số đặt cứng trong module:** từ Phase 1 các số luật chơi đã ở `RULES`. Còn lại là giới hạn kỹ thuật / chống lạm dụng
  (giao dịch `trade_offer.ex` 8 dòng / 10 triệu vàng, bạn bè, hộp thư, chat, quản trị) — xem `DECISIONS.md`.

## 9. Test, CI, simulator

- **Test:** 24 file `*_test.exs` (thêm `batch1_test.exs`, `batch2_test.exs` ở `test/hac_long_web/`).
  - `test/hac_long/`: accounts, guild_quests, leaderboard, world.
  - `test/hac_long/game/`: achievements, bestiary, chests, commands, crafting_events, daily, engine, fishing, gear, home_pets, simulator, tower, trade_offer, tutorial.
  - `test/hac_long_web/`: `channels/game_channel_test.exs` (1 294 dòng), auth_controller, error_json, remote_ip.
  - `test/support/`: `channel_case`, `conn_case`, `data_case`.
- **Alias `mix test`** = `ecto.create --quiet` + `ecto.migrate --quiet` + `test` (`mix.exs:54-61`). Cần PostgreSQL.
- Test JS: `node --test test/js/*.test.mjs` (hàm thuần `priv/static/js/logic.js`). E2E + soak: `e2e/` (mục 9g).
- **CI:** job **`hac-long`** trong `.github/workflows/ci.yml` của repo ngoài (`working-directory: reference/rpg-game`; Postgres 16,
  OTP 25 / Elixir 1.17: format, compile `--warnings-as-errors`, `node --check` các file JS, `mix test`).
  File `reference/rpg-game/.github/workflows/ci.yml` vẫn còn nhưng GitHub **không chạy** (thư mục con của repo `mmo-rpg-game`).
- **Simulator:** `mix hac_long.simulate [N] [--seed S]` (mặc định 5; `--seed` cho kết quả lặp lại được để so trước / sau).
  - Chạy 3 lớp × 5 cách chơi: `[]`, `quests`, `+daily`, `+upgrade`, `+chests` (`lib/mix/tasks/hac_long.simulate.ex:22-28`) → `Simulator.run(cls, opts)`.
  - Đổi cân bằng thì chạy trước / sau để so.

## 9b. Kết nối, bảo mật (Đợt 1, 2026-10-04)

- **Vé WebSocket** (`HacLong.Accounts.WsTicket`, ETS): `POST /api/ws-ticket` (token ở header) → vé ngẫu nhiên sống 30 s,
  dùng một lần; `UserSocket.connect` chỉ nhận `%{"ticket" => …}` (không nhận token nữa). `net.js` **tự quản lý nối lại**
  (tắt nối lại của Phoenix): mất kết nối → lấy vé mới → mở socket → vào lại kênh (`onRejoin`), lùi dần 1 → 15 s.
- **Phiên bản giao diện** (`HacLongWeb.ClientVersion`): băm `priv/static/js/*.js` + `css/*.css` lúc biên dịch; trang chủ chèn
  `window.CLIENT_VERSION` (trang không cache: `no-store`) và gắn `?v=<mã>` vào `js/…`, `css/…` (deploy bản mới thì trình duyệt
  không dùng file cũ trong cache); join `"game"` phải gửi `{v}` đúng, sai → `{reason: "version"}`,
  client tự tải lại (mỗi phiên bản một lần, chặn vòng lặp bằng `sessionStorage`).
- **`rid`** (`Session`): lệnh `cmd` có `rid` (chuỗi ≤ 64) thì nhớ kết quả (64 mã gần nhất); gửi lại cùng mã trả kết quả cũ.
  "Thao tác quá nhanh" không ghi nhớ. Client gắn `rid` cho mọi lệnh trừ `move`; hết giờ chờ thì gửi lại một lần cùng `rid`.
- **Log:** `config :phoenix, :filter_parameters` lọc `password`, `current`, `token`, `ticket` (log HTTP và tham số socket).
- **Vàng:** `characters.gold`, `mails.gold` là `bigint` + CHECK `>= 0` (migration `20261026000000`); vàng âm → `save!` ném
  `Ecto.ConstraintError`.
- Test: `test/hac_long_web/batch1_test.exs`.

## 9c. Nhật ký, giao dịch một transaction, quản trị (Đợt 2, 2026-10-04)

- **Migration `20261027000000`:** bảng `gold_log` (`user_id, delta, balance, reason, ref, inserted_at`), `gear_log`
  (`user_id, uid, base, rarity, action in|out, reason, ref`), `admin_log` (`admin_id, admin_name, op, target_id, params, result`),
  `users.role`; dòng `BASELINE` cho vàng / đồ hiếm sẵn có. Không khóa ngoại (xóa nhân vật vẫn giữ lịch sử).
- **Lý do ghi nhật ký:** `Session.handle_call` gọi `Characters.put_reason(reason, ref)` (process dictionary `:hl_save_reason`)
  trước mỗi tin nhắn: lệnh `cmd` → `act` viết hoa (`ATTACK`, `SELL`, `MARKET_BUY`…; `act` lạ → `CMD`), `ref` = `listing`/`id`/`uid`;
  `world_boss_end` → `WORLD_BOSS`; `shared_end` → `PARTY`; `admin` → `ADMIN`; ghi dồn vị trí / tắt → `MOVE`; giao dịch → `TRADE`.
  Gọi `Characters.save!` với `reason` rõ thì không dùng giá trị này.
- **Đối soát** `HacLong.Audit.run/1`: `gold_mismatch` (vàng ≠ tổng `delta`), `gear_duplicate` (cùng `uid` ở hai nhân vật / chợ),
  `gear_unlogged`; thống kê theo lý do + top người nhận. `prune/1` gộp vàng cũ thành dòng `CARRY`, giữ dòng `gear_log` cuối
  của mỗi `uid`. `mix hac_long.audit [--days N] [--prune N]` (thoát 1 khi có lỗi); release: `HacLong.Release.audit/1`, `prune_logs/1`.
- **Giao dịch trực tiếp** (`Trade.execute/1`): `Session.hold(A)`, `Session.hold(B)` → `TradeOffer.take/give` trên bản giữ →
  `Repo.transaction` lưu cả hai (`TRADE`, cùng `ref`) → `Session.release(uid, ref, player | nil)`.
  - Session đang bị giữ (`s.held = {ref, timer}`): `handle_call` xếp tin nhắn vào `s.queue`, trả lời sau khi nhả (`replay/1`);
    `flush/1` không ghi (để giao dịch ghi); `:timeout` không tự tắt; quá `@hold_ms` (3 s) tự nhả (`{:hold_expired, ref}`).
  - `Session.trade_take/3`, `trade_give/2` đã bỏ.
  - Không deadlock: Session không gọi đồng bộ sang Session khác; `WorldBoss` / `Party` gọi Session từ `Task`.
- **Chỉnh nhân vật:** `Session.admin(uid, fun, ref)` chạy `fun.(player)` trong Session, lưu, đẩy trạng thái, `World.refresh` nếu đổi ngoại hình.
- Test: `test/hac_long_web/batch2_test.exs`.

## 9d. Ép ngọc, Máy Hỗn Nguyên, cánh, khóa đồ (Đợt 3, 2026-10-04)

- **Cấp nâng theo từng món (C10):** `upgrades` chỉ còn khóa theo `uid`. Đồ thường được tách thành bản riêng
  `Gear.plain/1` (độ hiếm 0, `bonus: %{}`) khi: nâng cấp lần đầu (`Engine.ensure_instance/2`), khóa (`Engine.lock/3`),
  admin tặng kèm `up` hoặc tặng cánh, ra cánh từ máy ghép. Dữ liệu cũ (`upgrades[id]` đồ thường) tách lúc nạp
  (`Characters.to_player` → `Engine.split_upgrades/1`: món đang mặc + mọi món cùng loại trong túi, giữ cấp; không tính giới hạn túi).
- **Khóa đồ (C18):** `gear[].locked = true` (lưu trong jsonb, `Gear.load` đọc lại). Chặn ở `Engine.sell/2`, `Market` (`list_gear`),
  `TradeOffer.check/2`, `Chaos.gear_input/3`. Không chặn ép (người chơi tự quyết).
- **Ép +6 → +11 (D1, D2, D3, D9):** `Engine.upgrade/3` (`confirm` cho bước `destroy`), `upgrade_cost/2` trả thêm `rate`, `fail`;
  bảng `UPGRADE` trong `priv/game_data/upgrade.json` (`Data.upgrade/0`, `Data.upgrade_step/1`). `effective_level/1`: từ +10 mỗi cấp
  gấp đôi. Vỡ đồ: `destroy_equipped` (vũ khí → `club`, giáp → `vest`). Kết quả có `upgrade` và `announce` (từ +7).
- **Thông báo toàn server:** lệnh trả `announce` → `Session.run_command_` bỏ khỏi kết quả và gọi `Chat.system/1`.
- **Ngọc (D7):** `jewel_bless`, `jewel_soul`, `jewel_chaos` (slot `material`); rơi ở `Engine.jewel_drop/3` (bảng `JEWELS`),
  `Tower.climb/1` (mỗi 10 tầng, chỉ lần đầu vượt `tower_best`), `Chests.buy/2`, `WorldBoss.reward/4` (top 3).
  `Engine.pick_jewel/0` chọn theo trọng số.
- **Cánh (D6):** ô `equip.wing` (mặc định nil; `@equip_slots` trong `Engine`); món `wing_<lớp>_<1|2>` có `cls`, `tier`, `dmg`,
  `absorb`. `derived` trả `wingDmg`, `wingAbsorb` (+2 % mỗi cấp nâng tính theo `effective_level`); áp vào đòn người chơi
  (`mult`) và đòn quái (sau `guard`). Đấu trường (`Arena.opponent/2`): % sát thương của cánh gộp vào `atk`, % hấp thụ gộp vào máu (`maxHp / (1 − absorb)`).
  `Engine.look` có `wing: %{cls, tier}`; `doll.js` vẽ cánh bằng canvas dưới lớp thân.
- **Máy Hỗn Nguyên (D5):** `HacLong.Game.Chaos` (`combine/3`, `rate/2`, `output/2`), công thức `CHAOS` (`Data.chaos/0,1`); NPC
  `chaos` ở `priv/maps/village.json` [20, 6] (role `chaos`), lệnh `chaos {id, gear}` (Commands, `at_npc`). Client: `chaosCard`.
- **Client:** `GAME_DATA.UPGRADE`, `GAME_DATA.CHAOS` (PageController). `ui.js`: `SLOT_OPEN` có `wing`, `SLOT_REMOVABLE`
  (`shield`, `wing`), `effLevel`, `upClass` (viền `.up7/.up9/.up11`), nút khóa trong `showTip`, `forgeCard` (tỉ lệ, rủi ro,
  hỏi lại khi có thể vỡ), `chaosCard`, `gearTag`. Đồ khóa bị loại khỏi danh sách bán / chợ / giao dịch.
- Simulator in thêm `ngọc=` (số ngọc nhặt được trung bình). Bot vẫn chỉ nâng tới +4 như cũ.
- Test: `test/hac_long/game/forge_test.exs`.

## 9e. Lớp MU, dữ liệu đồ Item.txt, hình theo cấp (2026-10-04)

- Lớp nhân vật: mục 5. Đổi lớp đụng: `priv/game_data/classes.json` (`CLASSES`), `items.json` (cánh `wing_<lớp>_<1|2>`), `Engine` (`derived`,
  `level_up`, `allocate`, `rest`, kỹ năng), `Gear` (`@stats`), `Characters` (`stats`, `mp`), `Admin` (`add_stats`, `give_gear`),
  `Simulator` (`@alloc`), `World.drink_fountain`, `ui.js` (`STAT_INFO`, thanh MP, màn tạo nhân vật), `doll.js` (màu cánh).
- **`HacLong.Game.ItemTxt`**: đọc Item.txt (tách theo khoảng trắng, chú thích `//`, cảnh báo dòng hỏng), `to_item/1` ra nháp
  đồ Hắc Long (`id item_g_i`, `ref "g/i"`, `atkMin/atkMax/atk`, `def`, `level`, `req` gốc, `classes` cờ == 1, `cells`).
  `mix hac_long.items.import` ghi `priv/items_raw.json`, `priv/items_from_txt.json`. **Chưa thay đồ trong game** (INTEGRATION_PLAN §10).
- **`HacLong.Game.ItemIcons`**: tên file → bảng tra `{"g/i" | "custom/{id}" => {"cấp" => đường dẫn}}`; `pick/3` lấy mức lớn
  nhất ≤ cấp. `mix hac_long.icons [--src]` (mặc định `assets_src/items/icons`, hoặc `HL_ITEM_ICONS_DIR`) chép hình sang
  `priv/static/assets/items/`, ghi `priv/static/assets/item_icons.json`. `PageController` đọc file này mỗi lần tải trang
  (`GAME_DATA.ITEM_ICONS`); `ITEMS` gửi kèm `id`. Client: `ownIcon(it, cấp)` trong `itemIcon` / `cellIcon`, thiếu thì icon cũ.
- Test: `test/hac_long/game/item_data_test.exs` (file mẫu tự viết `test/fixtures/Item.sample.txt`).

## 9f. Nền dữ liệu và cấu hình (Phase 1, 2026-10-04)

- **J3** `priv/game_data/*.json`: 12 file (bảng file → khóa trong moduledoc `HacLong.Game.Data`). `Data` đọc mọi file theo tên,
  ghép; hai file cùng khóa → `CompileError`. Client vẫn nhận `GAME_DATA` như cũ.
- **J1 / A3 / B2 / E7** `RULES` (`rules.json`), đọc lúc biên dịch qua `Data.rules/0`:
  - `character` (cấp tối đa, vàng / đồ lúc tạo, chuyển sinh, giá nghỉ trọ, phạt chết), `xp` (`coef × L^exp + base`),
    `combat` (chí mạng / hệ số chí mạng / né theo AGI, dao động sát thương, % hồi MP, bỏ chạy, chí mạng quái, % cánh mỗi cấp),
    `skill_effects` (hệ số, lượt, sức mạnh của 10 kiểu `effect`), `monster` (công thức chỉ số quái, hệ số trùm),
    `loot` (bình máu theo cấp `Data.potion_for/1`, tỉ lệ rơi đồ hiếm, trọng số độ hiếm, vật phẩm lễ hội),
    `shop` (giá bán lại 40 %), `upgrade` (+N bằng quặng), `chests`, `crafting`, `tower`, `pets`, `bestiary`, `home`, `events`,
    `daily`, `fishing`, `tutorial`, `guild`, `market`, `arena`, `party`, `world`, `names`.
  - Module dùng `@rules Data.rules().nhóm` (compile-time), giữ đúng thứ tự phép tính cũ → simulator cùng seed giống hệt.
  - `Engine.base_xp/1`, `base_gold/1`: kinh nghiệm / vàng gốc theo cấp quái, dùng chung cho tháp, việc hằng ngày, sổ quái.
  - Client: `RULES` trong `PageController` thêm `upgradeBonusPct`, `wingPerLevel`, `smithEpicPerLevel`, `smithRare`, `tameBonus`,
    `petXpCoef` (trước viết cứng trong `ui.js`).
- **J2** `HacLong.Game.DataCheck`: `run!/1` (gọi trong `Data`), `run_maps!/2` (gọi trong `Maps`). Trả lỗi dạng
  `"shop.json: SHOP có món \"x\" không có trong ITEMS"`. Thêm `role` NPC mới → thêm vào `@npc_roles`; kỹ năng thú mới → `@pet_skills`.
- **B9** `Names.banned?/1`: bỏ dấu + chữ thường; `banned_words` khớp nguyên từ, `banned_parts` khớp một phần (có đổi số `4dm1n`).
  Áp dụng `Names.validate/1` (tên nhân vật) và `Guilds` (tên + ký hiệu bang). Tên đã có trước không bị đổi.
- **B11** `World.valid_pos/1`: ô không đi được hoặc bị bít bốn phía → `Maps.entry/1` (cạnh đá dịch chuyển, không có thì chỗ đứng
  khi qua cổng vào), bản đồ không còn → Nhà.
- Test: `test/hac_long/game/data_rules_test.exs`.

## 9g. Lưới an toàn test (Phase 2, 2026-10-04)

- **`priv/static/js/logic.js`** (`window.HLLogic`, nạp trước `net.js`): hàm thuần dùng chung — `firstStep` (tìm đường BFS,
  `map.js` `nextStep` gọi), `iconForLevel`, `effLevel`, `upClass`, `chaosRate`, `petLevel`, `tamePrice`, `allocAdd` /
  `allocBatches` (gom lệnh cộng điểm). Test: `test/js/logic.test.mjs` (`node --test`, CI job `hac-long`).
- **Hook `window.__hl`** (`ui.js` `testHook`, chỉ khi `?test=1`): `player()`, `ui()`, `world()`, `npcs()`, `walkTo()`,
  `step()`, `send()`, `tab()`. Không thêm quyền gì.
- **`e2e/`** (xem `e2e/README.md`): `lib.mjs` (đăng ký + tạo nhân vật với `X-Forwarded-For` riêng, `adminSession` dùng
  `e2e_admin` từ `scripts/e2e_seed.exs`, `travel` / `meetNpc` / `engage` / `fight`), 5 kịch bản `smoke`, `social`,
  `progress`, `admin`, `mobile`; `run.mjs` chạy hết (`HL_SHOTS_DOCS=1` chép ảnh sang `docs/screenshots/e2e-*.png`);
  `soak.mjs` bot WebSocket thô (giao thức Phoenix v2), đo p50 / p95 / max, lỗi, mất kết nối, bộ nhớ BEAM.
- **`test/hac_long_web/dupe_test.exs`** (N5): bắn song song giao dịch đang chốt + rao chợ + nhận thư (vòng lẻ tranh đúng món,
  vòng chẵn chỉ đụng vàng, giao dịch phải xong); nhiều người mua cùng một món chợ + người bán rút về; bán cho cửa hàng + giao
  dịch cùng món hiếm. Kiểm tổng vàng (cộng thư chưa nhận), số đồ thường (túi + chợ), đồ hiếm đúng một chỗ, `Audit` sạch.
- **CI:** `.github/workflows/hac-long-e2e.yml` (chỉ khi sửa `reference/rpg-game/**`): dev server + Postgres, e2e, soak
  10 bot / 2 phút (chạy tay chỉnh được), `mix hac_long.audit`, tải ảnh + log server.

## 9h. Ngọc, ép, kho (Phase 4, 2026-10-04)

- **`HacLong.Game.Storage`** (Tủ Đồ, NPC `role: "wardrobe"` ở Nhà): đồ thường ở `p.storage.inv` (cột `characters.storage`,
  `%{inv, extra}`), đồ hiếm gắn `stored: true` trong `gear` (`Gear.put/4`, `Gear.stored?/2`). `Gear.bag/1` bỏ đồ đang cất;
  mặc / bán / giao dịch / chợ / máy ghép từ chối đồ đang cất. Số ở `RULES.storage`.
- **Ép theo món:** `Engine.upgrade/3`, `Engine.life/2` nhận ô (`"weapon"`…), uid, hoặc id đồ thường trong túi
  (`forge_target/2` → `forge_instance/3`). Dòng Ngọc Sinh Mệnh lưu `opt` trên bản riêng; `life_bonus/2` cộng vào `derived`
  cùng `upgrade_bonus`. `view.forgeBag` = giá ép từng món trong túi.
- **`Engine.discard/3`**: vứt đồ thường (số lượng) / đồ hiếm (cả món); `gear_log` `out` lý do `DISCARD`.
- **Trần thư quản trị:** `game_channel.ex` `admin("gift")` theo `RULES.mail`.
- Client: `forgePick` (món chọn từ tooltip), `lifeLine`, `wardrobeCard` trong `ui.js`; `RULES.life` gửi từ `page_controller`.

## 9i. Xã hội, xếp hạng, PK cược vàng (Phase 5, 2026-10-04)

- **PK cược:** `HacLong.Game.PkFight` (thuần), `HacLong.PkBet` (GenServer lời mời; `execute/1` chạy ở tiến trình kênh của
  người nhận, giữ hai Session như `HacLong.Trade`). Bảng `pk_matches`. Kênh `"pk"`.
- **Chiến bang:** `HacLong.GuildWars` (GenServer giữ lời tuyên chiến; trận ở bảng `guild_wars`). `Guilds.brief/1` kèm `war`,
  `war_pending` — **GuildWars không được gọi `Guilds.brief/1`** (vòng gọi lại chính nó), dùng `Guilds.member_of/1`.
  Điểm: `Session.battle_over` (trận đấu trường) gọi `GuildWars.record/2`.
- **Xếp hạng:** `Leaderboard.boards/0` (ETS, `init_cache/0` lúc khởi động; `config :hac_long, :leaderboard_cache, false` trong test).
- **Session:** `Party.away/back` khi hết / có tab; đóng hết tab thì hủy giao dịch + lời mời cược; đổi bản đồ / vào trận thì
  `Trade.left/2` (`left_trade/3`); `Session.online/1` cho quản trị.
- **Hộp thư:** `Mailbox.claim_all/3`, `delete_read/1`, `cleanup/2` (hết hạn trừ thư còn quà).
- Client: `HLLogic.nameColor` / `parseChat` (logic.js), `Map_.setRelations`, `pkOp`, `viewGuildWar`, lọc hộp thư.

## 10. Bẫy cần biết

1. **Lưu cả dòng, không khóa lạc quan:** mọi thay đổi nhân vật phải đi qua `Session` của tài khoản đó.
   Sửa DB trực tiếp khi người chơi đang online sẽ bị Session **ghi đè** ở lần lưu sau.
2. ~~`Market.commit/4` bỏ qua kết quả transaction~~: **đã sửa** (Đợt 1), giờ chỉ báo thành công khi transaction commit.
3. ~~Giao dịch hai pha không transaction~~: **đã sửa** (Đợt 2), giờ ghi cả hai nhân vật trong một transaction (mục 9c).
4. ~~Cấp nâng theo loại đồ thường~~: **đã sửa** (Đợt 3), cấp nâng theo từng món (mục 9d).
5. **Ô trang bị cố định** (từ Đợt 3 là 4 ô: thêm `wing`) ở nhiều chỗ (mục 3, 6). Thêm ô mới phải sửa: `characters.ex:67`, `engine.ex:940-950, 1109, 1128-1134`,
   `doll.js`, `ui.js` (`310, 1099-1110, 1308-1327, 1373`), `market.ex`, `trade_offer.ex`.
6. **Quyền admin gán lúc kết nối:** đổi quyền thì người đó phải tải lại trang.
7. **`priv/game_data/` nạp lúc biên dịch (kể cả `RULES`):** sửa xong phải biên dịch lại (server dev tự làm; bản release phải build lại).
8. ~~Không có log vàng / đồ~~: **đã có** (Đợt 2). Nhưng nhật ký chỉ đúng khi mọi lần ghi nhân vật đi qua `Characters.save!`;
   sửa vàng thẳng bằng SQL sẽ bị `mix hac_long.audit` báo `gold_mismatch`.
9. **Session bị giữ khi giao dịch:** thêm `handle_call` mới vào Session thì nó tự xếp hàng khi bị giữ (mệnh đề chung). Thêm
   `handle_info` mới mà ghi nhân vật thì phải kiểm `s.held` (như `flush/1`), nếu không sẽ ghi đè kết quả giao dịch.
