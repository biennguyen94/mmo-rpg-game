#!/bin/sh
# Phase 15c: lấy dữ liệu / hình đồ gốc MU cho một máy (máy dev hoặc máy chủ). Không có gì trong đây vào git / Docker.
#
#   sh scripts/setup_items.sh                 # clone repo hình cạnh repo game (nếu chưa có) rồi chép hình
#   ITEMS_REPO=/duong/dan/mmo-rpg-game-items sh scripts/setup_items.sh
#
# Cần: git (quyền đọc repo riêng biennguyen94/mmo-rpg-game-items), mix, ImageMagick `convert` (không có thì hình
# không được cắt viền, vẫn chạy). Xong thì tải lại trang game là thấy hình; không cần build lại.
set -e
cd "$(dirname "$0")/.."
ITEMS_REPO="${ITEMS_REPO:-../../../mmo-rpg-game-items}"

if [ ! -d "$ITEMS_REPO/item_ref/items" ]; then
  echo "Chưa có $ITEMS_REPO: clone repo hình (cần quyền đọc)…"
  git clone --depth 1 https://github.com/biennguyen94/mmo-rpg-game-items "$ITEMS_REPO"
else
  echo "Cập nhật $ITEMS_REPO…"
  git -C "$ITEMS_REPO" pull --ff-only || echo "(không cập nhật được, dùng bản đang có)"
fi

# Item.txt: lấy từ repo hình (giống bản afrokick/muonlinejs); chỉ cần khi dựng lại items_mu.json
mkdir -p assets_src/private/items
cp "$ITEMS_REPO/item_ref/Item.txt" assets_src/private/items/Item.txt

mix hac_long.items.import
mix hac_long.items.fetch --icons-from "$ITEMS_REPO/item_ref/items"
mix hac_long.icons
echo "Xong. Hình ở priv/static/assets/mu_items/, bảng tra priv/static/assets/item_icons.json."
