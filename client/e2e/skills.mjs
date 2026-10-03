// P2-M3 qua trình duyệt thật: skill theo class.
// - Elf cấp 12: click chính mình → menu Heal / Greater Defense / Greater Damage; buff hiện ở HUD;
//   click người chơi khác → Heal (tốn MP, server trả combat có `heal`).
// - DW cấp 15: click chính mình → Teleport… → chọn ô → nhảy ngay (không đi bộ); MP tự hồi;
//   Energy Ball lên Spider được lặp lại tự động.
//   node client/e2e/skills.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1: mỗi tài khoản đăng ký từ một X-Forwarded-For riêng (giới
// hạn đăng ký theo IP). Cấp nhân vật đặt bằng scripts/e2e_level.exs (chỉ cho test).
import { execSync } from "node:child_process";
import { existsSync } from "node:fs";

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? "/opt/node-tools/node_modules/playwright/index.mjs");
const base = process.argv[2] ?? "http://localhost:4000";
const shots = process.argv[3] ?? "docs/screenshots";
const exe = process.env.CHROMIUM_PATH ?? "/opt/pw-browsers/chromium";
const results = [];
const check = (name, ok, extra = "") => {
  results.push({ name, ok, extra });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${extra ? "  — " + extra : ""}`);
};
const stamp = Date.now() % 1_000_000;
const until = (page, fn, arg, ms = 5000) =>
  page.waitForFunction(fn, arg, { timeout: ms }).then(() => true).catch(() => false);
const player = (page) => page.evaluate(() => window.__mu.player());
const self = (page) => page.evaluate(() => window.__mu.entities().find((e) => e.id === window.__mu.selfId));
const tilePx = async (page, x, y) => {
  const me = await self(page);
  const b = await page.locator('[data-test="game-canvas"]').boundingBox();
  return { x: b.x + b.width / 2 + (x - me.x) * 32, y: b.y + b.height / 2 + (y - me.y) * 32 };
};
const clickAt = async (page, x, y) => {
  const p = await tilePx(page, x, y);
  await page.mouse.click(p.x, p.y);
};

async function account(tag, cls, level) {
  const user = `sk${tag}${stamp}`;
  const ip = `10.77.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
  const call = async (path, body, token) =>
    (
      await fetch(base + path, {
        method: "POST",
        headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify(body),
      })
    ).json();
  const { token } = await call("/register", { username: user, password: "matkhau123" });
  await call("/characters", { name: `${tag}${stamp}`, class: cls }, token);
  execSync(`mix run scripts/e2e_level.exs ${user} ${level}`, { env: { ...process.env, LANG: "C.UTF-8" } });
  return user;
}

const browser = await chromium.launch({ executablePath: existsSync(exe) ? exe : undefined });
const errors = [];
async function enter(user, sent = null, recv = null) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => errors.push(String(e)));
  if (sent) page.on("websocket", (ws) => ws.on("framesent", (f) => sent.push(String(f.payload))));
  if (recv) page.on("websocket", (ws) => ws.on("framereceived", (f) => recv.push(String(f.payload))));
  await page.goto(base);
  await page.fill('input[name="username"]', user);
  await page.fill('input[name="password"]', "matkhau123");
  await page.click('button[type="submit"]');
  await page.click("text=Vào game");
  await page.waitForSelector('[data-test="where"]');
  await page.waitForFunction(() => window.__mu.entities().some((e) => e.id === window.__mu.selfId));
  return page;
}

// ---------- Elf: buff + heal ----------
const elf = await enter(await account("Ef", "ELF", 12));
const dkRecv = [];
const dk = await enter(await account("Dk", "DK", 1), null, dkRecv);
let me = await self(elf);
await clickAt(elf, me.x, me.y);
await elf.waitForSelector('[data-test="playermenu"]', { timeout: 3000 }).catch(() => null);
const menu = await elf.$$eval('[data-test="playermenu"] [data-skill]', (bs) => bs.map((b) => b.dataset.skill)).catch(() => []);
check("Elf click chính mình → menu Heal / Greater Defense / Greater Damage", ["heal", "greater_defense", "greater_damage"].every((s) => menu.includes(s)), menu.join(","));
await elf.click('[data-test="playermenu"] [data-skill="greater_defense"]');
const buffed = await until(elf, () => window.__mu.player().view.buffs.some((b) => b.id === "greater_defense"));
const chip = await elf.locator('[data-test="buffs"] [data-buff="greater_defense"]').textContent().catch(() => "");
check("Greater Defense: buff vào player.view.buffs + hiện ở HUD (giá trị, giây còn lại)", buffed && /\+\d+ \d+s/.test(chip), chip);
await elf.screenshot({ path: `${shots}/p2-elf-buff.png` });

// heal người chơi DK đứng gần (cùng safe zone): DK bước ra khỏi ô chung trước
const dk0 = await self(dk);
await clickAt(dk, dk0.x + 2, dk0.y);
await until(dk, ([x, y]) => { const s = window.__mu.entities().find((e) => e.id === window.__mu.selfId); return s.x === x && s.y === y; }, [dk0.x + 2, dk0.y]);
const mpBefore = (await self(elf)).mp;
const dkMe = await self(dk);
await until(elf, ([id, x]) => window.__mu.entities().find((e) => e.id === id)?.x === x, [dkMe.id, dkMe.x]);
const dkSeen = await until(elf, (id) => window.__mu.entities().some((e) => e.id === id), dkMe.id);
await elf.waitForTimeout(1600); // cooldown Greater Defense 1500 ms
await clickAt(elf, dkMe.x, dkMe.y);
await elf.waitForSelector('[data-test="playermenu"]', { timeout: 3000 }).catch(() => null);
const menu2 = await elf.$$eval('[data-test="playermenu"] [data-skill]', (bs) => bs.map((b) => b.dataset.skill)).catch(() => []);
await elf.click('[data-test="playermenu"] [data-skill="heal"]').catch(() => null);
const healed = await until(elf, (mp) => (window.__mu.entities().find((e) => e.id === window.__mu.selfId)?.mp ?? mp) <= mp - 8 + 1, mpBefore);
await elf.waitForTimeout(300);
const dkId = dkMe.id;
const healEvt = dkRecv.some((f) => f.includes('"combat"') && f.includes('"heal"') && f.includes(dkId));
check("Elf click người chơi khác → menu chỉ skill hỗ trợ; Heal tốn MP, người kia nhận combat.heal", dkSeen && healEvt && menu2.includes("heal") && !menu2.includes("teleport") && healed, `menu ${menu2.join(",")}, MP ${mpBefore}→${(await self(elf)).mp}`);

// ---------- DW: teleport, hồi MP, Energy Ball lặp ----------
const sent = [];
const dw = await enter(await account("Dw", "DW", 15), sent);
me = await self(dw);
await clickAt(dw, me.x, me.y);
await dw.waitForSelector('[data-test="playermenu"] [data-skill="teleport"]', { timeout: 3000 }).catch(() => null);
await dw.click('[data-test="playermenu"] [data-skill="teleport"]');
const aimbar = await dw.locator('[data-test="aimbar"]').isVisible();
const dest = { x: me.x + 6, y: me.y };
await clickAt(dw, dest.x, dest.y);
// đi bộ 6 ô mất ~1,2 s; teleport tới ngay (snapshot 100 ms)
const jumped = await until(dw, ([x, y]) => { const s = window.__mu.entities().find((e) => e.id === window.__mu.selfId); return s.x === x && s.y === y; }, [dest.x, dest.y], 600);
const mpAfterTp = (await self(dw)).mp;
check("DW Teleport: dòng hướng dẫn chọn ô, tới ô đích ngay (không đi bộ)", aimbar && jumped, `(${me.x},${me.y}) → (${(await self(dw)).x},${(await self(dw)).y}), MP ${mpAfterTp}`);
const regen = await until(dw, (mp) => (window.__mu.entities().find((e) => e.id === window.__mu.selfId)?.mp ?? 0) > mp, mpAfterTp, 4000);
check("MP tự hồi sau khi dùng skill (energy/40 mỗi giây)", regen, `${mpAfterTp}→${(await self(dw)).mp}`);
await dw.screenshot({ path: `${shots}/p2-dw-teleport.png` });

// Energy Ball lên Spider gần nhất: ra khỏi thị trấn rồi chọn skill trong menu quái
const walk = async (x, y) => {
  for (let i = 0; i < 20; i++) {
    const p = await self(dw);
    if (p.x === x && p.y === y) return;
    await clickAt(dw, Math.max(p.x - 12, Math.min(p.x + 12, x)), Math.max(p.y - 8, Math.min(p.y + 8, y)));
    await dw.waitForTimeout(900);
  }
};
await walk(25, 31);
await walk(40, 31);
let casts = 0;
for (let round = 0; round < 6 && casts < 2; round++) {
  const t = await dw.evaluate(() => {
    const me = window.__mu.entities().find((e) => e.id === window.__mu.selfId);
    return window.__mu.entities()
      .filter((e) => e.kind === "monster" && e.state !== "dead")
      .map((e) => ({ id: e.id, x: e.x, y: e.y, d: Math.max(Math.abs(e.x - me.x), Math.abs(e.y - me.y)) }))
      .sort((a, b) => a.d - b.d)[0];
  });
  if (!t) { await dw.waitForTimeout(1000); continue; }
  if (t.d > 10) { await walk(t.x - 3, t.y); continue; }
  await clickAt(dw, t.x, t.y);
  if (!(await dw.waitForSelector('[data-test="ctxmenu"] >> text=Energy Ball', { timeout: 1500 }).catch(() => null))) continue;
  const before = sent.length;
  await dw.click('[data-test="ctxmenu"] >> text=Energy Ball');
  await until(dw, (id) => { const s = window.__mu.entities().find((e) => e.id === id); return !s || s.state === "dead"; }, t.id, 12000);
  casts = sent.slice(before).filter((f) => f.includes('"energy_ball"')).length;
}
check("Energy Ball lặp lại tự động tới khi quái chết", casts >= 2, `${casts} lần gửi`);
check("không lỗi JS trên trang", errors.length === 0, errors.join(" | "));

await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} PASS`);
process.exit(failed.length ? 1 : 0);
