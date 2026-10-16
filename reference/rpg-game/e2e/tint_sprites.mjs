// B-20: hình quái xâm lăng tô lại màu từ hình CC0 có sẵn (cùng nguồn `priv/static/assets/monsters/`, xem CREDITS.md).
// Chạy: node e2e/tint_sprites.mjs  (cần Chromium của Playwright)
import { launch } from './lib.mjs';
import fs from 'node:fs';

const DIR = new URL('../priv/static/assets/', import.meta.url).pathname;
const JOBS = [
  // [nguồn, đích, bộ lọc canvas]
  ['monsters/golden_dragon', 'monsters/red_dragon', 'hue-rotate(-40deg) saturate(1.6) brightness(0.9)'],
  ['monsters/ancient_lich', 'monsters/white_wizard', 'grayscale(1) invert(0.9) brightness(1.05)'],
  ['monsters/orc_warrior', 'monsters/orc_soldier', 'hue-rotate(160deg) saturate(1.2)'],
  // Quặng Mithril: quặng sắt tô bạc-xanh (hình cũ giống quả cầu pha lê)
  // Đài Phúc Lành (Phase 2): đá dịch chuyển tô vàng ấm
  ['tiles/waystone', 'tiles/blessing', 'sepia(1) saturate(3) hue-rotate(-10deg) brightness(1.25)'],
  ['nodes/ore', 'nodes/ore_rare', 'grayscale(0.6) sepia(0.3) hue-rotate(170deg) saturate(2.2) brightness(1.25)'],
];

const browser = await launch();
const page = await browser.newPage();
const only = process.argv[2];
for (const [src, dst, filter] of JOBS.filter((j) => !only || j[1].includes(only))) {
  const data = 'data:image/png;base64,' + fs.readFileSync(DIR + src + '.png').toString('base64');
  const out = await page.evaluate(async ([data, filter]) => {
    const im = new Image();
    im.src = data;
    await im.decode();
    const c = document.createElement('canvas');
    c.width = im.width; c.height = im.height;
    const ctx = c.getContext('2d');
    ctx.filter = filter;
    ctx.drawImage(im, 0, 0);
    return c.toDataURL('image/png');
  }, [data, filter]);
  fs.writeFileSync(DIR + dst + '.png', Buffer.from(out.split(',')[1], 'base64'));
  console.log(`${src} → ${dst}`);
}
await browser.close();
