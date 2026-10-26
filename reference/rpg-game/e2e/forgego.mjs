// Ép từ khung đồ (DECISIONS "Ép từ khung đồ"): bấm vào đồ thấy trước bước ép kế tiếp (ở đâu, ngọc đủ / thiếu, tỉ lệ);
// nút "Ép ở Thợ Rèn" / "Ép ở Lão Hỗn Nguyên" tự về Làng, đi tới đúng NPC, mở bảng ép đã chọn sẵn món đó.
// Chạy: node e2e/forgego.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, act, travel, shot } from './lib.mjs';

const R = reporter('forgego');
const browser = await launch();
const { page, name, errors } = await newPlayer(browser, { cls: 'dk', viewport: { width: 400, height: 860 } });
const { admin } = await adminSession(browser);
await admin('add_gold', name, { amount: 200000 });
await admin('give_item', name, { id: 'jewel_bless', count: 3 });
await page.waitForFunction(() => (window.__hl.player().inv.jewel_bless || 0) >= 3, null, { timeout: 8000 }).catch(() => null);

// ra Rừng Mê rồi mở vũ khí đang mặc
if ((await player(page)).pos.map !== 'village') await travel(page, 'village');
await travel(page, 'forest_1');
await page.click('#tabs [data-tab="hero"]').catch(() => null);
await page.click('#tabs [data-tab="bag"]');
await act(page, '[data-act="slot-tip"][data-slot="weapon"]');
const tip = (await page.textContent('#itemtip').catch(() => '')) || '';
R.check('khung đồ đang mặc: xem trước "Ép +0 → +1 ở Thợ Rèn", ngọc, vàng', tip.includes('Ép +0 → +1 ở Thợ Rèn') && tip.includes('Ngọc Ước Nguyện') && tip.includes('vàng'), tip.slice(0, 200));
R.check('nút "Ép ở Thợ Rèn" có ở đồ đang mặc', !!(await page.$('#itemtip [data-act="forge-go"][data-slot="weapon"]')));
await shot(page, 'forgego-tip.png');

await page.click('#itemtip [data-act="forge-go"]');
await page.waitForSelector('[data-act="upgrade"][data-slot="weapon"]', { timeout: 20000 }).catch(() => null);
const p = await player(page);
R.check('tự về Làng, tới Thợ Rèn, bảng ép mở với vũ khí đứng đầu (đã chọn)', p.pos.map === 'village' && !!(await page.$('[data-act="upgrade"][data-slot="weapon"]')) && (((await page.textContent('.list .item .small.muted').catch(() => '')) || '').includes('đã chọn')), JSON.stringify(p.pos));
await shot(page, 'forgego-smith.png');

await act(page, '[data-act="upgrade"][data-slot="weapon"]');
const q = await player(page);
R.check('bấm ép: vũ khí lên +1', (q.upgrades[q.equip.weapon] || 0) === 1);

// món +9 trong túi: bước kế tiếp ở Lão Hỗn Nguyên (Máy Hỗn Nguyên), ngọc thiếu hiện đỏ; nút tự đi tới đó
const base = await page.evaluate(() => { const P = window.__hl.player(); return P.view.gear[P.equip.weapon].base; });
await admin('give_gear', name, { base, up: 9 });
await page.waitForFunction(() => Object.keys(window.__hl.player().view.forgeBag).some((id) => (window.__hl.player().view.forgeBag[id].cost || {}).at === 'chaos'), null, { timeout: 8000 }).catch(() => null);
const nine = await page.evaluate(() => { const fb = window.__hl.player().view.forgeBag; return Object.keys(fb).find((id) => (fb[id].cost || {}).at === 'chaos'); });
await page.click('#tabs [data-tab="bag"]');
await act(page, `[data-act="bag-tip"][data-id="${nine}"]`);
const tip9 = (await page.textContent('#itemtip').catch(() => '')) || '';
R.check('khung đồ +9: "Ép +9 → +10 ở Lão Hỗn Nguyên", tỉ lệ, ngọc thiếu', tip9.includes('Ép +9 → +10 ở Lão Hỗn Nguyên') && tip9.includes('tỉ lệ') && !!(await page.$('#itemtip .needs .lack')), tip9.slice(0, 240));
await shot(page, 'forgego-tip9.png');
await page.click('#itemtip [data-act="forge-go"][data-at="chaos"]');
await page.waitForSelector('[data-panel="chaos-upgrade"]', { timeout: 20000 }).catch(() => null);
R.check('tự đi tới Lão Hỗn Nguyên, thẻ ép +10/+11 mở ở Trong túi', !!(await page.$('[data-panel="chaos-upgrade"]')) && !!(await page.$(`[data-act="chaos_upgrade"][data-id="${nine}"]`)));

R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
