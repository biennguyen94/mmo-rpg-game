// P6-M2 qua trình duyệt thật: bấm Quest Master (Lorencia) → hộp QUEST MASTER có [Nhận]; nhận
// "Diệt Nhện" → dòng theo dõi "Hạ Spider 0/10"; nhận "Trưởng thành" (đã cấp 10 → xong ngay) →
// [Trả nhiệm vụ] → thông báo + Zen + MP potion; [Bỏ] quest; mở từ Menu chỉ xem (không [Nhận]).
//   node client/e2e/quest.mjs [baseUrl] [thư_mục_ảnh]
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
const ip = `10.93.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
const user = `qs${stamp}`;
const call = async (path, body, token) =>
  (
    await fetch(base + path, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(body),
    })
  ).json();
const { token } = await call("/register", { username: user, password: "matkhau123" });
await call("/characters", { name: `Qs${stamp}`, class: "DK" }, token);
execSync(`mix run scripts/e2e_level.exs ${user} 10`, { env: { ...process.env, LANG: "C.UTF-8" } });

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
await page.waitForFunction(() => window.__mu.entities().some((e) => e.id === window.__mu.selfId));

const self = () => page.evaluate(() => window.__mu.entities().find((e) => e.id === window.__mu.selfId));
const clickAt = async (x, y) => {
  const me = await self();
  const b = await page.locator('[data-test="game-canvas"]').boundingBox();
  await page.mouse.click(b.x + b.width / 2 + (x - me.x) * 32, b.y + b.height / 2 + (y - me.y) * 32);
};
// bấm nút trong panel tới khi `done()` đúng (panel có thể dựng lại giữa chừng)
const clickUntil = async (sel, done, tries = 5) => {
  for (let i = 0; i < tries; i++) {
    await page.click(sel, { timeout: 2000 }).catch(() => {});
    if (await until(page, done, null, 1500)) return true;
  }
  return false;
};

const npc = await page.evaluate(() => window.__mu.entities().find((e) => e.id === "npc_lorencia_quest_master"));
check("Quest Master ở thị trấn Lorencia", npc?.name === "Quest Master" && npc.kind === "npc", npc ? `(${npc.x},${npc.y})` : "không thấy");
await clickAt(npc.x, npc.y);
const opened = await page.waitForSelector('[data-panel="quests"]', { timeout: 8000 }).then(() => true).catch(() => false);
check("bấm NPC → tự đi lại gần → hộp QUEST MASTER", opened && (await page.textContent('[data-panel="quests"] h2')) === "QUEST MASTER");
check("có [Nhận] cho \"Diệt Nhện\"", (await page.$('[data-quest="q_spider"] [data-test="quest-accept"]')) !== null);

const accepted = await clickUntil('[data-quest="q_spider"] [data-test="quest-accept"]', () =>
  document.querySelector('[data-test="quest-active"] [data-quest="q_spider"]') !== null,
);
check("[Nhận] → \"Diệt Nhện\" sang mục Đang làm", accepted);
check(
  "dòng theo dõi \"Diệt Nhện: Hạ Spider 0/10\"",
  await until(page, () => document.querySelector('[data-test="quest-tracker"]')?.textContent.includes("Hạ Spider 0/10"), null, 4000),
);

const zen0 = (await page.evaluate(() => window.__mu.player().zen)) ?? 0;
await clickUntil('[data-quest="q_grow"] [data-test="quest-accept"]', () =>
  document.querySelector('[data-test="quest-active"] [data-quest="q_grow"] [data-test="quest-turnin"]') !== null,
);
check("\"Trưởng thành\" (đã cấp 10) xong ngay → có [Trả nhiệm vụ]", (await page.$('[data-quest="q_grow"] [data-test="quest-turnin"]')) !== null);
await page.screenshot({ path: `${shots}/p6-quest-master.png` });
const turned = await clickUntil('[data-quest="q_grow"] [data-test="quest-turnin"]', () =>
  document.querySelector('[data-test="quest-done"]')?.textContent.includes("1"),
);
check("[Trả nhiệm vụ] → Đã hoàn thành: 1", turned);
check("Zen +5 000", await until(page, (z) => window.__mu.player().zen === z + 5000, zen0, 4000));
check("MP potion vừa ×5 vào túi", await until(page, () => window.__mu.player().inventory.some((i) => i.templateId === "mp_potion_medium" && i.quantity >= 5), null, 4000));
await page.click('[data-tab="notices"]');
check("thông báo \"Hoàn thành nhiệm vụ Trưởng thành\"", await until(page, () => document.body.textContent.includes("Hoàn thành nhiệm vụ Trưởng thành"), null, 3000));

// bỏ "Diệt Nhện" (mở lại từ Menu: chế độ xem — không có [Nhận])
await page.click('[data-tab="menu"]');
await page.click('[data-test="quest-menu"]');
await page.waitForSelector('[data-panel="quests"]');
check("mở từ Menu: \"NHIỆM VỤ\", không có [Nhận]", (await page.textContent('[data-panel="quests"] h2')) === "NHIỆM VỤ" && (await page.$('[data-test="quest-accept"]')) === null);
await clickUntil('[data-quest="q_spider"] [data-test="quest-abandon"]', () => document.querySelector('[data-test="quest-abandon-confirm"]') !== null);
const dropped = await clickUntil('[data-test="quest-abandon-confirm"]', () => document.querySelector('[data-test="quest-active"] [data-quest="q_spider"]') === null);
check("[Bỏ] → [Bỏ thật?] → hết quest, hết dòng theo dõi", dropped && (await page.$('[data-test="quest-tracker"]')) === null);
await page.screenshot({ path: `${shots}/p6-quest-panel.png` });

check("không lỗi JS trên trang", errors.length === 0, errors.join(" | ").slice(0, 200));
await browser.close();
const pass = results.filter((r) => r.ok).length;
console.log(`\n${pass}/${results.length} PASS`);
process.exit(pass === results.length ? 0 : 1);
