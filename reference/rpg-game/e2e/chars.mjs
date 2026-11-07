// Nhiều nhân vật (DECISIONS "Nhiều nhân vật"): đổi nhân vật ở Cài đặt, tạo nhân vật thứ hai, thùng đồ chung ở Thủ Kho
// (nhân vật 2 cất vàng, nhân vật 1 thấy), tab khác vào nhân vật khác thì tab này bị đẩy về màn chọn nhân vật, xóa
// nhân vật cần đúng tên + mật khẩu.
// Chạy: node e2e/chars.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, player, send, shot, travel, walkTo, BASE } from './lib.mjs';

const R = reporter('chars');
const browser = await launch();
const A = await newPlayer(browser, { cls: 'dk' });
const { page } = A;
const rows = (pg) => pg.$$('.char-row');

async function toSelect(pg) {
  await pg.click('#tabs [data-tab="menu"]');
  await pg.click('[data-menu="settings"]');
  await pg.click('[data-act="char-switch"]');
  await pg.waitForSelector('.char-row');
}

async function enterChar(pg, name) {
  await pg.click(`.char-row:has-text("${name}") [data-act="char-enter"]`);
  await pg.waitForFunction((n) => window.__hl.player() && window.__hl.player().name === n, name);
}

// 0. F5: vào thẳng nhân vật đang chơi (màn chọn chỉ hiện khi mở game: tab mới, bước 5)
await page.reload();
await page.waitForFunction(() => window.__hl && (window.__hl.player() || document.querySelector('.char-row')));
R.check('F5: vào thẳng nhân vật đang chơi', !(await page.$('.char-row')) && (await player(page)).name === A.name);

// 1. Cài đặt → Đổi nhân vật: màn chọn có nhân vật đầu
await toSelect(page);
R.check('màn chọn nhân vật hiện nhân vật đầu', (await page.textContent('#view')).includes(A.name));

// 2. Tạo nhân vật thứ hai
await page.click('[data-act="char-new"]');
await page.waitForSelector('#hero-name');
const name2 = `N${Math.random().toString(36).slice(2, 8)}`;
await page.fill('#hero-name', name2);
await page.click('.class-opt[data-cls="elf"]');
await page.click('#create button[type="submit"]');
await page.waitForFunction((n) => window.__hl.player() && window.__hl.player().name === n, name2);
R.check('tạo và vào nhân vật thứ hai', (await player(page)).name === name2);

// 3. Nhân vật 2 cất 10 vàng vào thùng chung (đứng cạnh Thủ Kho)
await travel(page, 'village');
// Thủ Kho ở (11, 12) trong priv/maps/village.json: đứng ô dưới
await walkTo(page, 11, 13);
const stored = await send(page, { act: 'gold_store', n: 10 }).catch((e) => ({ ok: false, msg: e.msg }));
const g2 = (await player(page)).view.storage.gold;
R.check('nhân vật 2 cất vàng vào thùng chung', stored.ok !== false && g2 >= 10, JSON.stringify(stored));

// 4. Về nhân vật 1: thùng chung thấy số vàng đó
await toSelect(page);
R.check('màn chọn có 2 nhân vật', (await rows(page)).length === 2);
await enterChar(page, A.name);
R.check('nhân vật 1 thấy vàng trong thùng chung', (await player(page)).view.storage.gold === g2);

// 5. Tab khác vào nhân vật 2: tab này bị đẩy về màn chọn nhân vật
const tab2 = await A.ctx.newPage();
await tab2.goto(`${BASE}/?test=1`);
await tab2.waitForFunction(() => window.__hl && (window.__hl.player() || document.querySelector('.char-row')));
R.check('mở game ở tab mới: hiện màn chọn nhân vật', !!(await tab2.$('.char-row')));
if (!(await tab2.$('.char-row'))) await toSelect(tab2);
await enterChar(tab2, name2);
await page.waitForSelector('.char-row', { timeout: 8000 }).catch(() => null);
R.check('tab cũ bị đẩy về màn chọn nhân vật', !!(await page.$('.char-row')));
await shot(page, 'chars-select.png');
await tab2.close();

// 6. Xóa nhân vật 2: sai tên thì báo lỗi, đúng tên + mật khẩu thì mất
await page.click(`.char-row:has-text("${name2}") [data-act="char-del"]`);
await page.fill('#cd-name', 'Sai Ten');
await page.fill('#cd-pass', 'password123');
await page.click('#char-del-form button[type="submit"]');
await page.waitForTimeout(800);
R.check('xóa sai tên: vẫn còn 2 nhân vật', (await rows(page)).length === 2);
if (!(await page.$('#char-del-form'))) await page.click(`.char-row:has-text("${name2}") [data-act="char-del"]`);
await page.fill('#cd-name', name2);
await page.fill('#cd-pass', 'password123');
await page.click('#char-del-form button[type="submit"]');
await page.waitForFunction(() => document.querySelectorAll('.char-row').length === 1, null, { timeout: 5000 }).catch(() => null);
R.check('xóa đúng tên + mật khẩu: còn 1 nhân vật', (await rows(page)).length === 1);

// 7. Vào lại nhân vật 1 bình thường
await enterChar(page, A.name);
R.check('vào lại nhân vật 1', (await player(page)).name === A.name);

R.check('không lỗi JS', A.errors.length === 0, A.errors.join(' | '));
await R.done(browser);
