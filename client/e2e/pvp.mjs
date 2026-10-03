// P4-M1 qua trình duyệt thật: trong thị trấn không có [⚔ Tấn công]; ngoài thị trấn bấm người
// chơi → [⚔ Tấn công] → hỏi xác nhận (người NORMAL) → đánh tới chết; kẻ đánh nhấp nháy rồi thành
// WARNING (tên cam, panel "PK Cảnh báo (1)", thông báo); nạn nhân hồi sinh ở thị trấn; người cấp 5
// không đánh được; MURDERER bị NPC từ chối.
//   node client/e2e/pvp.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1. Cấp / HP / PK đặt bằng scripts/e2e_pvp.exs (chỉ cho test).
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
    await page.waitForTimeout(900);
  }
  return false;
};

async function account(tag, level, hp, pk) {
  const user = `pv${tag}${stamp}`;
  const name = `${tag}${stamp}`;
  const ip = `10.93.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
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
  execSync(`mix run scripts/e2e_pvp.exs ${user} ${level} ${hp} ${pk}`, { env: { ...process.env, LANG: "C.UTF-8" } });
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
const entityOf = (page, name) => page.evaluate((n) => window.__mu.entities().find((e) => e.name === n), name);
async function menuOn(page, name) {
  const t = await entityOf(page, name);
  await clickAt(page, t.x, t.y);
  return page.waitForSelector('[data-test="playermenu"]', { timeout: 3000 }).then(() => true).catch(() => false);
}

const A = await account("Pa", 10, 999999, 0);
const B = await account("Pb", 10, 8, 0);
const L = await account("Pl", 5, 999999, 0);
const pa = await enter(A.user);
const pb = await enter(B.user);


// ---------- trong thị trấn: không có nút tấn công ----------
await walkTo(pa, 17, 31);
await walkTo(pb, 19, 31);
await menuOn(pa, B.name);
check("trong thị trấn (safe zone): menu người chơi không có [⚔ Tấn công]", !(await pa.$('[data-test="pvp-attack"]')));
await pa.keyboard.press("Escape");

// ---------- ra ngoài thị trấn (đoạn đường ngay ngoài cổng, cách vùng Spider > 10 ô) ----------
await walkTo(pa, 28, 31);
await walkTo(pb, 30, 31);
check("menu người chơi ngoài thị trấn có [⚔ Tấn công]", (await menuOn(pa, B.name)) && !!(await pa.$('[data-test="pvp-attack"]')));
await pa.click('[data-test="pvp-attack"]');
const asked = await pa.waitForSelector('[data-test="pvp-confirm"]', { timeout: 2000 }).then(() => true).catch(() => false);
check("đánh người NORMAL lần đầu → hỏi xác nhận (sẽ bị tính PK)", asked && (await pa.textContent('[data-test="pvp-confirm"]')).includes("PK"));
await pa.screenshot({ path: `${shots}/p4-pvp-confirm.png` });
await pa.click('[data-test="pvp-confirm-yes"]');

const aggressor = await until(pb, (n) => window.__mu.entities().find((e) => e.name === n)?.aggressor === true, A.name, 6000);
check("B thấy A là kẻ gây sự (aggressor, tên nhấp nháy)", aggressor);
const died = await until(pb, () => window.__mu.entities().find((e) => e.id === window.__mu.selfId)?.state === "dead", null, 60000);
check("A tự đánh tới khi B chết (B thấy mình chết)", died);
const warn = await until(pa, () => window.__mu.player().view.pkState === "WARNING" && window.__mu.player().view.pkPoints === 1, null, 5000);
check("A giết người NORMAL → PK 1, trạng thái Cảnh báo", warn);
const orange = await until(pb, (n) => window.__mu.entities().find((e) => e.name === n)?.pkState === "WARNING", A.name, 5000);
check("người khác thấy A có pkState WARNING (tên cam)", orange);
await pa.click('[data-tab="notices"]');
const notice = await pa.textContent('[data-panel="notices"]');
check("thông báo \"Bạn đã giết người chơi — điểm PK 1\"", notice.includes("điểm PK 1"));
await pa.keyboard.press("Escape");
await pa.click('[data-tab="character"]');
const sheet = await pa.textContent('[data-panel="character"]');
check("panel Nhân vật: PK Cảnh báo (1)", sheet.includes("Cảnh báo (1)"));
await pa.keyboard.press("Escape");
await pa.screenshot({ path: `${shots}/p4-pvp-warning.png` });
const respawn = await until(pb, () => { const p = window.__mu.player(); return p.x >= 7 && p.x < 25 && p.y >= 21 && p.y < 43 && p.hp > 0; }, null, 15000);
check("B hồi sinh ở thị trấn", respawn);


// ---------- cấp 5 không đánh được ----------
const pl = await enter(L.user);
await walkTo(pl, 29, 33);
await pa.waitForTimeout(500);
await menuOn(pa, L.name);
check("người cấp 5: không có [⚔ Tấn công]", !(await pa.$('[data-test="pvp-attack"]')));
await pa.keyboard.press("Escape");

// ---------- MURDERER bị NPC từ chối ----------
const M = await account("Pm", 10, 999999, 2);
const pm = await enter(M.user);
check("MURDERER: panel Nhân vật PK Sát nhân (2)", (await pm.evaluate(() => window.__mu.player().view.pkState)) === "MURDERER");
const npc = await pm.evaluate(() => window.__mu.entities().find((e) => e.id === "npc_lorencia_potion_merchant"));
await clickAt(pm, npc.x, npc.y);
const refused = await until(pm, () => document.querySelector('[data-tab="notices"] .badge') !== null, null, 8000);
await pm.click('[data-tab="notices"]');
const mtext = await pm.textContent('[data-panel="notices"]');
check("MURDERER bấm NPC → \"Sát nhân không được dùng dịch vụ NPC.\", không mở shop", refused && mtext.includes("Sát nhân không được dùng dịch vụ NPC") && !(await pm.$('[data-panel="shop"]')));

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
