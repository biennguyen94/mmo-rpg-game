// Quản trị: "Đặt lại chỉ số" (reset_stats) + đoạn đầu công thức nhân vật tối đa (docs/ADMIN_GUIDE.md §6) trên chính
// tài khoản admin: dù trước đó đã cộng điểm / chỉ số, chạy xong vẫn ra đúng điểm của người chơi thật cấp 50 chuyển sinh 10.
// Chạy: node e2e/adminreset.mjs [url] [thư_mục_ảnh]
import { launch, reporter, adminSession, shot } from './lib.mjs';

const R = reporter('adminreset');
const browser = await launch();
const { page } = await adminSession(browser);
const run = () => page.evaluate(async () => {
  const uid = Net.userId;
  const A = async (op, p = {}) => { try { await Net.admin(op, { uid, ...p }); } catch (e) { console.warn(op, e.msg); } };
  const me = async () => (await Net.send({ act: 'title_set', id: null })).player;
  const cls = (await me()).cls;
  // giả như đã cày / chạy công thức cũ: điểm và chỉ số dư
  await A('add_points', { n: 123 });
  await A('add_stats', { str: 200, agi: 150 });
  // --- đoạn công thức trong tài liệu ---
  await A('set_rebirths', { n: 10 });
  await A('set_level', { level: 50 });
  await A('reset_stats');
  const SHARE = {
    dk:  [['str', 0.45], ['agi', 0.2], ['vit', 0.25], ['ene', 0.1]],
    dw:  [['ene', 0.5], ['agi', 0.2], ['vit', 0.2], ['str', 0.1]],
    elf: [['agi', 0.45], ['str', 0.2], ['vit', 0.25], ['ene', 0.1]],
    mg:  [['str', 0.4], ['ene', 0.25], ['agi', 0.2], ['vit', 0.15]],
  }[cls];
  const after = await me();
  if (uid === Net.userId) {
    const alloc = async (stat, n) => { for (; n > 0; n -= 99) { await new Promise((r) => setTimeout(r, 300)); await Net.send({ act: 'alloc', stat, n: Math.min(n, 99) }); } };
    const total = (await me()).points;
    for (const [stat, r] of SHARE) await alloc(stat, Math.floor(total * r));
    await alloc(SHARE[0][0], (await me()).points);
  }
  const p = await me();
  return { cls, reset: after.points, statsAfterReset: after.stats, left: p.points, sum: Object.values(p.stats).reduce((a, b) => a + b, 0) };
});
const a = await run();
const base = { dk: 83, dw: 81, elf: 82, mg: 104 }[a.cls], want = { dk: 495, dw: 495, elf: 495, mg: 593 }[a.cls];
R.check('reset_stats: điểm = 49 × điểm mỗi cấp + 10 × 25', a.reset === want, JSON.stringify(a));
R.check('chia hết điểm theo tỉ lệ, tổng chỉ số = gốc + điểm', a.left === 0 && a.sum === base + want, JSON.stringify(a));
const b = await run();
R.check('chạy lại công thức: ra y hệt (không cộng dồn)', b.reset === a.reset && b.sum === a.sum, JSON.stringify(b));

// nút "Đặt lại chỉ số" trên tab Quản trị (có hỏi xác nhận)
page.on('dialog', (d) => d.accept());
const name = await page.evaluate(() => window.__hl.player().name);
await page.evaluate(() => Net.admin('add_points', { uid: Net.userId, n: 50 }));
await page.click('#tabs [data-tab="menu"]');
await page.click('[data-menu="admin"]');
for (let i = 0; i < 20 && !(await page.$('[data-adm="reset_stats"]')); i++) {
  await page.fill('#adm-name', name);
  await page.press('#adm-name', 'Enter');
  await page.waitForSelector('[data-adm="reset_stats"]', { timeout: 1000 }).catch(() => null);
}
await page.click('[data-adm="reset_stats"]');
await page.waitForFunction((w) => window.__hl.player().points === w, a.reset, { timeout: 5000 }).catch(() => null);
const p = await page.evaluate(() => window.__hl.player());
R.check('nút Đặt lại chỉ số: chỉ số gốc, điểm về đúng', p.points === a.reset && Object.values(p.stats).reduce((x, y) => x + y, 0) === base, `${p.points} điểm, ${JSON.stringify(p.stats)}`);
await page.locator('[data-adm="reset_stats"]').scrollIntoViewIfNeeded();
await shot(page, 'adminreset.png');
await R.done(browser);
