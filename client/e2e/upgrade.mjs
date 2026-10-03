// P5-M2 qua trình duyệt thật: kéo Jewel of Bless thả lên kiếm trong túi → +1 (nhãn +1, tooltip
// "Short Sword +1", chỉ số tăng, thông báo), [Ép lên…] rồi bấm đồ (cách của mobile) → +2, Soul lên
// mũ +6 → +7 (SYSTEM cả map) hoặc +5, Life → option, dùng sai jewel → báo lỗi, không mất jewel.
//   node client/e2e/upgrade.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1. Đồ + jewel đặt bằng scripts/e2e_upgrade.exs (chỉ cho test).
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

const user = `up${stamp}`;
const call = async (path, body, token) =>
  (
    await fetch(base + path, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(body),
    })
  ).json();
const { token } = await call("/register", { username: user, password: "matkhau123" });
await call("/characters", { name: `Up${stamp}`, class: "DK" }, token);
execSync(`mix run scripts/e2e_upgrade.exs ${user}`, { env: { ...process.env, LANG: "C.UTF-8" } });

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

const inv = () => page.evaluate(() => window.__mu.player().inventory);
const byTpl = async (tid) => (await inv()).find((i) => i.templateId === tid);
const notices = async () => {
  await page.click('[data-tab="notices"]');
  const t = await page.textContent('[data-panel="notices"]').catch(() => "");
  await page.keyboard.press("Escape");
  return t;
};
const openBag = async () => {
  if (!(await page.$('[data-panel="inventory"]'))) await page.click('[data-tab="inventory"]');
  await page.waitForSelector('[data-test="bag"]');
};

// ---------- kéo Bless thả lên kiếm ----------
await openBag();
let sword = await byTpl("sword_t0");
let bless = await byTpl("jewel_bless");
await page.click(`[data-item="${sword.id}"]`);
const desc0 = await page.textContent('[data-test="tooltip"]');
await page.keyboard.press("Escape");
await openBag();
await page.dragAndDrop(`[data-item="${bless.id}"]`, `[data-item="${sword.id}"]`);
const up1 = await until(page, (id) => window.__mu.player().inventory.find((i) => i.id === id)?.level === 1, sword.id, 5000);
check("kéo Bless thả lên kiếm → kiếm +1, Bless còn 4", up1 && (await byTpl("jewel_bless")).quantity === 4);
check("ô túi hiện nhãn +1", (await page.textContent(`[data-item="${sword.id}"] .lvl`).catch(() => "")) === "+1");
await page.click(`[data-item="${sword.id}"]`);
const tip1 = await page.textContent('[data-test="tooltip"]');
check("tooltip \"Short Sword +1\", chỉ số tấn công tăng 3", tip1.includes("Short Sword +1") && tip1 !== desc0, tip1.slice(0, 80));
await page.keyboard.press("Escape");
await page.screenshot({ path: `${shots}/p5-upgrade-bag.png` });

// ---------- [Ép lên…] rồi bấm đồ ----------
await openBag();
bless = await byTpl("jewel_bless");
await page.click(`[data-item="${bless.id}"]`);
await page.click('[data-test="jewel-aim"]');
check("[Ép lên…] hiện dòng \"Chọn đồ để ép …\"", await until(page, () => document.querySelector('[data-test="jewel-aim-bar"]') !== null, null, 2000));
await page.click(`[data-item="${sword.id}"]`);
check("bấm kiếm → +2", await until(page, (id) => window.__mu.player().inventory.find((i) => i.id === id)?.level === 2, sword.id, 5000));

// ---------- sai loại jewel ----------
const soul = await byTpl("jewel_soul");
await openBag();
await page.dragAndDrop(`[data-item="${soul.id}"]`, `[data-item="${sword.id}"]`);
await page.waitForTimeout(600);
check("Soul lên kiếm +2 → bị từ chối, không mất Soul, kiếm vẫn +2", (await byTpl("jewel_soul")).quantity === 3 && (await byTpl("sword_t0")).level === 2);

// ---------- Soul lên mũ +6 ----------
const helm = await byTpl("helm_t0");
await openBag();
await page.dragAndDrop(`[data-item="${soul.id}"]`, `[data-item="${helm.id}"]`);
const done = await until(page, (id) => [5, 7].includes(window.__mu.player().inventory.find((i) => i.id === id)?.level), helm.id, 5000);
const lv = (await byTpl("helm_t0")).level;
const chat = await page.$$eval('[data-test="chat-log"] .line', (ls) => ls.map((l) => l.textContent).join("|")).catch(() => "");
check("Soul lên mũ +6 → +7 (SYSTEM cả map) hoặc +5", done && (lv === 5 || chat.includes("ép thành công Leather Helm +7")), `mũ +${lv}`);
const note = await notices();
check("thông báo kết quả ép", note.includes("Ép thành công") || note.includes("Ép thất bại"));

// ---------- Life → option ----------
const life = await byTpl("jewel_life");
let opt = 0;
for (let k = 0; k < 8 && opt === 0; k++) {
  await openBag();
  const l = await byTpl("jewel_life");
  if (!l) break;
  await page.dragAndDrop(`[data-item="${l.id}"]`, `[data-item="${helm.id}"]`);
  await page.waitForTimeout(500);
  opt = (await byTpl("helm_t0")).optionLevel ?? 0;
}
await openBag();
await page.click(`[data-item="${helm.id}"]`);
const tipH = await page.textContent('[data-test="tooltip"]').catch(() => "");
check("Life → mũ có option, tooltip \"Option Life +4 thủ\"", opt >= 1 && tipH.includes("Option Life +4 thủ"), `life ban đầu ${life?.quantity}`);
await page.screenshot({ path: `${shots}/p5-upgrade-option.png` });
await page.keyboard.press("Escape");

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
