// Cất / rút vàng ở Tủ Đồ (2026-10-24): ô nhập số vàng, nút Cất / Rút / Cất hết / Rút hết.
// Chạy: node e2e/wardrobe_gold.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, act, player, travel, meetNpc, shot } from './lib.mjs';

const R = reporter('wardrobe_gold');
const browser = await launch();
const { page, name, errors } = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
const adm = await adminSession(browser);
await adm.admin('add_gold', name, { amount: 5000 });
await page.waitForFunction(() => window.__hl.player().gold >= 5000);
const g0 = (await player(page)).gold;
if ((await player(page)).pos.map !== 'home') await travel(page, 'home');
R.check('gặp Tủ Đồ', await meetNpc(page, 'wardrobe'));
R.check('có thẻ Vàng trong tủ', !!(await page.$('#wd-gold')));
await page.fill('#wd-gold', '3000');
await act(page, '[data-act="gold_store"]:not([data-all])');
let p = await player(page);
R.check('cất 3000 vàng', p.gold === g0 - 3000 && p.view.storage.gold === 3000, `${p.gold} / ${p.view.storage.gold}`);
await shot(page, 'wardrobe-gold.png');
await act(page, '[data-act="gold_take"][data-all]');
p = await player(page);
R.check('rút hết', p.gold === g0 && p.view.storage.gold === 0, `${p.gold} / ${p.view.storage.gold}`);
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
