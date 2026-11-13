// Hiệu ứng lúc hạ quái (màn trận): đòn kỹ năng phải trúng xong (lần fx-hit cuối trên hình quái) TRƯỚC khi quái bắt đầu mờ
// (fx-dying). DECISIONS "Hiệu ứng: quái gục sau khi đòn trúng".
// Đo khoảng cách thời gian giữa hai lớp với mỗi hệ kỹ năng của 4 lớp nhân vật, quái bị hạ một đòn.
// Chạy: node e2e/killfx.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, act, travel, engage, shot } from './lib.mjs';

const R = reporter('killfx');
const browser = await launch();
const { admin } = await adminSession(browser);
const SK = { dk: ['twisting_slash', 'falling_slash'], dw: ['fire_ball', 'lightning'], elf: ['triple_shot', 'heal'], mg: ['power_slash', 'gigantic_storm'] };
// bump() gỡ rồi gắn lại lớp fx-hit mỗi lần trúng: ghi lần cuối

for (const cls of Object.keys(SK)) {
  const X = await newPlayer(browser, { cls, viewport: { width: 390, height: 844 } });
  const p = X.page;
  await admin('set_level', X.name, { level: 30 });
  await admin('add_stats', X.name, { str: 900, agi: 900, ene: 900, vit: 200 });
  await p.waitForFunction(() => window.__hl.player().level === 30, null, { timeout: 10000 });
  await p.evaluate(() => localStorage.setItem('hl-fx', '1'));
  await travel(p, 'forest_1');
  for (const sk of SK[cls]) {
    if (!(await engage(p))) { R.check(`${cls} ${sk}: vào trận`, false); continue; }
    await p.waitForSelector(`[data-act="skill"][data-skill="${sk}"]`);
    await p.evaluate(() => {
      window.__k = { hit: null, dying: null, t0: performance.now() };
      new MutationObserver((ms) => {
        for (const m of ms) {
          const el = m.target;
          if (!el.closest || !el.closest('.stage')) continue;
          if (el.classList.contains('fx-hit')) window.__k.hit = performance.now() - window.__k.t0;
          if (el.classList.contains('fx-dying') && window.__k.dying == null) window.__k.dying = performance.now() - window.__k.t0;
        }
      }).observe(document.body, { subtree: true, attributes: true, attributeFilter: ['class'] });
    });
    await p.click(`[data-act="skill"][data-skill="${sk}"]`);
    if (cls === 'dk' && sk === 'twisting_slash') for (let i = 0; i < 6; i++) { await p.waitForTimeout(90); await shot(p, `killfx-${i}.png`); }
    await p.waitForTimeout(1500);
    const k = await p.evaluate(() => window.__k);
    const b = (await player(p)).battle;
    const won = b && b.over && b.result === 'win';
    const ok = won && k.hit != null && k.dying != null && k.dying >= k.hit;
    R.check(`${cls} ${sk}: trúng trước khi quái mờ`, ok, JSON.stringify({ won, hit: k.hit && Math.round(k.hit), dying: k.dying && Math.round(k.dying) }));
    await act(p, 'leave').catch(() => null);
  }
  await X.page.context().close();
}
await R.done(browser);
