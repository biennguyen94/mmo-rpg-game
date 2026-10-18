// Icon ứng dụng (ô tắt trình duyệt, màn hình chính điện thoại, tab): hình trùm Hắc Long (`monsters/shadow_dragon.png`,
// CC0, xem CREDITS.md) phóng to kiểu pixel trên nền trắng. Ghi vào `priv/static/app/` và `priv/static/favicon.ico`.
// Chạy: node e2e/app_icons.mjs  (cần Chromium của Playwright)
import { launch } from './lib.mjs';
import fs from 'node:fs';

const STATIC = new URL('../priv/static/', import.meta.url).pathname;
const dragon = 'data:image/png;base64,' + fs.readFileSync(STATIC + 'assets/monsters/shadow_dragon.png').toString('base64');
// [tệp, cỡ, rồng chiếm (phần cạnh)]: hình vuông kín nền (trình duyệt / máy tự bo góc, cắt tròn); maskable: Android cắt
// hình, rồng nằm trong vùng an toàn 80%. Cỡ dưới 32 thu nhỏ mượt, từ 32 phóng nguyên lần (pixel sắc nét).
const JOBS = [
  ['app/icon-512.png', 512, 0.96],
  ['app/icon-192.png', 192, 0.96],
  ['app/icon-maskable-512.png', 512, 0.62],
  ['app/apple-touch-icon.png', 180, 0.9],
  ['app/favicon-32.png', 32, 1],
];
// favicon.ico thật (nhiều cỡ, mỗi cỡ một ảnh PNG bên trong)
const ICO = [16, 32, 48];

const browser = await launch();
const page = await browser.newPage();
async function render(size, scale) {
  const out = await page.evaluate(async ([dragon, size, scale]) => {
    const im = new Image();
    im.src = dragon;
    await im.decode();
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const g = c.getContext('2d');
    const bg = g.createRadialGradient(size / 2, size * 0.45, size * 0.05, size / 2, size / 2, size * 0.7);
    bg.addColorStop(0, '#ffffff');
    bg.addColorStop(0.7, '#f7f4fa');
    bg.addColorStop(1, '#ebe5f0');
    g.fillStyle = bg;
    g.fillRect(0, 0, size, size);
    const k = size * scale >= im.width ? Math.floor((size * scale) / im.width) : (size * scale) / im.width;
    const w = Math.round(im.width * k), x = Math.round((size - w) / 2), y = Math.round((size - w) / 2 + size * 0.02);
    g.imageSmoothingEnabled = k < 1;
    g.shadowColor = 'rgba(40, 20, 50, 0.35)';
    g.shadowBlur = size * 0.03;
    g.drawImage(im, x, y, w, w);
    return c.toDataURL('image/png');
  }, [dragon, size, scale]);
  return Buffer.from(out.split(',')[1], 'base64');
}

fs.mkdirSync(STATIC + 'app', { recursive: true });
for (const [file, size, scale] of JOBS) {
  fs.writeFileSync(STATIC + file, await render(size, scale));
  console.log('ghi', file);
}

// ICO: đầu 6 byte, mỗi ảnh một mục 16 byte, rồi dữ liệu PNG
const pngs = [];
for (const size of ICO) pngs.push([size, await render(size, 1)]);
const head = Buffer.alloc(6 + 16 * pngs.length);
head.writeUInt16LE(0, 0);
head.writeUInt16LE(1, 2);
head.writeUInt16LE(pngs.length, 4);
let off = head.length;
pngs.forEach(([size, png], i) => {
  const e = 6 + 16 * i;
  head.writeUInt8(size % 256, e);
  head.writeUInt8(size % 256, e + 1);
  head.writeUInt16LE(1, e + 4);
  head.writeUInt16LE(32, e + 6);
  head.writeUInt32LE(png.length, e + 8);
  head.writeUInt32LE(off, e + 12);
  off += png.length;
});
fs.writeFileSync(STATIC + 'favicon.ico', Buffer.concat([head, ...pngs.map((p) => p[1])]));
console.log('ghi favicon.ico', ICO.join('/'));
await browser.close();
