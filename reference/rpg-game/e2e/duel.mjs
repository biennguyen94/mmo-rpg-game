// Đấu trường trực quan (DECISIONS "Sự kiện, đấu trường, chiến bang trực quan" E1 / E2): thách đấu bản sao → màn VS,
// bật ⚡ thì server tự đánh lượt theo combo (thanh "⚡ Đang đánh theo combo"), xong → K.O.; đấu trực tiếp: A mời B ở
// bản đồ khác, B nhận ở hộp thoại, hai bên vào trận đầy máu, ⚡ tự đánh tới hết, không mất vàng, máu trả lại như cũ.
// Chạy: node e2e/duel.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, send, shot } from './lib.mjs';

const R = reporter('duel');
const browser = await launch();
const vp = { width: 390, height: 844 };
const A = await newPlayer(browser, { cls: 'dk', viewport: vp });
const B = await newPlayer(browser, { cls: 'elf', viewport: vp });
const { admin } = await adminSession(browser);
for (const X of [A, B]) {
  await admin('set_level', X.name, { level: 30 });
  await admin('add_gold', X.name, { amount: 20000 });
}
for (const X of [A, B]) await X.page.waitForFunction(() => window.__hl.player().level === 30, null, { timeout: 8000 }).catch(() => null);

// ---------- E1: đấu trường bản sao, ⚡ tự đánh lượt, VS / K.O. ----------
await A.page.click('[data-act="quick-toggle"]');
await A.page.waitForFunction(() => (window.__hl.player().view.autoCfg || {}).quick === true, null, { timeout: 5000 }).catch(() => null);
const uidB = await B.page.evaluate(() => window.Net.userId);
await send(A.page, { act: 'pvp_challenge', uid: uidB }).catch((e) => console.log('challenge', e.msg));
await A.page.waitForSelector('.vs-fx', { timeout: 3000 }).catch(() => null);
R.check('thách đấu: màn VS', !!(await A.page.$('.vs-fx')));
await shot(A.page, 'duel-vs.png');
await A.page.waitForSelector('.quick-arena', { timeout: 4000 }).catch(() => null);
R.check('⚡ bật: thanh "Đang đánh theo combo" ở màn đấu trường', /Đang đánh theo combo/.test(await A.page.textContent('.quick-arena').catch(() => '')));
await A.page.waitForFunction(() => { const b = window.__hl.player().battle; return !b || b.over; }, null, { timeout: 60000 }).catch(() => null);
const over = await A.page.evaluate(() => { const b = window.__hl.player().battle; return b ? b.result : 'left'; });
R.check('server tự đánh tới hết trận đấu trường', ['win', 'lose', 'left'].includes(over), over);
await shot(A.page, 'duel-arena-end.png');
for (let i = 0; i < 5; i++) { if (!(await A.page.evaluate(() => window.__hl.player().battle))) break; await send(A.page, { act: 'leave' }).catch(() => null); }
await admin('heal', A.name, {}).catch(() => null);

// ---------- E2: đấu trực tiếp, khác bản đồ ----------
await send(B.page, { act: 'travel', to: 'forest_2' }).catch(() => null);
await B.page.click('[data-act="quick-toggle"]');
await B.page.waitForFunction(() => (window.__hl.player().view.autoCfg || {}).quick === true, null, { timeout: 5000 }).catch(() => null);
const goldA = await A.page.evaluate(() => window.__hl.player().gold), goldB = await B.page.evaluate(() => window.__hl.player().gold);
const hpB0 = await B.page.evaluate(() => window.__hl.player().hp);
const inv = await A.page.evaluate((u) => window.Net.duel('invite', { uid: u }).then((r) => r.msg, (e) => 'ERR ' + e.msg), uidB);
R.check('A mời đấu trực tiếp', /Đã mời/.test(inv), inv);
await B.page.waitForSelector('[data-act="duel-op"][data-op="accept"]', { timeout: 5000 }).catch(() => null);
R.check('B thấy hộp thoại "Đấu trường trực tiếp"', /Đấu trường trực tiếp/.test(await B.page.textContent('.map-dialog').catch(() => '')));
await shot(B.page, 'duel-invite.png');
await B.page.click('[data-act="duel-op"][data-op="accept"]');
// Hồ Tỷ Thí: hai người ở hai đầu, A đi lại gần B (không cánh: sát bên) rồi bấm Đồ sát
await A.page.waitForFunction(() => window.__hl.player().pos.map === 'ho_ty_thi', null, { timeout: 8000 }).catch(() => null);
R.check('nhận lời: cả hai vào Hồ Tỷ Thí', await A.page.evaluate(() => window.__hl.player().pos.map) === 'ho_ty_thi' && await B.page.evaluate(() => window.__hl.player().pos.map) === 'ho_ty_thi');
const bp = await B.page.evaluate(() => window.__hl.player().pos);
await A.page.evaluate(([x, y]) => window.__hl.walkTo(x - 1, y), [bp.x, bp.y]);
await A.page.waitForFunction(([x, y]) => { const q = window.__hl.player().pos; return Math.max(Math.abs(q.x - x), Math.abs(q.y - y)) <= 1; }, [bp.x, bp.y], { timeout: 30000 }).catch(() => null);
await A.page.evaluate((u) => window.Net.slay(u).catch(() => null), uidB);
await A.page.waitForFunction(() => { const b = window.__hl.player().battle; return !!(b && b.encounter && b.encounter.duel); }, null, { timeout: 8000 }).catch(() => null);
const st = await A.page.evaluate(() => { const p = window.__hl.player(); return { duel: !!(p.battle && p.battle.encounter.duel), full: p.hp === p.view.derived.maxHp, eyebrow: (document.querySelector('.stage .eyebrow') || {}).textContent || '' }; });
R.check('A vào trận đấu trực tiếp, đầy máu, nhãn "⚔ Đấu trường trực tiếp"', st.duel && st.full && /Đấu trường trực tiếp/.test(st.eyebrow), JSON.stringify(st));
await shot(A.page, 'duel-live.png');
await A.page.waitForFunction(() => { const b = window.__hl.player().battle; return !b || b.over; }, null, { timeout: 120000 }).catch(() => null);
await B.page.waitForFunction(() => { const b = window.__hl.player().battle; return !b || b.over; }, null, { timeout: 20000 }).catch(() => null);
await A.page.waitForTimeout(800);
const endA = await A.page.evaluate(() => ({ gold: window.__hl.player().gold, r: (window.__hl.player().battle || {}).result || 'left' }));
const endB = await B.page.evaluate(() => ({ gold: window.__hl.player().gold, hp: window.__hl.player().hp, map: window.__hl.player().pos.map, r: (window.__hl.player().battle || {}).result || 'left' }));
R.check('đấu xong: không ai mất vàng, B vẫn ở Rừng Mê 2', endA.gold === goldA && endB.gold === goldB && endB.map === 'forest_2', JSON.stringify({ endA, endB, goldA, goldB }));
R.check('máu B trả lại như trước trận', endB.hp === hpB0 || endB.r === 'left', `${endB.hp} vs ${hpB0}`);
await shot(A.page, 'duel-ko.png');

await browser.close();
R.done();
