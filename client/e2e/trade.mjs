// P5-M4 qua trình duyệt thật: bấm người chơi → [🤝 Giao dịch] → hộp lời mời → [Đồng ý], panel giao
// dịch hai bàn; đặt đồ từ túi + Zen, bên kia thấy; thay đổi sau khi khóa bỏ khóa cả hai; [Khóa] →
// [Đồng ý] hai bên → đồ + Zen đổi chủ; từ chối báo người mời; đóng panel = hủy.
//   node client/e2e/trade.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1. Đồ + Zen đặt bằng scripts/e2e_upgrade.exs + e2e_guild.exs
// (chỉ cho test).
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
const env = { ...process.env, LANG: "C.UTF-8" };

async function account(tag, zen) {
  const user = `tr${tag}${stamp}`;
  const name = `${tag}${stamp}`;
  const ip = `10.93.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
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
  execSync(`mix run scripts/e2e_upgrade.exs ${user}`, { env });
  execSync(`mix run scripts/e2e_guild.exs ${user} 1 ${zen}`, { env });
  return { user, name, ip };
}

const browser = await chromium.launch({ executablePath: existsSync(exe) ? exe : undefined });
const errors = [];
async function enter(acc) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, extraHTTPHeaders: { "x-forwarded-for": acc.ip } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(base);
  await page.fill('input[name="username"]', acc.user);
  await page.fill('input[name="password"]', "matkhau123");
  await page.click('button[type="submit"]');
  await page.click("text=Vào game");
  await page.waitForSelector('[data-test="where"]');
  await page.waitForFunction(() => window.__mu.entities().some((e) => e.id === window.__mu.selfId));
  return page;
}
const stand = async (page, x, y) => {
  await clickAt(page, x, y);
  await (await page.$('[data-test="player-goto"]'))?.click();
  return until(page, ([x, y]) => window.__mu.player().x === x && window.__mu.player().y === y, [x, y], 6000);
};
async function menuClick(page, name, sel) {
  for (let k = 0; k < 5; k++) {
    const t = await page.evaluate((n) => window.__mu.entities().find((e) => e.name === n), name);
    if (!t) return false;
    await clickAt(page, t.x, t.y);
    if (await until(page, ([n, s]) => document.querySelector(`[data-target-name="${n}"]`) && document.querySelector(s), [name, sel], 1500)) {
      await page.click(sel);
      return true;
    }
    await page.keyboard.press("Escape");
    await page.waitForTimeout(400);
  }
  return false;
}
// bấm `sel` cho tới khi `done` đúng (panel vẽ lại theo mỗi event `trade`: lần bấm rơi đúng lúc vẽ lại thì mất)
async function clickUntil(page, sel, watch, done, arg) {
  for (let k = 0; k < 3; k++) {
    await page.click(sel, { timeout: 3000 }).catch(() => {});
    if (await until(watch, done, arg, 2000)) return true;
  }
  return false;
}
const inv = (page) => page.evaluate(() => window.__mu.player().inventory);
const byTpl = async (page, tid) => (await inv(page)).find((i) => i.templateId === tid);
const zenOf = (page) => page.evaluate(() => window.__mu.player().zen);
const open = async (pa, pb, A) => {
  await menuClick(pa, B.name, '[data-test="trade-request"]');
  await until(pb, () => document.querySelector('[data-test="trade-accept"]') !== null, null, 4000);
  await pb.click('[data-test="trade-accept"]');
  return until(pa, () => document.querySelector('[data-panel="trade"] [data-test="trade-mine"]') !== null, null, 4000);
};

const A = await account("Ta", 5000);
const B = await account("Tb", 0);
const pa = await enter(A);
const pb = await enter(B);
await stand(pa, 15, 34);
await stand(pb, 17, 34);

// ---------- mời → từ chối ----------
check("bấm người chơi → [🤝 Giao dịch]", await menuClick(pa, B.name, '[data-test="trade-request"]'));
check("người được mời thấy hộp \"… muốn giao dịch\"", await until(pb, (n) => document.querySelector('[data-test="trade-ask"]')?.textContent.includes(n), A.name, 4000));
await pb.click('[data-test="trade-decline"]');
await pa.click('[data-tab="notices"]');
check("từ chối → người mời được báo", await until(pa, (n) => document.querySelector('[data-panel="notices"]')?.textContent.includes(`${n} từ chối giao dịch`), B.name, 4000));
await pa.keyboard.press("Escape");

// ---------- mời → đồng ý → bàn ----------
check("mời lại → đồng ý → cả hai mở panel giao dịch", (await open(pa, pb, A)) && (await until(pb, () => document.querySelector('[data-panel="trade"]') !== null, null, 4000)));
const sword = await byTpl(pa, "sword_t0");
const bless = await byTpl(pb, "jewel_bless");
await pa.click(`[data-trade-bag="${sword.id}"]`);
// chờ bàn vẽ lại với món vừa đặt rồi mới nhập Zen (panel vẽ lại theo mỗi event `trade`)
await until(pa, (id) => document.querySelector(`[data-trade-mine="${id}"]`) !== null, sword.id, 3000);
for (let k = 0; k < 2; k++) {
  await pa.fill('[data-test="trade-zen"]', "1200");
  await pa.click('[data-test="trade-zen-set"]');
  if (await until(pa, () => document.querySelector('[data-test="trade-mine"]')?.textContent.includes("1.200"), null, 2000)) break;
}
await pb.click(`[data-trade-bag="${bless.id}"]`);
await until(pa, (id) => document.querySelector(`[data-trade-theirs="${id}"]`) !== null, bless.id, 3000);
check("bên kia thấy kiếm + 1 200 Zen trên bàn của A", await until(pb, (id) => document.querySelector(`[data-trade-theirs="${id}"]`) && document.querySelector('[data-test="trade-theirs"]').textContent.includes("1.200"), sword.id, 4000));
await pa.screenshot({ path: `${shots}/p5-trade-panel.png` });

// ---------- khóa, thay đổi bỏ khóa ----------
await pa.click('[data-test="trade-lock"]');
check("A khóa → B thấy \"🔒 Đã khóa\"", await until(pb, () => document.querySelector('[data-test="trade-theirs"]')?.textContent.includes("Đã khóa"), null, 3000));
check("[Đồng ý] tắt khi B chưa khóa", await pa.isDisabled('[data-test="trade-confirm"]'));
await pb.click(`[data-trade-mine="${bless.id}"]`);
check("B lấy lại món → khóa của A bỏ", await until(pa, () => !document.querySelector('[data-test="trade-mine"]').classList.contains("locked"), null, 3000));
await pb.click(`[data-trade-bag="${bless.id}"]`);
await until(pa, (id) => document.querySelector(`[data-trade-theirs="${id}"]`) !== null, bless.id, 3000);

// ---------- chốt (mỗi bước chờ bên kia thấy rồi mới làm tiếp: thay đổi tới sau khóa sẽ bỏ khóa) ----------
const theirsLocked = () => document.querySelector('[data-test="trade-theirs"]')?.classList.contains("locked");
await clickUntil(pa, '[data-test="trade-lock"]', pb, theirsLocked);
await clickUntil(pb, '[data-test="trade-lock"]', pa, theirsLocked);
await clickUntil(pa, '[data-test="trade-confirm"]', pb, () => document.querySelector('[data-test="trade-theirs"]')?.textContent.includes("Đã đồng ý"));
await clickUntil(pb, '[data-test="trade-confirm"]', pa, () => !document.querySelector('[data-panel="trade"]'));
const closed = await until(pa, () => !document.querySelector('[data-panel="trade"]'), null, 5000);
const gotSword = await until(pb, (id) => window.__mu.player().inventory.some((i) => i.id === id), sword.id, 5000);
check("hai bên đồng ý → panel đóng, B nhận kiếm, A nhận Bless", closed && gotSword && (await until(pa, (id) => window.__mu.player().inventory.some((i) => i.id === id), bless.id, 5000)));
check("Zen đổi: A 5 000 → 3 800, B 0 → 1 200", (await zenOf(pa)) === 3800 && (await zenOf(pb)) === 1200, `${await zenOf(pa)} / ${await zenOf(pb)}`);

// ---------- đóng panel = hủy ----------
await open(pa, pb, A);
await pa.keyboard.press("Escape");
check("A đóng panel (Esc) → giao dịch hủy, B được báo, panel B đóng", await until(pb, () => !document.querySelector('[data-panel="trade"]'), null, 4000));

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
