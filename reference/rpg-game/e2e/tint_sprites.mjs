// B-20: hình quái xâm lăng tô lại màu từ hình CC0 có sẵn (cùng nguồn `priv/static/assets/monsters/`, xem CREDITS.md).
// Chạy: node e2e/tint_sprites.mjs  (cần Chromium của Playwright)
import { launch } from './lib.mjs';
import fs from 'node:fs';

const DIR = new URL('../priv/static/assets/monsters/', import.meta.url).pathname;
const JOBS = [
  // [nguồn, đích, bộ lọc canvas]
  ['golden_dragon', 'red_dragon', 'hue-rotate(-40deg) saturate(1.6) brightness(0.9)'],
  ['ancient_lich', 'white_wizard', 'grayscale(1) invert(0.9) brightness(1.05)'],
  ['orc_warrior', 'orc_soldier', 'hue-rotate(160deg) saturate(1.2)'],
];

const browser = await launch();
const page = await browser.newPage();
for (const [src, dst, filter] of JOBS) {
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
