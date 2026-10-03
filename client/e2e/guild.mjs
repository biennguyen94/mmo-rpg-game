// P4-M3 qua trình duyệt thật: Menu → [🛡 Guild] (điều kiện cấp + Zen), tạo guild (trừ Zen, tên
// guild trên đầu người khác thấy), mời từ menu người chơi + hộp lời mời, mời bằng tên trong panel,
// từ chối, phong phó guild, phó guild mời / đuổi, chat /g chỉ thành viên, rời, giải tán (xác nhận).
//   node client/e2e/guild.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1. Cấp / Zen đặt bằng scripts/e2e_guild.exs (chỉ cho test).
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

async function account(tag, level = 1, zen = 0) {
  const user = `gd${tag}${stamp}`;
  const name = `${tag}${stamp}`;
  const ip = `10.97.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
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
  if (level > 1 || zen > 0) execSync(`mix run scripts/e2e_guild.exs ${user} ${level} ${zen}`, { env: { ...process.env, LANG: "C.UTF-8" } });
  return { user, name };
}

const browser = await chromium.launch({ executablePath: existsSync(exe) ? exe : undefined });
const errors = [];
async function enter(user) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
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
const stand = async (page, x, y) => {
  await clickAt(page, x, y);
  await (await page.$('[data-test="player-goto"]'))?.click();
  return until(page, ([x, y]) => window.__mu.player().x === x && window.__mu.player().y === y, [x, y], 6000);
};
// bấm người chơi `name` → menu (đúng tên) → nút `sel`
async function menuClick(page, name, sel) {
  const t = await page.evaluate((n) => window.__mu.entities().find((e) => e.name === n), name);
  if (!t) return false;
  await clickAt(page, t.x, t.y);
  const ok = await until(page, ([n, s]) => document.querySelector(`[data-target-name="${n}"]`) && document.querySelector(s), [name, sel], 3000);
  if (ok) await page.click(sel);
  else await page.keyboard.press("Escape");
  return ok;
}
const openGuild = async (page) => {
  if (await page.$('[data-panel="guild"]')) return true;
  await page.click('[data-tab="menu"]');
  await page.click('[data-test="guild-menu"]');
  return until(page, () => document.querySelector('[data-panel="guild"]') !== null, null, 3000);
};
const roster = (page) => page.$$eval("[data-guild-member]", (ms) => ms.map((m) => `${m.dataset.guildMember}:${m.dataset.role}`)).catch(() => []);
const said = (page, text) =>
  until(page, (t) => [...document.querySelectorAll('[data-test="chat-log"] .line')].some((l) => l.textContent.includes(t)), text, 4000);
const tagOf = (page, name) => page.evaluate((n) => window.__mu.entities().find((e) => e.name === n)?.guild ?? null, name);
async function say(page, text) {
  await page.keyboard.press("Enter");
  await page.keyboard.type(text);
  await page.keyboard.press("Enter");
}
const ask = async (page) => until(page, () => document.querySelector('[data-test="guild-ask"]') !== null, null, 4000);

const A = await account("Ga", 20, 25000);
const B = await account("Gb");
const C = await account("Gc");
const D = await account("Gd");
const pa = await enter(A.user);
const pb = await enter(B.user);
const pc = await enter(C.user);
const pd = await enter(D.user);
await stand(pa, 15, 35);
await stand(pb, 18, 35);
await stand(pc, 21, 35);
await stand(pd, 24, 35);
await pa.waitForTimeout(400);
const gname = `G${stamp % 100000}`;

// ---------- điều kiện + tạo ----------
check("Menu → [🛡 Guild] mở panel", await openGuild(pa));
const req = await pa.textContent('[data-test="guild-req"]').catch(() => "");
check("panel chưa có guild hiện điều kiện cấp + phí Zen", req.includes("Cần cấp") && req.includes("Zen"), req);
await openGuild(pb);
check("người thiếu cấp / Zen: nút [Tạo guild] tắt", await pb.isDisabled('[data-test="guild-create"]'));
await pb.keyboard.press("Escape");
await pa.fill('[data-test="guild-name"]', "ab");
await pa.click('[data-test="guild-create"]');
check("tên sai mẫu: báo ngay, không gửi", await until(pa, () => document.querySelector('[data-test="guild-hint"]')?.classList.contains("bad"), null, 2000));
const zen0 = await pa.evaluate(() => window.__mu.player().zen);
await pa.fill('[data-test="guild-name"]', gname);
await pa.click('[data-test="guild-create"]');
const created = await until(pa, (n) => document.querySelector('[data-panel="guild"] h2')?.textContent.includes(n), gname, 4000);
const zen1 = await pa.evaluate(() => window.__mu.player().zen);
check("tạo guild: panel GUILD · tên, mình là Chủ guild, Zen bị trừ", created && (await roster(pa)).join() === `${A.name}:master` && zen1 < zen0, `${zen0} → ${zen1}`);
check("người khác thấy tên guild trên đầu chủ guild", await until(pb, ([n, g]) => window.__mu.entities().find((e) => e.name === n)?.guild === g, [A.name, gname], 4000));
await pa.screenshot({ path: `${shots}/p4-guild-panel.png` });
await pa.keyboard.press("Escape");

// ---------- mời từ menu người chơi → đồng ý ----------
check("bấm người chơi → [🛡 Mời vào guild]", await menuClick(pa, B.name, '[data-test="guild-invite-menu"]'));
const askedB = await ask(pb);
check("người được mời thấy hộp \"… mời bạn vào guild …\"", askedB && (await pb.textContent('[data-test="guild-ask"]')).includes(gname));
await pb.screenshot({ path: `${shots}/p4-guild-invite.png` });
await pb.click('[data-test="guild-accept"]');
await openGuild(pa);
check("đồng ý → danh sách có thành viên mới; cả guild nhận thông báo", (await until(pa, (n) => document.querySelector(`[data-guild-member="${n}"]`) !== null, B.name, 4000)) && (await said(pa, `${B.name} đã vào guild`)));

// ---------- mời bằng tên → từ chối ----------
await pa.fill('[data-test="guild-invite-name"]', C.name);
await pa.click('[data-test="guild-invite"]');
check("mời bằng tên trong panel → C nhận lời mời", await ask(pc));
await pc.click('[data-test="guild-decline"]');
check("C từ chối → chủ guild nhận thông báo, hộp đóng", (await said(pa, `${C.name} từ chối`)) && !(await pc.$('[data-test="guild-ask"]')));

// ---------- thành viên thường không mời được; phong phó guild ----------
await pb.keyboard.press("Escape");
const tC = await pb.evaluate((n) => window.__mu.entities().find((e) => e.name === n), C.name);
await clickAt(pb, tC.x, tC.y);
await pb.waitForTimeout(400);
check("thành viên thường: menu không có [Mời vào guild]", !(await pb.$('[data-test="guild-invite-menu"]')));
await pb.keyboard.press("Escape");
await stand(pb, 18, 35);
await pa.click(`[data-guild-promote="${B.name}"]`);
check("chủ guild bấm ▲ → B thành Phó guild", await until(pa, (n) => document.querySelector(`[data-guild-member="${n}"]`)?.dataset.role === "assistant", B.name, 4000));

// ---------- phó guild mời ----------
check("phó guild mời C từ menu", await menuClick(pb, C.name, '[data-test="guild-invite-menu"]'));
await ask(pc);
await pc.click('[data-test="guild-accept"]');
check("guild 3 người", await until(pa, () => document.querySelectorAll("[data-guild-member]").length === 3, null, 4000), JSON.stringify(await roster(pa)));

// ---------- chat /g ----------
await say(pc, "/g họp guild");
const gotA = await until(pa, () => [...document.querySelectorAll('[data-test="chat-log"] .line')].some((l) => l.textContent.includes("[Guild]") && l.textContent.includes("họp guild")), null, 4000);
await pd.waitForTimeout(300);
const leakD = await pd.$$eval('[data-test="chat-log"] .line', (ls) => ls.some((l) => l.textContent.includes("họp guild"))).catch(() => false);
check("chat /g: thành viên nhận [Guild], người ngoài không", gotA && !leakD);

// ---------- phó guild đuổi member; rời ----------
await openGuild(pb);
check("phó guild không thấy nút đuổi chủ guild", !(await pb.$(`[data-guild-kick="${A.name}"]`)));
await pb.click(`[data-guild-kick="${C.name}"]`);
const kicked = await until(pc, () => !window.__mu.entities().find((e) => e.id === window.__mu.selfId)?.guild, null, 4000);
check("phó guild đuổi C → C mất tên guild trên đầu, người khác thấy", kicked && (await until(pa, (n) => !window.__mu.entities().find((e) => e.name === n)?.guild, C.name, 4000)));
await pb.click('[data-test="guild-leave"]');
check("B bấm [Rời guild] → panel B về \"chưa có guild\"", await until(pb, () => document.querySelector('[data-test="guild-create"]') !== null, null, 4000));
check("B biến khỏi danh sách của chủ guild", await until(pa, (n) => !document.querySelector(`[data-guild-member="${n}"]`), B.name, 4000));

// ---------- giải tán (xác nhận) ----------
check("chủ guild không có nút [Rời guild]", !(await pa.$('[data-test="guild-leave"]')));
await pa.click('[data-test="guild-disband"]');
check("[Giải tán guild] hỏi xác nhận", (await pa.$('[data-test="guild-disband-confirm"]')) !== null);
await pa.click('[data-test="guild-disband-confirm"]');
const gone = await until(pa, () => document.querySelector('[data-test="guild-create"]') !== null, null, 4000);
check("giải tán → panel về \"chưa có guild\", tên guild trên đầu mất", gone && (await until(pd, (n) => !window.__mu.entities().find((e) => e.name === n)?.guild, A.name, 4000)) && (await tagOf(pa, A.name)) === null);

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
