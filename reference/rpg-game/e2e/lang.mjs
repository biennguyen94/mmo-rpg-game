// Phase 10 (U1): hai ngôn ngữ. Bấm "English" ở trang đăng nhập → tạo nhân vật → đi bản đồ, mở Menu, Cài đặt, túi đồ:
// chữ hiện ra phải gần hết là tiếng Anh (đếm từ có dấu tiếng Việt, trừ tên người chơi); đổi về Tiếng Việt được.
// Chạy: node e2e/lang.mjs [url] [thư_mục_ảnh]
import { launch, reporter, BASE, shot } from './lib.mjs';

const R = reporter('lang');
const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, extraHTTPHeaders: { 'x-forwarded-for': `10.9.${Math.floor(Math.random() * 250)}.${1 + Math.floor(Math.random() * 250)}` } });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('dialog', (d) => d.accept());
await page.goto(`${BASE}/?test=1`);
await page.waitForSelector('#auth');
await page.click('[data-act="lang"][data-lang="en"]');
await page.waitForSelector('#auth');
R.check('trang đăng nhập đổi sang tiếng Anh', await page.evaluate(() => window.I18N.lang === 'en'));
const user = 'l_' + Math.random().toString(36).slice(2, 8);
await page.click('[data-auth="register"]');
await page.fill('#auth-user', user);
await page.fill('#auth-pass', 'password123');
await page.click('#auth button[type="submit"]');
await page.waitForSelector('#hero-name');
await page.fill('#hero-name', 'En' + Math.random().toString(36).slice(2, 7));
await page.click('#create button[type="submit"]');
await page.waitForFunction(() => window.__hl && window.__hl.player());

// tỉ lệ từ còn dấu tiếng Việt trong chữ đang hiện (bỏ ô chat người chơi)
const viRatio = () => page.evaluate(() => {
  const words = document.body.innerText.split(/\s+/).filter((w) => /\p{L}/u.test(w));
  const vi = words.filter((w) => /[À-ỹĐđ]/.test(w));
  return { ratio: vi.length / Math.max(1, words.length), sample: vi.slice(0, 12).join(' ') };
});
for (const [label, go] of [['bản đồ', () => window.__hl.tab('map')], ['nhân vật', () => window.__hl.tab('hero')], ['túi đồ', () => window.__hl.tab('bag')], ['menu', () => window.__hl.menu(null)], ['cài đặt', () => window.__hl.menu('settings')], ['nhiệm vụ', () => window.__hl.menu('quests')]]) {
  await page.evaluate(go);
  await page.waitForTimeout(300);
  const r = await viRatio();
  R.check(`${label}: ≥ 95 % chữ tiếng Anh`, r.ratio <= 0.05, `${Math.round(r.ratio * 100)}% — ${r.sample}`);
}
await page.evaluate(() => window.__hl.tab('map'));
await page.waitForTimeout(300);
await shot(page, 'lang-en-map.png');
await page.evaluate(() => window.__hl.menu('settings'));
await page.click('[data-act="lang"][data-lang="vi"]');
await page.waitForFunction(() => window.I18N && window.I18N.lang === 'vi' && window.__hl && window.__hl.player(), null, { timeout: 15000 }).catch(() => null);
R.check('đổi về Tiếng Việt', await page.evaluate(() => window.I18N.lang === 'vi'));
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
