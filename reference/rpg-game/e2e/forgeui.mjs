// Giao diện Thợ Rèn + Lão Hỗn Nguyên trên điện thoại: nguyên liệu mỗi loại một dòng, đủ thì sáng, công thức cánh gọn.
// Chạy: node e2e/forgeui.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, travel, meetNpc, leaveNpc, shot, overflowX } from './lib.mjs';

const R = reporter('forgeui');
const browser = await launch();
const { page, name, errors } = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
const adm = await adminSession(browser);
await adm.admin('set_level', name, { level: 50 });
await adm.admin('add_gold', name, { amount: 3000000 });
for (const [id, count] of [['jewel_bless', 5], ['jewel_soul', 1], ['jewel_chaos', 1]]) await adm.admin('give_item', name, { id, count });
await adm.admin('give_gear', name, { base: 'wing_dk_1', up: 6 });
await adm.admin('give_gear', name, { base: 'wing_dk_1', up: 9 });
await page.waitForFunction(() => (window.__hl.player().inv.jewel_chaos || 0) === 1);
await travel(page, 'village');

R.check('gặp Thợ Rèn', await meetNpc(page, 'blacksmith'));
await page.click('[data-act="npc-tab"][data-t="forge"]');
await page.click('[data-act="forge-tab"][data-tab2="bag"]').catch(() => null);
await page.waitForTimeout(300);
R.check('Thợ Rèn: nguyên liệu mỗi loại một dòng', (await page.$$('.needs')).length > 0);
R.check('Thợ Rèn: có ngọc đủ (sáng) và thiếu (đỏ)', (await page.$$('.needs .ok')).length > 0);
R.check('Thợ Rèn: không tràn ngang', !(await overflowX(page)));
await page.locator('.needs').first().scrollIntoViewIfNeeded();
await shot(page, 'forgeui-smith.png');
await leaveNpc(page);

R.check('gặp Lão Hỗn Nguyên', await meetNpc(page, 'chaos'));
await page.click('[data-panel="chaos-upgrade"] [data-act="forge-tab"][data-tab2="bag"]').catch(() => null);
await page.waitForTimeout(300);
await page.locator('[data-panel="chaos-upgrade"]').scrollIntoViewIfNeeded();
await shot(page, 'forgeui-chaos-up.png');
await page.click('[data-act="npc-tab"][data-t="wing"]');
await page.click('[data-fold="chaos-wing-lack"] > summary').catch(() => null);
const wing = page.locator('[data-act="chaos"][data-id="wing2"]');
await wing.scrollIntoViewIfNeeded();
const txt = await wing.locator('xpath=..').textContent();
R.check('công thức cánh 2 không lặp danh sách nguyên liệu trong mô tả', !txt.includes('5 Ước Nguyện + 5 Tâm Linh'), txt);
R.check('công thức cánh 2 ghi món bỏ vào gọn', txt.includes('Bỏ vào: 1 cánh cấp 1 +5 trở lên'), txt);
await shot(page, 'forgeui-chaos-wing.png');
R.check('Lão Hỗn Nguyên: không tràn ngang', !(await overflowX(page)));
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
