// Cầm 2 vũ khí (B-42): nút Cầm tay trái, ô tay trái trong túi đồ và hồ sơ ghi "Tay trái".
// Chạy: node e2e/dualwield.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, act, player, shot } from './lib.mjs';
const R = reporter('dualwield');
const browser = await launch();
const { page, name, errors } = await newPlayer(browser, { cls: 'dk' });
const adm = await adminSession(browser);
await adm.admin('set_level', name, { level: 50 });
for (let i = 0; i < 2; i++) await adm.admin('give_gear', name, { base: 'item_0_3' });
await page.waitForFunction(() => Object.values(window.__hl.player().view.gear || {}).filter((g) => g.base === 'item_0_3').length >= 2, null, { timeout: 10000 }).catch(() => {});
await page.click('#tabs [data-tab="bag"]'); await page.waitForTimeout(400);
const ids = await page.$$eval('[data-act="bag-tip"]', (els) => els.map((e) => e.dataset.id));
const p0 = await player(page);
const ks = ids.filter((id) => (p0.view.gear[id] || {}).base === 'item_0_3');
await act(page, `[data-act="bag-tip"][data-id="${ks[0]}"]`); await act(page, '#itemtip [data-act="equip"]:not([data-hand])');
await act(page, `[data-act="bag-tip"][data-id="${ks[1]}"]`);
const leftBtn = await page.$('#itemtip [data-act="equip"][data-hand="left"]');
R.check('có nút Cầm tay trái', !!leftBtn);
if (leftBtn) await act(page, '#itemtip [data-act="equip"][data-hand="left"]');
const bagLbl = await page.$eval('[data-slot="shield"] .lbl', (e) => e.textContent).catch(() => '');
R.check('túi đồ: ô ghi Tay trái', bagLbl === 'Tay trái', bagLbl);
await page.click('#tabs [data-tab="hero"]'); await page.click('[data-act="profile"]'); await page.waitForSelector('.prof-head');
const lbls = await page.$$eval('.prof-head ~ * .lbl, #view .slot .lbl', (els) => els.map((e) => e.textContent));
R.check('hồ sơ: có Tay trái, không có Khiên', lbls.includes('Tay trái') && !lbls.includes('Khiên'), lbls.join(','));
await shot(page, 'dualwield-profile.png');
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
