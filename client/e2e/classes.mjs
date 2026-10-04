// P2-M2 qua trình duyệt thật: màn tạo nhân vật có 3 class (DK/DW/ELF), tạo DW và ELF, chỉ số
// cấp 1 + đồ khởi đầu từ server, Elf cầm cung đánh Spider từ xa (tầm 5, P2-5).
//   node client/e2e/classes.mjs [baseUrl] [thư_mục_ảnh]   (server đang chạy)
// Mỗi lần chạy đăng ký 2 tài khoản (giới hạn auth.register theo IP: xem config rateLimit).
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
const pos = async (page) => {
  const m = (await page.textContent('[data-test="where"]')).match(/\((\d+),(\d+)\)/);
  return { x: +m[1], y: +m[2] };
};
const clickTile = async (page, dx, dy) => {
  const b = await page.locator('[data-test="game-canvas"]').boundingBox();
  await page.mouse.click(b.x + b.width / 2 + dx * 32, b.y + b.height / 2 + dy * 32);
};
const walkTo = async (page, x, y, ms = 15000) => {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const p = await pos(page);
    if (p.x === x && p.y === y) return true;
    const dx = Math.max(-12, Math.min(12, x - p.x));
    const dy = Math.max(-8, Math.min(8, y - p.y));
    await clickTile(page, dx, dy);
    // bấm trúng người chơi khác → menu (P3-M4): chọn "Đi tới đây"
    await (await page.$('[data-test="player-goto"]'))?.click();
    await page.waitForTimeout(Math.max(Math.abs(dx), Math.abs(dy)) * 210 + 150);
  }
  return false;
};

const browser = await chromium.launch({ executablePath: existsSync(exe) ? exe : undefined });
const errors = [];

async function create(cls, name) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(base);
  await page.click("text=Chưa có tài khoản? Đăng ký");
  await page.fill('input[name="username"]', `cls${cls.toLowerCase()}${stamp}`);
  await page.fill('input[name="password"]', "matkhau123");
  await page.click('button[type="submit"]');
  await page.waitForSelector('[data-test="class-picker"]');
  return { page, ctx, name };
}

// --- màn tạo nhân vật: 4 class (MG khóa), sprite tải được, DK chọn sẵn ---
const elf = await create("ELF", `Ef${stamp}`);
const opts = await elf.page.$$eval('[data-test="class-picker"] label', (ls) =>
  ls.map((l) => ({ id: l.querySelector("input").value, checked: l.querySelector("input").checked, disabled: l.querySelector("input").disabled, img: l.querySelector("img") })),
);
await elf.page.waitForFunction(() => [...document.querySelectorAll('[data-test="class-picker"] img')].every((i) => i.complete && i.naturalWidth > 0));
// P3-M5: thêm MG, khóa tới khi tài khoản có nhân vật cấp 20 (chi tiết ở mg.mjs)
check("màn tạo nhân vật: DK / DW / ELF / MG (khóa), DK chọn sẵn, có hình", opts.map((o) => o.id).join() === "DK,DW,ELF,MG" && opts[0].checked && opts[3].disabled);
await elf.page.screenshot({ path: `${shots}/p2-create-class.png` });

// --- tạo ELF ---
await elf.page.click('[data-test="class-picker"] label:has(input[value="ELF"])');
await elf.page.fill('input[name="name"]', elf.name);
await elf.page.click('button[type="submit"]');
await elf.page.waitForSelector('[data-test="where"]');
let p = await player(elf.page);
check(
  "tạo ELF: HP 130, MP 62, cầm cung, tầm đánh 5, Dmg 7~14",
  p.class === "ELF" && p.view.hpMax === 130 && p.view.mpMax === 62 && p.view.attackRange === 5 &&
    p.equipment.some((e) => e.templateId === "bow_t0" && e.slot === 5) && p.view.attackMin === 7 && p.view.attackMax === 14,
  `${p.class} hp ${p.view.hpMax} mp ${p.view.mpMax} tầm ${p.view.attackRange} dmg ${p.view.attackMin}~${p.view.attackMax}`,
);

// --- Elf ra ngoài, bắn Spider: đòn đầu trúng khi còn cách ≥ 2 ô ---
await walkTo(elf.page, 25, 31);
await walkTo(elf.page, 40, 31);
// Spider có aggro (đi 3 ô/s) nên có lúc lao tới sát trước đòn đầu: thử tới khi có đòn trúng từ ≥ 2 ô
let ranged = null;
let best = null;
for (let round = 0; round < 12 && !(best && best.d >= 2); round++) {
  const t = await elf.page.evaluate(() => {
    const me = window.__mu.entities().find((e) => e.id === window.__mu.selfId);
    return window.__mu.entities()
      .filter((e) => e.kind === "monster" && e.templateId === "spider" && e.state !== "dead")
      .map((e) => ({ id: e.id, x: e.x, y: e.y, hp: e.hp, d: Math.max(Math.abs(e.x - me.x), Math.abs(e.y - me.y)) }))
      .sort((a, b) => a.d - b.d)[0];
  });
  if (!t) { await elf.page.waitForTimeout(1000); continue; }
  const me = await pos(elf.page);
  if (t.d > 10) { await walkTo(elf.page, t.x - 6, t.y, 6000); continue; }
  await clickTile(elf.page, t.x - me.x, t.y - me.y);
  if (!(await elf.page.waitForSelector('[data-test="ctxmenu"]', { timeout: 1500 }).catch(() => null))) continue;
  await elf.page.click("text=Tấn công thường");
  // khoảnh khắc Spider mất máu lần đầu: đo khoảng cách
  ranged = await elf.page
    .waitForFunction(([id, hp]) => {
      const s = window.__mu.entities().find((e) => e.id === id);
      const me = window.__mu.entities().find((e) => e.id === window.__mu.selfId);
      if (!s || !me || s.hp >= hp) return null;
      return { d: Math.max(Math.abs(s.x - me.x), Math.abs(s.y - me.y)) };
    }, [t.id, t.hp], { timeout: 10000 })
    .then((h) => h.jsonValue())
    .catch(() => null);
  if (ranged && (!best || ranged.d > best.d)) best = ranged;
  // chờ trận này xong (Spider chết hoặc hết 15 s) rồi thử con khác
  await until(elf.page, (id) => { const s = window.__mu.entities().find((e) => e.id === id); return !s || s.state === "dead"; }, t.id, 15000);
}
check("Elf bắn trúng Spider từ xa (≥ 2 ô)", !!best && best.d >= 2, best ? `cách ${best.d} ô` : "không đánh được");
await elf.page.screenshot({ path: `${shots}/p2-elf-ranged.png` });

// --- tạo DW ---
const dw = await create("DW", `Dw${stamp}`);
await dw.page.click('[data-test="class-picker"] label:has(input[value="DW"])');
await dw.page.fill('input[name="name"]', dw.name);
await dw.page.click('button[type="submit"]');
await dw.page.waitForSelector('[data-test="where"]');
p = await player(dw.page);
check(
  "tạo DW: HP 110, MP 120, cầm gậy, tầm 1, Dmg 6~13",
  p.class === "DW" && p.view.hpMax === 110 && p.view.mpMax === 120 && p.view.attackRange === 1 &&
    p.equipment.some((e) => e.templateId === "staff_t0") && p.view.attackMin === 6 && p.view.attackMax === 13,
  `${p.class} hp ${p.view.hpMax} mp ${p.view.mpMax} dmg ${p.view.attackMin}~${p.view.attackMax}`,
);
const selfClass = await dw.page.evaluate(() => window.__mu.entities().find((e) => e.id === window.__mu.selfId)?.class);
check("spawn của người chơi có class (để vẽ sprite theo class)", selfClass === "DW", `class ${selfClass}`);
await dw.page.screenshot({ path: `${shots}/p2-dw.png` });
check("không lỗi JS trên trang", errors.length === 0, errors.join(" | "));

await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} PASS`);
process.exit(failed.length ? 1 : 0);
