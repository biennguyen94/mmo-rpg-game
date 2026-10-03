// P4-M2 qua trình duyệt thật: bấm người chơi → [🤺 Thách đấu] → hộp "… thách đấu tay đôi" →
// [Nhận] → thanh duel (đối thủ + đếm giờ) ở hai bên; người ngoài không có [⚔ Tấn công] với người
// đang duel; đánh đối thủ không hỏi xác nhận PK; về 0 HP thì giữ 1 HP và thua, không ai bị PK;
// [Đầu hàng] thua ngay; [Từ chối] báo người mời; người cùng nhóm không có [⚔ Tấn công] (P4M1-2).
//   node client/e2e/duel.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1. Cấp / HP đặt bằng scripts/e2e_pvp.exs (chỉ cho test).
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
const self = (page) => page.evaluate(() => window.__mu.entities().find((e) => e.id === window.__mu.selfId));
const clickAt = async (page, x, y) => {
  const me = await self(page);
  const b = await page.locator('[data-test="game-canvas"]').boundingBox();
  await page.mouse.click(b.x + b.width / 2 + (x - me.x) * 32, b.y + b.height / 2 + (y - me.y) * 32);
};
const walkTo = async (page, x, y, ms = 25000) => {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const p = await self(page);
    if (p.x === x && p.y === y) return true;
    await clickAt(page, Math.max(p.x - 12, Math.min(p.x + 12, x)), Math.max(p.y - 8, Math.min(p.y + 8, y)));
    await (await page.$('[data-test="player-goto"]'))?.click();
    await page.waitForTimeout(900);
  }
  return false;
};
async function account(tag, level, hp) {
  const user = `du${tag}${stamp}`;
  const name = `${tag}${stamp}`;
  const ip = `10.92.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
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
  execSync(`mix run scripts/e2e_pvp.exs ${user} ${level} ${hp} 0`, { env: { ...process.env, LANG: "C.UTF-8" } });
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
// bấm người chơi `name`; menu phải đúng người (đông người: người khác có thể đứng cùng ô)
async function menuOn(page, name) {
  for (let i = 0; i < 4; i++) {
    await page.keyboard.press("Escape");
    const t = await page.evaluate((n) => window.__mu.entities().find((e) => e.name === n), name);
    await clickAt(page, t.x, t.y);
    const ok = await page.waitForSelector(`[data-test="playermenu"] [data-target-name="${name}"]`, { timeout: 1500 }).then(() => true).catch(() => false);
    if (ok) return true;
    await page.waitForTimeout(700);
  }
  return false;
}
const notices = async (page) => {
  await page.click('[data-tab="notices"]');
  const t = await page.textContent('[data-panel="notices"]');
  await page.keyboard.press("Escape");
  return t;
};

const A = await account("Da", 10, 999999);
const B = await account("Db", 10, 8);
const C = await account("Dc", 10, 999999);
const pa = await enter(A.user);
const pb = await enter(B.user);
const pc = await enter(C.user);
await walkTo(pa, 27, 30);
await walkTo(pb, 29, 30);
await walkTo(pc, 28, 33);

// ---------- từ chối ----------
await menuOn(pa, B.name);
check("menu người chơi có [🤺 Thách đấu]", !!(await pa.$('[data-test="duel-request"]')));
await pa.click('[data-test="duel-request"]');
await pb.waitForSelector('[data-test="duel-ask"]', { timeout: 4000 }).catch(() => null);
check("B thấy hộp \"… thách đấu tay đôi\" có đếm ngược", ((await pb.textContent('[data-test="duel-ask"]').catch(() => "")) ?? "").includes(`${A.name} thách đấu tay đôi`));
await pb.click('[data-test="duel-decline"]');
check("B từ chối → A nhận thông báo \"… từ chối đấu tay đôi\"", await until(pa, () => document.querySelector('[data-tab="notices"] .badge') !== null, null, 4000) && (await notices(pa)).includes("từ chối đấu tay đôi"));

// ---------- nhận ----------
await menuOn(pa, B.name);
await pa.click('[data-test="duel-request"]');
await pb.waitForSelector('[data-test="duel-ask"]', { timeout: 4000 });
await pb.screenshot({ path: `${shots}/p4-duel-ask.png` });
await pb.click('[data-test="duel-accept"]');
const bars = (await until(pa, () => !!document.querySelector('[data-test="duel-bar"]'), null, 4000)) && (await until(pb, () => !!document.querySelector('[data-test="duel-bar"]'), null, 4000));
check("nhận → hai bên có thanh duel (đối thủ + đếm giờ + Đầu hàng)", bars && (await pa.textContent('[data-test="duel-bar"]')).includes(`Đấu với ${B.name}`));
const sys = await until(pc, () => [...document.querySelectorAll('[data-test="chat-log"] .line')].some((l) => l.textContent.includes("bắt đầu đấu tay đôi")), null, 4000);
check("người khác trên map thấy dòng SYSTEM \"… bắt đầu đấu tay đôi\"", sys);

// người ngoài không xen vào
await menuOn(pc, A.name);
check("người ngoài: không có [⚔ Tấn công] với người đang duel", !(await pc.$('[data-test="pvp-attack"]')));
await pc.keyboard.press("Escape");

// đánh đối thủ: không hỏi xác nhận PK
await menuOn(pa, B.name);
await pa.click('[data-test="pvp-attack"]');
check("đánh đối thủ duel không hỏi xác nhận PK", !(await pa.$('[data-test="pvp-confirm"]')));
await pa.screenshot({ path: `${shots}/p4-duel-bar.png` });
const ended = await until(pa, () => !document.querySelector('[data-test="duel-bar"]'), null, 60000);
const bState = await pb.evaluate(() => window.__mu.entities().find((e) => e.id === window.__mu.selfId));
check("B về 0 HP → duel kết thúc, B còn 1 HP, không chết", ended && bState.hp === 1 && bState.state !== "dead", JSON.stringify({ hp: bState.hp, state: bState.state }));
check("A: \"Bạn thắng …\"; B: \"Bạn thua …\"", (await notices(pa)).includes(`Bạn thắng ${B.name}`) && (await notices(pb)).includes(`Bạn thua ${A.name}`));
check("không ai bị PK sau duel", (await pa.evaluate(() => window.__mu.player().view.pkPoints)) === 0);
await pa.waitForTimeout(1200);
check("thắng duel: A tự dừng đánh (không thành đánh người thường)", (await pb.evaluate(() => window.__mu.entities().find((e) => e.id === window.__mu.selfId).hp)) === 1 && !(await pa.evaluate(() => window.__mu.entities().some((e) => e.aggressor && e.id === window.__mu.selfId))));

// ---------- đầu hàng ----------
await menuOn(pa, B.name);
await pa.click('[data-test="duel-request"]');
await pb.waitForSelector('[data-test="duel-ask"]', { timeout: 4000 });
await pb.click('[data-test="duel-accept"]');
await until(pb, () => !!document.querySelector('[data-test="duel-bar"]'), null, 4000);
await pb.click('[data-test="duel-surrender"]');
const surr = await until(pa, () => !document.querySelector('[data-test="duel-bar"]'), null, 4000);
check("[Đầu hàng] → B thua ngay, A thắng", surr && (await notices(pb)).includes(`Bạn thua ${A.name}`));

// ---------- cùng nhóm ----------
await menuOn(pa, C.name);
await pa.click('[data-test="party-invite"]');
await pc.waitForSelector('[data-test="party-accept"]', { timeout: 4000 });
await pc.click('[data-test="party-accept"]');
await until(pa, () => document.querySelectorAll("[data-member]").length === 2, null, 4000);
await menuOn(pa, C.name);
check("P4M1-2: người cùng nhóm → không có [⚔ Tấn công]", !(await pa.$('[data-test="pvp-attack"]')));

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
