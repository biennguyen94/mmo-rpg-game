// Quản trị qua tab Quản trị (tài khoản admin do scripts/e2e_seed.exs tạo): tra người chơi, cấm / bỏ cấm
// chat, gửi quà qua hộp thư, cộng vàng (Chỉnh nhân vật), kiểm tra vàng, nhật ký quản trị.
// Chạy: node e2e/admin.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, send, shot, travel, walkTo, fight, act } from './lib.mjs';

const R = reporter('admin');
const browser = await launch();
const X = await newPlayer(browser, { cls: 'dw' });
const { page, admin } = await adminSession(browser);
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));

await page.click('#tabs [data-tab="menu"]');
await page.click('[data-menu="admin"]');
R.check('tab Quản trị mở', (await page.textContent('#view')).includes('Tra cứu người chơi'));
// nhân vật mới chỉ vào database ở lần lưu định kỳ của Session (vài giây): tìm lại tới khi thấy
for (let i = 0; i < 20 && !(await page.$('[data-adm="mute"]')); i++) {
  await page.fill('#adm-name', X.name);
  await page.press('#adm-name', 'Enter');
  await page.waitForSelector('[data-adm="mute"]', { timeout: 1000 }).catch(() => null);
}
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

// Quà cho mọi người (V10): 123 vàng + một món đồ thường +3 qua hộp thư
const subj = 'Quà thử ' + Date.now();
await page.fill('#adm-gift-all input[name="subject"]', subj);
await page.fill('#adm-gift-all input[name="gold"]', '123');
await page.selectOption('#adm-gift-all select[name="gbase"]', { index: 1 });
await page.fill('#adm-gift-all input[name="gup"]', '3');
await page.click('#adm-gift-all button[type="submit"]');
// chờ thư tới: hỏi hộp thư mỗi 0,5 giây (không hỏi mỗi khung hình, kẻo đụng giới hạn 30 lần / phút)
await X.page.waitForFunction((s) => window.Net.mail().then((m) => m.mails.some((x) => x.subject === s), () => false), subj, { timeout: 15000, polling: 500 }).catch(() => null);
const mails = await X.page.evaluate(() => window.Net.mail());
const gift = mails.mails.find((m) => m.subject === subj);
R.check('người chơi nhận thư quà (vàng + đồ +3)', !!gift && gift.gold === 123 && Object.keys(gift.items).some((k) => k.startsWith('gear:') && k.endsWith(':3')), JSON.stringify(gift && gift.items));
const g0 = (await player(X.page)).gold, n0 = Object.keys((await player(X.page)).view.gear || {}).length;
if (gift) await send(X.page, { act: 'mail_claim', id: gift.id });
const pc = await player(X.page);
R.check('mở thư nhận 123 vàng và một món đồ', pc.gold === g0 + 123 && Object.keys(pc.view.gear || {}).length === n0 + 1, `${pc.gold - g0} vàng, ${Object.keys(pc.view.gear || {}).length - n0} đồ`);
R.check('không còn mục Gửi quà riêng ở người chơi', !(await page.$('#adm-gift')));

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

// ---------- Golden Invasion (Phase 7): quản trị bắt đầu ngay, người chơi đánh quái vàng ----------
await admin('set_level', X.name, { level: 12 });
await admin('heal', X.name);
await X.page.waitForFunction(() => window.__hl.player().level === 12);
await page.click('[data-adm="invasion"]');
await X.page.waitForFunction(() => document.body.textContent.includes('Golden Invasion'), null, { timeout: 8000 }).catch(() => null);
R.check('người chơi nhận thông báo Golden Invasion', (await X.page.textContent('body')).includes('Golden Invasion'));
await travel(X.page, 'village');
await travel(X.page, 'forest_1');
const gold = await X.page.evaluate(() => (window.__hl.world().monsters || []).find((m) => m.gold && !m.boss && !m.busy));
R.check('có quái vàng trên Rừng Mê', !!gold);
await shot(X.page, 'admin-invasion.png');
if (gold) {
  const xp0 = (await player(X.page)).xp, lv0 = (await player(X.page)).level;
  // quái đi lang thang: tìm lại vị trí rồi đi tới, vài lần
  for (let i = 0; i < 6 && !(await player(X.page)).battle; i++) {
    const g = await X.page.evaluate(() => (window.__hl.world().monsters || []).find((m) => m.gold && !m.boss && !m.busy));
    if (g) await walkTo(X.page, g.x, g.y);
  }
  const p = await player(X.page);
  R.check('đánh quái vàng: tên có "Vàng"', !!p.battle && p.battle.monster.name.includes('Vàng') && p.battle.monster.golden, p.battle && p.battle.monster.name);
  const res = await fight(X.page);
  const p2 = await player(X.page);
  R.check('thắng quái vàng, nhận thưởng lớn', res === 'win' && (p2.level > lv0 || p2.xp - xp0 >= p.battle.monster.xp * 0.5), `res=${res} xp ${xp0}→${p2.xp} reward ${p.battle && p.battle.monster.xp}`);
  await act(X.page, 'leave');
}

R.check('không lỗi JS', errors.length === 0 && X.errors.length === 0, [...errors, ...X.errors].join(' | '));
await R.done(browser);
