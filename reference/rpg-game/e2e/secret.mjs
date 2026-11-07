// Động Bí Ẩn (DECISIONS "Động Bí Ẩn"): quản trị mở động ngay (thẻ Động Bí Ẩn ở tab Quản trị) → Lão Từ báo đêm nay mở,
// gọi Thạch Long Ẩn thức giấc, nhân vật cấp thấp bước vào khe đá bị chặn vì cấp; quản trị đóng → về theo lịch.
// Chạy: node e2e/secret.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, meetNpc, send, shot } from './lib.mjs';

const R = reporter('secret');
const browser = await launch();
const X = await newPlayer(browser, { cls: 'dk' });
const { page, admin } = await adminSession(browser);
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));

async function openAdmin() {
  await page.click('#tabs [data-tab="map"]').catch(() => null);
  await page.click('#tabs [data-tab="menu"]');
  await page.click('[data-menu="admin"]');
  await page.waitForSelector('[data-adm="secret"]');
}

await openAdmin();
R.check('tab Quản trị có thẻ Động Bí Ẩn', (await page.textContent('#view')).includes('Động Bí Ẩn'));
await page.click('[data-adm="secret"][data-mode="open"]');
await page.waitForFunction(() => document.querySelector('#view').innerText.includes('Quản trị đang mở'), null, { timeout: 5000 }).catch(() => null);
R.check('mở ngay: đang mở, quản trị đang mở', (await page.textContent('#view')).includes('Quản trị đang mở'));

await page.click('[data-adm="secret_boss"]');
await page.waitForTimeout(800);
const boss = await page.evaluate(() => window.Net.admin('secret_boss').then(() => 'ok', (e) => e.msg));
R.check('gọi Thạch Long Ẩn (gọi lần hai báo đang thức)', /đang thức/.test(boss), boss);

// người chơi cấp 1: tới Đền Cổ (quản trị nâng cấp 34 + cộng vàng để dịch chuyển), hỏi Lão Từ, bước vào khe đá bị chặn vì cấp
await admin('set_level', X.name, { level: 34 });
await admin('add_gold', X.name, { amount: 5000 });
await X.page.waitForFunction(() => window.__hl.player().level === 34 && window.__hl.player().gold > 1000, null, { timeout: 8000 });
const tr = await send(X.page, { act: 'travel', to: 'vn_den_co' }).catch((e) => ({ ok: false, msg: e.msg }));
R.check('dịch chuyển tới Đền Cổ', (await X.page.evaluate(() => window.__hl.player().pos.map)) === 'vn_den_co', tr.msg || '');
R.check('Lão Từ: đêm nay khe đá đã hé mở', (await meetNpc(X.page, 'monk')) && (await X.page.textContent('#view')).includes('hé mở'));
await shot(X.page, 'secret-monk.png');
await X.page.click('[data-act="npc-close"]').catch(() => null);
// khe đá ở (14, 3): đi tới ô ngay dưới rồi bước lên
await X.page.evaluate(() => window.__hl.walkTo(14, 4));
await X.page.waitForFunction(() => { const p = window.__hl.player().pos; return p.x === 14 && p.y === 4; }, null, { timeout: 15000 }).catch(() => null);
const r34 = await send(X.page, { act: 'move', dir: 'up' }).catch((e) => ({ ok: false, msg: e.msg }));
R.check('cấp 34 bước vào khe đá: bị chặn (cần cấp 38)', (await X.page.evaluate(() => window.__hl.player().pos.map)) === 'vn_den_co');
await admin('set_level', X.name, { level: 40 });
await X.page.waitForFunction(() => window.__hl.player().level === 40, null, { timeout: 8000 });
await send(X.page, { act: 'move', dir: 'up' }).catch(() => null);
await X.page.waitForFunction(() => window.__hl.player().pos.map === 'vn_dong_bi_an', null, { timeout: 5000 }).catch(() => null);
R.check('cấp 40 bước vào khe đá: vào Động Bí Ẩn', (await X.page.evaluate(() => window.__hl.player().pos.map)) === 'vn_dong_bi_an');
await X.page.waitForTimeout(2500);
R.check('trong động thấy Thạch Long Ẩn', await X.page.evaluate(() => window.__hl.world().monsters.some((m) => m.boss)));
R.check('quái trong động có tên, cấp (không phải cấp 1)', await X.page.evaluate(() => { const ms = window.__hl.world().monsters; return ms.length > 0 && ms.every((m) => m.name && m.level > 1); }));
const top = await X.page.textContent('.map-top');
R.check('thanh trên: khoảng cấp quái động', /Nơi bí ẩn · quái cấp \d+–\d+/.test(top) && !top.includes('undefined'), top.slice(0, 160));
await shot(X.page, 'secret-cave.png');

await openAdmin();
await page.click('[data-adm="secret"][data-mode="auto"]');
await page.waitForFunction(() => document.querySelector('#view').innerText.includes('Theo lịch'), null, { timeout: 5000 }).catch(() => null);
R.check('theo lịch', (await page.textContent('#view')).includes('Theo lịch'));
// đóng hẳn: người trong động bị đưa ra Đền Cổ (SecretWatch, mỗi 20 giây)
await page.click('[data-adm="secret"][data-mode="close"]');
await X.page.waitForFunction(() => window.__hl.player().pos.map === 'vn_den_co', null, { timeout: 30000 }).catch(() => null);
R.check('đóng động: người trong động ra Đền Cổ', (await X.page.evaluate(() => window.__hl.player().pos.map)) === 'vn_den_co');
await page.click('[data-adm="secret"][data-mode="auto"]');
R.check('không lỗi JS', errors.length === 0 && X.errors.length === 0, errors.concat(X.errors).join(' | '));
await R.done(browser);
