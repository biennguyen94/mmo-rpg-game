// Pháp Trường Huyết Nguyệt (DECISIONS "Pháp Trường Huyết Nguyệt"): cổng phía nam Làng → bản đồ 60×40 không quái, ngày
// thường an toàn (nút đồ sát khóa); quản trị bấm 🩸 Mở ngay ở tab Quản trị → dải đếm giờ hiện ở mọi người, bản đồ phủ
// trăng máu; A đồ sát B: B gục không mất vàng, về Làng, chưa vào lại được; bảng xếp hạng ở Bảng Huyết Nguyệt;
// 🤖 Gọi tất cả bot vào (nếu server có bot); 🌕 Đóng sớm → top 1 nhận thư ngọc.
// Chạy: node e2e/bloodmoon.mjs [url] [thư_mục_ảnh]. Cần scripts/e2e_seed.exs (tài khoản quản trị).
import { launch, reporter, newPlayer, adminSession, player, act, travel, meetNpc, leaveNpc, walkTo, shot } from './lib.mjs';

const R = reporter('bloodmoon');
const browser = await launch();
const A = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
const B = await newPlayer(browser, { cls: 'elf' });
const adm = await adminSession(browser);
const ap = adm.page;
ap.on('dialog', (d) => d.accept());
await adm.admin('set_level', A.name, { level: 40 });
await adm.admin('add_stats', A.name, { str: 400, vit: 300, agi: 100 });
await adm.admin('set_level', B.name, { level: 15 });
for (const X of [A, B]) await adm.admin('add_gold', X.name, { amount: 3000 });
for (const X of [A, B]) await X.page.waitForFunction(() => window.__hl.player().gold >= 3000);
const uidB = await adm.lookup(B.name);
const MAP = await A.page.evaluate(() => window.GAME_DATA.RULES.bloodMoon.map);
// sự kiện còn mở từ lần chạy trước: đóng
await ap.evaluate(() => window.Net.admin('blood_moon_close').catch(() => null));

// ---------- bản đồ: cổng phía nam Làng, 60×40, không quái, an toàn ----------
for (const X of [A, B]) R.check(`${X === A ? 'A' : 'B'} qua cổng Làng tới Pháp Trường`, await travel(X.page, MAP));
const m = await A.page.evaluate((id) => { const m = window.GAME_DATA.WORLD.maps[id]; return { w: m.tiles[0].length, h: m.tiles.length, name: m.name }; }, MAP);
R.check('bản đồ 60×40', m.w === 60 && m.h === 40, JSON.stringify(m));
const w = await A.page.evaluate(() => window.__hl.world());
R.check('không có quái', (w.monsters || []).length === 0);
await shot(A.page, 'bloodmoon-calm.png');
const closed = await A.page.evaluate((uid) => window.Net.slay(uid).then(() => 'ok').catch((e) => e.msg), uidB);
R.check('ngày thường không đồ sát được', /Huyết Nguyệt/.test(closed), closed);

R.check('gặp Quan Giám Trảm', await meetNpc(A.page, 'executioner'));
const card = await A.page.textContent('#view');
R.check('thẻ NPC: luật, ngọc, quà top 3', /không mất vàng/.test(card) && /hạng 1/.test(card), card.slice(0, 120));
await shot(A.page, 'bloodmoon-npc.png');
await leaveNpc(A.page);

// ---------- quản trị mở ở tab Quản trị ----------
await ap.evaluate(() => window.__hl.menu('admin'));
await ap.waitForSelector('#adm-bm');
await ap.$eval('#adm-bm', (e) => e.scrollIntoView({ block: 'center' }));
await shot(ap, 'bloodmoon-admin.png');
// quà top chỉnh ở Quản trị: hạng 1 = 5 Ngọc Hỗn Nguyên, hạng 2 = 2 Ngọc Tâm Linh, còn lại 0
await ap.click('[data-adm="blood_moon_rewards"][data-reset]');
await ap.waitForTimeout(400);
for (const inp of await ap.$$('#adm-bm input[id^="adm-bm-rw-"]')) await inp.fill('0');
await ap.fill('#adm-bm-rw-0-jewel_chaos', '5');
await ap.fill('#adm-bm-rw-1-jewel_soul', '2');
await ap.click('[data-adm="blood_moon_rewards"]:not([data-reset])');
await ap.waitForTimeout(500);
const rw = await ap.evaluate(() => window.Net.admin('blood_moon').then((x) => x.blood_moon.rewards));
R.check('Quản trị lưu quà top', rw[0].jewel_chaos === 5 && rw[0].jewel_bless === 0 && rw[1].jewel_soul === 2, JSON.stringify(rw));
await ap.$eval('#adm-bm', (e) => e.scrollIntoView({ block: 'center' }));
await shot(ap, 'bloodmoon-rewards.png');
await ap.fill('#adm-bm-min', '10');
await ap.click('[data-adm="blood_moon_open"]');
await A.page.waitForSelector('#bm-chip .bm-chip.on', { timeout: 8000 }).catch(() => null);
R.check('mở: dải 🩸 đếm giờ hiện ở người chơi', !!(await A.page.$('#bm-chip .bm-chip.on')));
R.check('dải ở B cũng hiện, có số phút còn lại', /còn\s*\d+:\d\d/.test(await B.page.textContent('#bm-chip').catch(() => '')));
await ap.waitForFunction(() => /Đang mở/.test(document.querySelector('#adm-bm').textContent), null, { timeout: 5000 }).catch(() => null);
R.check('thẻ quản trị: Đang mở', /Đang mở/.test(await ap.textContent('#adm-bm')));
await A.page.waitForTimeout(600);
await shot(A.page, 'bloodmoon-open.png');

// ---------- A đồ sát B: không mất vàng, về Làng, khóa vào lại ----------
const gB = (await player(B.page)).gold;
// A lại sát bên B (không cánh: tầm 1 ô)
const bp = (await player(B.page)).pos;
for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
  await walkTo(A.page, bp.x + dx, bp.y + dy);
  const ap2 = (await player(A.page)).pos;
  if (Math.max(Math.abs(ap2.x - bp.x), Math.abs(ap2.y - bp.y)) <= 1) break;
}
const r = await A.page.evaluate((uid) => window.Net.slay(uid).then(() => 'ok').catch((e) => e.msg), uidB);
R.check('mở rồi: đồ sát được', r === 'ok', r);
for (let i = 0; i < 160; i++) {
  const [pa, pb] = [await player(A.page), await player(B.page)];
  if (pa.battle?.over && pb.battle?.over) break;
  const X = pa.battle?.encounter?.mine ? A : pb.battle?.encounter?.mine ? B : null;
  if (X && !(await X.page.$eval('[data-act="attack"]', (e) => e.disabled).catch(() => true))) await act(X.page, '[data-act="attack"]');
  else await A.page.waitForTimeout(100);
}
const pa = await player(A.page), pb = await player(B.page);
R.check('A thắng, B gục', pa.battle?.result === 'win' && pb.battle?.result === 'lose', `${pa.battle?.result} / ${pb.battle?.result}`);
R.check('B không mất vàng, về Làng', pb.gold === gB && pb.pos.map === 'village', `${gB} → ${pb.gold} @ ${pb.pos.map}`);
await shot(A.page, 'bloodmoon-win.png');
await act(B.page, 'leave').catch(() => null);
const back = await B.page.evaluate((to) => window.Net.send({ act: 'travel', to }).then((x) => x.msg || ''), MAP);
R.check('B chưa vào lại được ngay', /vừa gục/.test(back), back);
await act(A.page, 'leave').catch(() => null);
await A.page.waitForFunction(() => /bạn hạ\s*1/.test(document.querySelector('#bm-chip')?.textContent || ''), null, { timeout: 5000 }).catch(() => null);
await A.page.waitForTimeout(5000);
await shot(A.page, 'bloodmoon-chip.png');
// top 3 mỗi người một ô: điểm hiện đủ (không bị cắt), ô của mình tô sáng; 🏆 mở top 10
const cell = await A.page.evaluate(() => {
  const c = document.querySelector('#bm-chip .bm-cell.me');
  if (!c) return null;
  const b = c.querySelector('b'), r = b.getBoundingClientRect(), cr = c.getBoundingClientRect();
  return { txt: c.textContent, score: b.textContent, inside: r.right <= cr.right + 0.5 && r.width > 0 };
});
R.check('dải: ô top 1 của A, điểm hiện đủ', cell && cell.score === '1' && cell.inside, JSON.stringify(cell));
await A.page.click('[data-act="bm-top"]');
R.check('🏆 mở bảng top 10', !!(await A.page.$('#bm-chip .bm-list')));
await shot(A.page, 'bloodmoon-top10.png');
await A.page.click('[data-act="bm-top"]');
R.check('dải: bạn hạ 1, top có tên A', /bạn hạ\s*1/.test(await A.page.textContent('#bm-chip')) && (await A.page.textContent('#bm-chip')).includes(A.name));

R.check('Bảng Huyết Nguyệt: bảng xếp hạng có A', await meetNpc(A.page, 'blood_board') && (await A.page.textContent('#view')).includes(A.name));
await shot(A.page, 'bloodmoon-board.png');
await leaveNpc(A.page);

// ---------- gọi bot ----------
await ap.click('[data-adm="blood_moon_bots"]');
await ap.waitForTimeout(800);
await ap.$eval('#adm-bm', (e) => e.scrollIntoView({ block: 'center' }));
await shot(ap, 'bloodmoon-admin-open.png');
const st = await ap.evaluate(() => window.Net.admin('blood_moon').then((x) => x.blood_moon));
R.check('🤖 gọi bot: báo số bot đã gọi', st.bots >= 0, JSON.stringify({ bots: st.bots }));
if (st.bots > 0) {
  await A.page.waitForFunction(() => (window.__hl.world().players || []).length > 1, null, { timeout: 30000 }).catch(() => null);
  R.check('bot vào Pháp Trường', (await A.page.evaluate(() => (window.__hl.world().players || []).length)) > 1);
  await shot(A.page, 'bloodmoon-bots.png');
}

// ---------- đóng sớm: top 1 nhận thư ----------
await ap.click('[data-adm="blood_moon_close"]');
await A.page.waitForFunction(() => !document.querySelector('#bm-chip .bm-chip.on'), null, { timeout: 8000 }).catch(() => null);
R.check('đóng: dải biến mất', !(await A.page.$('#bm-chip .bm-chip.on')));
await A.page.waitForTimeout(1500);
const mails = await A.page.evaluate(() => window.Net.mail().then((x) => x.mails || []).catch(() => []));
const mm = mails.find((x) => /Huyết Nguyệt/.test(x.subject));
R.check('A (hạng 1) nhận thư ngọc theo mức Quản trị đặt (5 Ngọc Hỗn Nguyên)', !!mm && JSON.stringify(mm).includes('jewel_chaos') && !JSON.stringify(mm).includes('jewel_bless'), JSON.stringify(mm || mails).slice(0, 200));
// trả quà top về mặc định cho lần chạy sau
await ap.evaluate(() => window.Net.admin('blood_moon_rewards', { reset: true }).catch(() => null));
R.check('không lỗi JS', A.errors.length === 0 && B.errors.length === 0, [...A.errors, ...B.errors].join(' | '));
await R.done(browser);
