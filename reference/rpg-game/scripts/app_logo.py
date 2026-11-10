#!/usr/bin/env python3
"""Dựng logo Hắc Long (priv/static/app/logo.svg) từ đầu rồng vẽ chì "Dragon Portrait" của MetaShinryu
(OpenGameArt, CC-BY 3.0; CREDITS.md): tô lại tông đen thép, mắt đỏ rực, đặt to tràn khung trên nền đỏ thẫm, không viền.
Xuất PNG / favicon sau đó: node e2e/app_icons.mjs
Chạy: python3 scripts/app_logo.py [--png thử.png]
"""
import base64, io, os, sys
from PIL import Image, ImageChops, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'assets_src/app/dragon_portrait_metashinryu.png')
OUT = os.path.join(ROOT, 'priv/static/app/logo.svg')
S = 512
# bảng màu theo độ sáng nét chì: tối → đen tím, giữa → xám thép, sáng → ánh bạc
STOPS = [(0.0, (3, 3, 5)), (0.45, (12, 11, 15)), (0.72, (36, 33, 40)), (0.9, (92, 86, 96)), (1.0, (170, 162, 172))]
EYE = (0.369, 0.372)   # tâm mắt (phần bề rộng / chiều cao ảnh gốc đã cắt sát)
EYE_R = 0.045          # bán kính quầng mắt (phần bề rộng)


def ramp(v):
    for (a, ca), (b, cb) in zip(STOPS, STOPS[1:]):
        if v <= b:
            t = (v - a) / (b - a)
            return tuple(round(x + (y - x) * t) for x, y in zip(ca, cb))
    return STOPS[-1][1]


def head():
    im = Image.open(SRC).convert('RGBA')
    im = im.crop(im.getchannel('A').getbbox())
    lut = [ramp(i / 255) for i in range(256)]
    g = im.convert('L')
    rgb = Image.merge('RGB', [g.point([c[k] for c in lut]) for k in range(3)])
    # mắt: quầng đỏ cam cộng sáng, đậm ở giữa
    w, h = im.size
    cx, cy, r = EYE[0] * w, EYE[1] * h, EYE_R * w
    glow = Image.new('RGB', im.size, (0, 0, 0))
    m = Image.new('L', im.size, 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(m)
    for i in range(40, 0, -1):
        d.ellipse([cx - r * i / 40 * 1.5, cy - r * i / 40, cx + r * i / 40 * 1.5, cy + r * i / 40], fill=int(255 * (1 - i / 40) ** 0.6))
    m = m.filter(ImageFilter.GaussianBlur(r * 0.25))
    hot = Image.new('RGB', im.size, (255, 70, 20))
    glow = Image.composite(hot, glow, m)
    core = m.point(lambda v: max(0, v - 150) * 2)
    glow = Image.composite(Image.new('RGB', im.size, (255, 230, 120)), glow, core)
    # chỉ sáng ở phần tối của mắt (con ngươi giữ nét)
    rgb = ImageChops.add(rgb, ImageChops.multiply(glow, Image.merge('RGB', [g.point(lambda v: 255 - v // 2)] * 3)))
    out = rgb.convert('RGBA')
    out.putalpha(im.getchannel('A'))
    return out


def compose():
    h = head()
    # đầu rồng cao 1,12 khung: cắt phần cổ dưới đáy, mõm sát mép trái
    sc = S * 1.12 / h.height
    h = h.resize((round(h.width * sc), round(h.height * sc)), Image.LANCZOS)
    return h, (S - h.width + 18, -6)


def svg(h, pos):
    buf = io.BytesIO()
    h.save(buf, 'WEBP', quality=88)
    data = base64.b64encode(buf.getvalue()).decode()
    return f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 {S} {S}">
  <!-- Logo Hắc Long RPG: đầu rồng "Dragon Portrait" của MetaShinryu (OpenGameArt, CC-BY 3.0; tô lại, CREDITS.md) trên nền tự vẽ. Dựng: python3 scripts/app_logo.py; xuất PNG / favicon: node e2e/app_icons.mjs -->
  <defs>
    <radialGradient id="bg" cx="62%" cy="38%" r="80%">
      <stop offset="0" stop-color="#7a1624"/><stop offset="0.45" stop-color="#3a0c16"/><stop offset="1" stop-color="#0a0508"/>
    </radialGradient>
    <radialGradient id="glow" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#ff4a2a" stop-opacity="0.55"/><stop offset="1" stop-color="#ff4a2a" stop-opacity="0"/></radialGradient>
    <filter id="rim" x="-10%" y="-10%" width="120%" height="120%"><feDropShadow dx="0" dy="0" stdDeviation="5" flood-color="#ff3b2a" flood-opacity="0.55"/></filter>
  </defs>
  <rect width="{S}" height="{S}" fill="url(#bg)"/>
  <circle cx="{round(pos[0] + h.width * EYE[0])}" cy="{round(pos[1] + h.height * EYE[1])}" r="150" fill="url(#glow)"/>
  <image filter="url(#rim)" x="{pos[0]}" y="{pos[1]}" width="{h.width}" height="{h.height}" xlink:href="data:image/webp;base64,{data}"/>
</svg>
'''


if __name__ == '__main__':
    h, pos = compose()
    if '--png' in sys.argv:
        bg = Image.new('RGB', (S, S), (40, 8, 14))
        bg.paste(h, pos, h)
        bg.save(sys.argv[sys.argv.index('--png') + 1])
    else:
        open(OUT, 'w').write(svg(h, pos))
        print('ghi', OUT, os.path.getsize(OUT), 'byte')
