// Phase 17: Tiến Lên Miền Nam — sảnh, mở bàn, thêm máy, chơi hết ván bằng nút Gợi ý / Đánh / Bỏ lượt,
// chat bàn, biểu cảm, ném đồ (trừ vàng), xem lại ván; người thứ hai xem trận trên điện thoại.
// Chạy: node e2e/tienlen.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, player, shot, overflowX } from './lib.mjs';

const R = reporter('tienlen');
const browser = await launch();
const A = await newPlayer(browser, { cls: 'dk' });
const B = await newPlayer(browser, { cls: 'elf', viewport: { width: 390, height: 844 } });
const tl = (page) => page.evaluate(() => window.TL.state());

R.check('Làng có NPC Bà Chủ Sòng (role tienlen)', await A.page.evaluate(() => window.GAME_DATA.WORLD.maps.village.npcs.some((n) => n.role === 'tienlen')));

// ---------- sảnh ----------
await A.page.click('#tabs [data-tab="menu"]');
await A.page.click('[data-menu="tienlen"]');
await A.page.waitForSelector('#tl-root:not([hidden]) [data-tl-form="create"]', { timeout: 8000 });
R.check('Menu → 🃏 Tiến Lên mở sảnh', (await tl(A.page)).screen === 'lobby');
await shot(A.page, 'tienlen-lobby.png');

// ---------- mở bàn, thêm 3 máy ----------
await A.page.fill('[data-tl-form="create"] input[name="stake"]', '0');
await A.page.click('[data-tl-form="create"] button');
await A.page.waitForFunction(() => window.TL.state().screen === 'table', null, { timeout: 8000 });
for (const lv of ['easy', 'normal', 'normal']) {
  await A.page.click(`[data-tl="add-bot"][data-level="${lv}"]`);
  await A.page.waitForTimeout(250);
}
let s = await tl(A.page);
R.check('bàn có 4 người (mình + 3 máy), mình là chủ', s.view.players.length === 4 && s.view.host === s.view.me, JSON.stringify(s.view.players.map((p) => p.name)));
const gold0 = (await player(A.page)).gold;

// ---------- chia bài, chơi bằng nút ----------
await A.page.click('[data-tl="start"]');
await A.page.waitForFunction(() => { const v = window.TL.state().view; return v && (v.status === 'playing' || v.games_played === 1); }, null, { timeout: 8000 });
let shotMid = false, plays = 0;
// mỗi nước của máy cách 1 giây: một ván 4 người có thể mất 1–2 phút
const until = Date.now() + 180000;
while (Date.now() < until) {
  s = await tl(A.page);
  const v = s.view;
  if (v.status === 'waiting' && v.games_played === 1) break;
  if (v.status === 'playing' && v.game.current === v.me) {
    if (!shotMid) { await shot(A.page, 'tienlen-table.png'); shotMid = true; }
    await A.page.click('[data-tl="hint"]');
    await A.page.waitForTimeout(200);
    const canPlay = await A.page.$eval('[data-tl="play"]', (b) => !b.disabled).catch(() => false);
    if (canPlay) { await A.page.click('[data-tl="play"]'); plays++; }
    else if (await A.page.$('[data-tl="pass"]')) await A.page.click('[data-tl="pass"]');
    await A.page.waitForTimeout(250);
  } else {
    await A.page.waitForTimeout(150);
  }
}
s = await tl(A.page);
R.check('hết ván: bảng kết quả, ván đã chơi = 1', s.view.status === 'waiting' && s.view.games_played === 1 && !!(await A.page.$('.tl-results')), `plays ${plays}`);
R.check('đã đánh bằng nút Gợi ý → Đánh (hoặc tới trắng)', plays > 0 || (s.view.game.instant_winners || []).length > 0, `plays ${plays}`);
await shot(A.page, 'tienlen-result.png');

// ---------- chat, biểu cảm, ném đồ ----------
await A.page.click('[data-tl="chat-toggle"]');
await A.page.fill('[data-tl-form="chat"] input[name="text"]', 'Ván hay quá!');
await A.page.click('[data-tl-form="chat"] button');
await A.page.waitForFunction(() => [...document.querySelectorAll('.tl-chat-line')].some((l) => l.textContent.includes('Ván hay quá!')), null, { timeout: 5000 }).catch(() => null);
R.check('chat bàn hiện tin vừa gửi', await A.page.evaluate(() => [...document.querySelectorAll('.tl-chat-line')].some((l) => l.textContent.includes('Ván hay quá!'))));
await A.page.click('.tl-reacts [data-tl="react"]');
await A.page.waitForSelector('.tl-react', { timeout: 4000 }).catch(() => null);
R.check('biểu cảm hiện trên ghế mình', !!(await A.page.$('.tl-react')));
const target = await A.page.$('.tl-seat.target .tl-name');
await target.click();
await A.page.click('.tl-throw [data-item="tomato"]');
await A.page.waitForSelector('.tl-mark', { timeout: 4000 }).catch(() => null);
await A.page.waitForTimeout(300);
R.check('ném cà chua: dấu hiện trên ghế, trừ 1 vàng', !!(await A.page.$('.tl-mark')) && (await player(A.page)).gold === gold0 - 1, `${gold0} → ${(await player(A.page)).gold}`);

// ---------- người thứ hai xem trận trên điện thoại ----------
await B.page.evaluate(() => window.TL.open());
await B.page.waitForSelector(`[data-tl="watch"][data-id="${s.roomId}"]`, { timeout: 8000 }).catch(() => null);
await B.page.click(`[data-tl="watch"][data-id="${s.roomId}"]`);
await B.page.waitForFunction(() => window.TL.state().screen === 'watch', null, { timeout: 5000 }).catch(() => null);
const sb = await tl(B.page);
R.check('xem trận: thấy bàn, không có bài trên tay', sb.screen === 'watch' && sb.view.me == null && !(await B.page.$('#tl-hand')));
R.check('bàn trên điện thoại không tràn ngang', !(await overflowX(B.page)));
await shot(B.page, 'tienlen-watch-mobile.png');
await A.page.waitForFunction(() => (window.TL.state().view.spectators || 0) >= 1, null, { timeout: 4000 }).catch(() => null);
R.check('chủ bàn thấy 👀 1 người xem', ((await tl(A.page)).view.spectators || 0) >= 1);

// ---------- xem lại ván ----------
await A.page.click('[data-tl="lobby"]');
await A.page.click('[data-tl="history"]');
await A.page.waitForSelector('[data-tl="replay"]', { timeout: 8000 }).catch(() => null);
R.check('Ván đã chơi: có 1 ván', (await A.page.$$('[data-tl="replay"]')).length === 1);
await A.page.click('[data-tl="replay"]');
await A.page.waitForSelector('.tl-rp-controls', { timeout: 5000 }).catch(() => null);
await A.page.click('[data-tl="frame"][data-to="last"]');
const ev = await A.page.textContent('.tl-ev');
R.check('xem lại ván: tới bước cuối là "Hết ván"', ev.includes('Hết ván'), ev);
await shot(A.page, 'tienlen-replay.png');

// ---------- đóng sảnh, về bản đồ ----------
await A.page.click('[data-tl="close"]');
R.check('‹ Bản đồ đóng lớp phủ', await A.page.evaluate(() => !window.TL.isOpen() && document.getElementById('tl-root').hidden));

R.check('không lỗi JS', A.errors.length === 0 && B.errors.length === 0, A.errors.concat(B.errors).join(' | '));
await R.done(browser);
