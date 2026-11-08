// Hắc Long, linh vật Con Rồng Cháu Tiên (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long"): nhân vật đủ điều kiện (Long Vương và
// Chim Lạc cấp tối đa, Long Khí / Phong Khí đầy, đã hạ Hắc Long — đặt bằng HL_PREP: lệnh chuẩn bị chạy rpc vào server) vào vòng
// Long Phượng Hội ở Tế Đàn làm lễ → Bọc Trăm Trứng; đủ quái thì cho nở → thú Hắc Long + màn "Con Rồng Cháu Tiên".
// Chạy: HL_PREP="elixir --sname prep$RANDOM <đường dẫn>/hacprep.exs" node e2e/hac_long.mjs [url] [thư_mục_ảnh]
// (hacprep.exs <tên> ready|kills: xem DECISIONS; không có HL_PREP thì bỏ qua)
import { execSync } from 'node:child_process';
import { launch, reporter, newPlayer, adminSession, send, shot } from './lib.mjs';

const R = reporter('hac_long');
if (!process.env.HL_PREP) { console.log('bỏ qua: cần HL_PREP'); process.exit(0); }
const browser = await launch();
const A = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
const { admin } = await adminSession(browser);
const p = A.page;
const prep = (mode) => execSync(`${process.env.HL_PREP} ${A.name} ${mode}`, { stdio: 'pipe' }).toString();
await admin('set_level', A.name, { level: 50 });
await p.waitForFunction(() => window.__hl.player().level === 50, null, { timeout: 8000 }).catch(() => null);
prep('ready');
await p.waitForFunction(() => (window.__hl.player().pets || []).includes('chim_lac'), null, { timeout: 8000 }).catch(() => null);
R.check('đủ điều kiện làm lễ (không còn thiếu gì)', (await p.evaluate(() => window.__hl.player().view.hacMissing || ['?'])).length === 0, JSON.stringify(await p.evaluate(() => window.__hl.player().view.hacMissing)));

await admin('sky_hoi', A.name);
await send(p, { act: 'travel', to: 'altar' }).catch(() => null);
await p.waitForFunction(() => window.__hl.player().pos.map === 'altar', null, { timeout: 8000 }).catch(() => null);
await p.click('#tabs [data-tab="map"]').catch(() => null);
const at = await p.evaluate(() => window.MapView.sky().hoi.at);
await p.evaluate(([x, y]) => window.__hl.walkTo(x, y), at);
await p.waitForFunction(([x, y]) => { const q = window.__hl.player().pos; return Math.max(Math.abs(q.x - x), Math.abs(q.y - y)) <= 2; }, at, { timeout: 30000 }).catch(() => null);
await p.waitForSelector('#hoi-ui [data-act="le_long_phuong"]:not([disabled])', { timeout: 5000 }).catch(() => null);
R.check('trong vòng sáng: nút 🐉🐦 Làm lễ', /Làm lễ/.test(await p.textContent('#hoi-ui').catch(() => '')));
await shot(p, 'hac-hoi.png');
await p.click('#hoi-ui [data-act="le_long_phuong"]');
await p.waitForFunction(() => (window.__hl.player().inv.boc_tram_trung || 0) > 0, null, { timeout: 5000 }).catch(() => null);
const after = await p.evaluate(() => ({ egg: window.__hl.player().inv.boc_tram_trung || 0, lk: window.__hl.player().long_khi, view: window.__hl.player().view.egg }));
R.check('làm lễ: nhận Bọc Trăm Trứng, Long Khí về 0, có tiến độ ấp', after.egg === 1 && after.lk === 0 && after.view && !after.view.ready, JSON.stringify(after));

// tab Thú cưng: thẻ trứng; đủ quái thì nở
await p.click('#tabs [data-tab="menu"]');
await p.click('[data-menu="pets"]');
await p.waitForSelector('.egg-card', { timeout: 5000 }).catch(() => null);
R.check('Thú cưng: thẻ Bọc Trăm Trứng (chưa nở được)', !!(await p.$('.egg-card [data-act="egg_hatch"][disabled]')));
await shot(p, 'hac-egg.png');
prep('kills');
await p.waitForFunction(() => (window.__hl.player().view.egg || {}).ready === true, null, { timeout: 8000 }).catch(() => null);
await p.waitForSelector('.egg-card [data-act="egg_hatch"]:not([disabled])', { timeout: 5000 }).catch(() => null);
await p.click('.egg-card [data-act="egg_hatch"]');
await p.waitForSelector('.hatch-fx', { timeout: 5000 }).catch(() => null);
R.check('trứng nở: màn "Con Rồng Cháu Tiên"', !!(await p.$('.hatch-fx')));
await p.waitForTimeout(1200);
await shot(p, 'hac-hatch.png');
const pets = await p.evaluate(() => window.__hl.player().pets);
R.check('có thú Hắc Long (thường hoặc Chân Thân)', pets.includes('hac_long') || pets.includes('hac_long_chan'), JSON.stringify(pets));
await p.waitForTimeout(3500);
await shot(p, 'hac-pets.png');
R.check('không lỗi JS', A.errors.length === 0, A.errors.join(' | '));
await R.done(browser);
