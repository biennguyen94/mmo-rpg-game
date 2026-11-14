// Đấu trường (đánh bản sao người chơi khác, `monster.pvp`): kỹ năng của đối thủ có hiệu ứng như đồ sát — hạt theo hệ bay
// từ đối thủ về mình, vòng niệm chú dưới chân đối thủ, sóng + dấu dưới chân mình (DECISIONS "Hiệu ứng kỹ năng đối thủ ở
// đấu trường"). Trước đây đấu trường chỉ rung "bị đánh".
// Chạy: node e2e/arenafx.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, act, send, shot } from './lib.mjs';

const R = reporter('arenafx');
const browser = await launch();
const { admin } = await adminSession(browser);
const A = await newPlayer(browser, { cls: 'dk', viewport: { width: 800, height: 900 } });
const B = await newPlayer(browser, { cls: 'dw', viewport: { width: 390, height: 844 } });
// A trâu (đánh được nhiều lượt), B Phù Thủy nhiều MP để bản sao dùng kỹ năng
await admin('set_level', A.name, { level: 40 });
await admin('add_stats', A.name, { vit: 1500, str: 50 });
await admin('set_level', B.name, { level: 40 });
await admin('add_stats', B.name, { ene: 600 });
await A.page.waitForFunction(() => window.__hl.player().level === 40, null, { timeout: 10000 });
await B.page.waitForFunction(() => window.__hl.player().level === 40, null, { timeout: 10000 });
const uidB = await B.page.evaluate(() => window.Net.userId);
await A.page.evaluate(() => localStorage.setItem('hl-fx', '1'));
await A.page.evaluate(() => {
  window.__ev = [];
  const orig = window.BattleFx.run;
  window.BattleFx.run = function (ev, at) { window.__ev.push(...(ev || []).map((e) => ({ type: e.type, rev: !!e.rev, el: e.element }))); return orig.call(this, ev, at); };
});
const r = await send(A.page, { act: 'pvp_challenge', uid: uidB }).catch((e) => ({ msg: e.msg }));
await A.page.waitForFunction(() => !!(window.__hl.player().battle || {}).monster?.pvp, null, { timeout: 8000 }).catch(() => null);
R.check('vào trận đấu trường với bản sao B', !!((await player(A.page)).battle || {}).monster?.pvp, JSON.stringify(r));
let foeSkill = 0;
for (let i = 0; i < 25; i++) {
  const b = (await player(A.page)).battle;
  if (!b || b.over) break;
  await act(A.page, 'attack');
  await A.page.waitForTimeout(700);
  foeSkill = (await player(A.page)).battle?.log?.filter((l) => l.who === 'foe' && l.act && l.dmg > 0).length || 0;
  if (foeSkill && i > 2) break;
}
await shot(A.page, 'arenafx.png');
const ev = await A.page.evaluate(() => window.__ev);
R.check('đối thủ đã dùng kỹ năng gây sát thương', foeSkill > 0, String(foeSkill));
R.check('kỹ năng đối thủ có hiệu ứng theo hệ bay về mình (rev)', ev.some((e) => e.type === 'skill' && e.rev), JSON.stringify(ev.slice(-12)));
R.check('không lỗi JS', A.errors.length === 0, A.errors.join(' | '));
await R.done(browser);
