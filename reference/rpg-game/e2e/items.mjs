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

R.check('không lỗi JS', E.errors.length === 0, E.errors.join(' | '));
await R.done(browser);
