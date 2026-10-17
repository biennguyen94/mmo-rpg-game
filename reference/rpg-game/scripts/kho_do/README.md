# Kho Đồ Hắc Long (trang tra cứu)

Sinh trang tra cứu đồ, kỹ năng, nguyên tố, vùng chuyển sinh từ dữ liệu game:

```bash
MIX_ENV=test mix run --no-start scripts/kho_do/export.exs /tmp/kho/data.json
python3 scripts/kho_do/build.py /tmp/kho/data.json priv/static/assets/pixel_icons.json /tmp/kho/kho_do.html
```

`build.py` ghi `kho_do.html` (dùng hình `pixel/…` của bộ hình Pixel) và `kho_do.html.files.json` (danh sách hình cần
đăng kèm, đường dẫn tương đối với `priv/static/assets/`). Bản đã đăng: artifact "Kho Đồ Hắc Long".
