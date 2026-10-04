// P2-M6 qua trình duyệt thật: 📬 Hộp thư (badge, mail chào mừng, nhận quà, lọc, xóa đã đọc) và
// panel Bản đồ (minimap 256×256, vị trí, cổng, phím M).
//   node client/e2e/mail_map.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1; quà gửi bằng scripts/e2e_mail.exs (chỉ cho test).
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

async function account(tag) {
  const user = `ml${tag}${stamp}`;
  const name = `${tag}${stamp}`;
  const ip = `10.55.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
  const call = async (path, body, token) =>
    (
      await fetch(base + path, {
        method: "POST",
        headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify(body),
      })
    ).json();
  const { token } = await call("/register", { username: user, password: "matkhau123" });
  await call("/characters", { name }, token);
  return { user, name };
}

const browser = await chromium.launch({ executablePath: existsSync(exe) ? exe : undefined });
const errors = [];
async function enter(user, viewport = { width: 1280, height: 800 }) {
  const ctx = await browser.newContext({ viewport, hasTouch: viewport.width < 600 });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(base);
  await page.fill('input[name="username"]', user);
  await page.fill('input[name="password"]', "matkhau123");
  await page.click('button[type="submit"]');
  await page.click("text=Vào game");
  await page.waitForSelector('[data-test="where"]');
  return page;
}

const A = await account("Ma");
execSync(`mix run scripts/e2e_mail.exs ${A.name}`, { env: { ...process.env, LANG: "C.UTF-8" } });
const pa = await enter(A.user);

// badge: chào mừng + quà = 2 thư chưa đọc
const badge = await until(pa, () => document.querySelector('[data-test="mailbtn"] .badge')?.textContent === "2");
check("📬 trên HUD có badge 2 (thư chào mừng + quà)", badge, await pa.textContent('[data-test="mailbtn"]'));
await pa.click('[data-test="mailbtn"]');
const listed = await until(pa, () => document.querySelectorAll('[data-panel="mail"] [data-mail]').length === 2);
const text = await pa.textContent('[data-panel="mail"]');
const noBadge = (await pa.locator('[data-test="mailbtn"] .badge').count()) === 0;
check("mở Hộp thư: 2 thư (🎉 chào mừng, 🎁 quà), badge tắt", listed && text.includes("Chào mừng bạn đến MU Web") && text.includes("🎉") && text.includes("🎁") && noBadge);
await pa.click('[data-mail-filter="gift"]');
const giftOnly = (await pa.locator('[data-panel="mail"] [data-mail]').count()) === 1;
await pa.click('[data-mail-filter="unread"]');
const unreadAll = (await pa.locator('[data-panel="mail"] [data-mail]').count()) === 2;
await pa.click('[data-mail-filter="all"]');
check("lọc [Có quà] = 1, [Chưa đọc] = 2 (trạng thái lúc mở)", giftOnly && unreadAll);
await pa.screenshot({ path: `${shots}/p2-mail.png` });

const zen0 = (await player(pa)).zen;
await pa.click("[data-claim]");
const claimed = await until(pa, (z) => window.__mu.player().zen === z + 500 && window.__mu.player().view.potions.HP === 3, zen0);
const done = await until(pa, () => document.querySelector('[data-panel="mail"]')?.textContent.includes("✓ Đã nhận"));
check("[Nhận]: +500 Zen, +3 HP potion vào túi, hiện ✓ Đã nhận", claimed && done);
await pa.click('[data-test="mail-delete-read"]');
const emptied = await until(pa, () => document.querySelector('[data-panel="mail"]')?.textContent.includes("Không có thư"));
check("[Xóa đã đọc] xóa hết thư đã đọc / đã nhận", emptied);
await pa.click('[data-test="mailbtn"]');
check("bấm lại 📬 đóng panel", (await pa.locator('[data-panel="mail"]').count()) === 0);

// ---------- Bản đồ ----------
await pa.keyboard.press("m");
const mapOpen = await pa.locator('[data-panel="map"]').isVisible();
const size = await pa.$eval('[data-test="minimap"]', (c) => [c.width, c.height]);
const pos = await pa.textContent('[data-test="map-pos"]');
const me = await player(pa);
const active = await pa.getAttribute('[data-tab="map"]', "class");
const mapText = await pa.textContent('[data-panel="map"]');
check("phím M mở Bản đồ: minimap 256×256, vị trí đúng, tab 🗺️ sáng, có cổng Noria", mapOpen && size.join() === "256,256" && pos === `Vị trí: (${me.x}, ${me.y})` && active === "active" && mapText.includes("LORENCIA") && mapText.includes("Noria (cấp 10)"), pos);
await pa.screenshot({ path: `${shots}/p2-map.png` });
await pa.keyboard.press("Escape");
check("Esc đóng Bản đồ", (await pa.locator('[data-panel="map"]').count()) === 0);

// mobile: 5 tab, panel Bản đồ không tràn ngang
const pm = await enter((await account("Mm")).user, { width: 360, height: 740 });
const tabs = await pm.locator(".dock button").count();
await pm.locator('[data-tab="map"]').tap();
const fits = await pm.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth);
check("mobile: dock 5 tab, Bản đồ không tràn ngang ở 360px", tabs === 5 && fits && (await pm.locator('[data-panel="map"]').isVisible()));
await pm.screenshot({ path: `${shots}/p2-map-mobile.png` });
check("không lỗi JS trên trang", errors.length === 0, errors.join(" | "));

await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} PASS`);
process.exit(failed.length ? 1 : 0);
