// P3-M3 qua trình duyệt thật: Thủ kho ở thị trấn Lorencia, panel kho 15×8 + túi 8×8, gửi bằng
// tooltip [Gửi] và kéo thả, rút bằng [Rút], Esc đóng panel, tải lại trang đồ vẫn trong
// kho, tài khoản khác không thấy, mobile xếp dọc.
//   node client/e2e/warehouse.mjs [baseUrl] [thư_mục_ảnh]
// Server cần TRUSTED_PROXIES=127.0.0.1. Đồ ban đầu lấy từ scripts/e2e_seed.exs (chỉ cho test).
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

async function account(tag, seed) {
  const user = `wh${tag}${stamp}`;
  const ip = `10.97.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
  const call = async (path, body, token) =>
    (
      await fetch(base + path, {
        method: "POST",
        headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify(body),
      })
    ).json();
  const { token } = await call("/register", { username: user, password: "matkhau123" });
  await call("/characters", { name: `${tag}${stamp}`, class: "DK" }, token);
  if (seed) execSync(`mix run scripts/e2e_seed.exs ${user}`, { env: { ...process.env, LANG: "C.UTF-8" } });
  return user;
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
  await page.waitForFunction(() => window.__mu.entities().some((e) => e.id === window.__mu.selfId));
  return page;
}
// bấm Thủ kho (client tự đi lại gần rồi gửi npc_open)
async function openWarehouse(page) {
  const npc = await page.evaluate(() => window.__mu.entities().find((e) => e.id === "npc_lorencia_warehouse"));
  if (!npc) return false;
  await clickAt(page, npc.x, npc.y);
  return page.waitForSelector('[data-panel="warehouse"]', { timeout: 8000 }).then(() => true).catch(() => false);
}
const bagIds = (page) => page.evaluate(() => window.__mu.player().inventory.map((i) => i.templateId));
const whItem = (page, tid) =>
  page.$$eval("[data-wh-slot][data-item]", (cs) => cs.map((c) => ({ slot: Number(c.dataset.whSlot), id: c.dataset.item })), tid);

const A = await account("Wa", true);
const B = await account("Wb", false);
const pa = await enter(A);

// Thủ kho có trong thị trấn, tên "Warehouse Keeper"
const npc = await pa.evaluate(() => window.__mu.entities().find((e) => e.id === "npc_lorencia_warehouse"));
check("Thủ kho \"Warehouse Keeper\" ở thị trấn Lorencia", npc?.name === "Warehouse Keeper" && npc.kind === "npc", npc ? `(${npc.x},${npc.y})` : "không thấy");
const spriteOk = await pa.evaluate(() => new Promise((r) => { const i = new Image(); i.onload = () => r(i.naturalWidth > 0); i.onerror = () => r(false); i.src = "/assets/sprites/npcs/lorencia_warehouse.png"; }));
check("sprite Thủ kho tải được", spriteOk);

const opened = await openWarehouse(pa);
const cells = await pa.locator("[data-wh-slot]").count();
const bagCells = await pa.locator('[data-panel="warehouse"] [data-bag-slot]').count();
check("bấm Thủ kho → panel kho 15×8 (120 ô) + túi 8×8", opened && cells === 120 && bagCells === 64, `${cells} + ${bagCells} ô`);
await pa.screenshot({ path: `${shots}/p3-warehouse-desktop.png` });

// [Gửi] qua tooltip: kiếm
const inv = await pa.evaluate(() => window.__mu.player().inventory);
const sword = inv.find((i) => i.templateId === "sword_t0");
await pa.click(`[data-panel="warehouse"] [data-bag-slot="${sword.slot}"]`);
await pa.click('[data-test="deposit"]');
const deposited = await until(pa, (id) => document.querySelector(`[data-wh-slot][data-item="${id}"]`) !== null && !window.__mu.player().inventory.some((i) => i.id === id), sword.id);
check("[Gửi] kiếm → vào kho, rời túi", deposited);

// kéo thả nhẫn vào ô kho 17
const ring = inv.find((i) => i.templateId === "ring_hp_t0");
await pa.dragAndDrop(`[data-panel="warehouse"] [data-item="${ring.id}"]`, '[data-wh-slot="17"]');
const dragged = await until(pa, (id) => document.querySelector(`[data-wh-slot="17"]`)?.dataset.item === id, ring.id);
check("kéo nhẫn vào ô kho 17", dragged);

// [Rút] kiếm
await pa.click(`[data-wh-slot][data-item="${sword.id}"]`);
await pa.click('[data-test="withdraw"]');
const withdrawn = await until(pa, (id) => window.__mu.player().inventory.some((i) => i.id === id) && !document.querySelector(`[data-wh-slot][data-item="${id}"]`), sword.id);
check("[Rút] kiếm → về túi", withdrawn);

// panel phủ toàn màn hình (như Shop, §19.7): Esc đóng
await pa.keyboard.press("Escape");
const closed = await until(pa, () => !document.querySelector('[data-panel="warehouse"]'), null, 3000);
check("Esc đóng panel kho", closed);

// tải lại trang: nhẫn vẫn ở kho ô 17
await pa.reload();
await pa.click("text=Vào game").catch(() => {});
await pa.waitForSelector('[data-test="where"]');
await pa.waitForFunction(() => window.__mu.entities().some((e) => e.id === window.__mu.selfId));
await openWarehouse(pa);
const kept = await until(pa, (id) => document.querySelector(`[data-wh-slot="17"]`)?.dataset.item === id, ring.id);
check("tải lại trang → nhẫn vẫn trong kho (DB)", kept);
check("túi còn kiếm, không còn nhẫn", (await bagIds(pa)).includes("sword_t0") && !(await bagIds(pa)).includes("ring_hp_t0"));

// tài khoản khác: kho trống; mobile xếp dọc
const pb = await enter(B, { width: 390, height: 844 });
const openedB = await openWarehouse(pb);
const emptyB = (await pb.locator("[data-wh-slot][data-item]").count()) === 0;
check("tài khoản khác mở kho: trống (kho theo tài khoản)", openedB && emptyB);
const boxes = await pb.evaluate(() => [...document.querySelectorAll(".warehouse .col")].map((c) => c.getBoundingClientRect().top));
const overflow = await pb.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
check("mobile: kho trên, túi dưới, không tràn ngang", boxes.length === 2 && boxes[1] > boxes[0] && !overflow);
await pb.screenshot({ path: `${shots}/p3-warehouse-mobile.png` });

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
