"""Hình cho Đồi Sáo Diều, Chim Lạc, Hắc Long (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long"). Nguồn ghi ở CREDITS.md.

Chạy: python3 scripts/sky_assets.py <thư_mục_nguồn> <thư_mục_icon_64>
  thư mục nguồn có (tải từ OpenGameArt, CC0):
    Phoenix_SpriteSheet_0.png  (Chasersgaming, "Phoenix (reborn)")
    birds.32x32.png            (MoikMellah, "Animated Birds (32x32)")
    Clouds_4.png               (Igor Gundarev, "Clouds")
    clouds512_1.png            (Sam, "Cloud Set")
    dracheneier.png            (MELLE, "Dragon Eggs")
  thư mục icon 64: kết quả của scripts/sky_svg_icons.cjs (game-icons.net, CC BY 3.0)
Ghi vào priv/static/assets/ (pets/, items/, sky/, tiles/, npcs/).
"""
import colorsys
import os
import random
import sys

from PIL import Image, ImageEnhance, ImageFilter

SRC, ICONS = sys.argv[1], sys.argv[2]
A = os.path.join(os.path.dirname(__file__), "..", "priv", "static", "assets")


def out(rel):
    p = os.path.join(A, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def tint(im, hue, sat=0.75, light=1.0, spread=1.0):
    """Đổi sắc độ (giữ độ sáng từng điểm, `spread` > 1 giãn sáng tối): Chim Lạc màu đồng thau như trên trống đồng."""
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            # đỏ (bóng) tối hơn, vàng (sáng) sáng hơn: giữ khối lông khi đổi về một sắc
            l = l + (h - 0.08) * 1.6 if h < 0.25 else l
            l = max(0.0, min(1.0, (l - 0.5) * spread + 0.5))
            r2, g2, b2 = colorsys.hls_to_rgb(hue, min(1, l * light), sat * (0.4 + 0.6 * s))
            px[x, y] = (round(r2 * 255), round(g2 * 255), round(b2 * 255), a)
    return im


def bbox_crop(im, pad=1):
    bb = im.getbbox()
    if not bb:
        return im
    x0, y0, x1, y1 = bb
    return im.crop((max(0, x0 - pad), max(0, y0 - pad), min(im.size[0], x1 + pad), min(im.size[1], y1 + pad)))


def fit(im, size):
    """Thu vừa ô vuông `size` (giữ tỉ lệ, căn giữa, đáy sát dưới)."""
    im = bbox_crop(im)
    k = min(size / im.size[0], size / im.size[1])
    im = im.resize((max(1, round(im.size[0] * k)), max(1, round(im.size[1] * k))), Image.LANCZOS)
    c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c.paste(im, ((size - im.size[0]) // 2, (size - im.size[1]) // 2), im)
    return c


# ---------- Chim Lạc: 6 khung bay của phượng hoàng, tô đồng thau ----------
ph = Image.open(os.path.join(SRC, "Phoenix_SpriteSheet_0.png")).convert("RGBA")
fw = ph.size[0] // 10
# bỏ 1 điểm viền mỗi khung (tấm sprite có đường lưới xám giữa các khung)
frames = [ph.crop((i * fw + 1, 1, (i + 1) * fw - 1, fw - 1)) for i in range(6)]
frames = [tint(f, 0.11, 0.75, 1.25, 1.5) for f in frames]
# cùng một tỉ lệ cho mọi khung (không nhảy hình), phóng kiểu pixel ×2
strip = Image.new("RGBA", (64 * 6, 64), (0, 0, 0, 0))
for i, f in enumerate(frames):
    big = f.resize((f.size[0] * 2, f.size[1] * 2), Image.NEAREST)
    strip.paste(big, (i * 64 + (64 - big.size[0]) // 2, (64 - big.size[1]) // 2), big)
strip.save(out("sky/chim_lac.png"))
fit(frames[2], 32).save(out("pets/chim_lac.png"))

# ---------- Đàn Hạc: hàng chim trắng (nền hồng → trong suốt) ----------
bd = Image.open(os.path.join(SRC, "birds.32x32.png")).convert("RGBA")
px = bd.load()
for y in range(bd.size[1]):
    for x in range(bd.size[0]):
        r, g, b, a = px[x, y]
        if r > 200 and g < 60 and b > 200:
            px[x, y] = (0, 0, 0, 0)
hac = Image.new("RGBA", (32 * 6, 32), (0, 0, 0, 0))
for i in range(6):
    hac.paste(bd.crop((i * 32, 0, i * 32 + 32, 32)), (i * 32, 0))
hac.save(out("sky/hac.png"))

# ---------- Mây trôi: tách 5 đám mây ----------
cl = Image.open(os.path.join(SRC, "Clouds_4.png")).convert("RGBA")
cl.save(out("sky/clouds.png"))

# ---------- Mây mềm (Sam, "Cloud Set", CC0): bỏ nền xanh → trong suốt, tách từng đám ----------
cs = Image.open(os.path.join(SRC, "clouds512_1.png")).convert("RGBA")
BG = (129, 201, 249)
px = cs.load()
W, H = cs.size
for y in range(H):
    for x in range(W):
        r, g, b, _ = px[x, y]
        a = max(0.0, min(1.0, (r - BG[0]) / (255 - BG[0])))
        if a < 0.02:
            px[x, y] = (0, 0, 0, 0)
            continue
        # bỏ phần màu nền đã trộn vào (giữ bóng xám xanh nhẹ dưới đáy mây)
        c = [max(0, min(255, round((v - bg * (1 - a)) / a))) for v, bg in zip((r, g, b), BG)]
        px[x, y] = (c[0], c[1], c[2], round(a * 255))
# tách các đám theo hàng / cột trống
mask = [[px[x, y][3] > 8 for x in range(W)] for y in range(H)]
seen = [[False] * W for _ in range(H)]
boxes = []
for y in range(H):
    for x in range(W):
        if mask[y][x] and not seen[y][x]:
            st = [(x, y)]; seen[y][x] = True; x0 = x1 = x; y0 = y1 = y; n = 0
            while st:
                cx, cy = st.pop(); n += 1
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < W and 0 <= ny < H and mask[ny][nx] and not seen[ny][nx]:
                        seen[ny][nx] = True; st.append((nx, ny))
            if n > 400:
                boxes.append((x0, y0, x1 + 1, y1 + 1))
boxes.sort(key=lambda b: -(b[2] - b[0]) * (b[3] - b[1]))
for i, bx in enumerate(boxes[:6]):
    cs.crop((max(0, bx[0] - 2), max(0, bx[1] - 2), min(W, bx[2] + 2), min(H, bx[3] + 2))).save(out(f"sky/cloud{i + 1}.png"))
print("mây mềm:", len(boxes[:6]))

# ---------- Ô trời: xanh nhạt, vài vệt sáng (tự vẽ, CC0) ----------
rnd = random.Random(7)
sky = Image.new("RGBA", (32, 32))
for y in range(32):
    for x in range(32):
        t = y / 31
        base = (int(126 + 30 * t), int(186 + 20 * t), int(236 + 8 * t))
        n = rnd.randint(-4, 4)
        sky.putpixel((x, y), (base[0] + n, base[1] + n, min(255, base[2] + n), 255))
for _ in range(3):
    x0, y0, w = rnd.randint(0, 24), rnd.randint(4, 28), rnd.randint(5, 9)
    for x in range(x0, min(32, x0 + w)):
        r, g, b, a = sky.getpixel((x, y0))
        sky.putpixel((x, y0), (min(255, r + 22), min(255, g + 18), min(255, b + 10), 255))
sky.save(out("tiles/sky.png"))

# ---------- Bọc Trăm Trứng: quả trứng đen vân dung nham ----------
eggs = Image.open(os.path.join(SRC, "dracheneier.png")).convert("RGBA")
w3, h3 = eggs.size[0] // 3, eggs.size[1] // 3
egg = bbox_crop(eggs.crop((0, 0, w3, h3)))
fit(egg, 32).save(out("items/boc_tram_trung.png"))
fit(egg, 128).save(out("sky/egg.png"))

# ---------- Hắc Long (thú): đầu hoạt cảnh Hắc Long ở màn đăng nhập (Cethiel, CC0) ----------
hl = Image.open(os.path.join(A, "art", "hac_long.webp")).convert("RGBA")
fit(hl, 32).save(out("pets/hac_long.png"))
fit(hl, 96).save(out("sky/hac_long.png"))
# Chân Thân: ánh tím vàng quanh viền
glow = fit(hl, 96)
halo = glow.split()[3].filter(ImageFilter.GaussianBlur(4))
aura = Image.new("RGBA", glow.size, (190, 120, 255, 0))
aura.putalpha(halo.point(lambda v: min(255, v * 2)))
chan = Image.alpha_composite(aura, glow)
chan = ImageEnhance.Contrast(chan).enhance(1.15)
chan.save(out("sky/hac_long_chan.png"))
fit(chan, 32).save(out("pets/hac_long_chan.png"))

# ---------- Icon vật phẩm 32×32 ----------
for name in ["long_hac", "manh_may", "day_dieu_dut", "manh_sao", "sao_dong"]:
    im = Image.open(os.path.join(ICONS, f"{name}@64.png")).convert("RGBA")
    im.resize((32, 32), Image.LANCZOS).save(out(f"items/{name}.png"))

# ---------- NPC Ông Lão Làm Diều: người dân CC0 của Làng (npcs/elder) tô áo nâu ----------
el = Image.open(os.path.join(A, "npcs", "elder.png")).convert("RGBA")
tint(el, 0.08, 0.45, 1.05).save(out("npcs/kite_maker.png"))
print("xong")
