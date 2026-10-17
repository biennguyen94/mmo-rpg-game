// Cài đặt "Tự hủy đồ rơi": bật, bỏ hết loại giữ lại, lưu theo nhân vật (luật hủy ở Engine: test/hac_long/game/loot_filter_test.exs). Chạy: node e2e/lootfilter.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, shot } from './lib.mjs';

const R = reporter('lootfilter');
const browser = await launch();
const { page, errors } = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
await page.click('#tabs [data-tab="menu"]');
await page.click('[data-menu="settings"]');
const btn = () => page.locator('[data-act="loot-filter"]');
R.check('Cài đặt có thẻ Tự hủy đồ rơi, mặc định tắt', (await btn().getAttribute('aria-pressed')) === 'false');
await btn().click();
await page.waitForFunction(() => ((window.__hl.player().view || {}).autoCfg || {}).filter?.on === true, null, { timeout: 5000 }).catch(() => {});
R.check('bấm: bật (server lưu autoCfg.filter.on)', (await btn().getAttribute('aria-pressed')) === 'true');
for (const cb of await page.locator('[data-loot-keep]').all()) {
  if (await cb.isChecked()) { await cb.uncheck(); await page.waitForTimeout(400); }
}
const keep = await page.evaluate(() => window.__hl.player().view.autoCfg.filter.keep);
R.check('bỏ hết loại giữ lại', Array.isArray(keep) && keep.length === 0, JSON.stringify(keep));
// tải lại trang: cài đặt lưu theo nhân vật trên server
await page.reload();
await page.waitForFunction(() => window.__hl && window.__hl.player() && window.__hl.player().view, null, { timeout: 15000 });
const f2 = await page.evaluate(() => window.__hl.player().view.autoCfg?.filter);
R.check('tải lại: vẫn bật, giữ lại rỗng', f2?.on === true && Array.isArray(f2.keep) && f2.keep.length === 0, JSON.stringify(f2));
await page.click('#tabs [data-tab="menu"]');
await page.click('[data-menu="settings"]');
await shot(page, 'lootfilter.png');
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
