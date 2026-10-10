// Điện thoại 360 × 740: các tab, NPC, trận đánh không tràn ngang; nút bấm đủ lớn để chạm (≥ 36 px).
// Chạy: node e2e/mobile.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, act, travel, meetNpc, leaveNpc, engage, fight, shot, overflowX } from './lib.mjs';

const R = reporter('mobile');
const browser = await launch();
const { page, errors } = await newPlayer(browser, { cls: 'elf', viewport: { width: 360, height: 740 } });

// nút đang hiện mà thấp hơn `min` px (chỉ tính nút trong `scope`)
const small = (scope, min = 36) => page.evaluate(([scope, min]) => [...document.querySelectorAll(`${scope} button`)]
  .filter((b) => b.offsetParent && !b.classList.contains('small-btn') && b.getBoundingClientRect().height < min)
  .map((b) => (b.textContent || b.getAttribute('aria-label') || '').trim().slice(0, 20)), [scope, min]);

for (const t of ['map', 'hero', 'bag', 'menu']) {
  await page.click(`#tabs [data-tab="${t}"]`);
  await page.waitForTimeout(250);
  R.check(`tab ${t}: không tràn ngang`, !(await overflowX(page)));
  await shot(page, `mobile-${t}.png`);
}
const tabSmall = await small('#tabs');
R.check('thanh tab: nút đủ lớn để chạm', tabSmall.length === 0, tabSmall.join(', '));
await page.click('#tabs [data-tab="map"]');
// U5: màn bản đồ vừa khít, không cuộn trang (360 × 740)
const noScroll = () => page.evaluate(() => { const v = document.querySelector('#view'); return v.scrollHeight <= v.clientHeight + 1 && document.documentElement.scrollHeight <= innerHeight + 1; });
await page.waitForTimeout(200);
R.check('bản đồ vừa khít giữa HUD và dock, không cuộn', await noScroll());
// U4: chat trong bản đồ: nút 💬 góc dưới phải, cỡ vừa
const cb = await page.evaluate(() => { const b = document.querySelector('.chat-btn').getBoundingClientRect(), m = document.querySelector('.map-wrap').getBoundingClientRect(); return { w: b.width, right: m.right - b.right, bottom: m.bottom - b.bottom }; });
R.check('nút 💬 ở góc dưới phải bản đồ, ~36 px', cb.w <= 40 && cb.right < 20 && cb.bottom < 20, JSON.stringify(cb));
await page.click('.chat-btn');
await page.fill('#chat-input', 'chào từ điện thoại');
await page.press('#chat-input', 'Enter');
await page.waitForFunction(() => document.querySelector('#chat-log').textContent.includes('chào từ điện thoại'), null, { timeout: 5000 }).catch(() => null);
R.check('gửi chat từ khung chat trong bản đồ', (await page.textContent('#chat-log')).includes('chào từ điện thoại'));
await page.click('.chat-btn');
// U3: Menu có Cài đặt (âm thanh, đăng xuất)
await page.click('#tabs [data-tab="menu"]');
await page.click('[data-menu="settings"]');
R.check('Menu → Cài đặt có âm thanh và đăng xuất', !!(await page.$('[data-act="sound-toggle"]')) && !!(await page.$('[data-act="logout"]')));
// Phase 14: Thư viện — tìm không dấu, mở chi tiết, bấm liên kết sang mục khác
await page.click('[data-act="menu-back"]');
await page.click('[data-menu="library"]');
await page.click('[data-act="lib-tab"][data-tab2="monsters"]');
await page.fill('#lib-q', 'cho rung');
await page.waitForTimeout(150);
const libRows = await page.$$eval('.lib-row', (r) => r.length);
await page.click('.lib-row');
R.check('Thư viện: tìm "cho rung" ra 1 quái, có máu / nơi xuất hiện / đồ rơi', libRows === 1 && /Xuất hiện ở/i.test(await page.textContent('.lib-detail')), String(libRows));
await page.click('.lib-detail .lib-link >> nth=-1');
R.check('Thư viện: bấm tên đồ rơi chuyển sang Vật phẩm, có nguồn', (await page.textContent('#lib-tabs .primary')).includes('Vật phẩm') && (await page.textContent('#lib-results')).includes('Có được từ'));
R.check('Thư viện: không tràn ngang', !(await overflowX(page)));
await shot(page, 'mobile-library.png');
await page.click('#tabs [data-tab="map"]');

await travel(page, 'village');
for (const id of ['blacksmith', 'herbalist', 'elder']) {
  await meetNpc(page, id);
  R.check(`NPC ${id}: không tràn ngang`, !(await overflowX(page)));
  if (id === 'blacksmith') await shot(page, 'mobile-npc-shop.png');
  await leaveNpc(page);
}

await travel(page, 'forest_1');
if (await engage(page)) {
  R.check('trận đánh: không tràn ngang', !(await overflowX(page)));
  const b = await small('.actions');
  R.check('trận đánh: nút đủ lớn để chạm', b.length === 0, b.join(', '));
  await shot(page, 'mobile-battle.png');
  R.check('trận đánh vừa khít, không cuộn trang', await noScroll());
  await fight(page);
  await act(page, 'leave');
} else R.check('vào được trận đánh', false);

// B1: HUD trường hợp xấu nhất (vàng 8 chữ số, số đỏ trên cả 3 nút) không làm tràn ngang
await page.evaluate(() => {
  document.querySelector('#hud .gold').lastChild.textContent = '12.345.678';
  document.querySelectorAll('#hud .hud-btn').forEach((b) => { if (!b.querySelector('.points-dot')) b.insertAdjacentHTML('beforeend', '<span class="points-dot">99</span>'); });
});
R.check('HUD nhiều chữ số + số đỏ: không tràn ngang', !(await overflowX(page)));
await page.evaluate(() => window.__hl.tab('map'));

// Phase 8: bảng Thông báo (🔔) — tin lên cấp / thắng trận vừa rồi được giữ lại
await act(page, 'notes-open');
const nu = await page.evaluate(() => window.__hl.ui());
R.check('mở bảng Thông báo, không tràn ngang', nu.notes === true && !(await overflowX(page)));
await shot(page, 'mobile-notes.png');
await act(page, 'notes-close');
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
