// E2E bằng Playwright + Chromium headless: đi qua UI Phase 1 trên server thật, chụp ảnh
// desktop 1280px và mobile 360px. Chạy: node e2e/smoke.mjs [baseUrl] [thư_mục_ảnh]
// Playwright: dùng bản cài global nếu có (PLAYWRIGHT_MODULE ghi đè đường dẫn).
const pwPath = process.env.PLAYWRIGHT_MODULE ?? "/opt/node-tools/node_modules/playwright/index.mjs";
const { chromium } = await import(pwPath);

const base = process.argv[2] ?? "http://localhost:4000";
const shots = process.argv[3] ?? "../docs/screenshots";
const exe = process.env.CHROMIUM_PATH ?? "/opt/pw-browsers/chromium";
const results = [];
const check = (name, ok, extra = "") => {
  results.push({ name, ok });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${extra ? "  — " + extra : ""}`);
};

const browser = await chromium.launch({ executablePath: (await import("node:fs")).existsSync(exe) ? exe : undefined });
const user = `e2e${Date.now() % 1_000_000}`;
const charName = `E${Date.now() % 100_000_000}`;

async function hudPos(page) {
  const t = await page.textContent('[data-test="where"]');
  const m = t.match(/\((\d+),(\d+)\)/);
  return { x: +m[1], y: +m[2] };
}

// bấm vào ô (dx, dy) tính từ nhân vật (camera luôn giữ nhân vật ở giữa canvas)
async function clickTile(page, dx, dy) {
  // DEC-186: camera theo vị trí vẽ (trượt đều) → chờ vị trí vẽ bắt kịp vị trí server trước khi bấm
  await page
    .waitForFunction(
      () => {
        const me = window.__mu.entities().find((e) => e.id === window.__mu.selfId);
        const d = me && window.__mu.drawn(me.id);
        return !me || !d || (Math.abs(d.x - me.x) < 0.01 && Math.abs(d.y - me.y) < 0.01);
      },
      null,
      { timeout: 3000 }
    )
    .catch(() => null);
  const box = await page.locator('[data-test="game-canvas"]').boundingBox();
  await page.mouse.click(box.x + box.width / 2 + dx * 32, box.y + box.height / 2 + dy * 32);
  // bấm trúng người chơi khác (đông người, P3-M4) → menu người chơi: chọn "Đi tới đây"
  await (await page.$('[data-test="player-goto"]'))?.click();
}

async function waitPos(page, x, y, ms = 8000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const p = await hudPos(page);
    if (p.x === x && p.y === y) return true;
    await page.waitForTimeout(100);
  }
  return false;
}

// ---------- Desktop 1280 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await ctx.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
  await page.goto(base);

  await page.click("text=Chưa có tài khoản? Đăng ký");
  await page.fill('input[name="username"]', user);
  await page.fill('input[name="password"]', "matkhau123");
  await page.click('button[type="submit"]');
  await page.waitForSelector('input[name="name"]');
  check("đăng ký → màn tạo nhân vật", true);
  await page.screenshot({ path: `${shots}/desktop-01-create.png` });

  await page.fill('input[name="name"]', charName);
  await page.click('button[type="submit"]');
  await page.waitForSelector('[data-test="where"]');
  const start = await hudPos(page);
  check("tạo DK → vào Lorencia", (await page.textContent('[data-test="where"]')).startsWith("Lorencia"), JSON.stringify(start));
  check("không panel nào mở khi vào", (await page.locator(".panel").count()) === 0);
  await page.waitForTimeout(500);
  await page.screenshot({ path: `${shots}/desktop-02-world.png` });

  await clickTile(page, 3, 0);
  check("click-to-move: đi 3 ô sang phải", await waitPos(page, start.x + 3, start.y), JSON.stringify(await hudPos(page)));

  await page.keyboard.press("c");
  check("phím C mở panel Nhân vật", await page.locator('[data-panel="character"]').isVisible());
  const hpText = await page.textContent('[data-panel="character"]');
  check("panel Nhân vật hiện số server (Dmg 4 ~ 7, HP 185 / 185)", hpText.includes("4 ~ 7") && hpText.includes("185 / 185"));
  await page.screenshot({ path: `${shots}/desktop-03-character.png` });
  await page.keyboard.press("Escape");
  check("Esc đóng panel", (await page.locator(".panel").count()) === 0);

  await page.keyboard.press("i");
  check("phím I mở Túi đồ", await page.locator('[data-panel="inventory"]').isVisible());
  check("túi rỗng: lưới 8×8 + chữ \"Túi trống\"", (await page.locator('[data-bag-slot]').count()) === 64 && (await page.textContent('[data-panel="inventory"]')).includes("Túi trống"));
  await page.screenshot({ path: `${shots}/desktop-04-inventory.png` });
  await page.click('[data-tab="inventory"]');
  check("bấm lại tab đóng panel", (await page.locator(".panel").count()) === 0);

  await page.click('[data-tab="menu"]');
  check("tab Menu mở submenu (Cài đặt, Đăng xuất)", (await page.textContent('[data-test="submenu"]')).includes("Đăng xuất"));
  await page.screenshot({ path: `${shots}/desktop-05-menu.png` });
  await page.click('[data-tab="menu"]');

  // tới NPC (11,25) rồi bấm NPC → shop
  await clickTile(page, 12 - (start.x + 3), 26 - start.y);
  await waitPos(page, 12, 26);
  await clickTile(page, -1, -1);
  await page.waitForSelector('[data-panel="shop"]', { timeout: 5000 }).catch(() => null);
  check("bấm NPC → panel Shop (giá 100 Zen)", (await page.locator('[data-panel="shop"]').count()) === 1 && (await page.textContent('[data-panel="shop"]')).includes("100 Zen"));
  await page.screenshot({ path: `${shots}/desktop-06-shop.png` });
  await page.click('[data-buy="hp_potion_small"]');
  await page.waitForTimeout(400);
  await page.keyboard.press("Escape");
  await page.click('[data-tab="notices"]');
  check("mua thiếu Zen → thông báo lỗi trong panel Thông báo", (await page.textContent('[data-panel="notices"]')).includes("Không đủ Zen"));
  await page.screenshot({ path: `${shots}/desktop-07-notices.png` });
  await page.keyboard.press("Escape");

  // ra vùng Spider: tới cổng đông (25,31) rồi ra (40,31) — mỗi lần bấm trong tầm nhìn
  await clickTile(page, 25 - 12, 31 - 26);
  await waitPos(page, 25, 31, 8000);
  await clickTile(page, 15, 0);
  check("đi qua cổng thị trấn ra ngoài (40,31)", await waitPos(page, 40, 31, 8000), JSON.stringify(await hudPos(page)));
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${shots}/desktop-08-field.png` });

  // click Spider → context menu → Tấn công thường → tự đánh (client gửi attack theo cooldown).
  // Đông người (chạy cùng soak) có thể bị người khác ra đòn cuối / hết Spider: tối đa 6 lượt tới khi có EXP
  const nearestSpider = () =>
    page.evaluate(() => {
      const me = window.__mu.entities().find((e) => e.id === window.__mu.selfId);
      return window.__mu
        .entities()
        .filter((e) => e.kind === "monster" && e.templateId === "spider" && e.state !== "dead")
        .map((e) => ({ id: e.id, x: e.x, y: e.y, d: Math.max(Math.abs(e.x - me.x), Math.abs(e.y - me.y)) }))
        .sort((a, b) => a.d - b.d)[0];
    });
  let hit = false;
  let dead = false;
  let menuOk = false;
  const rounds = [];
  for (let round = 0; round < 6; round++) {
    const spider = await nearestSpider();
    // hết Spider sống trong tầm nhìn (bị đánh hết): chờ hồi sinh
    if (!spider) {
      await page.waitForTimeout(3000);
      continue;
    }
    const me = await hudPos(page);
    await clickTile(page, spider.x - me.x, spider.y - me.y);
    const menu = await page.waitForSelector('[data-test="ctxmenu"]', { timeout: 3000 }).catch(() => null);
    const ok = !!menu && (await menu.textContent()).includes("Tấn công thường");
    if (round === 0) {
      menuOk = ok;
      await page.screenshot({ path: `${shots}/desktop-09-ctxmenu.png` });
    }
    if (!ok) continue;
    await page.click("text=Tấn công thường");
    hit ||= await page
      .waitForFunction((id) => { const s = window.__mu.entities().find((e) => e.id === id); return !s || s.hp < 30; }, spider.id, { timeout: 20000 })
      .then(() => true)
      .catch(() => false);
    if (round === 0) await page.screenshot({ path: `${shots}/desktop-10-fight.png` });
    dead ||= await page
      .waitForFunction((id) => { const s = window.__mu.entities().find((e) => e.id === id); return !s || s.state === "dead"; }, spider.id, { timeout: 30000 })
      .then(() => true)
      .catch(() => false);
    await page.waitForTimeout(500);
    rounds.push(`${spider.id}:${ok ? "menu" : "nomenu"}`);
    if ((await page.evaluate(() => window.__mu.player().experience)) > 0) break;
  }
  check("click Spider → context menu (Tấn công thường / Hủy)", menuOk);
  check("tự đánh: Spider mất máu", hit);
  check("tự đánh tới khi Spider chết", dead);
  const p = await page.evaluate(() => window.__mu.player());
  check("nhận EXP + Zen (player từ server)", p.experience >= 10 && p.zen > 0, `exp=${p.experience} zen=${p.zen} hp=${p.hp} lượt ${rounds.join(",")}`);
  // bỏ đánh, quay về thị trấn cho an toàn
  await clickTile(page, -8, 0);

  check("không lỗi JS trên trang", errors.length === 0, errors.join(" | "));
  await ctx.close();
}

// ---------- Mobile 360 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 360, height: 740 }, hasTouch: true, isMobile: true });
  const page = await ctx.newPage();
  await page.goto(base);
  await page.fill('input[name="username"]', user);
  await page.fill('input[name="password"]', "matkhau123");
  await page.click('button[type="submit"]');
  await page.click("text=Vào game");
  await page.waitForSelector('[data-test="where"]');
  await page.waitForTimeout(500);
  const back = await hudPos(page);
  check("mobile: đăng nhập lại → vào lại được, vị trí từ server", back.x > 0, JSON.stringify(back));
  check("mobile: hiện 3 nút 🧪 💧 ✋", await page.locator('[data-mobile="hp"]').isVisible());
  const noHScroll = await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth);
  check("mobile: không tràn ngang ở 360px", noHScroll);
  await page.screenshot({ path: `${shots}/mobile-01-world.png` });
  await page.locator('[data-tab="character"]').tap();
  check("mobile: panel mở → ẩn nút mobile", !(await page.locator('[data-mobile="hp"]').isVisible()));
  await page.screenshot({ path: `${shots}/mobile-02-character.png` });
  await page.locator('[data-tab="inventory"]').tap();
  await page.screenshot({ path: `${shots}/mobile-03-inventory.png` });
  check("mobile: chuyển tab → chỉ 1 panel", (await page.locator(".panel").count()) === 1);
  await ctx.close();
}

await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} PASS`);
process.exit(failed.length ? 1 : 0);
