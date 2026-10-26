// Sự kiện đánh chung theo phòng (DECISIONS "Sự kiện đánh chung theo phòng"): hai người cùng mốc chuyển sinh vào Quảng
// Trường Quỷ thì chung một phòng — cùng bản đồ, cùng quái, thấy nhau trên bản đồ, nhãn phòng "CS 0–1 · 2 người"; người
// CS 2 vào phòng khác. Hạ quái của phòng: quái biến mất ở cả hai bên.
// Server cần chạy với HL_DS_OPEN=1 (Quảng Trường luôn mở; CI đặt sẵn).
// Chạy: node e2e/eventroom.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, act, travel, meetNpc, walkTo, fight, shot } from './lib.mjs';

const R = reporter('eventroom');
const browser = await launch();
const A = await newPlayer(browser, { cls: 'dk' });
const B = await newPlayer(browser, { cls: 'elf' });
const C = await newPlayer(browser, { cls: 'dw' });
const { admin } = await adminSession(browser);

for (const X of [A, B, C]) {
  await admin('set_level', X.name, { level: 40 });
  await admin('add_stats', X.name, { str: 400, vit: 300, agi: 100 });
  await admin('give_item', X.name, { id: 'ds_ticket', count: 1 });
  await admin('heal', X.name, {});
}
await admin('set_rebirths', C.name, { n: 2 });

async function enter(X) {
  const page = X.page;
  await page.waitForFunction(() => (window.__hl.player().inv || {}).ds_ticket >= 1, null, { timeout: 8000 }).catch(() => null);
  if ((await player(page)).pos.map !== 'village') await travel(page, 'village');
  await meetNpc(page, 'tower_guard');
  await page.waitForSelector('[data-act="ds_enter"]:not([disabled])', { timeout: 5000 }).catch(() => null);
  await act(page, 'ds_enter');
  await page.waitForFunction(() => window.__hl.player().pos.map === 'tower', null, { timeout: 5000 }).catch(() => null);
  return player(page);
}

const pa = await enter(A);
const pb = await enter(B);
const pc = await enter(C);
R.check('A, B (CS 0) cùng phòng: cùng bản đồ, cùng quái', pa.tower && pb.tower && pa.tower.room === pb.tower.room && JSON.stringify(pa.tower.tiles) === JSON.stringify(pb.tower.tiles), JSON.stringify([pa.tower && pa.tower.room, pb.tower && pb.tower.room]));
R.check('C (CS 2) phòng khác, quái mạnh theo mốc CS 3', pc.tower && pc.tower.room !== pa.tower.room && pc.tower.k === 3 && pa.tower.k === 1, JSON.stringify([pc.tower && pc.tower.room, pc.tower && pc.tower.k]));

// A thấy B trên bản đồ (kênh của phòng), nhãn phòng có số người
const bId = await B.page.evaluate(() => window.__hl.userId());
await A.page.waitForFunction((id) => (window.__hl.world().players || []).some((o) => o.id === id), bId, { timeout: 5000 }).catch(() => null);
const seen = await A.page.evaluate((id) => (window.__hl.world().players || []).some((o) => o.id === id), bId);
R.check('A thấy B trên bản đồ phòng', seen);
// chạy lại trong cùng đợt mở thì người của lần trước vẫn còn trong phòng: ít nhất 2 người
const people = () => +(((document.querySelector('#app') || {}).textContent || '').match(/Phòng CS 0–1 · (\d+) người/) || [])[1] || 0;
await A.page.waitForFunction(people, null, { timeout: 5000 }).catch(() => null);
await A.page.waitForFunction((f) => new Function('return ' + f)()() >= 2, people.toString(), { timeout: 5000 }).catch(() => null);
const hud = (await A.page.textContent('#app').catch(() => '')) || '';
const nPeople = +(hud.match(/Phòng CS 0–1 · (\d+) người/) || [])[1] || 0;
R.check('dòng trạng thái: "Phòng CS 0–1 · N người" (N ≥ 2)', nPeople >= 2, hud.match(/Phòng[^·]*·[^·]*/)?.[0] || '');
await shot(A.page, 'eventroom-shared.png');

// A hạ một con: biến mất ở cả B
const m = pa.tower.monsters[0];
await walkTo(A.page, m.x, m.y);
await A.page.waitForFunction(() => !!window.__hl.player().battle, null, { timeout: 6000 }).catch(() => null);
const res = await fight(A.page);
await act(A.page, 'leave').catch(() => null);
R.check('A hạ quái của phòng', res === 'win', String(res));
await B.page.waitForFunction((id) => !window.__hl.player().tower.monsters.some((q) => q.id === id), m.id, { timeout: 5000 }).catch(() => null);
const pb2 = await player(B.page);
R.check('quái A hạ biến mất ở B, điểm là của A', !pb2.tower.monsters.some((q) => q.id === m.id) && pb2.tower.ds.score === 0 && (await player(A.page)).tower.ds.score > 0, JSON.stringify({ left: pb2.tower.monsters.length, scoreB: pb2.tower.ds.score }));

// A, B cùng đánh một con: B ra đòn thì màn trận của A tụt máu ngay (không đợi A đánh), ghi "2 người cùng đánh"
const m2 = (await player(A.page)).tower.monsters[0];
await walkTo(A.page, m2.x, m2.y);
await A.page.waitForFunction(() => !!window.__hl.player().battle, null, { timeout: 6000 }).catch(() => null);
await walkTo(B.page, m2.x, m2.y);
await B.page.waitForFunction(() => !!window.__hl.player().battle, null, { timeout: 6000 }).catch(() => null);
const hpA = (await player(A.page)).battle?.monster.hp;
for (let i = 0; i < 5; i++) {
  await act(B.page, 'attack');
  const ok = await A.page.waitForFunction((h) => { const b = window.__hl.player().battle; return b && (b.over || b.monster.hp < h); }, hpA, { timeout: 1500 }).then(() => true).catch(() => false);
  if (ok) break;
}
const pa2 = await player(A.page);
R.check('B đánh: máu quái trên màn trận của A tụt ngay', pa2.battle && (pa2.battle.over || pa2.battle.monster.hp < hpA), JSON.stringify({ before: hpA, after: pa2.battle && pa2.battle.monster.hp }));
// sau lần đồng bộ phòng kế tiếp (đẩy cả nhân vật) máu vẫn là máu mới, không nhảy về đầy
await A.page.waitForTimeout(600);
const pa3 = await player(A.page);
R.check('đồng bộ phòng sau đó không trả máu cũ', pa3.battle && (pa3.battle.over || pa3.battle.monster.hp < hpA), JSON.stringify({ before: hpA, later: pa3.battle && pa3.battle.monster.hp }));
const eyebrow = (await A.page.textContent('.eyebrow').catch(() => '')) || '';
R.check('màn trận ghi "2 người cùng đánh"', pa2.battle.over || eyebrow.includes('2 người cùng đánh'), eyebrow);
await shot(A.page, 'eventroom-shared-fight.png');

for (const X of [A, B, C]) R.check(`không lỗi JS (${X.name})`, X.errors.length === 0, X.errors.join(' | '));
await R.done(browser);
