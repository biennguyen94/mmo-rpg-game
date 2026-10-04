// P6-M5 qua trình duyệt thật: quản trị bật world boss (`mix mu.event start world_boss --node …`)
// → SYSTEM "Bull Fighter Lord bắt đầu…", thanh event đếm ngược, boss (tên đỏ, `boss: true`) ở
// bãi Lorencia; tắt → thanh event mất, boss biến mất. Golden Invasion bật / tắt → thanh event.
// Người vào giữa event vẫn thấy thanh event.
//   node client/e2e/events.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1 và chạy có tên node: elixir --sname mu -S mix phx.server
// (MU_NODE=mu@host để đổi).
import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { hostname } from "node:os";

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? "/opt/node-tools/node_modules/playwright/index.mjs");
const base = process.argv[2] ?? "http://localhost:4000";
const shots = process.argv[3] ?? "docs/screenshots";
const exe = process.env.CHROMIUM_PATH ?? "/opt/pw-browsers/chromium";
const node = process.env.MU_NODE ?? `mu@${hostname().split(".")[0]}`;
const results = [];
const check = (name, ok, extra = "") => {
  results.push({ name, ok, extra });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${extra ? "  — " + extra : ""}`);
};
const stamp = Date.now() % 1_000_000;
const until = (page, fn, arg, ms = 5000) =>
  page.waitForFunction(fn, arg, { timeout: ms }).then(() => true).catch(() => false);
const ip = `10.95.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
const event = (cmd, kind) => {
  try {
    execSync(`mix mu.event ${cmd} ${kind} --node ${node}`, { env: { ...process.env, LANG: "C.UTF-8" }, stdio: "pipe" });
    return true;
  } catch (e) {
    console.log(String(e.stderr ?? e).slice(0, 300));
    return false;
  }
};
const call = async (path, body, token) =>
  (
    await fetch(base + path, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(body),
    })
  ).json();

async function account(tag) {
  const user = `ev${tag}${stamp}`;
  const { token } = await call("/register", { username: user, password: "matkhau123" });
  await call("/characters", { name: `Ev${tag}${stamp}`, class: "DK" }, token);
  return user;
}

const browser = await chromium.launch({ executablePath: existsSync(exe) ? exe : undefined });
const errors = [];
async function enter(user) {
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
  return page;
}

// dọn event còn sót từ lần chạy trước
event("stop", "world_boss");
event("stop", "golden_invasion");

const A = await account("a");
const B = await account("b");
// góc đông nam thị trấn (vẫn trong safe zone): bãi boss (42..47, 46..49) nằm trong tầm nhìn
execSync(`mix run scripts/e2e_pos.exs ${A} lorencia 24 40`, { env: { ...process.env, LANG: "C.UTF-8" } });
const pa = await enter(A);

check("mix mu.event start world_boss", event("start", "world_boss"));
check(
  "SYSTEM \"Bull Fighter Lord bắt đầu ở Lorencia\"",
  await until(pa, () => document.querySelector('[data-test="chat-log"]')?.textContent.includes("Bull Fighter Lord bắt đầu ở Lorencia"), null, 5000),
);
check(
  "thanh event: \"⚔ Bull Fighter Lord — Lorencia · còn 19:xx\"",
  await until(pa, () => /Bull Fighter Lord — Lorencia · còn (19:\d\d|20:00)/.test(document.querySelector('[data-test="world-event"]')?.textContent ?? ""), null, 5000),
  await pa.textContent('[data-test="world-event"]').catch(() => ""),
);
check(
  "boss Bull Fighter Lord có trên map (boss: true, HP 20 000)",
  await until(pa, () => window.__mu.entities().some((e) => e.kind === "monster" && e.boss && e.name === "Bull Fighter Lord" && e.maxHp === 20000), null, 5000),
);
await pa.screenshot({ path: `${shots}/p6-world-boss.png` });

// người vào giữa event vẫn thấy thanh event
const pb = await enter(B);
check("người vào sau vẫn thấy thanh event", await until(pb, () => document.querySelector('[data-test="world-event"]')?.textContent.includes("Bull Fighter Lord"), null, 5000));

check("mix mu.event stop world_boss", event("stop", "world_boss"));
check("tắt: thanh event mất, boss biến mất", await until(pa, () => !document.querySelector('[data-test="world-event"]') && !window.__mu.entities().some((e) => e.boss), null, 5000));

check("mix mu.event start golden_invasion", event("start", "golden_invasion"));
check(
  "Golden Invasion: thanh event \"Lorencia, Noria\" + SYSTEM",
  await until(pa, () => document.querySelector('[data-test="world-event"]')?.textContent.includes("Golden Invasion — Lorencia, Noria") && document.querySelector('[data-test="chat-log"]')?.textContent.includes("Golden Invasion bắt đầu"), null, 5000),
);
check("mix mu.event stop golden_invasion", event("stop", "golden_invasion"));
check("Golden Invasion kết thúc: thanh event mất", await until(pa, () => !document.querySelector('[data-test="world-event"]'), null, 5000));

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
