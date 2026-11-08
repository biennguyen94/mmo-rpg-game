// ⚡ Đánh nhanh theo combo (DECISIONS "Đánh nhanh theo combo"): bật nút ⚡ ở bản đồ, sắp combo ở Menu → Kỹ năng, bấm
// (đi tới) quái → server tự đánh hết trận theo combo, vẫn ở màn bản đồ (không mở màn trận), xong trận báo kết quả và có
// nút 📜 xem nhật ký; ✋ Đánh tay giữa trận thì mở màn trận như thường.
// Chạy: node e2e/quick.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, send, act, shot, meetNpc } from './lib.mjs';

const R = reporter('quick');
const browser = await launch();
const X = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
const { admin } = await adminSession(browser);
const p = X.page;
await admin('set_level', X.name, { level: 30 });
await admin('add_stats', X.name, { str: 120, vit: 80, agi: 30 });
await admin('give_item', X.name, { id: 'potion_l', count: 30 });
await admin('add_gold', X.name, { amount: 100000 });
await p.waitForFunction(() => window.__hl.player().level === 30, null, { timeout: 10000 });

// combo: Menu → Kỹ năng → ⚡ Combo đánh nhanh: thêm 2 bước (kỹ năng đầu bộ, đòn thường) rồi lưu
await p.click('#tabs [data-tab="menu"]');
await p.click('[data-menu="skills"]');
await p.waitForSelector('#combo-card');
await p.click('[data-act="combo-add"]');
await p.click('[data-act="combo-add"]');
await p.selectOption('[data-combo-id="1"]', 'attack');
await p.click('[data-act="combo-save"]');
await p.waitForFunction(() => ((window.__hl.player().view.autoCfg || {}).combo || []).length === 2, null, { timeout: 5000 }).catch(() => null);
const combo = await p.evaluate(() => (window.__hl.player().view.autoCfg || {}).combo);
R.check('lưu combo 2 bước (kỹ năng → đòn thường)', combo && combo.length === 2 && combo[1].id === 'attack', JSON.stringify(combo));

// ra bản đồ có quái, bật ⚡
const tr = await send(p, { act: 'travel', to: 'graveyard_1' }).catch((e) => ({ msg: e.msg }));
await p.click('#tabs [data-tab="map"]');
await p.waitForSelector('[data-act="quick-toggle"]');
await p.click('[data-act="quick-toggle"]');
await p.waitForFunction(() => (window.__hl.player().view.autoCfg || {}).quick === true, null, { timeout: 5000 }).catch(() => null);
R.check('dịch chuyển tới Nghĩa Địa', (await p.evaluate(() => window.__hl.player().pos.map)) === 'graveyard_1', tr.msg || '');
await p.evaluate(() => document.querySelector('#auto-bar').scrollIntoView({ block: 'end' }));
await shot(p, 'quick-bar.png');
R.check('nút ⚡ bật Đánh nhanh (chung hàng với 🤖 Tự đánh)', (await p.getAttribute('#auto-bar [data-act="quick-toggle"]', 'aria-pressed')) === 'true' && !(await p.$('#quick-bar')));

async function startFight() {
  for (let i = 0; i < 8; i++) {
    const w = await p.evaluate(() => window.__hl.world());
    const me = (await p.evaluate(() => window.__hl.player())).pos;
    const mons = (w.monsters || []).filter((m) => w.map === me.map && !m.busy && !m.boss);
    if (!mons.length) { await p.waitForTimeout(600); continue; }
    mons.sort((a, b) => Math.abs(a.x - me.x) + Math.abs(a.y - me.y) - (Math.abs(b.x - me.x) + Math.abs(b.y - me.y)));
    await p.evaluate(([x, y]) => window.__hl.walkTo(x, y), [mons[0].x, mons[0].y]);
    const ok = await p.waitForFunction(() => !!window.__hl.player().battle, null, { timeout: 15000 }).then(() => true).catch(() => false);
    if (ok) return true;
  }
  return false;
}

// hiệu ứng trận (fx.js) phát trên bản đồ: ghi lại các lần phát và có vị trí bám vào quái / mình không
await p.evaluate(() => {
  localStorage.setItem('hl-fx', '1');
  const run = window.BattleFx.run;
  window.__fx = [];
  window.BattleFx.run = (ev, at) => { const a = at && at(); window.__fx.push({ types: ev.map((e) => e.type), mon: !!(a && a.mon), me: !!(a && a.me) }); return run(ev, at); };
});
const kills0 = await p.evaluate(() => window.__hl.player().kills);
R.check('bấm quái: vào trận', await startFight());
await p.waitForTimeout(400);
R.check('vẫn ở màn bản đồ (không mở màn trận), thanh "Đang đánh"', !!(await p.$('#map-canvas')) && /Đang đánh/.test(await p.textContent('#auto-bar').catch(() => '')));
await p.waitForTimeout(900);
await shot(p, 'quick-fighting.png');
await p.waitForFunction(() => !window.__hl.player().battle, null, { timeout: 60000 }).catch(() => null);
const after = await p.evaluate(() => ({ battle: !!window.__hl.player().battle, kills: window.__hl.player().kills }));
R.check('server tự đánh hết trận và rời màn trận', !after.battle && after.kills > kills0, JSON.stringify({ ...after, kills0 }));
const fxs = await p.evaluate(() => window.__fx);
const types = fxs.flatMap((f) => f.types);
R.check('hiệu ứng kỹ năng / đòn đánh phát trên bản đồ, bám vào quái và mình', fxs.some((f) => f.mon && f.me) && types.some((t) => t === 'skill' || t === 'attack') && types.includes('kill'), JSON.stringify(types));
await p.waitForSelector('[data-act="quick-log"]', { timeout: 3000 }).catch(() => null);
R.check('có nút 📜 xem nhật ký trận vừa xong', !!(await p.$('[data-act="quick-log"]')));
await p.click('[data-act="quick-log"]').catch(() => null);
const log = await p.textContent('.quick-log').catch(() => '');
R.check('nhật ký trận vừa xong có dòng đánh', /gây ra|dùng/.test(log), log.slice(0, 120));
const sc = await p.evaluate(() => { const l = document.querySelector('.quick-log .log'); if (!l) return null; const cs = getComputedStyle(l); return { ov: cs.overflowY, fixed: getComputedStyle(l.parentElement).position }; });
R.check('nhật ký nổi trên bản đồ, cuộn được', sc && sc.fixed === 'fixed' && sc.ov === 'auto', JSON.stringify(sc));
await shot(p, 'quick-log.png');
await p.click('.quick-log [data-act="quick-log"]').catch(() => null);

// ✋ Đánh tay giữa trận: mở màn trận như thường, server thôi tự đánh
R.check('trận 2: vào trận', await startFight());
await p.waitForSelector('[data-act="quick-manual"]', { timeout: 3000 }).catch(() => null);
await p.click('[data-act="quick-manual"]').catch(() => null);
await p.waitForFunction(() => window.__hl.player().battle && window.__hl.player().battle.manual === true, null, { timeout: 5000 }).catch(() => null);
const manual = await p.evaluate(() => { const b = window.__hl.player().battle; return { manual: b && b.manual, turn: b && b.turn }; });
await p.waitForTimeout(2000);
const turn2 = await p.evaluate(() => (window.__hl.player().battle || {}).turn);
R.check('✋ Đánh tay: mở màn trận, server thôi tự đánh', manual.manual === true && !!(await p.$('[data-act="attack"]')) && turn2 === manual.turn, JSON.stringify({ ...manual, turn2 }));
for (let i = 0; i < 40; i++) { const b = (await p.evaluate(() => window.__hl.player().battle)); if (!b || b.over) break; await act(p, 'attack'); }
await act(p, 'leave').catch(() => null);
// 🗑 trên thanh ⚡: cho biết Tự hủy đồ rơi bật / tắt, bấm mở thẳng phần cài đặt
await p.click('#tabs [data-tab="map"]');
await p.waitForSelector('[data-act="quick-filter"]');
const f0 = await p.getAttribute('[data-act="quick-filter"]', 'aria-pressed');
await p.click('[data-act="quick-filter"]');
await p.waitForSelector('#loot-filter-card', { timeout: 3000 }).catch(() => null);
R.check('🗑 mở phần Tự hủy đồ rơi ở Cài đặt', !!(await p.$('#loot-filter-card')));
await p.click('#loot-filter-card [data-act="loot-filter"]');
await p.waitForFunction(() => ((window.__hl.player().view.autoCfg || {}).filter || {}).on === true, null, { timeout: 5000 }).catch(() => null);
await p.click('#tabs [data-tab="map"]');
await p.waitForSelector('[data-act="quick-filter"]');
const f1 = await p.getAttribute('[data-act="quick-filter"]', 'aria-pressed');
R.check('🗑 sáng khi Tự hủy đồ rơi đang bật', f0 === 'false' && f1 === 'true', `${f0} → ${f1}`);
// ⚙: cài đặt của cả hai, mỗi tính năng một nút 💾 Lưu, không còn "Bắt đầu tự đánh"
await p.click('#tabs [data-tab="map"]');
await p.click('[data-act="auto-set"]');
await p.waitForSelector('.auto-set');
R.check('⚙: có 💾 Lưu tự đánh và 💾 Lưu đánh nhanh, không có Bắt đầu tự đánh', !!(await p.$('.auto-set [data-act="auto-save"]')) && !!(await p.$('.auto-set [data-act="quick-save"]')) && !(await p.$('.auto-set [data-act="auto-on"]')));
await shot(p, 'quick-settings.png');
await p.click('.auto-set [data-act="auto-save"]');
await p.waitForTimeout(400);
R.check('💾 Lưu tự đánh không tự bắt đầu', !(await p.evaluate(() => window.__hl.player().auto)));
await p.click('.auto-set-head [data-act="auto-set"]').catch(() => null);

// 🤖 + ⚡ cùng bật: tự đánh theo combo, ở lại bản đồ (không mở bảng đánh quái)
await p.click('[data-act="auto-toggle"]');
await p.waitForFunction(() => !!window.__hl.player().auto, null, { timeout: 5000 }).catch(() => null);
R.check('nút 🤖 sáng khi bật', (await p.getAttribute('[data-act="auto-toggle"]', 'aria-pressed')) === 'true');
const k1 = await p.evaluate(() => window.__hl.player().kills);
let sawBattleView = false, sawMapFight = false;
for (let i = 0; i < 120; i++) {
  const st = await p.evaluate(() => ({ battle: !!window.__hl.player().battle, map: !!document.querySelector('#map-canvas'), atk: !!document.querySelector('[data-act="attack"]'), kills: window.__hl.player().kills }));
  if (st.battle && st.atk) sawBattleView = true;
  if (st.battle && st.map && !st.atk) sawMapFight = true;
  if (st.kills >= k1 + 2) break;
  await p.waitForTimeout(500);
}
const k2 = await p.evaluate(() => window.__hl.player().kills);
R.check('🤖 + ⚡: tự đánh hạ quái, ở lại bản đồ (không mở bảng đánh quái)', k2 > k1 && sawMapFight && !sawBattleView, JSON.stringify({ k1, k2, sawMapFight, sawBattleView }));
await p.click('[data-act="auto-toggle"]');
await p.waitForFunction(() => !window.__hl.player().auto, null, { timeout: 8000 }).catch(() => null);
R.check('nút 🤖 tối khi tắt', (await p.getAttribute('[data-act="auto-toggle"]', 'aria-pressed')) === 'false');
await p.waitForFunction(() => !window.__hl.player().battle, null, { timeout: 30000 }).catch(() => null);

// trong Tháp: đánh nhanh ở lại bản đồ, con đang đánh có thanh máu theo lượt
await send(p, { act: 'travel', to: 'village' }).catch(() => null);
await p.waitForFunction(() => window.__hl.player().pos.map === 'village', null, { timeout: 8000 }).catch(() => null);
await meetNpc(p, 'tower_guard');
const tw = await send(p, { act: 'tower_enter', floor: 1 }).catch((e) => ({ msg: e.msg }));
await p.evaluate(() => window.__hl.closeNpc && window.__hl.closeNpc());
await p.click('#tabs [data-tab="map"]').catch(() => null);
await p.waitForFunction(() => window.__hl.player().pos.map === 'tower', null, { timeout: 8000 }).catch(() => null);
R.check('vào Tháp', (await p.evaluate(() => window.__hl.player().pos.map)) === 'tower', tw.msg || '');
let towerFight = null;
for (let i = 0; i < 6 && !towerFight; i++) {
  const t = await p.evaluate(() => { const q = window.__hl.player(); return { me: q.pos, mons: (q.tower && q.tower.monsters) || [] }; });
  if (!t.mons.length) break;
  t.mons.sort((a, b) => Math.abs(a.x - t.me.x) + Math.abs(a.y - t.me.y) - (Math.abs(b.x - t.me.x) + Math.abs(b.y - t.me.y)));
  await p.evaluate(([x, y]) => window.__hl.walkTo(x, y), [t.mons[0].x, t.mons[0].y]);
  const ok = await p.waitForFunction(() => !!window.__hl.player().battle, null, { timeout: 12000 }).then(() => true).catch(() => false);
  if (ok) { await p.waitForTimeout(700); await shot(p, 'quick-tower.png'); }
  if (ok) towerFight = await p.evaluate(() => ({ map: !!document.querySelector('#map-canvas'), atk: !!document.querySelector('[data-act="attack"]'), enc: window.__hl.player().battle.encounter }));
}
R.check('Tháp: đánh nhanh ở lại bản đồ', towerFight && towerFight.map && !towerFight.atk && towerFight.enc && towerFight.enc.tower != null, JSON.stringify(towerFight));
await p.waitForFunction(() => !window.__hl.player().battle, null, { timeout: 60000 }).catch(() => null);
R.check('Tháp: đánh hết trận, rời màn trận', !(await p.evaluate(() => window.__hl.player().battle)));
R.check('không lỗi JS', X.errors.length === 0, X.errors.join(' | '));
await R.done(browser);
