// Hắc Long, linh vật Con Rồng Cháu Tiên (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long"): nhân vật đủ điều kiện (Long Vương và
// Chim Lạc cấp tối đa — đặt bằng HL_PREP: lệnh chuẩn bị chạy rpc vào server) tới Lão Hỗn Nguyên ở Làng ghép → thú Hắc Long
// (Long Phượng Hội đã bỏ hẳn, DECISIONS "Bỏ hẳn Long Phượng Hội").
// Chạy: node e2e/hac_long.mjs [url] [thư_mục_ảnh]: server chạy bằng `elixir --sname mu -S mix phx.server` (máy này);
// chuẩn bị nhân vật bằng scripts/hacprep.exs (đổi lệnh bằng HL_PREP).
import { execSync } from 'node:child_process';
import { launch, reporter, newPlayer, adminSession, send, shot, travel, meetNpc } from './lib.mjs';

const R = reporter('hac_long');
const PREP = process.env.HL_PREP || `elixir --sname prep${process.pid} ${new URL('../scripts/hacprep.exs', import.meta.url).pathname}`;
const browser = await launch();
const A = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
const { admin } = await adminSession(browser);
const p = A.page;
const prep = (mode) => execSync(`${PREP} ${A.name} ${mode}`, { stdio: 'pipe' }).toString();
await admin('set_level', A.name, { level: 50 });
await p.waitForFunction(() => window.__hl.player().level === 50, null, { timeout: 8000 }).catch(() => null);
prep('ready');
await p.waitForFunction(() => (window.__hl.player().pets || []).includes('chim_lac'), null, { timeout: 8000 }).catch(() => null);
R.check('đủ điều kiện ghép (không còn thiếu gì)', (await p.evaluate(() => window.__hl.player().view.hacMissing || ['?'])).length === 0, JSON.stringify(await p.evaluate(() => window.__hl.player().view.hacMissing)));

await travel(p, 'village').catch(() => null);
await meetNpc(p, 'chaos').catch(() => null);
await send(p, { act: 'hac_combine' }).catch(() => null);
await p.waitForFunction(() => { const q = window.__hl.player().pets || []; return q.includes('hac_long') || q.includes('hac_long_chan'); }, null, { timeout: 8000 }).catch(() => null);
const pets = await p.evaluate(() => window.__hl.player().pets);
R.check('ghép ở Lão Hỗn Nguyên: có Hắc Long (thường hoặc Chân Thân), mất Long Vương + Chim Lạc', (pets.includes('hac_long') || pets.includes('hac_long_chan')) && !pets.includes('chim_lac'), JSON.stringify(pets));
await shot(p, 'hac-combine.png');
R.check('không lỗi JS', A.errors.length === 0, A.errors.join(' | '));
await R.done(browser);
