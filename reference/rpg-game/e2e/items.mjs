// Phase 15b: đồ Item.txt theo lớp — 8 ô trang bị (đồ khởi đầu theo lớp), bảng chi tiết có "Dùng cho" và
// "Cần <chỉ số>" (đỏ khi thiếu, không cho trang bị), Thợ Rèn chỉ bày đồ đúng lớp, mua đồ lớp khác bị từ chối,
// mặc / tháo mũ. Có hình gốc (`mix hac_long.icons`) thì kiểm hình tải được; không có (CI) thì bỏ qua.
// Chạy: node e2e/items.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, send, shot, travel, meetNpc, act } from './lib.mjs';

const R = reporter('items');
const browser = await launch();
const E = await newPlayer(browser, { cls: 'elf' });
const { admin } = await adminSession(browser);

// ---------- đồ khởi đầu theo lớp, 8 ô ----------
const eq = (await player(E.page)).equip;
R.check('Tiên Nữ mới: Cung Ngắn + bộ Dây Leo (mũ, giáp, quần, găng, giày)', eq.weapon === 'item_4_0' && eq.helm === 'item_7_10' && eq.armor === 'item_8_10' && eq.pants === 'item_9_10' && eq.gloves === 'item_10_10' && eq.boots === 'item_11_10', JSON.stringify(eq));
await E.page.click('#tabs [data-tab="bag"]');
await E.page.waitForSelector('[data-act="slot-tip"][data-slot="boots"]', { timeout: 5000 }).catch(() => null);
const open = await E.page.$$eval('[data-act="slot-tip"]', (els) => els.map((e) => e.dataset.slot));
R.check('tab Túi đồ: mũ / quần / găng / giày là ô mở, có đồ', ['helm', 'pants', 'gloves', 'boots'].every((s) => open.includes(s)), open.join(','));
const icons = await E.page.evaluate(() => Object.keys(window.GAME_DATA.ITEM_ICONS || {}).length);
if (icons) {
  const imgs = await E.page.$$eval('.slot img.own', (els) => els.map((e) => e.naturalWidth));
  R.check('hình gốc của đồ đang mặc tải được', imgs.length >= 6 && imgs.every((w) => w > 0), JSON.stringify(imgs));
}
await shot(E.page, 'items-bag.png');

// ---------- yêu cầu chỉ số: Cung Bạc (bậc 7) cần Nhanh nhẹn 35 ----------
await admin('set_level', E.name, { level: 30 });
await admin('give_item', E.name, { id: 'item_4_5', count: 1 });
await E.page.waitForFunction(() => (window.__hl.player().inv || {}).item_4_5 >= 1, null, { timeout: 5000 }).catch(() => null);
await E.page.click('#tabs [data-tab="map"]');
await E.page.click('#tabs [data-tab="bag"]');
await E.page.click('[data-act="bag-tip"][data-id="item_4_5"]');
await E.page.waitForSelector('#itemtip', { timeout: 3000 }).catch(() => null);
const tip = (await E.page.textContent('#itemtip').catch(() => '')) || '';
R.check('bảng chi tiết: tên gốc, Dùng cho Tiên Nữ, Cần Nhanh nhẹn 35 (đỏ)', tip.includes('Silver Bow') && tip.includes('Dùng cho') && !!(await E.page.$('#itemtip .bad')) && tip.includes('Nhanh nhẹn 35'), tip.slice(0, 160));
R.check('thiếu chỉ số thì nút Trang bị bị khóa', !!(await E.page.$('#itemtip [data-act="equip"][disabled]')));
await shot(E.page, 'items-tip.png');
const r1 = await send(E.page, { act: 'equip', id: 'item_4_5' });
R.check('server cũng từ chối mặc khi thiếu chỉ số', r1.equip.weapon === 'item_4_0');

// ---------- tháo / mặc lại mũ ----------
await E.page.keyboard.press('Escape').catch(() => null);
const p1 = await send(E.page, { act: 'unequip', slot: 'helm' });
R.check('tháo mũ: ô trống, mũ về túi', p1.equip.helm == null && p1.inv.item_7_10 === 1);
const p2 = await send(E.page, { act: 'equip', id: 'item_7_10' });
R.check('mặc lại mũ', p2.equip.helm === 'item_7_10');

// ---------- Thợ Rèn chỉ bày đồ đúng lớp ----------
await E.page.click('#tabs [data-tab="map"]');
await travel(E.page, 'village').catch(() => null);
await meetNpc(E.page, 'blacksmith');
await E.page.waitForSelector('[data-act="buy"]', { timeout: 5000 }).catch(() => null);
const ids = await E.page.$$eval('[data-act="buy"]', (els) => els.map((e) => e.dataset.id));
const wrong = await E.page.evaluate((ids) => ids.filter((id) => { const it = window.GAME_DATA.ITEMS[id]; return it.classes && !it.classes.includes('elf'); }), ids);
R.check('Thợ Rèn bày đồ Tiên Nữ (cung, bộ Lụa…), không bày đồ lớp khác', ids.includes('item_4_8') && ids.includes('item_8_11') && wrong.length === 0, `${ids.length} món, sai lớp: ${wrong.join(',')}`);
await shot(E.page, 'items-shop.png');
const bad = await E.page.evaluate(() => window.__hl.send({ act: 'buy', id: 'item_1_1' }).then(() => window.__hl.ui()));
const last = await E.page.evaluate(() => document.body.textContent.includes('không dành cho Tiên Nữ'));
R.check('mua đồ lớp khác bị từ chối', last, JSON.stringify(bad && bad.busy));

// ---------- Phase 15c: nhẫn (2 ô), dây chuyền, Excellent, thưởng đủ bộ, cầm cung ----------
await admin('add_stats', E.name, { agi: 20 });
await admin('give_item', E.name, { id: 'item_13_8', count: 2 });
await admin('give_item', E.name, { id: 'item_13_12', count: 1 });
await E.page.waitForFunction(() => (window.__hl.player().inv || {}).item_13_12 >= 1, null, { timeout: 5000 }).catch(() => null);
await send(E.page, { act: 'equip', id: 'item_13_8' });
await send(E.page, { act: 'equip', id: 'item_13_8' });
const pj = await send(E.page, { act: 'equip', id: 'item_13_12' });
R.check('hai nhẫn vào ring1 + ring2, dây chuyền vào ô dây chuyền', pj.equip.ring1 === 'item_13_8' && pj.equip.ring2 === 'item_13_8' && pj.equip.pendant === 'item_13_12', JSON.stringify(pj.equip));
await admin('give_gear', E.name, { base: 'item_4_2', rarity: 1, bonus: { agi: 1 }, exc: ['atk_pct', 'crit'] });
await E.page.waitForFunction(() => Object.values(window.__hl.player().view.gear || {}).some((g) => g.excellent), null, { timeout: 5000 }).catch(() => null);
const exc = await E.page.evaluate(() => Object.values(window.__hl.player().view.gear || {}).find((g) => g.excellent));
await E.page.click('#tabs [data-tab="map"]');
await E.page.click('#tabs [data-tab="bag"]');
await E.page.click(`[data-act="bag-tip"][data-id="${exc && exc.uid}"]`).catch(() => null);
await E.page.waitForSelector('#itemtip', { timeout: 3000 }).catch(() => null);
const tipE = (await E.page.textContent('#itemtip').catch(() => '')) || '';
R.check('đồ Excellent: tên xanh, dòng "Tăng sát thương" và "Tỉ lệ chí mạng"', !!(await E.page.$('#itemtip b .exc')) && tipE.includes('Excellent') && tipE.includes('Tăng sát thương') && tipE.includes('Tỉ lệ chí mạng'), tipE.slice(0, 200));
if (icons) {
  const src = await E.page.$eval('#itemtip img.own', (e) => e.getAttribute('src')).catch(() => '');
  R.check('đồ Excellent dùng hình _e', /_e\.png/.test(src), src);
}
await shot(E.page, 'items-excellent.png');
const pe = await send(E.page, { act: 'equip', id: exc.uid });
const d0 = (await player(E.page)).view;
R.check('mặc đồ Excellent: tấn công / chí mạng tính dòng Excellent', pe.equip.weapon === exc.uid && d0.exc.atk_pct > 0 && d0.exc.crit > 0, JSON.stringify(d0.exc));

// đủ bộ Lụa (bậc 2): 5 món → có thưởng
for (const id of ['item_7_11', 'item_8_11', 'item_9_11', 'item_10_11', 'item_11_11']) await admin('give_item', E.name, { id, count: 1 });
await E.page.waitForFunction(() => (window.__hl.player().inv || {}).item_11_11 >= 1, null, { timeout: 5000 }).catch(() => null);
for (const id of ['item_7_11', 'item_8_11', 'item_9_11', 'item_10_11', 'item_11_11']) await send(E.page, { act: 'equip', id });
const sb = (await player(E.page)).view.setBonus;
R.check('đủ 5 món bộ Lụa: thưởng đủ bộ bật', sb.name === 'Lụa' && sb.have === 5 && sb.active, JSON.stringify(sb));
await E.page.click('#tabs [data-tab="map"]');
await E.page.click('#tabs [data-tab="bag"]');
R.check('tab Túi đồ hiện dòng "Bộ Lụa 5/5 ✓"', ((await E.page.textContent('.bag-bottom')) || '').includes('Bộ Lụa 5/5'));
await shot(E.page, 'items-set.png');
R.check('Tiên Nữ cầm cung trên hình nhân vật', ((await player(E.page)).view.look || {}).weapon === 'hand1/bow', JSON.stringify((await player(E.page)).view.look));

R.check('không lỗi JS', E.errors.length === 0, E.errors.join(' | '));
await R.done(browser);
