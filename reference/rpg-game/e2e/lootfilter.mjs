// Cài đặt "Tự hủy đồ rơi": bật, bỏ hết loại giữ lại, lưu qua tải lại trang; đánh thật: bật thì đồ rơi bị hủy, tắt thì vào túi. Chạy: node e2e/lootfilter.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, travel, engage, fight, act, player, shot } from './lib.mjs';

const R = reporter('lootfilter');
const browser = await launch();
const { page, name, errors } = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
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

// Đánh thật đến khi rơi trang bị (quái cấp 1 không rơi: lên cấp, sang Rừng Mê 2). Trả dòng nhật ký 🎁 / 🗑 đầu tiên.
const adm = await adminSession(browser);
await adm.admin('set_level', name, { level: 20 });
await adm.admin('add_gold', name, { amount: 100000 });
await page.waitForFunction(() => window.__hl.player().level === 20);
await page.click('#tabs [data-tab="map"]');
await travel(page, 'village');
await travel(page, 'forest_1');
await travel(page, 'forest_2');
async function huntDrop(tries = 80) {
  for (let i = 0; i < tries; i++) {
    if (!(await engage(page))) continue;
    const r = await fight(page);
    const p = await player(page);
    const line = r === 'win' && (p.battle?.log || []).find((l) => /🎁|🗑/.test(l.text));
    if (line) return { line: line.text, bag: (p.gear || []).length };
    await act(page, 'leave').catch(() => null);
  }
  return null;
}
const on = await huntDrop();
R.check('bật, giữ lại rỗng: trang bị rơi bị tự hủy, không vào túi', on && on.line.includes('🗑 Tự hủy') && on.bag === 0, JSON.stringify(on));
await shot(page, 'lootfilter-on.png');
await act(page, 'leave').catch(() => null);

// tắt: món rơi vào túi như thường
await page.click('#tabs [data-tab="menu"]');
await page.click('[data-menu="settings"]');
await btn().click();
await page.waitForFunction(() => window.__hl.player().view.autoCfg?.filter?.on === false, null, { timeout: 5000 }).catch(() => {});
await page.click('#tabs [data-tab="map"]');
const off = await huntDrop();
R.check('tắt: trang bị rơi vào túi', off && off.line.includes('🎁') && off.bag === 1, JSON.stringify(off));
await shot(page, 'lootfilter-off.png');
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
