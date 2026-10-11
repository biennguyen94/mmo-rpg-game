// B-21: Kalima — bảng ở Người Gác Tháp, Bản Đồ Thất Lạc, vào (bản đồ riêng), hạ quái Kalima → Kundun, nhận thưởng, về Làng.
// Chạy: node e2e/kalima.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, act, travel, meetNpc, walkTo, fight, shot } from './lib.mjs';

const R = reporter('kalima');
const browser = await launch();
const P = await newPlayer(browser, { cls: 'dk' });
const { admin } = await adminSession(browser);
const page = P.page;

await admin('set_level', P.name, { level: 32 });
await admin('add_stats', P.name, { str: 900, vit: 600, agi: 300 });
await admin('heal', P.name, {});
await page.waitForFunction(() => window.__hl.player().level >= 32, null, { timeout: 8000 }).catch(() => null);

if ((await player(page)).pos.map !== 'village') await travel(page, 'village');
R.check('gặp Người Gác Tháp', await meetNpc(page, 'tower_guard'));
await page.waitForSelector('[data-panel="kalima"]', { timeout: 5000 }).catch(() => null);
const card = (await page.textContent('[data-panel="kalima"]').catch(() => '')) || '';
R.check('bảng Kalima: Kalima 3 theo cấp, nút vào khóa khi chưa có bản đồ', card.includes('Kalima 3') && !!(await page.$('[data-act="kal_enter"][disabled]')), card.slice(0, 160));

await admin('give_item', P.name, { id: 'lost_map', count: 1 });
await page.waitForFunction(() => (window.__hl.player().inv.lost_map || 0) === 1, null, { timeout: 5000 }).catch(() => null);
await act(page, 'kal_enter');
await page.waitForFunction(() => window.__hl.player().pos.map === 'tower', null, { timeout: 5000 }).catch(() => null);
let p = await player(page);
R.check('vào Kalima: bản đồ riêng, mất bản đồ', p.pos.map === 'tower' && p.tower && p.tower.kal && p.tower.kal.n === 3 && !p.inv.lost_map, JSON.stringify({ map: p.pos.map, kal: p.tower && p.tower.kal }));
R.check('tên bản đồ "Kalima 3 · Hạ quái Kalima"', ((await page.textContent('#app').catch(() => '')) || '').includes('Kalima 3 · Hạ quái Kalima'));
await shot(page, 'kalima-guards.png');

const seen = new Set();
for (let i = 0; i < 25; i++) {
  await page.waitForFunction(() => { const t = window.__hl.player().tower; return !t || t.kal.done || t.monsters.length > 0; }, null, { timeout: 5000 }).catch(() => null);
  p = await player(page);
  if (!p.tower || p.tower.kal.done || !p.tower.monsters.length) break;
  seen.add(p.tower.kal.stage);
  if (p.hp < p.maxHp / 2) await admin('heal', P.name, {});
  for (const m of p.tower.monsters) {
    await walkTo(page, m.x, m.y);
    if ((await player(page)).battle) break;
  }
  if ((await player(page)).battle) {
    await fight(page);
    await act(page, 'leave').catch(() => null);
  }
}
p = await player(page);
R.check('hạ quái Kalima rồi Kundun: xong', seen.has('guards') && seen.has('boss') && p.tower && p.tower.kal.done, JSON.stringify({ seen: [...seen], kal: p.tower && p.tower.kal }));
await shot(page, 'kalima-done.png');

await walkTo(page, p.tower.exit[0], p.tower.exit[1]).catch(() => null);
await page.waitForFunction(() => window.__hl.player().pos.map === 'village', null, { timeout: 5000 }).catch(() => null);
p = await player(page);
R.check('xong rồi bước đi: về Làng', p.pos.map === 'village' && !p.tower, JSON.stringify({ map: p.pos.map }));

R.check('không lỗi JS', P.errors.length === 0, P.errors.join(' | '));
await R.done(browser);
