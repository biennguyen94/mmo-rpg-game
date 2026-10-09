// Smoke: đăng ký → tạo nhân vật (cả 4 lớp) → ra Làng → Rừng Mê đánh quái → về Thợ Rèn mua / bán →
// nghỉ trọ → cộng điểm. Chạy: node e2e/smoke.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, player, ui, send, act, travel, meetNpc, leaveNpc, engage, fight, shot } from './lib.mjs';

const R = reporter('smoke');
const browser = await launch();

// tạo đủ 4 lớp: chỉ số gốc + MP đúng dữ liệu lớp
for (const cls of ['dw', 'elf', 'mg']) {
  const { page, ctx, errors } = await newPlayer(browser, { cls });
  const p = await player(page);
  const c = await page.evaluate((cls) => window.GAME_DATA.CLASSES[cls], cls);
  R.check(`tạo nhân vật lớp ${cls}: chỉ số gốc, máu / MP đầy`, p.cls === cls && JSON.stringify(p.stats) === JSON.stringify(c.base) && p.hp === p.view.derived.maxHp && p.mp === p.view.derived.maxMp);
  R.check(`lớp ${cls}: không lỗi JS`, errors.length === 0, errors.join(' | '));
  await ctx.close();
}

const { page, errors, name } = await newPlayer(browser, { cls: 'dk' });
let p = await player(page);
R.check('nhân vật mới ở Nhà, cấp 1, có bình máu', p.pos.map === 'home' && p.level === 1 && (p.inv.potion_s || 0) > 0);
await shot(page, 'smoke-home.png');

R.check('ra Làng qua cửa Nhà', await travel(page, 'village'));
R.check('sang Rừng Mê', await travel(page, 'forest_1'));
await shot(page, 'smoke-forest.png');

// đánh tới khi thắng 2 trận (thua thì về Nhà, hồi máu, đi lại)
let wins = 0;
for (let i = 0; i < 6 && wins < 2; i++) {
  p = await player(page);
  if (p.pos.map !== 'forest_1') { await travel(page, 'village'); await travel(page, 'forest_1'); }
  if (!(await engage(page))) continue;
  if (i === 0) await shot(page, 'smoke-battle.png');
  const r = await fight(page);
  if (r === 'win') wins++;
  await act(page, 'leave');
}
p = await player(page);
R.check('thắng quái trong Rừng Mê, nhận kinh nghiệm + vàng', wins >= 1 && p.kills >= 1 && (p.xp > 0 || p.level > 1) && p.gold > 30, `wins=${wins} kills=${p.kills}`);

// về Làng: Thợ Rèn (xem hàng), Bà Lang: mua một bình, bán lại
if (p.pos.map !== 'village') await travel(page, 'village');
R.check('gặp Thợ Rèn, có hàng bán', (await meetNpc(page, 'blacksmith')) && (await page.$$('[data-act="buy"]')).length >= 5);
await shot(page, 'smoke-shop.png');
await leaveNpc(page);
R.check('gặp Bà Lang', await meetNpc(page, 'herbalist'));
const before = await player(page);
await act(page, '[data-act="buy"][data-id="potion_s"]');
let after = await player(page);
// Phase 12: giá bình tăng theo cấp (RULES.potionPricePerLevel)
const price = await page.evaluate((lv) => window.HLLogic.shopPrice(window.GAME_DATA.ITEMS.potion_s, lv, window.GAME_DATA.RULES.potionPricePerLevel), before.level);
R.check('mua Bình Máu Nhỏ: trừ đúng giá theo cấp, thêm 1 bình', after.gold === before.gold - price && after.inv.potion_s === (before.inv.potion_s || 0) + 1, `${before.gold}→${after.gold}`);
const sell = await page.evaluate(() => window.GAME_DATA.ITEMS.potion_s.sell);
const r = await send(page, { act: 'sell', id: 'potion_s' });
R.check('bán lại Bình Máu Nhỏ: cộng đúng giá bán', r.gold === after.gold + sell && r.inv.potion_s === after.inv.potion_s - 1);
await leaveNpc(page);

// nghỉ trọ
after = await player(page);
if (after.hp >= after.view.derived.maxHp) {
  // máu đầy thì bị thương một chút cho có việc để nghỉ: đánh thêm một trận
  await travel(page, 'forest_1');
  if (await engage(page)) { await fight(page); await act(page, 'leave'); }
  await travel(page, 'village');
}
R.check('gặp Chủ Quán Trọ', await meetNpc(page, 'innkeeper'));
const tired = await player(page);
if (tired.hp < tired.view.derived.maxHp || tired.mp < tired.view.derived.maxMp) await act(page, 'rest');
after = await player(page);
R.check('nghỉ trọ: hồi đầy máu và MP, trừ đúng giá', after.hp === after.view.derived.maxHp && after.mp === after.view.derived.maxMp && after.gold === tired.gold - (tired.hp < tired.view.derived.maxHp || tired.mp < tired.view.derived.maxMp ? tired.view.restCost : 0));
await leaveNpc(page);

// cộng điểm (nếu đã lên cấp) qua tab Nhân vật: bấm + hai lần → gom thành một lệnh
p = await player(page);
if (p.points >= 2) {
  await page.keyboard.press('c');
  await page.click('[data-act="alloc-add"][data-stat="str"]');
  await page.click('[data-act="alloc-add"][data-stat="str"]');
  await page.waitForTimeout(600);
  const q = await player(page);
  R.check('cộng 2 điểm Sức mạnh (gom lệnh)', q.stats.str === p.stats.str + 2 && q.points === p.points - 2);
  await page.keyboard.press('m');
}

R.check(`tab chính mở được (${name})`, await (async () => {
  for (const t of ['hero', 'bag', 'menu', 'map']) { await page.click(`#tabs [data-tab="${t}"]`); if ((await ui(page)).tab !== t) return false; }
  return true;
})());
R.check('không lỗi JS', errors.length === 0, errors.join(' | '));
await R.done(browser);
