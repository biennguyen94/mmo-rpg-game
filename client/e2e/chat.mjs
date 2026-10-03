// P2-M5 qua trình duyệt thật: chat NORMAL giữa 2 người cùng map, WHISPER (/w Tên), chống XSS
// (thẻ HTML hiện như chữ), gõ chat không kích hoạt phím tắt, nhắn người offline báo lỗi, nút 💬 mobile.
//   node client/e2e/chat.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1 (mỗi tài khoản đăng ký từ một X-Forwarded-For riêng).
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

async function account(tag) {
  const user = `ch${tag}${stamp}`;
  const name = `${tag}${stamp}`;
  const ip = `10.99.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
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
const log = (page) => page.$$eval('[data-test="chat-log"] .line', (ls) => ls.map((l) => l.textContent));

const A = await account("Ca");
const B = await account("Cb");
const pa = await enter(A.user);
const pb = await enter(B.user);

// NORMAL + XSS: gõ thẻ HTML → hiện như chữ, không tạo phần tử
await pa.keyboard.press("Enter");
const opened = await pa.locator('[data-test="chat-input"]').isVisible();
await pa.keyboard.type("xin chào <img src=x onerror=alert(1)> qi");
const panelBefore = await pa.locator(".panel").count();
await pa.keyboard.press("Enter");
const got = await until(pb, (n) => [...document.querySelectorAll('[data-test="chat-log"] .line')].some((l) => l.textContent.startsWith(`${n}: xin chào`)), A.name);
const lineB = (await log(pb)).find((t) => t.startsWith(`${A.name}:`)) ?? "";
const injected = await pb.$$eval('[data-test="chat-log"] img', (xs) => xs.length);
check("Enter mở ô chat; gõ không kích hoạt phím tắt (q, i)", opened && panelBefore === 0 && (await pa.locator(".panel").count()) === 0);
check("NORMAL: người cùng map nhận tin; thẻ HTML hiện như chữ (chống XSS)", got && lineB.includes("<img src=x") && injected === 0, lineB);
check("ô chat đóng sau khi gửi", !(await pa.locator('[data-test="chat-input"]').isVisible()));

// WHISPER
await pa.keyboard.press("Enter");
await pa.keyboard.type(`/w ${B.name.toUpperCase()} bí mật nhé`);
await pa.keyboard.press("Enter");
const wB = await until(pb, (n) => [...document.querySelectorAll('[data-test="chat-log"] .line.whisper')].some((l) => l.textContent === `[Mật] ${n}: bí mật nhé`), A.name);
const wA = await until(pa, (n) => [...document.querySelectorAll('[data-test="chat-log"] .line.whisper')].some((l) => l.textContent === `[Mật → ${n}] bí mật nhé`), B.name);
check("WHISPER /w Tên (không phân biệt hoa thường): người nhận + bản sao người gửi", wB && wA);
await pb.screenshot({ path: `${shots}/p2-chat.png` });

// nhắn người không online
await pa.keyboard.press("Enter");
await pa.keyboard.type("/w KhongCo999 alo");
await pa.keyboard.press("Enter");
await pa.waitForTimeout(500);
await pa.click('[data-tab="notices"]');
const notice = await pa.textContent('[data-panel="notices"]');
check("nhắn người không online → báo trong panel Thông báo", notice.includes("KhongCo999"), notice.slice(0, 80));
await pa.keyboard.press("Escape");

// mobile: nút 💬 mở ô chat
const pm = await enter((await account("Cm")).user, { width: 360, height: 740 });
await pm.locator('[data-mobile="chat"]').tap();
const mOpen = await pm.locator('[data-test="chat-input"]').isVisible();
const noOverflow = await pm.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth);
check("mobile: nút 💬 mở ô chat, không tràn ngang", mOpen && noOverflow);
await pm.screenshot({ path: `${shots}/p2-chat-mobile.png` });
check("không lỗi JS trên trang", errors.length === 0, errors.join(" | "));

await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} PASS`);
process.exit(failed.length ? 1 : 0);
