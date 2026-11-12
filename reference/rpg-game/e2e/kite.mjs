// Đồi Sáo Diều, Chim Lạc, Hắc Long (DECISIONS cùng tên): tới đồi qua cổng Hồ Long Vương, đứng mép đồi thả diều (chạm trời),
// gió giật thì giữ dây → quà gió + Phong Khí; Chim Lạc / Đàn Hạc / sao băng hiện trên đồi (thanh sự kiện, bản đồ nhỏ),
// nhặt Mảnh Sao; Ông Lão Làm Diều (việc, ghép Sáo Đồng, Bia Chim Lạc, Hắc Long).
// Chạy: node e2e/kite.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, send, shot, meetNpc, overflowX } from './lib.mjs';

const R = reporter('kite');
const browser = await launch();
const A = await newPlayer(browser, { cls: 'elf', viewport: { width: 390, height: 844 } });
const { admin } = await adminSession(browser);
await admin('set_level', A.name, { level: 35 });
await admin('add_gold', A.name, { amount: 50000 });
const p = A.page;
await p.waitForFunction(() => window.__hl.player().level === 35, null, { timeout: 8000 }).catch(() => null);
await send(p, { act: 'travel', to: 'long_vuong_lake' }).catch((e) => console.log('travel lake', e.msg));
await p.waitForFunction(() => window.__hl.player().pos.map === 'long_vuong_lake', null, { timeout: 8000 }).catch(() => null);
// cổng mép phải hồ → đồi
const portal = await p.evaluate(() => window.GAME_DATA.WORLD.maps.long_vuong_lake.portals.find((q) => q.to === 'doi_sao_dieu'));
R.check('Hồ Long Vương có cổng sang Đồi Sáo Diều', !!portal);
await p.click('#tabs [data-tab="map"]').catch(() => null);
await p.evaluate(([x, y]) => window.__hl.walkTo(x, y), portal.at);
await p.waitForFunction(() => window.__hl.player().pos.map === 'doi_sao_dieu', null, { timeout: 30000 }).catch(() => null);
R.check('qua cổng tới Đồi Sáo Diều', (await p.evaluate(() => window.__hl.player().pos.map)) === 'doi_sao_dieu');

// đứng mép đồi (cạnh ô trời, không sát cây)
const stand = await p.evaluate(() => {
  const m = window.GAME_DATA.WORLD.maps.doi_sao_dieu, me = window.__hl.player().pos;
  let best = null;
  for (let y = 0; y < m.tiles.length; y++) for (let x = 0; x < m.tiles[0].length; x++) {
    const c = m.tiles[y][x];
    if (!',:*'.includes(c)) continue;
    if (![[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => (m.tiles[y + dy] || '')[x + dx] === '^')) continue;
    let tree = false; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if ('TYK'.includes((m.tiles[y + dy] || '')[x + dx] || '_')) tree = true;
    if (tree) continue;
    const d = Math.abs(x - me.x) + Math.abs(y - me.y);
    if (!best || d < best.d) best = { x, y, d };
  }
  return best;
});
await p.evaluate(([x, y]) => window.__hl.walkTo(x, y), [stand.x, stand.y]);
await p.waitForFunction(([x, y]) => { const q = window.__hl.player().pos; return q.x === x && q.y === y; }, [stand.x, stand.y], { timeout: 30000 }).catch(() => null);
await p.waitForSelector('#kite-ui:not([hidden]) [data-act="kite-fly"]', { timeout: 5000 }).catch(() => null);
R.check('đứng mép đồi: hiện nút 🪁 Thả diều + Phong Khí', /Thả diều/.test(await p.textContent('#kite-ui').catch(() => '')) && /Phong Khí/.test(await p.textContent('#kite-ui').catch(() => '')));
await shot(p, 'kite-hill.png');

// chạm vào trời: thả diều, chờ gió giật rồi giữ dây
const skyTile = await p.evaluate(([x, y]) => { const m = window.GAME_DATA.WORLD.maps.doi_sao_dieu; for (let dy = -1; dy >= -3; dy--) for (let dx = -1; dx <= 1; dx++) if ((m.tiles[y + dy] || '')[x + dx] === '^') return [x + dx, y + dy]; return null; }, [stand.x, stand.y]);
const sc = await p.evaluate(([x, y]) => window.MapView.screenOf(x, y), skyTile);
await p.mouse.click(sc.x, sc.y);
await p.waitForSelector('#kite-ui [data-act="kite-hold"]', { timeout: 5000 }).catch(() => null);
R.check('chạm trời: diều bay, nút 🪁 Giữ dây', !!(await p.$('#kite-ui [data-act="kite-hold"]')));
await p.waitForTimeout(900);
await shot(p, 'kite-flying.png');
await p.waitForSelector('#kite-ui.bite', { timeout: 10000 }).catch(() => null);
await shot(p, 'kite-gust.png');
const pk0 = await p.evaluate(() => (window.__hl.player().view.kite || {}).phong_khi || 0);
await p.click('#kite-ui [data-act="kite-hold"]');
await p.waitForFunction((k) => ((window.__hl.player().view.kite || {}).phong_khi || 0) > k || (window.__hl.player().inv.day_dieu_dut || 0) > 0, pk0, { timeout: 5000 }).catch(() => null);
// Dây Diều Đứt (quà rác) thì không cộng Phong Khí (đúng luật)
const got = await p.evaluate(() => ({ pk: window.__hl.player().view.kite.phong_khi, junk: window.__hl.player().inv.day_dieu_dut || 0 }));
R.check('giữ dây đúng lúc: +1 Phong Khí (hoặc Dây Diều Đứt)', got.pk === pk0 + 1 || got.junk > 0, JSON.stringify(got));

// chỗ thoáng giữa đồi (không sát trời): vẫn thả được bằng nút, diều bay thẳng lên; sát cây thì báo vướng cây
await p.waitForTimeout(1200);
const mid = await p.evaluate(() => {
  const m = window.GAME_DATA.WORLD.maps.doi_sao_dieu, me = window.__hl.player().pos, T = (x, y) => (m.tiles[y] || '')[x];
  let best = null;
  for (let y = 8; y < m.tiles.length; y++) for (let x = 0; x < m.tiles[0].length; x++) {
    if (!',:'.includes(T(x, y)) || T(x, y - 1) === '^') continue;
    let tree = false; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if ('TYK'.includes(T(x + dx, y + dy) || '_')) tree = true;
    if (tree) continue;
    if (y < 12) continue; // giữa / cuối đồi, xa mép trời (dây diều không giới hạn)
    const d = Math.abs(x - me.x) + Math.abs(y - me.y);
    if (!best || d < best.d) best = { x, y, d };
  }
  return best;
});
await p.evaluate(([x, y]) => window.__hl.walkTo(x, y), [mid.x, mid.y]);
await p.waitForFunction(([x, y]) => { const q = window.__hl.player().pos; return q.x === x && q.y === y; }, [mid.x, mid.y], { timeout: 30000 }).catch(() => null);
await p.waitForSelector('#kite-ui [data-act="kite-fly"]', { timeout: 5000 }).catch(() => null);
await p.click('#kite-ui [data-act="kite-fly"]').catch(() => null);
await p.waitForSelector('#kite-ui [data-act="kite-hold"]', { timeout: 5000 }).catch(() => null);
R.check('cuối đồi (xa trời): bấm 🪁 Thả diều vẫn bay', !!(await p.$('#kite-ui [data-act="kite-hold"]')), JSON.stringify(mid));
await p.waitForTimeout(1500); // camera nâng lên theo diều
const kv = await p.evaluate(() => {
  const at = window.MapView.kiteAt(), me = window.__hl.player().pos, c = document.getElementById('map-canvas').getBoundingClientRect();
  const k = at && window.MapView.screenOf(at[0], at[1]), q = window.MapView.screenOf(me.x, me.y);
  return { at, me: [me.x, me.y], kin: !!k && k.y > c.top && k.y < c.bottom, pin: !!q && q.y > c.top && q.y < c.bottom };
});
R.check('bấm nút: diều lên giữa trời (cách người ≥ 3 hàng), khung nâng lên thấy cả diều lẫn người', kv.at && kv.me[1] - kv.at[1] >= 3 && kv.kin && kv.pin, JSON.stringify(kv));
await shot(p, 'kite-mid.png');
await p.waitForSelector('#kite-ui [data-act="kite-fly"]', { timeout: 12000 }).catch(() => null); // để lượt này hết (chậm tay)
const treeSpot = await p.evaluate(() => {
  const m = window.GAME_DATA.WORLD.maps.doi_sao_dieu, me = window.__hl.player().pos, T = (x, y) => (m.tiles[y] || '')[x];
  let best = null;
  for (let y = 8; y < m.tiles.length; y++) for (let x = 0; x < m.tiles[0].length; x++) {
    if (!',:'.includes(T(x, y))) continue;
    if (![[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]].some(([dx, dy]) => 'Y'.includes(T(x + dx, y + dy) || '_'))) continue;
    const d = Math.abs(x - me.x) + Math.abs(y - me.y);
    if (!best || d < best.d) best = { x, y, d };
  }
  return best;
});
await p.evaluate(([x, y]) => window.__hl.walkTo(x, y), [treeSpot.x, treeSpot.y]);
await p.waitForFunction(([x, y]) => { const q = window.__hl.player().pos; return q.x === x && q.y === y; }, [treeSpot.x, treeSpot.y], { timeout: 30000 }).catch(() => null);
await p.waitForTimeout(400);
R.check('đứng sát cây: báo "Vướng cây", không có nút thả', /Vướng cây/.test(await p.textContent('#kite-ui').catch(() => '')) && !(await p.$('#kite-ui [data-act="kite-fly"]')));

// Chim Lạc, Đàn Hạc, sao băng (quản trị gọi)
await admin('sky_bird', A.name);
await admin('sky_flock', A.name);
await admin('sky_meteor', A.name);
await p.waitForTimeout(800);
const hud = await p.evaluate(() => window.MapView.hudLines());
R.check('thanh sự kiện: Chim Lạc, Đàn Hạc, Mảnh Sao', hud.some((l) => /Chim Lạc/.test(l) && /Đàn Hạc/.test(l) && /Mảnh Sao/.test(l)), JSON.stringify(hud));
await shot(p, 'kite-events.png');
// nhặt Mảnh Sao gần nhất
// Mảnh Sao gần nhất đang lộ trên bản đồ (không bị khung nút / thanh che)
const star = await p.evaluate(() => {
  const me = window.__hl.player().pos;
  const seen = window.MapView.sky().stars.filter(([x, y]) => { const q = window.MapView.screenOf(x, y); const el = q && document.elementFromPoint(q.x, q.y); return el && el.id === 'map-canvas'; });
  return seen.sort((a, b) => Math.abs(a[0] - me.x) + Math.abs(a[1] - me.y) - Math.abs(b[0] - me.x) - Math.abs(b[1] - me.y))[0];
});
if (star) {
  const ss = await p.evaluate(([x, y]) => window.MapView.screenOf(x, y), star);
  await p.mouse.click(ss.x, ss.y);
} else {
  // mọi Mảnh Sao đều bị khung che: đi tới viên đầu rồi nhặt
  const s0 = await p.evaluate(() => window.MapView.sky().stars[0]);
  await p.evaluate(([x, y]) => window.__hl.walkTo(x, y), s0);
  await p.waitForFunction(([x, y]) => { const q = window.__hl.player().pos; return Math.max(Math.abs(q.x - x), Math.abs(q.y - y)) <= 1; }, s0, { timeout: 30000 }).catch(() => null);
  await send(p, { act: 'star_pick', x: s0[0], y: s0[1] }).catch(() => null);
}
await p.waitForFunction(() => (window.__hl.player().inv.manh_sao || 0) > 0, null, { timeout: 30000 }).catch(() => null);
R.check('chạm Mảnh Sao: đi tới nhặt', (await p.evaluate(() => window.__hl.player().inv.manh_sao || 0)) > 0, JSON.stringify({ star, pos: await p.evaluate(() => window.__hl.player().pos), stars: await p.evaluate(() => window.MapView.sky().stars) }));

// Ông Lão Làm Diều
R.check('gặp Ông Lão Làm Diều', await meetNpc(p, 'kite_maker'));
await p.waitForTimeout(600);
const npcText = await p.textContent('#view');
R.check('Ông Lão: việc hôm nay, ghép Sáo Đồng, Chim Lạc, Bia, Hắc Long', /Việc hôm nay/.test(npcText) && /Ghép Sáo Đồng/.test(npcText) && /Bia Chim Lạc/.test(npcText) && /Con Rồng Cháu Tiên/.test(npcText));
R.check('Ông Lão: không tràn ngang (điện thoại)', !(await overflowX(p)));
await shot(p, 'kite-npc.png');
await p.click('[data-act="npc-close"]').catch(() => null);

R.check('không lỗi JS', A.errors.length === 0, A.errors.join(' | '));
await R.done(browser);
