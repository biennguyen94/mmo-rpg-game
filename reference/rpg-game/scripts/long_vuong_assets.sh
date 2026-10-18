#!/usr/bin/env bash
# Dựng hình cho Hồ Long Vương và thú Long Vương (DECISIONS "Long Vương").
#   scripts/long_vuong_assets.sh /đường/dẫn/crawl-tiles
# Nguồn: bộ tile Dungeon Crawl Stone Soup (CC0, bản releases/Nov-2015) + vài ô tự vẽ bằng ImageMagick (CC0).
# Ra: priv/static/assets/{tiles,pets,npcs}/… (ghi đè). Cần ImageMagick (convert).
set -euo pipefail
cd "$(dirname "$0")/.."
CRAWL="${1:?đường dẫn tới repo crawl/tiles}"
SRC="$CRAWL/releases/Nov-2015"
A=priv/static/assets
T=$A/tiles
water=$T/water.png

# Long Vương: rồng thân rắn (quicksilver_dragon) tô dải màu vàng kim
convert "$SRC/mon/dragons/quicksilver_dragon.png" -channel RGB -colorspace gray \
  +level-colors '#3a1e00','#fff0a0' $A/pets/long_vuong.png

# Ông Lão Câu Cá: ông lão (unique/joseph) cầm cần câu tre vẽ thêm
convert "$SRC/mon/unique/joseph.png" -stroke '#8a6a2a' -strokewidth 1 -draw 'line 22,17 30,3' \
  -stroke '#d8d8d8' -draw 'line 30,3 31,12' $A/npcs/fisher.png

# Vực Rồng: nước sâu (dngn/water/deep_water) tối hơn
convert "$SRC/dngn/water/deep_water.png" -modulate 70,140,100 $T/deep_water.png

# cây đước mọc giữa nước, tượng rồng vàng
convert $water "$SRC/dngn/trees/mangrove1.png" -composite $T/mangrove.png
convert "$SRC/dngn/statues/statue_dragon.png" -channel RGB -colorspace gray \
  +level-colors '#3a2400','#ffe58a' $T/dragon_statue.png
# đèn lồng đỏ treo trên cột gỗ (tự vẽ)
convert -size 32x32 xc:none \
  -fill '#4a3014' -draw 'rectangle 14,8 17,31' -draw 'rectangle 10,29 21,31' -draw 'rectangle 17,8 24,9' \
  -fill '#3a2610' -draw 'line 23,9 23,11' \
  -fill '#b01818' -draw 'ellipse 23,17 5,6 0,360' \
  -fill '#e83a2a' -draw 'ellipse 23,17 3,5 0,360' \
  -fill '#ffd060' -draw 'rectangle 20,11 26,12' -draw 'rectangle 20,22 26,23' -draw 'line 23,24 23,27' \
  -fill '#ffe9a0' -draw 'point 22,16' \
  $T/lantern.png

# bến / cầu gỗ (tự vẽ): ván ngang trên nước, đi theo hướng bắc – nam; pier_h là bản xoay ngang
convert $water \
  -fill '#5a3a18' -draw 'rectangle 5,0 26,31' \
  -fill '#9a6a34' -draw 'rectangle 6,0 25,6' -draw 'rectangle 6,8 25,14' \
  -draw 'rectangle 6,16 25,22' -draw 'rectangle 6,24 25,30' \
  -fill '#b88448' -draw 'rectangle 6,0 25,1' -draw 'rectangle 6,8 25,9' \
  -draw 'rectangle 6,16 25,17' -draw 'rectangle 6,24 25,25' \
  -fill '#3a2610' -draw 'point 8,3' -draw 'point 23,3' -draw 'point 8,11' -draw 'point 23,11' \
  -draw 'point 8,19' -draw 'point 23,19' -draw 'point 8,27' -draw 'point 23,27' \
  -fill '#3d2810' -draw 'rectangle 3,2 5,6' -draw 'rectangle 26,2 28,6' \
  -draw 'rectangle 3,22 5,26' -draw 'rectangle 26,22 28,26' \
  $T/pier_v.png
convert $T/pier_v.png -rotate 90 $T/pier_h.png

# thuyền gỗ nhìn từ trên (tự vẽ), neo trên nước
convert $water \
  -fill '#3d2810' -draw 'polygon 16,2 24,9 25,22 16,30 7,22 8,9' \
  -fill '#8a5a2a' -draw 'polygon 16,4 22,10 23,21 16,28 9,21 10,10' \
  -fill '#a87444' -draw 'polygon 16,7 20,11 21,20 16,25 11,20 12,11' \
  -fill '#5a3a18' -draw 'rectangle 10,12 22,13' -draw 'rectangle 10,19 22,20' \
  -fill '#c8a060' -draw 'line 4,28 12,22' \
  $T/boat.png

# lá sen + hoa sen trên nước (tự vẽ)
convert $water \
  -fill '#2f7a34' -draw 'circle 9,10 9,4' -draw 'circle 22,21 22,14' -draw 'circle 8,25 8,21' \
  -fill '#1f5a24' -draw 'polygon 9,10 15,8 15,12' -draw 'polygon 22,21 29,19 29,23' \
  -fill '#f2a0c0' -draw 'circle 22,20 22,17' -fill '#fff0f6' -draw 'circle 22,20 22,19' \
  -fill '#f6c' -draw 'point 9,9' \
  $T/lotus.png


# Mồi Rồng: hũ sành đựng mồi, ánh vàng (tự vẽ)
convert -size 32x32 xc:none \
  -fill '#ffd86a40' -draw 'circle 16,18 16,4' \
  -fill '#5a3418' -draw 'ellipse 16,20 10,9 0,360' \
  -fill '#9a5a2a' -draw 'ellipse 16,20 8,7 0,360' \
  -fill '#5a3418' -draw 'rectangle 10,9 22,12' \
  -fill '#c87a3a' -draw 'rectangle 11,10 21,11' \
  -fill '#e0442a' -draw 'line 14,9 13,5' -draw 'line 13,5 16,3' -draw 'line 18,9 20,6' \
  -fill '#ffd860' -draw 'rectangle 10,19 22,20' \
  -fill '#3a2010' -draw 'ellipse 16,28 7,1 0,360' \
  $A/items/dragon_bait.png

echo "Xong: long_vuong, fisher, deep_water, mangrove, dragon_statue, lantern, pier_v, pier_h, boat, lotus, dragon_bait"
