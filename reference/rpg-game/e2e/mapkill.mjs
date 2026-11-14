// ⚡ Đánh nhanh trên bản đồ, nhân vật rất mạnh (CS 10, chỉ số tối đa) hạ quái / người một đòn
// (DECISIONS "Hiệu ứng đòn cuối trên bản đồ"):
// - vẫn có hiệu ứng đòn + gục (trước đây trận xong ngay lần trả đầu tiên thì không có hiệu ứng nào);
// - hiệu ứng luôn bám được vào chỗ đối phương (bản đồ xóa quái / người trước khi đòn bay tới thì vẫn giữ chỗ);
// - đối phương giữ hình đứng tới lúc đòn cuối trúng rồi mới mờ (người bị hạ cũng vậy, không biến mất ngay).
// Chạy: node e2e/mapkill.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, travel, send, shot } from './lib.mjs';

const R = reporter('mapkill');
const browser = await launch();
const { admin } = await adminSession(browser);

// ghi lại mỗi lần BattleFx.run: loại hiệu ứng, lúc đòn cuối trúng (hitUntil), hiệu ứng nào không tìm được chỗ bám;
// và các hình đang gục (MapView.dying) với lúc bắt đầu mờ
const instrument = (p) => p.evaluate(() => {
  window.__mk = { runs: [], ghosts: {} };
  const orig = window.BattleFx.run;
  window.BattleFx.run = function (ev, at) {
    // `at`: hiệu ứng bám vào bản đồ; không có thì phát theo màn trận (trên bản đồ không thấy gì)
    const rec = { t: performance.now(), types: ev.map((e) => e.type), miss: [], fid: (window.MapView.fightTarget() || {}).id, anchored: !!at };
    window.__mk.runs.push(rec);
    const r = orig.call(this, ev, at);
    rec.hu = window.BattleFx.hitUntil();
    if (at) for (const e of ev) setTimeout(() => { const a = at(); if (!a || !a.mon) rec.miss.push(e.type); }, (e.delay || 0) + 40);
    return r;
  };
  setInterval(() => {
    for (const g of window.MapView.dying()) {
      const r = window.__mk.ghosts[g.id] || (window.__mk.ghosts[g.id] = { first: performance.now() });
      r.t0 = g.t0;
    }
  }, 25);
});

async function strong(cls, name) {
  await admin('set_level', name, { level: 50 });
  await admin('set_rebirths', name, { n: 10 });
  await admin('add_stats', name, { str: 5000, agi: 3000, ene: 5000, vit: 2000 });
}

// ---------- quái ----------
{
  const X = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
  const p = X.page;
  await strong('dk', X.name);
  await p.waitForFunction(() => window.__hl.player().level === 50 && (window.__hl.player().rebirths || 0) >= 10, null, { timeout: 10000 });
  await p.evaluate(() => localStorage.setItem('hl-fx', '1'));
  await travel(p, 'forest_1');
  await p.click('#tabs [data-tab="map"]');
  await p.click('[data-act="quick-toggle"]');
  await p.waitForFunction(() => (window.__hl.player().view.autoCfg || {}).quick === true, null, { timeout: 5000 }).catch(() => null);
  await instrument(p);
  const kills = [];
  for (let i = 0; i < 12 && kills.length < 3; i++) {
    const w = await p.evaluate(() => window.__hl.world());
    const me = (await player(p)).pos;
    const mons = (w.monsters || []).filter((m) => !m.busy && !m.boss);
    if (!mons.length) { await p.waitForTimeout(800); continue; }
    mons.sort((a, b) => Math.abs(a.x - me.x) + Math.abs(a.y - me.y) - (Math.abs(b.x - me.x) + Math.abs(b.y - me.y)));
    const id = String(mons[0].id);
    const n0 = await p.evaluate(() => window.__mk.runs.length);
    await p.evaluate(([x, y]) => window.__hl.walkTo(x, y), [mons[0].x, mons[0].y]);
    // trận xong (một đòn) và hình gục mờ hết
    const done = await p.waitForFunction((n) => window.__mk.runs.slice(n).some((r) => r.anchored && r.types.includes('kill')), n0, { timeout: 15000 }).then(() => true).catch(() => false);
    if (!done) continue;
    if (kills.length === 0) for (let k = 0; k < 4; k++) { await p.waitForTimeout(120); await shot(p, `mapkill-mob-${k}.png`); }
    await p.waitForTimeout(2200);
    const r = await p.evaluate(([n, id]) => ({ run: window.__mk.runs.slice(n).find((x) => x.anchored && x.types.includes('kill')), nk: window.__mk.runs.slice(n).filter((x) => x.types.includes('kill')).length, g: window.__mk.ghosts[id] }), [n0, id]);
    kills.push({ id, ...r });
  }
  R.check('hạ quái một đòn: có hiệu ứng đòn + gục bám vào bản đồ (3 con)', kills.length === 3 && kills.every((k) => k.run.types.some((t) => t === 'attack' || t === 'skill')), JSON.stringify(kills.map((k) => k.run && k.run.types)));
  R.check('hiệu ứng gục mỗi con chỉ phát một lần', kills.length > 0 && kills.every((k) => k.nk === 1), JSON.stringify(kills.map((k) => k.nk)));
  R.check('hiệu ứng luôn bám được vào chỗ quái', kills.length > 0 && kills.every((k) => k.run.miss.length === 0), JSON.stringify(kills.map((k) => k.run && k.run.miss)));
  R.check('quái giữ hình tới lúc đòn cuối trúng rồi mới mờ', kills.length > 0 && kills.every((k) => k.g && k.g.t0 >= k.run.hu), JSON.stringify(kills.map((k) => k.g && { t0: Math.round(k.g.t0), hu: Math.round(k.run.hu) })));
  R.check('quái: không lỗi JS', X.errors.length === 0, X.errors.join(' | '));
  await X.ctx.close();
}

// ---------- người ----------
{
  const A = await newPlayer(browser, { cls: 'dw', viewport: { width: 390, height: 844 } });
  const B = await newPlayer(browser, { cls: 'elf', viewport: { width: 390, height: 844 } });
  await strong('dw', A.name);
  await admin('set_level', B.name, { level: 20 });
  for (const X of [A, B]) {
    await X.page.waitForFunction(() => window.__hl.player().level >= 20, null, { timeout: 10000 });
    await X.page.evaluate(() => localStorage.setItem('hl-fx', '1'));
    await send(X.page, { act: 'travel', to: 'forest_2' }).catch(() => null);
    await X.page.waitForFunction(() => window.__hl.player().pos.map === 'forest_2', null, { timeout: 8000 }).catch(() => null);
    await X.page.click('#tabs [data-tab="map"]').catch(() => null);
  }
  await A.page.click('[data-act="quick-toggle"]');
  await A.page.waitForFunction(() => (window.__hl.player().view.autoCfg || {}).quick === true, null, { timeout: 5000 }).catch(() => null);
  await instrument(A.page);
  await A.page.waitForFunction((n) => window.__hl.world().players.some((o) => o.name === n), B.name, { timeout: 8000 }).catch(() => null);
  const bid = await A.page.evaluate((n) => (window.__hl.world().players.find((o) => o.name === n) || {}).id, B.name);
  // B ngoài màn hình thì A đi lại gần trước
  const bp = await B.page.evaluate(() => window.__hl.player().pos);
  const onScreen = () => A.page.evaluate(([x, y]) => { const s = window.MapView.screenOf(x, y); return s.x > 20 && s.x < innerWidth - 20 && s.y > 80 && s.y < innerHeight - 120; }, [bp.x, bp.y]);
  if (!(await onScreen())) { await A.page.evaluate(([x, y]) => window.__hl.walkTo(x, y), [bp.x, bp.y]); for (let i = 0; i < 60 && !(await onScreen()); i++) await A.page.waitForTimeout(250); }
  const bp2 = await B.page.evaluate(() => window.__hl.player().pos);
  const s = await A.page.evaluate(([x, y]) => window.MapView.screenOf(x, y), [bp2.x, bp2.y]);
  await A.page.mouse.click(s.x, s.y);
  await A.page.waitForSelector('.pick-pop', { timeout: 3000 }).catch(() => null);
  const row = await A.page.$(`.pick-pop [data-act="pick-sel"]:has-text("${B.name}")`);
  if (row) await row.click();
  await A.page.click('.pick-pop [data-act="pick-slay"]').catch(() => null);
  const done = await A.page.waitForFunction(() => window.__mk.runs.some((r) => r.anchored && r.types.includes('kill')), null, { timeout: 40000 }).then(() => true).catch(() => false);
  for (let k = 0; k < 4 && done; k++) { await A.page.waitForTimeout(120); await shot(A.page, `mapkill-pvp-${k}.png`); }
  await A.page.waitForTimeout(2200);
  const r = await A.page.evaluate((id) => ({ run: window.__mk.runs.find((x) => x.anchored && x.types.includes('kill')), all: window.__mk.runs.filter((x) => x.fid === 'p' + id || x.types.includes('kill')), g: window.__mk.ghosts['p' + id] }), bid);
  const bMap = await B.page.evaluate(() => window.__hl.player().pos.map);
  R.check('hạ người: có hiệu ứng đòn + gục', done && r.all.some((x) => x.anchored && x.types.some((t) => t === 'attack' || t === 'skill')), JSON.stringify(r.all.map((x) => x.types)));
  R.check('hiệu ứng gục chỉ phát một lần', r.all.filter((x) => x.types.includes('kill')).length === 1, JSON.stringify(r.all.map((x) => x.types)));
  R.check('B bị hạ, về Làng (biến khỏi bản đồ của A)', bMap === 'village', bMap);
  R.check('hiệu ứng bám được vào chỗ B', done && r.run.miss.length === 0, JSON.stringify(r.run && r.run.miss));
  R.check('B giữ hình tới lúc đòn cuối trúng rồi mới mờ', !!(r.g && r.run && r.g.t0 >= r.run.hu), JSON.stringify({ g: r.g, hu: r.run && Math.round(r.run.hu) }));
  R.check('người: không lỗi JS', A.errors.length === 0, A.errors.join(' | '));
}
await R.done(browser);
