# assets_src — dữ liệu / hình gốc MU (không vào git)

Mọi thứ MU-derived nằm trong `assets_src/private/` (bị `.gitignore` và `.dockerignore` bỏ qua, CI kiểm tra):

```
assets_src/private/
  items/Item.txt           ← mix hac_long.items.fetch
  items/items_*.json       ← mix hac_long.items.import
  item_icons/              ← đặt hình đồ tay: item_{nhóm}_{số}.png, item_{nhóm}_{số}_{N}.png (+N), {id}_{N}.png
```

Quy trình, đặt tên hình, các hệ số: `docs/ITEMS_PHASE15B.md`. Mỗi máy (máy dev, máy chủ) tự chạy lại.
