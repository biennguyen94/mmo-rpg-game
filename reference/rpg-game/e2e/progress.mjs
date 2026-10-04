// Tiến trình: nhiệm vụ Trưởng Làng (nhận → hạ 5 Dơi Hang → trả), việc hằng ngày ở Bảng Tin, ép đồ ở Thợ
// Rèn, mua rương, Máy Hỗn Nguyên. Chạy: node e2e/progress.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, act, travel, meetNpc, leaveNpc, engage, fight, shot } from './lib.mjs';

const R = reporter('progress');
const browser = await launch();
const { page, name, errors } = await newPlayer(browser, { cls: 'dk' });
const adm = await adminSession(browser);
// cấp 8 + bình máu để hạ 5 con dơi nhanh; vàng, nguyên liệu cho ép / rương / máy ghép
await adm.admin('set_level', name, { level: 8 });
await adm.admin('heal', name);
await adm.admin('add_gold', name, { amount: 20000 });
for (const [id, count] of [['potion_m', 10], ['ore', 10], ['ore_rare', 10], ['dragon_scale', 1]]) await adm.admin('give_item', name, { id, count });
await page.waitForFunction(() => window.__hl.player().level === 8 && (window.__hl.player().inv.dragon_scale || 0) === 1);

await travel(page, 'village');

// ---------- Nhiệm vụ ----------
R.check('gặp Trưởng Làng', await meetNpc(page, 'elder'));
await act(page, '[data-act="quest_accept"][data-id="forest_kill"]');
let p = await player(page);
R.check('nhận nhiệm vụ "Lũ dơi hang"', 'forest_kill' in p.quests.active);
await leaveNpc(page);
await travel(page, 'forest_1');
for (let i = 0; i < 25 && (await player(page)).quests.active.forest_kill < 5; i++) {
  if (!(await engage(page, 'bat'))) continue;
  await fight(page);
  await act(page, 'leave');
}
p = await player(page);
R.check('hạ đủ 5 Dơi Hang', p.quests.active.forest_kill >= 5, JSON.stringify(p.quests.active));
await page.click('#tabs [data-tab="quests"]');
await shot(page, 'progress-quests.png');
await page.click('#tabs [data-tab="map"]');
await travel(page, 'village');
await meetNpc(page, 'elder');
const g0 = (await player(page)).gold;
await act(page, '[data-act="quest_turnin"][data-id="forest_kill"]');
p = await player(page);
const reward = await page.evaluate(() => window.GAME_DATA.QUESTS.find((q) => q.id === 'forest_kill').reward);
R.check('trả nhiệm vụ: nhận vàng thưởng (cộng quà hướng dẫn tân thủ), vào danh sách đã xong', p.quests.done.includes('forest_kill') && p.gold >= g0 + reward.gold && !('forest_kill' in p.quests.active), `done=${p.quests.done} gold ${g0}→${p.gold} thưởng ${reward.gold}`);
await leaveNpc(page);

// ---------- Việc hằng ngày ----------
R.check('gặp Bảng Tin', await meetNpc(page, 'board'));
p = await player(page);
R.check('có việc hằng ngày, hiện trên Bảng Tin', p.daily && p.daily.tasks.length >= 3 && (await page.textContent('#view')).includes(p.daily.tasks[0].name), `${p.daily.tasks.length} việc`);
await leaveNpc(page);

// ---------- Ép đồ (+1 bằng quặng), rương ----------
R.check('gặp Thợ Rèn', await meetNpc(page, 'blacksmith'));
const before = await player(page);
await act(page, '[data-act="upgrade"][data-slot="weapon"]');
p = await player(page);
const lvl = p.upgrades[p.equip.weapon] || 0;
R.check('ép vũ khí lên +1: tốn quặng và vàng', lvl === 1 && p.inv.ore === before.inv.ore - 1 && p.gold < before.gold, `lvl=${lvl}`);
await shot(page, 'progress-forge.png');
const bag0 = Object.keys(p.view.gear).length;
await act(page, '[data-act="chest_buy"][data-tier="wood"]');
p = await player(page);
R.check('mua Rương Gỗ: thêm một món đồ hiếm', Object.keys(p.view.gear).length === bag0 + 1);
await leaveNpc(page);

// ---------- Máy Hỗn Nguyên: ghép Ngọc Hỗn Nguyên (may rủi) ----------
R.check('gặp Lão Hỗn Nguyên', await meetNpc(page, 'chaos'));
const c0 = await player(page);
const rec = await page.evaluate(() => window.GAME_DATA.CHAOS.find((r) => r.id === 'make_chaos'));
await act(page, '[data-act="chaos"][data-id="make_chaos"]');
p = await player(page);
R.check('ghép: tốn đúng nguyên liệu + vàng, thành công thì có Ngọc Hỗn Nguyên', (p.inv.ore_rare || 0) === c0.inv.ore_rare - rec.items.ore_rare && !(p.inv.dragon_scale > 0) && p.gold === c0.gold - rec.gold && (p.inv.jewel_chaos || 0) <= 1, `ore_rare ${c0.inv.ore_rare}→${p.inv.ore_rare} scale ${p.inv.dragon_scale} gold ${c0.gold}→${p.gold} rec ${JSON.stringify(rec)}`);
await shot(page, 'progress-chaos.png');
await leaveNpc(page);

R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
