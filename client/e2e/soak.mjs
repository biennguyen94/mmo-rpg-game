// Soak test: N bot WebSocket chơi liên tục trên server thật (đi lang thang, đánh Spider, uống
// potion, mua potion ở NPC). In thống kê mỗi phút và tổng kết cuối. Không phải tính năng game.
//   node client/e2e/soak.mjs [baseUrl] [số_bot] [số_phút] [tỉ_lệ_bot_ở_thị_trấn]
// Tỉ lệ thị trấn (0..1, mặc định 0): các bot này chỉ đi lại trong thị trấn, không săn — đo AOI
// khi người chơi phân tán (P3-M1): thị trấn và vùng Spider cách nhau hơn một ô AOI.
// Server cần TRUSTED_PROXIES=127.0.0.1: mỗi bot gửi X-Forwarded-For riêng (giả lập IP khác nhau,
// giới hạn đăng ký theo IP vẫn giữ nguyên).
const base = process.argv[2] ?? "http://localhost:4000";
const N = Number(process.argv[3] ?? 20);
const minutes = Number(process.argv[4] ?? 20);
const townBots = Math.round(N * Number(process.argv[5] ?? 0));
const wsBase = base.replace(/^http/, "ws");
const stamp = Date.now() % 100000;
// vùng sinh Spider ở Lorencia (priv/maps/lorencia.json) — bot soak chỉ săn ở đây
const SPIDER = { x0: 42, x1: 58, y0: 24, y1: 44 };
const stats = { cmds: 0, ok: 0, errors: {}, kills: 0, levelUps: 0, deaths: 0, potions: 0, buys: 0, closes: 0, snapGaps: [], joins: 0, killedBy: {}, bytesIn: 0, msgsIn: 0, town: { joins: 0, bytesIn: 0, msgsIn: 0 }, byEvent: {} };

async function http(method, path, body, token, ip) {
  const r = await fetch(base + path, {
    method,
    headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return r.json();
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));

async function bot(i) {
  const ip = `10.9.${Math.floor(i / 200)}.${(i % 200) + 1}`;
  const user = `soak${stamp}x${i}`;
  const token = (await http("POST", "/register", { username: user, password: "matkhau123" }, null, ip)).token;
  const c = (await http("POST", "/characters", { name: `S${stamp}x${i}` }, token, ip)).character;
  const ticket = (await http("POST", "/ws-ticket", null, token, ip)).ticket;

  const ws = new WebSocket(`${wsBase}/socket/websocket?vsn=2.0.0&ticket=${ticket}`);
  let ref = 1;
  const waiting = new Map();
  const ents = new Map();
  let me = null, selfId = null, player = null, map = null, lastSnap = 0;
  const push = (event, payload) =>
    new Promise((res) => {
      const r = String(++ref);
      waiting.set(r, res);
      ws.send(JSON.stringify(["1", r, "game", event, payload]));
    });
  const cmd = async (act, p = {}) => {
    stats.cmds++;
    const rep = await push("cmd", { act, rid: `${i}-${ref}`, ...p });
    if (rep.status === "ok") stats.ok++;
    else stats.errors[rep.response?.error ?? "?"] = (stats.errors[rep.response?.error ?? "?"] ?? 0) + 1;
    return rep.status === "ok";
  };

  const town = i < townBots;
  ws.onmessage = (m) => {
    stats.bytesIn += m.data.length;
    stats.msgsIn++;
    if (town) {
      stats.town.bytesIn += m.data.length;
      stats.town.msgsIn++;
    }
    if (process.env.SOAK_EVENTS) {
      const ev = `${town ? "town" : "hunt"}:${JSON.parse(m.data)[3]}`;
      stats.byEvent[ev] = (stats.byEvent[ev] ?? 0) + m.data.length;
    }
    const [, r, , ev, p] = JSON.parse(m.data);
    if (ev === "phx_reply" && waiting.has(r)) {
      waiting.get(r)(p);
      waiting.delete(r);
    } else if (ev === "spawn") ents.set(p.id, p);
    else if (ev === "despawn") ents.delete(p.id);
    else if (ev === "snapshot") {
      const now = Date.now();
      if (lastSnap && i === N - 1) stats.snapGaps.push(now - lastSnap);
      lastSnap = now;
      for (const e of p.entities) if (ents.has(e.id)) Object.assign(ents.get(e.id), e);
      for (const id of p.removed) ents.delete(id);
      if (selfId && ents.has(selfId)) me = ents.get(selfId);
    } else if (ev === "player") {
      if (player && p.level > player.level) stats.levelUps++;
      // hạ quái thật sự (chính bot ra đòn cuối) = EXP tăng (G24)
      if (player && (p.level > player.level || p.experience > player.experience)) stats.kills++;
      player = p;
    } else if (ev === "combat" && p.target === selfId) {
      // HP mới nhất của bot (event player chỉ gửi khi tiến độ đổi)
      player.hp = p.hp;
      if (p.hp === 0) {
        stats.deaths++;
        // loại quái ra đòn kết liễu (đo vùng nguy hiểm cho người mới)
        const k = ents.get(p.attacker)?.templateId ?? p.attacker;
        stats.killedBy[k] = (stats.killedBy[k] ?? 0) + 1;
      }
    }
  };
  ws.onclose = () => stats.closes++;
  await new Promise((res) => (ws.onopen = res));
  const join = await push("phx_join", { clientVersion: "0.1.0", characterId: c.id });
  stats.joins++;
  if (town) stats.town.joins++;
  selfId = join.response.entityId;
  player = join.response.player;
  map = join.response.map;
  me = { x: player.x, y: player.y };
  const walkable = (x, y) => map.tiles[y] && [".", ":", "="].includes(map.tiles[y][x]);

  const end = Date.now() + minutes * 60_000;
  while (Date.now() < end && ws.readyState === 1) {
    if (player.hp < player.view.hpMax * 0.5 && player.view.potions.HP > 0) {
      const pot = player.inventory.find((it) => it.templateId === "hp_potion_small");
      if (pot && (await cmd("use_item", { itemId: pot.id }))) stats.potions++;
    }
    if (town) {
      // bot thị trấn: đi lại trong thị trấn (x < 26)
      const x = 13 + Math.floor(Math.random() * 12);
      const y = 26 + Math.floor(Math.random() * 11);
      if (walkable(x, y)) await cmd("move_to", { x, y });
      await sleep(1500 + Math.random() * 1500);
      continue;
    }
    const spider = [...ents.values()].filter((e) => e.kind === "monster" && e.templateId === "spider" && e.state !== "dead").sort((a, b) => cheb(a, me) - cheb(b, me))[0];
    const r = Math.random();
    if (player.zen >= 100 && player.view.potions.HP < 3 && r < 0.2) {
      // về NPC mua potion
      await cmd("move_to", { x: 12, y: 26 });
      await sleep(4000);
      if (await cmd("buy", { npcId: "lorencia_potion_merchant", templateId: "hp_potion_small", quantity: 1 })) stats.buys++;
    } else if (spider && cheb(spider, me) <= 8 && r < 0.8) {
      // đánh tới khi quái chết hoặc 12 giây
      const t0 = Date.now();
      while (Date.now() - t0 < 12000 && ents.get(spider.id)?.state !== "dead" && ws.readyState === 1) {
        const s = ents.get(spider.id);
        if (!s || player.hp < player.view.hpMax * 0.5) break;
        if (cheb(s, me) > 1) await cmd("move_to", { x: s.x + Math.sign(me.x - s.x), y: s.y + Math.sign(me.y - s.y) });
        else await cmd("attack", { target: spider.id });
        await sleep(player.view.cooldownMs + 20);
      }
    } else {
      // đi lang thang thiên về phía đông; ra khỏi thị trấn thì ở trong vùng Spider như người chơi
      // cấp 1 thật (từ P2-M4 Lorencia có quái mạnh ở vùng khác — B-1)
      for (let k = 0; k < 10; k++) {
        const x = me.x + Math.floor(Math.random() * 17) - 6;
        const y = me.y + Math.floor(Math.random() * 13) - 6;
        const inSpider = x >= SPIDER.x0 && x <= SPIDER.x1 && y >= SPIDER.y0 && y <= SPIDER.y1;
        // dải đường từ cổng đông thị trấn (26,30–32) sang vùng Spider
        const onRoad = x >= 26 && x < SPIDER.x0 && y >= 28 && y <= 35;
        const outside = x >= 26 && !inSpider && !onRoad;
        if (walkable(x, y) && !outside) {
          await cmd("move_to", { x, y });
          break;
        }
      }
      await sleep(1500 + Math.random() * 1500);
    }
  }
  ws.close();
}

const pct = (xs, p) => {
  if (!xs.length) return 0;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))];
};
const rate = (bytes, msgs, joins) => {
  const secs = Math.max(1, (Date.now() - started) / 1000);
  return `${(bytes / 1024 / Math.max(1, joins) / secs).toFixed(2)} KB/s/bot (${(msgs / Math.max(1, joins) / secs).toFixed(1)} tin/s/bot)`;
};
const report = (label) => {
  const g = stats.snapGaps;
  const t = stats.town;
  const split = townBots
    ? ` [thị trấn ${t.joins}: ${rate(t.bytesIn, t.msgsIn, t.joins)}; săn ${stats.joins - t.joins}: ${rate(stats.bytesIn - t.bytesIn, stats.msgsIn - t.msgsIn, stats.joins - t.joins)}]`
    : "";
  console.log(
    `${label} | bot ${stats.joins}/${N} | cmd ${stats.cmds} (ok ${stats.ok}) lỗi ${JSON.stringify(stats.errors)} | hạ (đòn cuối) ${stats.kills} lên cấp ${stats.levelUps} chết ${stats.deaths} ${JSON.stringify(stats.killedBy)} potion ${stats.potions} mua ${stats.buys} | đóng WS ${stats.closes} | nhận ${rate(stats.bytesIn, stats.msgsIn, stats.joins)}${split} | snapshot gap p50 ${pct(g, 50)} p99 ${pct(g, 99)} max ${Math.max(0, ...g)} ms`,
  );
};

const started = Date.now();
const timer = setInterval(() => report(`[${((Date.now() - started) / 60000).toFixed(1)} phút]`), 60_000);
const bots = [];
for (let i = 0; i < N; i++) {
  bots.push(bot(i).catch((e) => console.log(`bot ${i} lỗi: ${e?.message ?? e}`)));
  await sleep(200);
}
await Promise.all(bots);
clearInterval(timer);
report("[TỔNG KẾT]");
if (process.env.SOAK_EVENTS) console.log("byte theo event:", JSON.stringify(stats.byEvent));
process.exit(0);
