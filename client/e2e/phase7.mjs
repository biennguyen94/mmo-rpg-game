// P7-M2 / P7-M3 qua trình duyệt thật: kéo Jewel of Chaos thả lên kiếm +9 → +10 (50 %) hoặc mất
// kiếm; Chaos Goblin: cánh cấp 1 +7 + 5 Bless + 5 Soul + 2 Chaos → "Tạo cánh cấp 2 · tỉ lệ 30%" →
// [Kết hợp] → Zen −200 000, cánh cũ mất; thành công thì ra Wings of Dragon (DK), mặc vào ô cánh.
//   node client/e2e/phase7.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1. Đồ đặt bằng scripts/e2e_phase7.exs (chỉ cho test).
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
const ip = `10.96.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
const user = `p7${stamp}`;
const call = async (path, body, token) =>
  (
    await fetch(base + path, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(body),
    })
  ).json();
const { token } = await call("/register", { username: user, password: "matkhau123" });
await call("/characters", { name: `Pz${stamp}`, class: "DK" }, token);
execSync(`mix run scripts/e2e_phase7.exs ${user}`, { env: { ...process.env, LANG: "C.UTF-8" } });

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

const inv = () => page.evaluate(() => window.__mu.player().inventory);
const bagId = (tid) => page.evaluate((t) => window.__mu.player().inventory.find((i) => i.templateId === t)?.id, tid);
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

// ---- P7-M2: +9 → +10 bằng Jewel of Chaos ----
const sword = await bagId("sword_t0");
const chaos = await bagId("jewel_chaos");
await page.click('[data-tab="inventory"]');
await page.waitForSelector(`[data-item="${sword}"]`);
check("kiếm hiện nhãn +9", (await page.textContent(`[data-item="${sword}"] .lvl`).catch(() => "")) === "+9");
await page.dragAndDrop(`[data-item="${chaos}"]`, `[data-item="${sword}"]`);
const done = await until(page, (sid) => {
  const s = window.__mu.player().inventory.find((i) => i.id === sid);
  return !s || s.level === 10;
}, sword, 5000);
const after = (await inv()).find((i) => i.id === sword);
check("thả Chaos lên kiếm +9 → +10 hoặc mất kiếm (50 %)", done, after ? `+${after.level}` : "mất kiếm");
check("Chaos còn 3", (await inv()).find((i) => i.templateId === "jewel_chaos")?.quantity === 3);
await page.click('[data-tab="notices"]');
check(
  "thông báo kết quả ép",
  await until(page, () => /Ép thành công: .*\+10|Ép thất bại: .*bị hỏng/.test(document.body.textContent), null, 3000),
);
if (after) {
  await page.click('[data-tab="inventory"]');
  await page.click(`[data-item="${sword}"]`);
  // +10 gấp đôi: 3 + 7 đòn gốc của Short Sword + 33 (9 × 3 + 2 × 3)
  check("tooltip +10 tính chỉ số gấp đôi", await until(page, () => document.querySelector('[data-test="tooltip"]')?.textContent.includes("Tấn công +"), null, 2000), await page.textContent('[data-test="tooltip"]').catch(() => ""));
  await page.keyboard.press("Escape");
}
await page.keyboard.press("Escape");

// ---- P7-M3: cánh cấp 2 ----
const npc = await page.evaluate(() => window.__mu.entities().find((e) => e.id === "npc_noria_chaos_goblin"));
await clickAt(npc.x, npc.y);
check("bấm Chaos Goblin → CHAOS MACHINE", await page.waitForSelector('[data-panel="chaos"]', { timeout: 8000 }).then(() => true).catch(() => false));
for (const tid of ["wing_satan", "jewel_bless", "jewel_soul", "jewel_chaos"]) {
  const id = await bagId(tid);
  await clickUntil(`[data-chaos-bag="${id}"]`, (x) => document.querySelector(`[data-chaos-in]`) !== null);
}
check(
  "cánh +7 + 5 Bless + 5 Soul + Chaos → \"Tạo cánh cấp 2 · tỉ lệ 30%\"",
  await until(page, () => /Tạo cánh cấp 2.*30%/.test(document.querySelector('[data-test="chaos-recipe"]')?.textContent ?? ""), null, 4000),
  await page.textContent('[data-test="chaos-recipe"]').catch(() => ""),
);
await page.screenshot({ path: `${shots}/p7-chaos-wings2.png` });
const zen0 = await page.evaluate(() => window.__mu.player().zen);
check("[Kết hợp] → có kết quả", await clickUntil('[data-test="chaos-combine"]', () => document.querySelector('[data-test="chaos-result"]') !== null));
check("Zen −200 000, cánh cấp 1 mất, Chaos còn 1", await until(page, (z) => {
  const p = window.__mu.player();
  return p.zen === z - 200000 && !p.inventory.some((i) => i.templateId === "wing_satan") && p.inventory.find((i) => i.templateId === "jewel_chaos")?.quantity === 1;
}, zen0, 4000));
const made = (await inv()).filter((i) => i.templateId.startsWith("wing_")).map((i) => i.templateId);
check("thành công → Wings of Dragon (đúng class DK); thất bại → không có cánh", made.length === 0 || (made.length === 1 && made[0] === "wing_dragon"), made.join(",") || "thất bại (70 %)");
if (made.length) {
  await page.keyboard.press("Escape");
  await page.click('[data-tab="inventory"]');
  const w = await bagId("wing_dragon");
  await page.click(`[data-panel="inventory"] [data-item="${w}"]`).catch(() => {});
  await clickUntil('.tooltip button:has-text("Trang bị")', () => window.__mu.player().equipment.some((e) => e.templateId === "wing_dragon"));
  check("mặc Wings of Dragon, spawn có wing", await until(page, () => window.__mu.entities().find((e) => e.id === window.__mu.selfId)?.wing === "wing_dragon", null, 4000));
  await page.keyboard.press("Escape");
  await page.screenshot({ path: `${shots}/p7-wings2.png` });
}

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
