// Câu hỏi bảo mật (DECISIONS "Câu hỏi bảo mật"): đăng ký chọn câu hỏi + câu trả lời (lib.mjs: câu thứ nhất, "meo mun");
// quên mật khẩu → nhập tên → trả lời (sai: báo lỗi; đúng, khác hoa thường: đặt mật khẩu mới, đăng nhập luôn);
// tài khoản chưa có câu hỏi → gửi yêu cầu cho quản trị như cũ; Cài đặt có mục đổi câu hỏi bảo mật.
// Chạy: node e2e/secq.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, shot, enterFirst } from './lib.mjs';

const R = reporter('secq');
const browser = await launch();
const { page, user, errors } = await newPlayer(browser, { viewport: { width: 390, height: 844 } });

// đăng xuất (xóa token) rồi mở lại trang đăng nhập
await page.evaluate(() => { try { localStorage.clear(); } catch (e) {} });
await page.reload();
await page.waitForSelector('#auth');
await page.click('[data-auth="forgot"]');
await page.fill('#fg-user', user);
await page.click('#fg-find button[type="submit"]');
await page.waitForSelector('#recover', { timeout: 5000 }).catch(() => null);
const q = (await page.textContent('#recover').catch(() => '')) || '';
const want = await page.evaluate(() => window.GAME_DATA.RULES.account.security_questions[0].text);
R.check('quên mật khẩu: hiện đúng câu hỏi bảo mật đã chọn lúc đăng ký', q.includes(want), q.slice(0, 120));
await shot(page, 'secq-recover.png');

await page.fill('#rc-a', 'cho vang');
await page.fill('#rc-pass', 'moi12345');
await page.click('#recover button[type="submit"]');
await page.waitForTimeout(800);
const body = (await page.textContent('body')) || '';
R.check('trả lời sai: báo lỗi, vẫn ở màn quên mật khẩu', body.includes('Câu trả lời không đúng') && !!(await page.$('#recover')));

await page.fill('#rc-a', '  Meo   MUN ');
await page.fill('#rc-pass', 'moi12345');
await page.click('#recover button[type="submit"]');
// đăng nhập luôn → màn chọn nhân vật (như MU, DECISIONS "Nhiều nhân vật") → vào game
const inGame = await enterFirst(page).then(() => true).catch(() => false);
R.check('trả lời đúng (khác hoa thường, khoảng trắng): đặt mật khẩu mới, đăng nhập luôn', inGame);

// mật khẩu mới đăng nhập được, mật khẩu cũ thì không
const login = (pw) => page.evaluate(([u, p]) => fetch('/api/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: u, password: p }) }).then((r) => r.status), [user, pw]);
R.check('mật khẩu cũ hết dùng được, mật khẩu mới đăng nhập được', (await login('password123')) === 401 && (await login('moi12345')) === 200);

// Cài đặt: mục câu hỏi bảo mật
await page.click('#tabs [data-tab="menu"]');
await page.click('[data-menu="settings"]');
await page.waitForSelector('[data-act="sq-toggle"]', { timeout: 5000 }).catch(() => null);
const hasBtn = !!(await page.$('[data-act="sq-toggle"]'));
if (hasBtn) {
  await page.click('[data-act="sq-toggle"]');
  await page.selectOption('#sq-q', 'food');
  await page.fill('#sq-a', 'Phở bò');
  await page.fill('#sq-cur', 'moi12345');
  await page.click('#sq-form button[type="submit"]');
  await page.waitForTimeout(600);
}
const q2 = await page.evaluate((u) => fetch('/api/question', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: u }) }).then((r) => r.json()), user);
R.check('Cài đặt: đổi câu hỏi bảo mật', hasBtn && q2.question === 'food', JSON.stringify({ hasBtn, q2 }));
await shot(page, 'secq-settings.png');

// tài khoản không có câu hỏi: chuyển sang gửi yêu cầu cho quản trị
await page.evaluate(() => { try { localStorage.clear(); } catch (e) {} });
await page.reload();
await page.waitForSelector('#auth');
await page.click('[data-auth="forgot"]');
await page.fill('#fg-user', 'khong_co_ai_' + Date.now() % 100000);
await page.click('#fg-find button[type="submit"]');
R.check('tài khoản không có câu hỏi: hiện form nhờ quản trị', await page.waitForSelector('#forgot #fg-contact', { timeout: 5000 }).then(() => true).catch(() => false));

R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
