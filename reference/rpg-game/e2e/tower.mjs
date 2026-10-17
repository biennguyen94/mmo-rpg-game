// Tháp Vô Tận: quái trên tầng đi lang thang (server đẩy vị trí mới), bản đồ có hiệu ứng theo nền tầng, không lỗi JS.
import { launch, reporter, newPlayer, player, send, travel, meetNpc, shot } from './lib.mjs';

const R = reporter('tower');
const browser = await launch();
const P = await newPlayer(browser, { viewport: { width: 420, height: 900 } });
const page = P.page;
await page.evaluate(() => localStorage.setItem('hl-fx', '1'));

await travel(page, 'village');
R.check('gặp Người Gác Tháp', await meetNpc(page, 'tower_guard'));
let p = await send(page, { act: 'tower_enter', floor: 1 });
R.check('vào tầng 1', p.pos.map === 'tower' && p.tower && p.tower.monsters.length > 0, p.pos.map);
await page.evaluate(() => window.__hl.closeNpc());

const pos = (q) => JSON.stringify(q.tower.monsters.map((m) => [m.id, m.x, m.y]));
const before = pos(p);
await page.waitForFunction((b) => {
  const q = window.__hl.player();
  return q.tower && JSON.stringify(q.tower.monsters.map((m) => [m.id, m.x, m.y])) !== b;
}, before, { timeout: 15000 }).catch(() => null);
p = await player(page);
R.check('quái tầng tự đi lang thang', p.tower && pos(p) !== before);
await page.waitForTimeout(1500);
await shot(page, 'tower-fx.png');

R.check('không lỗi JS', P.errors.length === 0, P.errors.join(' | '));
await R.done(browser);
