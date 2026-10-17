// Phase 7 (B-33): hình quần trong bộ hình Pixel lấy từ hình chân nhân vật (Dungeon Crawl `player/legs`, CC0) nên
// nằm ở nửa dưới ô 32×32. Cắt sát phần có hình rồi phóng (số nguyên lần, giữ điểm ảnh sắc) vào giữa ô.
// Chạy sau scripts/pixel_icons.py:  node e2e/crop_icons.mjs  (cần Chromium của Playwright)
import { launch } from './lib.mjs';
import fs from 'node:fs';

const DIR = new URL('../priv/static/assets/pixel/', import.meta.url).pathname;
const files = fs.readdirSync(DIR).filter((f) => f.startsWith('player_legs_'));
const browser = await launch();
const page = await browser.newPage();
for (const f of files) {
  const data = 'data:image/png;base64,' + fs.readFileSync(DIR + f).toString('base64');
  const out = await page.evaluate(async (data) => {
    const im = new Image();
    im.src = data;
    await im.decode();
    const c = document.createElement('canvas');
    c.width = im.width; c.height = im.height;
    const ctx = c.getContext('2d');
    ctx.drawImage(im, 0, 0);
    const px = ctx.getImageData(0, 0, c.width, c.height).data;
    let x0 = c.width, y0 = c.height, x1 = -1, y1 = -1;
    for (let y = 0; y < c.height; y++) for (let x = 0; x < c.width; x++) {
      if (px[(y * c.width + x) * 4 + 3] > 0) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    }
    if (x1 < 0) return null;
    const w = x1 - x0 + 1, h = y1 - y0 + 1;
    const k = Math.max(1, Math.floor(Math.min(28 / w, 28 / h)));
    const o = document.createElement('canvas');
    o.width = 32; o.height = 32;
    const octx = o.getContext('2d');
    octx.imageSmoothingEnabled = false;
    octx.drawImage(c, x0, y0, w, h, Math.round((32 - w * k) / 2), Math.round((32 - h * k) / 2), w * k, h * k);
    return o.toDataURL('image/png');
  }, data);
  if (out) fs.writeFileSync(DIR + f, Buffer.from(out.split(',')[1], 'base64'));
  console.log(f, out ? 'ok' : 'trống');
}
await browser.close();
