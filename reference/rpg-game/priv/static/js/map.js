/* Vẽ bản đồ ô vuông lên canvas và tìm đường khi chạm vào một ô.
 * Chỉ hiển thị: vị trí thật do server quyết định (mỗi bước gửi lên, server kiểm tra rồi trả về).
 * Dữ liệu bản đồ tĩnh ở GAME_DATA.WORLD; quái và người chơi khác đến từ sự kiện "map" của server. */
(function () {
  const { WORLD, ZONES } = window.GAME_DATA;
  const TILE = 32;
  const WALK = new Set(WORLD.walkable);
  const PORTAL = new Set(['D', 'A', 'O']);
  // loại ô → hình (assets/tiles/*.png); nền "." dùng hình `floor` của từng bản đồ
  const GROUND = { grass: 1, dirt: 1, flowers: 1 };

  // cấp của từng loại quái, để tô màu độ khó
  const LEVEL = {}, NAME = {};
  ZONES.forEach((z) => { z.monsters.concat([z.boss]).forEach((m) => { LEVEL[m.id] = m.level; NAME[m.id] = m.name; }); });
  // quái bản đồ phụ chỉ có trong LIBRARY
  (((window.GAME_DATA || {}).LIBRARY || {}).monsters || []).forEach((m) => { if (!(m.id in LEVEL)) { LEVEL[m.id] = m.level; NAME[m.id] = m.name; } });

  const images = {};
  let canvas = null, ctx = null, mounted = null, getPlayer = () => null;
  let world = { map: null, monsters: [], players: [] };
  let userId = null;
  // quan hệ với người chơi khác (đồng đội, bang, bang địch) để tô màu tên; ui.js đặt qua setRelations
  let relations = () => ({});
  let boss = { alive: false }; // trùm thế giới (HacLong.WorldBoss)
  let lake = null, school = null; // Long Vương đang nổi / Đàn Cá Vàng (HacLong.LakeEvent): { x, y, until }
  let decorating = false;       // đang trang trí nhà: tô các ô đặt được
  const Doll = window.Doll;
  Doll.onReady(() => draw());

  // Thú cưng đi sau chủ một ô: nhớ ô trước đó của mỗi người.
  const trails = new Map();
  function petTile(key, x, y) {
    let t = trails.get(key);
    if (!t) { t = { last: [x, y], pet: [x, y + 1] }; trails.set(key, t); }
    if (t.last[0] !== x || t.last[1] !== y) {
      // nhảy xa (qua cổng, dịch chuyển) thì thú hiện ngay sau lưng
      t.pet = Math.abs(t.last[0] - x) + Math.abs(t.last[1] - y) > 1 ? [x, y + 1] : t.last;
      t.last = [x, y];
    }
    return t.pet;
  }

  // Đồ trang trí đã đặt trong Nhà (chỉ nhà của mình).
  const decorAt = (P, x, y) => P.pos.map === 'home' && (P.decor || []).find((d) => d.x === x && d.y === y);

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
      im.onload = () => { draw(); if (visiting) drawHome(...visiting); };
      im.src = 'assets/' + path + '.png';
      images[path] = im;
    }
    return images[path];
  }

  const mapOf = (id) => WORLD.maps[id];
  const tileAt = (m, x, y) => (y >= 0 && y < m.tiles.length && x >= 0 && x < m.tiles[0].length ? m.tiles[y][x] : null);
  const portalAt = (m, x, y) => m.portals.find((p) => p.at[0] === x && p.at[1] === y);
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
    if (P.pos.map === 'tower' && P.tower) return P.tower.monsters.map((q) => Object.assign({}, q, { id: 't' + q.id, boss: q.elite, hp: q.hp_pct == null ? 100 : q.hp_pct }));
    return world.map === P.pos.map ? world.monsters : [];
  }

  const monsterAt = (x, y) => mobs(getPlayer()).find((q) => q.x === x && q.y === y);
  const monsterById = (id) => mobs(getPlayer()).find((q) => q.id === id);
  const nodeAt = (x, y) => (world.nodes || []).find((n) => n.x === x && n.y === y);
  const npcAt = (m, x, y) => (m.npcs || []).find((n) => n.at[0] === x && n.at[1] === y);

  // Cổng vào vùng chưa mở (P.view.unlocked do server tính).
  function locked(P, portal) {
    const target = mapOf(portal.to);
    return (target.zone != null && !P.view.unlocked[target.zone]) || (!target.realm && target.minLevel != null && P.level < target.minLevel);
  }

  // Ngày và đêm (server gửi `phase` kèm trạng thái bản đồ): [nhãn, độ tối]
  const PHASES = { dawn: ['🌅', 0.25], day: ['☀️', 0], dusk: ['🌇', 0.3], night: ['🌙', 0.62] };
  const outdoors = (P) => P.pos.map !== 'home' && P.pos.map !== 'tower';
  // Cài đặt hiển thị (V1): 'auto' theo giờ, 'day' luôn sáng, 'night' luôn tối; chỉ đổi độ tối, không đổi luật
  const theme = () => { try { return localStorage.getItem('hl-theme') || 'auto'; } catch (e) { return 'auto'; } };
  const shade = () => ({ day: 'day', night: 'night' }[theme()] || world.phase);

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
  function weatherOf(m, id) {
    if (id === 'village') return 'smoke';
    const f = m.floor || '';
    if (f.includes('swamp')) return 'rain';
    if (f.includes('lair')) return 'embers';
    if (f.includes('mountain')) return 'snow';
    if (f.includes('graveyard')) return 'fog';
    if (f.includes('forest') || f.includes('camp')) return 'leaves';
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

  function weather(kind, t, cx, cy, m, id) {
    const vw = VW(), vh = VH();
    // khung bản đồ đang ẩn (trong trận): rộng / cao 0 thì wrap chia cho 0 ra NaN
    if (!(vw > 0 && vh > 0)) return;
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
    for (let i = 0; i < 16; i++) {
      const x = wrap(rnd(i, 1) * vw + Math.sin(t / 1300 + i * 2) * 30 - cx, vw), y = wrap(rnd(i, 2) * vh + Math.cos(t / 1700 + i) * 22 - cy, vh);
      const a = Math.max(0, Math.sin(t / 420 + i * 1.7)) * dark;
      if (a < 0.05) continue;
      const g = ctx.createRadialGradient(x, y, 0, x, y, 6);
      g.addColorStop(0, `rgba(220, 255, 140, ${a})`); g.addColorStop(1, 'rgba(220, 255, 140, 0)');
      ctx.fillStyle = g; ctx.fillRect(x - 6, y - 6, 12, 12);
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

  function top(P) {
    const m = cur(P);
    const z = m.zone != null ? ZONES[m.zone] : null;
    // bản đồ phụ (Phase 15a): cấp quái lấy từ Thư viện
    const side = m.side && ((window.GAME_DATA.LIBRARY || { maps: [] }).maps.find((x) => x.id === P.pos.map) || {});
    const ph = PHASES[world.phase] && outdoors(P) ? `<span class="phase">${PHASES[world.phase][0]}</span> ` : '';
    return `<div class="map-top">
        <b>${ph}${m.name}</b>${P.view && P.view.event && P.view.event.active && outdoors(P) ? ` <span class="small" style="color:var(--gold)">${P.view.event.icon} ${P.view.event.name}</span>` : ''}
        <span class="small muted">${m.event === 'chaos_castle' ? ccTop(P) : m.event === 'castle_siege' ? csTop(P) : m.tower && m.tower.kal ? (m.tower.kal.done ? 'Đi một bước để về Làng' : `Đã hạ ${m.tower.kal.killed}/${m.tower.kal.guards} quái · hết lúc ${new Date(m.tower.kal.ends_at * 1000).toLocaleTimeString('vi-VN')}`) : m.tower && m.tower.bc ? (m.tower.bc.done ? 'Đi một bước để về Làng' : `Quân canh đã hạ ${m.tower.bc.killed}/${m.tower.bc.guards} · hết lúc ${new Date(m.tower.bc.ends_at * 1000).toLocaleTimeString('vi-VN')}`) : m.tower && m.tower.ds ? `${m.tower.ds.score} điểm · hết lúc ${new Date(m.tower.ds.ends_at * 1000).toLocaleTimeString('vi-VN')} · ${m.tower.monsters.length ? `còn ${m.tower.monsters.length} quái` : 'cầu thang đã mở'}` : m.tower ? (m.tower.monsters.length ? `Còn ${m.tower.monsters.length} quái · kỷ lục tầng ${P.tower_best || 0}` : 'Cầu thang đã mở!') : side ? `Bản đồ phụ · quái cấp ${side.min}–${side.max}` : z ? (P.pos.map.endsWith('_boss') ? `Phòng trùm · cấp ${z.boss.level}` : `Quái cấp ${z.levels}`) : P.pos.map === 'home' ? 'Giếng nước hồi đầy máu' : P.pos.map === 'altar' ? 'Nơi trùm thế giới xuất hiện' : 'Bước vào người dân để nói chuyện'}</span>
      </div>`;
  }

  function html(P, overlay) {
    const m = cur(P);
    return `
      ${top(P)}
      <div class="map-wrap"><canvas id="map-canvas" aria-label="Bản đồ ${m.name}"></canvas><button class="zoom-btn ${zoomOn() ? 'on' : ''}" data-act="map-zoom" aria-pressed="${zoomOn()}" title="Vừa màn hình" aria-label="Vừa màn hình">⤢</button>${overlay || ''}</div>
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
    const dpr = window.devicePixelRatio || 1;
    ctx.setTransform(dpr * zoom, 0, 0, dpr * zoom, 0, 0);
    const [cx, cy] = camera(m, mx, my);
    lastCam = [cx, cy];
    ctx.fillStyle = '#0c0910';
    ctx.fillRect(0, 0, VW(), VH());
    const x0 = Math.max(0, Math.floor(cx / TILE)), y0 = Math.max(0, Math.floor(cy / TILE));
    const x1 = Math.min(m.tiles[0].length - 1, Math.ceil((cx + VW()) / TILE));
    const y1 = Math.min(m.tiles.length - 1, Math.ceil((cy + VH()) / TILE));
    const floor = image(m.floor);
    const labels = [], talk = [];
    const fx = fxOn(), fountains = [], lanterns = [];

    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const px = Math.round(x * TILE - cx), py = Math.round(y * TILE - cy);
        const kind = WORLD.legend[m.tiles[y][x]];
        if (floor.complete) ctx.drawImage(floor, px, py, TILE, TILE);
        if (kind !== 'floor') {
          // ô W: Đài Phúc Lành (Phase 2, thay đá dịch chuyển)
          const im = image('tiles/' + (kind === 'waystone' ? 'blessing' : kind));
          const sway = fx && (kind === 'tree' || kind === 'tree_autumn') ? Math.sin(now / 900 + x * 0.8 + y * 0.5) * 0.045 : 0;
          if (im.complete && sway) {
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
          if (fx && kind === 'fountain') fountains.push([px, py]);
          if (kind === 'lantern') lanterns.push([px, py]);
        }
        if (GROUND[kind]) continue;
        if (kind === 'waystone') labels.push(['Đài Phúc Lành', px + TILE / 2, py - 13, '#f0cf7a']);
        if (kind === 'stairs_up' && m.tower && (m.tower.bc || m.tower.kal)) { /* Lâu Đài: cầu thang lên chỉ là cảnh */ } else if (kind === 'stairs_up') labels.push([m.tower && m.tower.monsters.length ? (m.tower.ds ? '🔒 Đợt sau' : '🔒 Lên tầng') : (m.tower && m.tower.ds ? 'Đợt sau' : 'Lên tầng'), px + TILE / 2, py + TILE - 13, '#f0cf7a']);
        if (kind === 'stairs_down') labels.push(['Về Làng', px + TILE / 2, py + TILE - 13, '#b9d7ff']);
        const portal = PORTAL.has(m.tiles[y][x]) && portalAt(m, x, y);
        if (portal) {
          const shut = locked(P, portal);
          if (shut) { ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.fillRect(px, py, TILE, TILE); }
          // nhãn nằm trong ô cổng để không đè lên người đứng cạnh
          labels.push([(shut ? '🔒 ' : '') + mapOf(portal.to).name, px + TILE / 2, py + TILE - 13, shut ? '#9a93a3' : '#f0cf7a']);
        }
      }
    }

    // sự kiện "map" có thể đến trước/sau lúc đổi bản đồ một chút
    const here = world.map === P.pos.map;
    const names = mobNames();
    for (const q of mobs(P)) {
      const [qx, qy] = smooth('m' + q.id, q.x, q.y, DUR.monster, now);
      // quái đứng yên thì nhún nhẹ (chỉ là hình)
      const bob = fx && qx === q.x && qy === q.y ? Math.round(Math.sin(now / 380 + (parseInt(String(q.id).replace(/\D/g, ''), 10) || 0)) * 1.5) : 0;
      const px = Math.round(qx * TILE - cx), py = Math.round(qy * TILE - cy) + bob;
      if (px < -TILE || py < -TILE || px > VW() || py > VH()) continue;
      ctx.globalAlpha = q.busy ? 0.45 : 1;
      if (q.boss && !q.gold) {
        ctx.strokeStyle = '#f0cf7a'; ctx.lineWidth = 2;
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
      const nm = (q.busy ? '⚔ ' : '') + (q.gold ? (q.boss ? 'Trùm Vàng · ' : 'Vàng · ') : q.rare ? 'Bóng Đêm · ' : '') + (q.name || NAME[q.kind] || '');
      if (names) labels.push([nm, px + TILE / 2, py - 13 - off, q.gold ? '#ffd24a' : q.raid ? '#ff8a5c' : q.rare ? '#d59cff' : q.busy ? '#ef6a5a' : q.boss ? '#f0cf7a' : '#f1e6cf']);
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
    }

    for (const n of here ? world.nodes || [] : []) {
      const px = Math.round(n.x * TILE - cx), py = Math.round(n.y * TILE - cy);
      const im = image('nodes/' + n.item);
      if (im.complete) ctx.drawImage(im, px, py, TILE, TILE);
    }

    if (P.pos.map === 'home') {
      for (const d of P.decor || []) {
        const px = Math.round(d.x * TILE - cx), py = Math.round(d.y * TILE - cy);
        const im = image('decor/' + d.id);
        if (im.complete) ctx.drawImage(im, px, py, TILE, TILE);
      }
      if (decorating) {
        ctx.strokeStyle = 'rgba(240, 207, 122, 0.45)'; ctx.lineWidth = 1;
        ctx.setLineDash([4, 3]);
        for (let y = 0; y < m.tiles.length; y++) for (let x = 0; x < m.tiles[0].length; x++) {
          if (WALK.has(m.tiles[y][x]) && !PORTAL.has(m.tiles[y][x]) && !npcAt(m, x, y)) ctx.strokeRect(Math.round(x * TILE - cx) + 1.5, Math.round(y * TILE - cy) + 1.5, TILE - 3, TILE - 3);
        }
        ctx.setLineDash([]);
      }
    }

    for (const n of m.npcs || []) {
      const px = Math.round(n.at[0] * TILE - cx), py = Math.round(n.at[1] * TILE - cy);
      const im = image('npcs/' + n.sprite);
      if (im.complete) ctx.drawImage(im, px, py, TILE, TILE);
      labels.push([n.name, px + TILE / 2, py - 14, n.role === 'quests' ? '#f0cf7a' : '#c8f0b0']);
      if ((n.role === 'quests' && P.view.questReady) || (n.role === 'daily' && P.view.dailyReady) || (n.role === 'chest' && P.view.chestReady)) label('!', px + TILE - 4, py - 2, '#f0cf7a');
    }

    // trùm thế giới: vẽ to gấp đôi, có thanh máu chung
    if (m.worldBoss && boss.alive) {
      const [bx, by] = m.worldBoss;
      const px = Math.round(bx * TILE - cx), py = Math.round(by * TILE - cy);
      const im = image('monsters/ancient_dragon');
      if (im.complete) ctx.drawImage(im, px - TILE / 2, py - TILE, TILE * 2, TILE * 2);
      const w = TILE * 2, k = boss.hp / boss.maxHp;
      ctx.fillStyle = 'rgba(12,9,16,0.85)'; ctx.fillRect(px - TILE / 2, py - TILE - 8, w, 6);
      ctx.fillStyle = '#d9483b'; ctx.fillRect(px - TILE / 2 + 1, py - TILE - 7, Math.max(0, (w - 2) * k), 4);
      if (names) labels.push([boss.name, px + TILE / 2, py - TILE - 22, '#ef6a5a']);
    }

    const hero = image('monsters/hero');
    // thú cưng: nhỏ hơn một chút, đi sau chủ một ô
    const drawPet = (id, key, x, y) => {
      if (!id) return;
      const [tx, ty] = petTile(key, x, y);
      const [qx, qy] = smooth('pet' + key, tx, ty, DUR.player * 1.4, now);
      const im = image(id.startsWith('tame:') ? 'monsters/' + id.slice(5) : 'pets/' + id);
      if (im.complete) ctx.drawImage(im, Math.round(qx * TILE - cx) + 4, Math.round(qy * TILE - cy) + 6, TILE - 8, TILE - 8);
    };
    // Phase 13 (13-A): không vẽ người chơi khác trên bản đồ (nhiều người chung ô không biết ai là ai);
    // xem danh sách người trong bản đồ ở nút 👫 trên dock.
    const look = P.view && P.view.look;
    if (!m.tower) drawPet(look && look.pet, 'me', P.pos.x, P.pos.y);
    const px = Math.round(mx * TILE - cx), py = Math.round(my * TILE - cy);
    ctx.fillStyle = 'rgba(240, 207, 122, 0.35)';
    ctx.beginPath(); ctx.ellipse(px + TILE / 2, py + TILE - 4, 12, 5, 0, 0, Math.PI * 2); ctx.fill();
    const myDoll = Doll.canvas(look);
    if (myDoll) ctx.drawImage(myDoll, px, py, TILE, TILE); else if (hero.complete) ctx.drawImage(hero, px, py, TILE, TILE);
    const mine = bubbleOf(userId, now);
    if (mine) talk.push([mine, px + TILE / 2, py]);
    // câu cá: cần, dây, phao, cá bay lên (chỉ phía mình)
    if (fishing) fishFx(now, m, cx, cy, px, py, fx);
    // hướng dẫn người mới: vòng sáng nhấp nháy và mũi tên ở ô cần tới
    const goal = P.view && P.view.tutorial && P.view.tutorial.target;
    if (goal && goal.map === P.pos.map) {
      const gx = Math.round(goal.x * TILE - cx) + TILE / 2, gy = Math.round(goal.y * TILE - cy) + TILE / 2;
      const k = (Math.sin(now / 250) + 1) / 2;
      const vw = VW(), vh = VH(), pad = 18;
      if (gx < 0 || gy < 0 || gx > vw || gy > vh) {
        // ô đích bị khuất: mũi tên ở mép khung nhìn chỉ về phía đó
        const ex = Math.max(pad, Math.min(vw - pad, gx)), ey = Math.max(pad, Math.min(vh - pad, gy));
        const ang = Math.atan2(gy - vh / 2, gx - vw / 2);
        ctx.save(); ctx.translate(ex, ey); ctx.rotate(ang);
        ctx.fillStyle = `rgba(240, 207, 122, ${0.6 + k * 0.4})`;
        ctx.beginPath(); ctx.moveTo(12, 0); ctx.lineTo(-8, -9); ctx.lineTo(-8, 9); ctx.fill();
        ctx.restore();
      }
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
      // Hồ Long Vương: bóng cá, xoáy Vực Rồng, lá / hoa rơi, tia nắng sáng sớm / chiều tà
      if (m.fish === 'lake') lakeFx(now, m, cx, cy);
      // tầng Tháp / Quảng Trường / Lâu Đài / Kalima: hiệu ứng theo nền tầng (không có ngày đêm)
      const w = (outdoors(P) || m.tower) && weatherOf(m, P.pos.map);
      if (w) weather(w, now, cx, cy, m, P.pos.map);
    }
    // bóng tối theo giờ: tối dần ra xa nhân vật, quanh nhân vật vẫn sáng
    const dark = PHASES[shade()] && outdoors(P) ? PHASES[shade()][1] : 0;
    if (dark) {
      const lx = px + TILE / 2, ly = py + TILE / 2;
      const g = ctx.createRadialGradient(lx, ly, TILE * 1.2, lx, ly, TILE * 5);
      g.addColorStop(0, `rgba(8, 10, 32, ${dark * 0.25})`);
      g.addColorStop(1, `rgba(8, 10, 32, ${dark})`);
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, VW(), VH());
      if (fx && dark >= 0.3) nightGlow(now, m, cx, cy, dark);
      // đèn lồng (Hồ Long Vương) tỏa sáng ban đêm
      if (dark >= 0.3) for (const [lx0, ly0] of lanterns) {
        const x = lx0 + 23, y = ly0 + 17, f = fx ? 0.85 + 0.15 * Math.sin(now / 230 + lx0) : 1;
        const g = ctx.createRadialGradient(x, y, 1, x, y, TILE * 1.8);
        g.addColorStop(0, `rgba(255, 120, 70, ${0.55 * dark * f})`); g.addColorStop(1, 'rgba(255, 120, 70, 0)');
        ctx.fillStyle = g; ctx.fillRect(x - TILE * 1.8, y - TILE * 1.8, TILE * 3.6, TILE * 3.6);
      }
    }
    if (m.fish === 'lake' && school && Date.now() < school.until) schoolSpot(now, school.x * TILE - cx, school.y * TILE - cy, fx);
    if (m.fish === 'lake' && lake && Date.now() < lake.until) dragonSpot(now, lake.x * TILE - cx, lake.y * TILE - cy, fx);
    for (const l of labels) label(...l);
    for (const t of talk) bubble(...t);
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
      return !(!WALK.has(c) || PORTAL.has(c) || c === '<' || c === '>' || monsterAt(nx, ny) || nodeAt(nx, ny) || npcAt(m, nx, ny) || bossHere || decorAt(P, nx, ny));
    });
  }

  // Nhà của người khác (chỉ xem): vẽ cả căn nhà vừa khung, đồ trang trí của họ, chủ nhà
  // đứng trước cửa cùng thú cưng.
  let visiting = null;
  function drawHome(el, v) {
    visiting = [el, v];
    const m = mapOf('home');
    const cols = m.tiles[0].length, rows = m.tiles.length;
    const w = el.parentElement.clientWidth || cols * TILE;
    const T = Math.max(12, Math.min(TILE, Math.floor(w / cols)));
    const dpr = window.devicePixelRatio || 1;
    el.style.width = cols * T + 'px'; el.style.height = rows * T + 'px';
    el.width = Math.round(cols * T * dpr); el.height = Math.round(rows * T * dpr);
    const c = el.getContext('2d');
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    c.imageSmoothingEnabled = false;
    c.fillStyle = '#0c0910'; c.fillRect(0, 0, cols * T, rows * T);
    const put = (im, x, y, pad) => { if (im && (im.complete === undefined || im.complete)) c.drawImage(im, x * T + (pad || 0), y * T + (pad || 0), T - 2 * (pad || 0), T - 2 * (pad || 0)); };
    const floor = image(m.floor);
    for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) {
      const kind = WORLD.legend[m.tiles[y][x]];
      put(floor, x, y);
      if (kind !== 'floor') put(image('tiles/' + kind), x, y);
    }
    for (const d of v.decor || []) put(image('decor/' + d.id), d.x, d.y);
    for (const n of m.npcs || []) put(image('npcs/' + n.sprite), n.at[0], n.at[1]);
    const door = (m.portals[0] || { at: [Math.floor(cols / 2), rows - 1] }).at;
    const [hx, hy] = [door[0], door[1] - 1];
    const pet = v.look && v.look.pet;
    if (pet) put(image(pet.startsWith('tame:') ? 'monsters/' + pet.slice(5) : 'pets/' + pet), hx + 1, hy, T / 8);
    put(Doll.canvas(v.look) || image('monsters/hero'), hx, hy);
  }

  // ---------- Hồ Long Vương: không khí (chỉ vẽ, không ảnh hưởng luật) ----------
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
    drawHome,
    setRelations(f) { relations = f; },
    stopVisit() { visiting = null; },
    html, top, mount, resize, draw, tileFromEvent, nextStep, monsterAt, monsterById,
    // người chơi khác đứng ở ô (x, y) trên bản đồ đang đứng
    playerAt: () => null,
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
    // ô phao rơi khi bấm nút Câu cá (ô nước cạnh / cách một ô)
    bobberTile() { const P = getPlayer(), m = P && cur(P); return m ? bobberTile(P, m) : null; },
    say(uid, text) { bubbles.set(uid, { text, until: performance.now() + BUBBLE_MS }); draw(); },
    setDecorating(on) { decorating = on; draw(); },
    setWorld(snap) {
      world = snap;
      draw();
    },
    world: () => world,
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
