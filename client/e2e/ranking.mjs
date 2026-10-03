// P6-M1 qua trình duyệt thật: Menu → [🏆 Xếp hạng] → bảng "Tất cả" có mình + hạng của mình; tab
// DK chỉ có DK; tab Guild hiện "chưa có guild"; nhân vật cấp cao (seed) đứng trên.
//   node client/e2e/ranking.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1. Cấp đặt bằng scripts/e2e_level.exs (chỉ cho test).
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
const ip = `10.92.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
const user = `rk${stamp}`;
const name = `Rk${stamp}`;
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
// cấp tối đa: đứng đầu bảng (cùng cấp: tạo trước đứng trên, nên chỉ kiểm có mặt + hạng)
execSync(`mix run scripts/e2e_level.exs ${user} 30`, { env: { ...process.env, LANG: "C.UTF-8" } });

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

await page.click('[data-tab="menu"]');
await page.click('[data-test="ranking-menu"]');
check("Menu → [🏆 Xếp hạng] mở bảng", await until(page, () => document.querySelector('[data-test="ranking-table"]') !== null, null, 5000));
const me = await page.textContent('[data-test="ranking-me"]').catch(() => "");
check("có dòng \"Hạng của bạn: #…\"", /Hạng của bạn: #\d+/.test(me), me);
const row = await page.$(`[data-rank-row="${name}"]`);
check("nhân vật cấp 30 có trong top, tô vàng", !!row && (await row.getAttribute("class")) === "me");
await page.click('[data-board="level_DW"]');
check("tab DW: chỉ có DW, mình (DK) không có hạng", await until(page, () => [...document.querySelectorAll('[data-test="ranking-table"] tr td:nth-child(3)')].every((td) => td.textContent === "DW") && document.querySelector('[data-test="ranking-me"]')?.textContent.includes("không có trong bảng"), null, 4000));
await page.click('[data-board="guild"]');
check("tab Guild: \"Bạn chưa có guild\"", await until(page, () => document.querySelector('[data-test="ranking-me"]')?.textContent.includes("chưa có guild"), null, 4000));
await page.screenshot({ path: `${shots}/p6-ranking.png` });

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
