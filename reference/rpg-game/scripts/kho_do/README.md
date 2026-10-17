# Kho Đồ Hắc Long (trang tra cứu)

Sinh trang tra cứu đồ, kỹ năng, nguyên tố, chỉ số chiến đấu, vùng chuyển sinh từ dữ liệu game (`priv/game_data/`).
Đổi số trong game (rules.json, classes.json, đồ…) rồi chạy lại là trang tự đúng theo.

## Một lệnh, xem ngay ở máy

```bash
scripts/kho_do/build.sh              # ghi vào tmp/kho_do/ (đã gitignore)
scripts/kho_do/build.sh ~/kho        # hoặc thư mục khác
```

Ra `kho_do.html` kèm thư mục `pixel/` (hình trang dùng). Mở `kho_do.html` bằng trình duyệt, không cần chạy server.
Cần: Elixir (để đọc dữ liệu game, `MIX_ENV=test`, không cần Postgres) và Python 3.

## Từng bước (nếu cần)

```bash
MIX_ENV=test mix run --no-start scripts/kho_do/export.exs /tmp/kho/data.json
python3 scripts/kho_do/build.py /tmp/kho/data.json priv/static/assets/pixel_icons.json /tmp/kho/kho_do.html
```

- `export.exs`: xuất dữ liệu game ra JSON.
- `build.py` + `tpl.html`: dựng trang; ghi `kho_do.html` và `kho_do.html.files.json` (danh sách hình, đường dẫn tương đối
  với `priv/static/assets/`).

Bản đã đăng: artifact "Kho Đồ Hắc Long". Đăng lại sau khi build: nhờ Claude cập nhật artifact đó từ `tmp/kho_do/kho_do.html`.
