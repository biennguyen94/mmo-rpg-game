// Bản đồ thu nhỏ (B11): giữ và kéo để dời chỗ (nhớ vị trí qua F5, nằm gọn trong khung bản đồ); bấm nhẹ vẫn mở bản đồ thế giới.
// Chạy: node e2e/minimap.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, reloadGame, shot } from './lib.mjs';

const R = reporter('minimap');
const browser = await launch();

async function box(page) {
  return page.evaluate(() => {
    const m = document.getElementById('mini-map'), w = m.parentElement;
    const a = m.getBoundingClientRect(), b = w.getBoundingClientRect();
    return { x: a.left - b.left, y: a.top - b.top, w: a.width, h: a.height, ww: b.width, wh: b.height, cx: a.left + a.width / 2, cy: a.top + a.height / 2, bottom: b.bottom };
  });
}
const tab = (page) => page.evaluate(() => window.__hl.ui().tab);

for (const [label, viewport] of [['máy tính', { width: 1280, height: 900 }], ['điện thoại', { width: 390, height: 844 }]]) {
  const X = await newPlayer(browser, { viewport });
  const page = X.page;
  await page.waitForSelector('#mini-map');
  await page.waitForTimeout(400);
  const a = await box(page);
  R.check(`${label}: mặc định ở góc trái trên`, a.x <= 8 && a.y <= 8, JSON.stringify(a));

  // kéo xuống góc trái dưới (kéo quá mép: bị giữ trong khung; góc phải dưới là nút chat)
  await page.mouse.move(a.cx, a.cy);
  await page.mouse.down();
  await page.mouse.move(a.cx + 30, a.cy + 30, { steps: 4 });
  await page.mouse.move(a.cx - 200, a.bottom + 200, { steps: 8 });
  await page.mouse.up();
  await page.waitForTimeout(300);
  const b = await box(page);
  R.check(`${label}: kéo được xuống góc trái dưới, không lọt ra ngoài khung`, b.x >= 0 && b.x <= 8 && b.y > a.y + 50 && b.x + b.w <= b.ww - 4 && b.y + b.h <= b.wh - 4, JSON.stringify(b));
  R.check(`${label}: kéo xong không mở bản đồ thế giới`, (await tab(page)) === 'map', await tab(page));
  await shot(page, `minimap-drag-${viewport.width}.png`);

  await reloadGame(page);
  await page.waitForSelector('#mini-map');
  await page.waitForTimeout(400);
  const c = await box(page);
  R.check(`${label}: F5 vẫn nhớ vị trí`, Math.abs(c.x - b.x) <= 3 && Math.abs(c.y - b.y) <= 3, JSON.stringify(c));

  await page.mouse.click(c.cx, c.cy);
  await page.waitForTimeout(400);
  R.check(`${label}: bấm nhẹ vẫn mở bản đồ thế giới`, (await tab(page)) === 'travel', await tab(page));
  R.check(`${label}: không lỗi JS`, X.errors.length === 0, X.errors.join(' | '));
  await X.ctx.close();
}

// cảm ứng thật (điện thoại): chạm giữ rồi kéo bằng ngón tay
{
  const X = await newPlayer(browser, { viewport: { width: 390, height: 844 } });
  const page = X.page;
  const cdp = await X.ctx.newCDPSession(page);
  await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 });
  await page.waitForSelector('#mini-map');
  await page.waitForTimeout(400);
  const a = await box(page);
  const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
  await touch('touchStart', a.cx, a.cy);
  for (let i = 1; i <= 10; i++) await touch('touchMove', a.cx, a.cy + i * 30);
  await touch('touchEnd');
  await page.waitForTimeout(300);
  const b = await box(page);
  R.check('cảm ứng: chạm giữ kéo xuống được', b.y > a.y + 100, JSON.stringify(b));
  R.check('cảm ứng: kéo xong không mở bản đồ thế giới', (await tab(page)) === 'map', await tab(page));
  R.check('cảm ứng: không lỗi JS', X.errors.length === 0, X.errors.join(' | '));
  await X.ctx.close();
}
await R.done(browser);
