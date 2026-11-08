// Quản trị → Dựng nhân vật tối đa (docs/ADMIN_GUIDE.md §6): tra người chơi, bấm "⚡ Dựng tối đa" → người đó cấp 50,
// chuyển sinh 10, đồ tốt nhất của lớp +11 đã mặc và có tác dụng (đủ chỉ số yêu cầu), cánh cấp 3, Long Vương, vàng.
// Chạy: node e2e/maxbuild.mjs [url] [thư_mục_ảnh]
import { launch, reporter, newPlayer, adminSession, shot } from './lib.mjs';

const R = reporter('maxbuild');
const browser = await launch();
const { page, lookup } = await adminSession(browser);
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('dialog', (d) => d.accept());

for (const cls of (process.env.CLASSES || 'dk,elf').split(',')) {
  const X = await newPlayer(browser, { cls });
  await lookup(X.name);
  await page.click('#tabs [data-tab="map"]').catch(() => null);
  await page.click('#tabs [data-tab="menu"]');
  await page.click('[data-menu="admin"]');
  await page.fill('#adm-name', X.name);
  await page.press('#adm-name', 'Enter');
  await page.waitForSelector('#adm-maxb');
  R.check(`${cls}: thẻ Dựng nhân vật tối đa hiện cho người vừa tra`, (await page.textContent('#view')).includes('Dựng nhân vật tối đa'));
  await page.click('#adm-maxb button[type="submit"]');
  await page.waitForFunction(() => /Xong/.test((document.querySelector('.adm-maxb-log') || {}).innerText || ''), null, { timeout: 60000 }).catch(() => null);
  const log = await page.textContent('.adm-maxb-log').catch(() => '');
  R.check(`${cls}: dựng xong không bước nào lỗi`, /Xong, không có lỗi/.test(log), log.split('\n').filter((l) => l.startsWith('✗')).join(' | '));
  await page.$eval('.adm-maxb-log', (e) => e.scrollIntoView()).catch(() => null);
  await shot(page, `maxbuild-admin-${cls}.png`);

  await X.page.waitForFunction(() => window.__hl.player().level === 50, null, { timeout: 10000 }).catch(() => null);
  const me = await X.page.evaluate(() => { const p = window.__hl.player(); return { level: p.level, rebirths: p.rebirths, points: p.points, gold: p.gold, equip: p.equip, inactive: p.view.inactive, pet: p.pet, hp: p.hp, max: p.view.derived.maxHp }; });
  R.check(`${cls}: cấp 50, chuyển sinh 10, hết điểm tiềm năng`, me.level === 50 && me.rebirths === 10 && me.points === 0, JSON.stringify({ l: me.level, r: me.rebirths, p: me.points }));
  const worn = Object.values(me.equip).filter(Boolean).length;
  R.check(`${cls}: đồ đã mặc (vũ khí, giáp, nhẫn, dây chuyền, cánh)`, worn >= 10 && me.equip.wing && me.equip.ring2 && me.equip.pendant, `${worn} món`);
  R.check(`${cls}: mọi món đều có tác dụng (đủ chỉ số yêu cầu)`, (me.inactive || []).length === 0, JSON.stringify(me.inactive));
  R.check(`${cls}: Long Vương, vàng, đầy máu`, me.pet === 'long_vuong' && me.gold >= 100000000 && me.hp === me.max, JSON.stringify({ pet: me.pet, gold: me.gold, hp: me.hp, max: me.max }));
  await X.page.click('#tabs [data-tab="bag"]');
  await shot(X.page, `maxbuild-player-${cls}.png`);
  R.check(`${cls}: không lỗi JS người chơi`, X.errors.length === 0, X.errors.join(' | '));
  await X.ctx.close();
}
// chọn cấp 30, chuyển sinh 20 (quá 10 lần mỗi lần +endlessPoints): điểm tiềm năng tự tính theo cấp / chuyển sinh và cộng hết; đồ cần cấp 45+ chưa mặc (⚠)
{
  const X = await newPlayer(browser, { cls: 'dw' });
  await lookup(X.name);
  await page.fill('#adm-name', X.name);
  await page.press('#adm-name', 'Enter');
  await page.waitForFunction((n) => (document.querySelector('#view').innerText || '').includes(`Cho ${n}`), X.name);
  await page.selectOption('#adm-maxb select[name="level"]', '30');
  await page.fill('#adm-maxb input[name="rebirths"]', '20');
  const base = await X.page.evaluate(() => Object.values(window.__hl.player().stats).reduce((a, b) => a + b, 0));
  await page.click('#adm-maxb button[type="submit"]');
  await page.waitForFunction(() => /Xong/.test((document.querySelector('.adm-maxb-log') || {}).innerText || ''), null, { timeout: 60000 }).catch(() => null);
  const log = await page.textContent('.adm-maxb-log').catch(() => '');
  const pts = Number((log.match(/(\d+) điểm tiềm năng chưa cộng/) || [])[1]);
  const [per, maxRb, endless, rbp] = await page.evaluate(() => [window.GAME_DATA.CLASSES.dw.points, window.GAME_DATA.RULES.maxRebirths, window.GAME_DATA.RULES.endlessPoints, window.GAME_DATA.RULES.rebirthPoints]);
  const want = 29 * per + maxRb * rbp + (20 - maxRb) * endless;
  await X.page.waitForFunction(() => window.__hl.player().level === 30, null, { timeout: 10000 }).catch(() => null);
  const me = await X.page.evaluate(() => { const p = window.__hl.player(); return { level: p.level, rebirths: p.rebirths, points: p.points, sum: Object.values(p.stats).reduce((a, b) => a + b, 0) }; });
  R.check('cấp 30 chuyển sinh 20: đúng cấp / chuyển sinh', me.level === 30 && me.rebirths === 20, JSON.stringify(me));
  R.check('điểm tiềm năng tự tính theo cấp / chuyển sinh và đã cộng hết', pts === want && me.points === 0 && me.sum - base === pts, JSON.stringify({ pts, want, ...me, base }));
  R.check('đồ cần cấp cao hơn: báo ⚠ chưa mặc, không tính lỗi', /⚠/.test(log) && !/✗/.test(log), log.split('\n').filter((l) => /✗|⚠/.test(l)).slice(0, 3).join(' | '));
  await X.ctx.close();
}
R.check('không lỗi JS quản trị', errors.length === 0, errors.join(' | '));
await R.done(browser);
