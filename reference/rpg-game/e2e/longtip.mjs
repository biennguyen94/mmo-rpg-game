// Khung chi tiết đồ trên điện thoại (360 × 640): đồ nhiều dòng (6 dòng Excellent, May mắn, dòng cộng thêm, Bộ Thần, +9)
// không lố màn hình: khung cao tối đa bằng màn hình, phần thông tin cuộn (mờ ở mép dưới khi còn dòng),
// hàng nút luôn thấy. Chạy: node e2e/longtip.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, act, shot } from './lib.mjs';
const R = reporter('longtip');
const browser = await launch();
const { page, name, errors } = await newPlayer(browser, { cls: 'dk', viewport: { width: 360, height: 640 } });
const { admin } = await adminSession(browser);
const base = await page.evaluate(() => { const P = window.__hl.player(); return P.view.gear[P.equip.armor].base; });
await admin('give_gear', name, { base, up: 9, opt: 4, luck: true, anc: true, exc: ['hp_pct', 'dmg_red', 'gold_pct', 'mp_pct', 'reflect', 'def_rate'] });
await page.waitForFunction(() => Object.keys(window.__hl.player().view.forgeBag).length > 0, null, { timeout: 8000 }).catch(() => null);
const id = await page.evaluate(() => Object.keys(window.__hl.player().view.forgeBag)[0]);
await page.click('#tabs [data-tab="bag"]');
for (const y of [100, 560]) {
  await page.evaluate((y) => window.scrollTo(0, 0), y);
  await page.locator(`[data-act="bag-tip"][data-id="${id}"]`).click();
  const g = await page.evaluate(() => {
    const t = document.querySelector('#itemtip'), b = t.querySelector('.btns'), body = t.querySelector('.tip-body');
    const tr = t.getBoundingClientRect(), br = b.getBoundingClientRect();
    return { top: tr.top, bottom: tr.bottom, vh: innerHeight, btnBottom: br.bottom, btnTop: br.top, scroll: body.scrollHeight > body.clientHeight, lines: body.textContent.length };
  });
  R.check(`khung đồ nằm trong màn hình, hàng nút thấy được (${JSON.stringify(g)})`, g.top >= 0 && g.bottom <= g.vh && g.btnBottom <= g.vh && g.btnTop >= 0);
  R.check('đồ nhiều dòng: phần thông tin cuộn được, có mờ ở mép dưới', g.scroll && (await page.$('#itemtip .tip-body.more')) !== null);
  await page.evaluate(() => { const b = document.querySelector('#itemtip .tip-body'); b.scrollTop = b.scrollHeight; b.dispatchEvent(new Event('scroll')); });
  R.check('cuộn tới cuối: hết mờ', (await page.$('#itemtip .tip-body.more')) === null);
  await shot(page, `longtip-end.png`);
  break;
}
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
