// Đợt 8 phase 2026-10: tự đánh (B-31), bộ 4 kỹ năng tháp (B-29), vùng chuyển sinh (B-30), bộ hình đồ Pixel (B-33),
// hiệu ứng bản đồ (B-32).
// Chạy: node e2e/features.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, player, act, send, shot, overflowX } from './lib.mjs';

const R = reporter('features');
const browser = await launch();
const P = await newPlayer(browser, { cls: 'dk', viewport: { width: 420, height: 900 } });
const { admin } = await adminSession(browser);
const page = P.page;

await admin('set_level', P.name, { level: 8 });
await admin('add_stats', P.name, { str: 40, vit: 30 });
await admin('add_gold', P.name, { amount: 200000 });
await admin('give_item', P.name, { id: 'potion_s', count: 10 });
await page.waitForFunction(() => window.__hl.player().level >= 8 && (window.__hl.player().inv.potion_s || 0) >= 10, null, { timeout: 8000 }).catch(() => null);

// ---------- Tự đánh ----------
await send(page, { act: 'travel', to: 'village' }).catch(() => null);
await act(page, '[data-tab="map"]').catch(() => null);
await page.waitForSelector('#auto-bar', { timeout: 5000 }).catch(() => null);
R.check('Làng: thanh tự đánh báo không có quái', ((await page.textContent('#auto-bar').catch(() => '')) || '').includes('không có quái'));

await send(page, { act: 'travel', to: 'forest_1' });
await page.waitForFunction(() => window.__hl.player().pos.map === 'forest_1', null, { timeout: 5000 }).catch(() => null);
await page.waitForSelector('[data-act="auto-set"]', { timeout: 5000 }).catch(() => null);
await act(page, 'auto-set');
await page.selectOption('[data-auto="loot"]', 'pick');
await page.selectOption('[data-auto="range"]', '8');
await page.selectOption('[data-auto="skills"]', 'basic');
await page.selectOption('[data-auto="hp"]', '30');
await act(page, '.auto-go');
let p = await player(page);
R.check('lưu cài đặt theo nhân vật', !!p.view.autoCfg && p.view.autoCfg.range === 8, JSON.stringify(p.view.autoCfg));
R.check('bật tự đánh: server nhận cài đặt', p.auto && p.auto.loot === 'pick' && p.auto.range === 8 && p.auto.skills === 'basic' && p.auto.hp === 30 && p.auto.map === 'forest_1', JSON.stringify(p.auto));
const k0 = p.kills;
await page.waitForFunction((k) => { const q = window.__hl.player(); return q.kills > k && !q.battle; }, k0, { timeout: 60000 }).catch(() => null);
p = await player(page);
R.check('tự đánh: hạ quái và rời bảng kết quả mà không bấm gì', p.kills > k0 && !p.battle, JSON.stringify({ kills: p.kills - k0, battle: !!p.battle }));
R.check('thanh tự đánh hiện số quái đã hạ', ((await page.textContent('#auto-bar').catch(() => '')) || '').includes('đã hạ'));
R.check('bản đồ có thanh tự đánh: không tràn ngang', !(await overflowX(page)));
await shot(page, 'features-auto.png');
await page.waitForSelector('[data-act="auto-off"]', { timeout: 5000 }).catch(() => null);
await act(page, 'auto-off');
await page.waitForFunction(() => !window.__hl.player().auto, null, { timeout: 5000 }).catch(() => null);
R.check('tắt tự đánh', !(await player(page)).auto);

// ---------- Kỹ năng tháp, bộ 4 kỹ năng ----------
await admin('set_tower', P.name, { floor: 40 });
await page.waitForFunction(() => (window.__hl.player().view.skillsOpen || []).some((id) => id.startsWith('t_')), null, { timeout: 5000 }).catch(() => null);
p = await player(page);
const open = p.view.skillsOpen || [];
R.check('kỷ lục tháp 40: mở 4 kỹ năng tháp', open.filter((id) => id.startsWith('t_')).length === 4, JSON.stringify(open));
const pick = open.slice(-4);
p = await send(page, { act: 'skill_set', ids: pick });
R.check('chọn bộ 4 kỹ năng mang vào trận', JSON.stringify(p.view.skillSet) === JSON.stringify(pick), JSON.stringify(p.view.skillSet));

// ---------- Vùng đất chuyển sinh ----------
await admin('set_level', P.name, { level: 45 });
await page.waitForFunction(() => window.__hl.player().level >= 45, null, { timeout: 5000 }).catch(() => null);
p = await send(page, { act: 'travel', to: 'realm_01' });
R.check('chưa chuyển sinh: không vào được vùng chuyển sinh 1', p.pos.map !== 'realm_01', p.pos.map);
await admin('set_rebirths', P.name, { n: 1 });
await page.waitForFunction(() => (window.__hl.player().rebirths || 0) >= 1, null, { timeout: 5000 }).catch(() => null);
p = await send(page, { act: 'travel', to: 'realm_01' });
R.check('chuyển sinh 1 lần: vào vùng chuyển sinh 1', p.pos.map === 'realm_01', p.pos.map);
p = await send(page, { act: 'travel', to: 'realm_02' });
R.check('vùng 2 vẫn khóa (cần chuyển sinh 2 lần)', p.pos.map !== 'realm_02', p.pos.map);
p = await send(page, { act: 'travel', to: 'realm_01_5' });
R.check('vùng 1 bản đồ 5 (sâu nhất) vào được', p.pos.map === 'realm_01_5', p.pos.map);
await page.waitForTimeout(800);
await shot(page, 'realm-depth5.png');
p = await send(page, { act: 'travel', to: 'realm_01' });

// ---------- Bộ hình đồ, hiệu ứng bản đồ ----------
const bagSrcs = async () => {
  await act(page, '[data-tab="bag"]');
  return page.$$eval('img.own', (ims) => ims.map((i) => i.getAttribute('src')));
};
await page.evaluate(() => localStorage.setItem('hl-icons', 'pixel'));
const pix = await bagSrcs();
R.check('bộ hình Pixel: túi đồ dùng hình pixel/', pix.some((s) => s.includes('pixel/')), JSON.stringify(pix.slice(0, 3)));
await shot(page, 'features-pixel.png');
await page.evaluate(() => localStorage.setItem('hl-icons', 'svg'));
const svg = await bagSrcs();
R.check('bộ hình Biểu tượng: không còn hình pixel', !svg.some((s) => s.includes('pixel/')), JSON.stringify(svg.slice(0, 3)));

await act(page, '[data-tab="menu"]');
await act(page, '[data-menu="settings"]');
const fx0 = await page.getAttribute('[data-act="map-fx"]', 'aria-pressed');
await act(page, 'map-fx');
const fx1 = await page.getAttribute('[data-act="map-fx"]', 'aria-pressed');
R.check('nút bật / tắt hiệu ứng bản đồ', fx0 !== fx1, `${fx0} → ${fx1}`);
R.check('Cài đặt có chọn bộ hình đồ', !!(await page.$('[data-act="icon-set"][data-set="pixel"]')));

R.check('không lỗi JS', P.errors.length === 0, P.errors.join(' | '));
await R.done(browser);
