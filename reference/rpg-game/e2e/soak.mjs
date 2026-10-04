// Soak test (FEATURE_CATALOG N3): N bot chơi cùng lúc qua WebSocket (giao thức Phoenix thô, không cần
// trình duyệt, không cần thư viện ngoài), X phút. Mỗi bot: đăng ký, tạo nhân vật, ra Rừng Mê đi lang
// thang đánh quái (uống bình khi máu thấp, thua thì quay lại), thỉnh thoảng chat / xem chợ / xếp hạng.
// Đo độ trễ trả lời lệnh (p50 / p95 / max), lỗi, mất kết nối, bộ nhớ server (nếu chạy cùng máy).
//
//   node e2e/soak.mjs [url]                    # mặc định 30 bot, 10 phút
//   SOAK_BOTS=5 SOAK_MINUTES=1 node e2e/soak.mjs
//
// Đạt khi: không lỗi giao thức / mất kết nối, p95 < SOAK_P95_MS (mặc định 150 ms). Chạy xong nên chạy
// `mix hac_long.audit` (vàng khớp nhật ký, không trùng đồ hiếm). Server cần TRUSTED_PROXIES=127.0.0.1
// (mỗi bot đăng ký từ một X-Forwarded-For riêng).
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

const L = createRequire(import.meta.url)('../priv/static/js/logic.js');
const BASE = process.argv[2] || process.env.HL_URL || 'http://localhost:4000';
const BOTS = +(process.env.SOAK_BOTS || 30);
const MINUTES = +(process.env.SOAK_MINUTES || 10);
const P95_MAX = +(process.env.SOAK_P95_MS || 150);
const ROUTE = ['village', 'forest_1'];

// dữ liệu game và mã phiên bản lấy từ trang chủ (như trình duyệt)
const html = await (await fetch(BASE + '/')).text();
const GD = JSON.parse(html.match(/window\.GAME_DATA = (.*?); window\.CLIENT_VERSION/s)[1]);
const VERSION = html.match(/window\.CLIENT_VERSION = "([^"]+)"/)[1];
const WALK = new Set(GD.WORLD.walkable);
const PORTAL = new Set(['D', 'A', 'O']);

const lat = [];
const stats = { cmds: 0, errors: 0, timeouts: 0, disconnects: 0, fights: 0, wins: 0, losses: 0, chats: 0, notOk: 0 };
const errs = new Map();
const note = (k) => errs.set(k, (errs.get(k) || 0) + 1);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rnd = (n) => Math.floor(Math.random() * n);
const ip = () => `10.${1 + rnd(250)}.${rnd(250)}.${1 + rnd(250)}`;

async function api(path, body, headers) {
  const res = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body || {}) });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${path} ${res.status} ${data.error || ''}`);
  return data;
}

// Kênh Phoenix (serializer v2: [join_ref, ref, topic, event, payload]).
function connect(ticket) {
  const url = BASE.replace(/^http/, 'ws') + `/socket/websocket?ticket=${encodeURIComponent(ticket)}&vsn=2.0.0`;
  const ws = new WebSocket(url);
  let ref = 0;
  const waiting = new Map();
  const ch = { ws, closed: false, player: null };
  ws.onmessage = (e) => {
    const [, r, , event, payload] = JSON.parse(e.data);
    if (event === 'phx_reply' && waiting.has(r)) { waiting.get(r)(payload); waiting.delete(r); }
    if (event === 'player' && payload.player) ch.player = payload.player;
  };
  ws.onclose = () => { if (!ch.closed) { stats.disconnects++; ch.closed = true; } };
  ch.push = (topic, event, payload, timeout = 10000) => new Promise((resolve) => {
    if (ws.readyState !== 1) return resolve({ status: 'closed' });
    const r = String(++ref);
    const t0 = performance.now();
    const timer = setTimeout(() => { waiting.delete(r); stats.timeouts++; resolve({ status: 'timeout' }); }, timeout);
    waiting.set(r, (p) => { clearTimeout(timer); if (topic === 'game') lat.push(performance.now() - t0); resolve(p); });
    ws.send(JSON.stringify([topic === 'game' ? '1' : null, r, topic, event, payload]));
  });
  ch.open = () => new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error('ws error')); });
  return ch;
}

async function bot(i, until) {
  const user = `sk${i}_${rnd(36 ** 6).toString(36)}`;
  const xff = { 'x-forwarded-for': ip() };
  const { token } = await api('/api/register', { username: user, password: 'password123' }, xff);
  const { ticket } = await api('/api/ws-ticket', {}, { authorization: 'Bearer ' + token, ...xff });
  const ch = connect(ticket);
  await ch.open();
  const join = await ch.push('game', 'phx_join', { v: VERSION });
  if (join.status !== 'ok') throw new Error('join ' + JSON.stringify(join));
  const hb = setInterval(() => ch.push('phoenix', 'heartbeat', {}), 25000);

  // gửi lệnh; lỗi giao thức (status error / timeout) tính là lỗi, lệnh bị từ chối hợp lệ (ok: false) thì không
  let p = null;
  const cmd = async (c) => {
    stats.cmds++;
    const r = await ch.push('game', 'cmd', c);
    if (r.status !== 'ok') { stats.errors++; note(`${c.act}: ${r.status} ${JSON.stringify(r.response || '').slice(0, 80)}`); return null; }
    if (r.response.player) p = r.response.player;
    if (r.response.ok === false) stats.notOk++;
    return r.response;
  };
  await cmd({ act: 'create', name: `S${i}x${rnd(1e5)}`, cls: ['dk', 'dw', 'elf', 'mg'][i % 4] });

  const blocked = (m, x, y, goal) => {
    const c = m.tiles[y] && m.tiles[y][x];
    if (c == null || !WALK.has(c)) return false;
    if (m.npcs.some((n) => n.at[0] === x && n.at[1] === y)) return false;
    return goal || !PORTAL.has(c);
  };
  while (Date.now() < until && !ch.closed && p) {
    if (p.battle && !p.battle.over) {
      const d = p.view.derived;
      const pots = ['potion_s', 'potion_m', 'potion_l'].some((k) => p.inv[k] > 0);
      await cmd({ act: p.hp < d.maxHp * 0.3 && pots ? 'potion' : 'attack' });
      if (p.battle && p.battle.over) {
        stats.fights++;
        if (p.battle.result === 'win') stats.wins++;
        if (p.battle.result === 'lose') stats.losses++;
      }
    } else if (p.battle) {
      await cmd({ act: 'leave' });
    } else {
      const here = p.pos.map;
      const m = GD.WORLD.maps[here];
      const next = here === 'home' ? 'village' : ROUTE[ROUTE.indexOf(here) + 1];
      let dir;
      if (next && m.portals.some((q) => q.to === next)) {
        const portal = m.portals.find((q) => q.to === next);
        dir = L.firstStep(p.pos.x, p.pos.y, portal.at[0], portal.at[1], (x, y, goal) => blocked(m, x, y, goal));
      }
      dir = dir || ['up', 'down', 'left', 'right'][rnd(4)];
      await cmd({ act: 'move', dir });
    }
    // việc phụ, thưa: chat, xem chợ, bảng xếp hạng
    const roll = Math.random();
    if (roll < 0.01) { stats.chats++; await ch.push('game', 'chat', { text: `bot ${i} chào` }); }
    else if (roll < 0.015) await ch.push('game', 'market', { q: '' });
    else if (roll < 0.02) await ch.push('game', 'leaderboard', {});
    await sleep(140 + rnd(120));
  }
  clearInterval(hb);
  ch.closed = true;
  ch.ws.close();
}

function beamMemory() {
  try {
    const out = execSync("ps -eo rss,args | grep '[b]eam.*phx.server' | awk '{s+=$1} END {print s}'").toString().trim();
    return out ? Math.round(+out / 1024) + ' MB' : 'không đo được';
  } catch { return 'không đo được'; }
}

const until = Date.now() + MINUTES * 60_000;
const mem0 = beamMemory();
console.log(`Soak: ${BOTS} bot × ${MINUTES} phút → ${BASE} (bộ nhớ server lúc đầu: ${mem0})`);
const started = Date.now();
const results = await Promise.allSettled(Array.from({ length: BOTS }, (_, i) => sleep(i * 150).then(() => bot(i, until))));
const crashed = results.filter((r) => r.status === 'rejected');
crashed.forEach((r) => note('bot: ' + String(r.reason && r.reason.message).slice(0, 120)));

lat.sort((a, b) => a - b);
const q = (k) => (lat.length ? lat[Math.min(lat.length - 1, Math.floor(lat.length * k))] : 0);
const secs = (Date.now() - started) / 1000;
console.log(`
Lệnh: ${stats.cmds} (${Math.round(stats.cmds / secs)}/s) · bị từ chối hợp lệ: ${stats.notOk}
Trận: ${stats.fights} (thắng ${stats.wins}, thua ${stats.losses}) · chat ${stats.chats}
Độ trễ: p50 ${q(0.5).toFixed(1)} ms · p95 ${q(0.95).toFixed(1)} ms · max ${(lat[lat.length - 1] || 0).toFixed(1)} ms
Lỗi: ${stats.errors} · quá giờ: ${stats.timeouts} · mất kết nối: ${stats.disconnects} · bot hỏng: ${crashed.length}
Bộ nhớ server: ${mem0} → ${beamMemory()}`);
for (const [k, n] of errs) console.log(`  ${n} × ${k}`);
const ok = stats.errors === 0 && stats.timeouts === 0 && stats.disconnects === 0 && crashed.length === 0 && q(0.95) < P95_MAX && stats.fights > 0;
console.log(ok ? `\nSOAK PASS (p95 < ${P95_MAX} ms, không lỗi)` : '\nSOAK FAIL');
process.exit(ok ? 0 : 1);
