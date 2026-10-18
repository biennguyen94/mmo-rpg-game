// Cài đặt: tắt / bật tên quái trên đầu. Chạy: node e2e/mobname.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, travel, shot } from './lib.mjs';

const R = reporter('mobname');
const browser = await launch();
const { page, errors } = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
await travel(page, 'village');
await travel(page, 'forest_1');
await page.click('#tabs [data-tab="menu"]');
await page.click('[data-menu="settings"]');
const btn = page.locator('[data-act="mob-names"]');
R.check('Cài đặt có nút tên quái, mặc định bật', (await btn.getAttribute('aria-pressed')) === 'true');
await btn.click();
R.check('bấm: tắt tên quái (lưu hl-mobname=0)', (await page.evaluate(() => localStorage.getItem('hl-mobname'))) === '0' && (await page.locator('[data-act="mob-names"]').getAttribute('aria-pressed')) === 'false');
await page.click('#tabs [data-tab="map"]');
await page.waitForTimeout(800);
await shot(page, 'mobname-off.png');
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
