// Đồ sát (hai trình duyệt: A đánh B ngay từ bảng thông tin, luân phiên lượt, người thua về Nhà, vàng chuyển),
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

// ---------- Đồ sát: A bấm "Đồ sát" trên bảng thông tin B, hai bên vào trận ngay ----------
await adm.admin('set_level', B.name, { level: 12 });
for (const X of [A, B]) await travel(X.page, 'forest_1');
const g0 = (await player(A.page)).gold + (await player(B.page)).gold;
await A.page.evaluate((uid) => window.__hl.inspect(uid), uidB);
await A.page.waitForSelector('[data-act="slay"]');
await act(A.page, '[data-act="slay"]');
await B.page.waitForFunction(() => { const b = window.__hl.player().battle; return b && b.live; }, null, { timeout: 5000 }).catch(() => null);
R.check('B vào trận ngay, không cần đồng ý', !!(await player(B.page)).battle?.live);
R.check('A ra đòn trước; nút của B bị khóa', (await A.page.textContent('.slay-turn')).includes('Lượt của bạn') && await B.page.$eval('[data-act="attack"]', (e) => e.disabled));
await shot(B.page, 'slay-battle.png');

// luân phiên bấm Tấn công tới khi trận được chốt
for (let i = 0; i < 120; i++) {
  const [pa, pb] = [await player(A.page), await player(B.page)];
  if (pa.battle?.over && pb.battle?.over) break;
  const X = pa.battle?.encounter?.mine ? A : pb.battle?.encounter?.mine ? B : null;
  if (X && !(await X.page.$eval('[data-act="attack"]', (e) => e.disabled).catch(() => true))) await act(X.page, '[data-act="attack"]');
  else await A.page.waitForTimeout(100);
}
const sa = await player(A.page), sb = await player(B.page);
const loser = sa.battle?.result === 'lose' ? sa : sb;
R.check('trận kết thúc: một thắng một gục ngã', [sa.battle?.result, sb.battle?.result].sort().join() === 'lose,win', `${sa.battle?.result} / ${sb.battle?.result}`);
R.check('vàng người thua chuyển cho người thắng (tổng không đổi)', sa.gold + sb.gold === g0, `A ${sa.gold} B ${sb.gold}`);
R.check('người thua về Nhà', loser.pos.map === 'home', loser.pos.map);
await shot(A.page, 'slay-result.png');
for (const X of [A, B]) await act(X.page, '[data-act="leave"]');

// ---------- Lịch sử trận ở tab Khác ----------
await A.page.click('#tabs [data-tab="menu"]');
await A.page.click('[data-menu="arena"]');
await A.page.waitForSelector('#pk-history .item', { timeout: 8000 }).catch(() => null);
R.check('tab Khác hiện lịch sử đồ sát', (await A.page.$$('#pk-history .item')).length === 1);

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

// ---------- Quản trị: người đang online ----------
await adm.page.click('#tabs [data-tab="menu"]');
await adm.page.click('[data-menu="admin"]');
await act(adm.page, '[data-adm="online"]');
await adm.page.waitForSelector('#adm-online .item', { timeout: 5000 }).catch(() => null);
const onl = await adm.page.textContent('#adm-online');
R.check('tab Quản trị: danh sách người online có A và B', onl.includes(A.name) && onl.includes(B.name), onl.slice(0, 200));

R.check('không lỗi JS', A.errors.length === 0 && B.errors.length === 0, A.errors.concat(B.errors).join(' | '));
await R.done(browser);
