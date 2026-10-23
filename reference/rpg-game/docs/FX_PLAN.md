# Kế hoạch hiệu ứng

**Đã làm (2026-10-23):** Đợt 1 (đánh quái + kỹ năng theo hệ trong bảng trận, `js/fx.js`), phần di chuyển của Đợt 5
(bụi bước chân, ô đích, cột sáng khi sang bản đồ), viền +7/+9 nhấp nháy. Đợt 2 (đồ rơi theo độ quý, ép đồ / Máy Hỗn Nguyên /
Ngọc Sinh Mệnh). Còn lại: Đợt 3 (gồm hướng C), 4, phần còn lại của 5.

Ghi lại các đề xuất đã bàn ngày 2026-10-19. Mọi hiệu ứng **chỉ vẽ ở client** (server vẫn quyết định sát thương, đồ, kết quả):
không đổi luật chơi, không cần file hình mới (vẽ bằng Canvas 2D / CSS), tôn trọng công tắc hiệu ứng (`hl-fx`, `MapView.fxOn`)
và "giảm chuyển động" (`prefers-reduced-motion`), tự giảm bớt trên máy yếu. Hiệu ứng chạy song song lúc chờ server, không làm
chậm nhịp đánh (kể cả tự đánh).

**Anh đã chốt:** hướng **A** (hiệu ứng trong bảng đánh quái) + hướng **C** (thêm vài hiệu ứng nhẹ trên bản đồ). Không làm hướng B.

## Hướng đã bàn cho đánh quái / kỹ năng

- **A — giữ bảng đánh quái, phủ một lớp canvas trong suốt lên bảng** (`viewBattle`, `battleFx` trong `priv/static/js/ui.js`).
  Mọi chế độ dùng chung bảng (đánh tay, tự đánh, tháp, Quảng Trường Quỷ, Lâu Đài Máu, Kalima, Hỗn Chiến, đồ sát, PK cược) đều có
  hiệu ứng. Hình to, nhìn rõ trên điện thoại, ít rủi ro.
- **C — thêm trên bản đồ** (`priv/static/js/map.js`): người khác thấy mình đang đánh (vung vũ khí, tia sáng, số sát thương nhỏ
  trên đầu quái), quái chết tan thành hạt. Có thể cần server gửi thêm sự kiện nhẹ cho cả bản đồ (hỏi anh trước nếu đụng protocol).
- **B — bỏ bảng, đánh trực tiếp trên bản đồ:** KHÔNG làm (thay đổi lớn, đụng mọi chế độ).

## Danh sách hiệu ứng

### Đợt 1 — đánh quái và kỹ năng (trong bảng, hướng A)
- Đòn thường: nhân vật lao tới rồi lùi; vệt chém theo vũ khí (kiếm vòng cung, cung mũi tên bay, gậy cầu phép); quái chớp trắng,
  lùi lại, máu văng hạt.
- Chí mạng: khựng hình 0,1 giây, số to đỏ cam, rung bảng. Trượt: quái nghiêng né, chữ "Trượt" bay chéo.
- Quái chết: tan thành hạt, vàng bay về túi. Thanh máu tụt có lớp trễ màu trắng chạy theo.
- Kỹ năng theo **hệ nguyên tố** (dùng chung theo hệ, không vẽ từng chiêu):
  - Lửa: cầu lửa bay, nổ bùng, tàn lửa. Băng: mũi băng, sương xanh, mảnh băng vỡ. Sét: tia zigzag từ trên, nháy màn hình.
  - Gió / độc: xoáy lốc, bong bóng độc. Hồi máu / buff: vòng phép xoay dưới chân, số xanh, hào quang.
  - Lúc niệm: vòng phép dưới chân màu theo hệ. Đòn khắc hệ: chữ "Khắc hệ!" + viền riêng.
- Kỹ thuật: một bộ hạt hiệu ứng chung (hạt, vệt, vòng sáng), mỗi hiệu ứng vài dòng cấu hình.

### Đợt 2 — đồ rơi và ép đồ
- **Đồ rơi theo độ quý:** thường bình thường; có dòng cộng thêm viền xanh dương; Excellent cột sáng xanh lá; đồ Thần cột sáng
  vàng + lấp lánh; ngọc xoay phát sáng theo màu. Đồ rất hiếm: khựng hình, rung nhẹ, âm riêng.
- **Ép đồ +N:** đồ ở giữa, ngọc bay vào, búa gõ tia lửa, thanh hồi hộp ~1 giây rồi ra kết quả. Thành công nổ sáng mạnh dần từ +7;
  +10/+11 nổ vàng cam + thông báo cả server. Thất bại: đồ nứt, khói xám, chữ rung; vỡ đồ thì vỡ thành mảnh.
- **Máy Hỗn Nguyên:** nguyên liệu xoáy vào lò, lò rung, lóe sáng (thành) hoặc tắt lịm (hỏng).

### Đợt 3 — trên bản đồ (hướng C) + hào quang
- Hướng C như trên (người khác thấy mình đánh, quái tan hạt trên bản đồ).
- **Hào quang nhân vật theo đồ** (giống MU): đủ bộ cùng mức từ +7 xanh dương, +9 vàng, +11 cam đỏ có hạt bay lên. Cánh rơi hạt sáng
  phía sau. Thú hiếm (Long Vương) có vệt vàng theo sau.
- Hiệu ứng trạng thái trong trận: độc bong bóng xanh, bỏng lửa nhỏ, chảy máu giọt đỏ, choáng sao xoay trên đầu quái.
- Thú cưng: thú nhảy ra cắn kèm số sát thương màu riêng; Thủy Long Ba cột nước phụt lên; Long Vương có rồng vàng uốn lượn bay
  qua màn hình khi dùng kỹ năng.

### Đợt 4 — khoảnh khắc thành tích, thông báo server
- Lên cấp: cột sáng trên bản đồ, chữ LEVEL UP, chỉ số tăng bay lên.
- Chuyển sinh: màn chuyển cảnh riêng, xoáy sáng, ảnh nhân vật lớn + số lần chuyển sinh.
- Thành tựu / danh hiệu: thẻ huy hiệu trượt xuống từ trên + âm thanh. Hạ trùm lần đầu: chữ lớn "TRÙM ĐÃ GỤC", đồ bay ra.
- Thông báo cả server: dải băng chạy ngang đầu màn hình, màu + icon theo loại (ép +11, rớt đồ Thần, câu được Long Vương, Trùm thế
  giới, sự kiện mở).

### Đợt 5 — trau chuốt
- Di chuyển: bước chân nhún nhẹ + bóng tròn dưới chân; bụi ở đất / cát, gợn nước trên bến / cầu gỗ; vòng sáng ở ô đích khi chạm;
  qua cổng / dịch chuyển: cột sáng xoáy, nhân vật thu nhỏ rồi hiện ra.
- Giao diện: số vàng nhảy tăng dần; đồ mới vào túi ô nảy + sáng; rương bật nắp, vật phẩm bay ra; hộp quà / thư lắc trước khi mở.
- Thế giới: NPC có động tác (Thợ Rèn gõ búa tia lửa, Bà Lang khuấy nồi khói, Ông Lão giật cần); cổng xoáy sáng; đom đóm / bướm;
  tro bay Núi Lửa, tuyết Băng Nguyên, cát bay Hoang Mạc.

## Cách làm từng đợt
Mỗi đợt: làm xong → chụp ảnh / quay ngắn cho anh xem → anh OK mới sang đợt sau. Thêm i18n (`en.json`), ghi `DECISIONS.md`,
chạy `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`, `node --test test/js/*.mjs`.

---

# Đóng gói app điện thoại (đã bàn, chưa làm)

1. **PWA (có sẵn):** `priv/static/manifest.json` + icon `priv/static/app/`. Android Chrome / iPhone Safari → "Thêm vào màn hình chính".
2. **TWA (.apk / .aab, Google Play) — em đề xuất khi có tên miền:** đóng gói bằng Bubblewrap; cần tên miền HTTPS, file
   `/.well-known/assetlinks.json` trên server, khóa ký app (giữ kỹ), tài khoản Google Play 25 USD một lần. Sửa game không cần làm lại .apk.
3. **Capacitor:** vỏ app gọi được tính năng máy (thông báo đẩy, rung, giữ màn hình sáng), làm được bản iPhone (cần Mac + Apple 99 USD/năm).

- Lợi ích: icon, toàn màn hình, có trên Google Play, **thông báo đẩy** (Long Vương sắp nổi, Quảng Trường Quỷ mở, có thư).
- Lưu ý: vẫn cần internet + server; lên Google Play có rủi ro bị gỡ vì tên / cơ chế / icon mô phỏng MU (phát .apk riêng ít rủi ro hơn).
- Việc tiếp theo khi anh có tên miền: thêm `assetlinks.json`, script đóng gói + hướng dẫn, rồi thông báo đẩy cho sự kiện.
