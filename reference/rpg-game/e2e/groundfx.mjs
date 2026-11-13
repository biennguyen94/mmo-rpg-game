// Hiệu ứng kỹ năng trên mặt đất (DECISIONS "Hiệu ứng kỹ năng trên mặt đất"):
// - màn trận: dùng kỹ năng → canvas mặt đất trong sân đấu (`.stage canvas.bfx-ground`, dưới hình quái) có vẽ (sóng, dấu)
//   lúc đòn trúng, vẫn còn dấu sau ~1 giây; ảnh từng hệ;
// - bản đồ (⚡ đánh nhanh): MapView có dấu mặt đất trong lúc đánh;
// - bảng mẫu mọi hệ (GroundFx vẽ thẳng lên một canvas) để xem bằng mắt.
// Chạy: node e2e/groundfx.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, act, travel, engage, shot } from './lib.mjs';

const R = reporter('groundfx');
const browser = await launch();
const { admin } = await adminSession(browser);
const SK = { dk: ['twisting_slash', 'falling_slash'], dw: ['fire_ball', 'lightning'], elf: ['heal'] };

// số điểm ảnh đã vẽ trên canvas mặt đất của sân đấu
const inked = (p) => p.evaluate(() => {
  const c = document.querySelector('#view .stage canvas.bfx-ground');
  if (!c || !c.width) return -1;
  const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
  let n = 0;
  for (let i = 3; i < d.length; i += 4) if (d[i] > 8) n++;
  return n;
});

for (const cls of Object.keys(SK)) {
  const X = await newPlayer(browser, { cls, viewport: { width: 800, height: 900 } });
  const p = X.page;
  await admin('set_level', X.name, { level: 30 });
  await admin('add_stats', X.name, { str: 60, agi: 60, ene: 60, vit: 200 });
  await p.waitForFunction(() => window.__hl.player().level === 30, null, { timeout: 10000 });
  await p.evaluate(() => localStorage.setItem('hl-fx', '1'));
  await travel(p, 'forest_1');
  for (const sk of SK[cls]) {
    if (!(await engage(p))) { R.check(`${cls} ${sk}: vào trận`, false); continue; }
    await p.waitForSelector(`[data-act="skill"][data-skill="${sk}"]`);
    await p.click(`[data-act="skill"][data-skill="${sk}"]`);
    await p.waitForTimeout(650);
    const a = await inked(p);
    const st = await p.$('#view .stage');
    if (st) await st.screenshot({ path: `${process.argv[3] || 'e2e/screenshots'}/groundfx-${cls}-${sk}.png` }).catch(() => null);
    await p.waitForTimeout(700);
    const b = await inked(p);
    R.check(`${cls} ${sk}: mặt đất sân đấu có sóng / dấu, còn dấu sau ~1,3 giây`, a > 200 && b > 50, JSON.stringify({ a, b }));
    for (let i = 0; i < 40; i++) { const bt = (await player(p)).battle; if (!bt || bt.over) break; await act(p, 'attack'); }
    await act(p, 'leave').catch(() => null);
  }
  R.check(`${cls}: không lỗi JS`, X.errors.length === 0, X.errors.join(' | '));
  await X.ctx.close();
}

// ⚡ đánh nhanh trên bản đồ: dấu mặt đất trên bản đồ
{
  const X = await newPlayer(browser, { cls: 'dw', viewport: { width: 390, height: 844 } });
  const p = X.page;
  await admin('set_level', X.name, { level: 30 });
  await admin('add_stats', X.name, { ene: 60, vit: 200 });
  await p.waitForFunction(() => window.__hl.player().level === 30, null, { timeout: 10000 });
  await p.evaluate(() => localStorage.setItem('hl-fx', '1'));
  await travel(p, 'forest_1');
  await p.click('#tabs [data-tab="map"]');
  await p.waitForSelector('[data-act="quick-toggle"]');
  await p.click('[data-act="quick-toggle"]');
  await p.waitForFunction(() => (window.__hl.player().view.autoCfg || {}).quick === true, null, { timeout: 5000 }).catch(() => null);
  let seen = 0;
  for (let i = 0; i < 6 && !seen; i++) {
    const w = await p.evaluate(() => window.__hl.world());
    const me = (await player(p)).pos;
    const mons = (w.monsters || []).filter((m) => !m.busy && !m.boss);
    if (!mons.length) { await p.waitForTimeout(800); continue; }
    mons.sort((a, b) => Math.abs(a.x - me.x) + Math.abs(a.y - me.y) - (Math.abs(b.x - me.x) + Math.abs(b.y - me.y)));
    await p.evaluate(([x, y]) => window.__hl.walkTo(x, y), [mons[0].x, mons[0].y]);
    for (let k = 0; k < 30 && !seen; k++) { await p.waitForTimeout(150); seen = await p.evaluate(() => window.MapView.groundCount()); }
  }
  await shot(p, 'groundfx-map.png');
  R.check('⚡ bản đồ: có dấu kỹnăng trên mặt đất', seen > 0, String(seen));
  R.check('bản đồ: không lỗi JS', X.errors.length === 0, X.errors.join(' | '));
  await X.ctx.close();
}

// bảng mẫu mọi hệ: vẽ thẳng bằng GroundFx (ảnh để xem bằng mắt)
{
  const X = await newPlayer(browser, { cls: 'dk', viewport: { width: 900, height: 520 } });
  const p = X.page;
  await p.evaluate(() => {
    const c = document.createElement('canvas');
    c.width = 900; c.height = 520; c.id = 'gsample';
    Object.assign(c.style, { position: 'fixed', inset: '0', zIndex: 99999, background: '#3b4a2c' });
    document.body.appendChild(c);
    const g = c.getContext('2d');
    const els = ['fire', 'ice', 'lightning', 'wind', 'earth', 'dark', 'light', 'none'];
    const marks = [];
    els.forEach((el, i) => {
      const x = 110 + (i % 4) * 220, y = 150 + Math.floor(i / 4) * 230;
      marks.push(window.GroundFx.make('mark', el, x, y, 70, { cls: 'dk' }));
      marks.push(window.GroundFx.make('cast', el, x, y - 75, 40));
    });
    // dừng hình: dấu ở ~30% đời (đang rõ nhất), vòng niệm chú ở ~50%
    const t0 = performance.now();
    marks.forEach((m) => { m.t0 = t0 - m.life * (m.kind === 'mark' ? 0.3 : 0.5); });
    window.__gs = () => { g.fillStyle = '#3b4a2c'; g.fillRect(0, 0, 900, 520); g.fillStyle = '#fff'; g.font = '14px sans-serif';
      els.forEach((el, i) => g.fillText(el, 90 + (i % 4) * 220, 250 + Math.floor(i / 4) * 230));
      marks.forEach((m) => window.GroundFx.draw(g, m, t0, 0, 0)); };
    window.__gs();
  });
  await p.waitForTimeout(200);
  await p.evaluate(() => window.__gs());
  await shot(p, 'groundfx-sample.png');
  R.check('bảng mẫu vẽ không lỗi', X.errors.length === 0, X.errors.join(' | '));
  await X.ctx.close();
}
await R.done(browser);
