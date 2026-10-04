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

for (const t of ['map', 'hero', 'bag', 'quests', 'misc']) {
  await page.click(`#tabs [data-tab="${t}"]`);
  await page.waitForTimeout(250);
  R.check(`tab ${t}: không tràn ngang`, !(await overflowX(page)));
  await shot(page, `mobile-${t}.png`);
}
const tabSmall = await small('#tabs');
R.check('thanh tab: nút đủ lớn để chạm', tabSmall.length === 0, tabSmall.join(', '));
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
  await fight(page);
  await act(page, 'leave');
} else R.check('vào được trận đánh', false);

R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
