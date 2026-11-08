// Tháo hết đồ (cả vũ khí) rồi bấm món trong túi: ô thông tin vẫn hiện và mặc lại được
// (lỗi cũ: `canLeft` đọc `ref` của vũ khí tay phải khi tay phải trống → ô thông tin không hiện).
// Chạy: node e2e/bare_tip.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, send } from './lib.mjs';

const R = reporter('bare_tip');
const browser = await launch();
for (const cls of ['dk', 'mg']) {
  const X = await newPlayer(browser, { cls, viewport: { width: 390, height: 844 } });
  const p = X.page;
  const slots = await p.evaluate(() => Object.entries(window.__hl.player().equip).filter(([, v]) => v).map(([k]) => k));
  const weapon = await p.evaluate(() => window.__hl.player().equip.weapon);
  for (const s of slots) await send(p, { act: 'unequip', slot: s }).catch(() => null);
  await p.waitForFunction(() => !window.__hl.player().equip.weapon);
  await p.click('#tabs [data-tab="bag"]');
  await p.waitForSelector('[data-act="bag-tip"]');
  const ids = await p.$$eval('[data-act="bag-tip"]', (els) => els.map((e) => e.dataset.id));
  R.check(`${cls}: vũ khí đã về túi`, ids.includes(weapon), ids.join(','));
  await p.click(`[data-act="bag-tip"][data-id="${weapon}"]`);
  await p.waitForSelector('#itemtip [data-act="equip"]', { timeout: 3000 }).catch(() => null);
  R.check(`${cls}: tay không, bấm vũ khí trong túi vẫn hiện thông tin`, !!(await p.$('#itemtip [data-act="equip"]')));
  await p.click('#itemtip [data-act="equip"]').catch(() => null);
  await p.waitForFunction(() => !!window.__hl.player().equip.weapon, null, { timeout: 5000 }).catch(() => null);
  R.check(`${cls}: mặc lại được`, await p.evaluate(() => !!window.__hl.player().equip.weapon));
  R.check(`${cls}: không lỗi JS`, X.errors.length === 0, X.errors.join(' | '));
  await X.ctx.close();
}
await R.done(browser);
