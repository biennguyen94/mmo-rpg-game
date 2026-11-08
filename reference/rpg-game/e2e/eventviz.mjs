// Sự kiện, đấu trường, chiến bang trực quan — Đợt 1 hiển thị (DECISIONS "Sự kiện, đấu trường, chiến bang trực quan"):
// trùm thế giới to trên Tế Đàn + thanh sự kiện (máu %, top sát thương), ⚡ đánh trùm ngay trên bản đồ; chiến bang:
// thanh tỉ số, vòng đỏ người bang địch; Công Thành Chiến: thanh Vương Miện, màu bang; điểm trên bản đồ nhỏ.
// Chạy: node e2e/eventviz.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, send, shot, meetNpc, leaveNpc } from './lib.mjs';

const R = reporter('eventviz');
const browser = await launch();
const vp = { width: 390, height: 844 };
const A = await newPlayer(browser, { cls: 'dk', viewport: vp });
const C = await newPlayer(browser, { cls: 'elf', viewport: vp });
const { admin } = await adminSession(browser);
for (const X of [A, C]) {
  await admin('set_level', X.name, { level: 45 });
  await admin('add_gold', X.name, { amount: 3000000 });
  await admin('give_item', X.name, { id: 'potion_m', count: 30 });
}
await admin('set_level', A.name, { level: 150 });
for (const X of [A, C]) await X.page.waitForFunction(() => window.__hl.player().level >= 45 && window.__hl.player().gold >= 3000000, null, { timeout: 8000 }).catch(() => null);
const hud = (X) => X.page.evaluate(() => window.MapView.hudLines());

// ---------- C1 / C2: trùm thế giới ----------
await admin('world_boss_off', A.name).catch(() => null);
await admin('world_boss', A.name).catch(() => null);
await send(A.page, { act: 'travel', to: 'altar' }).catch(() => null);
await A.page.waitForFunction(() => window.__hl.player().pos.map === 'altar', null, { timeout: 8000 }).catch(() => null);
await A.page.click('#tabs [data-tab="map"]').catch(() => null);
await A.page.waitForTimeout(700);
let h = await hud(A);
R.check('Tế Đàn: thanh sự kiện có trùm thế giới + % máu', h.some((l) => /🐉 .*\d+%/.test(l)), JSON.stringify(h));
await shot(A.page, 'eventviz-boss.png');
// ⚡ bật rồi bấm vào trùm: đánh ngay trên bản đồ
await A.page.click('[data-act="quick-toggle"]');
await A.page.waitForFunction(() => (window.__hl.player().view.autoCfg || {}).quick === true, null, { timeout: 5000 }).catch(() => null);
const wb = await A.page.evaluate(() => window.GAME_DATA.WORLD.maps.altar.worldBoss);
const s = await A.page.evaluate(([x, y]) => window.MapView.screenOf(x, y), wb);
await A.page.mouse.click(s.x, s.y);
await A.page.waitForFunction(() => !!window.__hl.player().battle, null, { timeout: 15000 }).catch(() => null);
await A.page.waitForTimeout(1200);
const mid = await A.page.evaluate(() => ({ battle: !!window.__hl.player().battle, world: !!(window.__hl.player().battle || { monster: {} }).monster.world, map: !!document.querySelector('#map-canvas'), atk: !!document.querySelector('[data-act="attack"]'), f: window.MapView.fightTarget() }));
R.check('⚡ bấm trùm thế giới: vào trận, ở lại bản đồ, đánh dấu con đang đánh "boss"', mid.battle && mid.world && mid.map && !mid.atk && mid.f && mid.f.id === 'boss', JSON.stringify(mid));
await A.page.waitForFunction(() => window.MapView.hudLines().some((l) => l.includes('★')), null, { timeout: 6000 }).catch(() => null);
h = await hud(A);
R.check('top sát thương có tên mình (★)', h.some((l) => l.includes('★')), JSON.stringify(h));
await shot(A.page, 'eventviz-boss-fight.png');
await A.page.click('[data-act="quick-toggle"]').catch(() => null);
await A.page.waitForFunction(() => (window.__hl.player().view.autoCfg || {}).quick !== true, null, { timeout: 5000 }).catch(() => null);
for (let i = 0; i < 20; i++) {
  const b = await A.page.evaluate(() => window.__hl.player().battle);
  if (!b) break;
  await send(A.page, { act: b.over ? 'leave' : 'flee' }).catch(() => null);
}

// ---------- F1: chiến bang ----------
const tagA = 'A' + String(Date.now()).slice(-3), tagC = 'C' + String(Date.now()).slice(-3);
await send(A.page, { act: 'guild_create', name: 'Bang ' + tagA, tag: tagA });
await send(C.page, { act: 'guild_create', name: 'Bang ' + tagC, tag: tagC });
const war = await A.page.evaluate((t) => window.Net.guild('war_declare', { tag: t }).then(() => 'ok', (e) => e.msg), tagC);
const acc = await C.page.evaluate(() => window.Net.guild('war_accept').then(() => 'ok', (e) => e.msg));
R.check('tuyên chiến + nhận', war === 'ok' && acc === 'ok', `${war} / ${acc}`);
for (const X of [A, C]) {
  await X.page.waitForFunction(() => !!(window.__hl.player().guild || {}).war, null, { timeout: 8000 }).catch(() => null);
  await send(X.page, { act: 'travel', to: 'forest_2' }).catch(() => null);
  await X.page.waitForFunction(() => window.__hl.player().pos.map === 'forest_2', null, { timeout: 8000 }).catch(() => null);
  await X.page.click('#tabs [data-tab="map"]').catch(() => null);
}
await A.page.waitForTimeout(800);
h = await hud(A);
R.check('thanh chiến bang: "⚔ [A] 0 – 0 [C]"', h.some((l) => l.includes(`[${tagA}] 0 – 0 [${tagC}]`)), JSON.stringify(h));
await A.page.waitForFunction((n) => window.__hl.world().players.some((o) => o.name === n), C.name, { timeout: 8000 }).catch(() => null);
await shot(A.page, 'eventviz-war.png');

// ---------- D1 / D2: Công Thành Chiến ----------
await admin('open_cs', A.name);
for (const X of [A, C]) {
  await send(X.page, { act: 'travel', to: 'village' }).catch(() => null);
  await X.page.waitForFunction(() => window.__hl.player().pos.map === 'village', null, { timeout: 8000 }).catch(() => null);
  await meetNpc(X.page, 'tower_guard');
  const r = await send(X.page, { act: 'cs_enter' }).catch((e) => ({ msg: e.msg }));
  await X.page.waitForFunction(() => window.__hl.player().pos.map === 'castle_siege', null, { timeout: 8000 }).catch(() => null);
  if ((await X.page.evaluate(() => window.__hl.player().pos.map)) !== 'castle_siege') console.log('cs_enter', r && r.msg);
  await X.page.click('#tabs [data-tab="map"]').catch(() => null);
}
await A.page.waitForTimeout(900);
h = await hud(A);
R.check('Công Thành: thanh "👑 Vương Miện chưa có chủ" + giờ', h.some((l) => /👑 Vương Miện chưa có chủ.*\d+:\d\d/.test(l)), JSON.stringify(h));
const crown = await A.page.evaluate(() => window.__hl.world().monsters.some((q) => q.kind === window.GAME_DATA.RULES.castleSiege.crownKind));
R.check('Vương Miện có trên bản đồ', crown);
await shot(A.page, 'eventviz-cs.png');
// D3: chạm người bang khác trong Công Thành → đồ sát ngay (không mở menu)
const cpos = await C.page.evaluate(() => window.__hl.player().pos);
await A.page.waitForFunction(([x, y, n]) => window.MapView.playersNear(x, y).some((o) => o.name === n), [cpos.x, cpos.y, C.name], { timeout: 6000 }).catch(() => null);
const sc = await A.page.evaluate(([x, y]) => window.MapView.screenOf(x, y), [cpos.x, cpos.y]);
await A.page.mouse.click(sc.x, sc.y);
await A.page.waitForFunction(() => { const b = window.__hl.player().battle; return !!(b && b.encounter && b.encounter.slay != null); }, null, { timeout: 12000 }).catch(() => null);
const d3 = await A.page.evaluate(() => ({ slay: !!((window.__hl.player().battle || {}).encounter || {}).slay, pop: !!document.querySelector('.pick-pop') }));
R.check('Công Thành: chạm người bang khác → đồ sát ngay, không menu', d3.slay && !d3.pop, JSON.stringify(d3));
await shot(A.page, 'eventviz-cs-slay.png');

await browser.close();
R.done();
