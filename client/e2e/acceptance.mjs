// Nghiệm thu Phase 1 (KB_00_RULES §7) qua trình duyệt thật: Playwright + Chromium headless,
// server thật, 2 người chơi. Đồ/Zen ban đầu của người A lấy từ scripts/e2e_seed.exs (chỉ cho test).
//   node client/e2e/acceptance.mjs [baseUrl] [thư_mục_ảnh]   (chạy ở thư mục gốc repo; server đang chạy)
import { execSync } from "node:child_process";
import { existsSync } from "node:fs";

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? "/opt/node-tools/node_modules/playwright/index.mjs");
const base = process.argv[2] ?? "http://localhost:4000";
const shots = process.argv[3] ?? "docs/screenshots";
const exe = process.env.CHROMIUM_PATH ?? "/opt/pw-browsers/chromium";
const results = [];
const check = (id, name, ok, extra = "") => {
  results.push({ id, name, ok, extra });
  console.log(`${ok ? "PASS" : "FAIL"}  [${id}] ${name}${extra ? "  — " + extra : ""}`);
};

const stamp = Date.now() % 1_000_000;
const A = { user: `acca${stamp}`, char: `Aa${stamp}` };
const B = { user: `accb${stamp}`, char: `Bb${stamp}` };

async function http(method, path, body, token) {
  const r = await fetch(base + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return r.json();
}

// A: tạo qua HTTP rồi seed (Session chưa giữ nhân vật)
const ta = (await http("POST", "/register", { username: A.user, password: "matkhau123" })).token;
await http("POST", "/characters", { name: A.char }, ta);
console.log(execSync(`mix run scripts/e2e_seed.exs ${A.user}`, { env: { ...process.env, LANG: "C.UTF-8" } }).toString().trim().split("\n").pop());

const browser = await chromium.launch({ executablePath: existsSync(exe) ? exe : undefined });

const pos = async (page) => {
  const m = (await page.textContent('[data-test="where"]')).match(/\((\d+),(\d+)\)/);
  return { x: +m[1], y: +m[2] };
};
const player = (page) => page.evaluate(() => window.__mu.player());
const clickTile = async (page, dx, dy) => {
  const b = await page.locator('[data-test="game-canvas"]').boundingBox();
  await page.mouse.click(b.x + b.width / 2 + dx * 32, b.y + b.height / 2 + dy * 32);
};
const walkTo = async (page, x, y, ms = 15000) => {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const p = await pos(page);
    if (p.x === x && p.y === y) return true;
    // bấm trong tầm nhìn (tối đa ±12 ô mỗi lần)
    const dx = Math.max(-12, Math.min(12, x - p.x));
    const dy = Math.max(-8, Math.min(8, y - p.y));
    await clickTile(page, dx, dy);
    await page.waitForTimeout(Math.max(Math.abs(dx), Math.abs(dy)) * 210 + 150);
  }
  return false;
};
const until = (page, fn, arg, ms = 5000) =>
  page.waitForFunction(fn, arg, { timeout: ms }).then(() => true).catch(() => false);
const login = async (page, u) => {
  await page.goto(base);
  await page.fill('input[name="username"]', u);
  await page.fill('input[name="password"]', "matkhau123");
  await page.click('button[type="submit"]');
};

const ctxA = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const pa = await ctxA.newPage();
const errorsA = [];
pa.on("pageerror", (e) => errorsA.push(String(e)));

// 1. login
await login(pa, A.user);
const entered = await pa.waitForSelector("text=Vào game", { timeout: 5000 }).then(() => true).catch(() => false);
check(1, "login OK", entered);

// 3. vào Lorencia
await pa.click("text=Vào game");
await pa.waitForSelector('[data-test="where"]');
check(3, "vào Lorencia OK", (await pa.textContent('[data-test="where"]')).startsWith("Lorencia"));

// 13. dùng potion — TRƯỚC khi mặc áo (Q14): HP 100 → Q → 150
let p = await player(pa);
const potBefore = p.view.potions.HP;
await pa.keyboard.press("q");
const healed = await until(pa, () => window.__mu.player().hp === 150);
p = await player(pa);
check(13, "dùng potion OK (trước khi mặc áo, Q14)", healed && p.view.potions.HP === potBefore - 1, `hp=${p.hp} potion ${potBefore}→${p.view.potions.HP}`);

// 11 + icon: Túi đồ → kiếm, nhẫn qua tooltip [Trang bị]; giáp kéo thả vào ô ARMOR (P2-M1)
await pa.keyboard.press("i");
const imgs = await pa.$$eval('[data-panel="inventory"] img', (xs) =>
  Promise.all(xs.map((i) => (i.complete ? null : new Promise((r) => (i.onload = i.onerror = r))))).then(() =>
    xs.map((i) => ({ src: i.getAttribute("src"), w: i.naturalWidth })),
  ),
);
check(11, "mỗi item hiển thị một icon (chưa có icon thật → placeholder, cảnh báo ở ICON_REPORT)", imgs.length >= 3 && imgs.every((i) => i.w > 0 && i.src.endsWith("placeholder.png")), `${imgs.length} icon`);
for (const tid of ["sword_t0", "armor_t0", "ring_hp_t0"]) {
  const it = (await player(pa)).inventory.find((i) => i.templateId === tid);
  if (tid === "armor_t0") await pa.dragAndDrop(`[data-item="${it.id}"]`, '[data-slot="1"]');
  else {
    await pa.click(`[data-item="${it.id}"]`);
    await pa.click('[data-test="tooltip"] >> text=Trang bị');
  }
  await until(pa, (id) => window.__mu.player().equipment.some((e) => e.id === id), it.id);
}
p = await player(pa);
check(10, "equip item OK (kiếm/giáp/nhẫn qua UI)", p.equipment.length === 3 && p.view.attackMax === 7 + 7 && p.view.defense === 15 && p.view.hpMax === 191 + 20, `atk ${p.view.attackMin}~${p.view.attackMax} def ${p.view.defense} hpMax ${p.view.hpMax}`);
await pa.screenshot({ path: `${shots}/accept-equip.png` });
await pa.click('[data-slot="8"]');
await pa.click('[data-test="tooltip"] >> text=Tháo');
const unequipped = await until(pa, () => window.__mu.player().equipment.length === 2);
check(10, "tháo đồ qua tooltip [Tháo]", unequipped);
await pa.keyboard.press("Escape");

// 7. cộng stat: bấm [+] VIT 3 lần nhanh → MỘT alloc 3 điểm (debounce 200 ms)
await pa.keyboard.press("c");
for (let i = 0; i < 3; i++) await pa.click('[data-stat="vitality"]');
const allocated = await until(pa, () => window.__mu.player().vitality === 28);
p = await player(pa);
check(8, "cộng stat OK (VIT +3, gộp một lệnh)", allocated && p.freeStatPoints === 7, `VIT ${p.vitality}, còn ${p.freeStatPoints}`);
await pa.screenshot({ path: `${shots}/accept-character.png` });
await pa.keyboard.press("Escape");

// 12. mua potion từ NPC; bán nhẫn
await walkTo(pa, 12, 26);
await clickTile(pa, -1, -1);
await pa.waitForSelector('[data-panel="shop"]', { timeout: 5000 }).catch(() => null);
const zen0 = (await player(pa)).zen;
await pa.click('[data-buy="hp_potion_small"]');
const bought = await until(pa, (z) => window.__mu.player().zen === z - 100, zen0);
check(12, "mua potion từ NPC OK (−100 Zen)", bought, `zen ${zen0}→${(await player(pa)).zen}`);
const ring = (await player(pa)).inventory.find((i) => i.templateId === "ring_hp_t0");
await pa.click(`[data-panel="shop"] [data-item="${ring.id}"] button`);
const sold = await until(pa, (z) => window.__mu.player().zen === z - 100 + 750, zen0);
check(12, "bán đồ ở NPC (+750 Zen)", sold);
await pa.screenshot({ path: `${shots}/accept-shop.png` });
await pa.keyboard.press("Escape");

// P2-M1: túi đồ lưới 8×8 — tách stack, kéo gộp, kéo vào thùng rác → xác nhận → vứt, nhặt lại
{
  await pa.keyboard.press("i");
  const pot = () => window.__mu.player().inventory.filter((i) => i.templateId === "hp_potion_small");
  let stacks = await pa.evaluate(pot);
  const total = stacks.reduce((n, i) => n + i.quantity, 0);
  await pa.click(`[data-item="${stacks[0].id}"]`);
  await pa.fill('[data-test="split-qty"]', "1");
  await pa.click('[data-test="tooltip"] >> text=Tách');
  const split = await until(pa, (n) => window.__mu.player().inventory.filter((i) => i.templateId === "hp_potion_small").length === n + 1, stacks.length);
  check("P2", "tách stack potion qua tooltip [Tách]", split && total >= 2, `${total} potion`);
  stacks = await pa.evaluate(pot);
  const [a, b] = stacks.sort((x, y) => x.slot - y.slot);
  await pa.dragAndDrop(`[data-item="${b.id}"]`, `[data-bag-slot="${a.slot}"]`);
  const merged = await until(pa, () => window.__mu.player().inventory.filter((i) => i.templateId === "hp_potion_small").length === 1);
  check("P2", "kéo stack lên stack cùng loại → gộp (move_item)", merged);
  // nhịp người thật: nhóm lệnh đồ giới hạn rateLimit.cmd.categories.item (5 lệnh / giây)
  await pa.waitForTimeout(1100);
  const one = (await pa.evaluate(pot))[0];
  await pa.dragAndDrop(`[data-item="${one.id}"]`, `[data-bag-slot="40"]`);
  const moved = await until(pa, () => window.__mu.player().inventory.some((i) => i.templateId === "hp_potion_small" && i.slot === 40));
  check("P2", "kéo sang ô trống → chuyển ô (move_item)", moved);
  await pa.dragAndDrop(`[data-item="${one.id}"]`, '[data-test="trash"]');
  const asked = await pa.locator('[data-test="confirm-drop"]').isVisible();
  await pa.screenshot({ path: `${shots}/p2-inventory-drop.png` });
  await pa.click('[data-test="confirm-drop-yes"]');
  const dropped = await until(pa, () => !window.__mu.player().inventory.some((i) => i.templateId === "hp_potion_small"));
  check("P2", "kéo vào thùng rác → hỏi xác nhận → vứt xuống đất", asked && dropped);
  await pa.keyboard.press("Escape");
  // spawn của món vừa vứt tới sau reply của lệnh drop
  const onGround = await until(pa, () => window.__mu.entities().some((e) => e.kind === "item" && e.templateId === "hp_potion_small"));
  await pa.keyboard.press(" ");
  const back = await until(pa, (n) => window.__mu.player().inventory.some((i) => i.templateId === "hp_potion_small" && i.quantity === n), total);
  check("P2", "món vứt hiện dưới đất, nhặt lại đúng số lượng", onGround && back, `${total} potion`);
}

// 2. tạo DK qua UI (người B), 16. hai người thấy nhau
const ctxB = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const pb = await ctxB.newPage();
await pb.goto(base);
await pb.click("text=Chưa có tài khoản? Đăng ký");
await pb.fill('input[name="username"]', B.user);
await pb.fill('input[name="password"]', "matkhau123");
await pb.click('button[type="submit"]');
await pb.waitForSelector('input[name="name"]');
await pb.fill('input[name="name"]', B.char);
await pb.click('button[type="submit"]');
await pb.waitForSelector('[data-test="where"]');
const pB = await player(pb);
check(2, "tạo DK OK (qua UI: DK cấp 1, HP 185, MP 30)", pB.class === "DK" && pB.level === 1 && pB.view.hpMax === 185 && pB.view.mpMax === 30);
const aId = await pa.evaluate(() => window.__mu.selfId);
const aPos = await pos(pa);
const seesA = await until(pb, (id) => window.__mu.entities().some((e) => e.id === id), aId);
await clickTile(pa, 2, 1);
const sawMove = await until(pb, ([id, x, y]) => {
  const e = window.__mu.entities().find((q) => q.id === id);
  return e && e.x === x && e.y === y;
}, [aId, aPos.x + 2, aPos.y + 1], 5000);
check(16, "2 player login cùng lúc thấy nhau di chuyển", seesA && sawMove);
await pb.screenshot({ path: `${shots}/accept-two-players.png` });

// 4–6, 8: ra ngoài, đánh Spider (mặc giáp nên an toàn — Q14) tới khi có đồ rơi
await walkTo(pa, 25, 31);
await walkTo(pa, 40, 31);
check(4, "click-to-move OK (qua cổng ra (40,31))", JSON.stringify(await pos(pa)) === '{"x":40,"y":31}');
let kills = 0;
let drop = null;
const exp0 = (await player(pa)).experience;
const lv0 = (await player(pa)).level;
let firstKill = null;
// đánh tới khi (a) chính A lên cấp và (b) có đồ rơi để nhặt; người khác (vd. bot soak) có thể
// ra đòn cuối trước — khi đó A không được EXP (G24), không tính là A giết
const levelled = async () => (await player(pa)).level > lv0;
for (let round = 0; round < 60 && (!drop || !(await levelled())); round++) {
  const expBefore = (await player(pa)).experience + (await player(pa)).level * 100000;
  const target = await pa.evaluate(() => {
    const me = window.__mu.entities().find((e) => e.id === window.__mu.selfId);
    return window.__mu.entities()
      .filter((e) => e.kind === "monster" && e.state !== "dead")
      .map((e) => ({ id: e.id, x: e.x, y: e.y, d: Math.max(Math.abs(e.x - me.x), Math.abs(e.y - me.y)) }))
      .sort((a, b) => a.d - b.d)[0];
  });
  if (!target) { await pa.waitForTimeout(1000); continue; }
  const me = await pos(pa);
  if (target.d > 10) await walkTo(pa, target.x - 1, target.y, 6000);
  const me2 = await pos(pa);
  const t2 = await pa.evaluate((id) => window.__mu.entities().find((e) => e.id === id), target.id);
  if (!t2) continue;
  await clickTile(pa, t2.x - me2.x, t2.y - me2.y);
  if (!(await pa.waitForSelector('[data-test="ctxmenu"]', { timeout: 1500 }).catch(() => null))) continue;
  await pa.click("text=Tấn công thường");
  const died = await until(pa, (id) => { const s = window.__mu.entities().find((e) => e.id === id); return !s || s.state === "dead"; }, target.id, 25000);
  await pa.waitForTimeout(300);
  const mine = (await player(pa)).experience + (await player(pa)).level * 100000 !== expBefore;
  if (died && mine) {
    kills++;
    firstKill ??= { id: target.id, at: Date.now() };
  }
  drop ??= await pa.evaluate(() => window.__mu.entities().find((e) => e.kind === "item") ?? null);
  void me;
}
check(5, "click-to-attack Spider OK", kills > 0, `${kills} con`);
// Spider hồi sinh sau respawnSeconds (8 s): cùng id, còn sống, đầy máu
const respawned = firstKill && (await until(pa, (id) => {
  const s = window.__mu.entities().find((e) => e.id === id);
  return s && s.state !== "dead" && s.hp === s.maxHp;
}, firstKill.id, 15000));
check(6, "Spider chết + respawn OK", !!respawned, firstKill ? `${firstKill.id} sau ${((Date.now() - firstKill.at) / 1000).toFixed(1)} s` : "");
p = await player(pa);
check(7, "nhận EXP + lên level OK", p.level > lv0, `cấp ${lv0}→${p.level}, exp ${exp0}→${p.experience}`);
await pa.click('[data-tab="notices"]');
check(7, "thông báo Level up trong panel Thông báo", (await pa.textContent('[data-panel="notices"]')).includes(`Level ${lv0} → ${lv0 + 1}`));
await pa.screenshot({ path: `${shots}/accept-notices.png` });
await pa.keyboard.press("Escape");
if (drop) {
  const invBefore = (await player(pa)).view.inventoryUsed;
  await walkTo(pa, drop.x, drop.y, 8000);
  await pa.keyboard.press("Space");
  const picked = await until(pa, (n) => window.__mu.player().view.inventoryUsed > n || window.__mu.player().inventory.some((i) => i.quantity > 1), invBefore);
  check(9, "nhặt item OK (Space)", picked, drop.templateId);
} else {
  check(9, "nhặt item OK", false, `không có đồ rơi sau ${kills} con`);
}
await pa.screenshot({ path: `${shots}/accept-field.png` });

// 15. reload → trạng thái còn nguyên
const before = await player(pa);
await pa.reload();
await pa.click("text=Vào game");
await pa.waitForSelector('[data-test="where"]');
await pa.waitForTimeout(300);
const after = await player(pa);
const same = ["level", "experience", "zen", "vitality", "freeStatPoints"].every((k) => before[k] === after[k]) &&
  JSON.stringify(before.equipment.map((e) => e.id).sort()) === JSON.stringify(after.equipment.map((e) => e.id).sort()) &&
  before.inventory.length === after.inventory.length;
check(15, "reload page → character state còn nguyên", same, `cấp ${after.level}, exp ${after.experience}, zen ${after.zen}, đồ ${after.inventory.length}+${after.equipment.length}`);
check(0, "không lỗi JS trên trang", errorsA.length === 0, errorsA.join(" | "));

await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} PASS`);
console.log("JSON " + JSON.stringify(results));
process.exit(failed.length ? 1 : 0);
