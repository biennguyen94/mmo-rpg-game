// Phase 18 M2: Lâu Đài Máu — bảng ở Người Gác Tháp (giờ mở, vé), mua vé, vào (bản đồ riêng), hạ quân canh → phá
// Cổng Thành → hạ Hiệp Sĩ Máu, nhận Lông Vũ Kền Kền, bước tiếp về Làng, cùng đợt không vào lại.
// Server cần chạy với HL_DS_OPEN=1 (mở luôn; CI đặt sẵn).
// Chạy: node e2e/bc.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, act, travel, meetNpc, walkTo, fight, shot } from './lib.mjs';

const R = reporter('bc');
const browser = await launch();
const P = await newPlayer(browser, { cls: 'dk' });
const { admin } = await adminSession(browser);
const page = P.page;

// đủ cấp, đủ mạnh để hạ trùm, đủ vàng mua vé
await admin('set_level', P.name, { level: 42 });
await admin('add_stats', P.name, { str: 900, vit: 600, agi: 300 });
await admin('add_gold', P.name, { amount: 100000 });
await admin('heal', P.name, {});
await page.waitForFunction(() => window.__hl.player().level >= 42 && window.__hl.player().gold >= 100000, null, { timeout: 8000 }).catch(() => null);

if ((await player(page)).pos.map !== 'village') await travel(page, 'village');
R.check('gặp Người Gác Tháp', await meetNpc(page, 'tower_guard'));
await page.waitForSelector('[data-panel="blood-castle"]', { timeout: 5000 }).catch(() => null);
const card = (await page.textContent('[data-panel="blood-castle"]').catch(() => '')) || '';
R.check('bảng Lâu Đài Máu: đang mở, nút vào khóa khi chưa có vé', card.includes('Lâu Đài Máu') && card.includes('Đang mở') && !!(await page.$('[data-act="bc_enter"][disabled]')), card.slice(0, 200));

const g0 = (await player(page)).gold;
await act(page, 'bc_buy');
let p = await player(page);
R.check('mua vé: trừ vàng, có 1 vé', p.gold === g0 - p.view.bc.price && p.inv.bc_ticket === 1, `gold ${g0}→${p.gold}, vé ${p.inv.bc_ticket}`);

await act(page, 'bc_enter');
await page.waitForFunction(() => window.__hl.player().pos.map === 'tower', null, { timeout: 5000 }).catch(() => null);
p = await player(page);
R.check('vào Lâu Đài: bản đồ riêng, bước quân canh, mất vé', p.pos.map === 'tower' && p.tower && p.tower.bc && p.tower.bc.stage === 'guards' && !p.inv.bc_ticket, JSON.stringify({ map: p.pos.map, bc: p.tower && p.tower.bc }));
const title = (await page.textContent('#app').catch(() => '')) || '';
R.check('tên bản đồ "Lâu Đài Máu · Hạ quân canh"', title.includes('Lâu Đài Máu · Hạ quân canh'), '');
await shot(page, 'bc-guards.png');

// hạ mọi quái tới khi xong (quân canh → cổng → trùm)
const seen = new Set();
for (let i = 0; i < 20; i++) {
  p = await player(page);
  if (!p.tower || p.tower.bc.done || !p.tower.monsters.length) break;
  seen.add(p.tower.bc.stage);
  if (p.hp < p.maxHp / 2) await admin('heal', P.name, {});
  const m = p.tower.monsters[0];
  await walkTo(page, m.x, m.y);
  if ((await player(page)).battle) {
    await fight(page);
    await act(page, 'leave').catch(() => null);
  }
}
p = await player(page);
R.check('qua đủ ba bước, hạ trùm: xong, có Lông Vũ Kền Kền', ['guards', 'gate', 'boss'].every((s) => seen.has(s)) && p.tower && p.tower.bc.done && p.inv.condor_feather === 1, JSON.stringify({ seen: [...seen], bc: p.tower && p.tower.bc, feather: p.inv.condor_feather }));
await shot(page, 'bc-done.png');

// bước tiếp (về phía lối ra): về Làng
await walkTo(page, p.tower.exit[0], p.tower.exit[1]).catch(() => null);
await page.waitForFunction(() => window.__hl.player().pos.map === 'village', null, { timeout: 5000 }).catch(() => null);
p = await player(page);
R.check('xong rồi bước đi: về Làng, cùng đợt không vào lại', p.pos.map === 'village' && !p.tower && p.view.bc.used === true, JSON.stringify({ map: p.pos.map, bc: p.view.bc }));

R.check('không lỗi JS', P.errors.length === 0, P.errors.join(' | '));
await R.done(browser);
