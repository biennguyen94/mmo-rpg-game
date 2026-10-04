# Dữ liệu đồ của anh (Item.txt + bộ hình theo cấp)

Thư mục này chứa dữ liệu đồ **của anh** (không phải dữ liệu Webzen). Được đưa vào git bình thường.

```
assets_src/items/
  Item.txt          ← bảng đồ (định dạng: docs/INTEGRATION_PLAN.md §10)
  icons/            ← hình đồ, PNG hoặc WebP
```

## Đặt tên hình

| Tên file | Dùng cho |
|---|---|
| `item_{nhóm}_{số}.png` | hình mặc định của đồ `nhóm/số` trong Item.txt |
| `item_{nhóm}_{số}_{N}.png` | hình dùng từ cấp **+N** trở lên (vd `_0`, `_5`, `_10`) |
| `{id}_{N}.png`, `{id}.png` | đồ hiện có của Hắc Long chưa gắn Item.txt (vd `broadsword_7.png`, `club_0.png`) |

- Game chọn mức **lớn nhất ≤ cấp nâng** của món: có `_0`, `_5`, `_10` thì +0…+4 dùng `_0`, +5…+9 dùng `_5`, +10, +11 dùng `_10`.
  Mốc nào là tùy anh, không cần đủ.
- Đuôi `_e` / `_a` (biến thể Excellent / Ancient) được giữ lại nhưng game chưa dùng.
- Thiếu hình thì game dùng icon cũ, không lỗi.

## Lệnh

```bash
cd reference/rpg-game
mix hac_long.icons              # quét icons/, chép sang priv/static/assets/items/, ghi item_icons.json
mix hac_long.items.import       # đọc Item.txt → priv/items_raw.json + priv/items_from_txt.json (nháp)
```

Tải lại trang là thấy hình mới (không cần build lại server). Bản Docker: chạy `mix hac_long.icons` rồi commit
`priv/static/assets/items/` và `priv/static/assets/item_icons.json` trước khi build.
