// Icon ứng dụng (ô tắt trình duyệt, màn hình chính điện thoại, tab): hình trùm Hắc Long (`monsters/shadow_dragon.png`,
// CC0, xem CREDITS.md) phóng to kiểu pixel trên nền tối viền vàng. Ghi vào `priv/static/app/` và `priv/static/favicon.ico`.
// Chạy: node e2e/app_icons.mjs  (cần Chromium của Playwright)
import { launch } from './lib.mjs';
import fs from 'node:fs';

const STATIC = new URL('../priv/static/', import.meta.url).pathname;
const dragon = 'data:image/png;base64,' + fs.readFileSync(STATIC + 'assets/monsters/shadow_dragon.png').toString('base64');
// [tệp, cỡ, bo góc (phần cạnh), rồng chiếm (phần cạnh)]; maskable: Android tự cắt hình, rồng nằm trong vùng an toàn 80%
const JOBS = [
  ['app/icon-512.png', 512, 0.22, 0.78],
  ['app/icon-192.png', 192, 0.22, 0.78],
  ['app/icon-maskable-512.png', 512, 0, 0.6],
  ['app/apple-touch-icon.png', 180, 0, 0.74],
  ['app/favicon-32.png', 32, 0.18, 0.94],
  ['favicon.ico', 64, 0.18, 0.9],
];

const browser = await launch();
const page = await browser.newPage();
for (const [file, size, radius, scale] of JOBS) {
  const out = await page.evaluate(async ([dragon, size, radius, scale]) => {
    const im = new Image();
    im.src = dragon;
    await im.decode();
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const g = c.getContext('2d');
    const r = size * radius;
    g.beginPath();
    g.roundRect(0, 0, size, size, r);
    g.clip();
    const bg = g.createRadialGradient(size / 2, size * 0.45, size * 0.05, size / 2, size / 2, size * 0.75);
    bg.addColorStop(0, '#5a2346');
    bg.addColorStop(0.55, '#24162e');
    bg.addColorStop(1, '#0d0a12');
    g.fillStyle = bg;
    g.fillRect(0, 0, size, size);
    if (size >= 64) {
      g.lineWidth = Math.max(2, size * 0.025);
      g.strokeStyle = '#c9a24a';
      const i = g.lineWidth / 2 + (radius ? 0 : size * 0.04);
      g.beginPath();
      g.roundRect(i, i, size - 2 * i, size - 2 * i, Math.max(0, r - i));
      g.stroke();
    }
    // phóng nguyên lần (pixel sắc nét)
    const k = Math.max(1, Math.floor((size * scale) / im.width));
    const w = im.width * k, x = Math.round((size - w) / 2), y = Math.round((size - w) / 2);
    g.imageSmoothingEnabled = false;
    g.shadowColor = 'rgba(255, 70, 90, 0.55)';
    g.shadowBlur = size * 0.06;
    g.drawImage(im, x, y, w, w);
    return c.toDataURL('image/png');
  }, [dragon, size, radius, scale]);
  fs.mkdirSync(STATIC + 'app', { recursive: true });
  fs.writeFileSync(STATIC + file, Buffer.from(out.split(',')[1], 'base64'));
  console.log('ghi', file);
}
await browser.close();
