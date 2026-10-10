// Phase 13: không vẽ người khác trên bản đồ, nút 👫 Quanh đây (số người + danh sách), hồ sơ người chơi
// (mình và người khác), máu quái đang bị đánh hiện cho người cùng bản đồ, % cộng thêm ở tab Nhân vật.
// Chạy: node e2e/people.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, player, travel, engage, act, shot, overflowX, fight } from './lib.mjs';

const R = reporter('people');
const browser = await launch();
const A = await newPlayer(browser, { cls: 'dk', viewport: { width: 360, height: 740 } });
const B = await newPlayer(browser, { cls: 'elf' });
for (const X of [A, B]) { await travel(X.page, 'village'); await travel(X.page, 'forest_1'); }

// ---------- Quanh đây ----------
await A.page.waitForFunction((n) => window.__hl.world().players.some((o) => o.name === n), B.name, { timeout: 8000 }).catch(() => null);
await A.page.waitForTimeout(300);
const dot = await A.page.evaluate(() => (document.querySelector('#tabs [data-tab="people"] .points-dot') || {}).textContent);
R.check('dock có nút 👫 với số người cùng bản đồ', +dot >= 1, String(dot));
await A.page.click('#tabs [data-tab="people"]');
await A.page.waitForSelector('.people-row');
R.check('danh sách Quanh đây có B', (await A.page.textContent('#view')).includes(B.name));
R.check('Quanh đây: không tràn ngang (điện thoại)', !(await overflowX(A.page)));
await shot(A.page, 'people-list.png');

// ---------- Hồ sơ người khác ----------
await A.page.click(`.people-row:has-text("${B.name}")`);
await A.page.waitForSelector('.prof-head');
await A.page.waitForFunction(() => document.querySelector('#view').textContent.includes('Đăng ký'), null, { timeout: 8000 }).catch(() => null);
const prof = await A.page.textContent('#view');
R.check('hồ sơ B: tên, hạng, chỉ số, trang bị, số liệu', prof.includes(B.name) && /Hạng: #\d+/.test(prof) && prof.includes('Sức mạnh') && prof.includes('Trang bị') && prof.includes('Quái đã hạ'), prof.slice(0, 160));
R.check('hồ sơ B có nút Giao dịch, Kết bạn, Thách đấu', !!(await A.page.$('[data-act="trade-op"]')) && !!(await A.page.$('[data-act="friend-op"]')) && !!(await A.page.$('[data-act="pvp_challenge"]')));
R.check('hồ sơ: không tràn ngang (điện thoại)', !(await overflowX(A.page)));
await shot(A.page, 'people-profile.png');
await act(A.page, 'profile-close');
R.check('‹ Quay lại về danh sách', !!(await A.page.$('.people-row')));

// ---------- Hồ sơ của mình (tab Nhân vật) ----------
await A.page.click('#tabs [data-tab="hero"]');
await A.page.click(`[data-act="profile"]`);
await A.page.waitForSelector('.prof-head');
await A.page.waitForFunction(() => document.querySelector('#view').textContent.includes('Đăng ký'), null, { timeout: 8000 }).catch(() => null);
const mine = await A.page.textContent('#view');
R.check('hồ sơ của mình: đang online @ Rừng Mê, không có nút hành động', mine.includes(A.name) && mine.includes('Đang online') && !(await A.page.$('[data-act="trade-op"]')), mine.slice(0, 160));
await A.page.click('#tabs [data-tab="map"]');

// ---------- Không vẽ người khác; máu quái đồng bộ ----------
// quái Rừng Mê 1 thường chết sau một đòn: sang Rừng Mê 2 (quái trâu hơn) để kịp thấy máu giảm
for (const X of [A, B]) { await X.page.click('#tabs [data-tab="map"]').catch(() => null); await travel(X.page, 'forest_2'); }
let synced = null; const why = [];
for (let i = 0; i < 4 && !synced; i++) {
  if (!(await engage(B.page, null, 30))) { why.push('engage'); continue; }
  await A.page.waitForFunction(() => (window.__hl.world().monsters || []).some((m) => m.busy), null, { timeout: 8000 }).catch(() => null);
  await act(B.page, 'attack');
  const over = await B.page.evaluate(() => { const b = window.__hl.player().battle; return !b || b.over; });
  if (over) { why.push('one-hit'); await act(B.page, 'leave').catch(() => null); continue; }
  await A.page.waitForFunction(() => (window.__hl.world().monsters || []).some((m) => m.busy && m.hp < 100), null, { timeout: 8000 }).catch(() => null);
  const seen = await A.page.evaluate(() => (window.__hl.world().monsters || []).filter((m) => m.busy && m.hp < 100).map((m) => m.hp));
  // chưa thấy (ảnh bản đồ của A tới chậm): rời trận, thử con khác
  if (seen.length) synced = seen;
  else { why.push({ A: await A.page.evaluate(() => { const w = window.__hl.world(); return [w.map, (w.monsters || []).filter((m) => m.busy).map((m) => [m.id, m.hp])]; }), B: await B.page.evaluate(() => { const p = window.__hl.player(); return [p.pos.map, p.battle && p.battle.encounter, p.battle && [p.battle.monster.hp, p.battle.monster.maxHp, p.battle.over]]; }) }); await fight(B.page).catch(() => null); await act(B.page, 'leave').catch(() => null); }
}
R.check('A thấy máu quái B đang đánh giảm (đồng bộ)', !!synced && synced.some((h) => h < 100), JSON.stringify({ synced, why }));
await shot(A.page, 'people-map.png');

// ---------- Tab Nhân vật: % cộng thêm ----------
const ex = await A.page.evaluate(() => window.__hl.player().view.extra);
R.check('tab Nhân vật có dữ liệu phần cộng thêm (đồ / thú cưng / món ăn)', ex && typeof ex.atk === 'number' && ex.gear != null, JSON.stringify(ex));

R.check('không lỗi JS', A.errors.length === 0 && B.errors.length === 0, A.errors.concat(B.errors).join(' | '));
await R.done(browser);
