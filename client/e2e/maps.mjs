// P2-M4 qua trình duyệt thật: cổng Lorencia ↔ Noria, thiếu cấp bị chặn, NPC mới, quái mới có sprite.
//   node client/e2e/maps.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1 (đăng ký từ X-Forwarded-For riêng); cấp đặt bằng
// scripts/e2e_level.exs (chỉ cho test).
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
// đi tới (x, y): bấm từng chặng ≤ 12×8 ô (trong khung nhìn), chờ tới hoặc hết giờ
const walkTo = async (page, x, y, ms = 25000) => {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const p = await self(page);
    if (!p) return false;
    if (p.x === x && p.y === y) return true;
    await clickAt(page, Math.max(p.x - 12, Math.min(p.x + 12, x)), Math.max(p.y - 8, Math.min(p.y + 8, y)));
    await page.waitForTimeout(900);
  }
  return false;
};

async function account(tag, level) {
  const user = `mp${tag}${stamp}`;
  const ip = `10.88.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
  const call = async (path, body, token) =>
    (
      await fetch(base + path, {
        method: "POST",
        headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify(body),
      })
    ).json();
  const { token } = await call("/register", { username: user, password: "matkhau123" });
  await call("/characters", { name: `${tag}${stamp}`, class: "DK" }, token);
  execSync(`mix run scripts/e2e_level.exs ${user} ${level}`, { env: { ...process.env, LANG: "C.UTF-8" } });
  return user;
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

// ---------- cấp 1: bị chặn ở cổng ----------
const low = await enter(await account("Lo", 1));
const npcs = await low.evaluate(() => window.__mu.entities().filter((e) => e.kind === "npc").map((e) => e.id).sort());
check("Lorencia có 2 NPC (Potion + Weapon Merchant)", npcs.join() === "npc_lorencia_potion_merchant,npc_lorencia_weapon_merchant", npcs.join());
await walkTo(low, 15, 9);
await clickAt(low, 15, 8);
const blocked = await until(low, () => document.querySelector('[data-tab="notices"] .badge') !== null, null, 4000);
await low.click('[data-tab="notices"]');
const noticeText = await low.textContent('[data-panel="notices"]').catch(() => "");
check("cấp 1 bước vào cổng → báo cần cấp 10, vẫn ở Lorencia", blocked && noticeText.includes("Cần cấp 10") && (await low.evaluate(() => window.__mu.map())) === "lorencia", noticeText.slice(0, 80));
await low.keyboard.press("Escape");

// Weapon Merchant bán đồ t0 cả 3 class
const wm = await low.evaluate(() => window.__mu.entities().find((e) => e.id === "npc_lorencia_weapon_merchant"));
await walkTo(low, wm.x + 1, wm.y);
await clickAt(low, wm.x, wm.y);
const shopOk = await low.waitForSelector('[data-panel="shop"]', { timeout: 5000 }).then(() => true).catch(() => false);
const buyables = await low.$$eval("[data-buy]", (bs) => bs.map((b) => b.dataset.buy)).catch(() => []);
check("Weapon Merchant Lorencia bán đồ t0 cả 3 class", shopOk && ["sword_t0", "staff_t0", "bow_t0", "pad_armor_t0", "vine_armor_t0"].every((t) => buyables.includes(t)), `${buyables.length} món`);
await low.screenshot({ path: `${shots}/p2-weapon-merchant.png` });

// ---------- cấp 10: sang Noria và quay về ----------
const hi = await enter(await account("Hi", 10));
await walkTo(hi, 15, 9);
await clickAt(hi, 15, 8);
const toNoria = await until(hi, () => window.__mu.map() === "noria", null, 8000);
const where = await hi.textContent('[data-test="where"]');
await until(hi, () => window.__mu.entities().filter((e) => e.kind === "npc").length === 2, null, 3000);
const noriaNpcs = await hi.evaluate(() => window.__mu.entities().filter((e) => e.kind === "npc").map((e) => e.id).sort());
check("cấp 10 bước vào cổng → sang Noria (HUD, NPC Noria), đứng cạnh cổng nam", toNoria && where.startsWith("Noria") && noriaNpcs.join() === "npc_noria_potion_merchant,npc_noria_weapon_merchant", `${where} · ${noriaNpcs.join(",")}`);
await hi.waitForTimeout(500);
await hi.screenshot({ path: `${shots}/p2-noria-town.png` });

// quái Noria có sprite: đi lên phía bắc nhìn vùng Goblin
await walkTo(hi, 31, 42, 15000);
await hi.waitForTimeout(800);
const mons = await hi.evaluate(() => [...new Set(window.__mu.entities().filter((e) => e.kind === "monster").map((e) => e.templateId))]);
const spritesOk = await hi.evaluate(async (ids) => {
  const ok = await Promise.all(ids.map((id) => new Promise((r) => { const i = new Image(); i.onload = () => r(i.naturalWidth > 0); i.onerror = () => r(false); i.src = `/assets/sprites/monsters/${id}.png`; })));
  return ok.every(Boolean);
}, mons);
check("thấy quái Noria, mọi sprite quái tải được", mons.length > 0 && mons.every((m) => ["goblin", "chain_scorpion", "beetle_monster", "hunter", "forest_monster", "agon", "stone_golem"].includes(m)) && spritesOk, mons.join(","));
await hi.screenshot({ path: `${shots}/p2-noria-field.png` });

// quay về Lorencia qua cổng nam (31,61)
await walkTo(hi, 31, 60, 25000);
await clickAt(hi, 31, 61);
const back = await until(hi, () => window.__mu.map() === "lorencia", null, 8000);
const pos = await self(hi);
check("cổng nam Noria → về Lorencia (15,9)", back && pos.x === 15 && pos.y === 9, `(${pos.x},${pos.y})`);

// reload: vẫn ở map đã lưu
await hi.reload();
await hi.click("text=Vào game");
await hi.waitForSelector('[data-test="where"]');
check("reload → vào lại đúng map đã lưu", (await hi.textContent('[data-test="where"]')).startsWith("Lorencia"));
check("không lỗi JS trên trang", errors.length === 0, errors.join(" | "));

await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} PASS`);
process.exit(failed.length ? 1 : 0);
