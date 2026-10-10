// Phase 18 M1: Quảng Trường Quỷ — bảng ở Người Gác Tháp (giờ mở, vé, bảng xếp hạng), mua vé, vào (bản đồ riêng),
// hạ hết đợt 1, sang đợt 2, tự ra (cầu thang xuống) nhận thưởng theo điểm, không vào lại được cùng đợt.
// Server cần chạy với HL_DS_OPEN=1 (Quảng Trường luôn mở; CI đặt sẵn).
// Chạy: node e2e/ds.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, act, idle, travel, meetNpc, walkTo, fight, shot } from './lib.mjs';

const R = reporter('ds');
const browser = await launch();
const P = await newPlayer(browser, { cls: 'dk' });
const { admin } = await adminSession(browser);
const page = P.page;

// nhân vật đủ cấp, đủ mạnh để qua đợt đầu, đủ vàng mua vé
await admin('set_level', P.name, { level: 40 });
await admin('add_stats', P.name, { str: 400, vit: 300, agi: 100 });
await admin('add_gold', P.name, { amount: 50000 });
await admin('heal', P.name, {});
await page.waitForFunction(() => window.__hl.player().level >= 40 && window.__hl.player().gold >= 50000, null, { timeout: 8000 }).catch(() => null);

if ((await player(page)).pos.map !== 'village') await travel(page, 'village');
R.check('gặp Người Gác Tháp', await meetNpc(page, 'tower_guard'));
await page.waitForSelector('[data-panel="devil-square"]', { timeout: 5000 }).catch(() => null);
const card = (await page.textContent('[data-panel="devil-square"]').catch(() => '')) || '';
R.check('bảng Quảng Trường Quỷ: đang mở, giá vé, nút vào khóa khi chưa có vé', card.includes('Quảng Trường Quỷ') && card.includes('Đang mở') && !!(await page.$('[data-act="ds_enter"][disabled]')), card.slice(0, 200));

const g0 = (await player(page)).gold;
await act(page, 'ds_buy');
let p = await player(page);
const price = p.view.ds.price;
R.check('mua vé: trừ vàng, có 1 vé', p.gold === g0 - price && p.inv.ds_ticket === 1, `gold ${g0}→${p.gold}, vé ${p.inv.ds_ticket}`);
await shot(page, 'ds-npc.png');

await act(page, 'ds_enter');
await page.waitForFunction(() => window.__hl.player().pos.map === 'tower', null, { timeout: 5000 }).catch(() => null);
p = await player(page);
R.check('vào Quảng Trường: bản đồ riêng, đợt 1, mất vé', p.pos.map === 'tower' && p.tower && p.tower.ds && p.tower.floor === 1 && !p.inv.ds_ticket, JSON.stringify({ map: p.pos.map, floor: p.tower && p.tower.floor }));
const title = (await page.textContent('#app').catch(() => '')) || '';
R.check('tên bản đồ "Quảng Trường Quỷ · Đợt 1/5"', title.includes('Quảng Trường Quỷ · Đợt 1/'), '');
await shot(page, 'ds-wave1.png');

// hạ hết quái đợt 1
for (let i = 0; i < 12; i++) {
  p = await player(page);
  if (!p.tower || !p.tower.monsters.length) break;
  const m = p.tower.monsters[0];
  await walkTo(page, m.x, m.y);
  if ((await player(page)).battle) {
    await fight(page);
    await act(page, 'leave').catch(() => null);
  }
}
p = await player(page);
R.check('hạ hết quái đợt 1: có điểm', p.tower && p.tower.monsters.length === 0 && p.tower.ds.score > 0, JSON.stringify(p.tower && { left: p.tower.monsters.length, score: p.tower.ds.score }));

// sang đợt 2 qua cầu thang lên
await walkTo(page, p.tower.stairs[0], p.tower.stairs[1]);
await page.waitForFunction(() => (window.__hl.player().tower || {}).floor === 2, null, { timeout: 5000 }).catch(() => null);
p = await player(page);
R.check('cầu thang lên: sang đợt 2', p.tower && p.tower.floor === 2, String(p.tower && p.tower.floor));

// tự ra: cầu thang xuống ở lối vào
const score = p.tower.ds.score;
const g1 = p.gold;
await walkTo(page, p.tower.exit[0], p.tower.exit[1]);
await page.waitForFunction(() => window.__hl.player().pos.map === 'village', null, { timeout: 5000 }).catch(() => null);
p = await player(page);
R.check('tự ra: về Làng, nhận vàng theo điểm, điểm cao nhất hôm nay', p.pos.map === 'village' && !p.tower && p.gold > g1 && p.view.ds.best === score, JSON.stringify({ map: p.pos.map, gold: [g1, p.gold], best: p.view.ds.best, score }));

// cùng đợt không vào lại được
await admin('give_item', P.name, { id: 'ds_ticket', count: 1 });
await page.waitForFunction(() => (window.__hl.player().inv || {}).ds_ticket >= 1, null, { timeout: 5000 }).catch(() => null);
await idle(page);
p = await player(page);
R.check('cùng đợt: đã vào rồi, không vào lại', p.view.ds.used === true, JSON.stringify(p.view.ds));

// bảng xếp hạng hôm nay có tên mình
await meetNpc(page, 'tower_guard');
await page.waitForFunction((n) => (document.querySelector('[data-panel="devil-square"]') || {}).textContent?.includes(n), P.name, { timeout: 35000 }).catch(() => null);
const card2 = (await page.textContent('[data-panel="devil-square"]').catch(() => '')) || '';
R.check('bảng xếp hạng hôm nay có tên mình', card2.includes(P.name), card2.slice(-160));
await shot(page, 'ds-board.png');

R.check('không lỗi JS', P.errors.length === 0, P.errors.join(' | '));
await R.done(browser);
