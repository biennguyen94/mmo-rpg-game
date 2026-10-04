// P3-M5 qua trình duyệt thật: nhiều nhân vật (tối đa 4) + Magic Gladiator.
// Tạo DK → MG bị khóa (🔒 cần cấp 20) → DK lên cấp 20 → tạo MG (26 mỗi stat, HP 188, MP 112,
// cầm sword_t0, sprite riêng, panel có "Dmg phép", menu quái có Energy Ball + Falling Slash khi đủ
// cấp) → [Đổi nhân vật] về danh sách → vào lại DK → tạo đủ 4 nhân vật thì hết nút tạo.
//   node client/e2e/mg.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1. Cấp nhân vật đặt bằng scripts/e2e_level.exs (chỉ cho test).
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

const user = `mg${stamp}`;
const ip = `10.95.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
await fetch(base + "/register", {
  method: "POST",
  headers: { "content-type": "application/json", "x-forwarded-for": ip },
  body: JSON.stringify({ username: user, password: "matkhau123" }),
});

const browser = await chromium.launch({ executablePath: existsSync(exe) ? exe : undefined });
const errors = [];
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const page = await ctx.newPage();
page.on("pageerror", (e) => errors.push(String(e)));
await page.goto(base);
await page.fill('input[name="username"]', user);
await page.fill('input[name="password"]', "matkhau123");
await page.click('button[type="submit"]');

async function create(name, cls) {
  await page.waitForSelector('[data-test="class-picker"]');
  await page.click(`.classopt:has(input[value="${cls}"])`);
  await page.fill('input[name="name"]', name);
  await page.click('button[type="submit"]');
  await page.waitForSelector('[data-test="where"]', { timeout: 8000 });
  await page.waitForFunction(() => window.__mu.entities().some((e) => e.id === window.__mu.selfId));
}
async function toList() {
  await page.click('[data-tab="menu"]');
  await page.click('[data-test="switch-character"]');
  await page.waitForSelector('[data-test="character-list"]', { timeout: 5000 });
}

// ---------- tài khoản mới: form tạo, MG khóa ----------
await page.waitForSelector('[data-test="class-picker"]');
const mgOpt = await page.$eval('input[name="class"][value="MG"]', (i) => ({ disabled: i.disabled, hint: i.closest("label").textContent })).catch(() => null);
check("tài khoản mới: MG có trong danh sách nhưng khóa (🔒 cần nhân vật cấp 20)", mgOpt?.disabled === true && mgOpt.hint.includes("cấp 20"), mgOpt?.hint);
await page.screenshot({ path: `${shots}/p3-create-mg-locked.png` });
await create(`Dk${stamp}`, "DK");
check("tạo DK → vào game", (await page.evaluate(() => window.__mu.player().class)) === "DK");

// ---------- đổi nhân vật → danh sách 1/4 ----------
await toList();
const rows1 = await page.$$eval("[data-character]", (rs) => rs.map((r) => r.textContent));
const listText = await page.textContent('[data-test="character-list"]');
check("[Đổi nhân vật] → danh sách: 1 nhân vật (class, cấp, map), 1/4, có [+ Tạo nhân vật]", rows1.length === 1 && rows1[0].includes("DK · Cấp 1 · Lorencia") && listText.includes("1/4") && !!(await page.$('[data-test="new-character"]')), rows1.join(" | "));

// DK lên cấp 20 → MG mở
execSync(`mix run scripts/e2e_level.exs ${user} 20`, { env: { ...process.env, LANG: "C.UTF-8" } });
await page.reload();
await page.waitForSelector('[data-test="character-list"]');
await page.click('[data-test="new-character"]');
await page.waitForSelector('[data-test="class-picker"]');
check("có nhân vật cấp 20 → MG mở", (await page.$eval('input[name="class"][value="MG"]', (i) => i.disabled)) === false);

// ---------- tạo MG ----------
await create(`Mg${stamp}`, "MG");
const p = await page.evaluate(() => window.__mu.player());
check(
  "MG cấp 1: 26 mỗi stat, HP 188, MP 112, cầm sword_t0",
  p.class === "MG" && p.level === 1 && [p.strength, p.agility, p.vitality, p.energy].every((v) => v === 26) && p.view.hpMax === 188 && p.view.mpMax === 112 && p.equipment.some((e) => e.templateId === "sword_t0" && e.slot === 5),
  `${p.class} HP ${p.view.hpMax} MP ${p.view.mpMax}`,
);
check("MG có Energy Ball (DW) từ cấp 1, chưa có Falling Slash (DK, cấp 5)", p.view.skills.includes("energy_ball") && !p.view.skills.includes("falling_slash"), p.view.skills.join(","));
const spriteOk = await page.evaluate(() => new Promise((r) => { const i = new Image(); i.onload = () => r(i.naturalWidth > 0); i.onerror = () => r(false); i.src = "/assets/sprites/characters/mg/body.png"; }));
check("sprite MG tải được", spriteOk);
await page.click('[data-tab="character"]');
const sheet = await page.textContent('[data-panel="character"]');
check("panel Nhân vật MG có \"Dmg phép\" và \"Tốc độ phép\"", sheet.includes("Dmg phép") && sheet.includes("Tốc độ phép"), sheet.replace(/\s+/g, " ").slice(0, 160));
await page.screenshot({ path: `${shots}/p3-mg-character.png` });
await page.keyboard.press("Escape");

// ---------- quay lại DK ----------
await toList();
const rows2 = await page.$$eval("[data-character]", (rs) => rs.map((r) => r.dataset.character));
check("danh sách 2 nhân vật theo thứ tự tạo", rows2.join() === `Dk${stamp},Mg${stamp}`, rows2.join());
await page.click(`[data-enter="Dk${stamp}"]`);
await page.waitForSelector('[data-test="where"]');
await until(page, (n) => window.__mu.player()?.name === n, `Dk${stamp}`);
const dk = await page.evaluate(() => window.__mu.player());
check("vào lại DK (cấp 20, giữ nguyên)", dk.name === `Dk${stamp}` && dk.class === "DK" && dk.level === 20);

// ---------- đủ 4 nhân vật ----------
await toList();
for (const [i, cls] of [["Dw", "DW"], ["El", "ELF"]]) {
  await page.click('[data-test="new-character"]');
  await create(`${i}${stamp}`, cls);
  await toList();
}
const rows4 = await page.$$eval("[data-character]", (rs) => rs.length);
const full = await page.textContent('[data-test="character-list"]');
check("4/4 nhân vật → không còn nút [+ Tạo nhân vật]", rows4 === 4 && full.includes("4/4") && !(await page.$('[data-test="new-character"]')));
await page.screenshot({ path: `${shots}/p3-character-list.png` });

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
