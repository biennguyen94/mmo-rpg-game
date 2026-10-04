# Ghi chú kỹ thuật Hắc Long (cho người / agent sửa code)

> Bản đồ nhanh của code: dữ liệu nằm đâu, luồng lệnh, chỗ vàng / đồ thay đổi, quản trị, xếp hạng, cách vẽ, test.
> Đọc file này trước, rồi mới mở code. Số dòng theo bản hiện tại (gốc commit `5c514b7`).
> **Sửa code ở chỗ nào được nhắc trong file này thì cập nhật luôn file này.**
>
> - Tổng quan cho người chơi / cách chạy: `README.md`.
> - Kế hoạch tích hợp tính năng từ MU Web: `docs/INTEGRATION_PLAN.md`.

## Mục lục

1. [Luồng lệnh và lưu nhân vật](#1-luồng-lệnh-và-lưu-nhân-vật)
2. [Vàng: mọi chỗ thay đổi](#2-vàng-mọi-chỗ-thay-đổi)
3. [Đồ: lưu trữ, đồ ngẫu nhiên, nâng cấp, rơi đồ](#3-đồ-lưu-trữ-đồ-ngẫu-nhiên-nâng-cấp-rơi-đồ)
4. [Quản trị](#4-quản-trị)
5. [Bảng xếp hạng, lớp nhân vật](#5-bảng-xếp-hạng-lớp-nhân-vật)
6. [Vẽ nhân vật và giao diện trang bị](#6-vẽ-nhân-vật-và-giao-diện-trang-bị)
7. [Chiến đấu](#7-chiến-đấu)
8. [Dữ liệu game](#8-dữ-liệu-game)
9. [Test, CI, simulator](#9-test-ci-simulator)
10. [Bẫy cần biết](#10-bẫy-cần-biết)

---

## 1. Luồng lệnh và lưu nhân vật

```
Client (priv/static/js) ──"act"──▶ HacLongWeb.GameChannel ──▶ HacLong.Game.Session (1 GenServer / tài khoản)
                                                               │ run_command_ (session.ex:397-421)
                                                               │   Commands.run → hàm thuần Engine / module tính năng
                                                               │   player đổi → save(s, player) (session.ex:723-726)
                                                               ▼
                                                   HacLong.Game.Characters.save!/2 (characters.ex:23-43)
```

- **Session tuần tự hóa** mọi lệnh của một tài khoản, kể cả nhiều tab (moduledoc `session.ex:1-17`).
- **Lưu cả dòng:** `Repo.insert!(…, on_conflict: {:replace, Character.fields() ++ [:updated_at]}, conflict_target: :user_id)`.
  - Không có cột version, không có khóa lạc quan.
  - `@save_version 1` (`characters.ex:13`) chỉ là trường trong map, không phải khóa.
- **Lệnh thường không chạy trong transaction:** hàm thuần trên map trong RAM, sau đó lưu cả dòng.
- **Di chuyển** gom lại rồi ghi định kỳ: `@flush_ms 5_000` (`session.ex:36`), `mark_dirty` (`session.ex:733`).
- **Giới hạn tốc độ lệnh:** `@act_ms 80`, `@act_burst 10` (`session.ex:40-41`).
- **Schema nhân vật:** `HacLong.Game.Character` (`character.ex:5` `@fields`, `7-54`). `gold` là `:integer` (dòng 13).
- **Một tài khoản = một nhân vật** (`conflict_target: :user_id`).

## 2. Vàng: mọi chỗ thay đổi

**Không có bảng log vàng / log đồ.** Thao tác quản trị chỉ ghi Logger (`game_channel.ex:375`).

Các bảng hiện có: `users`, `user_tokens`, `characters`, `chat_reports`, `user_blocks`, `mails`, `guilds`,
`guild_members`, `guild_requests`, `pvp`, `market_listings`, `home_likes`, `friends`.

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

- **Quyền:** cột `users.admin` boolean (`accounts/user.ex:9`).
  - Gán vào socket lúc kết nối (`user_socket.ex:10`), **không đọc lại**: đổi quyền thì người đó phải kết nối lại.
  - Cấp / thu: `mix hac_long.admin USER [--revoke]` → `Moderation.set_admin/2` (`moderation.ex:178-183`).
    Bản release: `bin/hac_long eval 'HacLong.Moderation.set_admin("ten", true)'`.
- **Kênh:** `handle_in("admin", %{"op" => op}, %{assigns: %{admin: true}})` (`game_channel.ex:374-382`); không phải admin → "Không có quyền." (`384`).
- **Các `op`** (`admin/3`, `game_channel.ex:555-619`):

| op | Làm gì |
|---|---|
| `reports` | `Moderation.open_reports` |
| `lookup {name}` | tìm người: id, username, admin, nhân vật (tên, cấp, vàng, số quái), cấm / khóa, số báo cáo |
| `resolve {id, action: dismiss\|mute\|ban, minutes}` | xử lý báo cáo |
| `mute` / `unmute` / `ban` / `unban` `{uid, minutes, reason}` | `nil` phút = vĩnh viễn (`~U[9999-12-31]`); `ban` thu hồi mọi token |
| `announce {text}` | `Chat.system("📢 …")`, tối đa 200 ký tự |
| `gift {subject, body, gold, xp, items, uid \| all: true}` | `Mailbox.send` / `send_all` |
| `world_boss` | `WorldBoss.spawn_now()` |

- **`HacLong.Moderation`** (`moderation.ex`): `block`, `unblock`, `blocked`, `report`, `open_reports`, `resolve`, `mute`, `unmute`, `ban`, `unban`, `find_user`, `info`, `set_admin`.
- **Thư** (bảng `mails`: `user_id, subject, body, gold, xp, items map, claimed_at`; migration `20261011000000`):
  - kiểm ở `Mailbox.row` (`mailbox.ex:44-73`): tiêu đề không rỗng; gold / xp nguyên ≥ 0; `items` = `%{id => n>0}` với id hợp lệ;
  - **chỉ chứa đồ thường**, không gửi được đồ ngẫu nhiên; **không có trần vàng**;
  - giữ 50 thư / người (`@keep`).
- **Tab Quản trị** (client): hiện khi `Net.isAdmin` (`ui.js:113`, lấy từ `r.admin` lúc vào kênh `ui.js:1818`); `viewAdmin` (`ui.js:142-180`):
  - danh sách báo cáo (bỏ qua / cấm chat 1 giờ / khóa 1 ngày);
  - tra người: cấm chat 1 giờ / 1 ngày, bỏ cấm, khóa 1 ngày / vĩnh viễn, mở khóa, tặng quà cho người đó;
  - thông báo server, tặng quà cho tất cả, gọi trùm thế giới;
  - form quà `giftForm` (`182-193`): một món + vàng / xp; gửi đi ở `onGift` (`196-203`).
- **Chưa có:** chỉnh nhân vật trực tiếp (xp, cấp, vàng, chỉ số), tặng đồ ngẫu nhiên / đồ đã nâng cấp, log thao tác admin.

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

**Lớp nhân vật** (`CLASSES`):

| id | Tên | Gốc str / vit / agi / def | Tăng mỗi cấp | Kỹ năng |
|---|---|---|---|---|
| `warrior` | Chiến Binh | 8 / 7 / 4 / 5 | str +3, vit +1 | cleave, stun_bash, war_cry |
| `rogue` | Thích Khách | 6 / 6 / 9 / 4 | str +1, agi +3 | backstab, venom, shadow_step |
| `knight` | Hiệp Sĩ | 6 / 8 / 3 / 7 | str +2, vit +1, def +1 | holy, guard, judgement |

Mỗi lớp có thêm `hair`, `icon`, `desc`. Cột lớp trong `characters` là `cls`.

## 6. Vẽ nhân vật và giao diện trang bị

- **`priv/static/js/doll.js`** (54 dòng): ghép lớp **ảnh PNG 32×32** (tile Dungeon Crawl) trên canvas, từ `assets/doll/<đường dẫn>.png`.
  - Thứ tự: thân `['base/human_m','legs/pants_black','boots/short_brown2']` → giáp → tóc → vũ khí → khiên (`doll.js:9, 15`).
  - Dữ liệu `look` từ server: `Engine.look` (`engine.ex:940-950`) = `{hair, weapon, armor, shield, pet}`.
    Mỗi giá trị là trường `doll` của món đồ (đồ ngẫu nhiên lấy theo `base`).
  - API: `Doll.canvas` (cache theo khóa lớp), `Doll.url` (data URL; lỗi thì dùng `assets/monsters/hero.png`), `Doll.onReady`.
  - Dùng ở `map.js:332, 345, 459`, `ui.js:52` (`heroSprite`), `307`, `1632`.
- **Ô trang bị trong giao diện** (đều 3 ô Vũ khí / Giáp / Khiên):
  - thẻ "Trang bị" ở tab Nhân vật (`ui.js:1099-1110`), chỉ khiên có nút tháo;
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
  - chí mạng, hệ số chí mạng, né tránh theo `agi`.

**Sát thương:** `damage(atk, dfn) = max(1, round(atk*atk/(atk+dfn)*rand(0.9,1.1)))` (`engine.ex:185`).

**Đòn người chơi** `act_strike` (`engine.ex:419-461`):
- `atk = d.atk*(1+power(:player,"rage"))*(1-power(:player,"weaken"))` (`433-434`);
- hệ số kỹ năng: `strike_with` (`519-590`);
- `mult *= 1 + Bestiary.mastery(p, m.id)` (+5 % ở 25 con, +10 % ở 100 con; `bestiary.ex:13, 25`);
- **`dmg = round(damage*mult*(crit ? critMult : 1))` (`444-445`)**: chỗ cắm thêm % sát thương;
- thú cưng cắn thêm (`464-484`).

**Đòn quái** `monster_turn` (`engine.ex:592-640`):
- `m_atk *= (1 - weaken)`;
- **`dmg = damage(m_atk, d.def) * (chí_mạng ? 1.5 : 1) * (1 - power(:player,"guard"))` (`612-615`)**:
  chỗ cắm thêm % giảm sát thương nhận ("guard" = −50 %);
- né = `d.dodge + evade`.

**Các hệ số % đang có:** hiệu ứng `rage / weaken / guard / evade` (lưu ở `battle.effects`), Bestiary, thú cưng / món ăn (hp / atk / def / gold / xp),
`Home.xp_bonus`, `Events.xp_bonus`.

**Các đường combat khác** cũng đi qua `derived` / `Engine.act`: đấu trường dựng đối thủ từ `Engine.derived`
(`arena.ex:74-96`); trùm thế giới và đánh tổ đội qua `Commands.run` → `Engine.act`.

## 8. Dữ liệu game

- `priv/game_data.json`, **nạp lúc biên dịch** (`HacLong.Game.Data`, `data.ex:31-59`, `@external_resource`): sửa phải biên dịch / khởi động lại.
  Truy cập qua `data.ex:68-91`.
- Khóa cấp cao:

| Khóa | Kiểu | Số lượng | Ghi chú |
|---|---|---|---|
| `CLASSES` | dict | 3 | |
| `ZONES` | list | 6 | Rừng Mê, Trại Goblin, Nghĩa Địa Cổ, Núi Khổng Lồ, Đầm Lầy Rồng, Hang Hắc Long; trường `id, name, desc, icon, levels, monsters, boss` |
| `ITEMS` | dict | 39 | xem dưới |
| `BOSS_DROPS` | dict | 2 | `hill_giant → dragonshield`, `golden_dragon → relic` |
| `SHOP` | list | 17 | |
| `RECIPES` | list | 10 | |
| `QUESTS` | list | 18 | |
| `PETS` | list | 6 | |
| `FURNITURE` | list | 17 | |
| `EVENTS` | list | 4 | |

- **`ITEMS`:**
  - trường: `name, slot, price` (mọi món), `icon, level, doll, sprite, desc, def, atk, food, heal, drop`;
  - theo `slot`: material 14, weapon 8, armor 6, shield 4, food 4, potion 3.
  - Vũ khí (atk / giá / cấp): `club` 3 / 0 / 1, `dagger` 7 / 60 / 3, `broadsword` 13 / 220 / 7, `mace` 21 / 650 / 12,
    `battleaxe` 31 / 1600 / 17, `greatsword` 44 / 3600 / 22, `waraxe` 60 / 7500 / 27, `relic` 82 / chỉ rơi / 30.
  - Giáp: `vest, leather, chain, scale, lamellar, breastplate` (thủ 2 → 34).
  - Khiên: `round, checked, spiked, dragonshield` (chỉ rơi, cấp 24).
  - Nguyên liệu: `ore` (25), `ore_rare` (125), `dragon_scale` (1000), `herb`, `herb_rare`, `fish_*`, `old_boot`, vật phẩm lễ hội.
- **Số đặt cứng trong module** (không có trong JSON): rương `chests.ex:15-19`, rèn `crafting.ex:22-24`, bang `guilds.ex:23-26`,
  chợ `market.ex:23-25`, giao dịch `trade_offer.ex:13`, nâng cấp `engine.ex:20`.

## 9. Test, CI, simulator

- **Test:** 22 file `*_test.exs`.
  - `test/hac_long/`: accounts, guild_quests, leaderboard, world.
  - `test/hac_long/game/`: achievements, bestiary, chests, commands, crafting_events, daily, engine, fishing, gear, home_pets, simulator, tower, trade_offer, tutorial.
  - `test/hac_long_web/`: `channels/game_channel_test.exs` (1 294 dòng), auth_controller, error_json, remote_ip.
  - `test/support/`: `channel_case`, `conn_case`, `data_case`.
- **Alias `mix test`** = `ecto.create --quiet` + `ecto.migrate --quiet` + `test` (`mix.exs:54-61`). Cần PostgreSQL.
- **Không có** test JS, test giao diện, `package.json`.
- **CI:** `reference/rpg-game/.github/workflows/ci.yml` (Postgres 16, OTP 25 / Elixir 1.17: format, compile `--warnings-as-errors`, test).
  ⚠ **Không chạy**, vì thư mục này nằm trong repo `mmo-rpg-game` (`git rev-parse --show-toplevel` = `/home/user/mmo-rpg-game`);
  GitHub chỉ đọc `.github/workflows` ở gốc repo.
- **Simulator:** `mix hac_long.simulate [N]` (mặc định 5).
  - Chạy 3 lớp × 5 cách chơi: `[]`, `quests`, `+daily`, `+upgrade`, `+chests` (`lib/mix/tasks/hac_long.simulate.ex:22-28`) → `Simulator.run(cls, opts)`.
  - Đổi cân bằng thì chạy trước / sau để so.

## 10. Bẫy cần biết

1. **Lưu cả dòng, không khóa lạc quan:** mọi thay đổi nhân vật phải đi qua `Session` của tài khoản đó.
   Sửa DB trực tiếp khi người chơi đang online sẽ bị Session **ghi đè** ở lần lưu sau.
2. **`Market.commit/4` bỏ qua kết quả transaction** (`market.ex:172-179`): rollback vẫn báo thành công.
3. **Giao dịch hai pha không transaction** (`trade.ex:182-200`): tiến trình chết giữa chừng có thể lệch đồ / vàng.
4. **Cấp nâng theo loại đồ thường** (`upgrades` khóa theo id): hai cái `broadsword` dùng chung một cấp; bán cái cuối thì mất cấp.
5. **3 ô trang bị cố định** ở nhiều chỗ (mục 3, 6). Thêm ô mới phải sửa: `characters.ex:67`, `engine.ex:940-950, 1109, 1128-1134`,
   `doll.js`, `ui.js` (`310, 1099-1110, 1308-1327, 1373`), `market.ex`, `trade_offer.ex`.
6. **Quyền admin gán lúc kết nối:** đổi quyền thì người đó phải tải lại trang.
7. **`game_data.json` nạp lúc biên dịch:** sửa xong phải biên dịch lại (server dev tự làm; bản release phải build lại).
8. **Không có log vàng / đồ:** khi nghi gian lận chưa có gì để đối soát (xem `docs/INTEGRATION_PLAN.md` mục 1).
