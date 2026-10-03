# Hướng dẫn quản trị MU Web (bản release)

> Dành cho **người vận hành server**. Mọi lệnh dưới đây đã chạy thử trên bản release (`MIX_ENV=prod mix release`)
> ngày 2026-10-03, kết quả ghi kèm từng lệnh.
>
> - Cài đặt / chạy lần đầu: `docs/RUN_LOCAL.md`.
> - Luật chơi để trả lời người chơi: `docs/USER_GUIDE.md`.

## Mục lục

1. [Hiện có gì, chưa có gì](#1-hiện-có-gì-chưa-có-gì)
2. [Cách gõ lệnh quản trị](#2-cách-gõ-lệnh-quản-trị)
3. [Khởi động, dừng, cập nhật server](#3-khởi-động-dừng-cập-nhật-server)
4. [Thông báo hệ thống](#4-thông-báo-hệ-thống)
5. [Cấm chat](#5-cấm-chat)
6. [Gửi thư / tặng quà](#6-gửi-thư--tặng-quà)
7. [Bật / tắt sự kiện](#7-bật--tắt-sự-kiện)
8. [Tra cứu người chơi](#8-tra-cứu-người-chơi)
9. [Sửa nhân vật (chỉ khi offline)](#9-sửa-nhân-vật-chỉ-khi-offline)
10. [Kiểm tra gian lận (audit)](#10-kiểm-tra-gian-lận-audit)
11. [Sao lưu và phục hồi DB](#11-sao-lưu-và-phục-hồi-db)
12. [Xử lý tình huống thường gặp](#12-xử-lý-tình-huống-thường-gặp)
13. [Bảng lệnh nhanh](#13-bảng-lệnh-nhanh)

---

## 1. Hiện có gì, chưa có gì

| Có (qua dòng lệnh trên máy chủ) | **Chưa có** |
|---|---|
| Thông báo hệ thống toàn server | Khóa (ban) tài khoản, kick người đang online |
| Cấm / bỏ cấm chat | Quyền admin / GM trong game, lệnh `/` cho GM |
| Gửi thư, tặng Zen / item qua thư | Trang web quản trị |
| Bật / tắt Golden Invasion, World Boss | Xóa nhân vật, đổi tên |
| Kiểm tra dupe đồ / lệch Zen, thống kê Zen | Trả lại đồ bị mất (chỉ tặng đồ mới qua thư) |
| Đặt Zen có ghi audit, reset PK, đưa nhân vật về thị trấn (offline) | |

- **Không có quyền admin trong game:** mọi thao tác đều làm **trên máy chủ**, ai vào được máy chủ là có toàn quyền.
  Giữ kín SSH và file `.env`.
- Phần "Chưa có" là việc ngoài Phase 7, cần duyệt mới làm (xem đề xuất 3 mức ở trao đổi ngày 2026-10-03).

---

## 2. Cách gõ lệnh quản trị

Server là một node Erlang / Elixir. Lệnh quản trị là **một đoạn code Elixir gửi vào server đang chạy** bằng `bin/mu rpc`.

### 2.1 Chạy bằng Docker (cách khuyên dùng)

Đứng trong thư mục có `docker-compose.yml`:

```bash
docker compose exec app bin/mu rpc 'Mu.Chat.system("Xin chào")'
```

### 2.2 Chạy trực tiếp (không Docker)

Đứng trong thư mục release (vd. `_build/prod/rel/mu/`), **cùng user hệ điều hành** với server
(dùng chung cookie trong `releases/COOKIE`):

```bash
bin/mu rpc 'Mu.Chat.system("Xin chào")'
```

> Trong tài liệu này viết tắt cả hai cách là `bin/mu rpc '…'`.

### 2.3 Quy tắc gõ

- Cả đoạn code nằm trong **dấu nháy đơn** `'…'`. Chuỗi bên trong dùng **nháy kép** `"…"`.
  Chuỗi có dấu nháy đơn (vd. `Devil's`) thì phải thoát theo shell, tốt nhất tránh dùng.
- Muốn **xem kết quả** thì bọc trong `IO.inspect(...)`. Không bọc thì lệnh vẫn chạy nhưng không in gì.
- Nhiều lệnh trong một lần: ngăn cách bằng `;`.
- Truy vấn DB cần `import Ecto.Query;` ở đầu.
- Tiếng Việt có dấu gõ bình thường (UTF-8).
- Lỗi cú pháp chỉ in ra lỗi, **không làm sập server**.

### 2.4 Phiên tương tác (gõ nhiều lệnh liền)

```bash
bin/mu remote                      # Docker: docker compose exec app bin/mu remote
iex(mu@...)1> Mu.Chat.system("Test")
:ok
```

Thoát bằng **Ctrl + C hai lần**. **Không gõ `System.stop()` / `:init.stop()`**: lệnh đó tắt luôn server.

---

## 3. Khởi động, dừng, cập nhật server

### 3.1 Docker

| Việc | Lệnh |
|---|---|
| Chạy (lần đầu build image) | `docker compose up -d --build` |
| Xem log | `docker compose logs -f app` (Ctrl + C để thoát xem) |
| Khởi động lại | `docker compose restart app` |
| Dừng | `docker compose stop` (DB giữ nguyên trong volume `db`) |
| Trạng thái | `docker compose ps` |

- `bin/start` trong container **tự chạy migration còn thiếu** rồi mới bật server.
- **Không** chạy `docker compose down -v`: `-v` **xóa volume DB = mất toàn bộ dữ liệu**.

### 3.2 Chạy trực tiếp

Cần các biến môi trường (xem `.env.example`):

| Biến | Bắt buộc | Ý nghĩa |
|---|---|---|
| `DATABASE_URL` | ✔ | `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | ✔ | chuỗi ngẫu nhiên ≥ 64 ký tự (`openssl rand -base64 48`) |
| `PHX_HOST` | ✔ | IP hoặc domain người chơi truy cập |
| `PHX_SCHEME`, `PHX_URL_PORT` | | `http` / `https` và cổng hiện trên URL |
| `PORT` | | cổng server lắng nghe (mặc định 4000) |
| `CHECK_ORIGIN` | | danh sách origin được phép, ngăn bằng dấu phẩy |
| `TRUSTED_PROXIES` | | dải IP proxy (Caddy…) để đọc IP thật |
| `POOL_SIZE` | | số kết nối DB (mặc định 10) |

```bash
bin/mu eval "Mu.Release.migrate()"     # chạy migration còn thiếu
PHX_SERVER=true bin/mu daemon          # chạy nền (hoặc: bin/start = migrate + start)
bin/mu pid                             # kiểm tra đang chạy
bin/mu stop                            # dừng
```

### 3.3 Cập nhật bản mới / đổi số gameplay

- Số gameplay (`priv/game_data/*.json`) và bản đồ được **đóng gói vào bản release**.
  Sửa số → **build lại** (`docker compose up -d --build` hoặc `MIX_ENV=prod mix release`) → khởi động lại.
- Trước khi cập nhật:
  1. thông báo bảo trì (mục 4) vài phút trước;
  2. **sao lưu DB** (mục 11);
  3. cập nhật và khởi động lại.
- **Những thứ mất khi khởi động lại** (chỉ sống trong RAM):
  - sự kiện đang chạy (quái event biến mất, lịch chạy tiếp ở lần kế);
  - danh sách cấm chat;
  - nhóm (party), giao dịch đang mở, thách đấu, guild war đang diễn ra.

  Nhân vật, túi đồ, kho, Zen, guild, thư, nhiệm vụ nằm trong DB, không mất.

---

## 4. Thông báo hệ thống

```bash
bin/mu rpc 'Mu.Chat.system("Server bảo trì lúc 03:00, dự kiến 15 phút")'
# → :ok
```

- Tin hiện dòng **[Hệ thống]** trong khung chat của **mọi người đang online, mọi map**.
- Người offline **không** nhận được. Muốn mọi người đều thấy → gửi thư (mục 6), nhưng thư là theo từng nhân vật.
- Tối đa 100 ký tự / tin (như chat thường).

---

## 5. Cấm chat

```bash
bin/mu rpc 'Mu.Chat.mute("TenNhanVat", 30)'         # cấm 30 phút → :ok
bin/mu rpc 'Mu.Chat.mute("TenNhanVat", nil)'        # cấm tới khi server khởi động lại
bin/mu rpc 'Mu.Chat.unmute("TenNhanVat")'           # bỏ cấm → :ok
bin/mu rpc 'IO.inspect(Mu.Chat.muted_until("TenNhanVat"))'
# → nil (không bị cấm) | 1791072974 (giờ hết cấm, giây Unix) | :infinity
```

- Theo **tên nhân vật**, không phân biệt hoa thường. Không kiểm tên có tồn tại: gõ sai tên vẫn trả `:ok`.
- Cấm **một nhân vật**, không phải cả tài khoản: người chơi đổi sang nhân vật khác vẫn chat được.
- Danh sách cấm **mất khi khởi động lại server**.
- Đổi giờ hết cấm sang giờ đọc được:
  `bin/mu rpc 'IO.inspect(DateTime.from_unix!(Mu.Chat.muted_until("TenNhanVat")))'`.

---

## 6. Gửi thư / tặng quà

```bash
# Thư thông báo (không quà)
bin/mu rpc 'IO.inspect(Mu.Mail.deliver_to_name("TenNhanVat", %{kind: "SYSTEM", title: "Bảo trì", body: "Server bảo trì 03:00"}))'

# Tặng Zen
bin/mu rpc 'IO.inspect(Mu.Mail.deliver_to_name("TenNhanVat", %{kind: "GIFT", title: "Quà sự kiện", body: "Cảm ơn bạn", zen: 1000}))'

# Tặng item
bin/mu rpc 'IO.inspect(Mu.Mail.deliver_to_name("TenNhanVat", %{kind: "GIFT", title: "Bình máu", item: "hp_potion_small", quantity: 10}))'
```

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| `kind` | ✔ | `"SYSTEM"` (không quà) hoặc `"GIFT"` (có Zen / item) |
| `title` | ✔ | tối đa 80 ký tự |
| `body` | | nội dung |
| `zen` | | số nguyên ≥ 0 |
| `item` | | **mã template** (vd. `hp_potion_small`, `jewel_bless`), xem bên dưới |
| `quantity` | | ≥ 1, mặc định 1 |

**Kết quả:**

| Trả về | Nghĩa |
|---|---|
| `{:ok, %Mu.Mail.Message{…}}` | đã gửi. Người đang online thấy số trên 📬 ngay |
| `{:error, :no_character}` | sai tên nhân vật |
| `{:error, :unknown_item}` | sai mã item |
| `{:error, :title_too_long}` / `:bad_zen` / `:bad_quantity` / `:bad_mail` | sai dữ liệu |

- Người chơi bấm **[Nhận]** trong 📬 Hộp thư. Đồ vào túi (cần chỗ trống), Zen cộng thẳng.
  Lúc nhận mới ghi log `MAIL` (Zen) / `MAIL_CLAIM` (item).
- Thư **hết hạn sau 30 ngày**: quá hạn thì không thấy, không nhận được nữa. Mỗi nhân vật tối đa 100 thư.
- Một lần gửi = **một nhân vật**. Gửi nhiều người: gọi nhiều lần, hoặc một vòng lặp
  (ví dụ tặng mọi nhân vật cấp ≥ 10):

  ```bash
  bin/mu rpc 'import Ecto.Query; for n <- Mu.Repo.all(from c in Mu.Game.Character, where: c.level >= 10, select: c.name), do: Mu.Mail.deliver_to_name(n, %{kind: "GIFT", title: "Quà mừng", zen: 500})'
  ```

**Tra mã item:**

```bash
bin/mu rpc 'IO.inspect(Mu.Game.Data.items() |> Map.keys() |> Enum.sort(), limit: :infinity)'
bin/mu rpc 'IO.inspect(Mu.Game.Data.item("jewel_bless"))'      # xem chi tiết một món
```

Hay dùng: `hp_potion_small`, `mp_potion_small`, `hp_potion_medium`, `mp_potion_medium`, `jewel_bless`,
`jewel_soul`, `jewel_life`, `jewel_chaos`. Đồ tặng qua thư luôn là **+0, không option**.

> ⚠ Quà là Zen / đồ **sinh ra mới**. Tặng nhiều làm lạm phát. Mọi khoản đều hiện trong thống kê Zen (mục 10).

---

## 7. Bật / tắt sự kiện

Sự kiện **tự chạy theo lịch UTC** (Golden Invasion 00, 03, 06… giờ, 15 phút; World Boss giờ lẻ 01, 03, 05…, 20 phút).
Bật / tắt tay khi cần:

```bash
bin/mu rpc 'IO.inspect(Mu.WorldEvents.start("golden_invasion"))'   # hoặc "world_boss"
bin/mu rpc 'IO.inspect(Mu.WorldEvents.stop("world_boss"))'
bin/mu rpc 'IO.inspect(Mu.WorldEvents.active())'                   # sự kiện đang chạy
```

| Trả về | Nghĩa |
|---|---|
| `:ok` | đã bật / tắt |
| `{:error, :running}` | sự kiện đó đang chạy rồi |
| `{:error, :not_running}` | tắt khi không chạy |
| `{:error, :unknown}` | sai tên (chỉ có `golden_invasion`, `world_boss`) |

- Bật tay: chạy **ngay**, đủ thời lượng như lịch, có thông báo bắt đầu / kết thúc. **Không có** báo trước 5 phút.
  Muốn báo trước thì tự gửi `Mu.Chat.system(...)` trước.
- Tắt tay: quái sự kiện biến mất, **không** chia thưởng boss.
- Đổi giờ / thời lượng / phần thưởng: sửa `events` trong `priv/game_data/config.json`, rồi build lại (mục 3.3).

---

## 8. Tra cứu người chơi

**Số người đang online / tên nhân vật online:**

```bash
bin/mu rpc 'IO.inspect(Registry.count(Mu.Game.Registry))'
bin/mu rpc 'IO.inspect(Registry.select(Mu.Game.NameRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}]))'
# → ["tester1", ...]  (tên viết thường)
```

**Thông tin một nhân vật** (kèm tài khoản):

```bash
bin/mu rpc 'import Ecto.Query; IO.inspect(Mu.Repo.all(from c in Mu.Game.Character, join: a in assoc(c, :account), where: fragment("lower(?)", c.name) == "tester1", select: %{id: c.id, name: c.name, account: a.username, class: c.class, level: c.level, zen: c.zen, map: c.map_id, x: c.position_x, y: c.position_y, pk: c.pk_points}))'
```

Kết quả mẫu:

```elixir
[%{account: "admintest", class: "DK", id: "cfb1ba4b-…", level: 1, map: "lorencia",
   name: "Tester1", pk: 0, x: 15, y: 31, zen: 5000}]
```

> Viết tên nhân vật **chữ thường** trong `== "…"`.

- **Nhân vật đang online:** số trong DB có thể chậm hơn trong game một chút (server lưu định kỳ và khi thoát).
- **Mọi nhân vật của một tài khoản:** thay điều kiện `where` bằng `where: a.username == "admintest"`.
- **Tổng số tài khoản / nhân vật:**
  `bin/mu rpc 'IO.inspect({Mu.Repo.aggregate(Mu.Accounts.Account, :count), Mu.Repo.aggregate(Mu.Game.Character, :count)})'`.
- **Bảng xếp hạng:** người chơi tự xem trong game (☰ → 🏆), cập nhật mỗi 5 phút.

---

## 9. Sửa nhân vật (chỉ khi offline)

> ⚠ **Chỉ sửa khi nhân vật OFFLINE.** Kiểm bằng lệnh online ở mục 8.
> Nhân vật đang online thì server giữ bản trong RAM và **ghi đè** thay đổi của bạn khi lưu.
> Với Zen còn làm lệch audit.
>
> ⚠ **Không sửa trực tiếp bảng item / Zen bằng SQL.** Làm vậy `audit` sẽ báo lỗi (mục 10). Tặng đồ / Zen → dùng thư (mục 6).

### 9.1 Đặt Zen (có ghi audit `ADMIN`)

```bash
bin/mu rpc 'import Ecto.Query; c = Mu.Repo.one!(from c in Mu.Game.Character, where: fragment("lower(?)", c.name) == "tester1"); IO.inspect(Mu.Game.ZenAudit.admin_set(c.id, 5000, "boi thuong ticket 12"))'
# → {:ok, :ok}
```

- **Đặt** số Zen (không phải cộng thêm). Muốn cộng thì tra Zen hiện tại trước, hoặc tặng qua thư.
- Tham số cuối là **lý do / mã phiếu** được lưu vào log, nên ghi rõ.

### 9.2 Xóa điểm PK

```bash
bin/mu rpc 'import Ecto.Query; IO.inspect(Mu.Repo.update_all(from(c in Mu.Game.Character, where: fragment("lower(?)", c.name) == "tester1"), set: [pk_points: 0, last_pk_at: nil]))'
# → {1, nil}   (1 = số nhân vật đã sửa; 0 = sai tên)
```

### 9.3 Đưa nhân vật về thị trấn (kẹt chỗ)

```bash
bin/mu rpc 'import Ecto.Query; IO.inspect(Mu.Repo.update_all(from(c in Mu.Game.Character, where: fragment("lower(?)", c.name) == "tester1"), set: [map_id: "lorencia", position_x: 15, position_y: 31]))'
```

- Điểm hồi sinh: Lorencia `("lorencia", 15, 31)`, Noria `("noria", 31, 50)`.
- Người chơi vào lại game sẽ đứng ở đó.

---

## 10. Kiểm tra gian lận (audit)

```bash
bin/mu rpc 'IO.inspect(Mu.Audit.run().problems, limit: :infinity)'
# → []   = sạch
```

**Mỗi dòng lỗi** có dạng `%{check: "...", id: ..., detail: "..."}`:

| `check` | Nghĩa | Nên làm |
|---|---|---|
| `serial_dup` | 2+ món cùng serial: **dấu hiệu nhân bản đồ** | tìm chủ các món (theo `id`), xem log, giữ bằng chứng |
| `orphan` | món đồ không nằm ở đâu | báo lập trình, đừng tự xóa |
| `owner_mismatch` / `no_audit` | chủ hiện tại khác log chuyển chủ cuối | thường do sửa DB tay; nếu không ai sửa → nghi gian lận |
| `zen_mismatch` | Zen nhân vật ≠ tổng log Zen | thường do sửa Zen bằng SQL (không qua `admin_set`); nếu không → nghi gian lận |

**Thống kê Zen** (Zen sinh ra / mất đi theo ngày và lý do):

```bash
bin/mu rpc 'IO.inspect(Mu.Audit.run(days: 7).supply, limit: :infinity)'
```

Kết quả mẫu:

```elixir
%{total: 5000, characters: 1,
  by_day: [%{day: "2026-10-03", reason: "ADMIN", gained: 5000, spent: 0}]}
```

- `total`: tổng Zen đang có trên server.
- `reason` hay gặp:
  - `MONSTER` (đánh quái), `BUY` / `SELL` (NPC), `TRADE`, `MAIL` (quà);
  - `GUILD_CREATE`, `CHAOS` (phí Chaos Machine), `QUEST`;
  - `ADMIN` (bạn đặt), `START`, `BASELINE`.
- Theo dõi hằng ngày: `MONSTER` tăng đột biến ở một ngày có thể là bot / lỗi.
- Audit **chỉ đọc**, không tự khóa ai. Nên chạy **mỗi ngày** và **sau mỗi lần cập nhật**.

---

## 11. Sao lưu và phục hồi DB

**Docker:**

```bash
# Sao lưu (nên đặt lịch cron mỗi ngày)
docker compose exec -T db pg_dump -U mu -Fc mu > backup_$(date +%F).dump

# Phục hồi (DỪNG app trước; ghi đè dữ liệu hiện tại)
docker compose stop app
docker compose exec -T db pg_restore -U mu -d mu --clean --if-exists < backup_2026-10-03.dump
docker compose start app
```

**Chạy trực tiếp:** `pg_dump -Fc "$DATABASE_URL_DẠNG_postgres://…" > backup.dump`, phục hồi bằng `pg_restore --clean`.

- Thử phục hồi vào một DB khác ít nhất một lần để chắc bản sao lưu dùng được.
- Giữ bản sao lưu ở **máy khác** với máy chủ.

---

## 12. Xử lý tình huống thường gặp

| Tình huống | Cách xử lý |
|---|---|
| Người chơi spam / chửi bới | `Mu.Chat.mute("Ten", 60)` (mục 5) |
| Người chơi kẹt trong tường / chỗ lạ | chờ họ thoát → đưa về thị trấn (mục 9.3) |
| Mất đồ do lỗi game | xác minh, rồi tặng lại món tương tự qua thư (mục 6). **Không** tạo đồ bằng SQL. Đồ +N / option không tặng lại được |
| Bị PK oan do lỗi | chờ offline → xóa PK (mục 9.2) |
| Bảo trì | `Mu.Chat.system(...)` báo trước 5–10 phút → sao lưu → cập nhật → khởi động lại |
| Nghi nhân bản đồ / Zen | chạy audit (mục 10), lưu kết quả, sao lưu DB làm bằng chứng. Hiện **chưa có lệnh khóa tài khoản**: tạm thời cấm chat và theo dõi; cần khóa thật thì báo lập trình bổ sung |
| Sự kiện bị lỗi / muốn hủy | `Mu.WorldEvents.stop("world_boss")` |
| Muốn tổ chức sự kiện ngoài giờ | báo trước bằng `Mu.Chat.system`, rồi `Mu.WorldEvents.start(...)` |
| Server không vào được | `docker compose ps`, `docker compose logs --tail 200 app`; khởi động lại `docker compose restart app` |
| `bin/mu rpc` báo không kết nối được node | server chưa chạy, hoặc gõ lệnh khác user / khác container (cookie khác) |

---

## 13. Bảng lệnh nhanh

```bash
# Thông báo
bin/mu rpc 'Mu.Chat.system("Nội dung")'

# Cấm / bỏ cấm chat
bin/mu rpc 'Mu.Chat.mute("Ten", 30)'
bin/mu rpc 'Mu.Chat.unmute("Ten")'

# Thư / quà
bin/mu rpc 'IO.inspect(Mu.Mail.deliver_to_name("Ten", %{kind: "GIFT", title: "Quà", zen: 1000}))'
bin/mu rpc 'IO.inspect(Mu.Mail.deliver_to_name("Ten", %{kind: "GIFT", title: "Quà", item: "jewel_bless", quantity: 1}))'

# Sự kiện
bin/mu rpc 'IO.inspect(Mu.WorldEvents.start("golden_invasion"))'
bin/mu rpc 'IO.inspect(Mu.WorldEvents.stop("world_boss"))'

# Online
bin/mu rpc 'IO.inspect(Registry.count(Mu.Game.Registry))'

# Audit
bin/mu rpc 'IO.inspect(Mu.Audit.run().problems, limit: :infinity)'
bin/mu rpc 'IO.inspect(Mu.Audit.run(days: 7).supply, limit: :infinity)'
```

Docker: thêm `docker compose exec app` phía trước mỗi lệnh.

Bản dev (không phải release) có lệnh `mix` tương đương: `mix mu.chat`, `mix mu.mail`, `mix mu.event` (kèm `--node mu@host`),
và `mix mu.audit`. Xem `docs/RUN_LOCAL.md §8`.
