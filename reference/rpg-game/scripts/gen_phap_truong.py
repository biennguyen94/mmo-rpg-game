#!/usr/bin/env python3
"""Sinh bản đồ Pháp Trường Huyết Nguyệt (priv/maps/phap_truong.json), DECISIONS "Pháp Trường Huyết Nguyệt".

60 x 40 ô, không quái. Rừng tre bao quanh (style "arena": cây vẽ thành tre), sân đấu đất tròn ở giữa có vòng cột đá,
4 tượng rồng, đèn lồng; 4 miếu đổ nát ở 4 góc; suối cạn chéo bên trái có cầu gỗ; đá, cây khô, hoa rải rác.
Cổng về Làng ở mép dưới. Ngẫu nhiên có seed cố định (chạy lại ra đúng bản đồ cũ); kiểm mọi ô đi được nối với cổng.

Chạy: python3 scripts/gen_phap_truong.py
"""
import json
import math
import random
from collections import deque
from pathlib import Path

W, H = 60, 40
CX, CY = 30, 19
random.seed(20261113)
g = [["," for _ in range(W)] for _ in range(H)]


def put(x, y, c):
    if 0 <= x < W and 0 <= y < H:
        g[y][x] = c


# nền: cỏ, lốm đốm nền trơn
for y in range(H):
    for x in range(W):
        if random.random() < 0.35:
            g[y][x] = "."

# rừng tre bao quanh, mép trong lồi lõm
for y in range(H):
    for x in range(W):
        d = min(x, y, W - 1 - x, H - 1 - y)
        if d < 2 or (d == 2 and random.random() < 0.55) or (d == 3 and random.random() < 0.18):
            g[y][x] = "T" if random.random() < 0.8 else "Y"

# suối cạn chéo bên trái (từ trên xuống), cầu gỗ ở chỗ đường đi qua
stream = []
x = 13.0
for y in range(2, H - 2):
    x += random.choice([-0.6, 0, 0.4, 0.7])
    xi = int(x)
    stream.append((xi, y))
    put(xi, y, "~")
    put(xi + 1, y, "~")

# sân đấu tròn: đất, vòng cột đá có khe, 4 tượng rồng ở 4 góc chéo, đèn lồng
R = 9
for y in range(H):
    for x in range(W):
        d = math.hypot((x - CX) * 0.85, y - CY)
        if d <= R:
            g[y][x] = ":"
        elif d <= R + 1.1:
            a = math.degrees(math.atan2(y - CY, (x - CX) * 0.85)) % 360
            # khe vào ở 4 hướng chính, còn lại cột cách quãng
            if min(abs(a - k) for k in (0, 90, 180, 270, 360)) > 14 and (x + y) % 3 == 0:
                g[y][x] = "I"
            else:
                g[y][x] = ":"
for dx, dy in ((-6, -5), (6, -5), (-6, 5), (6, 5)):
    put(CX + dx, CY + dy, "G")
for dx, dy in ((-3, -7), (3, -7), (-3, 7), (3, 7), (-9, -1), (-9, 1), (9, -1), (9, 1)):
    put(CX + dx, CY + dy, "J")
# đài giữa sân: một cột đá cổ (đứng quanh được)
put(CX, CY, "I")


# miếu đổ nát ở 4 góc: tường gạch thiếu mảng, cửa mở, đèn lồng trước cửa, bên trong nền đất
def shrine(x0, y0, door_bottom):
    for y in range(y0, y0 + 5):
        for x in range(x0, x0 + 7):
            edge = y in (y0, y0 + 4) or x in (x0, x0 + 6)
            if edge:
                g[y][x] = "#" if random.random() > 0.18 else "R"
            else:
                g[y][x] = ":"
    dy = y0 + 4 if door_bottom else y0
    g[dy][x0 + 3] = "D"
    oy = dy + 1 if door_bottom else dy - 1
    put(x0 + 2, oy, "J")
    put(x0 + 4, oy, "J")
    put(x0 + 3, y0 + 2, "G")


shrine(5, 4, True)
shrine(48, 4, True)
shrine(5, 30, False)
shrine(48, 30, False)


# đường đất: cổng → sân, sân → 4 miếu (đi vòng, chỗ qua suối là cầu gỗ)
def path(a, b):
    (x, y), (tx, ty) = a, b
    while (x, y) != (tx, ty):
        if x != tx and (y == ty or random.random() < 0.5):
            x += 1 if tx > x else -1
        else:
            y += 1 if ty > y else -1
        c = g[y][x]
        if c == "~":
            g[y][x] = "E"
        elif c in ",.TYRK*":
            g[y][x] = ":"


ENTRY = (30, H - 1)
path((30, H - 2), (CX, CY + R))
path((CX - R, CY), (8, 9))
path((CX + R, CY), (51, 9))
path((CX - 4, CY + R - 1), (8, 29))
path((CX + 4, CY + R - 1), (51, 29))
path((CX, CY - R), (CX, 4))

# đá, cây khô, hoa, đèn lồng rải rác (không chắn đường)
for _ in range(70):
    x, y = random.randrange(3, W - 3), random.randrange(3, H - 3)
    if g[y][x] in ",.":
        g[y][x] = random.choice("RRKK**,")
for _ in range(14):
    x, y = random.randrange(4, W - 4), random.randrange(4, H - 4)
    if g[y][x] in ",." and math.hypot((x - CX) * 0.85, y - CY) > R + 3:
        g[y][x] = "J"

# cổng về Làng ở mép dưới, chỗ đứng ngay trên
put(*ENTRY, "O")
put(30, H - 2, ":")
put(30, H - 3, ":")
# NPC đứng cạnh lối vào (ô đi được để không chặn bản đồ; NPC chặn đường lúc chơi nên để lệch lối đi)
NPCS = [
    {"id": "executioner", "name": "Quan Giám Trảm", "sprite": "elder", "at": [27, 35], "role": "blood_moon",
     "lines": ["Đêm trăng máu, Pháp Trường mở cửa. Ai hạ được nhiều người nhất được ban ngọc quý.",
               "Gục ở đây không mất vàng, không bị tên đỏ, nhưng phải về Làng nghỉ một lúc mới vào lại được."]},
    {"id": "blood_board", "name": "Bảng Huyết Nguyệt", "sprite": "board", "at": [33, 35], "role": "blood_moon",
     "lines": ["Bảng ghi những người hạ được nhiều mạng nhất đêm trăng máu."]},
]
for n in NPCS:
    x, y = n["at"]
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if g[y + dy][x + dx] in "TYRKJIG#~":
                g[y + dy][x + dx] = ","

WALK = set(".,:*DAOE")
tiles = ["".join(r) for r in g]


# mọi ô đi được nối với cổng (không có chỗ kẹt)
def check():
    seen, q = {ENTRY}, deque([ENTRY])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if 0 <= n[0] < W and 0 <= n[1] < H and n not in seen and tiles[n[1]][n[0]] in WALK:
                seen.add(n)
                q.append(n)
    walk = {(x, y) for y in range(H) for x in range(W) if tiles[y][x] in WALK}
    return walk - seen


# ô đi được bị cô lập: lấp thành cỏ cây (không phải chỗ đứng)
lost = check()
for x, y in lost:
    g[y][x] = "T"
tiles = ["".join(r) for r in g]
assert not check()
for n in NPCS:
    assert tiles[n["at"][1]][n["at"][0]] in WALK

m = {
    "id": "phap_truong",
    "name": "Pháp Trường",
    "zone": None,
    "floor": "tiles/grass",
    "min_level": 10,
    "style": "arena",
    "_doc": "DECISIONS \"Pháp Trường Huyết Nguyệt\": không quái, vùng an toàn; lúc sự kiện Huyết Nguyệt mở (HacLong.BloodMoon) "
    "thì đồ sát tự do. Sinh bằng scripts/gen_phap_truong.py.",
    "portals": [{"at": list(ENTRY), "to": "village", "spawn": [12, 15]}],
    "spawns": [],
    "npcs": NPCS,
    "sourceType": "DESIGN",
    "version": 1,
    "verified": False,
    "tiles": tiles,
}
out = Path(__file__).resolve().parent.parent / "priv/maps/phap_truong.json"
out.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n")
print(f"{out}: {W}x{H}, {sum(r.count(c) for r in tiles for c in WALK)} ô đi được")
for r in tiles:
    print(r)
