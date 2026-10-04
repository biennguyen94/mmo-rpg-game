// Quản trị qua tab Quản trị (tài khoản admin do scripts/e2e_seed.exs tạo): tra người chơi, cấm / bỏ cấm
// chat, gửi quà qua hộp thư, cộng vàng (Chỉnh nhân vật), kiểm tra vàng, nhật ký quản trị.
// Chạy: node e2e/admin.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, send, shot } from './lib.mjs';

const R = reporter('admin');
const browser = await launch();
const X = await newPlayer(browser, { cls: 'dw' });
const { page } = await adminSession(browser);
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));

await page.click('#tabs [data-tab="admin"]');
R.check('tab Quản trị mở', (await page.textContent('#view')).includes('Tra cứu người chơi'));
await page.fill('#adm-name', X.name);
await page.press('#adm-name', 'Enter');
await page.waitForFunction((n) => document.querySelector('#view').textContent.includes(n) && document.querySelector('[data-adm="mute"]'), X.name, { timeout: 5000 }).catch(() => null);
R.check('tra cứu thấy nhân vật', !!(await page.$('[data-adm="mute"]')));

// cấm chat 1 giờ → người chơi không chat được; bỏ cấm → chat lại được
await page.click('[data-adm="mute"][data-minutes="60"]');
await page.waitForTimeout(500);
const muted = await X.page.evaluate(() => window.Net.chat('thử chat').then(() => 'ok', (e) => e.msg));
R.check('bị cấm chat thì không gửi được tin', muted !== 'ok', muted);
await page.click('[data-adm="unmute"]');
await page.waitForTimeout(500);
const unmuted = await X.page.evaluate(() => window.Net.chat('đã được chat').then(() => 'ok', (e) => e.msg));
R.check('bỏ cấm chat thì gửi lại được', unmuted === 'ok', unmuted);

// gửi quà 123 vàng qua hộp thư
await page.fill('#adm-gift input[name="subject"]', 'Quà thử');
await page.fill('#adm-gift input[name="gold"]', '123');
await page.click('#adm-gift button[type="submit"]');
await X.page.waitForFunction(() => window.Net.mail().then((m) => m.mails.some((x) => x.subject === 'Quà thử')), null, { timeout: 5000 }).catch(() => null);
const mails = await X.page.evaluate(() => window.Net.mail());
const gift = mails.mails.find((m) => m.subject === 'Quà thử');
R.check('người chơi nhận thư quà', !!gift && gift.gold === 123);
const g0 = (await player(X.page)).gold;
if (gift) await send(X.page, { act: 'mail_claim', id: gift.id });
R.check('mở thư nhận 123 vàng', (await player(X.page)).gold === g0 + 123);

// Chỉnh nhân vật: cộng 1000 vàng (người chơi đang online thấy liền)
const g1 = (await player(X.page)).gold;
await page.fill('form.adm-char[data-op="add_gold"] input[name="amount"]', '1000');
await page.click('form.adm-char[data-op="add_gold"] button[type="submit"]');
await X.page.waitForFunction((g) => window.__hl.player().gold === g, g1 + 1000, { timeout: 5000 }).catch(() => null);
R.check('cộng 1000 vàng, người chơi thấy ngay', (await player(X.page)).gold === g1 + 1000);
await shot(page, 'admin-user.png');

// nhật ký vàng của người này có dòng ADMIN; kiểm tra vàng; nhật ký quản trị
await page.click('[data-adm="gold_log"]');
await page.waitForSelector('.adm-table', { timeout: 5000 }).catch(() => null);
R.check('nhật ký vàng có dòng quản trị', (await page.textContent('#view')).match(/ADMIN|MAIL/) != null);
await page.click('[data-adm="audit"][data-days="1"]');
await page.waitForFunction(() => /Vàng 1 ngày qua/.test(document.querySelector('#view').textContent), null, { timeout: 10000 }).catch(() => null);
R.check('kiểm tra vàng chạy và hiện kết quả', /Vàng 1 ngày qua/.test(await page.textContent('#view')));
await shot(page, 'admin-audit.png');

R.check('không lỗi JS', errors.length === 0 && X.errors.length === 0, [...errors, ...X.errors].join(' | '));
await R.done(browser);
