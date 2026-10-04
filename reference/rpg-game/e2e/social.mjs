// Social: hai trình duyệt (A, B) — tổ đội, bạn bè + tin riêng, chat thế giới, giao dịch trực tiếp (vàng +
// đồ, bấm trên bảng giao dịch), chợ (A rao, B mua, A nhận tiền qua hộp thư).
// Chạy: node e2e/social.mjs [url] [thư_mục_ảnh]. Cần scripts/e2e_seed.exs (tài khoản quản trị).
import { launch, reporter, newPlayer, adminSession, player, ui, send, act, travel, meetNpc, leaveNpc, shot } from './lib.mjs';

const R = reporter('social');
const browser = await launch();
const A = await newPlayer(browser, { cls: 'dk' });
const B = await newPlayer(browser, { cls: 'elf' });
const adm = await adminSession(browser);
await adm.admin('add_gold', A.name, { amount: 5000 });
await adm.admin('give_item', A.name, { id: 'herb', count: 5 });
const uidA = await adm.lookup(A.name);
const uidB = await adm.lookup(B.name);
for (const X of [A, B]) await travel(X.page, 'village');
await A.page.waitForFunction(() => window.__hl.player().gold >= 5000);
R.check('quản trị tặng vàng / đồ cho người đang online', (await player(A.page)).gold >= 5000 && (await player(A.page)).inv.herb === 5);

// ---------- Tổ đội: A mời, B bấm "Vào tổ đội" ----------
await A.page.evaluate((uid) => window.Net.party('invite', { uid }), uidB);
await B.page.waitForFunction(() => window.__hl.ui().dialog === 'invite', null, { timeout: 5000 }).catch(() => null);
R.check('B nhận lời mời tổ đội', (await ui(B.page)).dialog === 'invite');
await act(B.page, 'party-accept');
await A.page.waitForFunction(() => (window.__hl.ui().party || { members: [] }).members.length === 2, null, { timeout: 5000 }).catch(() => null);
R.check('cả hai cùng tổ đội', (await ui(A.page)).party?.members.length === 2 && (await ui(B.page)).party?.members.length === 2);
await shot(B.page, 'social-party.png');
await B.page.evaluate(() => window.Net.party('leave'));

// ---------- Bạn bè + tin riêng ----------
await A.page.evaluate((name) => window.Net.friends('request', { name }), B.name);
await B.page.evaluate((uid) => window.Net.friends('accept', { uid }), uidA);
const fl = await A.page.evaluate(() => window.Net.friends('list'));
R.check('A và B thành bạn', (fl.friends || []).some((f) => f.id === uidB), JSON.stringify(fl).slice(0, 200));
await B.page.evaluate((uid) => window.Net.dm('send', { uid, text: 'chào bạn' }), uidA);
const h = await A.page.evaluate((uid) => window.Net.dm('history', { uid }), uidB);
R.check('A nhận tin riêng của B', JSON.stringify(h).includes('chào bạn'));

// ---------- Chat thế giới: gõ trên ô chat ----------
await A.page.fill('#chat-input', 'xin chào cả làng');
await A.page.press('#chat-input', 'Enter');
await B.page.waitForFunction(() => document.querySelector('#chat-log') && document.querySelector('#chat-log').textContent.includes('xin chào cả làng'), null, { timeout: 5000 }).catch(() => null);
R.check('B thấy tin chat của A', (await B.page.textContent('#chat-log')).includes('xin chào cả làng'));

// ---------- Giao dịch: A mời, B bấm Xem; A đặt 300 vàng + 2 Cỏ Thuốc; hai bên bấm Xác nhận ----------
const a0 = await player(A.page), b0 = await player(B.page);
await A.page.evaluate((uid) => window.Net.trade('request', { uid }), uidB);
await B.page.waitForFunction(() => window.__hl.ui().dialog === 'trade', null, { timeout: 5000 }).catch(() => null);
await act(B.page, '[data-act="trade-op"][data-op="accept"]');
await A.page.waitForFunction(() => window.__hl.ui().trade === 'open', null, { timeout: 5000 }).catch(() => null);
R.check('mở bảng giao dịch hai bên', (await ui(A.page)).trade === 'open' && (await ui(B.page)).trade === 'open');
await A.page.selectOption('#trade-add select[name="item"]', 'herb');
await A.page.fill('#trade-add input[name="count"]', '2');
await A.page.click('#trade-add button[type="submit"]:not([name])');
await A.page.waitForTimeout(400);
await A.page.fill('#trade-add input[name="gold"]', '300');
await A.page.click('#trade-add button[name="set"]');
await B.page.waitForFunction(() => document.body.textContent.includes('300 vàng'), null, { timeout: 5000 }).catch(() => null);
await shot(B.page, 'social-trade.png');
await act(A.page, '[data-act="trade-op"][data-op="ready"]');
await act(B.page, '[data-act="trade-op"][data-op="ready"]');
await A.page.waitForFunction(() => !window.__hl.ui().trade, null, { timeout: 8000 }).catch(() => null);
await B.page.waitForFunction((g) => window.__hl.player().gold === g, b0.gold + 300, { timeout: 5000 }).catch(() => null);
const a1 = await player(A.page), b1 = await player(B.page);
R.check('giao dịch xong: A −300 vàng −2 Cỏ Thuốc, B +300 +2', a1.gold === a0.gold - 300 && a1.inv.herb === 3 && b1.gold === b0.gold + 300 && b1.inv.herb === 2, `A ${a0.gold}→${a1.gold}, B ${b0.gold}→${b1.gold}`);

// ---------- Chợ: A rao 1 Cỏ Thuốc giá 100, B mua, A nhận tiền qua hộp thư ----------
R.check('A gặp Chủ Chợ', await meetNpc(A.page, 'merchant'));
let r = await send(A.page, { act: 'market_sell', id: 'herb', count: 1, price: 100 });
R.check('A rao bán Cỏ Thuốc', r.inv.herb === 2);
await leaveNpc(A.page);
R.check('B gặp Chủ Chợ', await meetNpc(B.page, 'merchant'));
const list = await B.page.evaluate(() => window.Net.market(''));
const l = (list.listings || []).find((x) => x.seller_id === uidA && x.item === 'herb' && x.price === 100);
R.check('B thấy hàng của A trên chợ', !!l, JSON.stringify(list.listings || []).slice(0, 300));
const b2 = await player(B.page);
if (l) r = await send(B.page, { act: 'market_buy', listing: l.id });
R.check('B mua: −100 vàng, +1 Cỏ Thuốc', r.gold === b2.gold - 100 && r.inv.herb === b2.inv.herb + 1);
await shot(B.page, 'social-market.png');
const fee = await A.page.evaluate(() => window.Net.market('').then((m) => m.fee));
const mails = await A.page.evaluate(() => window.Net.mail());
const sale = (mails.mails || []).find((m) => !m.claimed && m.gold > 0);
R.check('A có thư tiền bán hàng (trừ phí chợ)', !!sale && sale.gold === 100 - Math.floor((100 * fee) / 100), JSON.stringify(mails).slice(0, 300));
const a2 = await player(A.page);
if (sale) r = await send(A.page, { act: 'mail_claim', id: sale.id });
R.check('A nhận tiền từ thư', r.gold === a2.gold + (sale ? sale.gold : 0));

R.check('không lỗi JS (A, B)', A.errors.length === 0 && B.errors.length === 0, [...A.errors, ...B.errors].join(' | '));
await R.done(browser);
