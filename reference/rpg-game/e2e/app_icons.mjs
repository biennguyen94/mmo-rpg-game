// Icon ứng dụng (ô tắt trình duyệt, màn hình chính điện thoại, tab): `priv/static/app/logo.svg` (khung viền vàng tự vẽ +
// đầu Hắc Long vẽ tay của Cethiel, CC0; xem CREDITS.md). Ghi vào `priv/static/app/` và `priv/static/favicon.ico`.
// Chạy: node e2e/app_icons.mjs  (cần Chromium của Playwright)
import { launch } from './lib.mjs';
import fs from 'node:fs';

const STATIC = new URL('../priv/static/', import.meta.url).pathname;
// logo vector tự vẽ (`priv/static/app/logo.svg`, CC0): nét ở mọi cỡ (trước dùng hình rồng pixel 32×32 phóng to nên vỡ hạt)
const svg = fs.readFileSync(STATIC + 'app/logo.svg', 'utf8');
// bản không nền cho icon maskable (vẽ thu nhỏ đè lên nền kín): khỏi lộ ô vuông nền của phần thu nhỏ
const svgBare = svg.replace(/<rect width="512" height="512" fill="url\(#bg\)"\/>/, '');
// [tệp, cỡ, hình chiếm (phần cạnh)]: maskable — Android cắt hình, phần vẽ thu vào vùng an toàn 80%, nền vẫn kín.
const JOBS = [
  ['app/icon-512.png', 512, 1],
  ['app/icon-192.png', 192, 1],
  ['app/icon-maskable-512.png', 512, 0.78],
  ['app/apple-touch-icon.png', 180, 1],
  ['app/favicon-32.png', 32, 1],
];
// favicon.ico thật (nhiều cỡ, mỗi cỡ một ảnh PNG bên trong)
const ICO = [16, 32, 48];

const browser = await launch();
const page = await browser.newPage();
async function render(size, scale) {
  const out = await page.evaluate(async ([svg, bare, size, scale]) => {
    const load = async (src) => { const im = new Image(); im.src = src; await im.decode(); return im; };
    const im = await load('data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg));
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const g = c.getContext('2d');
    g.imageSmoothingQuality = 'high';
    // nền kín cả ô (vẽ hình cỡ đầy đủ rồi phủ phần đã thu nhỏ lên trên)
    g.drawImage(im, 0, 0, size, size);
    if (scale < 1) {
      // nền như logo (tâm đỏ tím, mép gần đen), không lộ ô vuông của phần thu nhỏ
      const bg = g.createRadialGradient(size / 2, size * 0.4, 0, size / 2, size / 2, size * 0.75);
      bg.addColorStop(0, '#3a1420');
      bg.addColorStop(0.6, '#1b0f1d');
      bg.addColorStop(1, '#0c0810');
      g.fillStyle = bg;
      g.fillRect(0, 0, size, size);
      const w = size * scale, o = (size - w) / 2;
      const small = await load('data:image/svg+xml;charset=utf-8,' + encodeURIComponent(bare));
      g.drawImage(small, o, o, w, w);
    }
    return c.toDataURL('image/png');
  }, [svg, svgBare, size, scale]);
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
