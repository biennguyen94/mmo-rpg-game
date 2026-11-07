// Bộ tên (DECISIONS "Bộ tên thay cho tên MU"): quản trị bấm "Tên mới" ở tab Quản trị → người đang chơi tự tải lại, chữ
// hiện ra đổi sang tên mới (Thư viện không còn tên MU, có tên mới); tiếng Anh cũng đổi; bấm "Tên MU" thì về như cũ.
// Chạy: node e2e/names.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, shot } from './lib.mjs';

const R = reporter('names');
const browser = await launch();
const X = await newPlayer(browser, { cls: 'elf' });
const { page } = await adminSession(browser);
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));

const MU = ['Ngọc Ước Nguyện', 'Vé Quảng Trường', 'Dấu Ấn Kundun', 'Bản Đồ Thất Lạc'];
const ALT = ['Ngọc Lam Tinh', 'Vé Quỷ Môn', 'Dấu Ấn Ma Chủ', 'Bản Đồ U Minh'];

// mở một mục Menu từ lưới (đang ở mục khác thì về tab bản đồ trước)
async function openMenu(pg, sec) {
  await pg.click('#tabs [data-tab="map"]').catch(() => null);
  await pg.click('#tabs [data-tab="menu"]');
  await pg.click(`[data-menu="${sec}"]`);
}
async function openAdmin() {
  await openMenu(page, 'admin');
  await page.waitForSelector('[data-adm="name_pack"]');
}
async function libraryText(pg) {
  await openMenu(pg, 'library');
  await pg.click('[data-act="lib-tab"][data-tab2="items"]');
  await pg.waitForTimeout(400);
  return pg.evaluate(() => document.querySelector('#view').innerText);
}
async function waitPack(pg, pack) {
  await pg.waitForFunction((k) => window.I18N && window.I18N.pack === k && window.__hl && window.__hl.player(), pack, { timeout: 15000 }).catch(() => null);
  if (await pg.$('.char-row')) {
    await pg.click('.char-row [data-act="char-enter"]');
    await pg.waitForFunction(() => window.__hl.player());
  }
  return pg.evaluate(() => window.I18N.pack);
}

await openAdmin();
R.check('tab Quản trị có thẻ Bộ tên, đang dùng tên MU', (await page.textContent('#view')).includes('Đang dùng: Tên MU'));
const before = await libraryText(X.page);
R.check('tên MU: Thư viện có tên MU', MU.some((t) => before.includes(t)));

// đổi sang tên mới: người chơi đang mở game tự tải lại
await openAdmin();
await page.click('[data-adm="name_pack"][data-pack="alt"]');
await page.waitForFunction(() => document.querySelector('#view').innerText.includes('Đang dùng: Tên mới'), null, { timeout: 5000 }).catch(() => null);
R.check('quản trị: đang dùng Tên mới', (await page.textContent('#view')).includes('Đang dùng: Tên mới'));
R.check('người đang chơi tự tải lại, nhận bộ tên mới', (await waitPack(X.page, 'alt')) === 'alt');
const after = await libraryText(X.page);
const leftMu = MU.filter((t) => after.includes(t));
R.check('tên mới: Thư viện không còn tên MU', leftMu.length === 0, leftMu.join(', '));
R.check('tên mới: Thư viện có tên mới', ALT.some((t) => after.includes(t)));
R.check('đổi tên trong câu, giữ số', await X.page.evaluate(() => window.I18N.tr('Cần 3 Ngọc Ước Nguyện để vào Quảng Trường Quỷ.') === 'Cần 3 Ngọc Lam Tinh để vào Quỷ Môn Trận.'));
await shot(X.page, 'names-alt.png');

// tiếng Anh + tên mới
await X.page.evaluate(() => localStorage.setItem('hl-lang', 'en'));
await X.page.reload();
await waitPack(X.page, 'alt');
const en = await X.page.evaluate(() => [window.I18N.tr('Quảng Trường Quỷ'), window.I18N.tr('Ngọc Ước Nguyện'), window.I18N.tr('Dao Găm Kris')]);
R.check('tiếng Anh: tên mới tiếng Anh', en[0] === 'Demon Gate Trial' && en[1] === 'Azure Gem' && en[2] === 'Wavy Dagger', en.join(' | '));
await X.page.evaluate(() => localStorage.setItem('hl-lang', 'vi'));

// về tên MU
await openAdmin();
await page.click('[data-adm="name_pack"][data-pack="mu"]');
await X.page.reload();
R.check('về tên MU', (await waitPack(X.page, 'mu')) === 'mu');
const back = await libraryText(X.page);
R.check('tên MU: Thư viện có lại tên MU', MU.some((t) => back.includes(t)));

R.check('không lỗi JS', errors.length === 0 && X.errors.length === 0, errors.concat(X.errors).join(' | '));
await R.done(browser);
