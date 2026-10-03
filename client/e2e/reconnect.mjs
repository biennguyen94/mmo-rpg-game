// P3-M2 qua trình duyệt thật (KB_TECHNICAL §4): mất kết nối → nhân vật ở lại map (người khác vẫn
// thấy), client tự nối lại → "Đã kết nối lại", vị trí giữ nguyên; đăng xuất → rời map ngay;
// đóng tab không quay lại → rời map sau reconnectGraceSeconds (30 s).
//   node client/e2e/reconnect.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1 (mỗi tài khoản đăng ký từ một X-Forwarded-For riêng).
// Mất mạng giả lập: đóng WebSocket từ trình duyệt (Phoenix báo lỗi kênh như rớt mạng) và chặn
// `/ws-ticket` một lúc để client chưa nối lại được.
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
  const user = `rc${tag}${stamp}`;
  const name = `${tag}${stamp}`;
  const ip = `10.98.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
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
async function enter(user) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => errors.push(String(e)));
  // giữ tham chiếu WebSocket để test đóng được (giả lập rớt mạng)
  await page.addInitScript(() => {
    const W = window.WebSocket;
    window.__sockets = [];
    window.WebSocket = class extends W {
      constructor(...a) {
        super(...a);
        window.__sockets.push(this);
      }
    };
  });
  await page.goto(base);
  await page.fill('input[name="username"]', user);
  await page.fill('input[name="password"]', "matkhau123");
  await page.click('button[type="submit"]');
  await page.click("text=Vào game");
  await page.waitForSelector('[data-test="where"]');
  await page.waitForFunction(() => window.__mu.entities().some((e) => e.id === window.__mu.selfId));
  return page;
}
const self = (page) => page.evaluate(() => window.__mu.entities().find((e) => e.id === window.__mu.selfId));
const sees = (page, name) => page.evaluate((n) => window.__mu.entities().some((e) => e.kind === "player" && e.name === n), name);
const dropNet = async (page) => {
  await page.route("**/ws-ticket", (r) => r.abort());
  await page.evaluate(() => window.__sockets.forEach((s) => s.close()));
};

const A = await account("Ra");
const B = await account("Rb");
const C = await account("Rc");
const pa = await enter(A.user);
const pb = await enter(B.user);

// A đi vài bước (ô trống trong thị trấn)
const start = await self(pa);
const box = await pa.locator('[data-test="game-canvas"]').boundingBox();
await pa.mouse.click(box.x + box.width / 2 + 3 * 32, box.y + box.height / 2);
await until(pa, ([x]) => window.__mu.player().x === x, [start.x + 3], 6000);
await pa.waitForTimeout(400);
const before = await self(pa);
check("B thấy A trước khi mất mạng", await until(pb, (n) => window.__mu.entities().some((e) => e.name === n), A.name, 4000));

// ---------- mất kết nối ----------
await dropNet(pa);
const banner = await until(pa, () => document.querySelector(".netbar")?.textContent.includes("Mất kết nối"), null, 3000);
check("A mất mạng → thanh \"Mất kết nối, đang kết nối lại…\"", banner);
await pa.screenshot({ path: `${shots}/p3-reconnect-lost.png` });
await pb.waitForTimeout(5000);
check("5 s sau B vẫn thấy A trên map (server giữ nhân vật)", await sees(pb, A.name));

// mạng trở lại → tự nối lại, giữ vị trí
await pa.unroute("**/ws-ticket");
const back = await until(pa, () => !document.querySelector(".netbar") && window.__mu.entities().some((e) => e.id === window.__mu.selfId), null, 25000);
const after = await self(pa);
check("nối lại tự động, vị trí giữ nguyên", back && after.x === before.x && after.y === before.y, `(${before.x},${before.y}) → (${after?.x},${after?.y})`);
await pa.click('[data-tab="notices"]');
const notices = await pa.textContent('[data-panel="notices"]').catch(() => "");
check("thông báo \"Đã kết nối lại.\"", notices.includes("Đã kết nối lại."));
await pa.keyboard.press("Escape");

check("B vẫn thấy A sau khi A nối lại", await sees(pb, A.name));

// ---------- đăng xuất: rời map ngay ----------
await pa.click('[data-tab="menu"]');
await pa.click("text=🚪 Đăng xuất");
const t0 = Date.now();
const gone = await until(pb, (n) => !window.__mu.entities().some((e) => e.name === n), A.name, 4000);
check("đăng xuất → B thấy A biến mất ngay (không chờ 30 s)", gone, `${Date.now() - t0} ms`);

// ---------- đóng tab không quay lại: rời map sau 30 s ----------
const pc = await enter(C.user);
check("B thấy C vào", await until(pb, (n) => window.__mu.entities().some((e) => e.name === n), C.name, 4000));
await pc.context().close();
const t1 = Date.now();
await pb.waitForTimeout(10000);
check("đóng tab: 10 s sau C vẫn trên map", await sees(pb, C.name));
const left = await until(pb, (n) => !window.__mu.entities().some((e) => e.name === n), C.name, 30000);
const secs = (Date.now() - t1) / 1000;
check("đóng tab: C rời map sau khoảng reconnectGraceSeconds (30 s)", left && secs >= 28 && secs <= 36, `${secs.toFixed(1)} s`);

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
