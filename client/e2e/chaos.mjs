// P6-M3 / P6-M4 qua trình duyệt thật: Chaos Goblin ở Noria → cửa sổ CHAOS MACHINE; đặt kiếm +9 +
// Jewel of Chaos → server báo "Tạo cánh cấp 1 · tỉ lệ 35%"; [Kết hợp] → kết quả (thành công / thất
// bại), đồ đặt vào mất, Zen −20 000; mặc Wings of Satan vào ô cánh (đã mở) → spawn có `wing`,
// chỉ số có sát thương / hấp thụ.
//   node client/e2e/chaos.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1. Đồ đặt bằng scripts/e2e_chaos.exs (chỉ cho test).
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
const ip = `10.94.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
const user = `ch${stamp}`;
const call = async (path, body, token) =>
  (
    await fetch(base + path, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(body),
    })
  ).json();
const { token } = await call("/register", { username: user, password: "matkhau123" });
await call("/characters", { name: `Ch${stamp}`, class: "DK" }, token);
execSync(`mix run scripts/e2e_chaos.exs ${user}`, { env: { ...process.env, LANG: "C.UTF-8" } });

const browser = await chromium.launch({ executablePath: existsSync(exe) ? exe : undefined });
const errors = [];
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, extraHTTPHeaders: { "x-forwarded-for": ip } });
const page = await ctx.newPage();
page.on("pageerror", (e) => errors.push(String(e)));
await page.goto(base);
await page.fill('input[name="username"]', user);
await page.fill('input[name="password"]', "matkhau123");
await page.click('button[type="submit"]');
await page.click("text=Vào game");
await page.waitForSelector('[data-test="where"]');
await page.waitForFunction(() => window.__mu.entities().some((e) => e.id === window.__mu.selfId));

const self = () => page.evaluate(() => window.__mu.entities().find((e) => e.id === window.__mu.selfId));
const clickAt = async (x, y) => {
  const me = await self();
  const b = await page.locator('[data-test="game-canvas"]').boundingBox();
  await page.mouse.click(b.x + b.width / 2 + (x - me.x) * 32, b.y + b.height / 2 + (y - me.y) * 32);
};
const clickUntil = async (sel, done, tries = 5) => {
  for (let i = 0; i < tries; i++) {
    await page.click(sel, { timeout: 2000 }).catch(() => {});
    if (await until(page, done, null, 1500)) return true;
  }
  return false;
};
const bagId = (tid) => page.evaluate((t) => window.__mu.player().inventory.find((i) => i.templateId === t)?.id, tid);

check("vào Noria", (await page.evaluate(() => window.__mu.map())) === "noria");
const npc = await page.evaluate(() => window.__mu.entities().find((e) => e.id === "npc_noria_chaos_goblin"));
check("Chaos Goblin ở thị trấn Noria", npc?.name === "Chaos Goblin", npc ? `(${npc.x},${npc.y})` : "không thấy");
await clickAt(npc.x, npc.y);
check("bấm NPC → cửa sổ CHAOS MACHINE", await page.waitForSelector('[data-panel="chaos"]', { timeout: 8000 }).then(() => true).catch(() => false));

const sword = await bagId("sword_t0");
const chaos = await bagId("jewel_chaos");
await clickUntil(`[data-chaos-bag="${sword}"]`, () => document.querySelector("[data-chaos-in]") !== null);
await clickUntil(`[data-chaos-bag="${chaos}"]`, () => document.querySelectorAll("[data-chaos-in]").length === 2);
check(
  "kiếm +9 + Chaos → \"Tạo cánh cấp 1 · tỉ lệ 35%\"",
  await until(page, () => /Tạo cánh cấp 1.*35%/.test(document.querySelector('[data-test="chaos-recipe"]')?.textContent ?? ""), null, 4000),
  await page.textContent('[data-test="chaos-recipe"]').catch(() => ""),
);
await page.screenshot({ path: `${shots}/p6-chaos-machine.png` });
const zen0 = await page.evaluate(() => window.__mu.player().zen);
const combined = await clickUntil('[data-test="chaos-combine"]', () => document.querySelector('[data-test="chaos-result"]') !== null);
const res = await page.textContent('[data-test="chaos-result"]').catch(() => "");
check("[Kết hợp] → có kết quả", combined, res);
check("kiếm đã mất, Chaos còn 1, Zen −20 000", await until(page, (z) => {
  const inv = window.__mu.player().inventory;
  return !inv.some((i) => i.templateId === "sword_t0") && inv.find((i) => i.templateId === "jewel_chaos")?.quantity === 1 && window.__mu.player().zen === z - 20000;
}, zen0, 4000));

// mặc cánh (ô 7 mở): bấm cánh trong túi → [Trang bị]
await page.keyboard.press("Escape");
await page.click('[data-tab="inventory"]');
const wing = await bagId("wing_satan");
await page.click(`[data-panel="inventory"] [data-item="${wing}"]`).catch(() => {});
await clickUntil('.tooltip button:has-text("Trang bị")', () => window.__mu.player().equipment.some((e) => e.templateId === "wing_satan"));
check("mặc Wings of Satan vào ô cánh (ô 7 không khóa)", await until(page, () => window.__mu.player().equipment.some((e) => e.slot === 7 && e.templateId === "wing_satan"), null, 4000));
check("spawn của mình có wing = wing_satan (người khác thấy cánh)", await until(page, () => window.__mu.entities().find((e) => e.id === window.__mu.selfId)?.wing === "wing_satan", null, 4000));
await page.keyboard.press("Escape");
await page.screenshot({ path: `${shots}/p6-wings.png` });

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
