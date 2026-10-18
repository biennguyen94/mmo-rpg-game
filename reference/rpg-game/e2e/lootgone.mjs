// Bảng đồ rơi sau trận: hủy vật phẩm xếp chồng (bình máu) khi túi đã có sẵn loại đó → dòng vẫn gạch ngang.
// Chạy: node e2e/lootgone.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, travel, engage, fight, act, player, shot } from './lib.mjs';

const R = reporter('lootgone');
const browser = await launch();
const { page, name, errors } = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
// túi có sẵn bình các cỡ
const adm = await adminSession(browser);
for (const b of ['potion_s', 'potion_m', 'potion_l']) await adm.admin('give_item', name, { id: b, count: 5 });
await page.waitForFunction(() => (window.__hl.player().inv.potion_s || 0) >= 5);
await travel(page, 'village');
await travel(page, 'forest_1');
let id = null;
for (let i = 0; i < 40 && !id; i++) {
  if (!(await engage(page))) continue;
  const r = await fight(page);
  const p = await player(page);
  if (r === 'win') id = (p.battle?.reward?.items || []).find((x) => (p.inv[x] || 0) > 1);
  if (!id) await act(page, 'leave').catch(() => null);
}
R.check('rơi bình máu khi túi đã có loại đó', !!id, String(id));
if (id) {
  const before = (await player(page)).inv[id];
  await page.click(`.loot [data-act="discard"][data-id="${id}"]`);
  await page.waitForFunction(([k, n]) => (window.__hl.player().inv[k] || 0) < n, [id, before], { timeout: 5000 }).catch(() => {});
  const after = (await player(page)).inv[id] || 0;
  R.check('hủy: túi bớt, vẫn còn bình cũ', after < before && after > 0, `${before} → ${after}`);
  const row = page.locator('.loot-row', { has: page.locator(`[data-id="${id}"]`) });
  R.check('dòng vật phẩm gạch ngang, hết nút Hủy', (await row.getAttribute('class')).includes('gone') && (await row.locator('[data-act="discard"]').count()) === 0);
  await shot(page, 'lootgone.png');
}
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
