// Thú cưng (DECISIONS "Thú cưng 3 nhóm, chỉ cộng chỉ số"): mua ở Người Nuôi Thú, bảng hiện nhóm + chỉ số cộng (không còn
// cắn / kỹ năng), cho ăn lên cấp, thuần phục quái bản đồ phụ.
import { launch, reporter, newPlayer, adminSession, player, act, send, travel, meetNpc, shot } from './lib.mjs';

const R = reporter('pets');
const browser = await launch();
const P = await newPlayer(browser, { viewport: { width: 420, height: 900 } });
const page = P.page;
const { admin } = await adminSession(browser);
await admin('add_gold', P.name, { amount: 2000000 });
await page.waitForFunction(() => window.__hl.player().gold >= 2000000, null, { timeout: 8000 }).catch(() => null);

await travel(page, 'village');
R.check('gặp Người Nuôi Thú', await meetNpc(page, 'pet_keeper'));
const shop = (await page.textContent('#npc, .npc, body')) || '';
R.check('cửa hàng thú hiện nhóm Chiến / Hộ vệ / Tài lộc, không còn cắn / kỹ năng', ['Chiến', 'Hộ vệ', 'Tài lộc'].every((g) => shop.includes(g)) && !shop.includes('đòn thường') && !shop.includes('Kỹ năng:'));
await act(page, '[data-act="pet_buy"][data-id="hound"]');
await page.waitForFunction(() => window.__hl.player().pet === 'hound', null, { timeout: 5000 }).catch(() => null);
let p = await player(page);
R.check('mua Chó Săn, dắt theo luôn', p.pet === 'hound', p.pet);

const feedBtn = await page.waitForSelector('[data-act="pet_feed"]', { timeout: 5000 }).catch(() => null);
R.check('có nút cho thú ăn', !!feedBtn);
const gold0 = p.gold;
await act(page, '[data-act="pet_feed"]');
await page.waitForFunction(() => (window.__hl.player().pet_xp || {}).hound >= 20, null, { timeout: 5000 }).catch(() => null);
p = await player(page);
const v = (p.view.pets || []).find((x) => x.id === 'hound');
R.check('cho ăn: +20 trận, lên cấp 2, trừ vàng', (p.pet_xp || {}).hound === 20 && v && v.level === 2 && p.gold < gold0, JSON.stringify({ xp: p.pet_xp, lv: v && v.level, gold: p.gold }));
R.check('giá lần sau theo cấp²', v && v.feed === 4 * 500, v && v.feed);
await shot(page, 'pets-npc.png');

// Menu → Thú cưng: nhóm + chỉ số cộng theo cấp
await act(page, 'npc-close').catch(() => null);
await page.evaluate(() => window.__hl.menu('pets'));
const menu = (await page.textContent('body')) || '';
R.check('Menu Thú cưng hiện nhóm và chỉ số cộng theo cấp', menu.includes('Chiến') && menu.includes('Tấn công +') && menu.includes('Chí mạng +') && menu.includes('cấp 2') && !menu.includes('🦷'));
await shot(page, 'pets-menu.png');

// thuần phục quái bản đồ phụ (đặt sổ quái bằng lệnh quản trị không có: kiểm qua view.taming / tameable rỗng mà không lỗi)
p = await send(page, { act: 'pet_tame', id: 'adder' });
R.check('chưa hạ đủ thì không thuần được quái bản đồ phụ', !(p.pets || []).includes('tame:adder'));

R.check('không lỗi JS', P.errors.length === 0, P.errors.join(' | '));
await R.done(browser);
