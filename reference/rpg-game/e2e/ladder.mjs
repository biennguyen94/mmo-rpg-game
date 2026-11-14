// Thang vùng co giãn theo server (DECISIONS "Thang vùng co giãn theo server"): thẻ 🗺 Thang vùng chuyển sinh ở tab Quản
// trị (bảng 10 vùng, Tính lại ngay, Đặt tay, Đóng băng); đặt tay vùng 1 = 12 → Chọn bản đồ và bản đồ vùng 1 ghi "≈ CS 12";
// quái vùng 1 mạnh hơn lúc thang gốc. Xong trả về tự động.
// Chạy: node e2e/ladder.mjs [url] [thư_mục_ảnh]. Cần scripts/e2e_seed.exs (tài khoản quản trị).
import { launch, reporter, newPlayer, adminSession, player, travel, engage, act, shot } from './lib.mjs';

const R = reporter('ladder');
const browser = await launch();
const adm = await adminSession(browser);
const ap = adm.page;
ap.on('dialog', (d) => d.accept());
const A = await newPlayer(browser, { cls: 'dk', viewport: { width: 390, height: 844 } });
await adm.admin('set_level', A.name, { level: 50 });
await adm.admin('set_rebirths', A.name, { n: 1 });
await adm.admin('add_stats', A.name, { str: 400, vit: 400, agi: 100 });
await A.page.waitForFunction(() => window.__hl.player().level === 50 && (window.__hl.player().rebirths || 0) >= 1, null, { timeout: 10000 }).catch(() => null);

// thẻ quản trị
await ap.evaluate(() => window.Net.admin('realm_ladder_set', { overrides: Object.fromEntries([...Array(10)].map((_, i) => [i + 1, null])) }).catch(() => null));
await ap.evaluate(() => window.__hl.menu('admin'));
await ap.waitForSelector('#adm-ladder table', { timeout: 10000 });
R.check('thẻ Thang vùng: bảng 10 vùng', (await ap.$$('#adm-ladder tr')).length === 11);

// mức gốc: quái vùng 1
async function realmFight() {
  if ((await player(A.page)).pos.map !== 'realm_01') {
    if ((await player(A.page)).pos.map !== 'village') await travel(A.page, 'village');
    R.check('qua cổng tới vùng 1', await travel(A.page, 'realm_01'));
  }
  if (!(await engage(A.page))) return null;
  const m = (await player(A.page)).battle.monster;
  for (let i = 0; i < 6; i++) { const b = (await player(A.page)).battle; if (!b || b.over) break; await act(A.page, 'flee').catch(() => null); }
  await act(A.page, 'leave').catch(() => null);
  return m;
}
const m0 = await realmFight();

await ap.fill('#adm-lad-1', '12');
await ap.click('[data-adm="realm_ladder_set"]');
await ap.waitForTimeout(800);
await ap.$eval('#adm-ladder', (e) => e.scrollIntoView({ block: 'center' }));
await shot(ap, 'ladder-admin.png');
// hàng vùng 1: Gốc | Mục tiêu | Hiện tại | Đặt tay
const row1 = await ap.evaluate(() => [...document.querySelectorAll('#adm-ladder tr')[1].querySelectorAll('td')].map((c) => c.textContent.trim()));
R.check('đặt tay vùng 1 = 12: cột Hiện tại đổi', row1[2] === '12', JSON.stringify(row1));

await A.page.waitForFunction(() => (window.__ladder || [])[0] === 12, null, { timeout: 5000 }).catch(() => null);
R.check('người chơi nhận thang mới', await A.page.evaluate(() => (window.__ladder || [])[0] === 12));
await A.page.waitForTimeout(300);
R.check('bản đồ vùng 1 ghi ≈ CS 12', /≈ CS 12/.test(await A.page.textContent('.map-top').catch(() => '')));
await shot(A.page, 'ladder-map.png');
const m1 = await realmFight();
R.check('quái vùng 1 mạnh hơn (máu, cấp)', m0 && m1 && m1.maxHp > m0.maxHp && m1.level > m0.level, JSON.stringify({ m0: m0 && [m0.maxHp, m0.level], m1: m1 && [m1.maxHp, m1.level] }));

await A.page.click('#tabs [data-tab="travel"]');
await A.page.click('[data-act="travel-seg"][data-seg="cs"]').catch(() => null);
await A.page.waitForTimeout(300);
R.check('Chọn bản đồ: vùng 1 ghi ≈ CS 12', /≈ CS 12/.test(await A.page.textContent('#view')));
await shot(A.page, 'ladder-travel.png');

// 🤖 Tính cả bot: bật → nút sáng, mẫu ghi "cả bot"; tắt lại
await ap.click('[data-adm="realm_ladder_bots"]');
await ap.waitForFunction(() => /Bật/.test((document.querySelector('[data-adm="realm_ladder_bots"]') || {}).textContent || ''), null, { timeout: 8000 }).catch(() => null);
const botsOn = await ap.evaluate(() => ({ btn: document.querySelector('[data-adm="realm_ladder_bots"]').getAttribute('aria-pressed'), txt: document.querySelector('#adm-ladder').textContent }));
R.check('🤖 Tính cả bot: bật, mẫu ghi "cả bot"', botsOn.btn === 'true' && /cả bot/.test(botsOn.txt), botsOn.btn);
await ap.$eval('#adm-ladder', (e) => e.scrollIntoView({ block: 'center' }));
await shot(ap, 'ladder-bots.png');
await ap.click('[data-adm="realm_ladder_bots"]');
await ap.waitForFunction(() => /Tắt/.test((document.querySelector('[data-adm="realm_ladder_bots"]') || {}).textContent || ''), null, { timeout: 8000 }).catch(() => null);
R.check('🤖 Tính cả bot: tắt lại', (await ap.getAttribute('[data-adm="realm_ladder_bots"]', 'aria-pressed')) === 'false');

// trả về tự động
await ap.fill('#adm-lad-1', '');
await ap.click('[data-adm="realm_ladder_set"]');
await A.page.waitForFunction(() => (window.__ladder || [])[0] === 1, null, { timeout: 5000 }).catch(() => null);
R.check('bỏ đặt tay: về thang tự động', await A.page.evaluate(() => (window.__ladder || [])[0] === 1));
R.check('không lỗi JS', A.errors.length === 0, A.errors.join(' | '));
await R.done(browser);
