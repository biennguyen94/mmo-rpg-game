// P3-M4 qua trình duyệt thật: bấm người chơi → [Mời vào nhóm] → hộp lời mời [Đồng ý] / [Từ chối],
// khung nhóm (★ trưởng nhóm, class, cấp, thanh HP), chat /p chỉ trong nhóm, từ chối báo người
// mời, đuổi (✕) → nhóm giải tán, rời nhóm, mất kết nối hiện "Mất kết nối".
//   node client/e2e/party.mjs [baseUrl] [thư_mục_ảnh]
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
const self = (page) => page.evaluate(() => window.__mu.entities().find((e) => e.id === window.__mu.selfId));
const clickAt = async (page, x, y) => {
  const me = await self(page);
  const b = await page.locator('[data-test="game-canvas"]').boundingBox();
  await page.mouse.click(b.x + b.width / 2 + (x - me.x) * 32, b.y + b.height / 2 + (y - me.y) * 32);
};

async function account(tag) {
  const user = `pt${tag}${stamp}`;
  const name = `${tag}${stamp}`;
  const ip = `10.96.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
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
// `page` đứng ở (x, y)
const stand = async (page, x, y) => {
  await clickAt(page, x, y);
  return until(page, ([x, y]) => window.__mu.player().x === x && window.__mu.player().y === y, [x, y], 6000);
};
// `page` bấm vào người chơi tên `name` → menu → [Mời vào nhóm]
async function invite(page, name) {
  const t = await page.evaluate((n) => window.__mu.entities().find((e) => e.name === n), name);
  if (!t) return false;
  await clickAt(page, t.x, t.y);
  const ok = await page.waitForSelector('[data-test="party-invite"]', { timeout: 3000 }).then(() => true).catch(() => false);
  if (ok) await page.click('[data-test="party-invite"]');
  return ok;
}
const members = (page) => page.$$eval("[data-member]", (ms) => ms.map((m) => m.dataset.member)).catch(() => []);
const chatText = (page) => page.$$eval('[data-test="chat-log"] .line', (ls) => ls.map((l) => l.textContent)).catch(() => []);
async function say(page, text) {
  await page.keyboard.press("Enter");
  await page.keyboard.type(text);
  await page.keyboard.press("Enter");
}

const A = await account("Pa");
const B = await account("Pb");
const C = await account("Pc");
const pa = await enter(A.user);
const pb = await enter(B.user);
const pc = await enter(C.user);
// đứng tách nhau trong thị trấn để bấm trúng
await stand(pa, 15, 33);
await stand(pb, 18, 33);
await stand(pc, 21, 33);
await pa.waitForTimeout(400);

// ---------- mời → đồng ý ----------
check("bấm người chơi → menu có [Mời vào nhóm]", await invite(pa, B.name));
const asked = await until(pb, (n) => document.querySelector('[data-test="party-ask"]')?.textContent.includes(n), A.name, 4000);
check("người được mời thấy hộp \"… mời bạn vào nhóm\" có đếm ngược", asked, asked ? await pb.textContent('[data-test="party-ask"]') : "");
await pb.screenshot({ path: `${shots}/p3-party-invite.png` });
await pb.click('[data-test="party-accept"]');
const formed = await until(pa, (n) => [...document.querySelectorAll("[data-member]")].map((m) => m.dataset.member).includes(n), B.name, 4000);
const frameA = await pa.textContent('[data-test="party"]').catch(() => "");
check("đồng ý → khung nhóm 2 người, ★ trưởng nhóm, class + cấp", formed && (await members(pb)).length === 2 && frameA.includes(`★ ${A.name}`) && frameA.includes("DK Lv1"), frameA);
check("thanh HP thành viên", (await pa.locator('[data-test="party"] .bar.hp .fill').count()) === 2);
await pa.screenshot({ path: `${shots}/p3-party-frame.png` });

// ---------- chat /p ----------
await say(pb, "/p đi săn thôi");
const gotA = await until(pa, () => [...document.querySelectorAll('[data-test="chat-log"] .line')].some((l) => l.textContent.includes("[Nhóm]") && l.textContent.includes("đi săn thôi")), null, 4000);
await pc.waitForTimeout(300);
check("chat /p: thành viên nhận [Nhóm], người ngoài không", gotA && !(await chatText(pc)).some((t) => t.includes("đi săn thôi")));

// ---------- từ chối ----------
check("trưởng nhóm mời C", await invite(pa, C.name));
await until(pc, () => document.querySelector('[data-test="party-ask"]') !== null, null, 4000);
await pc.click('[data-test="party-decline"]');
const declined = await until(pa, (n) => [...document.querySelectorAll('[data-test="chat-log"] .line')].some((l) => l.textContent.includes(`${n} từ chối`)), C.name, 4000);
check("C từ chối → A nhận thông báo, hộp lời mời của C đóng", declined && !(await pc.$('[data-test="party-ask"]')));

// thành viên thường không mời được (menu không có [Mời vào nhóm])
const tC = await pb.evaluate((n) => window.__mu.entities().find((e) => e.name === n), C.name);
await clickAt(pb, tC.x, tC.y);
await pb.waitForTimeout(500);
check("thành viên thường: menu không có [Mời vào nhóm]", !(await pb.$('[data-test="party-invite"]')));
await pb.keyboard.press("Escape");
// không có menu thì bấm người chơi = đi tới chỗ họ: đưa B về chỗ cũ để bấm trúng
await stand(pb, 18, 33);

// ---------- đuổi → còn 1 người → giải tán ----------
await pa.click(`[data-kick="${B.name}"]`);
const kicked = await until(pb, () => !document.querySelector('[data-test="party"]'), null, 4000);
const goneA = await until(pa, () => !document.querySelector('[data-test="party"]'), null, 4000);
check("trưởng nhóm bấm ✕ → B ra khỏi nhóm, nhóm 1 người giải tán", kicked && goneA);

// ---------- lập lại, mất kết nối, rời nhóm ----------
await invite(pa, B.name);
await until(pb, () => document.querySelector('[data-test="party-ask"]') !== null, null, 4000);
await pb.click('[data-test="party-accept"]');
await invite(pa, C.name);
await until(pc, () => document.querySelector('[data-test="party-ask"]') !== null, null, 4000);
await pc.click('[data-test="party-accept"]');
check("nhóm 3 người", await until(pa, () => document.querySelectorAll("[data-member]").length === 3, null, 4000));
await pc.context().close();
const off = await until(pa, (n) => document.querySelector(`[data-member="${n}"]`)?.textContent.includes("Mất kết nối"), C.name, 5000);
check("C đóng tab → khung nhóm hiện \"Mất kết nối\" (vẫn trong nhóm trong hạn reconnect)", off);
await pb.click('[data-test="party-leave"]');
const left = await until(pa, (n) => !document.querySelector(`[data-member="${n}"]`), B.name, 4000);
const leftB = await until(pb, () => !document.querySelector('[data-test="party"]'), null, 4000);
check("B bấm [Rời nhóm] → biến khỏi khung của A, khung của B đóng", left && leftB, JSON.stringify(await members(pa)));

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
