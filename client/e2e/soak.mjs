// Soak test: N bot WebSocket chơi liên tục trên server thật (đi lang thang, đánh Spider, uống
// potion, mua potion ở NPC). In thống kê mỗi phút và tổng kết cuối. Không phải tính năng game.
//   node client/e2e/soak.mjs [baseUrl] [số_bot] [số_phút]
// Server cần TRUSTED_PROXIES=127.0.0.1: mỗi bot gửi X-Forwarded-For riêng (giả lập IP khác nhau,
// giới hạn đăng ký theo IP vẫn giữ nguyên).
const base = process.argv[2] ?? "http://localhost:4000";
const N = Number(process.argv[3] ?? 20);
const minutes = Number(process.argv[4] ?? 20);
const wsBase = base.replace(/^http/, "ws");
const stamp = Date.now() % 100000;
const stats = { cmds: 0, ok: 0, errors: {}, kills: 0, levelUps: 0, deaths: 0, potions: 0, buys: 0, closes: 0, snapGaps: [], joins: 0 };

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

  ws.onmessage = (m) => {
    const [, r, , ev, p] = JSON.parse(m.data);
    if (ev === "phx_reply" && waiting.has(r)) {
      waiting.get(r)(p);
      waiting.delete(r);
    } else if (ev === "spawn") ents.set(p.id, p);
    else if (ev === "despawn") ents.delete(p.id);
    else if (ev === "snapshot") {
      const now = Date.now();
      if (lastSnap && i === 0) stats.snapGaps.push(now - lastSnap);
      lastSnap = now;
      for (const e of p.entities) if (ents.has(e.id)) Object.assign(ents.get(e.id), e);
      for (const id of p.removed) ents.delete(id);
      if (selfId && ents.has(selfId)) me = ents.get(selfId);
    } else if (ev === "player") {
      if (player && p.level > player.level) stats.levelUps++;
      player = p;
    } else if (ev === "combat" && p.target === selfId && p.hp === 0) stats.deaths++;
  };
  ws.onclose = () => stats.closes++;
  await new Promise((res) => (ws.onopen = res));
  const join = await push("phx_join", { clientVersion: "0.1.0", characterId: c.id });
  stats.joins++;
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
    const spider = [...ents.values()].filter((e) => e.kind === "monster" && e.state !== "dead").sort((a, b) => cheb(a, me) - cheb(b, me))[0];
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
        if (!s) break;
        if (cheb(s, me) > 1) await cmd("move_to", { x: s.x + Math.sign(me.x - s.x), y: s.y + Math.sign(me.y - s.y) });
        else await cmd("attack", { target: spider.id });
        await sleep(player.view.cooldownMs + 20);
      }
      if (ents.get(spider.id)?.state === "dead") stats.kills++;
    } else {
      // đi lang thang (thiên về phía đông, nơi có Spider)
      for (let k = 0; k < 10; k++) {
        const x = me.x + Math.floor(Math.random() * 17) - 6;
        const y = me.y + Math.floor(Math.random() * 13) - 6;
        if (walkable(x, y)) {
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
const report = (label) => {
  const g = stats.snapGaps;
  console.log(
    `${label} | bot ${stats.joins}/${N} | cmd ${stats.cmds} (ok ${stats.ok}) lỗi ${JSON.stringify(stats.errors)} | giết ${stats.kills} lên cấp ${stats.levelUps} chết ${stats.deaths} potion ${stats.potions} mua ${stats.buys} | đóng WS ${stats.closes} | snapshot gap p50 ${pct(g, 50)} p99 ${pct(g, 99)} max ${Math.max(0, ...g)} ms`,
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
process.exit(0);
