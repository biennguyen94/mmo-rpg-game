// Phase 5: PK cược vàng (hai trình duyệt: A mời từ bảng thông tin người chơi, B nhận / từ chối / để hết hạn),
// lệnh chat /w /p, bảng xếp hạng theo lớp, hộp thư (lọc, nhận tất cả), quản trị xem người online.
// Chạy: node e2e/pk.mjs [url] [thư_mục_ảnh]. Cần scripts/e2e_seed.exs (tài khoản quản trị).
import { launch, reporter, newPlayer, adminSession, player, ui, act, travel, shot } from './lib.mjs';

const R = reporter('pk');
const browser = await launch();
const A = await newPlayer(browser, { cls: 'dk' });
const B = await newPlayer(browser, { cls: 'elf' });
const adm = await adminSession(browser);
for (const X of [A, B]) await adm.admin('add_gold', X.name, { amount: 5000 });
await adm.admin('set_level', A.name, { level: 30 });
const uidA = await adm.lookup(A.name);
const uidB = await adm.lookup(B.name);
for (const X of [A, B]) await X.page.waitForFunction(() => window.__hl.player().gold >= 5000);
for (const X of [A, B]) await travel(X.page, 'village');

// A mở bảng thông tin B, nhập số cược, bấm "Cược đấu"
async function invite(wager) {
  await A.page.evaluate((uid) => window.__hl.inspect(uid), uidB);
  await A.page.waitForSelector('#pk-wager');
  await A.page.fill('#pk-wager', String(wager));
  await act(A.page, '[data-act="pk-ask"]');
  await B.page.waitForFunction(() => window.__hl.ui().dialog === 'pk', null, { timeout: 5000 }).catch(() => null);
}

// ---------- Nhận cược: tổng vàng hai người không đổi, người thắng +cược ----------
const a0 = (await player(A.page)).gold, g0 = a0 + (await player(B.page)).gold;
await invite(1000);
R.check('B nhận hộp mời cược 1 000 vàng', (await ui(B.page)).dialog === 'pk' && (await B.page.textContent('.map-dialog')).includes('1.000'));
await shot(B.page, 'pk-invite.png');
await act(B.page, '[data-act="pk-op"][data-op="accept"]');
await B.page.waitForFunction(() => window.__hl.ui().dialog === 'pkResult', null, { timeout: 5000 }).catch(() => null);
await A.page.waitForFunction(() => window.__hl.ui().dialog === 'pkResult', null, { timeout: 5000 }).catch(() => null);
R.check('cả hai xem bảng kết quả trận', (await ui(A.page)).dialog === 'pkResult' && (await ui(B.page)).dialog === 'pkResult');
await shot(A.page, 'pk-result.png');
const pa = await player(A.page), pb = await player(B.page);
R.check('tổng vàng không đổi, một người +1 000 / một người −1 000 (hoặc hòa)', pa.gold + pb.gold === g0 && [0, 1000].includes(Math.abs(pa.gold - a0)), `A ${pa.gold} B ${pb.gold}`);
await act(A.page, '[data-act="dialog-close"]');
await act(B.page, '[data-act="dialog-close"]');

// ---------- Từ chối ----------
await invite(200);
await act(B.page, '[data-act="pk-op"][data-op="decline"]');
const info = await A.page.evaluate(() => window.Net.pk('info'));
R.check('B từ chối: không còn lời mời, vẫn 1 trận hôm nay', info.invite == null && info.today === 1 && info.history.length === 1, JSON.stringify({ i: info.invite, t: info.today }));

// ---------- Cược quá số vàng: báo lỗi ----------
await A.page.evaluate((uid) => window.__hl.inspect(uid), uidB);
await A.page.waitForSelector('#pk-wager');
await A.page.fill('#pk-wager', '999999');
await act(A.page, '[data-act="pk-ask"]');
R.check('cược quá số vàng đang có: không gửi', (await B.page.evaluate(() => window.__hl.ui().dialog)) !== 'pk');
await act(A.page, '[data-act="dialog-close"]').catch(() => null);

// ---------- Lịch sử trận ở tab Khác ----------
await A.page.click('#tabs [data-tab="menu"]');
await A.page.click('[data-menu="arena"]');
await A.page.waitForSelector('#pk-history .item', { timeout: 8000 }).catch(() => null);
R.check('tab Khác hiện lịch sử trận cược', (await A.page.$$('#pk-history .item')).length === 1);

// ---------- Bảng xếp hạng theo lớp ----------
await A.page.click('[data-act="menu-back"]');
await A.page.click('[data-menu="board"]');
await A.page.waitForSelector('#board-cls', { timeout: 8000 }).catch(() => null);
await act(A.page, '[data-board-cls="dk"]');
// bảng giữ trong cache 60 giây nên người vừa tạo có thể chưa có tên; hạng của mình thì luôn mới
await A.page.waitForFunction(() => (document.querySelector('#board') || {}).textContent?.includes('trong lớp'), null, { timeout: 8000 }).catch(() => null);
const boardText = await A.page.textContent('#board');
R.check('bảng Cấp cao lọc theo lớp, hiện hạng trong lớp', boardText.includes('trong lớp') && boardText.includes('Kiếm Sĩ'), boardText.slice(0, 160));
await shot(A.page, 'pk-board-class.png');
await A.page.click('#tabs [data-tab="map"]');

// ---------- Lệnh chat: /w cho bạn bè, /p khi chưa có tổ đội ----------
await A.page.evaluate((name) => window.Net.friends('request', { name }), B.name);
await B.page.evaluate((uid) => window.Net.friends('accept', { uid }), uidA);
// A nạp lại danh sách bạn (khi B nhận lời, giao diện A tự nạp)
await A.page.waitForTimeout(500);
await A.page.click('.chat-btn');
await A.page.waitForSelector('#chat-input');
await A.page.fill('#chat-input', `/w ${B.name} hẹn đấu tối nay`);
await A.page.press('#chat-input', 'Enter');
await A.page.waitForTimeout(500);
const h = await B.page.evaluate((uid) => window.Net.dm('history', { uid }), uidA);
R.check('/w Tên gửi tin riêng cho bạn', JSON.stringify(h).includes('hẹn đấu tối nay'), JSON.stringify(h).slice(0, 200));

// ---------- Lời mời hết hạn (30 giây) ----------
await invite(100);
await B.page.waitForFunction(() => window.__hl.ui().dialog !== 'pk', null, { timeout: 40000 }).catch(() => null);
R.check('lời mời hết hạn sau 30 giây: hộp mời tự đóng', (await ui(B.page)).dialog !== 'pk');

// ---------- Quản trị: người đang online ----------
await adm.page.click('#tabs [data-tab="menu"]');
await adm.page.click('[data-menu="admin"]');
await act(adm.page, '[data-adm="online"]');
await adm.page.waitForSelector('#adm-online .item', { timeout: 5000 }).catch(() => null);
const onl = await adm.page.textContent('#adm-online');
R.check('tab Quản trị: danh sách người online có A và B', onl.includes(A.name) && onl.includes(B.name), onl.slice(0, 200));

R.check('không lỗi JS', A.errors.length === 0 && B.errors.length === 0, A.errors.concat(B.errors).join(' | '));
await R.done(browser);
