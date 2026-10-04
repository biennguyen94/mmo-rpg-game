// Thư viện chung cho e2e Hắc Long: mở trình duyệt, đăng ký + tạo nhân vật, đi trên bản đồ, gặp NPC,
// đánh quái, lệnh quản trị, chụp ảnh, in PASS / FAIL. Mỗi kịch bản dùng tài khoản ngẫu nhiên nên chạy
// độc lập, chạy lại được nhiều lần trên cùng database.
//
// Biến môi trường:
//   HL_URL              địa chỉ server (mặc định http://localhost:4000; tham số dòng lệnh đầu tiên cũng được)
//   HL_SHOTS            thư mục ảnh (mặc định e2e/screenshots; tham số thứ hai)
//   PLAYWRIGHT_MODULE   đường dẫn playwright (mặc định bản cài sẵn /opt/node-tools, rồi `playwright`)
//   CHROMIUM_PATH       Chromium có sẵn (mặc định /opt/pw-browsers/chromium nếu có)
//   HL_E2E_ADMIN(_PASS) tài khoản quản trị do scripts/e2e_seed.exs tạo
//
// Server cần TRUSTED_PROXIES=127.0.0.1: mỗi người chơi test gửi X-Forwarded-For riêng để không
// chạm giới hạn đăng ký theo IP (5 / giờ).
import fs from 'node:fs';
import path from 'node:path';

export const BASE = process.argv[2] || process.env.HL_URL || 'http://localhost:4000';
export const SHOTS = process.argv[3] || process.env.HL_SHOTS || path.join(path.dirname(new URL(import.meta.url).pathname), 'screenshots');
fs.mkdirSync(SHOTS, { recursive: true });

async function loadPlaywright() {
  const candidates = [process.env.PLAYWRIGHT_MODULE, '/opt/node-tools/node_modules/playwright/index.mjs', 'playwright'].filter(Boolean);
  for (const c of candidates) {
    if (c.startsWith('/') && !fs.existsSync(c)) continue;
    try { return await import(c); } catch (e) { /* thử tiếp */ }
  }
  throw new Error('Không tìm thấy playwright (đặt PLAYWRIGHT_MODULE hoặc npm install playwright).');
}

export async function launch() {
  const { chromium } = await loadPlaywright();
  const exe = process.env.CHROMIUM_PATH || '/opt/pw-browsers/chromium';
  return chromium.launch({ executablePath: fs.existsSync(exe) ? exe : undefined });
}

// ---------- Kết quả ----------
export function reporter(name) {
  let pass = 0, fail = 0;
  const r = {
    check(what, ok, extra = '') {
      ok ? pass++ : fail++;
      console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}${extra && !ok ? '  — ' + extra : ''}`);
      return ok;
    },
    async done(browser) {
      if (browser) await browser.close();
      console.log(`\n${name}: ${pass} PASS / ${fail} FAIL`);
      process.exit(fail ? 1 : 0);
    },
  };
  return r;
}

const rand = () => Math.random().toString(36).slice(2, 8);
const ip = () => `10.${1 + Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}.${1 + Math.floor(Math.random() * 250)}`;

// ---------- Người chơi ----------
// Mở một trình duyệt riêng (context), đăng ký tài khoản mới, tạo nhân vật lớp `cls`.
// Trả { page, ctx, user, name, errors }; `errors`: lỗi JS trên trang (kịch bản kiểm phải rỗng).
export async function newPlayer(browser, { cls = 'dk', viewport = { width: 1280, height: 900 }, name } = {}) {
  const ctx = await browser.newContext({ viewport, extraHTTPHeaders: { 'x-forwarded-for': ip() } });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('dialog', (d) => d.accept());
  const user = `t_${rand()}`;
  name = name || `T${rand()}`;
  await page.goto(`${BASE}/?test=1`);
  await page.waitForSelector('#auth');
  await page.click('[data-auth="register"]');
  await page.fill('#auth-user', user);
  await page.fill('#auth-pass', 'password123');
  await page.click('#auth button[type="submit"]');
  await page.waitForSelector('#hero-name');
  await page.fill('#hero-name', name);
  await page.click(`.class-opt[data-cls="${cls}"]`);
  await page.click('#create button[type="submit"]');
  await page.waitForFunction(() => window.__hl && window.__hl.player());
  return { page, ctx, user, name, errors };
}

// Đăng nhập tài khoản quản trị (scripts/e2e_seed.exs) để tặng vàng / đồ cho người chơi test qua lệnh quản trị.
export async function adminSession(browser) {
  const ctx = await browser.newContext({ extraHTTPHeaders: { 'x-forwarded-for': ip() } });
  const page = await ctx.newPage();
  await page.goto(`${BASE}/?test=1`);
  await page.waitForSelector('#auth');
  await page.fill('#auth-user', process.env.HL_E2E_ADMIN || 'e2e_admin');
  await page.fill('#auth-pass', process.env.HL_E2E_ADMIN_PASS || 'e2e-admin-pass');
  await page.click('#auth button[type="submit"]');
  await page.waitForFunction(() => window.__hl && window.__hl.ui().logged && !window.__hl.ui().loading);
  // tab Quản trị chỉ hiện khi đã có nhân vật: tài khoản quản trị mới thì tạo một nhân vật
  await page.waitForSelector('#hero-name, #tabs:not([hidden])');
  if (await page.$('#hero-name')) {
    await page.fill('#hero-name', `KT${rand()}`);
    await page.click('#create button[type="submit"]');
    await page.waitForFunction(() => window.__hl.player());
  }
  const uids = new Map();
  // lệnh quản trị lên nhân vật tên `who` (tra uid một lần): admin('add_gold', 'Tên', { amount: 100 })
  // nhân vật mới chỉ vào database ở lần lưu định kỳ của Session (vài giây): tra lại tới khi thấy
  async function lookup(who) {
    for (let i = 0; i < 40 && !uids.has(who); i++) {
      const r = await page.evaluate((n) => window.Net.admin('lookup', { name: n }).catch(() => null), who);
      if (r && r.user) uids.set(who, r.user.id); else await page.waitForTimeout(500);
    }
    if (!uids.has(who)) throw new Error(`Quản trị không tìm thấy ${who}`);
    return uids.get(who);
  }
  async function admin(op, who, payload = {}) {
    const uid = await lookup(who);
    return page.evaluate(([op, p]) => window.Net.admin(op, p).catch((e) => ({ error: e.msg })), [op, { uid, ...payload }]);
  }
  return { page, ctx, admin, lookup };
}

// ---------- Trạng thái, thao tác (window.__hl, chỉ có khi mở trang với ?test=1) ----------
export const player = (page) => page.evaluate(() => window.__hl.player());
export const ui = (page) => page.evaluate(() => window.__hl.ui());
export const idle = (page) => page.waitForFunction(() => !window.__hl.ui().busy && !window.__hl.ui().walking, null, { timeout: 15000 });

// Gửi lệnh như bấm nút (qua sendCommand của giao diện); trả trạng thái nhân vật sau lệnh.
export async function send(page, cmd) {
  await idle(page);
  return page.evaluate((c) => window.__hl.send(c), cmd);
}

// Bấm nút `data-act` (có thể kèm thêm thuộc tính, vd '[data-id="potion_s"]') rồi chờ xong.
export async function act(page, sel) {
  await idle(page);
  await page.click(sel.startsWith('[') || sel.startsWith('.') || sel.startsWith('#') ? sel : `[data-act="${sel}"]`);
  await page.waitForTimeout(80);
  await idle(page);
}

export async function walkTo(page, x, y) {
  await idle(page);
  return page.evaluate(([x, y]) => window.__hl.walkTo(x, y), [x, y]);
}

// Đi qua cổng sang bản đồ kề `to` (đứng trên ô cổng). Trả true nếu đã sang.
export async function travel(page, to) {
  const p = await player(page);
  const portal = await page.evaluate(([from, to]) => {
    const m = window.GAME_DATA.WORLD.maps[from];
    return m.portals.find((q) => q.to === to);
  }, [p.pos.map, to]);
  if (!portal) throw new Error(`Không có cổng ${p.pos.map} → ${to}`);
  await walkTo(page, portal.at[0], portal.at[1]);
  await page.waitForFunction((to) => window.__hl.player().pos.map === to, to, { timeout: 10000 }).catch(() => null);
  await idle(page);
  return (await player(page)).pos.map === to;
}

// Gặp NPC `id` trên bản đồ đang đứng (bước vào NPC → mở hội thoại). Trả true nếu đã mở.
export async function meetNpc(page, id) {
  const n = (await page.evaluate(() => window.__hl.npcs())).find((x) => x.id === id);
  if (!n) throw new Error(`Không có NPC ${id}`);
  await walkTo(page, n.at[0], n.at[1]);
  await page.waitForFunction((id) => window.__hl.ui().npc === id, id, { timeout: 8000 }).catch(() => null);
  return (await ui(page)).npc === id;
}

export async function leaveNpc(page) {
  await act(page, 'npc-close');
}

// Chạm vào con quái gần nhất (loại `kind` nếu có) trên bản đồ → vào trận. Trả true nếu đang trong trận.
export async function engage(page, kind = null, tries = 6) {
  for (let i = 0; i < tries; i++) {
    const w = await page.evaluate(() => window.__hl.world());
    const me = (await player(page)).pos;
    const mons = (w.monsters || []).filter((m) => w.map === me.map && !m.busy && (!kind || m.kind === kind));
    if (!mons.length) { await page.waitForTimeout(500); continue; }
    mons.sort((a, b) => Math.abs(a.x - me.x) + Math.abs(a.y - me.y) - (Math.abs(b.x - me.x) + Math.abs(b.y - me.y)));
    await walkTo(page, mons[0].x, mons[0].y);
    if ((await player(page)).battle) return true;
  }
  return !!(await player(page)).battle;
}

// Đánh tới khi trận kết thúc (tấn công; máu thấp thì uống bình). Trả kết quả 'win' | 'lose' | 'fled'.
export async function fight(page, maxTurns = 80) {
  for (let i = 0; i < maxTurns; i++) {
    const p = await player(page);
    if (!p.battle || p.battle.over) break;
    const low = p.hp < p.view.derived.maxHp * 0.3;
    const potion = await page.$('[data-act="potion"]:not([disabled])');
    await act(page, low && potion ? 'potion' : 'attack');
  }
  const p = await player(page);
  return p.battle && p.battle.result;
}

export async function shot(page, file) {
  await page.screenshot({ path: path.join(SHOTS, file), fullPage: false });
}

// Trang có tràn ngang không (điện thoại).
export const overflowX = (page) => page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
