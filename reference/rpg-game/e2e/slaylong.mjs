// Đồ sát nhanh (⚡) trận dài giữa hai nhân vật ngang nhau: nhật ký trận đầy 60 dòng rồi vẫn có hiệu ứng đòn trên bản đồ
// (trước đây dòng mới tính theo số dòng nên nhật ký đầy là mất hết hiệu ứng; DECISIONS "Hiệu ứng đòn cuối trên bản đồ").
// Chạy: node e2e/slaylong.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, send, shot } from './lib.mjs';

const R = reporter('slaylong');
const browser = await launch();
const { admin } = await adminSession(browser);
const A = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
const B = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
for (const X of [A, B]) {
  await admin('set_level', X.name, { level: 30 });
  await admin('add_stats', X.name, { vit: 3000 });
}
for (const X of [A, B]) {
  await X.page.waitForFunction(() => window.__hl.player().level === 30, null, { timeout: 10000 });
  await X.page.evaluate(() => localStorage.setItem('hl-fx', '1'));
  await send(X.page, { act: 'travel', to: 'forest_2' }).catch(() => null);
  await X.page.waitForFunction(() => window.__hl.player().pos.map === 'forest_2', null, { timeout: 8000 }).catch(() => null);
  await X.page.click('#tabs [data-tab="map"]').catch(() => null);
  await X.page.click('[data-act="quick-toggle"]');
  await X.page.waitForFunction(() => (window.__hl.player().view.autoCfg || {}).quick === true, null, { timeout: 5000 }).catch(() => null);
}
await A.page.evaluate(() => {
  window.__runs = [];
  const orig = window.BattleFx.run;
  window.BattleFx.run = function (ev, at) {
    const b = window.__hl.player().battle;
    window.__runs.push({ n: ((b && b.log) || []).length, hit: ev.some((e) => e.type === 'attack' || e.type === 'skill') });
    return orig.call(this, ev, at);
  };
});
// A lại gần B rồi bấm Đồ sát nhanh
await A.page.waitForFunction((n) => window.__hl.world().players.some((o) => o.name === n), B.name, { timeout: 8000 }).catch(() => null);
const bp = await B.page.evaluate(() => window.__hl.player().pos);
await A.page.evaluate(([x, y]) => window.__hl.walkTo(x, y), [bp.x, bp.y]);
const onScreen = () => A.page.evaluate(([x, y]) => { const s = window.MapView.screenOf(x, y); return s.x > 20 && s.x < innerWidth - 20 && s.y > 80 && s.y < innerHeight - 120; }, [bp.x, bp.y]);
for (let i = 0; i < 60 && !(await onScreen()); i++) await A.page.waitForTimeout(250);
const bp2 = await B.page.evaluate(() => window.__hl.player().pos);
const s = await A.page.evaluate(([x, y]) => window.MapView.screenOf(x, y), [bp2.x, bp2.y]);
await A.page.mouse.click(s.x, s.y);
await A.page.waitForSelector('.pick-pop', { timeout: 3000 }).catch(() => null);
const row = await A.page.$(`.pick-pop [data-act="pick-sel"]:has-text("${B.name}")`);
if (row) await row.click();
await A.page.click('.pick-pop [data-act="pick-slay"]').catch(() => null);
R.check('vào trận đồ sát nhanh', await A.page.waitForFunction(() => !!(window.__hl.player().battle || {}).live, null, { timeout: 30000 }).then(() => true).catch(() => false));
// chờ nhật ký đầy 60 dòng, rồi đánh thêm một lúc
const full = await A.page.waitForFunction(() => ((window.__hl.player().battle || {}).log || []).length >= 60, null, { timeout: 240000 }).then(() => true).catch(() => false);
R.check('trận đủ dài: nhật ký đầy 60 dòng', full, String(await A.page.evaluate(() => ((window.__hl.player().battle || {}).log || []).length)));
const t0 = await A.page.evaluate(() => window.__runs.length);
await A.page.waitForTimeout(15000);
const after = await A.page.evaluate((t0) => window.__runs.slice(t0), t0);
await shot(A.page, 'slaylong.png');
R.check('nhật ký đầy rồi vẫn có hiệu ứng đòn', after.filter((r) => r.hit).length >= 3, JSON.stringify(after.slice(0, 10)));
R.check('không lỗi JS', A.errors.length === 0, A.errors.join(' | '));
await R.done(browser);
