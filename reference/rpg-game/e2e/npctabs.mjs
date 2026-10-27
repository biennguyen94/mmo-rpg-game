// Khung NPC gọn (DECISIONS "Khung NPC gọn"): Thợ Rèn và Lão Hỗn Nguyên chia tab (dính trên đầu khi cuộn, nhớ tab đã mở),
// món ép được lên đầu, chạm vào món mở chi tiết, món thiếu nguyên liệu / đã tối đa gập lại; chấm báo số việc làm được.
// Chạy: node e2e/npctabs.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, travel, meetNpc, leaveNpc, act, shot, overflowX } from './lib.mjs';

const R = reporter('npctabs');
const browser = await launch();
const { page, name, errors } = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
const { admin } = await adminSession(browser);
await admin('set_level', name, { level: 50 });
await admin('add_gold', name, { amount: 3000000 });
await admin('give_item', name, { id: 'jewel_bless', count: 2 });
await admin('give_gear', name, { base: 'wing_dk_1', up: 9 });
await page.waitForFunction(() => (window.__hl.player().inv.jewel_bless || 0) >= 2);
await travel(page, 'village');
const tabs = () => page.$$eval('.npc-tabs [data-act="npc-tab"]', (b) => b.map((x) => [x.dataset.t, x.classList.contains('primary'), (x.querySelector('.points-dot') || {}).textContent || '']));

R.check('gặp Thợ Rèn', await meetNpc(page, 'blacksmith'));
let t = await tabs();
R.check('Thợ Rèn có 5 tab, mặc định Mua', t.map((x) => x[0]).join() === 'buy,sell,forge,smith,chest' && t[0][1], JSON.stringify(t));
R.check('tab Mua: có hàng bán, không có phần ép đồ', (await page.$$('[data-act="buy"]')).length >= 5 && !(await page.$('[data-act="upgrade"]')));
R.check('tab Ép đồ có chấm báo số món ép được', +t.find((x) => x[0] === 'forge')[2] >= 1, JSON.stringify(t));

await act(page, '[data-act="npc-tab"][data-t="forge"]');
const rows = await page.$$eval('.item.fz', (els) => els.map((e) => !!e.querySelector('[data-act="upgrade"]:not([disabled])')));
const firstLack = rows.indexOf(false);
R.check('món ép được đứng trước món thiếu nguyên liệu', rows[0] === true && (firstLack < 0 || !rows.slice(firstLack).includes(true)), JSON.stringify(rows));
R.check('hàng gọn: chưa mở chi tiết', !(await page.$('.fz-detail')));
await act(page, '.item.fz .grow[data-act="forge-more"]');
R.check('chạm vào món: mở chi tiết (tỉ lệ, nguyên liệu)', /Tỉ lệ/.test((await page.textContent('.fz-detail').catch(() => '')) || ''));
await shot(page, 'npctabs-forge.png');
R.check('Thợ Rèn: không tràn ngang', !(await overflowX(page)));

// thanh tab dính trên đầu khi cuộn xuống
await page.evaluate(() => { const v = document.querySelector('#view'); v.scrollTop = v.scrollHeight; });
await page.waitForTimeout(150);
const stuck = await page.evaluate(() => { const v = document.querySelector('#view').getBoundingClientRect(), b = document.querySelector('.npc-tabs').getBoundingClientRect(); return b.top >= v.top - 1 && b.bottom <= v.bottom; });
R.check('cuộn xuống: thanh tab vẫn thấy', stuck);

// nhớ tab: rời đi rồi gặp lại vẫn ở Ép đồ
await leaveNpc(page);
await meetNpc(page, 'blacksmith');
t = await tabs();
R.check('gặp lại: nhớ tab Ép đồ', t.find((x) => x[0] === 'forge')[1], JSON.stringify(t));
await leaveNpc(page);

R.check('gặp Lão Hỗn Nguyên', await meetNpc(page, 'chaos'));
t = await tabs();
R.check('Lão Hỗn Nguyên có 4 tab, mặc định Ép +10/+11', t.map((x) => x[0]).join() === 'up,wing,lines,misc' && t[0][1], JSON.stringify(t));
await act(page, '[data-act="npc-tab"][data-t="wing"]');
R.check('tab Cánh: chỉ công thức cánh', (await page.$$eval('[data-act="chaos"]', (b) => b.map((x) => x.dataset.id))).every((id) => /^wing/.test(id)));
const fold = await page.$('[data-fold="chaos-wing-lack"]');
R.check('công thức chưa đủ nguyên liệu gập lại', fold && !(await fold.evaluate((d) => d.open)));
await page.click('[data-fold="chaos-wing-lack"] > summary');
// mở phần gập rồi vẽ lại (server đẩy trạng thái): vẫn mở
await page.evaluate(() => window.__hl.send({ act: 'noop' }).catch(() => null));
await page.waitForTimeout(400);
R.check('phần gập giữ trạng thái mở qua lần vẽ lại', await page.$eval('[data-fold="chaos-wing-lack"]', (d) => d.open).catch(() => false));
await shot(page, 'npctabs-chaos.png');
R.check('Lão Hỗn Nguyên: không tràn ngang', !(await overflowX(page)));
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
