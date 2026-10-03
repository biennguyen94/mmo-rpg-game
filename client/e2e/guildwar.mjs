// P4-M4 qua trình duyệt thật: master tuyên chiến trong panel Guild, master bên kia nhận hộp lời
// tuyên chiến → [Nhận], hai guild thấy thanh war (điểm, giờ), đánh người guild địch ngoài thị trấn
// không hỏi xác nhận PK, giết → +1 điểm, không bị tính PK; master đầu hàng (xác nhận) → hai bên
// nhận kết quả, thanh war mất.
//   node client/e2e/guildwar.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1. Cấp / Zen / HP đặt bằng scripts/e2e_guild.exs và
// scripts/e2e_pvp.exs (chỉ cho test).
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
const self = (page) => page.evaluate(() => window.__mu.entities().find((e) => e.id === window.__mu.selfId));
const clickAt = async (page, x, y) => {
  const me = await self(page);
  const b = await page.locator('[data-test="game-canvas"]').boundingBox();
  await page.mouse.click(b.x + b.width / 2 + (x - me.x) * 32, b.y + b.height / 2 + (y - me.y) * 32);
};
const walkTo = async (page, x, y, ms = 25000) => {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const p = await self(page);
    if (p.x === x && p.y === y) return true;
    await clickAt(page, Math.max(p.x - 12, Math.min(p.x + 12, x)), Math.max(p.y - 8, Math.min(p.y + 8, y)));
    await (await page.$('[data-test="player-goto"]'))?.click();
    await page.waitForTimeout(700);
  }
  return false;
};

// `seed`: lệnh chỉ cho test (cấp / Zen / HP)
async function account(tag, seed) {
  const user = `gw${tag}${stamp}`;
  const name = `${tag}${stamp}`;
  const ip = `10.98.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
  const call = async (path, body, token) =>
    (
      await fetch(base + path, {
        method: "POST",
        headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify(body),
      })
    ).json();
  const { token } = await call("/register", { username: user, password: "matkhau123" });
  await call("/characters", { name, class: "DK" }, token);
  execSync(`mix run ${seed.replace("USER", user)}`, { env: { ...process.env, LANG: "C.UTF-8" } });
  return { user, name };
}

const browser = await chromium.launch({ executablePath: existsSync(exe) ? exe : undefined });
const errors = [];
async function enter(user) {
  // mỗi trình duyệt một IP (server TRUSTED_PROXIES): 15 bộ E2E liền nhau vượt rateLimit.login.perIp nếu cùng 127.0.0.1
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    extraHTTPHeaders: { "x-forwarded-for": `10.99.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}` },
  });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(base);
  await page.fill('input[name="username"]', user);
  await page.fill('input[name="password"]', "matkhau123");
  await page.click('button[type="submit"]');
  await page.click("text=Vào game");
  await page.waitForSelector('[data-test="where"]');
  await page.waitForFunction(() => window.__mu.entities().some((e) => e.id === window.__mu.selfId));
  return page;
}
const openGuild = async (page) => {
  if (await page.$('[data-panel="guild"]')) return true;
  await page.click('[data-tab="menu"]');
  await page.click('[data-test="guild-menu"]');
  return until(page, () => document.querySelector('[data-panel="guild"]') !== null, null, 3000);
};
// master lập guild `gname` rồi mời `member` (đang online) bằng tên
async function found(pm, gname, pmember, member) {
  await openGuild(pm);
  await pm.fill('[data-test="guild-name"]', gname);
  await pm.click('[data-test="guild-create"]');
  await until(pm, () => document.querySelector('[data-test="guild-invite-name"]') !== null, null, 4000);
  await pm.fill('[data-test="guild-invite-name"]', member);
  await pm.click('[data-test="guild-invite"]');
  await until(pmember, () => document.querySelector('[data-test="guild-accept"]') !== null, null, 4000);
  await pmember.click('[data-test="guild-accept"]');
  return until(pm, () => document.querySelectorAll("[data-guild-member]").length === 2, null, 4000);
}
const bar = (page) => page.textContent('[data-test="war-bar"]').catch(() => "");

const MA = await account("Wa", "scripts/e2e_guild.exs USER 20 20000");
const MB = await account("Wb", "scripts/e2e_guild.exs USER 20 20000");
const A1 = await account("Xa", "scripts/e2e_pvp.exs USER 10 999999 0");
const B1 = await account("Xb", "scripts/e2e_pvp.exs USER 10 8 0");
const [pma, pmb, pa1, pb1] = [await enter(MA.user), await enter(MB.user), await enter(A1.user), await enter(B1.user)];
const ga = `A${stamp % 100000}`;
const gb = `B${stamp % 100000}`;

check("hai guild lập xong, mỗi guild 2 người", (await found(pma, ga, pa1, A1.name)) && (await found(pmb, gb, pb1, B1.name)));

// ---------- tuyên chiến → nhận ----------
await pma.fill('[data-test="guild-war-name"]', gb);
await pma.click('[data-test="guild-war-declare"]');
// panel full-screen che hộp / thanh war
for (const p of [pma, pmb]) await p.keyboard.press("Escape");
const asked = await until(pmb, () => document.querySelector('[data-test="war-ask"]') !== null, null, 4000);
check("master guild B thấy hộp \"… tuyên chiến\" có đếm ngược", asked && (await pmb.textContent('[data-test="war-ask"]')).includes(ga));
check("thành viên thường không nhận hộp tuyên chiến", !(await pb1.$('[data-test="war-ask"]')));
await pmb.screenshot({ path: `${shots}/p4-war-ask.png` });
await pmb.click('[data-test="war-accept"]');
const started = await until(pa1, () => document.querySelector('[data-test="war-bar"]') !== null, null, 4000);
check("bắt đầu: cả hai guild thấy thanh war 0 – 0", started && (await bar(pa1)).includes("0 – 0") && (await until(pb1, () => document.querySelector('[data-test="war-bar"]') !== null, null, 4000)));
check("chỉ master có [Đầu hàng]", !!(await pma.$('[data-test="war-surrender"]')) && !(await pa1.$('[data-test="war-surrender"]')));

// ---------- đánh người guild địch ngoài thị trấn ----------
await walkTo(pa1, 28, 31);
await walkTo(pb1, 30, 31);
const t = await pa1.evaluate((n) => window.__mu.entities().find((e) => e.name === n), B1.name);
await clickAt(pa1, t.x, t.y);
const menu = await until(pa1, (n) => document.querySelector(`[data-target-name="${n}"]`) && document.querySelector('[data-test="pvp-attack"]'), B1.name, 3000);
check("menu người guild địch có [⚔ Tấn công]", menu);
await pa1.click('[data-test="pvp-attack"]');
await pa1.waitForTimeout(400);
check("đánh người guild địch: không hỏi xác nhận PK", !(await pa1.$('[data-test="pvp-confirm"]')));
const died = await until(pb1, () => window.__mu.entities().find((e) => e.id === window.__mu.selfId)?.state === "dead", null, 60000);
check("B1 chết", died);
check("guild A được +1: thanh war 1 – 0", await until(pa1, () => document.querySelector('[data-test="war-bar"]')?.textContent.includes("1 – 0"), null, 5000), await bar(pa1));
check("kẻ giết không bị tính PK", (await pa1.evaluate(() => window.__mu.player().view.pkState)) === "NORMAL");
await pa1.screenshot({ path: `${shots}/p4-war-bar.png` });

// ---------- đầu hàng ----------
await pmb.click('[data-test="war-surrender"]');
check("[Đầu hàng] hỏi xác nhận", !!(await pmb.$('[data-test="war-surrender-confirm"]')));
await pmb.click('[data-test="war-surrender-confirm"]');
const ended = await until(pma, () => !document.querySelector('[data-test="war-bar"]'), null, 4000);
await pma.click('[data-tab="notices"]').catch(() => {});
const note = await pma.textContent('[data-panel="notices"]').catch(() => "");
check("đầu hàng → thanh war mất, guild A nhận \"thắng … (đầu hàng)\"", ended && note.includes("thắng") && note.includes("đầu hàng"), note.slice(0, 120));

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
