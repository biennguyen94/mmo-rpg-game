/* Vẽ bản đồ ô vuông lên canvas và tìm đường khi chạm vào một ô.
 * Chỉ hiển thị: vị trí thật do server quyết định (mỗi bước gửi lên, server kiểm tra rồi trả về).
 * Dữ liệu bản đồ tĩnh ở GAME_DATA.WORLD; quái và người chơi khác đến từ sự kiện "map" của server. */
(function () {
  const { WORLD, ZONES } = window.GAME_DATA;
  const SECRET = (window.GAME_DATA.RULES || {}).secret || {};
  const CS = (window.GAME_DATA.RULES || {}).castleSiege || {};
  const TILE = 32;
  const WALK = new Set(WORLD.walkable);
  const PORTAL = new Set(['D', 'A', 'O']);
  // loại ô → hình (assets/tiles/*.png); nền "." dùng hình `floor` của từng bản đồ
  const GROUND = { grass: 1, dirt: 1, flowers: 1, sand: 1 };

  // cấp của từng loại quái, để tô màu độ khó
  const LEVEL = {}, NAME = {};
  ZONES.forEach((z) => { z.monsters.concat([z.boss]).forEach((m) => { LEVEL[m.id] = m.level; NAME[m.id] = m.name; }); });
  // quái bản đồ phụ chỉ có trong LIBRARY
  (((window.GAME_DATA || {}).LIBRARY || {}).monsters || []).forEach((m) => { if (!(m.id in LEVEL)) { LEVEL[m.id] = m.level; NAME[m.id] = m.name; } });

  const images = {};
  let canvas = null, ctx = null, mounted = null, getPlayer = () => null;
  let fight = null; // ⚡ Đánh nhanh: { id, hp } con đang đánh (`setFight`)
  const seenTower = new Map(); // mã quái tầng → lần thấy cuối (vẽ con đang đánh khi nó tạm vắng khỏi danh sách)
  let world = { map: null, monsters: [], players: [] };
  let playersTimer = null;
  let userId = null;
  // quan hệ với người chơi khác (đồng đội, bang, bang địch) để tô màu tên; ui.js đặt qua setRelations
  let relations = () => ({});
  let boss = { alive: false }; // trùm thế giới (HacLong.WorldBoss)
  // hiệu ứng di chuyển (docs/FX_PLAN.md): dấu bước chân, ô đích vừa chạm, lúc sang bản đồ mới
  let steps = [], lastTile = null, mark = null, arrive = 0;
  let lake = null, school = null; // Long Vương đang nổi / Đàn Cá Vàng (HacLong.LakeEvent): { x, y, until }
  // Đồi Sáo Diều (HacLong.SkyEvent): Chim Lạc, Đàn Hạc { x, y, until }, Mảnh Sao [[x, y]], Long Phượng Hội { at, until, radius }
  let skyEv = { bird: null, flock: null, stars: [], hoi: null };
  // FX đợt 3 (hướng C): quái trên bản đồ bị đánh (máu tụt: tia chém) / gục (tan thành hạt); suy ra từ sự kiện "map"
  let mobFx = [];
  let levelAt = 0; // vừa lên cấp: cột sáng vàng ở chỗ nhân vật (FX_PLAN đợt 4)
  // B4 (DECISIONS "Bản đồ đẹp hơn"): vừa vào bản đồ (`enter.at`): mở dần từ tối + xoáy sáng, tên bản đồ to giữa màn
  let enter = { map: null, at: 0 };
  // B7: dấu chân lâu trên tuyết / cát (5 giây), cỏ bắn lên khi bước qua bụi cỏ, gợn nước khi đứng ven hồ
  let prints = [], rustle = [], stillSince = 0;
  const Doll = window.Doll;
  Doll.onReady(() => draw());

  // ---------- Di chuyển mượt ----------
  // Server gửi vị trí theo ô; khi vẽ thì trượt từ ô cũ sang ô mới trong `dur` ms.
  // Nhảy xa hơn một ô (dịch chuyển, qua cổng) thì hiện ngay ở chỗ mới.
  const anim = new Map();
  let frame = null, lastCam = [0, 0];
  const DUR = { me: 130, player: 160, monster: 380 };

  // Bong bóng lời nói trên đầu nhân vật (chat), hiện vài giây.
  const bubbles = new Map();
  const BUBBLE_MS = 6000;
  let bubbleTimer = null, tutTimer = null;

  function bubble(text, cx, py) {
    ctx.font = '500 11px "Be Vietnam Pro", system-ui, sans-serif';
    let t = text;
    while (ctx.measureText(t).width > 170 && t.length > 4) t = t.slice(0, -2);
    if (t !== text) t = t.slice(0, -1) + '…';
    const w = ctx.measureText(t).width + 12, x = Math.round(cx - w / 2), y = py - 34;
    ctx.fillStyle = 'rgba(246, 240, 226, 0.95)';
    ctx.beginPath(); ctx.roundRect(x, y, w, 18, 6); ctx.fill();
    ctx.beginPath(); ctx.moveTo(cx - 4, y + 18); ctx.lineTo(cx + 4, y + 18); ctx.lineTo(cx, y + 23); ctx.fill();
    ctx.fillStyle = '#1b1422';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(t, cx, y + 9.5);
  }

  function bubbleOf(uid, now) {
    const b = bubbles.get(uid);
    if (!b) return null;
    if (b.until < now) { bubbles.delete(uid); return null; }
    return b.text;
  }

  function smooth(key, x, y, dur, now) {
    let a = anim.get(key);
    if (!a || Math.abs(a.tx - x) + Math.abs(a.ty - y) > 1) {
      a = { fx: x, fy: y, tx: x, ty: y, t0: now, dur };
      anim.set(key, a);
    } else if (a.tx !== x || a.ty !== y) {
      const [cx, cy] = at(a, now);
      Object.assign(a, { fx: cx, fy: cy, tx: x, ty: y, t0: now, dur });
    }
    a.seen = now;
    return at(a, now);
  }

  function at(a, now) {
    const k = Math.min(1, (now - a.t0) / a.dur);
    if (k < 1 && !frame) frame = requestAnimationFrame(() => { frame = null; draw(); });
    return [a.fx + (a.tx - a.fx) * k, a.fy + (a.ty - a.fy) * k];
  }

  function image(path) {
    if (!images[path]) {
      const im = new Image();
      im.onload = () => draw();
      im.src = 'assets/' + path + '.png';
      images[path] = im;
    }
    return images[path];
  }

  const mapOf = (id) => WORLD.maps[id];
  const tileAt = (m, x, y) => (y >= 0 && y < m.tiles.length && x >= 0 && x < m.tiles[0].length ? m.tiles[y][x] : null);
  const portalAt = (m, x, y) => m.portals.find((p) => p.at[0] === x && p.at[1] === y);
  // Phòng sự kiện đánh chung (HacLong.EventRoom): nhãn phòng + số người; số quái mình hạ (`mine`, `killed` là của cả phòng)
  const roomTag = (t) => (t.room ? ` · Phòng ${t.room_label || ''} · ${t.people || 1} người` : '');
  const roomMine = (e) => (e.mine != null ? ` (bạn hạ ${e.mine})` : '');
  // Tầng Tháp Vô Tận không có trong WORLD: dựng từ trạng thái nhân vật (P.tower).
  function cur(P) {
    if (P.pos.map !== 'tower' || !P.tower) return mapOf(P.pos.map);
    const t = P.tower;
    // Quảng Trường Quỷ (Phase 18 M1) chạy trên trạng thái tháp (`t.ds`): nền vùng cuối, tên theo đợt
    // Lâu Đài Máu (Phase 18 M2): `t.bc`, tên theo bước
    const BC_STAGE = { guards: 'Hạ quân canh', gate: 'Phá Cổng Thành', boss: 'Hạ Hiệp Sĩ Máu', done: 'Hoàn thành' };
    const zi = t.ds || t.bc || t.kal ? ZONES.length - 1 : Math.floor((t.floor - 1) / 10) % ZONES.length;
    const KAL_STAGE = { guards: 'Hạ quái Kalima', boss: 'Hạ Kundun', done: 'Hoàn thành' };
    const name = t.kal ? `Kalima ${t.kal.n} · ${KAL_STAGE[t.kal.stage] || ''}` : t.bc ? `Lâu Đài Máu · ${BC_STAGE[t.bc.stage] || ''}` : t.ds ? `Quảng Trường Quỷ · Đợt ${t.floor}/${t.ds.waves}` : `Tháp Vô Tận · Tầng ${t.floor}`;
    // Phase 6: tầng 61+ dùng nền vùng đất chuyển sinh (server gửi `theme`)
    return { name, zone: null, floor: (!t.ds && !t.bc && !t.kal && t.theme) || 'floors/' + ZONES[zi].id, tiles: t.tiles, portals: [], npcs: [], tower: t };
  }

  // Quái trên bản đồ đang đứng: quái dùng chung (sự kiện "map") hoặc quái của tầng tháp (máu phần trăm ở `hp_pct`).
  function mobs(P) {
    const list = P.pos.map === 'tower' && P.tower
      ? P.tower.monsters.map((q) => Object.assign({}, q, { id: 't' + q.id, boss: q.elite, hp: q.hp_pct == null ? 100 : q.hp_pct }))
      : world.map === P.pos.map ? world.monsters : [];
    // nhớ chỗ đứng cuối của quái tầng tháp / sự kiện: con đang đánh bị bỏ khỏi danh sách tầng suốt trận
    if (P.pos.map === 'tower') for (const q of list) seenTower.set(String(q.id), q);
    // ⚡ Đánh nhanh: con đang đánh (ở lại bản đồ) hiện máu theo lượt và dấu ⚔, cả quái tầng tháp / sự kiện (máu chỉ có ở trận)
    if (!fight) return list;
    const mark = (q) => Object.assign({}, q, { hp: fight.hp, busy: true, mine: true });
    if (list.some((q) => String(q.id) === fight.id)) return list.map((q) => (String(q.id) === fight.id ? mark(q) : q));
    const last = P.pos.map === 'tower' && seenTower.get(fight.id);
    return last ? list.concat([mark(last)]) : list;
  }
  // vị trí trên màn hình (px CSS) của con đang đánh và của mình, để hiệu ứng trận (js/fx.js) bám vào bản đồ
  let spots = null;
  // vị trí con đang đánh lần gần nhất: trận xong / quái vừa bị xóa khỏi bản đồ trước khi hiệu ứng kỹ năng bay tới thì
  // vẫn bay tới đúng chỗ (giữ ~1,5 giây)
  let lastFight = null;
  function fightSpots() {
    const live = (() => {
      if (!canvas || !spots || !fight) return null;
      const r = canvas.getBoundingClientRect();
      if (!r.width) return null;
      const k = r.width / VW(), sz = TILE * k;
      const at = (p) => (p ? { x: r.left + p[0] * k, y: r.top + (p[1] + TILE / 2) * k, w: sz, h: sz } : null);
      return { mon: at(spots.mpos[fight.id]), me: at(spots.me) };
    })();
    if (live && live.mon) { lastFight = { ...live, t: performance.now() }; return live; }
    if (lastFight && performance.now() - lastFight.t < 1500) return { mon: lastFight.mon, me: (live && live.me) || lastFight.me };
    return live;
  }
  // ---------- Người chơi khác trên bản đồ (DECISIONS "Người chơi trên bản đồ, Đồ sát nhanh") ----------
  // Cài đặt (máy này): 'all' tất cả, 'team' chỉ tổ đội & bang, 'off' tắt. Dù chọn gì vẫn vẽ: người đang đồ sát với
  // mình, đồng đội tổ đội, người vừa bấm 📍 ở Quanh đây. Ưu tiên: các người trên → tổ đội / bang → tên đỏ → gần nhất;
  // tối đa theo vùng đang thấy (8–30). Cùng một ô: vẽ lệch như quạt tối đa 3 người, còn lại "+N".
  const PSTACK = 3;
  let drawnP = []; // người đang vẽ (để bấm): { o, x, y }
  let pinned = null; // 📍 { id, until }
  const playersMode = () => { try { return localStorage.getItem('hl-players') || 'all'; } catch (e) { return 'all'; } };
  function visiblePlayers(P) {
    const all = world.map === P.pos.map ? world.players.filter((o) => o.id !== userId) : [];
    const rel = relations() || {};
    const party = rel.party || [], foe = fight && fight.id[0] === 'p' ? +fight.id.slice(1) : null;
    const t = performance.now(), mode = playersMode();
    const team = (o) => party.includes(o.id) || (rel.tag && o.tag === rel.tag);
    const must = (o) => o.id === foe || party.includes(o.id) || (pinned && pinned.id === o.id && t < pinned.until) || (o.duel && o.duel.with === userId);
    const d = (o) => Math.abs(o.x - P.pos.x) + Math.abs(o.y - P.pos.y);
    const rank = (o) => (must(o) ? 0 : team(o) ? 1 : o.red ? 2 : 3);
    const list = all.filter((o) => must(o) || mode === 'all' || (mode === 'team' && team(o)))
      .sort((a, b) => rank(a) - rank(b) || d(a) - d(b));
    const cap = Math.max(8, Math.min(30, Math.round(((VW() / TILE) * (VH() / TILE)) / 10)));
    return list.filter((o, i) => must(o) || i < cap);
  }
  function drawPlayers(P, now, cx, cy, labels, mpos, fx) {
    const list = visiblePlayers(P), rel = relations() || {}, groups = new Map(), placed = [];
    const t = performance.now();
    const cs = P.view && P.view.cs, csOn = mapOf(P.pos.map) && mapOf(P.pos.map).event === 'castle_siege' && cs && cs.phase === 'fight';
    const csHolder = csOn && cs.holder ? cs.holder.tag : null;
    if (fx && rel.enemy && list.some((o) => o.tag === rel.enemy) && !tutTimer) tutTimer = setTimeout(() => { tutTimer = null; draw(); }, 120);
    drawnP = [];
    for (const o of list) {
      const key = o.x + ',' + o.y, g = groups.get(key) || [];
      g.push(o); groups.set(key, g);
      drawnP.push({ o, x: o.x, y: o.y });
      const [sx, sy] = smooth('p' + o.id, o.x, o.y, DUR.player, now);
      const px = Math.round(sx * TILE - cx), py = Math.round(sy * TILE - cy);
      const i = g.length - 1, off = i === 0 ? 0 : i === 1 ? -7 : 7;
      mpos['p' + o.id] = [px + TILE / 2 + (i < PSTACK ? off : 0), py];
      if (i >= PSTACK || px < -TILE || py < -TILE || px > VW() || py > VH()) continue;
      const pin = pinned && pinned.id === o.id && t < pinned.until;
      const mine = fight && fight.id === 'p' + o.id;
      if (pin) {
        const k = (Math.sin(t / 160) + 1) / 2;
        ctx.strokeStyle = `rgba(240, 207, 122, ${0.5 + k * 0.5})`; ctx.lineWidth = 3;
        ctx.beginPath(); ctx.arc(px + TILE / 2 + off, py + TILE / 2, TILE * (0.6 + k * 0.15), 0, Math.PI * 2); ctx.stroke();
      }
      ctx.fillStyle = 'rgba(0, 0, 0, 0.28)';
      ctx.beginPath(); ctx.ellipse(px + TILE / 2 + off, py + TILE - 4, 11, 4, 0, 0, Math.PI * 2); ctx.fill();
      // D2: Công Thành Chiến — vòng dưới chân theo màu bang; F1: người bang địch (chiến bang) — vòng đỏ nhấp nháy
      const enemy = rel.enemy && o.tag === rel.enemy;
      if ((csOn && o.tag) || enemy) {
        const k = 0.5 + 0.5 * Math.sin(t / 200);
        ctx.strokeStyle = enemy ? `rgba(255, 70, 50, ${0.55 + 0.45 * k})` : csHolder && o.tag === csHolder ? '#ffd24a' : guildCol(o.tag);
        ctx.lineWidth = enemy ? 2.5 : 2;
        ctx.beginPath(); ctx.ellipse(px + TILE / 2 + off, py + TILE - 4, 13 + (enemy ? k * 2 : 0), 5, 0, 0, Math.PI * 2); ctx.stroke();
      }
      const dl = window.Doll && Doll.canvas(o.look);
      if (dl) ctx.drawImage(dl, px + off, py, TILE, TILE);
      // đang đồ sát: máu trên đầu (con mình đang đánh: máu theo lượt của trận; người ngoài: máu người đó gửi lên)
      const hp = mine ? fight.hp : o.duel ? o.duel.hp : null;
      if (hp != null) {
        const bw = TILE - 6, k = Math.max(0, Math.min(100, hp)) / 100;
        ctx.fillStyle = 'rgba(12,9,16,0.85)'; ctx.fillRect(px + off + 3, py + TILE + 1, bw, 5);
        ctx.fillStyle = '#d9483b'; ctx.fillRect(px + off + 4, py + TILE + 2, Math.max(0, (bw - 2) * k), 3);
        if (fx && Math.sin(t / 220) > 0) { ctx.font = '700 12px system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'bottom'; ctx.fillStyle = '#ef6a5a'; ctx.fillText('⚔', px + TILE + off - 4, py + 10); }
      }
      // tên: không đè lên tên đã vẽ (trừ người đang đồ sát với mình / vừa 📍) → chấm nhỏ
      const name = (csOn && csHolder && o.tag === csHolder ? '👑 ' : '') + (o.safe ? '🛡 ' : '') + (o.duel || mine || enemy ? '⚔ ' : '') + (o.tag ? `[${o.tag}] ` : '') + o.name;
      const col = window.HLLogic ? window.HLLogic.nameColor(o, rel) : '#f1e6cf';
      const lx = px + TILE / 2 + off, ly = py - 13, w = name.length * 5.6 + 10;
      const r = [lx - w / 2, ly - 8, w, 14];
      const hit = placed.some((q) => r[0] < q[0] + q[2] && q[0] < r[0] + r[2] && r[1] < q[1] + q[3] && q[1] < r[1] + r[3]);
      if (!hit || mine || pin) { placed.push(r); labels.push([name, lx, ly, col]); }
      else { ctx.fillStyle = col; ctx.beginPath(); ctx.arc(lx, py - 4, 2.5, 0, Math.PI * 2); ctx.fill(); }
    }
    // cùng ô quá 3 người: huy hiệu "+N" ở góc ô
    for (const g of groups.values()) {
      if (g.length <= PSTACK) continue;
      const p0 = mpos['p' + g[0].id];
      if (!p0) continue;
      const x = p0[0] + TILE / 2 - 4, y = p0[1] + 4, txt = `+${g.length - PSTACK}`;
      ctx.font = '800 10px system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillStyle = 'rgba(12,9,16,0.85)'; ctx.beginPath(); ctx.arc(x, y, 8, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = '#f0cf7a'; ctx.fillText(txt, x, y);
    }
    if (pinned && t < pinned.until && !tutTimer) tutTimer = setTimeout(() => { tutTimer = null; draw(); }, 60);
  }
  // ---------- Sự kiện trực quan (DECISIONS "Sự kiện, đấu trường, chiến bang trực quan") ----------
  // màu bang theo tên tắt (Công Thành Chiến: vòng dưới chân mỗi bang một màu; bang giữ Vương Miện màu vàng)
  function guildCol(tag) {
    let h = 0;
    for (const ch of String(tag || '')) h = (h * 31 + ch.charCodeAt(0)) % 360;
    return `hsl(${h}, 75%, 60%)`;
  }
  function crownGlow(px, py, t) {
    const k = t ? 0.5 + 0.5 * Math.sin(t / 260) : 0.7, x = px + TILE / 2, y = py + TILE / 2;
    const g = ctx.createRadialGradient(x, y, 2, x, y, TILE * 1.4);
    g.addColorStop(0, `rgba(255, 215, 90, ${0.35 + 0.25 * k})`); g.addColorStop(1, 'rgba(255, 215, 90, 0)');
    ctx.fillStyle = g; ctx.fillRect(x - TILE * 1.4, y - TILE * 1.4, TILE * 2.8, TILE * 2.8);
    ctx.font = '16px system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'bottom';
    ctx.fillText('👑', x, py - 18 - k * 4);
  }
  // điểm (gx, gy) (px trên khung) bị khuất: mũi tên ở mép khung chỉ về phía đó (kèm biểu tượng nhỏ)
  function edgeArrow(gx, gy, rgb, t, icon) {
    const vw = VW(), vh = VH(), pad = 18;
    if (gx >= 0 && gy >= 0 && gx <= vw && gy <= vh) return;
    const k = t ? (Math.sin(t / 250) + 1) / 2 : 1;
    const ex = Math.max(pad, Math.min(vw - pad, gx)), ey = Math.max(pad + hudH, Math.min(vh - pad, gy));
    const ang = Math.atan2(gy - vh / 2, gx - vw / 2);
    ctx.save(); ctx.translate(ex, ey); ctx.rotate(ang);
    ctx.fillStyle = `rgba(${rgb}, ${0.6 + k * 0.4})`;
    ctx.beginPath(); ctx.moveTo(12, 0); ctx.lineTo(-8, -9); ctx.lineTo(-8, 9); ctx.fill();
    ctx.restore();
    if (icon) {
      ctx.font = '14px system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(icon, ex - Math.cos(ang) * 20, ey - Math.sin(ang) * 20);
    }
    if (t && !tutTimer) tutTimer = setTimeout(() => { tutTimer = null; draw(); }, 60);
  }
  const mmss = (s) => { const v = Math.max(0, Math.round(s)); return `${Math.floor(v / 60)}:${String(v % 60).padStart(2, '0')}`; };
  // thanh sự kiện ở đáy bản đồ: mỗi dòng { text, k (0..1 thanh tiến độ), col, k2 / col2 (thanh chia đôi), sub }
  function hudLines(P, m) {
    const L = [], t = m.tower, now = Date.now() / 1000;
    const ppl = t && t.room ? ` · 👥 ${t.people || 1}` : '';
    const hpOf = (q) => (q ? (q.hp_pct == null ? 100 : q.hp_pct) / 100 : 0);
    if (t && t.ds) {
      const k = (t.floor - 1 + (t.monsters.length ? 0 : 1)) / Math.max(1, t.ds.waves);
      L.push({ text: `🌊 Đợt ${t.floor}/${t.ds.waves} · ${t.ds.score} điểm · ${t.monsters.length ? `còn ${t.monsters.length} quái` : 'cầu thang mở'} · ${mmss(t.ds.ends_at - now)}${ppl}`, k, col: '#ef6a5a' });
    } else if (t && t.bc && !t.bc.done) {
      const b = t.bc, gate = b.stage === 'gate', bossSt = b.stage === 'boss';
      const k = bossSt || gate ? 1 - hpOf(t.monsters[0]) : b.killed / Math.max(1, b.guards);
      L.push({ text: `${gate ? '🚪 Phá Cổng Thành' : bossSt ? '🩸 Hạ Hiệp Sĩ Máu' : `🛡 Quân canh ${b.killed}/${b.guards}`} · ${mmss(b.ends_at - now)}${ppl}`, k, col: bossSt ? '#ef6a5a' : '#f0cf7a' });
    } else if (t && t.kal && !t.kal.done) {
      const q = t.kal, bossSt = q.stage === 'boss';
      L.push({ text: `${bossSt ? '👹 Hạ Kundun' : `👹 Quái Kalima ${q.killed}/${q.guards}`} · ${mmss(q.ends_at - now)}${ppl}`, k: bossSt ? 1 - hpOf(t.monsters[0]) : q.killed / Math.max(1, q.guards), col: '#c084ff' });
    } else if (m.event === 'chaos_castle') {
      const c = P.view && P.view.cc;
      if (c && c.phase === 'entry') L.push({ text: `⏳ Hỗn chiến sau ${mmss(c.starts_at - now)} · ${c.players} người`, k: 0, col: '#f0cf7a' });
      else if (c && c.phase !== 'idle') L.push({ text: `⚔ Còn ${c.alive} người · ${c.monsters} quái · ${mmss(c.ends_at - now)}`, k: c.starts_at ? Math.min(1, (now - c.starts_at) / Math.max(1, c.ends_at - c.starts_at)) : 0, col: '#ef6a5a' });
    } else if (m.event === 'castle_siege') {
      const c = P.view && P.view.cs;
      if (c && c.phase === 'fight') {
        const mine = c.holder && P.guild && P.guild.id === c.holder.id;
        L.push({ text: `👑 ${c.holder ? `[${c.holder.tag}] giữ Vương Miện${mine ? ' · bảo vệ nó!' : ''}` : 'Vương Miện chưa có chủ'}${c.crown ? '' : ' · đang hiện lại'} · ${mmss(c.ends_at - now)}`,
          k: Math.min(1, 1 - (c.ends_at - now) / Math.max(60, (c.run_minutes || 30) * 60)), col: c.holder ? guildCol(c.holder.tag) : '#f0cf7a' });
      }
    } else if (m.worldBoss) {
      if (boss.alive) {
        const left = (boss.endsAt - (boss.skew || 0) - Date.now()) / 1000;
        const k1 = (n) => (n >= 1000 ? (n / 1000).toFixed(1) + 'k' : n);
        const all = boss.top || [], mine = all.findIndex((x) => x.id === userId);
        // top 3 sát thương; mình ở hạng 4–5 thì thêm hạng của mình
        const top = all.slice(0, 3).map((x, i) => `${i + 1}. ${x.id === userId ? '★' : ''}${x.name} ${k1(x.dmg)}`)
          .concat(mine >= 3 ? [`★ #${mine + 1} ${k1(all[mine].dmg)}`] : []).join('  ');
        L.push({ text: `🐉 ${boss.name} ${Math.round((boss.hp / boss.maxHp) * 100)}% · ${boss.fighters || 0} người · ${mmss(left)}`, k: boss.hp / boss.maxHp, col: '#d9483b', sub: top });
      } else if (boss.nextAt) {
        L.push({ text: `🐉 ${boss.name || 'Trùm thế giới'} xuất hiện sau ${mmss((boss.nextAt - (boss.skew || 0) - Date.now()) / 1000)}`, k: 0, col: '#d9483b' });
      }
    }
    // Đồi Sáo Diều / Tế Đàn (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long")
    const nowMs = Date.now(), SKY = (window.GAME_DATA.RULES || {}).sky || {};
    if (m.kite) {
      const b = skyEv.bird && skyEv.bird.until > nowMs, f = skyEv.flock && skyEv.flock.until > nowMs, st = skyEv.stars.length;
      // một dòng cho cả ba (đỡ che phần trời): thanh theo Chim Lạc nếu có
      const parts = [b && `🐦 Chim Lạc ${mmss((skyEv.bird.until - nowMs) / 1000)}`, f && `🕊 Đàn Hạc ${mmss((skyEv.flock.until - nowMs) / 1000)}`, st && `🌠 ${st} Mảnh Sao`].filter(Boolean);
      if (parts.length) L.push({ text: parts.join(' · '), k: b ? (skyEv.bird.until - nowMs) / 1000 / ((SKY.bird || {}).stay || 180) : f ? (skyEv.flock.until - nowMs) / 1000 / ((SKY.flock || {}).stay || 120) : 1, col: b ? '#e0a040' : f ? '#e8f2ff' : '#ffd36a' });
    }
    if (skyEv.hoi && skyEv.hoi.until > nowMs) {
      L.push({ text: `🐉🐦 Long Phượng Hội ở Tế Đàn · còn ${mmss((skyEv.hoi.until - nowMs) / 1000)}${P.pos.map === 'altar' ? ' · bước vào vòng sáng' : ''}`, k: (skyEv.hoi.until - nowMs) / 1000 / (((SKY.hoi || {}).stay) || 300), col: '#c88cff' });
    }
    // F1: chiến bang đang diễn ra: tỉ số hai bang (mọi bản đồ, trừ trong Tháp)
    const w = !t && P.guild && P.guild.war;
    if (w && w.enemy) {
      const tot = Math.max(1, w.mine + w.theirs);
      L.push({ text: `⚔ [${P.guild.tag}] ${w.mine} – ${w.theirs} [${w.enemy.tag}] · ${mmss(w.ends_at - now)}`, k: w.mine + w.theirs ? w.mine / tot : 0.5, col: '#5aa9ff', col2: '#ef4a3a' });
    }
    return L;
  }
  let hudTimer = null, hudPx = 0, hudH = 0;
  // ở mép trên khung bản đồ (đáy có khung chat nổi), chừa nút ⤢ bên phải; bản đồ nhỏ dời xuống dưới thanh (`miniPlace`)
  function eventHud(P, m) {
    const L = hudLines(P, m);
    const r = canvas.getBoundingClientRect(), k = r.width ? r.width / VW() : 1;
    const H = L.reduce((a, l) => a + (l.sub ? 34 : 22), 0);
    hudH = H;
    if (Math.round(H * k) !== hudPx) { hudPx = Math.round(H * k); const el = document.getElementById('mini-map'); if (el && !miniDrag) miniPlace(el); }
    if (!L.length) return;
    const vw = VW(), x = 6, w = vw - x - 44 / k;
    let y = 4;
    ctx.save();
    for (let i = 0; i < L.length; i++) {
      const l = L[i], h = l.sub ? 34 : 22;
      ctx.fillStyle = 'rgba(12, 9, 16, 0.78)';
      ctx.beginPath(); ctx.roundRect ? ctx.roundRect(x, y, w, h - 2, 6) : ctx.rect(x, y, w, h - 2); ctx.fill();
      ctx.fillStyle = l.col2 || 'rgba(255,255,255,0.12)'; ctx.fillRect(x + 4, y + 15, w - 8, 3);
      ctx.fillStyle = l.col; ctx.fillRect(x + 4, y + 15, Math.max(0, (w - 8) * Math.max(0, Math.min(1, l.k))), 3);
      ctx.font = '700 10.5px "Be Vietnam Pro", system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = '#f1e6cf';
      ctx.fillText(l.text, x + w / 2, y + 8, w - 10);
      if (l.sub) { ctx.font = '600 9.5px system-ui, sans-serif'; ctx.fillStyle = '#f0cf7a'; ctx.fillText(l.sub, x + w / 2, y + 26, w - 10); }
      y += h;
    }
    ctx.restore();
    // đồng hồ đếm ngược: vẽ lại mỗi giây
    if (!hudTimer) hudTimer = setTimeout(() => { hudTimer = null; if (canvas && document.body.contains(canvas)) draw(); }, 1000);
  }
  // người (đang vẽ) đứng ở ô (x, y), kể cả người bị gom vào "+N\"
  const playersNear = (x, y) => drawnP.filter((d) => d.x === x && d.y === y).map((d) => d.o);
  function pin(id) { pinned = { id, until: performance.now() + 4500 }; draw(); }
  // tâm ô (x, y) trên màn hình (px CSS), theo khung nhìn vẽ gần nhất; null nếu chưa vẽ
  function screenOf(x, y) {
    if (!canvas) return null;
    const r = canvas.getBoundingClientRect(), k = r.width / VW();
    return { x: r.left + (x * TILE - lastCam[0] + TILE / 2) * k, y: r.top + (y * TILE - lastCam[1] + TILE / 2) * k };
  }

  function setFight(f) {
    const changed = JSON.stringify(f) !== JSON.stringify(fight);
    fight = f;
    if (changed) draw();
  }

  const monsterAt = (x, y) => mobs(getPlayer()).find((q) => q.x === x && q.y === y);
  const monsterById = (id) => mobs(getPlayer()).find((q) => q.id === id);
  const nodeAt = (x, y) => (world.nodes || []).find((n) => n.x === x && n.y === y);
  const npcAt = (m, x, y) => (m.npcs || []).find((n) => n.at[0] === x && n.at[1] === y);

  // Cổng vào vùng chưa mở (P.view.unlocked do server tính).
  function locked(P, portal) {
    const target = mapOf(portal.to);
    return (target.zone != null && !P.view.unlocked[target.zone]) || (!target.realm && target.minLevel != null && P.level < target.minLevel) ||
      // bản đồ bí mật (Động Bí Ẩn): cửa chỉ mở những đêm động mở (server kiểm lại)
      (target.secret === 'night' && !secretOpen(P));
  }

  const secretOpen = (P) => !!(P && P.view && P.view.secret && P.view.secret.open);

  // Ngày và đêm (server gửi `phase` kèm trạng thái bản đồ): [nhãn, độ tối]
  const PHASES = { dawn: ['🌅', 0.25], day: ['☀️', 0], dusk: ['🌇', 0.3], night: ['🌙', 0.62] };
  const outdoors = (P) => P.pos.map !== 'tower';
  // Cài đặt hiển thị (V1): 'auto' theo giờ, 'day' luôn sáng, 'night' luôn tối; chỉ đổi độ tối, không đổi luật
  const theme = () => { try { return localStorage.getItem('hl-theme') || 'auto'; } catch (e) { return 'auto'; } };
  const shade = () => ({ day: 'day', night: 'night' }[theme()] || world.phase);
  // B6: độ tối chuyển dần theo giờ Việt Nam (mốc như HacLong.World.Clock: bình minh 5–7, ngày 7–18, hoàng hôn 18–20, đêm
  // 20–5). Đồng hồ máy lệch (buổi tính ra khác buổi server gửi) thì dùng mức cố định của buổi server. Trả [độ tối, ánh
  // cam hồng 0..1] — ánh mạnh nhất giữa bình minh / hoàng hôn.
  function sky() {
    const ph = shade();
    const fixed = [PHASES[ph] ? PHASES[ph][1] : 0, ph === 'dawn' || ph === 'dusk' ? 0.6 : 0];
    if (theme() !== 'auto') return fixed;
    const d = new Date(), h = (d.getUTCHours() + 7 + d.getUTCMinutes() / 60) % 24;
    const calc = h >= 5 && h < 7 ? 'dawn' : h >= 7 && h < 18 ? 'day' : h >= 18 && h < 20 ? 'dusk' : 'night';
    if (calc !== ph) return fixed;
    const N = PHASES.night[1];
    if (ph === 'dawn') { const k = (h - 5) / 2; return [N * (1 - k), Math.sin(k * Math.PI)]; }
    if (ph === 'dusk') { const k = (h - 18) / 2; return [N * k, Math.sin(k * Math.PI)]; }
    return fixed;
  }

  // ---------- Bản đồ động (Phase 5, B-32) ----------
  // Chỉ là hình: nước gợn, cây lay, quái nhún nhẹ, thời tiết theo vùng, đom đóm / đèn lồng ban đêm, khói bếp ở Làng,
  // đài phun nước lấp lánh. Hạt tính thẳng từ thời gian (không giữ trạng thái) nên rất nhẹ; vẽ lại ~30 khung/giây
  // (requestAnimationFrame, bỏ bớt khung cho đều nhịp) khi đang xem bản đồ. Tắt ở Menu → Cài đặt (`hl-fx`); máy đặt
  // "giảm chuyển động" thì mặc định tắt.
  const fxOn = () => {
    try {
      const v = localStorage.getItem('hl-fx');
      if (v) return v === '1';
    } catch (e) { /* bị chặn: theo mặc định */ }
    return !(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  };
  // tên quái trên đầu (bản đồ, tháp, sự kiện, trùm thế giới): tắt ở Menu → Cài đặt (`hl-mobname`), mặc định bật
  const mobNames = () => {
    try { return localStorage.getItem('hl-mobname') !== '0'; } catch (e) { return true; }
  };
  const FX_MS = 33;
  let fxRaf = null, fxLast = 0;
  function fxTick() {
    if (fxRaf || !fxOn() || !canvas || document.hidden) return;
    const loop = (t) => {
      fxRaf = null;
      if (!canvas || !canvas.isConnected || document.hidden || !fxOn()) return;
      // khung tới sớm (màn 60 / 120 Hz): chờ khung sau, giữ nhịp đều ~30 khung/giây
      if (t - fxLast < FX_MS - 4) { fxRaf = requestAnimationFrame(loop); return; }
      fxLast = t;
      draw();
    };
    fxRaf = requestAnimationFrame(loop);
  }
  document.addEventListener('visibilitychange', () => { if (!document.hidden) draw(); });
  // số giả ngẫu nhiên cố định theo chỉ số (hạt thời tiết, đom đóm)
  const rnd = (i, k) => { const v = Math.sin(i * 127.1 + k * 311.7) * 43758.5453; return v - Math.floor(v); };
  // hạt gắn với bản đồ (không với màn hình): trừ vị trí camera rồi quấn vòng trong khung nhìn, nên khi nhân vật đi,
  // hạt đứng yên trong thế giới (tuyết, lá, mưa không "đi theo" nhân vật)
  const wrap = (v, m) => ((v % m) + m) % m;
  // thời tiết theo nền bản đồ
  // B5: thời tiết chung cả server (server gửi `world.weather` theo giờ); bản đồ tháp / sự kiện: theo nền tầng như trước
  const WEATHER_ICON = { clear: '☀️', rain: '🌧️', storm: '⛈️', fog: '🌫️', snow: '❄️', blizzard: '🌨️', leaves: '🍂', dust: '💨', embers: '🔥' };
  const WEATHER_NAME = { clear: 'Trời quang', rain: 'Mưa', storm: 'Giông bão', fog: 'Sương mù', snow: 'Tuyết rơi', blizzard: 'Bão tuyết', leaves: 'Lá bay', dust: 'Gió cát', embers: 'Tàn lửa' };
  function weatherNow(m, id) {
    if (world.map === id && world.weather && !m.tower) return world.weather === 'clear' ? null : world.weather;
    return weatherOf(m, id);
  }
  // biểu tượng thời tiết trên thanh tên bản đồ (cập nhật khi sự kiện "map" tới, `setWorld`)
  function wxIcon(P) {
    const wk = P && world.map === P.pos.map && outdoors(P) ? world.weather : null;
    return wk && WEATHER_ICON[wk] ? `<span title="${WEATHER_NAME[wk]}">${WEATHER_ICON[wk]}</span> ` : '';
  }
  function weatherOf(m, id) {
    if (id === 'village') return 'smoke';
    const f = m.floor || '';
    if (f.includes('swamp')) return 'rain';
    if (f.includes('lair')) return 'embers';
    if (f.includes('mountain')) return 'snow';
    if (f.includes('graveyard')) return 'fog';
    if (f.includes('camp')) return 'dust';
    if (f.includes('forest')) return 'leaves';
    return null;
  }
  // ống khói: góc trên phải mỗi khối nhà gạch (ô "#") ở Làng
  const chimneyCache = new Map();
  function chimneys(m, id) {
    if (!chimneyCache.has(id)) {
      const out = [];
      m.tiles.forEach((row, y) => [...row].forEach((c, x) => {
        if (c === '#' && tileAt(m, x, y - 1) !== '#' && tileAt(m, x + 1, y) !== '#') out.push([x, y]);
      }));
      chimneyCache.set(id, out);
    }
    return chimneyCache.get(id);
  }

  let thunderAt = 0;
  function weather(kind, t, cx, cy, m, id) {
    const vw = VW(), vh = VH();
    // khung bản đồ đang ẩn (trong trận): rộng / cao 0 thì wrap chia cho 0 ra NaN
    if (!(vw > 0 && vh > 0)) return;
    if (kind === 'storm') {
      // mưa to xiên + chớp: mỗi ~9 giây một lần lóe (hai nhịp), sấm theo sau
      ctx.strokeStyle = 'rgba(170, 200, 230, 0.55)'; ctx.lineWidth = 1.2;
      ctx.beginPath();
      for (let i = 0; i < 130; i++) {
        const x = wrap(rnd(i, 1) * vw + t * 0.3 - cx, vw + 60) - 30, y = wrap(rnd(i, 2) * vh + t * 0.8 - cy, vh);
        ctx.moveTo(x, y); ctx.lineTo(x - 6, y + 13);
      }
      ctx.stroke();
      const cyc = t % 9000;
      if (cyc < 90 || (cyc > 180 && cyc < 260)) {
        ctx.fillStyle = `rgba(230, 235, 255, ${cyc < 90 ? 0.45 : 0.25})`; ctx.fillRect(0, 0, vw, vh);
        if (t - thunderAt > 5000) { thunderAt = t; setTimeout(() => window.Sound && window.Sound.play('thunder'), 500); }
      }
      return;
    }
    if (kind === 'blizzard') {
      for (let i = 0; i < 120; i++) {
        const x = wrap(rnd(i, 1) * vw + t * (0.12 + rnd(i, 4) * 0.08) - cx, vw), y = wrap(rnd(i, 2) * vh + t * (0.05 + rnd(i, 3) * 0.05) - cy, vh);
        ctx.fillStyle = `rgba(245, 248, 255, ${0.5 + 0.4 * rnd(i, 5)})`;
        ctx.fillRect(x, y, 2 + rnd(i, 6) * 2, 2);
      }
      ctx.fillStyle = 'rgba(225, 235, 250, 0.12)'; ctx.fillRect(0, 0, vw, vh);
      return;
    }
    if (kind === 'rain') {
      ctx.strokeStyle = 'rgba(170, 200, 230, 0.5)'; ctx.lineWidth = 1;
      ctx.beginPath();
      for (let i = 0; i < 70; i++) {
        const x = wrap(rnd(i, 1) * vw + t * 0.12 - cx, vw + 40) - 20, y = wrap(rnd(i, 2) * vh + t * 0.55 - cy, vh);
        ctx.moveTo(x, y); ctx.lineTo(x - 3, y + 9);
      }
      ctx.stroke();
    } else if (kind === 'snow') {
      ctx.fillStyle = 'rgba(245, 248, 255, 0.8)';
      for (let i = 0; i < 55; i++) {
        const x = wrap(rnd(i, 1) * vw + Math.sin(t / 900 + i) * 12 - cx, vw), y = wrap(rnd(i, 2) * vh + t * (0.025 + rnd(i, 3) * 0.03) - cy, vh);
        ctx.fillRect(x, y, 2, 2);
      }
    } else if (kind === 'embers') {
      for (let i = 0; i < 40; i++) {
        const x = wrap(rnd(i, 1) * vw + Math.sin(t / 700 + i) * 10 - cx, vw), y = wrap(rnd(i, 2) * vh - t * (0.02 + rnd(i, 3) * 0.03) - cy, vh);
        const a = 0.4 + 0.5 * Math.abs(Math.sin(t / 300 + i));
        ctx.fillStyle = `rgba(255, ${120 + Math.round(rnd(i, 4) * 80)}, 40, ${a})`;
        ctx.fillRect(x, y, 2, 2);
      }
    } else if (kind === 'leaves') {
      for (let i = 0; i < 12; i++) {
        const x = wrap(rnd(i, 1) * vw + t * 0.03 + Math.sin(t / 800 + i) * 18 - cx, vw), y = wrap(rnd(i, 2) * vh + t * 0.022 - cy, vh);
        ctx.save(); ctx.translate(x, y); ctx.rotate(Math.sin(t / 500 + i) * 0.9);
        ctx.fillStyle = rnd(i, 3) > 0.5 ? 'rgba(196, 140, 52, 0.75)' : 'rgba(120, 160, 60, 0.7)';
        ctx.beginPath(); ctx.ellipse(0, 0, 3.5, 1.8, 0, 0, Math.PI * 2); ctx.fill();
        ctx.restore();
      }
    } else if (kind === 'dust') {
      // Trại (đất khô): bụi cát bay ngang theo gió (FX_PLAN đợt 5)
      for (let i = 0; i < 26; i++) {
        const x = wrap(rnd(i, 1) * vw + t * (0.08 + rnd(i, 3) * 0.06) - cx, vw + 30) - 15, y = wrap(rnd(i, 2) * vh + Math.sin(t / 600 + i) * 6 - cy, vh);
        ctx.fillStyle = `rgba(214, 186, 132, ${0.25 + 0.3 * rnd(i, 4)})`;
        ctx.fillRect(x, y, 6 + rnd(i, 5) * 8, 1.5);
      }
    } else if (kind === 'fog') {
      for (let i = 0; i < 6; i++) {
        const x = wrap(rnd(i, 1) * (vw + 240) + t * 0.012 * (1 + rnd(i, 3)) - cx, vw + 240) - 120, y = wrap(rnd(i, 2) * vh - cy, vh);
        const g = ctx.createRadialGradient(x, y, 4, x, y, 110);
        g.addColorStop(0, 'rgba(200, 205, 220, 0.16)'); g.addColorStop(1, 'rgba(200, 205, 220, 0)');
        ctx.fillStyle = g; ctx.fillRect(x - 110, y - 110, 220, 220);
      }
    } else if (kind === 'smoke') {
      chimneys(m, id).forEach(([gx, gy], j) => {
        const bx = gx * TILE - cx + TILE - 8, by = gy * TILE - cy + 2;
        for (let i = 0; i < 6; i++) {
          const k = ((t / 2600 + i / 6 + j * 0.37) % 1);
          const r = 3 + k * 8;
          ctx.fillStyle = `rgba(210, 205, 200, ${0.4 * (1 - k)})`;
          ctx.beginPath(); ctx.arc(bx + Math.sin(t / 700 + i + j) * 4 + k * 10, by - k * 34, r, 0, Math.PI * 2); ctx.fill();
        }
      });
    }
  }

  // sau lớp bóng tối: đom đóm ngoài trời và đèn lồng quanh người dân ở Làng
  function nightGlow(t, m, cx, cy, dark) {
    const vw = VW(), vh = VH();
    if (!(vw > 0 && vh > 0)) return;
    for (const n of m.npcs || []) {
      const x = n.at[0] * TILE - cx + TILE / 2, y = n.at[1] * TILE - cy + TILE / 2;
      if (x < -60 || y < -60 || x > vw + 60 || y > vh + 60) continue;
      const f = 0.85 + 0.15 * Math.sin(t / 180 + n.at[0]);
      const g = ctx.createRadialGradient(x, y, 2, x, y, TILE * 1.6);
      g.addColorStop(0, `rgba(255, 196, 110, ${0.35 * dark * f})`); g.addColorStop(1, 'rgba(255, 196, 110, 0)');
      ctx.fillStyle = g; ctx.fillRect(x - TILE * 1.6, y - TILE * 1.6, TILE * 3.2, TILE * 3.2);
    }
    const ff = /forest|swamp/.test(m.floor || '') ? 30 : 16;
    for (let i = 0; i < ff; i++) {
      const x = wrap(rnd(i, 1) * vw + Math.sin(t / 1300 + i * 2) * 30 - cx, vw), y = wrap(rnd(i, 2) * vh + Math.cos(t / 1700 + i) * 22 - cy, vh);
      const a = Math.max(0, Math.sin(t / 420 + i * 1.7)) * dark;
      if (a < 0.05) continue;
      const g = ctx.createRadialGradient(x, y, 0, x, y, 6);
      g.addColorStop(0, `rgba(220, 255, 140, ${a})`); g.addColorStop(1, 'rgba(220, 255, 140, 0)');
      ctx.fillStyle = g; ctx.fillRect(x - 6, y - 6, 12, 12);
    }
  }

  // B6: đêm — cực quang trên núi, đuốc lập lòe ở hang / nghĩa địa (cột, đá cạnh lối đi), ánh trăng lấp lánh trên nước
  function nightFx(t, m, cx, cy, dark, x0, y0, x1, y1) {
    const vw = VW(), vh = VH(), f = m.floor || '';
    if (f.includes('mountain')) {
      for (let b = 0; b < 3; b++) {
        ctx.beginPath();
        const base = 26 + b * 18, amp = 10 + b * 4;
        for (let x = 0; x <= vw; x += 12) {
          const y = base + Math.sin(x / 70 + t / (2600 + b * 500) + b) * amp + Math.sin(x / 23 + t / 900) * 3;
          x ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
        }
        ctx.lineTo(vw, 0); ctx.lineTo(0, 0); ctx.closePath();
        const a = (0.1 + 0.05 * Math.sin(t / 1700 + b)) * dark;
        ctx.fillStyle = b === 1 ? `rgba(170, 110, 255, ${a})` : `rgba(90, 255, 170, ${a})`;
        ctx.fill();
      }
    }
    const torches = /lair|graveyard/.test(f);
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const c = (m.tiles[y] || '')[x];
        const px = x * TILE - cx, py = y * TILE - cy;
        if (torches && (c === 'I' || c === 'R' || c === 'S') && rnd(x * 3 + 1, y * 5 + 2) < 0.12 && WALK.has((m.tiles[y + 1] || '')[x])) {
          const fl = 0.75 + 0.25 * Math.sin(t / 90 + x * 3) * Math.sin(t / 37 + y);
          const g = ctx.createRadialGradient(px + TILE / 2, py + 8, 1, px + TILE / 2, py + 8, TILE * 2);
          g.addColorStop(0, `rgba(255, 150, 60, ${0.55 * dark * fl})`); g.addColorStop(1, 'rgba(255, 150, 60, 0)');
          ctx.fillStyle = g; ctx.fillRect(px - TILE * 1.5, py - TILE * 1.5, TILE * 4, TILE * 4);
          ctx.fillStyle = `rgba(255, ${200 + Math.round(40 * fl)}, 120, ${0.9 * fl})`;
          ctx.beginPath(); ctx.ellipse(px + TILE / 2, py + 6 - fl * 2, 2.5, 4 + fl * 2, 0, 0, Math.PI * 2); ctx.fill();
        }
        if ((c === '~' || c === '=') && rnd(x + 11, y + 7) < 0.5) {
          const k = Math.max(0, Math.sin(t / 700 + x * 1.7 + y * 2.3));
          if (k > 0.6) {
            ctx.fillStyle = `rgba(230, 235, 255, ${(k - 0.6) * 1.6 * dark})`;
            ctx.fillRect(px + 6 + rnd(x, y) * 18, py + 6 + rnd(y, x) * 18, 3, 1.2);
          }
        }
      }
    }
  }

  // Hỗn Chiến Thành (B-19): chờ hỗn chiến / còn bao nhiêu người, quái (P.view.cc)
  function ccTop(P) {
    const c = P.view && P.view.cc;
    if (!c || c.phase === 'idle') return 'Hỗn Chiến Thành đã kết thúc';
    const at = (u) => new Date(u * 1000).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' });
    return c.phase === 'entry' ? `Chờ hỗn chiến lúc ${at(c.starts_at)} · ${c.players} người`
      : `Hỗn chiến · còn ${c.alive} người, ${c.monsters} quái · hết lúc ${at(c.ends_at)}`;
  }

  // Công Thành Chiến (B-22): bang đang giữ Vương Miện, giờ hết (P.view.cs)
  function csTop(P) {
    const c = P.view && P.view.cs;
    if (!c || c.phase !== 'fight') return 'Công Thành Chiến đã kết thúc';
    const at = new Date(c.ends_at * 1000).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' });
    return `👑 ${c.holder ? `[${c.holder.tag}] giữ Vương Miện` : 'Vương Miện chưa có chủ'} · hết lúc ${at}`;
  }

  // dòng phụ của bảng tên bản đồ (B4): cấp quái / phòng trùm / sự kiện
  function subtitle(P, m) {
    const z = m.zone != null ? ZONES[m.zone] : null;
    const side = m.side && ((window.GAME_DATA.LIBRARY || { maps: [] }).maps.find((x) => x.id === P.pos.map) || {});
    if (m.tower) return '';
    if (m.secret) return SECRET.min ? `Nơi bí ẩn · quái cấp ${SECRET.min}–${SECRET.max}` : 'Nơi bí ẩn';
    if (P.pos.map === 'village') return 'Nơi bình yên';
    if (P.pos.map.endsWith('_boss') && z) return `Phòng trùm · cấp ${z.boss.level}`;
    if (side && side.min && !(side.monsters || []).length) return `Không có quái · cần cấp ${side.min}`;
    if (side && side.min) return `Quái cấp ${side.min}–${side.max}`;
    if (z) return `Quái cấp ${z.levels}`;
    return '';
  }

  // B4: bảng tên bản đồ giữa màn (hiện 0,3 giây, giữ, mờ dần; tổng 2,6 giây) và màn mở dần từ tối khi vừa sang bản đồ
  function enterFx(t, P, m, px, py) {
    const k = t - enter.at;
    if (k < 0 || k > 2600) return;
    const vw = VW(), vh = VH();
    if (k < 520) {
      const a = 1 - k / 520;
      ctx.fillStyle = `rgba(6, 4, 10, ${0.92 * a})`;
      ctx.fillRect(0, 0, vw, vh);
      // xoáy sáng quanh nhân vật (như bước qua cổng)
      const x = px + TILE / 2, y = py + TILE / 2;
      ctx.save(); ctx.translate(x, y); ctx.rotate(k / 140);
      for (let i = 0; i < 3; i++) {
        ctx.strokeStyle = `rgba(190, 160, 255, ${0.7 * a})`; ctx.lineWidth = 2.5;
        ctx.beginPath(); ctx.arc(0, 0, 10 + i * 9 + (k / 520) * 30, i * 2.1, i * 2.1 + 3.6); ctx.stroke();
      }
      ctx.restore();
    }
    const a = k < 300 ? k / 300 : k > 1900 ? Math.max(0, 1 - (k - 1900) / 700) : 1;
    const tr = (s) => (window.I18N ? window.I18N.tr(s) : s);
    const name = tr(m.name || ''), sub = tr(subtitle(P, m));
    const y = Math.round(vh * 0.26) - (1 - a) * 8;
    ctx.save();
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.font = '700 28px "Grenze Gotisch", "Palatino Linotype", Georgia, serif';
    const w = Math.min(vw - 24, Math.max(ctx.measureText(name).width + 70, 200));
    const g = ctx.createLinearGradient(vw / 2 - w / 2, 0, vw / 2 + w / 2, 0);
    g.addColorStop(0, 'rgba(10, 7, 14, 0)'); g.addColorStop(0.2, `rgba(10, 7, 14, ${0.72 * a})`);
    g.addColorStop(0.8, `rgba(10, 7, 14, ${0.72 * a})`); g.addColorStop(1, 'rgba(10, 7, 14, 0)');
    ctx.fillStyle = g; ctx.fillRect(vw / 2 - w / 2, y - 26, w, sub ? 62 : 48);
    ctx.fillStyle = `rgba(240, 207, 122, ${0.55 * a})`;
    ctx.fillRect(vw / 2 - w * 0.32, y - 25, w * 0.64, 1); ctx.fillRect(vw / 2 - w * 0.32, y + (sub ? 35 : 21), w * 0.64, 1);
    ctx.shadowColor = 'rgba(0, 0, 0, 0.9)'; ctx.shadowBlur = 6;
    ctx.fillStyle = `rgba(240, 207, 122, ${a})`;
    ctx.fillText(name, vw / 2, y);
    if (sub) {
      ctx.font = '600 12px "Be Vietnam Pro", system-ui, sans-serif';
      ctx.fillStyle = `rgba(241, 230, 207, ${0.9 * a})`;
      ctx.fillText(sub, vw / 2, y + 23);
    }
    ctx.restore();
  }

  function top(P) {
    const m = cur(P);
    const z = m.zone != null ? ZONES[m.zone] : null;
    // bản đồ phụ (Phase 15a): cấp quái lấy từ Thư viện
    const side = m.side && ((window.GAME_DATA.LIBRARY || { maps: [] }).maps.find((x) => x.id === P.pos.map) || {});
    const ph = (PHASES[world.phase] && outdoors(P) ? `<span class="phase">${PHASES[world.phase][0]}</span> ` : '') +
      `<span class="phase" id="map-wx">${wxIcon(P)}</span>`;
    return `<div class="map-top">
        <b>${ph}${m.name}</b>${P.view && P.view.event && P.view.event.active && outdoors(P) ? ` <span class="small" style="color:var(--gold)">${P.view.event.icon} ${P.view.event.name}</span>` : ''}
        <span class="small muted">${m.event === 'chaos_castle' ? ccTop(P) : m.event === 'castle_siege' ? csTop(P) : m.tower && m.tower.kal ? (m.tower.kal.done ? 'Đi một bước để về Làng' : `Đã hạ ${m.tower.kal.killed}/${m.tower.kal.guards} quái${roomMine(m.tower.kal)} · hết lúc ${new Date(m.tower.kal.ends_at * 1000).toLocaleTimeString('vi-VN')}${roomTag(m.tower)}`) : m.tower && m.tower.bc ? (m.tower.bc.done ? 'Đi một bước để về Làng' : `Quân canh đã hạ ${m.tower.bc.killed}/${m.tower.bc.guards}${roomMine(m.tower.bc)} · hết lúc ${new Date(m.tower.bc.ends_at * 1000).toLocaleTimeString('vi-VN')}${roomTag(m.tower)}`) : m.tower && m.tower.ds ? `${m.tower.ds.score} điểm · hết lúc ${new Date(m.tower.ds.ends_at * 1000).toLocaleTimeString('vi-VN')} · ${m.tower.monsters.length ? `còn ${m.tower.monsters.length} quái` : 'cầu thang đã mở'}${roomTag(m.tower)}` : m.tower ? (m.tower.monsters.length ? `Còn ${m.tower.monsters.length} quái · kỷ lục tầng ${P.tower_best || 0}` : 'Cầu thang đã mở!') : m.secret ? `Nơi bí ẩn${SECRET.min ? ` · quái cấp ${SECRET.min}–${SECRET.max}` : ''} · cần cấp ${m.minLevel || 38}` : side ? (side.monsters && !side.monsters.length ? `Không có quái · cần cấp ${side.min}` : `Bản đồ phụ · quái cấp ${side.min}–${side.max}`) : z ? (P.pos.map.endsWith('_boss') ? `Phòng trùm · cấp ${z.boss.level}` : `Quái cấp ${z.levels}`) : P.pos.map === 'altar' ? 'Nơi trùm thế giới xuất hiện' : 'Bước vào người dân để nói chuyện'}</span>
      </div>`;
  }

  function html(P, overlay) {
    const m = cur(P);
    return `
      ${top(P)}
      <div class="map-wrap"><canvas id="map-canvas" aria-label="Bản đồ ${m.name}"></canvas>${miniOn() && !m.tower ? '<canvas class="mini-map" id="mini-map" role="button" tabindex="0" data-act="world-map" title="Bấm: bản đồ thế giới · giữ và kéo: dời chỗ" aria-label="Bản đồ thu nhỏ, bấm để mở bản đồ thế giới, giữ và kéo để dời chỗ"></canvas>' : ''}<button class="zoom-btn ${zoomOn() ? 'on' : ''}" data-act="map-zoom" aria-pressed="${zoomOn()}" title="Vừa màn hình" aria-label="Vừa màn hình">⤢</button>${overlay || ''}</div>
      <p class="small muted map-hint">Chạm vào ô để đi tới, bước vào quái để đánh.</p>`;
  }

  function mount(player) {
    getPlayer = player;
    canvas = document.getElementById('map-canvas');
    if (!canvas) { mounted = null; return; }
    ctx = canvas.getContext('2d');
    if (mounted !== getPlayer().pos.map) anim.clear();
    mounted = getPlayer().pos.map;
    resize();
  }

  // V7: "Vừa màn hình" — thu cả bản đồ cho vừa khung (không phóng to quá 1); lưu ở trình duyệt
  let zoom = 1;
  const zoomOn = () => { try { return localStorage.getItem('hl-zoom') === '1'; } catch (e) { return false; } };
  const VW = () => canvas.clientWidth / zoom, VH = () => canvas.clientHeight / zoom;

  function resize() {
    if (!canvas) return;
    const w = canvas.parentElement.clientWidth;
    // màn bản đồ vừa khít (U5): cao theo khung còn lại giữa HUD và dock
    const fit = canvas.closest('.fit');
    const h = fit ? Math.max(160, canvas.parentElement.clientHeight) : Math.min(Math.round(window.innerHeight * 0.52), 13 * TILE);
    const dpr = window.devicePixelRatio || 1;
    canvas.style.height = h + 'px';
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.imageSmoothingEnabled = false;
    draw();
  }

  // Góc trên trái của khung nhìn (pixel), đi theo nhân vật (x, y tính theo ô, có thể lẻ),
  // không lố ra ngoài bản đồ.
  function camera(m, x, y) {
    const vw = VW(), vh = VH();
    const mw = m.tiles[0].length * TILE, mh = m.tiles.length * TILE;
    const axis = (view, size, t) => (size <= view ? (size - view) / 2 : Math.max(0, Math.min(size - view, t * TILE + TILE / 2 - view / 2)));
    return [Math.round(axis(vw, mw, x)), Math.round(axis(vh, mh, y))];
  }

  function label(text, cx, y, color) {
    if (window.I18N) text = window.I18N.tr(text);
    ctx.font = '600 10px "Be Vietnam Pro", system-ui, sans-serif';
    const w = ctx.measureText(text).width + 6;
    ctx.fillStyle = 'rgba(12, 9, 16, 0.78)';
    ctx.fillRect(Math.round(cx - w / 2), y, w, 13);
    ctx.fillStyle = color || '#f1e6cf';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    ctx.fillText(text, cx, y + 1);
  }

  function levelColor(P, lv) {
    if (lv <= P.level - 3) return '#9a93a3';
    if (lv <= P.level) return '#7fd08a';
    if (lv <= P.level + 2) return '#e8c15a';
    return '#ef6a5a';
  }

  function draw() {
    const P = getPlayer();
    if (!canvas || !ctx || !P || !P.pos || mounted !== P.pos.map) return;
    const m = cur(P);
    const now = performance.now();
    const [mx, my] = smooth('me', P.pos.x, P.pos.y, DUR.me, now);
    zoom = zoomOn() ? Math.min(1, canvas.clientWidth / (m.tiles[0].length * TILE), canvas.clientHeight / (m.tiles.length * TILE)) : 1;
    zoom *= kiteZoom(now, my);
    const dpr = window.devicePixelRatio || 1;
    ctx.setTransform(dpr * zoom, 0, 0, dpr * zoom, 0, 0);
    const [cx, cy] = camera(m, mx, my - kiteLift(now, my));
    lastCam = [cx, cy];
    ctx.fillStyle = '#0c0910';
    ctx.fillRect(0, 0, VW(), VH());
    const x0 = Math.max(0, Math.floor(cx / TILE)), y0 = Math.max(0, Math.floor(cy / TILE));
    const x1 = Math.min(m.tiles[0].length - 1, Math.ceil((cx + VW()) / TILE));
    const y1 = Math.min(m.tiles.length - 1, Math.ceil((cy + VH()) / TILE));
    const floor = image(m.floor);
    const labels = [], talk = [];
    const fx = fxOn(), fountains = [], lanterns = [], tufts = [], incense = [];
    const grassy = /forest|swamp|grass/.test(m.floor || '') && outdoors(P);

    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const px = Math.round(x * TILE - cx), py = Math.round(y * TILE - cy);
        const kind = WORLD.legend[m.tiles[y][x]];
        // ô trời (Đồi Sáo Diều): lót nền cỏ (mặt đồi cong lấn vào), trời vẽ sau ở `clouds` theo đường chân trời cong
        if (kind === 'sky') { if (floor.complete) ctx.drawImage(floor, px, py, TILE, TILE); continue; }
        if (floor.complete) ctx.drawImage(floor, px, py, TILE, TILE);
        // Biển Long Vương (DECISIONS "Biển Long Vương"): cát, dừa, nước biển vẽ bằng code; sóng dạt bờ vẽ sau (`seaShore`)
        // Biển Long Vương (DECISIONS "Biển Long Vương"): cát, nước, sóng vẽ liền một mảng theo đường cong (`seaWorld`), không
        // theo ô; cầu tàu, thuyền, dừa vẽ sau cùng đè lên
        if (m.style === 'sea' && SEA_KINDS[kind]) continue;
        if (kind !== 'floor') {
          // ô W: Đài Phúc Lành (Phase 2, thay đá dịch chuyển)
          const im = image('tiles/' + kind);
          const sway = fx && (kind === 'tree' || kind === 'tree_autumn') ? Math.sin(now / 900 + x * 0.8 + y * 0.5) * 0.045 : 0;
          if (m.style === 'bamboo' && (kind === 'tree' || kind === 'tree_autumn')) {
            bamboo(px, py, x, y, fx ? now : 0);
          } else if (im.complete && sway) {
            // cây lay theo gió: nghiêng quanh gốc
            ctx.save(); ctx.translate(px + TILE / 2, py + TILE); ctx.transform(1, 0, sway, 1, 0, 0);
            ctx.drawImage(im, -TILE / 2, -TILE, TILE, TILE); ctx.restore();
          } else if (im.complete) ctx.drawImage(im, px, py, TILE, TILE);
          if (fx && kind === 'water') {
            // nước gợn: hai vệt sáng trôi ngang
            for (let k = 0; k < 2; k++) {
              const ph = (now / 1400 + x * 0.37 + y * 0.61 + k * 0.5) % 1;
              ctx.fillStyle = `rgba(220, 240, 255, ${0.16 * Math.sin(ph * Math.PI)})`;
              ctx.fillRect(px + 4 + ph * (TILE - 14), py + 8 + k * 12 + ((x + y + k) % 3) * 2, 8, 1.5);
            }
          }
          if (m.style === 'paddy' && kind === 'water') paddy(px, py, x, y, fx ? now : 0);
          if (fx && m.style === 'temple' && kind === 'dragon_statue') incense.push([px, py]);
          if (fx && kind === 'fountain') fountains.push([px, py]);
          if (kind === 'lantern') lanterns.push([px, py]);
        }
        // B7: bụi cỏ lay theo gió (ô cỏ / nền cỏ, ~1/3 số ô, chọn cố định theo vị trí)
        if (fx && grassy && (kind === 'grass' || kind === 'floor') && rnd(x * 7 + y * 13, 9) < 0.34) tufts.push([px, py, x, y]);
        if (GROUND[kind]) continue;
        if (kind === 'waystone') labels.push(['Đá Dịch Chuyển', px + TILE / 2, py - 13, '#f0cf7a']);
        if (kind === 'stairs_up' && m.tower && (m.tower.bc || m.tower.kal)) { /* Lâu Đài: cầu thang lên chỉ là cảnh */ } else if (kind === 'stairs_up') labels.push([m.tower && m.tower.monsters.length ? (m.tower.ds ? '🔒 Đợt sau' : '🔒 Lên tầng') : (m.tower && m.tower.ds ? 'Đợt sau' : 'Lên tầng'), px + TILE / 2, py + TILE - 13, '#f0cf7a']);
        if (kind === 'stairs_down') labels.push(['Về Làng', px + TILE / 2, py + TILE - 13, '#b9d7ff']);
        const portal = PORTAL.has(m.tiles[y][x]) && portalAt(m, x, y);
        // Động Bí Ẩn (D8): cửa đóng thì trông như vách đá, không nhãn; mở thì khe đá phát sáng tím
        if (portal && (mapOf(portal.to) || {}).secret) {
          if (!secretOpen(P)) {
            const st = image('tiles/stone');
            if (st.complete) ctx.drawImage(st, px, py, TILE, TILE);
          } else {
            crackFx(px, py, fx ? now : 0);
            labels.push(['Khe Đá Phát Sáng', px + TILE / 2, py + TILE - 13, '#d6a8ff']);
          }
          continue;
        }
        if (portal) {
          const shut = locked(P, portal);
          if (shut) { ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.fillRect(px, py, TILE, TILE); } else if (fx) portalSwirl(px + TILE / 2, py + TILE / 2, now);
          // nhãn nằm trong ô cổng để không đè lên người đứng cạnh
          labels.push([(shut ? '🔒 ' : '') + mapOf(portal.to).name, px + TILE / 2, py + TILE - 13, shut ? '#9a93a3' : '#f0cf7a']);
        }
      }
    }

    groundFx(m, x0, y0, x1, y1, cx, cy, now, fx);
    if (m.kite) clouds(now, m, cx, cy, fx, x0, y0, x1, y1);
    if (tufts.length) grassFx(now, tufts);
    for (const [ix, iy] of incense) {
      for (let i = 0; i < 4; i++) {
        const k = ((now / 2600) + i / 4) % 1;
        ctx.fillStyle = `rgba(220, 215, 230, ${0.35 * (1 - k)})`;
        ctx.beginPath(); ctx.arc(ix + TILE / 2 + Math.sin(now / 600 + i * 2) * 4 * k, iy + 4 - k * 26, 1.5 + k * 4, 0, Math.PI * 2); ctx.fill();
      }
    }
    if (fx) printFx(now, cx, cy);

    // sự kiện "map" có thể đến trước/sau lúc đổi bản đồ một chút
    const here = world.map === P.pos.map;
    const names = mobNames();
    const mpos = {}; // vị trí quái trên màn (số sát thương bay lên khi Đánh nhanh)
    let crownSpot = null;
    for (const q of mobs(P)) {
      const [qx, qy] = smooth('m' + q.id, q.x, q.y, DUR.monster, now);
      // quái đứng yên thì nhún nhẹ (chỉ là hình)
      const bob = fx && qx === q.x && qy === q.y ? Math.round(Math.sin(now / 380 + (parseInt(String(q.id).replace(/\D/g, ''), 10) || 0)) * 1.5) : 0;
      const px = Math.round(qx * TILE - cx), py = Math.round(qy * TILE - cy) + bob;
      mpos[q.id] = [px + TILE / 2, py];
      const crown = m.event === 'castle_siege' && q.kind === CS.crownKind;
      if (crown) crownSpot = [px + TILE / 2, py + TILE / 2];
      if (px < -TILE || py < -TILE || px > VW() || py > VH()) continue;
      // Công Thành Chiến: Vương Miện có quầng vàng + 👑 (DECISIONS "Sự kiện trực quan")
      if (crown) crownGlow(px, py, fx ? now : 0);
      // quái người khác đang đánh: mờ đi; con mình đang đánh (⚡ Đánh nhanh, ở lại bản đồ) vẫn rõ
      ctx.globalAlpha = q.busy && !q.mine ? 0.45 : 1;
      if (q.boss && !q.gold) {
        ctx.strokeStyle = '#f0cf7a'; ctx.lineWidth = 2;
        ctx.strokeRect(px + 1, py + 1, TILE - 2, TILE - 2);
      }
      // quái Tinh Anh (Động Bí Ẩn): viền tím
      if (q.elite) {
        ctx.strokeStyle = '#c084ff'; ctx.lineWidth = 2;
        ctx.strokeRect(px + 1, py + 1, TILE - 2, TILE - 2);
      }
      const im = image('monsters/' + q.kind);
      if (q.rare) { ctx.shadowColor = '#b36bff'; ctx.shadowBlur = 12; }
      // quái vàng Golden Invasion: quầng vàng nhấp nháy; trùm vàng vẽ to 1,5 lần (Phase 7, M3)
      if (q.gold) {
        const pulse = 0.5 + 0.5 * Math.sin(now / 250);
        ctx.fillStyle = `rgba(255, 210, 90, ${0.18 + 0.17 * pulse})`;
        ctx.beginPath(); ctx.arc(px + TILE / 2, py + TILE / 2, TILE * (q.boss ? 0.95 : 0.62), 0, Math.PI * 2); ctx.fill();
        ctx.shadowColor = '#ffd24a'; ctx.shadowBlur = 10 + 8 * pulse;
      }
      const sz = q.gold && q.boss ? TILE * 1.5 : TILE, off = (sz - TILE) / 2;
      if (im.complete) ctx.drawImage(im, px - off, py - off, sz, sz);
      ctx.shadowBlur = 0;
      ctx.globalAlpha = 1;
      // Phase 13: tên trên đầu, thanh máu dưới chân (máu do server giữ, ai cùng bản đồ cũng thấy như nhau)
      const nm = (crown ? '👑 ' : '') + (q.busy ? '⚔ ' : '') + (q.gold ? (q.boss ? 'Trùm Vàng · ' : 'Vàng · ') : q.elite ? 'Tinh Anh · ' : q.rare ? 'Bóng Đêm · ' : '') + (q.name || NAME[q.kind] || '');
      if (names) labels.push([nm, px + TILE / 2, py - 13 - off, q.gold ? '#ffd24a' : q.raid ? '#ff8a5c' : q.elite ? '#c084ff' : q.rare ? '#d59cff' : q.busy ? '#ef6a5a' : q.boss ? '#f0cf7a' : '#f1e6cf']);
      const hpk = Math.max(0, Math.min(100, q.hp == null ? 100 : q.hp)) / 100, bw = sz - 6;
      ctx.fillStyle = 'rgba(12,9,16,0.85)'; ctx.fillRect(px - off + 3, py - off + sz + 1, bw, 5);
      ctx.fillStyle = q.gold ? '#e8b923' : q.boss ? '#c0392b' : '#d9483b'; ctx.fillRect(px - off + 4, py - off + sz + 2, Math.max(0, (bw - 2) * hpk), 3);
      const lv = q.level || LEVEL[q.kind] || 1;
      ctx.font = '700 9px system-ui, sans-serif';
      ctx.fillStyle = 'rgba(12,9,16,0.85)';
      ctx.fillRect(px + TILE - 14, py + TILE - 10, 14, 10);
      ctx.fillStyle = levelColor(P, lv);
      ctx.textAlign = 'center'; ctx.textBaseline = 'top';
      ctx.fillText(String(lv), px + TILE - 7, py + TILE - 9);
      // đang có người đánh (⚔): thỉnh thoảng lóe tia chém (người khác không vẽ trên bản đồ, chỉ thấy quái bị đánh)
      if (fx && q.busy && q.by !== userId) {
        const ph = ((now + (parseInt(String(q.id).replace(/\D/g, ''), 10) || 0) * 137) % 1100) / 1100;
        if (ph < 0.3) slashAt(px + TILE / 2, py + TILE / 2, ph / 0.3, '#ffe9b0');
      }
    }

    if (m.style === 'sea') seaWorld(m, cx, cy, x0, y0, x1, y1, fx ? now : 0);
    if (fx) drawMobFx(now, cx, cy);

    for (const n of here ? world.nodes || [] : []) {
      const px = Math.round(n.x * TILE - cx), py = Math.round(n.y * TILE - cy);
      const im = image('nodes/' + n.item);
      if (im.complete) ctx.drawImage(im, px, py, TILE, TILE);
    }

    for (const n of m.npcs || []) {
      const px = Math.round(n.at[0] * TILE - cx), py = Math.round(n.at[1] * TILE - cy);
      const im = image('npcs/' + n.sprite);
      if (im.complete) ctx.drawImage(im, px, py, TILE, TILE);
      if (fx) npcAct(n.id, px, py, now);
      labels.push([n.name, px + TILE / 2, py - 14, n.role === 'quests' ? '#f0cf7a' : '#c8f0b0']);
      if ((n.role === 'quests' && P.view.questReady) || (n.role === 'daily' && P.view.dailyReady) || (n.role === 'chest' && P.view.chestReady)) label('!', px + TILE - 4, py - 2, '#f0cf7a');
    }

    // trùm thế giới: vẽ to gấp đôi, có thanh máu chung
    // C1 (DECISIONS "Sự kiện trực quan"): quầng đỏ nhấp nháy, thanh máu to có %, ⚔ khi mình đang đánh (⚡ ở lại bản đồ)
    if (m.worldBoss && boss.alive) {
      const [bx, by] = m.worldBoss;
      const px = Math.round(bx * TILE - cx), py = Math.round(by * TILE - cy);
      mpos.boss = [px + TILE / 2, py - TILE / 2];
      const pulse = fx ? 0.5 + 0.5 * Math.sin(now / 320) : 0.6;
      const g = ctx.createRadialGradient(px + TILE / 2, py, 4, px + TILE / 2, py, TILE * 1.9);
      g.addColorStop(0, `rgba(255, 80, 60, ${0.28 + 0.2 * pulse})`); g.addColorStop(1, 'rgba(255, 80, 60, 0)');
      ctx.fillStyle = g; ctx.fillRect(px - TILE * 1.5, py - TILE * 2, TILE * 4, TILE * 4);
      const im = image('monsters/ancient_dragon');
      if (im.complete) { ctx.shadowColor = '#ff5a3c'; ctx.shadowBlur = 10 + 10 * pulse; ctx.drawImage(im, px - TILE / 2, py - TILE, TILE * 2, TILE * 2); ctx.shadowBlur = 0; }
      const w = TILE * 3, k = Math.max(0, boss.hp / boss.maxHp), bx0 = px + TILE / 2 - w / 2, by0 = py - TILE - 12;
      ctx.fillStyle = 'rgba(12,9,16,0.88)'; ctx.fillRect(bx0, by0, w, 9);
      ctx.fillStyle = k < 0.25 ? '#ff4a2a' : '#d9483b'; ctx.fillRect(bx0 + 1, by0 + 1, Math.max(0, (w - 2) * k), 7);
      ctx.font = '800 8px system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = '#fff';
      ctx.fillText(`${Math.round(k * 100)}%`, px + TILE / 2, by0 + 5);
      const me = fight && fight.id === 'boss';
      if (names) labels.push([(me ? '⚔ ' : '') + boss.name, px + TILE / 2, by0 - 10, '#ef6a5a']);
      if (fx && me) { const ph = (now % 900) / 900; if (ph < 0.35) slashAt(px + TILE / 2, py, ph / 0.35, '#ffe9b0'); }
    }

    if (fx && P.pos.map === 'village') villageFx(now, m, cx, cy);
    miniMap(P, m, now, cx, cy);
    const hero = image('monsters/hero');
    // người chơi khác (DECISIONS "Người chơi trên bản đồ"): ưu tiên, giới hạn theo vùng thấy, xếp quạt khi đứng chồng
    drawPlayers(P, now, cx, cy, labels, mpos, fx);
    // không vẽ thú cưng trên bản đồ (rối bản đồ, anh yêu cầu 2026-10-23): thú chỉ hiện trong trận, hồ sơ, Nhà
    const look = P.view && P.view.look;
    const px = Math.round(mx * TILE - cx), py = Math.round(my * TILE - cy);
    if (fx) moveFx(now, m, P, cx, cy, px, py);
    if (look && (look.aura || look.wing)) heroAura(now, px, py, look, fx);
    if (look && look.pet === 'long_vuong') dragonAura(now, px, py, fx);
    if (look && (look.pet === 'hac_long' || look.pet === 'hac_long_chan')) hacAura(now, px, py, fx, look.pet === 'hac_long_chan');
    if (look && look.pet === 'chim_lac') birdAura(now, px, py, fx);
    ctx.fillStyle = 'rgba(240, 207, 122, 0.35)';
    ctx.beginPath(); ctx.ellipse(px + TILE / 2, py + TILE - 4, 12, 5, 0, 0, Math.PI * 2); ctx.fill();
    const myDoll = Doll.canvas(look);
    // đang đi: nhún nhẹ; vừa sang bản đồ: hiện ra từ nhỏ tới to (FX_PLAN đợt 5)
    const walking = fx && (mx !== P.pos.x || my !== P.pos.y);
    const bobY = walking ? -Math.abs(Math.sin(now / 85)) * 2.5 : 0;
    const grow = fx && arrive && now - arrive < 420 ? 0.35 + 0.65 * ((now - arrive) / 420) : 1;
    const hs = TILE * grow, hx = px + (TILE - hs) / 2, hy = py + (TILE - hs) + bobY;
    if (myDoll) ctx.drawImage(myDoll, hx, hy, hs, hs); else if (hero.complete) ctx.drawImage(hero, hx, hy, hs, hs);
    if (fx && levelAt && now - levelAt < 1600) levelColumn(px, py, (now - levelAt) / 1600);
    const mine = bubbleOf(userId, now);
    if (mine) talk.push([mine, px + TILE / 2, py]);
    // câu cá: cần, dây, phao, cá bay lên (chỉ phía mình)
    if (fishing) fishFx(now, m, cx, cy, px, py, fx);
    if (kiting) kiteFx(now, m, cx, cy, px, py, fx);
    // hướng dẫn người mới: vòng sáng nhấp nháy và mũi tên ở ô cần tới
    const goal = P.view && P.view.tutorial && P.view.tutorial.target;
    if (goal && goal.map === P.pos.map) {
      const gx = Math.round(goal.x * TILE - cx) + TILE / 2, gy = Math.round(goal.y * TILE - cy) + TILE / 2;
      const k = (Math.sin(now / 250) + 1) / 2;
      // ô đích bị khuất: mũi tên ở mép khung nhìn chỉ về phía đó
      edgeArrow(gx, gy, '240, 207, 122', now);
      ctx.strokeStyle = `rgba(240, 207, 122, ${0.5 + k * 0.5})`;
      ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(gx, gy, TILE * (0.55 + k * 0.15), 0, Math.PI * 2); ctx.stroke();
      const ay = gy - TILE - 6 - k * 6;
      ctx.fillStyle = '#f0cf7a';
      ctx.beginPath(); ctx.moveTo(gx - 8, ay); ctx.lineTo(gx + 8, ay); ctx.lineTo(gx, ay + 10); ctx.fill();
      if (!tutTimer) tutTimer = setTimeout(() => { tutTimer = null; draw(); }, 60);
    }
    if (fx) {
      // đài phun nước lấp lánh
      for (const [fx0, fy0] of fountains) {
        for (let i = 0; i < 5; i++) {
          const k = (now / 900 + i / 5) % 1;
          ctx.fillStyle = `rgba(230, 245, 255, ${0.8 * (1 - k)})`;
          ctx.fillRect(fx0 + TILE / 2 + Math.sin(i * 2.1) * 8 * k, fy0 + TILE / 2 - Math.sin(k * Math.PI) * 12, 2, 2);
        }
      }
      // Biển Long Vương: bóng cá, xoáy Vực Rồng, lá / hoa rơi, tia nắng sáng sớm / chiều tà
      if (m.fish === 'lake') lakeFx(now, m, cx, cy);
      // tầng Tháp / Quảng Trường / Lâu Đài / Kalima: hiệu ứng theo nền tầng (không có ngày đêm)
      const w = (outdoors(P) || m.tower) && weatherNow(m, P.pos.map);
      if (w) weather(w, now, cx, cy, m, P.pos.map);
      // Làng: khói bếp luôn có, thời tiết nào cũng vậy
      if (P.pos.map === 'village' && w !== 'smoke') weather('smoke', now, cx, cy, m, P.pos.map);
    }
    // bóng tối theo giờ: tối dần ra xa nhân vật, quanh nhân vật vẫn sáng (B6: chuyển dần, ánh cam hồng lúc bình minh / hoàng hôn)
    const [dark0, glowK] = outdoors(P) ? sky() : [0, 0];
    // Động Bí Ẩn (D7): tối hẳn, chỉ sáng một vòng quanh nhân vật như cầm đuốc
    const dark = m.secret ? 0.86 : dark0 > 0.02 ? dark0 : 0;
    if (fx && m.secret) caveFx(now, m, cx, cy, x0, y0, x1, y1);
    if (glowK > 0.02 && outdoors(P)) {
      const g = ctx.createLinearGradient(0, 0, 0, VH());
      const dusk = shade() === 'dusk';
      g.addColorStop(0, `rgba(${dusk ? '255, 110, 90' : '255, 170, 110'}, ${0.22 * glowK})`);
      g.addColorStop(1, `rgba(${dusk ? '140, 60, 120' : '255, 200, 150'}, ${0.08 * glowK})`);
      ctx.fillStyle = g; ctx.fillRect(0, 0, VW(), VH());
    }
    if (dark) {
      const lx = px + TILE / 2, ly = py + TILE / 2;
      const g = ctx.createRadialGradient(lx, ly, TILE * (m.secret ? 0.9 : 1.2), lx, ly, TILE * (m.secret ? 3.2 : 5));
      g.addColorStop(0, `rgba(8, 10, 32, ${dark * 0.25})`);
      g.addColorStop(1, `rgba(8, 10, 32, ${dark})`);
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, VW(), VH());
      if (fx && dark >= 0.3) nightGlow(now, m, cx, cy, dark);
      if (fx && dark >= 0.3) nightFx(now, m, cx, cy, dark, x0, y0, x1, y1);
      // đèn lồng (Biển Long Vương) tỏa sáng ban đêm
      if (dark >= 0.3) for (const [lx0, ly0] of lanterns) {
        const x = lx0 + 23, y = ly0 + 17, f = fx ? 0.85 + 0.15 * Math.sin(now / 230 + lx0) : 1;
        const g = ctx.createRadialGradient(x, y, 1, x, y, TILE * 1.8);
        g.addColorStop(0, `rgba(255, 120, 70, ${0.55 * dark * f})`); g.addColorStop(1, 'rgba(255, 120, 70, 0)');
        ctx.fillStyle = g; ctx.fillRect(x - TILE * 1.8, y - TILE * 1.8, TILE * 3.6, TILE * 3.6);
      }
    }
    if (m.fish === 'lake' && school && Date.now() < school.until) schoolSpot(now, school.x * TILE - cx, school.y * TILE - cy, fx);
    // Đồi Sáo Diều: Đàn Hạc, Chim Lạc lượn trên trời, Mảnh Sao rơi trên đồi; Tế Đàn: vòng Long Phượng Hội
    if (m.kite) {
      const t = Date.now();
      if (skyEv.flock && t < skyEv.flock.until) flockSpot(now, skyEv.flock.x * TILE - cx, skyEv.flock.y * TILE - cy, fx);
      if (skyEv.bird && t < skyEv.bird.until) birdSpot(now, skyEv.bird.x * TILE - cx, skyEv.bird.y * TILE - cy, fx);
      for (const [sx, sy] of skyEv.stars) starSpot(now, sx * TILE - cx, sy * TILE - cy, fx, labels);
      // mây trôi, chim lượn: vẽ lại liên tục (~16 khung / giây) khi bật hiệu ứng
      if (fx && !tutTimer) tutTimer = setTimeout(() => { tutTimer = null; draw(); }, 60);
    }
    if (skyEv.hoi && Date.now() < skyEv.hoi.until && P.pos.map === 'altar') hoiRing(now, skyEv.hoi, cx, cy, fx);
    if (m.fish === 'lake' && lake && Date.now() < lake.until) dragonSpot(now, lake.x * TILE - cx, lake.y * TILE - cy, fx);
    // Vương Miện khuất khỏi khung nhìn: mũi tên vàng ở mép chỉ về phía nó (D1)
    if (crownSpot) edgeArrow(crownSpot[0], crownSpot[1], '240, 207, 122', fx ? now : 0, '👑');
    for (const l of labels) label(...l);
    for (const t of talk) bubble(...t);
    eventHud(P, m, now);
    drawFloats(mpos, [Math.round(mx * TILE - cx) + TILE / 2, Math.round(my * TILE - cy)]);
    spots = { mpos, me: [Math.round(mx * TILE - cx) + TILE / 2, Math.round(my * TILE - cy)] };
    if (enter.map !== P.pos.map) enter = { map: P.pos.map, at: now };
    if (fx) enterFx(now, P, m, px, py);
    // vẽ lại khi bong bóng hết hạn
    if (bubbles.size && !bubbleTimer) bubbleTimer = setTimeout(() => { bubbleTimer = null; draw(); }, 1000);
    // bỏ những con quái/người đã biến mất khỏi bản đồ
    for (const [k, a] of anim) if (a.seen !== now) anim.delete(k);
    fxTick();
  }

  // Ô dưới ngón tay/chuột.
  function tileFromEvent(e) {
    const [cx, cy] = lastCam;
    const r = canvas.getBoundingClientRect();
    return [Math.floor(((e.clientX - r.left) / zoom + cx) / TILE), Math.floor(((e.clientY - r.top) / zoom + cy) / TILE)];
  }

  // Hướng của bước đầu tiên trên đường ngắn nhất tới (tx, ty), hoặc null.
  // Không đi xuyên quái hay cổng; riêng ô đích thì cho phép (đánh quái, qua cổng, uống nước giếng).
  function nextStep(P, tx, ty) {
    const m = cur(P);
    return window.HLLogic.firstStep(P.pos.x, P.pos.y, tx, ty, (nx, ny, goal) => {
      const c = tileAt(m, nx, ny);
      if (c == null) return false;
      if (goal) return true;
      const bossHere = boss.alive && m.worldBoss && m.worldBoss[0] === nx && m.worldBoss[1] === ny;
      // không đi ngang qua cầu thang (lên/xuống tầng ngoài ý muốn); ô đích thì được
      return !(!WALK.has(c) || PORTAL.has(c) || c === '<' || c === '>' || monsterAt(nx, ny) || nodeAt(nx, ny) || npcAt(m, nx, ny) || bossHere);
    });
  }

  // ---------- Biển Long Vương: không khí (chỉ vẽ, không ảnh hưởng luật) ----------
  const lakeCache = new Map();
  function lakeInfo(m) {
    if (lakeCache.has(m)) return lakeCache.get(m);
    let x0 = 1e9, y0 = 1e9, x1 = -1, y1 = -1, dx = 0, dy = 0, dn = 0;
    m.tiles.forEach((row, y) => [...row].forEach((c, x) => {
      if (c === '~' || c === '=') { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
      if (c === '=') { dx += x; dy += y; dn++; }
    }));
    const info = { x0, y0, x1, y1, deep: dn ? [dx / dn + 0.5, dy / dn + 0.5] : null };
    lakeCache.set(m, info);
    return info;
  }
  const isWater = (m, x, y) => '~='.includes((m.tiles[Math.floor(y)] || '')[Math.floor(x)] || '#');
  function lakeFx(t, m, cx, cy) {
    const L = lakeInfo(m), vw = VW(), vh = VH(), dark = PHASES[shade()] ? PHASES[shade()][1] : 0;
    // bóng cá lượn dưới nước (chỉ để trang trí, không liên quan tỉ lệ câu)
    for (let i = 0; i < 5; i++) {
      const sp = 9000 + i * 2300, k = t / sp + i * 1.7;
      const fx0 = L.x0 + 0.5 + (L.x1 - L.x0) * (0.5 + 0.45 * Math.sin(k * 2 * Math.PI));
      const fy0 = L.y0 + 0.5 + (L.y1 - L.y0) * (0.5 + 0.42 * Math.sin(k * 2 * Math.PI * 1.7 + i));
      if (!isWater(m, fx0, fy0)) continue;
      const ang = Math.atan2(Math.cos(k * 2 * Math.PI * 1.7 + i) * 1.7 * (L.y1 - L.y0), Math.cos(k * 2 * Math.PI) * (L.x1 - L.x0));
      const x = fx0 * TILE - cx, y = fy0 * TILE - cy, big = i === 0 ? 1.6 : 1;
      ctx.save(); ctx.translate(x, y); ctx.rotate(ang);
      ctx.fillStyle = 'rgba(0, 10, 25, 0.28)';
      ctx.beginPath(); ctx.ellipse(0, 0, 9 * big, 3.5 * big, 0, 0, Math.PI * 2); ctx.fill();
      const w = Math.sin(t / 150 + i) * 2;
      ctx.beginPath(); ctx.moveTo(-8 * big, 0); ctx.lineTo(-14 * big, -4 * big + w); ctx.lineTo(-14 * big, 4 * big + w); ctx.fill();
      ctx.restore();
    }
    // Vực Rồng: xoáy nước chậm
    if (L.deep) {
      const x = L.deep[0] * TILE - cx, y = L.deep[1] * TILE - cy;
      ctx.lineWidth = 2;
      for (let i = 0; i < 3; i++) {
        const a0 = t / (2600 + i * 700) + i * 2.1, r = TILE * (0.6 + i * 0.55);
        ctx.strokeStyle = `rgba(150, 210, 255, ${0.22 - i * 0.05})`;
        ctx.beginPath(); ctx.arc(x, y, r, a0, a0 + 2.2); ctx.stroke();
      }
    }
    if (dark < 0.3) {
      // ban ngày: lá vàng, hoa hồng rơi chậm, xoay nhẹ; neo theo bản đồ (không đi theo nhân vật / camera)
      const W = m.tiles[0].length * TILE, H = m.tiles.length * TILE;
      for (let i = 0; i < 30; i++) {
        const fall = 9000 + rnd(i, 3) * 6000, k = (t / fall + rnd(i, 4)) % 1;
        const x = wrap(rnd(i, 1) * W + Math.sin(t / 1400 + i) * 26, W) - cx, y = k * H - cy;
        if (x < -10 || y < -10 || x > vw + 10 || y > vh + 10) continue;
        ctx.save(); ctx.translate(x, y); ctx.rotate(Math.sin(t / 600 + i) * 1.2);
        ctx.fillStyle = i % 3 ? 'rgba(230, 180, 60, 0.75)' : 'rgba(245, 160, 190, 0.8)';
        ctx.beginPath(); ctx.ellipse(0, 0, 3.5, 1.8, 0, 0, Math.PI * 2); ctx.fill();
        ctx.restore();
      }
    }
    // tia nắng chéo lúc sáng sớm / chiều tà
    if (shade() === 'dawn' || shade() === 'dusk') {
      const col = shade() === 'dawn' ? '255, 230, 170' : '255, 190, 120';
      for (let i = 0; i < 3; i++) {
        const a = 0.07 + 0.05 * Math.sin(t / 2200 + i * 2), x = (i + 0.5) * m.tiles[0].length * TILE / 3 - cx;
        ctx.fillStyle = `rgba(${col}, ${a})`;
        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x + 60, 0); ctx.lineTo(x - 80, vh); ctx.lineTo(x - 170, vh); ctx.fill();
      }
    }
  }

  // Dấu bước chân (bụi trên đất, gợn nước trên bến / cầu gỗ), vòng sáng ở ô đích, cột sáng khi vừa sang bản đồ mới
  // cổng đi được: vòng xoáy sáng quay chậm
  function portalSwirl(x, y, t) {
    ctx.save();
    ctx.translate(x, y + 4); ctx.scale(1, 0.45);
    for (let i = 0; i < 3; i++) {
      const a = t / 600 + i * 2.1;
      ctx.strokeStyle = `rgba(150, 210, 255, ${0.55 - i * 0.12})`; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(0, 0, 9 + i * 4, a, a + 2.2); ctx.stroke();
    }
    ctx.restore();
  }

  // động tác người dân (chỉ là hình): Thợ Rèn gõ búa tia lửa, Bà Lang / Bác Đầu Bếp nồi bốc khói, Ông Lão giật cần,
  // Lão Hỗn Nguyên lò xoáy sáng
  function npcAct(id, px, py, t) {
    const x = px + TILE / 2, y = py + TILE / 2;
    if (id === 'blacksmith') {
      const k = (t % 1100) / 1100;
      if (k < 0.25) for (let i = 0; i < 6; i++) {
        const a = -Math.PI / 2 + (i - 2.5) * 0.45, r = 3 + k * 4 * 14;
        ctx.fillStyle = `rgba(255, ${190 + i * 10}, 90, ${1 - k * 4})`;
        ctx.fillRect(x + 8 + Math.cos(a) * r, y + 6 + Math.sin(a) * r, 2, 2);
      }
    } else if (id === 'herbalist' || id === 'cook') {
      for (let i = 0; i < 4; i++) {
        const k = ((t / 1800) + i / 4) % 1;
        ctx.fillStyle = id === 'herbalist' ? `rgba(160, 230, 170, ${0.45 * (1 - k)})` : `rgba(225, 220, 215, ${0.45 * (1 - k)})`;
        ctx.beginPath(); ctx.arc(x + 10 + Math.sin(t / 500 + i) * 3, y + 4 - k * 22, 2 + k * 4, 0, Math.PI * 2); ctx.fill();
      }
    } else if (id === 'fisher') {
      // cần câu giật nhẹ mỗi vài giây
      const tug = (t % 3200) < 260 ? Math.sin((t % 3200) / 260 * Math.PI) * 4 : 0;
      ctx.strokeStyle = 'rgba(120, 90, 50, 0.9)'; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.moveTo(x + 6, y); ctx.lineTo(x + 20, y - 12 - tug); ctx.stroke();
      ctx.strokeStyle = 'rgba(230, 230, 230, 0.6)'; ctx.lineWidth = 0.8;
      ctx.beginPath(); ctx.moveTo(x + 20, y - 12 - tug); ctx.lineTo(x + 24, y + 10); ctx.stroke();
    } else if (id === 'pet_keeper') {
      // B10: tim bay lên
      for (let i = 0; i < 2; i++) {
        const k = ((t / 2200) + i / 2) % 1;
        ctx.fillStyle = `rgba(255, 120, 150, ${0.8 * (1 - k)})`;
        heart(x + 9 + Math.sin(t / 400 + i * 3) * 3, y - 2 - k * 20, 2.6);
      }
    } else if (id === 'merchant' || id === 'dealer') {
      // B10: xu / lá bài lấp lánh
      const k = (t % 1600) / 1600;
      if (k < 0.5) {
        ctx.fillStyle = id === 'merchant' ? `rgba(255, 215, 90, ${1 - k * 2})` : `rgba(240, 240, 255, ${1 - k * 2})`;
        ctx.fillRect(x + 8, y - 4 - k * 16, id === 'merchant' ? 4 : 3, id === 'merchant' ? 4 : 5);
      }
    } else if (id === 'board') {
      // B10: tờ giấy rung theo gió
      ctx.fillStyle = 'rgba(245, 235, 210, 0.9)';
      ctx.save(); ctx.translate(x + 7, y - 6); ctx.rotate(Math.sin(t / 300) * 0.25); ctx.fillRect(-3, 0, 6, 7); ctx.restore();
    } else if (id === 'festival' || id === 'wardrobe') {
      // B10: hoa giấy / lấp lánh
      for (let i = 0; i < 5; i++) {
        const k = ((t / 1700) + i / 5) % 1;
        ctx.fillStyle = ['#ff6a6a', '#ffd24a', '#7fd08a', '#9fd8ff', '#c49bff'][i];
        ctx.globalAlpha = 0.85 * (1 - k);
        ctx.fillRect(x - 10 + i * 5 + Math.sin(t / 300 + i) * 3, y - 18 + k * 26, 2, 3);
        ctx.globalAlpha = 1;
      }
    } else if (id === 'tower_guard') {
      // B10: mũi giáo lóe sáng
      const k = (t % 2600) / 2600;
      if (k < 0.12) { ctx.fillStyle = `rgba(255, 255, 255, ${1 - k / 0.12})`; ctx.fillRect(x + 9, y - 16, 2, 6); ctx.fillRect(x + 7, y - 14, 6, 2); }
    } else if (id === 'girl') {
      // B10: cánh hoa bay
      for (let i = 0; i < 3; i++) {
        const k = ((t / 2600) + i / 3) % 1;
        ctx.fillStyle = `rgba(255, 180, 210, ${0.85 * (1 - k)})`;
        ctx.beginPath(); ctx.ellipse(x - 6 + k * 22, y - 8 + Math.sin(k * 6 + i) * 6, 2, 1.2, k * 4, 0, Math.PI * 2); ctx.fill();
      }
    } else if (id === 'chaos') {
      for (let i = 0; i < 3; i++) {
        const a = t / 400 + i * 2.1;
        ctx.fillStyle = ['#ff8a5a', '#c49bff', '#9fd8ff'][i];
        ctx.beginPath(); ctx.arc(x + Math.cos(a) * 13, y - 4 + Math.sin(a) * 5, 1.8, 0, Math.PI * 2); ctx.fill();
      }
    }
  }

  function heart(x, y, r) {
    ctx.beginPath(); ctx.moveTo(x, y + r);
    ctx.bezierCurveTo(x - r * 2, y - r * 0.4, x - r * 0.8, y - r * 1.8, x, y - r * 0.6);
    ctx.bezierCurveTo(x + r * 0.8, y - r * 1.8, x + r * 2, y - r * 0.4, x, y + r);
    ctx.fill();
  }

  // B10: Làng sống động — dân làng đi dạo theo vòng đường đất, chó chạy theo, cừu gặm cỏ, gà mổ thóc, cờ bay trên cột.
  // Chỉ là hình (không chắn đường, không bấm được); vị trí tính thẳng từ thời gian nên ai cũng thấy na ná nhau.
  const LOOP = [[6, 5], [18, 5], [18, 11], [6, 11]];
  function loopAt(k) {
    const segs = LOOP.map((a, i) => [a, LOOP[(i + 1) % LOOP.length]]);
    const lens = segs.map(([a, b]) => Math.abs(b[0] - a[0]) + Math.abs(b[1] - a[1]));
    let d = (((k % 1) + 1) % 1) * lens.reduce((s, v) => s + v, 0);
    for (let i = 0; i < segs.length; i++) {
      if (d <= lens[i]) { const [a, b] = segs[i], f = d / lens[i]; return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, Math.sign(b[0] - a[0])]; }
      d -= lens[i];
    }
    return [LOOP[0][0], LOOP[0][1], 1];
  }
  function sprite(path, x, y, s, flip) {
    const im = image(path);
    if (!im.complete) return;
    ctx.save(); ctx.translate(x + TILE / 2, y + TILE);
    if (flip) ctx.scale(-1, 1);
    ctx.drawImage(im, -TILE * s / 2, -TILE * s, TILE * s, TILE * s);
    ctx.restore();
  }
  function villageFx(t, m, cx, cy) {
    const walkers = [['npcs/carpenter', 0, 1 / 95000], ['npcs/hunter', 0.5, 1 / 110000]];
    for (const [img, off, sp] of walkers) {
      const [gx, gy, dir] = loopAt(off + t * sp);
      const px = gx * TILE - cx, py = gy * TILE - cy - Math.abs(Math.sin(t / 160 + off * 9)) * 1.5;
      ctx.fillStyle = 'rgba(0, 0, 0, 0.25)'; ctx.beginPath(); ctx.ellipse(px + TILE / 2, py + TILE - 3, 9, 3, 0, 0, Math.PI * 2); ctx.fill();
      sprite(img, px, py, 0.9, dir < 0);
    }
    // chó chạy theo người thứ nhất, lùi 1,2 ô
    {
      const [gx, gy, dir] = loopAt(t / 95000 - 0.03);
      const px = gx * TILE - cx, py = gy * TILE - cy + 6 - Math.abs(Math.sin(t / 110)) * 3;
      sprite('monsters/jackal', px, py, 0.6, dir > 0);
    }
    // cừu gặm cỏ ở bãi cỏ góc dưới phải (đi qua lại chậm), cúi đầu nhịp nhàng
    for (let i = 0; i < 2; i++) {
      const gx = 20.5 + Math.sin(t / 9000 + i * 2) * 1.5, gy = 12 + i * 0.5;
      sprite('monsters/wild_sheep', gx * TILE - cx, gy * TILE - cy + Math.max(0, Math.sin(t / 700 + i * 3)) * 2, 0.7, Math.cos(t / 9000 + i * 2) < 0);
    }
    // gà mổ thóc cạnh Bác Đầu Bếp
    for (let i = 0; i < 3; i++) {
      const gx = 3 + i * 0.7 + Math.sin(t / 4000 + i * 2.3) * 0.4, gy = 9.6 + (i % 2) * 0.4;
      const px = gx * TILE - cx, py = gy * TILE - cy, peck = (t / 380 + i * 1.7) % 3 < 0.4 ? 3 : 0;
      ctx.fillStyle = '#f2efe6'; ctx.beginPath(); ctx.ellipse(px, py, 5, 4, 0, 0, Math.PI * 2); ctx.fill();
      ctx.beginPath(); ctx.arc(px + 4, py - 3 + peck, 2.6, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = '#d9483b'; ctx.fillRect(px + 3.5, py - 6.5 + peck, 2, 2);
      ctx.fillStyle = '#e8b84a'; ctx.fillRect(px + 6.4, py - 3 + peck, 2, 1.2);
    }
    // cờ bay trên các cột đá (ô I)
    m.tiles.forEach((row, y) => [...row].forEach((c, x) => {
      if (c !== 'I') return;
      const px = x * TILE - cx + TILE / 2, py = y * TILE - cy - 6;
      ctx.fillStyle = '#5a4630'; ctx.fillRect(px - 1, py - 14, 2, 16);
      ctx.beginPath(); ctx.moveTo(px + 1, py - 14);
      for (let i = 0; i <= 6; i++) ctx.lineTo(px + 1 + i * 2.2, py - 14 + Math.sin(t / 200 + i * 0.8 + x) * 1.6 + i * 0.25);
      for (let i = 6; i >= 0; i--) ctx.lineTo(px + 1 + i * 2.2, py - 7 + Math.sin(t / 200 + i * 0.8 + x) * 1.6 - i * 0.25);
      ctx.closePath(); ctx.fillStyle = x % 2 ? '#c0392b' : '#e8b84a'; ctx.fill();
    }));
  }

  // cột sáng vàng khi lên cấp (k: 0..1)
  function levelColumn(px, py, k) {
    const x = px + TILE / 2, y = py + TILE - 4, h = 110 * Math.min(1, k * 4);
    const a = k < 0.7 ? 1 : (1 - k) / 0.3;
    const g = ctx.createLinearGradient(0, y - h, 0, y);
    g.addColorStop(0, 'rgba(255, 230, 140, 0)'); g.addColorStop(0.5, `rgba(255, 215, 90, ${0.55 * a})`); g.addColorStop(1, `rgba(255, 250, 220, ${0.9 * a})`);
    ctx.fillStyle = g; ctx.fillRect(x - 13, y - h, 26, h);
    ctx.strokeStyle = `rgba(255, 215, 90, ${a})`; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.ellipse(x, y, 8 + k * 26, 3 + k * 9, 0, 0, Math.PI * 2); ctx.stroke();
    for (let i = 0; i < 8; i++) {
      const kk = (k * 2 + i / 8) % 1;
      ctx.fillStyle = `rgba(255, 240, 170, ${a * (1 - kk)})`;
      ctx.fillRect(x + Math.sin(i * 1.7) * 12, y - kk * 90, 2, 2);
    }
  }

  // vệt chém chéo (k: 0..1) ở tâm (x, y)
  function slashAt(x, y, k, col) {
    ctx.save();
    ctx.globalAlpha = 1 - k; ctx.strokeStyle = col; ctx.lineWidth = 2.5; ctx.lineCap = 'round';
    const d = 9 + k * 6;
    ctx.beginPath(); ctx.moveTo(x - d, y - d); ctx.lineTo(x + d, y + d); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(x + d, y - d); ctx.lineTo(x - d, y + d); ctx.stroke();
    ctx.fillStyle = col;
    for (let i = 0; i < 4; i++) { const a = i * 1.57 + 0.6; ctx.beginPath(); ctx.arc(x + Math.cos(a) * d * 1.3, y + Math.sin(a) * d * 1.3, 1.6, 0, Math.PI * 2); ctx.fill(); }
    ctx.restore();
  }

  function drawMobFx(t, cx, cy) {
    mobFx = mobFx.filter((e) => t - e.t0 < e.life);
    for (const e of mobFx) {
      const k = Math.max(0, (t - e.t0) / e.life), x = e.x * TILE + TILE / 2 - cx, y = e.y * TILE + TILE / 2 - cy;
      if (e.k === 'hit') {
        // con mình đang đánh: hiệu ứng đòn thật đã vẽ (kỹ năng / đòn thường), không thêm dấu X
        if (!e.mine) slashAt(x, y, k, '#ffffff');
        ctx.save(); ctx.globalAlpha = 1 - k; ctx.font = '800 11px system-ui, sans-serif'; ctx.textAlign = 'center';
        ctx.lineWidth = 3; ctx.strokeStyle = '#000'; ctx.strokeText(`-${e.pct}%`, x, y - TILE * 0.6 - k * 14);
        ctx.fillStyle = '#ff8a6a'; ctx.fillText(`-${e.pct}%`, x, y - TILE * 0.6 - k * 14); ctx.restore();
      } else {
        // gục: hình mờ dần bay lên, hạt tỏa ra
        const im = image('monsters/' + e.kind);
        ctx.save();
        ctx.globalAlpha = (1 - k) * 0.8;
        if (im.complete && k < 0.6) ctx.drawImage(im, x - TILE / 2, y - TILE / 2 - k * 12, TILE, TILE);
        for (let i = 0; i < 14; i++) {
          const a = i * 2.39996, r = 4 + k * (14 + (i % 4) * 5);
          ctx.fillStyle = i % 3 ? '#e8dcc0' : '#ffd24a';
          ctx.beginPath(); ctx.arc(x + Math.cos(a) * r, y + Math.sin(a) * r - k * 16, 2 * (1 - k) + 0.5, 0, Math.PI * 2); ctx.fill();
        }
        ctx.restore();
      }
    }
  }

  // hào quang theo đồ (look.aura 7 / 9 / 11) + hạt sáng cánh rơi phía sau; tắt hiệu ứng thì chỉ vẽ quầng tĩnh
  const AURA = { 7: [111, 180, 255], 9: [255, 210, 74], 11: [255, 106, 42] };
  function heroAura(t, px, py, look, fx) {
    const x = px + TILE / 2, y = py + TILE / 2, c = AURA[look.aura];
    ctx.save();
    if (c) {
      const pulse = fx ? 0.5 + 0.5 * Math.sin(t / 380) : 0.5;
      const g = ctx.createRadialGradient(x, y + 4, 2, x, y + 4, TILE * 0.75);
      g.addColorStop(0, `rgba(${c}, ${0.35 + 0.2 * pulse})`); g.addColorStop(1, `rgba(${c}, 0)`);
      ctx.fillStyle = g; ctx.fillRect(x - TILE, y - TILE, TILE * 2, TILE * 2);
      ctx.strokeStyle = `rgba(${c}, ${0.5 + 0.3 * pulse})`; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.ellipse(x, py + TILE - 4, 13 + pulse * 2, 5 + pulse, 0, 0, Math.PI * 2); ctx.stroke();
      // +11: hạt cam đỏ bay lên; +9: vài đốm vàng
      const n = fx ? (look.aura >= 11 ? 7 : look.aura >= 9 ? 4 : 2) : 0;
      for (let i = 0; i < n; i++) {
        const k = ((t / 1400) + i / n) % 1, xx = x + Math.sin(i * 2.1 + t / 600) * 10;
        ctx.fillStyle = `rgba(${c}, ${1 - k})`;
        ctx.beginPath(); ctx.arc(xx, py + TILE - 6 - k * 30, 1.6, 0, Math.PI * 2); ctx.fill();
      }
    }
    if (look.wing && fx) {
      for (let i = 0; i < 4; i++) {
        const k = ((t / 1600) + i / 4) % 1, side = i % 2 ? 1 : -1;
        ctx.fillStyle = `rgba(232, 244, 255, ${0.85 * (1 - k)})`;
        ctx.beginPath(); ctx.arc(x + side * (12 + (i % 3) * 3), py + 8 + k * 26, 1.3, 0, Math.PI * 2); ctx.fill();
      }
    }
    ctx.restore();
  }

  // Long Vương đi theo (DECISIONS "Long Vương: thần thú độc nhất"): vầng vàng quanh chân và vài vảy rồng vàng xoay quanh
  function dragonAura(t, px, py, fx) {
    const x = px + TILE / 2, y = py + TILE - 4;
    const pulse = fx ? 0.5 + 0.5 * Math.sin(t / 500) : 0.5;
    ctx.save();
    ctx.strokeStyle = `rgba(255, 214, 90, ${0.45 + 0.3 * pulse})`; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.ellipse(x, y, 15 + pulse * 2, 6 + pulse, 0, 0, Math.PI * 2); ctx.stroke();
    if (fx) {
      for (let i = 0; i < 3; i++) {
        const a = t / 700 + (i * Math.PI * 2) / 3;
        ctx.fillStyle = `rgba(255, 200, 60, ${0.6 + 0.3 * Math.sin(t / 300 + i)})`;
        ctx.beginPath(); ctx.arc(x + Math.cos(a) * 15, y - 10 + Math.sin(a) * 6, 1.8, 0, Math.PI * 2); ctx.fill();
      }
    }
    ctx.restore();
  }

  // B11: bản đồ thu nhỏ ở góc khung bản đồ (tắt ở Cài đặt, `hl-minimap`): nền ô tô màu theo loại (vẽ sẵn mỗi bản đồ một lần),
  // chấm: mình (trắng), quái (đỏ, trùm vàng), cổng (tím), NPC (xanh); khung trắng là phần đang nhìn thấy
  // ⚡ Đánh nhanh (DECISIONS "Đánh nhanh theo combo"): số sát thương / máu hồi bay lên trên đầu quái (`target` = mã quái
  // trên bản đồ) hoặc mình ('me'), mờ dần ~0,9 giây
  const floats = [];
  let floatTimer = null;
  function floatText(target, text, col) {
    floats.push({ target: String(target), text, col, t0: performance.now() });
    if (floats.length > 12) floats.shift();
    draw();
  }
  function drawFloats(mpos, me) {
    const t = performance.now();
    for (let i = floats.length - 1; i >= 0; i--) {
      const f = floats[i], k = (t - f.t0) / 900;
      if (k >= 1) { floats.splice(i, 1); continue; }
      const pos = f.target === 'me' ? me : mpos[f.target];
      if (!pos) continue;
      const y = pos[1] - 8 - k * 28;
      ctx.globalAlpha = 1 - k * k;
      ctx.font = '800 15px system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'bottom';
      ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(10, 6, 12, 0.85)'; ctx.strokeText(f.text, pos[0], y);
      ctx.fillStyle = f.col; ctx.fillText(f.text, pos[0], y);
      ctx.globalAlpha = 1;
    }
    if (floats.length && !floatTimer) floatTimer = setTimeout(() => { floatTimer = null; draw(); }, 33);
  }
  const miniOn = () => { try { return localStorage.getItem('hl-minimap') !== '0'; } catch (e) { return true; } };
  const MINI_COL = { floor: '#3a3328', grass: '#3f5a2a', dirt: '#6a5030', flowers: '#4a6a30', tree: '#1f3a1a', tree_autumn: '#4a3a14', tree_dead: '#3a2e22',
    rock: '#5a4a3e', water: '#1e4a7a', deep_water: '#163a66', brick: '#7a3e2a', stone: '#6a6a70', column: '#9a9aa0', fountain: '#4a8ac0', waystone: '#c0a040',
    door: '#a07040', arch: '#a07040', portal: '#9a5aff', stairs_up: '#d0b060', stairs_down: '#80a0d0', mangrove: '#2a4a2a', lotus: '#3a6a5a', boat: '#5a3a20',
    pier_v: '#7a5a30', pier_h: '#7a5a30', dragon_statue: '#b09040', lantern: '#c05030', sand: '#c8b07a', palm: '#3a6a2a' };
  const miniCache = new Map();
  function miniBase(m, id) {
    if (miniCache.has(id)) return miniCache.get(id);
    const w = m.tiles[0].length, h = m.tiles.length, c = document.createElement('canvas');
    c.width = w; c.height = h;
    const g = c.getContext('2d');
    m.tiles.forEach((row, y) => [...row].forEach((ch, x) => { g.fillStyle = MINI_COL[WORLD.legend[ch]] || '#2a2430'; g.fillRect(x, y, 1, 1); }));
    miniCache.set(id, c);
    return c;
  }
  // giữ và kéo để dời bản đồ thu nhỏ: vị trí lưu theo tỉ lệ khoảng trống trong khung (`hl-minimap-pos`, {x, y} trong 0..1),
  // nên đổi cỡ khung / xoay máy vẫn ở đúng góc; bấm nhẹ (không kéo) vẫn mở bản đồ thế giới
  const MINI_PAD = 6;
  let miniPos = (() => { try { const v = JSON.parse(localStorage.getItem('hl-minimap-pos')); return v && v.x >= 0 && v.x <= 1 && v.y >= 0 && v.y <= 1 ? v : { x: 0, y: 0 }; } catch (e) { return { x: 0, y: 0 }; } })();
  function miniPlace(el) {
    const wrap = el.parentElement;
    if (!wrap) return;
    // thanh sự kiện ở mép trên (`eventHud`): bản đồ nhỏ không đè lên
    const top0 = MINI_PAD + hudPx;
    const fw = Math.max(0, wrap.clientWidth - el.offsetWidth - MINI_PAD * 2), fh = Math.max(0, wrap.clientHeight - el.offsetHeight - MINI_PAD - top0);
    const l = Math.round(MINI_PAD + miniPos.x * fw) + 'px', t = Math.round(top0 + miniPos.y * fh) + 'px';
    if (el.style.left !== l) el.style.left = l;
    if (el.style.top !== t) el.style.top = t;
  }
  let miniDrag = null, miniNoClick = false;
  document.addEventListener('pointerdown', (e) => {
    const el = e.target.closest && e.target.closest('#mini-map');
    if (!el || e.button > 0) return;
    const r = el.getBoundingClientRect();
    miniDrag = { el, id: e.pointerId, sx: e.clientX, sy: e.clientY, ox: e.clientX - r.left, oy: e.clientY - r.top, moved: false };
  });
  document.addEventListener('pointermove', (e) => {
    const d = miniDrag;
    if (!d || e.pointerId !== d.id) return;
    if (!d.moved && Math.hypot(e.clientX - d.sx, e.clientY - d.sy) < 6) return;
    if (!d.moved) { d.moved = true; d.el.classList.add('dragging'); try { d.el.setPointerCapture(d.id); } catch (err) { /* bỏ qua */ } }
    const wrap = d.el.parentElement;
    if (!wrap) return;
    const wr = wrap.getBoundingClientRect();
    const top0 = MINI_PAD + hudPx;
    const fw = Math.max(1, wrap.clientWidth - d.el.offsetWidth - MINI_PAD * 2), fh = Math.max(1, wrap.clientHeight - d.el.offsetHeight - MINI_PAD - top0);
    const clamp01 = (v) => Math.max(0, Math.min(1, v));
    miniPos = { x: clamp01((e.clientX - d.ox - wr.left - MINI_PAD) / fw), y: clamp01((e.clientY - d.oy - wr.top - top0) / fh) };
    miniPlace(d.el);
    e.preventDefault();
  });
  const miniEnd = (e) => {
    const d = miniDrag;
    if (!d || e.pointerId !== d.id) return;
    miniDrag = null;
    if (!d.moved) return;
    d.el.classList.remove('dragging');
    miniNoClick = true;
    setTimeout(() => { miniNoClick = false; }, 300);
    try { localStorage.setItem('hl-minimap-pos', JSON.stringify({ x: +miniPos.x.toFixed(3), y: +miniPos.y.toFixed(3) })); } catch (err) { /* bỏ qua */ }
  };
  document.addEventListener('pointerup', miniEnd);
  document.addEventListener('pointercancel', miniEnd);
  // vừa kéo xong thì nuốt cú click đi kèm (không mở bản đồ thế giới)
  document.addEventListener('click', (e) => {
    if (miniNoClick && e.target.closest && e.target.closest('#mini-map')) { miniNoClick = false; e.stopPropagation(); e.preventDefault(); }
  }, true);

  function miniMap(P, m, now, cx, cy) {
    const el = document.getElementById('mini-map');
    if (!el) return;
    const w = m.tiles[0].length, h = m.tiles.length, s = Math.max(2, Math.min(4, Math.floor(96 / Math.max(w, h * 1.4))));
    const dpr = window.devicePixelRatio || 1;
    if (el.width !== w * s * dpr) { el.width = w * s * dpr; el.height = h * s * dpr; el.style.width = w * s + 'px'; el.style.height = h * s + 'px'; }
    if (!miniDrag) miniPlace(el);
    const g = el.getContext('2d');
    g.setTransform(dpr, 0, 0, dpr, 0, 0); g.imageSmoothingEnabled = false;
    g.drawImage(miniBase(m, P.pos.map), 0, 0, w * s, h * s);
    const dot = (x, y, col, r) => { g.fillStyle = col; g.fillRect(x * s + s / 2 - r, y * s + s / 2 - r, r * 2, r * 2); };
    for (const n of m.npcs || []) dot(n.at[0], n.at[1], '#8fe08a', Math.max(1, s / 2));
    for (const p of m.portals || []) dot(p.at[0], p.at[1], '#c49bff', Math.max(1.2, s / 2));
    if (world.map === P.pos.map) for (const q of world.monsters || []) dot(q.x, q.y, q.boss ? '#ffd24a' : q.gold ? '#ffe08a' : '#ef5a4a', Math.max(1, s / 2.4));
    const blink = 0.6 + 0.4 * Math.sin(now / 200);
    // G2: trùm thế giới, Vương Miện (to, nhấp nháy); người chơi khác: hồng (khác quái đỏ, NPC xanh lá, cổng tím),
    // đồng đội tổ đội vàng chanh, người bang mình xanh dương, người bang địch đỏ cam viền trắng
    if (m.worldBoss && boss.alive) dot(m.worldBoss[0], m.worldBoss[1], `rgba(255, 70, 50, ${blink})`, Math.max(2.5, s * 1.1));
    // Đồi Sáo Diều: Chim Lạc (đồng, to), Đàn Hạc (trắng), Mảnh Sao (vàng); Tế Đàn: vòng Long Phượng Hội (tím)
    if (m.kite) {
      if (skyEv.bird) dot(skyEv.bird.x, skyEv.bird.y, `rgba(240, 170, 70, ${blink})`, Math.max(2.5, s * 1.1));
      if (skyEv.flock) dot(skyEv.flock.x, skyEv.flock.y, 'rgba(255, 255, 255, 0.95)', Math.max(2, s * 0.9));
      for (const [sx, sy] of skyEv.stars) dot(sx, sy, `rgba(255, 230, 120, ${blink})`, Math.max(1.5, s * 0.7));
    }
    if (skyEv.hoi && P.pos.map === 'altar') dot(skyEv.hoi.at[0], skyEv.hoi.at[1], `rgba(200, 140, 255, ${blink})`, Math.max(3, s * 1.4));
    if (world.map === P.pos.map) {
      const crown = m.event === 'castle_siege' && (world.monsters || []).find((q) => q.kind === CS.crownKind);
      if (crown) dot(crown.x, crown.y, `rgba(255, 215, 90, ${blink})`, Math.max(2.5, s * 1.1));
      const rel = relations() || {}, party = rel.party || [];
      const r = Math.max(1.5, s / 1.6);
      for (const o of world.players || []) {
        if (o.id === userId) continue;
        const enemy = rel.enemy && o.tag === rel.enemy;
        const col = party.includes(o.id) ? '#d4ff3a' : enemy ? '#ff7a2a' : rel.tag && o.tag === rel.tag ? '#5aa9ff' : '#ff6ad5';
        // viền tối cho nổi trên nền
        dot(o.x, o.y, enemy ? '#ffffff' : 'rgba(10, 6, 14, 0.9)', r + 0.8);
        dot(o.x, o.y, col, r);
      }
    }
    dot(P.pos.x, P.pos.y, `rgba(255, 255, 255, ${blink})`, Math.max(1.5, s * 0.7));
    g.strokeStyle = 'rgba(255, 255, 255, 0.55)'; g.lineWidth = 1;
    g.strokeRect(cx / TILE * s + 0.5, cy / TILE * s + 0.5, VW() / TILE * s, VH() / TILE * s);
  }

  // Động Bí Ẩn (D8): khe đá phát sáng tím — vết nứt sáng, hào quang nhấp nháy, hạt sáng bay ra
  function crackFx(px, py, t) {
    const st = image('tiles/stone');
    if (st.complete) ctx.drawImage(st, px, py, TILE, TILE);
    const k = t ? 0.7 + 0.3 * Math.sin(t / 300) : 1, cx0 = px + TILE / 2, cy0 = py + TILE / 2;
    const g = ctx.createRadialGradient(cx0, cy0, 1, cx0, cy0, TILE * 1.3);
    g.addColorStop(0, `rgba(190, 120, 255, ${0.55 * k})`); g.addColorStop(1, 'rgba(190, 120, 255, 0)');
    ctx.fillStyle = g; ctx.fillRect(px - TILE, py - TILE, TILE * 3, TILE * 3);
    ctx.strokeStyle = `rgba(235, 210, 255, ${0.95 * k})`; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(cx0 - 2, py + 3); ctx.lineTo(cx0 + 3, py + 11); ctx.lineTo(cx0 - 3, py + 18); ctx.lineTo(cx0 + 2, py + 29); ctx.stroke();
    if (t) for (let i = 0; i < 4; i++) {
      const q = ((t / 1400) + i / 4) % 1;
      ctx.fillStyle = `rgba(220, 180, 255, ${0.9 * (1 - q)})`;
      ctx.fillRect(cx0 + Math.sin(i * 2.3 + t / 500) * 8 * q, cy0 - q * 22, 2, 2);
    }
  }
  // Động Bí Ẩn (D7): pha lê lấp lánh trên vách / cột, sương tím trôi sát đất, nước nhỏ giọt (âm thanh thưa)
  let dripAt = 0;
  function caveFx(t, m, cx, cy, x0, y0, x1, y1) {
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const c = (m.tiles[y] || '')[x];
        if ((c === 'R' || c === 'I') && rnd(x * 5 + 7, y * 3 + 1) < 0.35) {
          const px = x * TILE - cx, py = y * TILE - cy, k = Math.max(0, Math.sin(t / 600 + x * 1.9 + y * 2.7));
          const col = rnd(x, y) > 0.5 ? '180, 140, 255' : '120, 220, 255';
          ctx.fillStyle = `rgba(${col}, ${0.35 + 0.5 * k})`;
          const bx = px + 8 + rnd(x + 1, y) * 14, by = py + 6 + rnd(x, y + 1) * 14;
          ctx.beginPath(); ctx.moveTo(bx, by - 6); ctx.lineTo(bx + 3, by); ctx.lineTo(bx, by + 3); ctx.lineTo(bx - 3, by); ctx.closePath(); ctx.fill();
          if (k > 0.92) { ctx.fillStyle = 'rgba(255, 255, 255, 0.9)'; ctx.fillRect(bx - 0.5, by - 8, 1, 4); ctx.fillRect(bx - 2, by - 6.5, 4, 1); }
        }
      }
    }
    const vw = VW(), vh = VH();
    for (let i = 0; i < 7; i++) {
      const x = wrap(rnd(i, 1) * (vw + 200) + t * 0.01 * (1 + rnd(i, 2)) - cx, vw + 200) - 100, y = wrap(rnd(i, 3) * vh - cy, vh);
      const g = ctx.createRadialGradient(x, y, 4, x, y, 90);
      g.addColorStop(0, 'rgba(150, 90, 220, 0.14)'); g.addColorStop(1, 'rgba(150, 90, 220, 0)');
      ctx.fillStyle = g; ctx.fillRect(x - 90, y - 90, 180, 180);
    }
    if (t - dripAt > 5200 + rnd(Math.floor(t / 5000), 3) * 4000) { dripAt = t; if (window.Sound) window.Sound.play('drip'); }
  }

  // B1: Rừng Tre — ô cây vẽ thành bụi tre (3–4 thân có đốt, lá nhọn, lay theo gió)
  function bamboo(px, py, gx, gy, t) {
    const n = 3 + Math.floor(rnd(gx, gy) * 2);
    for (let i = 0; i < n; i++) {
      const bx = px + 5 + (i / n) * (TILE - 8) + rnd(gx + i, gy) * 4, h = TILE + 6 + rnd(gx, gy + i) * 10;
      const sw = t ? Math.sin(t / 800 + gx * 0.7 + i) * 2.5 : 0;
      const tx = bx + sw, ty = py + TILE - h;
      ctx.strokeStyle = i % 2 ? '#7aa83e' : '#8cbc48'; ctx.lineWidth = 2.6;
      ctx.beginPath(); ctx.moveTo(bx, py + TILE); ctx.quadraticCurveTo(bx + sw * 0.3, py + TILE - h / 2, tx, ty); ctx.stroke();
      ctx.fillStyle = '#4f7428';
      for (let k = 0.25; k < 1; k += 0.25) ctx.fillRect(bx + sw * k * k - 1.6, py + TILE - h * k, 3.2, 1.2);
      ctx.fillStyle = 'rgba(120, 175, 60, 0.9)';
      for (let l = 0; l < 3; l++) {
        const a = -0.6 + l * 0.6 + (t ? Math.sin(t / 600 + l + i) * 0.15 : 0);
        ctx.save(); ctx.translate(tx, ty + l * 3); ctx.rotate(a + (l === 1 ? Math.PI : 0) * 0.15);
        ctx.beginPath(); ctx.ellipse(l === 1 ? -5 : 5, 0, 6, 1.4, 0, 0, Math.PI * 2); ctx.fill(); ctx.restore();
      }
    }
  }
  // B3: Ruộng Bậc Thang — mạ lúa mọc thành hàng trên ô nước
  // ---------- Biển Long Vương: cát, dừa, nước theo độ sâu, sóng dạt bờ, hải âu (vẽ bằng code, không cần hình) ----------
  const SEA_KINDS = { sand: 1, palm: 1, water: 1, deep_water: 1, boat: 1, pier_v: 1, pier_h: 1, dirt: 1, rock: 1 };
  const WET = { water: 1, deep_water: 1, boat: 1, pier_v: 1, pier_h: 1 };
  // mép trên của cát / của biển theo cột (ô), ranh nối mềm giữa các cột (như chân trời Đồi Sáo Diều)
  const seaCols = new Map();
  function seaEdges(m) {
    let e = seaCols.get(m.id);
    if (e) return e;
    const W = m.tiles[0].length, H = m.tiles.length, sand = [], shore = [];
    for (let x = 0; x < W; x++) {
      let a = H, b = H;
      for (let y = 4; y < H; y++) { const k = kindAt(m, x, y); if (a === H && (k === 'sand' || WET[k] || k === 'palm')) a = y; if (WET[k]) { b = y; break; } }
      sand.push(a); shore.push(b);
    }
    e = { sand, shore };
    seaCols.set(m.id, e);
    return e;
  }
  function edgeY(arr, wx, seed) {
    const w = arr.length, a = wx / TILE - 0.5, c0 = Math.floor(a), t = a - c0;
    const v = (c) => arr[Math.max(0, Math.min(w - 1, c))];
    const k = Math.max(0, Math.min(1, (t - 0.15) / 0.7)), s = k * k * (3 - 2 * k);
    return (v(c0) + (v(c0 + 1) - v(c0)) * s) * TILE + 2.4 * Math.sin(wx * 0.07 + seed) + 1.3 * Math.sin(wx * 0.19 + seed * 2) + 0.6 * Math.sin(wx * 0.41);
  }
  // tấm vân cát lặp liền mạch (128 px, chu kỳ khớp mép nên không lộ chỗ nối)
  let sandPat = null;
  function sandPattern() {
    if (sandPat) return sandPat;
    const N = 128, c = document.createElement('canvas'); c.width = c.height = N;
    const g = c.getContext('2d'), img = g.createImageData(N, N), d = img.data, P = (2 * Math.PI) / N;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const n = (Math.sin(x * P * 2 + Math.sin(y * P * 3) * 1.5) + Math.sin(y * P * 4 + x * P) * 0.6 + Math.sin((x + y) * P * 6) * 0.25) / 1.85;
        const ripple = Math.sin(y * P * 11 + Math.sin(x * P * 2) * 2.2) * 0.5 + 0.5;
        const grain = rnd(x * 131 + y * 17, 7) - 0.5;
        const l = 1 + n * 0.045 - ripple * 0.03 + grain * 0.07;
        const i = (y * N + x) * 4;
        d[i] = Math.min(255, 221 * l); d[i + 1] = Math.min(255, 197 * l); d[i + 2] = Math.min(255, 148 * l); d[i + 3] = 255;
      }
    }
    g.putImageData(img, 0, 0);
    sandPat = ctx.createPattern(c, 'repeat');
    return sandPat;
  }
  // tấm vân đất đường làng (lặp liền mạch)
  let dirtPat = null;
  function dirtPattern() {
    if (dirtPat) return dirtPat;
    const N = 96, c = document.createElement('canvas'); c.width = c.height = N;
    const g = c.getContext('2d'), img = g.createImageData(N, N), d = img.data, P = (2 * Math.PI) / N;
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const n = (Math.sin(x * P * 3 + Math.sin(y * P * 2) * 2) + Math.sin(y * P * 5 - x * P * 2) * 0.7) / 1.7;
        const grain = rnd(x * 37 + y * 101, 13) - 0.5;
        const l = 1 + n * 0.07 + grain * 0.16;
        const i = (y * N + x) * 4;
        d[i] = Math.min(255, 132 * l); d[i + 1] = Math.min(255, 98 * l); d[i + 2] = Math.min(255, 58 * l); d[i + 3] = 255;
      }
    }
    g.putImageData(img, 0, 0);
    dirtPat = ctx.createPattern(c, 'repeat');
    return dirtPat;
  }
  // đường đất liền mạch: mỗi ô đất là một đốm tròn, nối sang ô đất / cổng bên cạnh, mép mềm (bóng tối nhẹ ngoài rìa)
  function roadWorld(m, x0, y0, x1, y1) {
    const isRoad = (x, y) => { const k = kindAt(m, x, y); return k === 'dirt' || k === 'portal'; };
    const shape = (grow) => {
      ctx.beginPath();
      for (let y = y0 - 1; y <= y1 + 1; y++) {
        for (let x = x0 - 1; x <= x1 + 1; x++) {
          if (kindAt(m, x, y) !== 'dirt') continue;
          const cx0 = x * TILE + TILE / 2, cy0 = y * TILE + TILE / 2, r = TILE * 0.5 + grow;
          ctx.moveTo(cx0 + r, cy0); ctx.arc(cx0, cy0, r, 0, Math.PI * 2);
          if (isRoad(x + 1, y)) ctx.rect(cx0, cy0 - r * 0.86, TILE, r * 1.72);
          if (isRoad(x, y + 1)) ctx.rect(cx0 - r * 0.86, cy0, r * 1.72, TILE);
        }
      }
    };
    shape(4); ctx.fillStyle = 'rgba(60, 45, 25, 0.28)'; ctx.fill();
    shape(0); ctx.fillStyle = dirtPattern(); ctx.fill();
  }
  // đá ghềnh tròn (thay hình đá vuông): khối đá bóng bẩy, rêu, bọt nước quanh chân nếu đứng trong nước
  function boulder(x, y, gx, gy, wet, t) {
    const r = 12 + rnd(gx * 3 + gy, 5) * 3;
    ctx.save();
    if (wet && t) { ctx.strokeStyle = `rgba(255,255,255,${0.35 + 0.25 * Math.sin(t / 500 + gx)})`; ctx.lineWidth = 2; ctx.beginPath(); ctx.ellipse(x, y + r * 0.45, r * 1.1, r * 0.4, 0, 0, Math.PI * 2); ctx.stroke(); }
    ctx.fillStyle = 'rgba(0,0,0,0.25)'; ctx.beginPath(); ctx.ellipse(x + 2, y + r * 0.5, r, r * 0.35, 0, 0, Math.PI * 2); ctx.fill();
    const gr = ctx.createRadialGradient(x - r * 0.35, y - r * 0.4, 2, x, y, r);
    gr.addColorStop(0, '#a49a8c'); gr.addColorStop(0.6, '#6f665c'); gr.addColorStop(1, '#3e3832');
    ctx.fillStyle = gr; ctx.beginPath();
    for (let i = 0; i <= 10; i++) { const a = (i / 10) * Math.PI * 2, rr = r * (0.82 + rnd(gx * 7 + gy * 5 + i, 3) * 0.22); ctx.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr * 0.78); }
    ctx.closePath(); ctx.fill();
    ctx.fillStyle = 'rgba(90, 130, 70, 0.45)'; ctx.beginPath(); ctx.ellipse(x - r * 0.2, y - r * 0.45, r * 0.45, r * 0.18, -0.3, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  }
  // vẽ cả vùng biển: cát → biển (màu theo khoảng cách tới bờ) → gợn / nắng → sóng dạt bờ → cầu tàu, thuyền, dừa → hải âu
  // thuyền thúng (đan tre tròn) nổi trên nước, nghiêng nhẹ theo sóng
  function basketBoat(x, y, tilt) {
    ctx.save(); ctx.translate(x, y); ctx.rotate(tilt);
    ctx.fillStyle = 'rgba(10, 40, 70, 0.35)'; ctx.beginPath(); ctx.ellipse(1, 4, 14, 6, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#7a5428'; ctx.beginPath(); ctx.ellipse(0, 0, 13, 9, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#4a3014'; ctx.beginPath(); ctx.ellipse(0, -1, 10, 6, 0, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = 'rgba(200, 160, 90, 0.55)'; ctx.lineWidth = 0.8;
    for (let i = -9; i <= 9; i += 3) { ctx.beginPath(); ctx.moveTo(i, -6); ctx.lineTo(i * 0.9, 5); ctx.stroke(); }
    ctx.strokeStyle = '#a07438'; ctx.lineWidth = 2; ctx.beginPath(); ctx.ellipse(0, 0, 13, 9, 0, 0, Math.PI * 2); ctx.stroke();
    // mái chèo gác ngang
    ctx.strokeStyle = '#c09050'; ctx.lineWidth = 1.6; ctx.beginPath(); ctx.moveTo(-15, 4); ctx.lineTo(12, -6); ctx.stroke();
    ctx.restore();
  }
  function seaWorld(m, cx, cy, x0, y0, x1, y1, t) {
    const e = seaEdges(m), L = x0 * TILE - TILE, R = (x1 + 2) * TILE, B = (m.tiles.length + 1) * TILE;
    const sandTop = (wx) => edgeY(e.sand, wx, 1.1), shoreY = (wx) => edgeY(e.shore, wx, 2.7);
    ctx.save();
    ctx.translate(-cx, -cy);
    roadWorld(m, x0, y0, x1, y1);
    // cát: một mảng liền, mép trên cong mềm giáp cỏ
    ctx.beginPath(); ctx.moveTo(L, B);
    for (let wx = L; wx <= R; wx += 4) ctx.lineTo(wx, sandTop(wx));
    ctx.lineTo(R, B); ctx.closePath();
    ctx.fillStyle = sandPattern(); ctx.fill();
    // mép cỏ → cát: viền tối mềm và vài chùm cỏ lấn ra cát
    ctx.strokeStyle = 'rgba(70, 90, 40, 0.35)'; ctx.lineWidth = 3;
    ctx.beginPath(); for (let wx = L; wx <= R; wx += 4) { const y = sandTop(wx) + 1; if (wx === L) ctx.moveTo(wx, y); else ctx.lineTo(wx, y); } ctx.stroke();
    for (let wx = Math.ceil(L / 9) * 9; wx <= R; wx += 9) {
      if (rnd(wx, 3) < 0.55) continue;
      const y = sandTop(wx) + 2, sw = t ? Math.sin(t / 900 + wx) * 1.2 : 0;
      ctx.strokeStyle = 'rgba(74, 120, 50, 0.85)'; ctx.lineWidth = 1.2;
      ctx.beginPath(); ctx.moveTo(wx, y); ctx.lineTo(wx - 2 + sw, y + 5); ctx.moveTo(wx, y); ctx.lineTo(wx + 2 + sw, y + 6); ctx.stroke();
    }
    // biển: mép trên là đường bờ cong; màu theo độ sâu (gradient từ bờ ra khơi)
    const top = Math.min(...e.shore) * TILE;
    const g = ctx.createLinearGradient(0, top, 0, top + 7 * TILE);
    g.addColorStop(0, '#46c6cc'); g.addColorStop(0.35, '#2a8fb0'); g.addColorStop(1, '#123a70');
    ctx.beginPath(); ctx.moveTo(L, B);
    for (let wx = L; wx <= R; wx += 4) ctx.lineTo(wx, shoreY(wx));
    ctx.lineTo(R, B); ctx.closePath();
    ctx.fillStyle = g; ctx.fill();
    ctx.save(); ctx.clip();
    // dải nước nông xanh ngọc ôm theo bờ
    ctx.strokeStyle = 'rgba(120, 230, 225, 0.32)'; ctx.lineWidth = 26;
    ctx.beginPath(); for (let wx = L; wx <= R; wx += 6) { const y = shoreY(wx) + 6; if (wx === L) ctx.moveTo(wx, y); else ctx.lineTo(wx, y); } ctx.stroke();
    if (t) {
      // gợn sóng dài trôi ngang + đốm nắng lấp lánh, rải liên tục theo tọa độ thế giới
      const ys = Math.floor((cy) / 14) * 14, ye = cy + VH() + 14;
      for (let wy = Math.max(ys, top); wy <= ye; wy += 14) {
        const deep = Math.min(1, (wy - top) / (7 * TILE));
        for (let k = 0; k < 3; k++) {
          const span = 160, ph = ((t / (2600 + k * 700)) * span + rnd(wy, k) * span) % span;
          const wx = Math.floor(L / span) * span + ph + k * 53;
          for (let x = wx; x < R; x += span) {
            ctx.fillStyle = `rgba(230, 250, 255, ${0.13 - deep * 0.06})`;
            ctx.fillRect(x, wy + Math.sin(x * 0.05 + t / 900) * 2, 18 + k * 6, 1.4);
          }
        }
      }
      for (let i = 0; i < 40; i++) {
        const wx = L + rnd(i, 11) * (R - L), wy = top + rnd(i, 23) * (B - top), a = Math.max(0, Math.sin(t / 320 + i * 1.7));
        ctx.fillStyle = `rgba(255, 255, 240, ${a * 0.5})`; ctx.fillRect(wx, wy, 2, 2);
      }
    }
    ctx.restore();
    // sóng dạt bờ: lưỡi nước + bọt trắng dâng lên cát rồi rút, lệch nhịp mềm dọc bờ, để lại vệt cát ướt
    if (t) {
      const reach = (wx) => {
        const ph = (t / 4400 + Math.sin(wx * 0.006) * 0.35 + wx * 0.0011) % 1;
        const up = ph < 0.35 ? Math.sin((ph / 0.35) * Math.PI / 2) : Math.cos(((ph - 0.35) / 0.65) * Math.PI / 2);
        return up * TILE * 0.6;
      };
      const pts = [];
      for (let wx = L; wx <= R; wx += 4) pts.push([wx, shoreY(wx), reach(wx)]);
      ctx.fillStyle = 'rgba(150, 118, 70, 0.22)';
      ctx.beginPath(); pts.forEach(([x, y, r], i) => (i ? ctx.lineTo(x, y - r - 5) : ctx.moveTo(x, y - r - 5))); for (let i = pts.length - 1; i >= 0; i--) ctx.lineTo(pts[i][0], pts[i][1] + 2); ctx.closePath(); ctx.fill();
      ctx.fillStyle = 'rgba(125, 220, 222, 0.55)';
      ctx.beginPath(); pts.forEach(([x, y, r], i) => (i ? ctx.lineTo(x, y - r) : ctx.moveTo(x, y - r))); for (let i = pts.length - 1; i >= 0; i--) ctx.lineTo(pts[i][0], pts[i][1] + 2); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.85)'; ctx.lineWidth = 2.2; ctx.lineCap = 'round';
      ctx.beginPath(); pts.forEach(([x, y, r], i) => { const yy = y - r - 1 - Math.sin(x * 0.2 + t / 450) * 1.2; if (i) ctx.lineTo(x, yy); else ctx.moveTo(x, yy); }); ctx.stroke();
      for (const [x, y, r] of pts) if (rnd(x, 5) < 0.3) { ctx.fillStyle = `rgba(255,255,255,${0.6 * r / (TILE * 0.6)})`; ctx.fillRect(x, y - r + 3 + rnd(x, 9) * 4, 1.6, 1.6); }
    }
    ctx.restore();
    // cầu tàu, thuyền, dừa: vẽ đè lên mặt nước / cát
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const k = kindAt(m, x, y), px = Math.round(x * TILE - cx), py = Math.round(y * TILE - cy);
        if (k === 'pier_v' || k === 'pier_h') { const im = image('tiles/' + k); if (im.complete) ctx.drawImage(im, px, py, TILE, TILE); }
        else if (k === 'boat') basketBoat(px + TILE / 2, py + TILE / 2 + (t ? Math.sin(t / 700 + x) * 1.5 : 0), t ? Math.sin(t / 900 + x) * 0.08 : 0);
        else if (k === 'palm') palmTile(px, py, x, y, t, null);
        else if (k === 'rock') boulder(px + TILE / 2, py + TILE / 2, x, y, !!WET[kindAt(m, x, y + 1)] || !!WET[kindAt(m, x + 1, y)], t);
      }
    }
    seaShore(m, cx, cy, x0, y0, x1, y1, t, true);
  }
  const isSea = (k) => k === 'water' || k === 'deep_water' || k === 'boat';
  const kindAt = (m, x, y) => WORLD.legend[(m.tiles[y] || '')[x]];
  // khoảng cách (ô) tới bờ gần nhất phía trên, để tô nước nông → sâu
  function seaDepth(m, x, y) {
    let d = 0;
    // cầu tàu đứng trên nước: tính như nước (không làm cột dưới cầu nông lại)
    const wet = (k) => isSea(k) || k === 'pier_v' || k === 'pier_h';
    while (d < 8 && wet(kindAt(m, x, y - d - 1))) d++;
    return d;
  }
  // cát mịn: vân sáng / tối liền mạch qua các ô (nhiễu theo tọa độ thế giới), gợn cát cong nối tiếp, hạt nhỏ dày và mờ;
  // vẽ sẵn mỗi ô một lần (cache) cho nhẹ
  const sandCache = new Map();
  const sandNoise = (x, y) => (Math.sin(x * 0.11 + y * 0.07) + Math.sin(x * 0.05 - y * 0.13 + 1.7) + Math.sin((x + y) * 0.031 + 4.1)) / 3;
  function sandTile(px, py, gx, gy) {
    const key = gx + ',' + gy;
    let c = sandCache.get(key);
    if (!c) {
      c = document.createElement('canvas'); c.width = c.height = TILE;
      const g = c.getContext('2d');
      g.fillStyle = '#dcc493'; g.fillRect(0, 0, TILE, TILE);
      // vân lớn: ô 4×4 px, sáng / tối rất nhẹ theo nhiễu liền mạch
      for (let y = 0; y < TILE; y += 4) {
        for (let x = 0; x < TILE; x += 4) {
          const n = sandNoise(gx * TILE + x, gy * TILE + y);
          g.fillStyle = n > 0 ? `rgba(255, 246, 215, ${n * 0.22})` : `rgba(150, 112, 60, ${-n * 0.16})`;
          g.fillRect(x, y, 4, 4);
        }
      }
      // gợn cát do gió: đường cong mảnh theo tọa độ thế giới (nối liền giữa các ô)
      g.strokeStyle = 'rgba(160, 125, 70, 0.10)'; g.lineWidth = 1;
      for (let k = -1; k < 4; k++) {
        const base = k * 11 - ((gy * TILE) % 11);
        g.beginPath();
        for (let x = 0; x <= TILE; x += 2) { const wx = gx * TILE + x; const y = base + Math.sin(wx * 0.09 + k) * 2.5; if (x === 0) g.moveTo(x, y); else g.lineTo(x, y); }
        g.stroke();
      }
      // hạt cát li ti
      for (let i = 0; i < 70; i++) {
        const r1 = rnd(gx * 31 + gy * 17 + i * 7, 97), r2 = rnd(gx * 13 + gy * 29 + i * 11, 89), r3 = rnd(gx * 7 + gy * 3 + i, 41);
        g.fillStyle = r3 < 0.5 ? 'rgba(120, 90, 50, 0.16)' : r3 < 0.85 ? 'rgba(255, 250, 230, 0.35)' : 'rgba(190, 150, 95, 0.3)';
        g.fillRect(Math.floor(r1 * TILE), Math.floor(r2 * TILE), 1, 1);
      }
      sandCache.set(key, c);
    }
    ctx.drawImage(c, px, py, TILE, TILE);
  }
  // ô có cát bên cạnh (dừa / đá trên bãi cát thì lót cát; trên cỏ thì giữ nền cỏ)
  const nearSand = (m, x, y) => [[0, 1], [0, -1], [1, 0], [-1, 0]].filter(([dx, dy]) => kindAt(m, x + dx, y + dy) === 'sand').length >= 2;
  function palmTile(px, py, gx, gy, t, m) {
    if (m && nearSand(m, gx, gy)) sandTile(px, py, gx, gy);
    const sway = t ? Math.sin(t / 1100 + gx * 0.9) * 2.5 : 0;
    const bx = px + TILE / 2, by = py + TILE - 2, tx = bx + 5 + sway, ty = py + 4;
    ctx.save();
    ctx.fillStyle = 'rgba(0,0,0,0.18)'; ctx.beginPath(); ctx.ellipse(bx + 6, by, 10, 3, 0, 0, Math.PI * 2); ctx.fill();
    // thân cong có đốt
    ctx.strokeStyle = '#7a5530'; ctx.lineWidth = 3.2; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(bx, by); ctx.quadraticCurveTo(bx - 2, py + TILE * 0.45, tx, ty); ctx.stroke();
    ctx.strokeStyle = '#5a3c20'; ctx.lineWidth = 1;
    for (let i = 1; i < 6; i++) { const k = i / 6, x = bx + (tx - bx) * k - 1.5, y = by + (ty - by) * k; ctx.beginPath(); ctx.moveTo(x - 1.5, y); ctx.lineTo(x + 1.5, y); ctx.stroke(); }
    // tàu lá xòe, lay theo gió
    for (let i = 0; i < 6; i++) {
      const a = -Math.PI / 2 + (i - 2.5) * 0.62 + sway * 0.03, len = 13 + (i % 2) * 3;
      const ex = tx + Math.cos(a) * len, ey = ty + Math.sin(a) * len * 0.6 + 6;
      ctx.strokeStyle = i % 2 ? '#2f7a34' : '#3c9440'; ctx.lineWidth = 2.6;
      ctx.beginPath(); ctx.moveTo(tx, ty); ctx.quadraticCurveTo((tx + ex) / 2, Math.min(ty, ey) - 5, ex, ey); ctx.stroke();
    }
    ctx.fillStyle = '#6a4a22'; ctx.beginPath(); ctx.arc(tx - 1, ty + 2, 1.8, 0, Math.PI * 2); ctx.arc(tx + 2, ty + 3, 1.8, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
  }
  function seaTile(m, kind, px, py, gx, gy, t) {
    if (kind === 'sand') return sandTile(px, py, gx, gy);
    if (kind === 'palm') return palmTile(px, py, gx, gy, t, m);
    // nước: nông (xanh ngọc) → sâu (lam thẫm) theo khoảng cách tới bờ; lấy trung bình 3 cột cạnh nhau và chuyển dần
    // từ mép trên xuống mép dưới ô, nên không thành sọc / bậc theo từng ô
    const dd = (y) => {
      let sum = 0;
      for (let k = -1; k <= 1; k++) { const kk = kindAt(m, gx + k, y); sum += isSea(kk) || kk === 'pier_v' || kk === 'pier_h' ? seaDepth(m, gx + k, y) : -0.6; }
      return Math.max(0, Math.min(1, (sum / 3 + 0.3) / 7));
    };
    const d = dd(gy), d2 = dd(gy + 1) || d;
    const col = (k) => { const c0 = [64, 196, 204], c1 = [18, 58, 112]; return `rgb(${c0.map((v, i) => Math.round(v + (c1[i] - v) * k)).join(',')})`; };
    const g = ctx.createLinearGradient(0, py, 0, py + TILE);
    g.addColorStop(0, col(d)); g.addColorStop(1, col(Math.max(d, d2)));
    ctx.fillStyle = g; ctx.fillRect(px, py, TILE + 0.5, TILE + 0.5);
    if (!t) return;
    // gợn sóng dài trôi ngang + đốm nắng lấp lánh
    for (let k = 0; k < 3; k++) {
      const ph = (t / (2200 + k * 500) + gx * 0.21 + gy * 0.47 + k * 0.33) % 1;
      ctx.fillStyle = `rgba(230, 250, 255, ${(0.16 - d * 0.08) * Math.sin(ph * Math.PI)})`;
      ctx.fillRect(px + ph * TILE - 6, py + 5 + k * 10, 14, 1.5);
    }
    const tw = rnd(gx * 7 + gy * 3, 50);
    if (tw < 0.3) { const a = Math.max(0, Math.sin(t / 300 + tw * 40)); ctx.fillStyle = `rgba(255, 255, 240, ${a * 0.55})`; ctx.fillRect(px + tw * 90 % TILE, py + (tw * 170) % TILE, 2, 2); }
  }
  // sóng dạt vào bờ: dải bọt trắng ở mép nước giáp cát, dâng lên cát rồi rút (để lại vệt cát ướt), lệch nhịp theo cột
  function seaShore(m, cx, cy, x0, y0, x1, y1, t, gullsOnly) {
    if (!t) return;
    ctx.save();
    if (!gullsOnly) {
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const k = kindAt(m, x, y);
        if (!isSea(k) || !GROUND[kindAt(m, x, y - 1)] && kindAt(m, x, y - 1) !== 'palm') continue;
        const px = x * TILE - cx, py = y * TILE - cy;
        const ph = ((t / 4200) + x * 0.045) % 1;
        // dâng nhanh, rút chậm
        const up = ph < 0.35 ? Math.sin((ph / 0.35) * Math.PI / 2) : Math.cos(((ph - 0.35) / 0.65) * Math.PI / 2);
        const reach = up * TILE * 0.55;
        // vệt cát ướt
        ctx.fillStyle = `rgba(150, 120, 70, ${0.28 * up})`;
        ctx.fillRect(px, py - reach - 3, TILE, reach + 3);
        // lưỡi sóng nước trong
        ctx.fillStyle = 'rgba(120, 215, 220, 0.55)';
        ctx.fillRect(px, py - reach, TILE, reach);
        // mép bọt gợn
        ctx.fillStyle = `rgba(255, 255, 255, ${0.5 + 0.4 * up})`;
        ctx.beginPath();
        ctx.moveTo(px, py - reach);
        for (let i = 0; i <= 4; i++) ctx.lineTo(px + (i * TILE) / 4, py - reach - 1.5 - Math.sin(i * 1.7 + x + t / 500) * 1.5);
        ctx.lineTo(px + TILE, py - reach + 2.5); ctx.lineTo(px, py - reach + 2.5); ctx.closePath(); ctx.fill();
        // bọt li ti
        for (let i = 0; i < 4; i++) {
          const r = rnd(x * 19 + i * 5, 61);
          ctx.fillStyle = `rgba(255, 255, 255, ${0.55 * up})`;
          ctx.fillRect(px + r * TILE, py - reach + 3 + (i % 2) * 3, 1.6, 1.6);
        }
      }
    }
    }
    // hải âu bay ngang trên biển (3 con, vòng lặp chậm)
    ctx.strokeStyle = 'rgba(250, 250, 250, 0.9)'; ctx.lineWidth = 1.4;
    const W = m.tiles[0].length * TILE;
    for (let i = 0; i < 3; i++) {
      const gx = ((t / (90 + i * 25) + i * 300) % (W + 200)) - 100 - cx;
      const gy = (m.tiles.length - 7 + i * 1.6) * TILE - cy + Math.sin(t / 700 + i) * 8;
      const flap = Math.sin(t / 140 + i * 2) * 3;
      ctx.beginPath(); ctx.moveTo(gx - 6, gy - flap); ctx.quadraticCurveTo(gx - 3, gy - 3, gx, gy); ctx.quadraticCurveTo(gx + 3, gy - 3, gx + 6, gy - flap); ctx.stroke();
    }
    ctx.restore();
  }

  function paddy(px, py, gx, gy, t) {
    ctx.strokeStyle = 'rgba(150, 200, 70, 0.9)'; ctx.lineWidth = 1.2;
    ctx.beginPath();
    for (let r = 0; r < 3; r++) {
      for (let c = 0; c < 4; c++) {
        const bx = px + 4 + c * 8 + (r % 2) * 3, by = py + 9 + r * 9, sw = t ? Math.sin(t / 700 + gx * 0.5 + c) * 1.4 : 0;
        ctx.moveTo(bx, by); ctx.lineTo(bx - 2 + sw, by - 6);
        ctx.moveTo(bx, by); ctx.lineTo(bx + 2 + sw, by - 6);
        ctx.moveTo(bx, by); ctx.lineTo(bx + sw, by - 7);
      }
    }
    ctx.stroke();
  }

  // B9: mép ô mềm + bóng đổ + trang trí rải theo ô (chỉ vẽ, vị trí cố định theo ô, không chắn đường)
  const WALLS = new Set(['#', 'R', 'S', 'I', 'K', 'T', 'Y']);
  const WATERS = new Set(['~', '=']);
  const DECOR = {
    forest: ['pebble', 'flower', 'mushroom', 'flower'], swamp: ['mushroom', 'reed', 'pebble'], camp: ['pebble', 'bone', 'pebble'],
    graveyard: ['bone', 'pebble', 'crack'], mountain: ['pebble', 'crack', 'pebble'], lair: ['crack', 'pebble', 'bone'], grass: ['flower', 'pebble', 'flower'],
  };
  function groundFx(m, x0, y0, x1, y1, cx, cy, t, fx) {
    const at = (x, y) => (m.tiles[y] || '')[x];
    const theme = ((m.floor || '').split('/')[1] || 'grass');
    const decor = DECOR[theme] || DECOR.grass;
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const c = at(x, y), px = Math.round(x * TILE - cx), py = Math.round(y * TILE - cy);
        // bóng đổ của tường / đá / cây xuống ô đi được ngay dưới
        if (WALK.has(c) && WALLS.has(at(x, y - 1))) {
          const g = ctx.createLinearGradient(0, py, 0, py + 11);
          g.addColorStop(0, 'rgba(0, 0, 0, 0.32)'); g.addColorStop(1, 'rgba(0, 0, 0, 0)');
          ctx.fillStyle = g; ctx.fillRect(px, py, TILE, 11);
        }
        if (WALK.has(c) && WALLS.has(at(x - 1, y))) {
          const g = ctx.createLinearGradient(px, 0, px + 6, 0);
          g.addColorStop(0, 'rgba(0, 0, 0, 0.18)'); g.addColorStop(1, 'rgba(0, 0, 0, 0)');
          ctx.fillStyle = g; ctx.fillRect(px, py, 6, TILE);
        }
        // bờ nước: nước sát bờ tối hơn, viền bọt sáng lăn tăn
        if (WATERS.has(c)) {
          for (const [dx, dy] of [[0, -1], [0, 1], [-1, 0], [1, 0]]) {
            const n = at(x + dx, y + dy);
            if (n == null || WATERS.has(n) || !WALK.has(n)) continue;
            const vert = dy !== 0;
            // dải sáng mềm sát bờ (bọt), nhấp nhô nhẹ theo thời gian
            const pulse = fx ? 0.22 + 0.06 * Math.sin(t / 900 + x * 1.3 + y) : 0.24;
            const g = vert
              ? ctx.createLinearGradient(0, dy > 0 ? py + TILE : py, 0, dy > 0 ? py + TILE - 7 : py + 7)
              : ctx.createLinearGradient(dx > 0 ? px + TILE : px, 0, dx > 0 ? px + TILE - 7 : px + 7, 0);
            g.addColorStop(0, `rgba(225, 240, 255, ${pulse})`); g.addColorStop(1, 'rgba(225, 240, 255, 0)');
            ctx.fillStyle = g;
            ctx.fillRect(vert ? px : (dx > 0 ? px + TILE - 7 : px), vert ? (dy > 0 ? py + TILE - 7 : py) : py, vert ? TILE : 7, vert ? 7 : TILE);
          }
        }
        // đường đất lấn mép mềm vào cỏ / nền
        if (c === ':') {
          for (const [dx, dy] of [[0, -1], [0, 1], [-1, 0], [1, 0]]) {
            const n = at(x + dx, y + dy);
            if (n !== ',' && n !== '.' && n !== '*') continue;
            ctx.fillStyle = 'rgba(150, 112, 62, 0.55)';
            for (let i = 0; i < 5; i++) {
              const k = (i + rnd(x * 5 + i, y * 3 + dx + dy * 2)) / 5, r = 1.6 + rnd(x + i, y - i) * 2.4;
              const bx = dx ? (dx > 0 ? px + TILE + r * 0.6 : px - r * 0.6) : px + k * TILE;
              const by = dy ? (dy > 0 ? py + TILE + r * 0.6 : py - r * 0.6) : py + k * TILE;
              ctx.beginPath(); ctx.arc(bx, by, r, 0, Math.PI * 2); ctx.fill();
            }
          }
        }
        // trang trí rải: ~12 % ô nền / cỏ, không ở ô cổng, cạnh tường
        if ((c === '.' || c === ',') && rnd(x * 11 + 3, y * 17 + 5) < 0.12) {
          const kind = decor[Math.floor(rnd(x + 31, y + 7) * decor.length)];
          const dx = px + 6 + rnd(x, y * 2) * (TILE - 12), dy = py + 8 + rnd(x * 2, y) * (TILE - 14);
          decorAt(kind, dx, dy, x, y);
        }
      }
    }
  }
  function decorAt(kind, x, y, gx, gy) {
    if (kind === 'pebble') {
      ctx.fillStyle = 'rgba(160, 155, 150, 0.75)'; ctx.beginPath(); ctx.ellipse(x, y, 2.4, 1.6, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = 'rgba(120, 115, 110, 0.7)'; ctx.beginPath(); ctx.ellipse(x + 3.5, y + 1.5, 1.6, 1.1, 0, 0, Math.PI * 2); ctx.fill();
    } else if (kind === 'flower') {
      const col = ['#f2d24a', '#f08aa8', '#ffffff', '#b38cff'][Math.floor(rnd(gx + 3, gy + 9) * 4)];
      for (const [ox, oy] of [[0, 0], [4, 2], [-3, 3]]) {
        ctx.fillStyle = '#4f8a3a'; ctx.fillRect(x + ox, y + oy, 1, 3);
        ctx.fillStyle = col; ctx.beginPath(); ctx.arc(x + ox + 0.5, y + oy, 1.5, 0, Math.PI * 2); ctx.fill();
      }
    } else if (kind === 'mushroom') {
      ctx.fillStyle = '#e8dcc2'; ctx.fillRect(x - 0.8, y - 1, 1.8, 3.5);
      ctx.fillStyle = rnd(gx, gy) > 0.5 ? '#c0392b' : '#b08050';
      ctx.beginPath(); ctx.ellipse(x, y - 1.2, 3, 2, 0, Math.PI, 0); ctx.fill();
      ctx.fillStyle = '#fff'; ctx.fillRect(x - 1.5, y - 2.4, 1, 1);
    } else if (kind === 'reed') {
      ctx.strokeStyle = 'rgba(140, 160, 80, 0.9)'; ctx.lineWidth = 1;
      ctx.beginPath(); for (let i = -1; i <= 1; i++) { ctx.moveTo(x + i * 2, y + 3); ctx.lineTo(x + i * 3, y - 6); } ctx.stroke();
      ctx.fillStyle = '#6a4a2a'; ctx.fillRect(x - 0.6, y - 7, 1.6, 3);
    } else if (kind === 'bone') {
      ctx.strokeStyle = 'rgba(230, 225, 210, 0.8)'; ctx.lineWidth = 1.6; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(x - 4, y + 1); ctx.lineTo(x + 4, y - 1); ctx.stroke();
      ctx.fillStyle = 'rgba(230, 225, 210, 0.8)';
      for (const [ox, oy] of [[-4, 1], [4, -1]]) { ctx.beginPath(); ctx.arc(x + ox, y + oy, 1.5, 0, Math.PI * 2); ctx.fill(); }
    } else if (kind === 'crack') {
      ctx.strokeStyle = 'rgba(0, 0, 0, 0.35)'; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(x - 5, y - 2); ctx.lineTo(x - 1, y); ctx.lineTo(x + 1, y - 3); ctx.lineTo(x + 5, y + 1); ctx.moveTo(x - 1, y); ctx.lineTo(x, y + 4); ctx.stroke();
    }
  }

  // B7: bụi cỏ — 3 lá cỏ mảnh lay theo gió (lệch pha theo vị trí, gió thổi từng đợt)
  function grassFx(t, tufts) {
    ctx.lineWidth = 1.2; ctx.lineCap = 'round';
    const gust = 0.6 + 0.4 * Math.sin(t / 2300);
    for (const [px, py, x, y] of tufts) {
      const bx = px + 6 + rnd(x, y + 3) * (TILE - 14), by = py + 12 + rnd(x + 5, y) * (TILE - 14);
      const sw = Math.sin(t / 650 + x * 0.9 + y * 0.4) * 2.6 * gust;
      ctx.strokeStyle = rnd(x, y) > 0.5 ? 'rgba(150, 200, 90, 0.85)' : 'rgba(110, 170, 70, 0.85)';
      ctx.beginPath();
      for (let i = -1; i <= 1; i++) { ctx.moveTo(bx + i * 2.5, by); ctx.quadraticCurveTo(bx + i * 3 + sw * 0.5, by - 4, bx + i * 3.5 + sw, by - 7 - Math.abs(i) * -1); }
      ctx.stroke();
    }
  }
  // B7: dấu chân mờ dần 5 giây (tuyết: lõm xanh xám; cát: nâu), cỏ bắn lên khi vừa bước vào bụi cỏ
  function printFx(t, cx, cy) {
    prints = prints.filter((s) => t - s.t0 < 5000);
    for (const s of prints) {
      const a = 0.5 * (1 - (t - s.t0) / 5000), x = s.x * TILE + TILE / 2 - cx, y = s.y * TILE + TILE / 2 + 6 - cy;
      const ang = Math.atan2(s.dy, s.dx) + Math.PI / 2;
      ctx.save(); ctx.translate(x, y); ctx.rotate(ang);
      ctx.fillStyle = s.snow ? `rgba(120, 140, 170, ${a})` : `rgba(120, 90, 50, ${a})`;
      ctx.beginPath(); ctx.ellipse(-3.5, -2, 2, 3.2, 0, 0, Math.PI * 2); ctx.fill();
      ctx.beginPath(); ctx.ellipse(3.5, 3, 2, 3.2, 0, 0, Math.PI * 2); ctx.fill();
      ctx.restore();
    }
    rustle = rustle.filter((s) => t - s.t0 < 600);
    for (const s of rustle) {
      const k = (t - s.t0) / 600, x = s.x * TILE + TILE / 2 - cx, y = s.y * TILE + TILE - 6 - cy;
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * Math.PI - Math.PI, r = 4 + k * 12;
        ctx.fillStyle = `rgba(${130 + i * 10}, ${190 - i * 5}, 80, ${0.8 * (1 - k)})`;
        ctx.fillRect(x + Math.cos(a) * r, y + Math.sin(a) * r * 0.8 + k * k * 8, 2, 3);
      }
    }
  }

  function moveFx(t, m, P, cx, cy, px, py) {
    const key = `${P.pos.map}:${P.pos.x},${P.pos.y}`;
    if (lastTile && lastTile.key !== key) {
      if (lastTile.map === P.pos.map) {
        steps.push({ x: lastTile.x, y: lastTile.y, t0: t, wet: '=~'.includes((m.tiles[lastTile.y] || '')[lastTile.x]) });
        const f = m.floor || '';
        if (/mountain|camp/.test(f)) prints.push({ x: lastTile.x, y: lastTile.y, t0: t, dx: P.pos.x - lastTile.x, dy: P.pos.y - lastTile.y, snow: f.includes('mountain') });
        if ((m.tiles[P.pos.y] || '')[P.pos.x] === ',' || ((m.tiles[P.pos.y] || '')[P.pos.x] === '.' && /forest|swamp/.test(f))) rustle.push({ x: P.pos.x, y: P.pos.y, t0: t });
        if (prints.length > 40) prints.shift();
      } else { arrive = t; prints = []; rustle = []; }
      stillSince = t;
    }
    lastTile = { key, map: P.pos.map, x: P.pos.x, y: P.pos.y };
    if (!stillSince) stillSince = t;
    // đứng yên ven hồ: gợn nước lan ra ở ô nước kề bên, mỗi ~1,8 giây
    if (t - stillSince > 600) {
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        if (!isWater(m, P.pos.x + dx, P.pos.y + dy)) continue;
        const k = ((t - stillSince) % 1800) / 1800, x = (P.pos.x + dx) * TILE + TILE / 2 - cx, y = (P.pos.y + dy) * TILE + TILE / 2 - cy;
        ctx.strokeStyle = `rgba(210, 235, 255, ${0.5 * (1 - k)})`; ctx.lineWidth = 1.2;
        ctx.beginPath(); ctx.ellipse(x - dx * 8, y - dy * 6, 3 + k * 12, 1.5 + k * 5, 0, 0, Math.PI * 2); ctx.stroke();
        break;
      }
    }
    steps = steps.filter((s) => t - s.t0 < 520);
    for (const s of steps) {
      const k = (t - s.t0) / 520, x = s.x * TILE + TILE / 2 - cx, y = s.y * TILE + TILE - 5 - cy;
      if (s.wet) {
        ctx.strokeStyle = `rgba(200, 235, 255, ${0.6 * (1 - k)})`; ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.ellipse(x, y, 5 + k * 10, 2 + k * 4, 0, 0, Math.PI * 2); ctx.stroke();
      } else {
        ctx.fillStyle = `rgba(205, 185, 150, ${0.45 * (1 - k)})`;
        for (let i = -1; i <= 1; i++) { ctx.beginPath(); ctx.arc(x + i * (4 + k * 6), y - k * 4 - Math.abs(i) * 1, 2 + k * 2.5, 0, Math.PI * 2); ctx.fill(); }
      }
    }
    if (mark && t - mark.t0 < 900 && mark.map === P.pos.map) {
      const k = (t - mark.t0) / 900, x = mark.x * TILE + TILE / 2 - cx, y = mark.y * TILE + TILE / 2 - cy;
      ctx.strokeStyle = `rgba(240, 207, 122, ${0.9 * (1 - k)})`; ctx.lineWidth = 2;
      for (const d of [0, 0.35]) { const kk = Math.max(0, k - d); ctx.beginPath(); ctx.ellipse(x, y + 8, 4 + kk * 14, 2 + kk * 6, 0, 0, Math.PI * 2); ctx.stroke(); }
    } else if (mark && t - mark.t0 >= 900) mark = null;
    if (arrive && t - arrive < 800) {
      const k = (t - arrive) / 800, x = px + TILE / 2, y = py + TILE - 4;
      const g = ctx.createLinearGradient(x - 14, 0, x + 14, 0);
      g.addColorStop(0, 'rgba(180, 220, 255, 0)'); g.addColorStop(0.5, `rgba(220, 240, 255, ${0.7 * (1 - k)})`); g.addColorStop(1, 'rgba(180, 220, 255, 0)');
      ctx.fillStyle = g; ctx.fillRect(x - 14, y - 70 * (1 - k * 0.3), 28, 70 * (1 - k * 0.3));
      ctx.strokeStyle = `rgba(200, 230, 255, ${0.8 * (1 - k)})`; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.ellipse(x, y, 6 + k * 22, 3 + k * 9, 0, 0, Math.PI * 2); ctx.stroke();
    }
  }

  // Long Vương nổi: bóng rồng vàng lượn dưới ô nước, bọt vàng sủi lên (vẽ cả khi tắt hiệu ứng, chỉ không động)
  function dragonSpot(t, x, y, fx) {
    const c = x + TILE / 2, d = y + TILE / 2, k = fx ? t : 0;
    const g = ctx.createRadialGradient(c, d, 2, c, d, TILE * 0.9);
    g.addColorStop(0, `rgba(255, 215, 90, ${0.55 + 0.2 * Math.sin(k / 300)})`); g.addColorStop(1, 'rgba(255, 215, 90, 0)');
    ctx.fillStyle = g; ctx.fillRect(c - TILE, d - TILE, TILE * 2, TILE * 2);
    // thân rồng: chuỗi vảy uốn lượn quanh ô
    ctx.fillStyle = 'rgba(120, 80, 0, 0.45)';
    for (let i = 0; i < 9; i++) {
      const a = k / 900 + i * 0.45, r = TILE * 0.32;
      ctx.beginPath(); ctx.arc(c + Math.cos(a) * r, d + Math.sin(a * 1.3) * r * 0.6, 4.5 - i * 0.35, 0, Math.PI * 2); ctx.fill();
    }
    // bọt vàng
    for (let i = 0; i < 6; i++) {
      const p = fx ? (t / 1100 + i / 6) % 1 : i / 6;
      ctx.fillStyle = `rgba(255, 236, 150, ${0.9 * (1 - p)})`;
      ctx.beginPath(); ctx.arc(c + Math.sin(i * 2.4) * TILE * 0.3, d - p * TILE * 0.45, 1.5 + p * 2, 0, Math.PI * 2); ctx.fill();
    }
    ctx.strokeStyle = 'rgba(255, 220, 110, 0.8)'; ctx.lineWidth = 1.5;
    ctx.strokeRect(x + 1, y + 1, TILE - 2, TILE - 2);
  }

  // Đàn Cá Vàng: vài con cá vàng lượn vòng, lấp lánh (vẽ cả khi tắt hiệu ứng, chỉ không động)
  function schoolSpot(t, x, y, fx) {
    const c = x + TILE / 2, d = y + TILE / 2, k = fx ? t : 0;
    for (let i = 0; i < 5; i++) {
      const a = k / 700 + i * 1.26, r = TILE * (0.18 + 0.06 * (i % 2));
      ctx.save(); ctx.translate(c + Math.cos(a) * r, d + Math.sin(a) * r * 0.7); ctx.rotate(a + Math.PI / 2);
      ctx.fillStyle = 'rgba(255, 190, 40, 0.85)';
      ctx.beginPath(); ctx.ellipse(0, 0, 3.5, 1.6, 0, 0, Math.PI * 2); ctx.fill();
      ctx.beginPath(); ctx.moveTo(-3, 0); ctx.lineTo(-6, -2); ctx.lineTo(-6, 2); ctx.fill();
      ctx.restore();
    }
    for (let i = 0; i < 4; i++) {
      const p = fx ? (t / 500 + i / 4) % 1 : i / 4;
      ctx.fillStyle = `rgba(255, 250, 200, ${0.9 * Math.sin(p * Math.PI)})`;
      ctx.fillRect(x + 4 + ((i * 11) % (TILE - 8)), y + 4 + ((i * 7 + 5) % (TILE - 8)), 2, 2);
    }
    ctx.strokeStyle = 'rgba(255, 200, 80, 0.5)'; ctx.setLineDash([3, 3]); ctx.lineWidth = 1;
    ctx.strokeRect(x + 1, y + 1, TILE - 2, TILE - 2); ctx.setLineDash([]);
  }

  // ---------- Đồi Sáo Diều (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long") ----------
  // trời Đồi Sáo Diều: một dải chuyển màu liền (xanh đậm trên cao → xanh nhạt chân trời), ánh nắng, 3 lớp mây mềm trôi
  // (hình mây CC0 `sky/cloud1..5`: xa nhỏ chậm mờ, gần to nhanh rõ; lớp xa ít trôi theo camera hơn → có chiều sâu), sương
  // mỏng ở chân trời, đồi xa mờ dần. Trời cắt theo đường chân trời cong (`horizon`), không theo cạnh ô.
  // Đường chân trời: mặt đồi là một đường cong liền (không theo cạnh ô): mỗi cột lấy mặt đất ngay dưới mép trời, giữa các
  // cột dốc mềm (smoothstep), cộng gợn nhỏ như mô đất. Tọa độ thế giới (pixel), dùng chung cho trời, đồi xa, viền cỏ.
  const groundTop = (m, c) => { let y = 0; while (y < m.tiles.length && (m.tiles[y] || '')[c] === '^') y++; return y * TILE; };
  function horizon(m, wx) {
    const w = m.tiles[0].length, a = wx / TILE - 0.5, c0 = Math.floor(a), t = a - c0;
    const v = (c) => groundTop(m, Math.max(0, Math.min(w - 1, c)));
    const k = Math.max(0, Math.min(1, (t - 0.2) / 0.6)), s = k * k * (3 - 2 * k);
    return v(c0) + (v(c0 + 1) - v(c0)) * s + 2.2 * Math.sin(wx * 0.11 + 1.3) + 1.6 * Math.sin(wx * 0.043) + 0.8 * Math.sin(wx * 0.29);
  }
  // đường cong trên màn hình (bước 3px), dùng cho cắt trời và vẽ viền
  function horizonPts(m, cx, cy) {
    const pts = [];
    for (let sx = -3; sx <= VW() + 3; sx += 3) pts.push([sx, horizon(m, sx + cx) - cy]);
    return pts;
  }
  function skyClip(m, cx, cy) {
    const pts = horizonPts(m, cx, cy);
    ctx.beginPath(); ctx.moveTo(pts[0][0], -4);
    for (const [x, y] of pts) ctx.lineTo(x, y);
    ctx.lineTo(pts[pts.length - 1][0], -4); ctx.closePath(); ctx.clip();
  }
  // đồi xa nhiều lớp: càng xa càng nhạt, ngả xanh lam (phối cảnh không khí), trôi theo camera ít hơn (thị sai)
  const FAR_HILLS = [
    { col: [150, 185, 214], a: 0.55, par: 0.25, h: 30, f: [0.009, 0.023], ph: 0.7 },
    { col: [118, 165, 160], a: 0.65, par: 0.45, h: 20, f: [0.014, 0.037], ph: 2.1 },
    { col: [92, 148, 104], a: 0.75, par: 0.7, h: 12, f: [0.021, 0.055], ph: 4.2 },
  ];
  function farHills(m, cx, cy) {
    const w = m.tiles[0].length;
    let base = Infinity;
    for (let c = 0; c < w; c++) base = Math.min(base, groundTop(m, c));
    FAR_HILLS.forEach((L) => {
      ctx.fillStyle = `rgba(${L.col.join(',')}, ${L.a})`;
      ctx.beginPath(); ctx.moveTo(-3, VH() + 4);
      for (let sx = -3; sx <= VW() + 3; sx += 4) {
        const wx = sx + cx * L.par;
        const top = base + 6 - L.h * (0.55 + 0.3 * Math.sin(wx * L.f[0] + L.ph) + 0.15 * Math.sin(wx * L.f[1] + L.ph * 2));
        ctx.lineTo(sx, top - cy);
      }
      ctx.lineTo(VW() + 3, VH() + 4); ctx.closePath(); ctx.fill();
    });
  }
  // mép đồi giáp trời theo đường cong: bóng mềm phía đất, viền nắng, cỏ lún phún lay theo gió
  function skyEdge(t, m, cx, cy, fx) {
    const pts = horizonPts(m, cx, cy);
    const line = (dy) => { ctx.beginPath(); pts.forEach(([x, y], i) => (i ? ctx.lineTo(x, y + dy) : ctx.moveTo(x, y + dy))); };
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    line(5); ctx.strokeStyle = 'rgba(18, 48, 18, 0.22)'; ctx.lineWidth = 10; ctx.stroke();
    line(2); ctx.strokeStyle = 'rgba(30, 70, 25, 0.35)'; ctx.lineWidth = 4; ctx.stroke();
    line(0); ctx.strokeStyle = 'rgba(160, 215, 110, 0.85)'; ctx.lineWidth = 1.6; ctx.stroke();
    for (let i = 0; i < pts.length; i++) {
      const [x, y] = pts[i], wx = x + cx;
      for (let j = 0; j < 2; j++) {
        const r1 = rnd(Math.round(wx) * 3 + j, 7), r2 = rnd(Math.round(wx) + j * 13, 3);
        const bx = x + j * 1.5, h = 3 + r1 * 7 + (r2 > 0.92 ? 4 : 0);
        const sway = fx ? Math.sin(t / 650 + wx * 0.07 + j) * (1 + h * 0.15) : 0;
        ctx.strokeStyle = r2 < 0.33 ? '#4f9a35' : r2 < 0.66 ? '#3d8429' : '#68b045'; ctx.lineWidth = 1.2;
        ctx.beginPath(); ctx.moveTo(bx, y + 2); ctx.quadraticCurveTo(bx + sway * 0.4, y - h * 0.5, bx + sway, y - h); ctx.stroke();
      }
    }
  }
  function skyRows(m) { let r = 0; while (r < m.tiles.length && m.tiles[r].includes('^')) r++; return r; }
  function skyBack(t, m, cx, cy) {
    const rows = skyRows(m), top = -cy, bot = rows * TILE - cy;
    if (bot <= 0) return;
    const g = ctx.createLinearGradient(0, top, 0, bot);
    g.addColorStop(0, '#3f7fcf'); g.addColorStop(0.55, '#7cb6ec'); g.addColorStop(0.9, '#c4e2fb'); g.addColorStop(1, '#e6f3fd');
    ctx.fillStyle = g; ctx.fillRect(0, Math.max(0, top), VW(), bot + TILE - Math.max(0, top));
    // ánh nắng góc trên phải
    const sx = VW() * 0.82, sy = top + TILE * 1.2, sun = ctx.createRadialGradient(sx, sy, 4, sx, sy, TILE * 6);
    sun.addColorStop(0, 'rgba(255, 250, 225, 0.55)'); sun.addColorStop(1, 'rgba(255, 250, 225, 0)');
    ctx.fillStyle = sun; ctx.fillRect(0, Math.max(0, top), VW(), bot);
  }
  const CLOUD_LAYERS = [
    { n: 6, scale: 0.28, alpha: 0.55, speed: 0.0035, par: 0.35, band: [0.05, 0.55] },
    { n: 5, scale: 0.45, alpha: 0.8, speed: 0.007, par: 0.6, band: [0.15, 0.8] },
    { n: 3, scale: 0.7, alpha: 0.95, speed: 0.012, par: 1, band: [0.35, 0.95] },
  ];
  function clouds(t, m, cx, cy, fx, x0, y0, x1, y1) {
    const rows = skyRows(m);
    if (rows * TILE - cy <= 0) return;
    const w = m.tiles[0].length * TILE, H = rows * TILE, k = fx ? t : 0;
    ctx.save(); skyClip(m, cx, cy);
    skyBack(t, m, cx, cy);
    // đồi xa sau lớp mây xa (mây xa nằm sau đồi gần, mây gần bay trước)
    CLOUD_LAYERS.forEach((L, li) => {
      if (li === 1) { ctx.globalAlpha = 1; farHills(m, cx, cy); hazeBand(); }
      for (let i = 0; i < L.n; i++) {
        const im = image('sky/cloud' + (1 + ((i + li * 2) % 5)));
        if (!im.complete || !im.naturalWidth) continue;
        const cw = im.naturalWidth * L.scale, ch = im.naturalHeight * L.scale, span = w + cw * 2;
        const x = ((rnd(i + 11 * li, 5) * span + k * L.speed * (0.8 + 0.4 * rnd(i, 9))) % span) - cw;
        const y = (L.band[0] + (L.band[1] - L.band[0]) * rnd(i + 7 * li, 4)) * H - ch / 2;
        // lớp xa trôi theo camera ít hơn (thị sai)
        const sx = x - cx * L.par, sy = y - cy * (0.6 + 0.4 * L.par);
        ctx.globalAlpha = L.alpha * (0.85 + 0.15 * Math.sin(k / 4000 + i));
        ctx.drawImage(im, Math.round(sx), Math.round(sy), cw, ch);
      }
    });
    ctx.globalAlpha = 1;
    ctx.restore();
    skyEdge(t, m, cx, cy, fx);
    // sương mỏng ở chân trời: dải sáng ngay trên đồi xa, nhòe ranh giới trời / đất
    function hazeBand() {
      const hb = H - cy, haze = ctx.createLinearGradient(0, hb - TILE * 2.2, 0, hb + TILE);
      haze.addColorStop(0, 'rgba(240, 248, 255, 0)'); haze.addColorStop(0.6, 'rgba(240, 248, 255, 0.4)'); haze.addColorStop(1, 'rgba(240, 248, 255, 0.15)');
      ctx.fillStyle = haze; ctx.fillRect(0, hb - TILE * 2.2, VW(), TILE * 3.2);
    }
  }
  // Chim Lạc lượn vòng quanh ô (6 khung bay `sky/chim_lac.png`, mỗi khung 64×64), ánh đồng lấp lánh
  function birdSpot(t, x, y, fx) {
    const c = x + TILE / 2, d = y + TILE / 2, k = fx ? t : 0;
    const g = ctx.createRadialGradient(c, d, 2, c, d, TILE * 1.1);
    g.addColorStop(0, `rgba(255, 205, 110, ${0.45 + 0.2 * Math.sin(k / 300)})`); g.addColorStop(1, 'rgba(255, 205, 110, 0)');
    ctx.fillStyle = g; ctx.fillRect(c - TILE * 1.2, d - TILE * 1.2, TILE * 2.4, TILE * 2.4);
    const im = image('sky/chim_lac');
    if (im.complete) {
      const a = k / 1300, bx = c + Math.cos(a) * TILE * 0.55, by = d + Math.sin(a) * TILE * 0.3 - 4;
      const fr = Math.floor(k / 110) % 4 + 1, flip = Math.sin(a) < 0;
      ctx.save(); ctx.translate(bx, by); if (!flip) ctx.scale(-1, 1);
      ctx.drawImage(im, fr * 64, 0, 64, 64, -26, -26, 52, 52); ctx.restore();
    }
    if (fx) sparkle(c, d, t, 6, TILE * 0.9, 'rgba(255, 236, 170, 0.9)');
    ctx.strokeStyle = 'rgba(255, 210, 120, 0.85)'; ctx.lineWidth = 1.5;
    ctx.strokeRect(x + 1, y + 1, TILE - 2, TILE - 2);
  }
  // Đàn Hạc: năm con hạc trắng (`sky/hac.png`, 6 khung 32×32) bay vòng
  function flockSpot(t, x, y, fx) {
    const c = x + TILE / 2, d = y + TILE / 2, k = fx ? t : 0, im = image('sky/hac');
    for (let i = 0; i < 5; i++) {
      const a = k / 900 + i * 1.26, r = TILE * (0.35 + 0.12 * (i % 2));
      const bx = c + Math.cos(a) * r, by = d + Math.sin(a) * r * 0.5;
      if (im.complete) {
        const fr = (Math.floor(k / 130) + i) % 5;
        ctx.save(); ctx.translate(bx, by); if (Math.sin(a) > 0) ctx.scale(-1, 1);
        ctx.drawImage(im, fr * 32, 0, 32, 32, -11, -11, 22, 22); ctx.restore();
      }
    }
    ctx.strokeStyle = 'rgba(240, 248, 255, 0.6)'; ctx.setLineDash([3, 3]); ctx.lineWidth = 1;
    ctx.strokeRect(x + 1, y + 1, TILE - 2, TILE - 2); ctx.setLineDash([]);
  }
  // Mảnh Sao vừa rơi trên đồi: hòn sáng vàng, quầng, tia lấp lánh
  function starSpot(t, x, y, fx, labels) {
    const c = x + TILE / 2, d = y + TILE / 2 + 4, k = fx ? t : 0, p = 0.6 + 0.4 * Math.sin(k / 220 + x);
    const g = ctx.createRadialGradient(c, d, 1, c, d, TILE * 0.8);
    g.addColorStop(0, `rgba(255, 230, 140, ${0.75 * p})`); g.addColorStop(1, 'rgba(255, 230, 140, 0)');
    ctx.fillStyle = g; ctx.fillRect(c - TILE, d - TILE, TILE * 2, TILE * 2);
    const im = image('items/manh_sao');
    if (im.complete) ctx.drawImage(im, c - 11, d - 11, 22, 22);
    if (fx) sparkle(c, d, t, 4, 10, 'rgba(255, 255, 220, 0.95)');
    labels.push(['🌠 Mảnh Sao', c, y - 4, '#ffe08a']);
  }
  // Long Phượng Hội ở Tế Đàn: vòng sáng tím vàng bán kính `radius` ô, rồng và chim bay quấn quanh
  function hoiRing(t, h, cx, cy, fx) {
    const c = h.at[0] * TILE - cx + TILE / 2, d = h.at[1] * TILE - cy + TILE / 2, R = (h.radius + 0.5) * TILE, k = fx ? t : 0;
    const g = ctx.createRadialGradient(c, d, R * 0.2, c, d, R * 1.1);
    g.addColorStop(0, 'rgba(200, 140, 255, 0.25)'); g.addColorStop(0.8, `rgba(255, 210, 110, ${0.22 + 0.1 * Math.sin(k / 400)})`); g.addColorStop(1, 'rgba(255, 210, 110, 0)');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(c, d, R * 1.1, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = `rgba(255, 220, 130, ${0.7 + 0.3 * Math.sin(k / 250)})`; ctx.lineWidth = 2.5;
    ctx.setLineDash([8, 6]); ctx.lineDashOffset = -k / 40;
    ctx.beginPath(); ctx.arc(c, d, R, 0, Math.PI * 2); ctx.stroke(); ctx.setLineDash([]); ctx.lineDashOffset = 0;
    const dragon = image('pets/long_vuong'), bird = image('sky/chim_lac');
    const a = k / 1200;
    if (dragon.complete) ctx.drawImage(dragon, c + Math.cos(a) * R * 0.7 - 20, d + Math.sin(a) * R * 0.45 - 30, 40, 40);
    if (bird.complete) {
      const fr = Math.floor(k / 110) % 4 + 1;
      ctx.drawImage(bird, fr * 64, 0, 64, 64, c + Math.cos(a + Math.PI) * R * 0.7 - 24, d + Math.sin(a + Math.PI) * R * 0.45 - 34, 48, 48);
    }
    if (fx) sparkle(c, d, t, 12, R, 'rgba(255, 240, 200, 0.9)');
    if (fx && !tutTimer) tutTimer = setTimeout(() => { tutTimer = null; draw(); }, 60);
  }
  // thú Hắc Long dắt theo: quầng tím đen dưới chân, rồng nhỏ bay lượn bên cạnh
  function hacAura(t, px, py, fx, chan) {
    const x = px + TILE / 2, y = py + TILE - 4, pulse = fx ? 0.5 + 0.5 * Math.sin(t / 450) : 0.5;
    ctx.save();
    ctx.strokeStyle = chan ? `rgba(220, 150, 255, ${0.55 + 0.3 * pulse})` : `rgba(150, 90, 220, ${0.45 + 0.3 * pulse})`; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.ellipse(x, y, 16 + pulse * 2, 6 + pulse, 0, 0, Math.PI * 2); ctx.stroke();
    const im = image(chan ? 'sky/hac_long_chan' : 'sky/hac_long');
    if (im.complete) {
      const a = (fx ? t : 0) / 900, dx = Math.cos(a) * 18, dy = Math.sin(a * 2) * 4;
      ctx.globalAlpha = 0.95;
      ctx.save(); ctx.translate(x + dx + 12, py - 2 + dy); if (Math.cos(a) < 0) ctx.scale(-1, 1);
      ctx.drawImage(im, -15, -10, 30, 19); ctx.restore();
    }
    ctx.restore(); ctx.globalAlpha = 1;
  }
  // thú Chim Lạc dắt theo: chim đồng nhỏ bay vòng trên đầu
  function birdAura(t, px, py, fx) {
    const im = image('sky/chim_lac');
    if (!im.complete) return;
    const a = (fx ? t : 0) / 800, fr = Math.floor((fx ? t : 0) / 110) % 4 + 1;
    ctx.save(); ctx.translate(px + TILE / 2 + Math.cos(a) * 14, py - 6 + Math.sin(a) * 4); if (Math.sin(a) > 0) ctx.scale(-1, 1);
    ctx.drawImage(im, fr * 64, 0, 64, 64, -11, -11, 22, 22); ctx.restore();
  }

  // ---------- Thả diều: dây, diều, gió giật, quà gió bay về (ui.js gọi MapView.kite) ----------
  // kiting: { phase: fly | wait | gust | catch | miss, t0, tx, ty (ô trời diều bay tới), big, item }
  let kiting = null;
  // diều bay cao: camera nâng dần lên cho thấy cả diều (trên) lẫn người (dưới), diều xong thì hạ về
  // diều quá xa (không vừa khung) thì thu nhỏ khung một chút (tối đa còn 0,7) cho thấy cả hai
  let lift = 0, liftAt = 0, kz = 1, kzAt = 0;
  const KITE_PANEL = 64; // khung 🪁 Giữ dây nổi ở đáy bản đồ: người không bị che
  const ease = (v, want, dt, ms) => (Math.abs(want - v) < 0.002 ? want : v + (want - v) * Math.min(1, dt / ms));
  const again = () => { if (!frame) frame = requestAnimationFrame(() => { frame = null; draw(); }); };
  function kiteZoom(now, my) {
    let want = 1;
    if (kiting) want = Math.max(0.7, Math.min(1, (canvas.clientHeight - hudPx - KITE_PANEL) / zoom / TILE / (my - kiting.ty + 3)));
    const dt = Math.min(100, now - (kzAt || now)); kzAt = now;
    kz = ease(kz, want, dt, 400);
    if (kz !== want) again();
    return kz;
  }
  function kiteLift(now, my) {
    let want = 0;
    if (kiting) {
      // chừa trên đầu: thanh sự kiện (hudPx) + chỗ cho dấu "!" khi gió giật
      const vt = VH() / TILE, top = 1.5 + hudPx / zoom / TILE, c = Math.max(my + 1 + KITE_PANEL / zoom / TILE - vt / 2, Math.min(my, kiting.ty - top + vt / 2));
      want = Math.max(0, my - c);
    }
    const dt = Math.min(100, now - (liftAt || now)); liftAt = now;
    lift = ease(lift, want, dt, 260);
    if (lift !== want) again();
    return lift;
  }
  const KITE_MS = { fly: 700, catch: 1800, miss: 700 };
  // giống server (`Kite.check_spot/1`): null nếu thả được (chỗ thoáng, không sát cây; dây không giới hạn), không thì lời nhắc
  function kiteCheck(m, x, y) {
    if (!m || !m.kite) return 'Thả diều ở Đồi Sáo Diều (cổng mép phải Biển Long Vương).';
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if ('TYK'.includes((m.tiles[y + dy] || '')[x + dx] || '_')) return 'Vướng cây rồi, ra chỗ thoáng để thả diều.';
    return null;
  }
  function drawKite(x, y, ang, big, sc = 1) {
    ctx.save(); ctx.translate(x, y); ctx.rotate(ang); ctx.scale(sc, sc);
    ctx.fillStyle = big ? '#ffd34d' : '#e8352a';
    ctx.beginPath(); ctx.moveTo(0, -11); ctx.lineTo(8, 0); ctx.lineTo(0, 13); ctx.lineTo(-8, 0); ctx.closePath(); ctx.fill();
    ctx.fillStyle = big ? '#fff3b0' : '#ffd34d';
    ctx.beginPath(); ctx.moveTo(0, -11); ctx.lineTo(8, 0); ctx.lineTo(0, 0); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.moveTo(0, 13); ctx.lineTo(-8, 0); ctx.lineTo(0, 0); ctx.closePath(); ctx.fill();
    ctx.strokeStyle = '#3a2a1a'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(0, -11); ctx.lineTo(0, 13); ctx.moveTo(-8, 0); ctx.lineTo(8, 0); ctx.stroke();
    // đuôi diều: dải lụa uốn
    ctx.strokeStyle = '#ffe9b0'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(0, 13);
    for (let i = 1; i <= 4; i++) ctx.quadraticCurveTo(i % 2 ? 5 : -5, 13 + i * 5 - 2, 0, 13 + i * 5);
    ctx.stroke();
    ctx.restore();
  }
  function kiteFx(now, m, cx, cy, px, py, anim) {
    const f = kiting, el = now - f.t0;
    const hx = px + TILE - 8, hy = py + 14; // tay cầm dây
    const kx0 = f.tx * TILE - cx + TILE / 2, ky0 = f.ty * TILE - cy + TILE / 2;
    if (f.phase === 'fly' && el > KITE_MS.fly) { f.phase = 'wait'; f.t0 = now - (el - KITE_MS.fly); }
    if (['catch', 'miss'].includes(f.phase) && el > KITE_MS[f.phase]) { kiting = null; return; }
    const e = now - f.t0;
    let kx = kx0, ky = ky0, ang = 0, show = true;
    if (f.phase === 'fly') {
      const k = Math.min(1, e / KITE_MS.fly);
      kx = hx + (kx0 - hx) * k; ky = hy + (ky0 - hy) * k - Math.sin(k * Math.PI) * 20; ang = (1 - k) * 0.8;
    } else if (f.phase === 'wait') {
      kx = kx0 + (anim ? Math.sin(e / 700) * 6 : 0); ky = ky0 + (anim ? Math.sin(e / 500) * 4 : 0); ang = anim ? Math.sin(e / 600) * 0.25 : 0;
    } else if (f.phase === 'gust') {
      kx = kx0 + (anim ? Math.sin(e / 45) * 7 : 0); ky = ky0 - Math.min(10, e / 40); ang = anim ? Math.sin(e / 60) * 0.7 : 0;
      if (f.big) {
        const g = ctx.createRadialGradient(kx, ky, 2, kx, ky, TILE * 1.4);
        g.addColorStop(0, 'rgba(255, 210, 110, 0.55)'); g.addColorStop(1, 'rgba(255, 210, 110, 0)');
        ctx.fillStyle = g; ctx.fillRect(kx - TILE * 1.4, ky - TILE * 1.4, TILE * 2.8, TILE * 2.8);
      }
      const j = anim ? Math.abs(Math.sin(e / 110)) * 6 : 0;
      ctx.font = 'bold 18px sans-serif'; ctx.textAlign = 'center'; ctx.lineWidth = 3; ctx.strokeStyle = '#000';
      ctx.strokeText('!', kx, ky - 18 - j); ctx.fillStyle = f.big ? '#ffd34d' : '#ffe14d'; ctx.fillText('!', kx, ky - 18 - j);
      if (anim) for (let i = 0; i < 3; i++) { ctx.strokeStyle = `rgba(255,255,255,${0.5 - i * 0.12})`; ctx.lineWidth = 1; ctx.beginPath(); const yy = ky - 6 + i * 6, ph = (e / 180 + i * 0.3) % 1; ctx.moveTo(kx - 30 + ph * 20, yy); ctx.lineTo(kx - 14 + ph * 20, yy); ctx.stroke(); }
    } else if (f.phase === 'miss') {
      kx = kx0 + e / 6; ky = ky0 - e / 10; ang = e / 120; show = e < 600;
    } else if (f.phase === 'catch') {
      const k = Math.min(1, e / 500); kx = kx0 + (hx - kx0) * k; ky = ky0 + (hy - 20 - ky0) * k; show = e < 500;
    }
    // diều càng xa càng nhỏ; dây càng dài càng võng (gió thổi lệch sang một bên)
    const dist = Math.hypot(kx - hx, ky - hy) / TILE, sc = Math.max(0.55, Math.min(1, 1.12 - dist * 0.08));
    if (show && f.phase !== 'miss') {
      const sag = 10 + dist * 6, sway = anim ? Math.sin(now / 900) * dist * 1.5 : 0;
      ctx.strokeStyle = 'rgba(245, 240, 230, 0.85)'; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(hx, hy);
      ctx.bezierCurveTo(hx + (kx - hx) * 0.3 + sway, hy + (ky - hy) * 0.15 + sag * 0.6, hx + (kx - hx) * 0.7 + sway, ky + sag, kx, ky + 12 * sc);
      ctx.stroke();
    }
    if (show) drawKite(kx, ky, ang, f.big, sc);
    if (f.phase === 'catch') {
      const bird = f.item === 'chim_lac';
      if (anim && (bird || f.item === 'manh_sao' || /^jewel_/.test(f.item || ''))) {
        const a = Math.max(0, 1 - e / KITE_MS.catch) * (bird ? 0.6 : 0.45), w = TILE * (bird ? 1.3 : 0.8);
        const g = ctx.createLinearGradient(0, ky0 - VH(), 0, ky0);
        g.addColorStop(0, 'rgba(255, 225, 120, 0)'); g.addColorStop(1, `rgba(255, 225, 120, ${a})`);
        ctx.fillStyle = g; ctx.fillRect(kx0 - w / 2, 0, w, ky0 + 4);
        sparkle(kx0, ky0, e, bird ? 18 : 10, TILE * (bird ? 2.4 : 1.4), '#fff2a8');
      }
      const k = Math.min(1, e / 900), tx = px + TILE / 2, ty = py;
      const x = kx0 + (tx - kx0) * k, y = ky0 + (ty - ky0) * k - Math.sin(k * Math.PI) * (bird ? 50 : 30);
      if (bird) {
        const im = image('sky/chim_lac'), fr = Math.floor(e / 110) % 4 + 1;
        if (im.complete && k < 1) ctx.drawImage(im, fr * 64, 0, 64, 64, x - 30, y - 30, 60, 60);
      } else {
        // ngọc không có hình `items/` (dùng bộ icon riêng): hiện 💎; ảnh chưa tải / hỏng thì bỏ qua (không vẽ ảnh hỏng)
        const jewel = /^jewel_/.test(f.item || ''), im = !jewel && image('items/' + f.item), sz = TILE * 0.8;
        if (k < 1 && (jewel || (im.complete && im.naturalWidth))) {
          ctx.save(); ctx.translate(x, y); ctx.rotate(anim ? k * Math.PI * 3 : 0);
          if (jewel) { ctx.font = '20px system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText('💎', 0, 0); } else ctx.drawImage(im, -sz / 2, -sz / 2, sz, sz);
          ctx.restore();
        }
      }
    }
    if (!anim && !frame) frame = requestAnimationFrame(() => { frame = null; draw(); });
  }

  // ---------- Câu cá: cần, dây, phao, cá bay (ui.js gọi MapView.fish) ----------
  // fishing: { phase: cast | wait | bite | catch | boot | miss, t0, tx, ty (ô phao), big, item }
  let fishing = null;
  const FISH_MS = { cast: 450, catch: 1800, boot: 2600, miss: 600 };
  function bobberTile(P, m) {
    for (const [dx, dy] of [[0, 1], [0, -1], [1, 0], [-1, 0]]) {
      const w = (k) => '~=MQU'.includes((m.tiles[P.pos.y + dy * k] || '')[P.pos.x + dx * k] || '#');
      if (w(1)) return w(2) && !'MU'.includes(m.tiles[P.pos.y + dy * 2][P.pos.x + dx * 2]) ? [P.pos.x + dx * 2, P.pos.y + dy * 2] : [P.pos.x + dx, P.pos.y + dy];
    }
    return null;
  }
  function shakeMap(strong) {
    const el = canvas && canvas.parentElement;
    if (!el || !fxOn()) return;
    el.classList.remove('map-shake', 'map-shake-big'); void el.offsetWidth;
    el.classList.add(strong ? 'map-shake-big' : 'map-shake');
  }
  // giọt nước bắn (hạt tính theo thời gian)
  function splash(x, y, k, n, col) {
    for (let i = 0; i < n; i++) {
      const a = Math.PI * (0.15 + 0.7 * rnd(i, 7)), v = 22 + 20 * rnd(i, 8);
      const dx = Math.cos(a) * v * k * (i % 2 ? 1 : -1), dy = -Math.sin(a) * v * k + 60 * k * k;
      ctx.fillStyle = `rgba(${col}, ${1 - k})`;
      ctx.fillRect(x + dx, y + dy, 2, 2);
    }
  }
  function ripple(x, y, k, col = '210, 235, 255') {
    ctx.strokeStyle = `rgba(${col}, ${0.7 * (1 - k)})`; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.ellipse(x, y, 4 + 14 * k, 2 + 6 * k, 0, 0, Math.PI * 2); ctx.stroke();
  }
  function sparkle(x, y, t, n, r, col) {
    for (let i = 0; i < n; i++) {
      const a = i / n * Math.PI * 2 + t / 500, rr = r * (0.4 + 0.6 * ((t / 700 + rnd(i, 5)) % 1));
      const sx = x + Math.cos(a) * rr, sy = y + Math.sin(a) * rr, s = 1 + 2 * Math.abs(Math.sin(t / 120 + i));
      ctx.fillStyle = col; ctx.fillRect(sx - s / 2, sy - 0.5, s, 1); ctx.fillRect(sx - 0.5, sy - s / 2, 1, s);
    }
  }
  function fishFx(now, m, cx, cy, px, py, anim) {
    const f = fishing, el = now - f.t0;
    const hx = px + TILE - 6, hy = py + 8; // đầu cần (tay phải nhân vật)
    const bx = f.tx * TILE - cx + TILE / 2, by = f.ty * TILE - cy + TILE / 2;
    const auto = (ph) => FISH_MS[ph] && el > FISH_MS[ph];
    if (f.phase === 'cast' && auto('cast')) { f.phase = 'wait'; f.t0 = now - (el - FISH_MS.cast); }
    if (['catch', 'boot', 'miss'].includes(f.phase) && auto(f.phase)) { fishing = null; return; }
    const e = now - f.t0;
    // cần câu
    ctx.strokeStyle = '#8a6a2a'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(px + TILE - 12, py + 20); ctx.lineTo(hx, hy); ctx.stroke();
    let ox = bx, oy = by, show = true;
    if (f.phase === 'cast') {
      // quỹ đạo ném: đường cong, phao rơi xuống
      const k = Math.min(1, e / FISH_MS.cast), cxp = (hx + bx) / 2, cyp = Math.min(hy, by) - 40;
      ox = (1 - k) * (1 - k) * hx + 2 * (1 - k) * k * cxp + k * k * bx;
      oy = (1 - k) * (1 - k) * hy + 2 * (1 - k) * k * cyp + k * k * by;
    } else if (f.phase === 'wait') {
      oy = by + (anim ? Math.sin(e / 420) * 1.5 : 0);
      if (anim) { ripple(bx, by + 3, (e % 1700) / 1700); if (e < 800) { ripple(bx, by + 3, e / 800); splash(bx, by, e / 800, 6, '220, 240, 255'); } }
    } else if (f.phase === 'bite') {
      oy = by + Math.min(5, e / 30); // phao chìm nhanh
      if (anim) {
        splash(bx, by, Math.min(1, e / 600), 12, f.big ? '255, 220, 120' : '220, 240, 255');
        ripple(bx, by + 3, (e % 500) / 500, f.big ? '255, 210, 90' : '210, 235, 255');
      }
      if (f.big) {
        const g = ctx.createRadialGradient(bx, by, 2, bx, by, TILE * 1.4);
        g.addColorStop(0, 'rgba(255, 210, 80, 0.55)'); g.addColorStop(1, 'rgba(255, 210, 80, 0)');
        ctx.fillStyle = g; ctx.fillRect(bx - TILE * 1.4, by - TILE * 1.4, TILE * 2.8, TILE * 2.8);
      }
      // dấu ! nảy lên trên phao
      const j = anim ? Math.abs(Math.sin(e / 110)) * 6 : 0;
      ctx.font = 'bold 18px sans-serif'; ctx.textAlign = 'center'; ctx.lineWidth = 3; ctx.strokeStyle = '#000';
      ctx.strokeText('!', bx, by - 12 - j); ctx.fillStyle = f.big ? '#ffd34d' : '#ffe14d'; ctx.fillText('!', bx, by - 12 - j);
    } else {
      show = f.phase === 'miss' && e < 300;
      if (show) oy = by - e / 30;
    }
    // dây câu (căng và rung khi kéo)
    if (show || (f.phase !== 'miss' && e < 400)) {
      const tug = f.phase === 'catch' && e < 400 && anim ? Math.sin(e / 18) * 3 : 0;
      ctx.strokeStyle = 'rgba(235, 235, 235, 0.85)'; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(hx, hy);
      ctx.quadraticCurveTo((hx + ox) / 2 + tug, Math.max(hy, oy) + (f.phase === 'wait' ? 10 : tug), ox, oy); ctx.stroke();
      if (tug) splash(ox, oy, (e % 400) / 400, 8, '220, 240, 255');
    }
    if (show) {
      ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(ox, oy - 2, 3.2, Math.PI, 0); ctx.fill();
      ctx.fillStyle = '#e8352a'; ctx.beginPath(); ctx.arc(ox, oy - 2, 3.2, 0, Math.PI); ctx.fill();
    }
    if (f.phase === 'catch') {
      // cột sáng cho đồ hiếm
      const rare = f.item === 'fish_gold' || f.item === 'long_vuong', dragon = f.item === 'long_vuong';
      if (rare && anim) {
        const a = Math.max(0, 1 - e / FISH_MS.catch) * (dragon ? 0.6 : 0.45), w = TILE * (dragon ? 1.3 : 0.8);
        const g = ctx.createLinearGradient(0, by - VH(), 0, by);
        g.addColorStop(0, 'rgba(255, 225, 120, 0)'); g.addColorStop(1, `rgba(255, 225, 120, ${a})`);
        ctx.fillStyle = g; ctx.fillRect(bx - w / 2, 0, w, by + 4);
        sparkle(bx, by - TILE, e, dragon ? 18 : 10, TILE * (dragon ? 2.4 : 1.4), '#fff2a8');
      }
      // cá bay vòng cung về phía nhân vật, xoay tròn
      const k = Math.min(1, e / 700), tx = px + TILE / 2, ty = py;
      const x = bx + (tx - bx) * k, y = by + (ty - by) * k - Math.sin(k * Math.PI) * (dragon ? 70 : 40);
      const im = image(dragon ? 'pets/long_vuong' : 'items/' + f.item), sz = TILE * (dragon ? 1.8 : 0.8);
      if (im.complete && k < 1) {
        ctx.save(); ctx.translate(x, y); ctx.rotate(anim && !dragon ? k * Math.PI * 4 : 0);
        ctx.drawImage(im, -sz / 2, -sz / 2, sz, sz); ctx.restore();
        if (anim) sparkle(x, y, e, 5, 12, 'rgba(255, 255, 255, 0.9)');
      }
    }
    if (f.phase === 'boot') {
      // ủng cũ bay thẳng vào màn hình, nhân vật choáng, quạ bay ngang
      const vw = VW(), vh = VH(), k = Math.min(1, e / 650);
      const im = image('items/old_boot'), sz = TILE * (0.8 + 5 * k * k);
      if (im.complete && e < 900) {
        ctx.globalAlpha = e < 650 ? 1 : Math.max(0, 1 - (e - 650) / 250);
        const x = bx + (vw / 2 - bx) * k, y = by + (vh / 2 - by) * k;
        ctx.save(); ctx.translate(x, y); ctx.rotate(k * 5); ctx.drawImage(im, -sz / 2, -sz / 2, sz, sz); ctx.restore();
        ctx.globalAlpha = 1;
      }
      if (e > 650) {
        ctx.font = '14px sans-serif'; ctx.textAlign = 'center';
        for (let i = 0; i < 3; i++) {
          const a = e / 260 + i * 2.1;
          ctx.fillText('💫', px + TILE / 2 + Math.cos(a) * 10, py - 4 + Math.sin(a) * 3);
        }
        const q = (e - 650) / (FISH_MS.boot - 650);
        ctx.font = '16px sans-serif';
        for (let i = 0; i < 3; i++) ctx.fillText('🐦‍⬛', -30 + q * (vw + 60) - i * 26, 30 + i * 12 + Math.sin(e / 120 + i) * 4);
      }
    }
    if (!anim && !frame) frame = requestAnimationFrame(() => { frame = null; draw(); });
  }

  window.MapView = {
    setRelations(f) { relations = f; },
    html, top, mount, resize, draw, tileFromEvent, nextStep, monsterAt, monsterById,
    // người chơi khác (đang vẽ) đứng ở ô (x, y): bảng chọn khi bấm
    playersNear,
    playerAt: (x, y) => playersNear(x, y)[0] || null,
    pin,
    playersMode,
    screenOf,
    // người chơi khác đang ở cùng bản đồ (Phase 13)
    players: () => (world.map === (getPlayer() || {}).pos?.map ? world.players.filter((o) => o.id !== userId) : []),
    mountedMap: () => mounted,
    fxOn,
    mobNames,
    setUser(id) { userId = id; },
    setBoss(st) { boss = st; draw(); },
    // l, s: { tile: [x, y], until } (ui.js onLake) hoặc null
    setLake(l, s) {
      const at = (v) => v && { x: v.tile[0], y: v.tile[1], until: v.until };
      lake = at(l); school = at(s); draw();
    },
    // Đồi Sáo Diều (ui.js onSky): { bird, birdLeft, flock, flockLeft, stars, hoi: { at, left, radius } }
    setSky(st) {
      const t = Date.now(), at = (v, left) => v && { x: v[0], y: v[1], until: t + left };
      skyEv = { bird: at(st.bird, st.birdLeft), flock: at(st.flock, st.flockLeft), stars: st.stars || [],
        hoi: st.hoi && { at: st.hoi.at, until: t + st.hoi.left, radius: st.hoi.radius } };
      draw();
    },
    sky: () => skyEv,
    // thả diều (ui.js): fly | gust | catch | miss | null; data: { big, item, tx, ty }
    kite(ev, data = {}) {
      const P = getPlayer(), m = P && cur(P);
      if (!ev || !m) { kiting = null; draw(); return; }
      if (ev === 'fly') {
        const t = data.tx != null ? [data.tx, data.ty] : null;
        kiting = t && { phase: 'fly', t0: performance.now(), tx: t[0], ty: t[1], big: false };
      } else if (kiting) {
        Object.assign(kiting, data, { phase: ev, t0: performance.now() });
        if (ev === 'gust') shakeMap(kiting.big);
      }
      draw();
    },
    kiteAt: () => kiting && [kiting.tx, kiting.ty],
    kiteCheck() { const P = getPlayer(), m = P && cur(P); return kiteCheck(m, P ? P.pos.x : 0, P ? P.pos.y : 0); },
    // vừa lên cấp (ui.js celebrate): cột sáng vàng ở chỗ nhân vật
    levelUp() { levelAt = performance.now(); draw(); },
    // vòng sáng ở ô vừa chạm để đi tới (ui.js walkTo)
    mark(x, y) { const P = getPlayer(); if (P && P.pos) { mark = { x, y, map: P.pos.map, t0: performance.now() }; draw(); } },
    // ô phao rơi khi bấm nút Câu cá (ô nước cạnh / cách một ô)
    bobberTile() { const P = getPlayer(), m = P && cur(P); return m ? bobberTile(P, m) : null; },
    say(uid, text) { bubbles.set(uid, { text, until: performance.now() + BUBBLE_MS }); draw(); },
    setWorld(snap) {
      const wxOld = world.weather;
      // FX đợt 3: so với lần trước (cùng bản đồ): máu quái tụt → tia chém; quái biến mất khi đã bị đánh → tan thành hạt
      if (fxOn() && world.map && snap && snap.map === world.map) {
        const t = performance.now(), next = new Map((snap.monsters || []).map((q) => [q.id, q]));
        for (const q of world.monsters || []) {
          const n = next.get(q.id), hp = q.hp == null ? 100 : q.hp;
          if (n && n.hp != null && n.hp < hp) mobFx.push({ k: 'hit', x: n.x, y: n.y, pct: Math.max(1, Math.round(hp - n.hp)), t0: t, life: 600, mine: n.by === userId });
          // gục: chờ đòn kỹ năng bay tới (~0,35 giây, hình quái vẫn đứng) rồi mới mờ dần
          else if (!n && (hp < 100 || q.busy)) mobFx.push({ k: 'die', x: q.x, y: q.y, kind: q.kind, t0: t + 350, life: 1250 });
        }
        if (mobFx.length > 40) mobFx = mobFx.slice(-40);
      }
      // 🛡 bảo vệ / tên đỏ hết giờ phía client: server chỉ gửi lại bản đồ khi có thay đổi, nên đếm ngược ở đây rồi tự bỏ
      // (nút Đồ sát ở bản đồ / Quanh đây sáng lại đúng lúc)
      const at = Date.now();
      let nextEnd = 0;
      for (const o of snap.players || []) {
        const su = at + (o.safe_s || 0) * 1000, ru = at + (o.red_s || 0) * 1000;
        Object.defineProperty(o, 'safe', { get: () => Date.now() < su, enumerable: true, configurable: true });
        Object.defineProperty(o, 'red', { get: () => Date.now() < ru, enumerable: true, configurable: true });
        for (const u of [su, ru]) if (u > at && (!nextEnd || u < nextEnd)) nextEnd = u;
      }
      clearTimeout(playersTimer);
      if (nextEnd) playersTimer = setTimeout(() => { draw(); window.dispatchEvent(new Event('hl-players-changed')); }, nextEnd - at + 80);
      world = snap;
      const wx = document.getElementById('map-wx');
      if (wx && (snap.weather !== wxOld || !wx.innerHTML)) wx.innerHTML = wxIcon(getPlayer());
      draw();
    },
    world: () => world,
    miniOn,
    floatText,
    setFight,
    fightSpots,
    // dòng thanh sự kiện ở đáy bản đồ (e2e đọc chữ, canvas không đọc được)
    // chiều cao thanh sự kiện (px CSS) đang chiếm mép trên
    hudPx: () => hudPx,
    hudLines() { const P = getPlayer(); return P ? hudLines(P, cur(P)).map((l) => l.text + (l.sub ? ' | ' + l.sub : '')) : []; },
    // ⚡ con đang đánh trên bản đồ { id, hp } (e2e)
    fightTarget() { return fight; },
    // câu cá (ui.js): cast | bite | catch | miss | null; data: { big, item }
    fish(ev, data = {}) {
      const P = getPlayer(), m = P && cur(P);
      if (!ev || !m) { fishing = null; draw(); return; }
      if (ev === 'cast') {
        const t = data.tx != null ? [data.tx, data.ty] : bobberTile(P, m);
        fishing = t && { phase: 'cast', t0: performance.now(), tx: t[0], ty: t[1], big: false };
      } else if (fishing) {
        const ph = ev === 'catch' && data.item === 'old_boot' ? 'boot' : ev;
        Object.assign(fishing, data, { phase: ph, t0: performance.now() });
        if (ev === 'bite') shakeMap(fishing.big);
        if (ph === 'catch' && (data.item === 'fish_gold' || data.item === 'long_vuong')) shakeMap(data.item === 'long_vuong');
      }
      draw();
    },
  };
})();
