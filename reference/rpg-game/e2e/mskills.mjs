// Quái dùng kỹ năng theo hệ + kháng hệ nhẫn / dây chuyền (DECISIONS "Quái dùng kỹ năng theo hệ"): nhân vật cấp 40 đeo
// Nhẫn Lửa +11 (ô thông tin ghi "Kháng 🔥 Lửa 21%"), đánh quái cấp 30+ tới khi quái dùng kỹ năng → dòng nhật ký
// "<quái> dùng <hệ> <kỹ năng>"; Thư viện ghi kỹ năng quái; không lỗi JS.
// Chạy: node e2e/mskills.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, send, engage, fight, act, shot } from './lib.mjs';

const R = reporter('mskills');
const browser = await launch();
const X = await newPlayer(browser, { cls: 'dk' });
const { admin } = await adminSession(browser);
const p = X.page;
await admin('set_level', X.name, { level: 40 });
await admin('add_stats', X.name, { str: 150, vit: 120, agi: 40 });
await admin('add_gold', X.name, { amount: 200000 });
await admin('give_item', X.name, { id: 'potion_l', count: 50 });
await admin('give_gear', X.name, { base: 'item_13_21', up: 11, equip: true });
await p.waitForFunction(() => window.__hl.player().level === 40 && window.__hl.player().equip.ring1, null, { timeout: 10000 });

R.check('kháng Lửa từ Nhẫn Lửa +11 (server)', await p.evaluate(() => Math.abs((window.__hl.player().view.derived.resist || {}).fire - 0.21) < 0.001));
await p.click('#tabs [data-tab="bag"]');
await p.click('[data-act="slot-tip"][data-slot="ring1"]');
await p.waitForSelector('#itemtip');
R.check('ô thông tin nhẫn ghi Kháng 🔥 Lửa 21%', /Kháng 🔥 Lửa 21%/.test(await p.textContent('#itemtip')), (await p.textContent('#itemtip')).slice(0, 120));
await p.mouse.click(5, 300);

const tr = await send(p, { act: 'travel', to: 'vn_den_co' }).catch((e) => ({ msg: e.msg }));
R.check('tới Đền Cổ (quái cấp 34–38)', (await p.evaluate(() => window.__hl.player().pos.map)) === 'vn_den_co', tr.msg || '');
let line = null;
for (let i = 0; i < 12 && !line; i++) {
  if (!(await engage(p))) break;
  await fight(p, 60);
  line = await p.evaluate(() => (window.__hl.player().battle.log || []).find((l) => l.who === 'foe' && l.act && /[🔥❄️⚡🪨🌪✨🌑]/u.test(l.act)));
  if (line) await shot(p, 'mskills-battle.png');
  const b = (await p.evaluate(() => window.__hl.player())).battle;
  if (b) await act(p, 'leave').catch(() => null);
  if ((await p.evaluate(() => window.__hl.player().hp)) <= 0) await send(p, { act: 'rest' }).catch(() => null);
}
R.check('quái dùng kỹ năng theo hệ trong trận', !!line, line ? `${line.name}: ${line.act}` : 'không thấy');

// Thư viện ghi kỹ năng quái
const lib = await p.evaluate(() => (window.GAME_DATA.LIBRARY.monsters || []).filter((m) => (m.skills || []).length).length);
R.check('Thư viện: quái có danh sách kỹ năng', lib > 50, `${lib} quái`);
R.check('không lỗi JS', X.errors.length === 0, X.errors.join(' | '));
await R.done(browser);
