// Người chơi trên bản đồ + ⚡ Đồ sát nhanh (DECISIONS "Người chơi trên bản đồ, Đồ sát nhanh"): A thấy B trên bản đồ,
// bấm vào B mở menu (Hồ sơ, Giao dịch, Đồ sát), công tắc Tắt / Tất cả, 📍 ở Quanh đây; A và B cùng bật ⚡, A đồ sát
// nhanh B: cả hai ở lại bản đồ, server tự đánh tới khi có người gục; C cùng bản đồ thấy ⚔ trên A, B.
// Chạy: node e2e/mapplayers.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, send, shot } from './lib.mjs';

const R = reporter('mapplayers');
const browser = await launch();
const A = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
const B = await newPlayer(browser, { cls: 'elf', viewport: { width: 390, height: 844 } });
const C = await newPlayer(browser, { cls: 'dw', viewport: { width: 390, height: 844 } });
const { admin } = await adminSession(browser);
for (const X of [A, B, C]) {
  await admin('set_level', X.name, { level: 20 });
  await admin('add_gold', X.name, { amount: 50000 });
  await admin('give_item', X.name, { id: 'potion_m', count: 20 });
}
for (const X of [A, B, C]) {
  await X.page.waitForFunction(() => window.__hl.player().level === 20 && window.__hl.player().gold >= 50000, null, { timeout: 8000 }).catch(() => null);
  await send(X.page, { act: 'travel', to: 'forest_2' }).catch(() => null);
  await X.page.waitForFunction(() => window.__hl.player().pos.map === 'forest_2', null, { timeout: 8000 }).catch(() => null);
  await X.page.click('#tabs [data-tab="map"]').catch(() => null);
}
R.check('A, B, C cùng ở Rừng Mê 2', (await Promise.all([A, B, C].map((X) => X.page.evaluate(() => window.__hl.player().pos.map)))).every((m) => m === 'forest_2'));
const posB = async () => B.page.evaluate(() => window.__hl.player().pos);
await A.page.waitForFunction((n) => window.__hl.world().players.some((o) => o.name === n), B.name, { timeout: 8000 }).catch(() => null);
await A.page.waitForTimeout(500);
let bp = await posB();
R.check('A thấy B vẽ trên bản đồ', await A.page.evaluate(([x, y, n]) => window.MapView.playersNear(x, y).some((o) => o.name === n), [bp.x, bp.y, B.name]));
await shot(A.page, 'mapplayers-map.png');

// bấm vào B: menu của B
// bấm vào ô của B; B đứng chung ô với người khác (vd C) thì hiện bảng chọn trước → chọn dòng B
let sawPicker = false;
const tapB = async () => {
  bp = await posB();
  const s = await A.page.evaluate(([x, y]) => window.MapView.screenOf(x, y), [bp.x, bp.y]);
  await A.page.mouse.click(s.x, s.y);
  await A.page.waitForSelector('.pick-pop', { timeout: 3000 }).catch(() => null);
  const row = await A.page.$(`.pick-pop [data-act="pick-sel"]:has-text("${B.name}")`);
  if (row) { sawPicker = true; await row.click(); }
};
await tapB();
const pop = await A.page.textContent('.pick-pop').catch(() => '');
R.check('bấm vào B: menu có tên B, Hồ sơ, Giao dịch, Đồ sát', pop.includes(B.name) && pop.includes('Hồ sơ') && pop.includes('Giao dịch') && /Đồ sát/.test(pop), pop.slice(0, 120));
await shot(A.page, 'mapplayers-menu.png');
const cp = await C.page.evaluate(() => window.__hl.player().pos);
if (cp.x === bp.x && cp.y === bp.y) R.check('B, C chung ô: hiện bảng chọn người trước', sawPicker);
await A.page.click('.pick-pop [data-act="pick-close"]');

// công tắc: Tắt → không vẽ B; Tất cả → vẽ lại
await A.page.evaluate(() => localStorage.setItem('hl-players', 'off'));
await A.page.evaluate(() => window.MapView.draw());
bp = await posB();
R.check('Cài đặt Tắt: không vẽ B', !(await A.page.evaluate(([x, y, n]) => window.MapView.playersNear(x, y).some((o) => o.name === n), [bp.x, bp.y, B.name])));
await A.page.evaluate(() => localStorage.setItem('hl-players', 'all'));
await A.page.evaluate(() => window.MapView.draw());

// 📍 ở Quanh đây: về bản đồ
await A.page.click('#tabs [data-tab="people"]');
await A.page.waitForSelector('[data-act="people-pin"]', { timeout: 5000 }).catch(() => null);
await A.page.click(`.people-row:has-text("${B.name}") [data-act="people-pin"]`).catch(() => null);
await A.page.waitForSelector('#map-canvas', { timeout: 3000 }).catch(() => null);
R.check('📍 Quanh đây: về bản đồ', !!(await A.page.$('#map-canvas')));

// ⚡ Đồ sát nhanh: A và B bật ⚡; A bấm B → 🗡⚡ Đồ sát nhanh
for (const X of [A, B]) { await X.page.click('[data-act="quick-toggle"]'); await X.page.waitForFunction(() => (window.__hl.player().view.autoCfg || {}).quick === true, null, { timeout: 5000 }).catch(() => null); }
await tapB();
await A.page.waitForSelector('.pick-pop [data-act="pick-slay"]', { timeout: 3000 }).catch(() => null);
R.check('menu có 🗡⚡ Đồ sát nhanh khi bật ⚡', /Đồ sát nhanh/.test(await A.page.textContent('.pick-pop').catch(() => '')));
await A.page.click('.pick-pop [data-act="pick-slay"]');
await A.page.waitForFunction(() => !!window.__hl.player().battle, null, { timeout: 10000 }).catch(() => null);
await A.page.waitForTimeout(900);
const midA = await A.page.evaluate(() => ({ battle: !!window.__hl.player().battle, map: !!document.querySelector('#map-canvas'), atk: !!document.querySelector('[data-act="attack"]'), bar: (document.querySelector('#auto-bar') || {}).textContent || '' }));
const midB = await B.page.evaluate(() => ({ battle: !!window.__hl.player().battle, map: !!document.querySelector('#map-canvas'), atk: !!document.querySelector('[data-act="attack"]') }));
R.check('đồ sát nhanh: A ở lại bản đồ, thanh "🗡 Đồ sát"', midA.battle && midA.map && !midA.atk && /Đồ sát/.test(midA.bar), JSON.stringify(midA));
R.check('B (bật ⚡) bị đánh cũng ở lại bản đồ', midB.battle && midB.map && !midB.atk, JSON.stringify(midB));
await shot(A.page, 'mapplayers-slay-A.png');
await shot(B.page, 'mapplayers-slay-B.png');
// C cùng bản đồ thấy ⚔ (đang đồ sát) trên A hoặc B
const seenDuel = await C.page.waitForFunction(([a, b]) => window.__hl.world().players.some((o) => (o.name === a || o.name === b) && o.duel), [A.name, B.name], { timeout: 8000 }).then(() => true).catch(() => false);
R.check('C thấy A / B đang đồ sát (⚔, máu)', seenDuel);
await shot(C.page, 'mapplayers-spectator.png');
for (const X of [A, B]) await X.page.waitForFunction(() => { const q = window.__hl.player(); return q && !q.battle; }, null, { timeout: 200000 }).catch(() => null);
const end = (await Promise.all([A, B].map((X) => X.page.evaluate(() => { const q = window.__hl.player(); return !!q && !q.battle; })))).every(Boolean);
const deaths = await Promise.all([A, B].map((X) => X.page.evaluate(() => window.__hl.player().deaths)));
R.check('server tự đánh tới khi có người gục, hai bên tự rời màn trận', end && deaths.some((d) => d >= 1), JSON.stringify({ end, deaths }));
R.check('không lỗi JS', [A, B, C].every((X) => X.errors.length === 0), [A, B, C].flatMap((X) => X.errors).join(' | '));
await R.done(browser);
