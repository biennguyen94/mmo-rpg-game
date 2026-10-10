#!/usr/bin/env python3
# Chạy: python3 scripts/doll_weapons.py priv/static/assets/doll/hand1  (cần ImageMagick `convert`)
# Vẽ sprite vũ khí 32x32 (lớp hand1 của doll.js) bằng ImageMagick: cung, nỏ, gậy phép. Tự vẽ (Phase 15c).
import subprocess, sys
OUT = sys.argv[1]
K, W1, W2, W3, S, G1, G2, G3 = '#000000', '#5a3a1a', '#8b5a2b', '#b07a40', '#d8d8d8', '#2f6fd0', '#5fa8ff', '#e8f4ff'

def save(name, px):
    cmd = ['convert', '-size', '32x32', 'xc:none']
    for (x, y), c in px.items():
        cmd += ['-fill', c, '-draw', f'point {x},{y}']
    cmd.append(f'{OUT}/{name}.png')
    subprocess.run(cmd, check=True)

def outline(px):
    out = dict(px)
    for (x, y) in list(px):
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            q = (x+dx, y+dy)
            if q not in px and 0 <= q[0] < 32 and 0 <= q[1] < 32:
                out.setdefault(q, K)
    return out

# cung: thân cong (lồi sang trái), dây thẳng bên phải, tay cầm giữa
bow = {}
for y in range(2, 25):
    x = 3 + round(4 * ((y - 13) / 11) ** 2)
    bow[(x, y)] = W2
    bow[(x + 1, y)] = W3 if abs(y - 13) > 2 else W1
bow = outline(bow)
for y in range(3, 24):
    bow.setdefault((8, y), S)
save('bow', bow)

# nỏ: cánh cung dọc ở đầu (bên trái), báng ngang tới tay, dây
xb = {}
for x in range(2, 10):
    xb[(x, 13)] = W2
    xb[(x, 14)] = W1
for y in range(8, 20):
    xb[(2, y)] = W3 if y not in (13, 14) else W1
    if y in (8, 19):
        xb[(3, y)] = W2
xb = outline(xb)
for y in list(range(9, 13)) + list(range(15, 19)):
    xb[(5, y)] = S
save('crossbow', xb)

# gậy phép: cán dài, ngọc tròn trên đỉnh
st = {}
for y in range(6, 28):
    st[(5, y)] = W2
    st[(6, y)] = W3 if y % 5 else W1
for (x, y) in [(4,2),(5,1),(6,1),(7,2),(4,3),(7,3),(5,4),(6,4),(5,2),(6,2),(5,3),(6,3),(4,4),(7,4),(5,5),(6,5)]:
    st[(x, y)] = G1
st[(5, 2)] = G3; st[(6, 2)] = G2; st[(5, 3)] = G2
st = outline(st)
save('staff', st)
