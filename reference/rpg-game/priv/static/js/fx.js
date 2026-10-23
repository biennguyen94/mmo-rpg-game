/* Hiệu ứng trận đánh (docs/FX_PLAN.md, hướng A): một canvas trong suốt phủ cả màn hình, không bắt chuột; vị trí lấy từ
 * hình quái (`#view .stage > .sprite`) và hình nhân vật (`#view .me .sprite`) lúc phát, nên mọi chế độ dùng bảng trận
 * (đánh tay, tự đánh, tháp, sự kiện, đấu trường, đồ sát) đều có. Chỉ là hình: server vẫn quyết định sát thương.
 *
 * BattleFx.run(events): events là mảng { type, ... }:
 *   attack { cls, crit }        đòn thường của mình (kiếm chém / tên bay / cầu phép theo lớp)
 *   skill  { element, crit }    kỹ năng gây sát thương, hình theo hệ nguyên tố
 *   buff   { element, heal }    kỹ năng lên mình (hồi máu, tăng sức)
 *   miss                        đòn của mình trượt
 *   hurt   { crit }             quái / đối thủ đánh trúng mình
 *   kill                        quái gục: tan thành hạt, vàng bay về túi
 *   ghost  { from }             thanh máu quái: lớp trắng trễ chạy từ % cũ (`from`, 0..100) về % mới
 *   loot   { items: [{ tier, name, col }] }   đồ rơi (FX đợt 2): cột sáng theo độ quý (anc vàng, exc xanh lá, opt xanh
 *                               dương, ngọc theo màu ngọc); Thần / Excellent: cột to, tên món, chớp, rung, âm "rare"
 *   forge  { mode, icon, outcome, level, n }  ép đồ / Máy Hỗn Nguyên / Ngọc Sinh Mệnh: món giữa màn hình, ngọc / nguyên
 *                               liệu bay vào, búa gõ tia lửa (~0,8 giây), rồi nổ sáng (thành) hoặc nứt / khói / vỡ (hỏng)
 *   pet    { img, dmg, tidal }  thú cưng nhảy ra cắn (FX đợt 3): số sát thương màu riêng; Thủy Long Ba: cột nước + rồng vàng
 *   dragon                      Long Vương (Hồi Sinh): rồng vàng uốn lượn bay ngang màn hình
 * `BattleFx.ambient({ mon, me, aura, wing })`: hiệu ứng nền khi đang ở màn trận (gọi sau mỗi lần vẽ, null để tắt):
 *   trạng thái (độc bong bóng xanh, bỏng tàn lửa, chảy máu giọt đỏ, choáng sao xoay), hào quang đồ +7/+9/+11, hạt cánh.
 * Tắt hiệu ứng (`MapView.fxOn`, "giảm chuyển động") thì không phát gì. */
(function () {
  const COLORS = {
    fire: ['#fff3b0', '#ffb03d', '#ff4a1f'],
    lightning: ['#ffffff', '#cfeaff', '#7fb8ff'],
    wind: ['#f0fff8', '#a8ecd0', '#5fc9a0'],
    earth: ['#f0d29a', '#b07f40', '#6b4a22'],
    dark: ['#e6ccff', '#9a5ce0', '#46207a'],
    light: ['#fffbe6', '#ffe79a', '#ffc93d'],
    water: ['#f0ffff', '#9fe0ff', '#4aa8e8'],
    ice: ['#f0ffff', '#bfefff', '#6cc4f0'],
    poison: ['#e8ffc0', '#9ad855', '#4f8a2a'],
    none: ['#ffffff', '#ffe08a', '#c9a24a'],
  };
  let canvas = null, ctx = null, raf = null, dpr = 1;
  const parts = []; // hạt và vật thể đang bay
  const on = () => !!(window.MapView && window.MapView.fxOn && window.MapView.fxOn());
  const now = () => performance.now();
  const rand = (a, b) => a + Math.random() * (b - a);

  function ensure() {
    if (canvas && canvas.isConnected) return true;
    canvas = document.createElement('canvas');
    canvas.id = 'bfx';
    canvas.setAttribute('aria-hidden', 'true');
    document.body.appendChild(canvas);
    ctx = canvas.getContext('2d');
    resize();
    return true;
  }
  function resize() {
    if (!canvas) return;
    dpr = Math.min(2, window.devicePixelRatio || 1);
    canvas.width = Math.round(window.innerWidth * dpr);
    canvas.height = Math.round(window.innerHeight * dpr);
  }
  window.addEventListener('resize', resize);

  // tâm (và cỡ) một phần tử trên màn hình
  function spot(sel) {
    const el = document.querySelector(sel);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    if (!r.width) return null;
    return { x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height, el };
  }
  const MON = '#view .stage > .sprite', ME = '#view .me .sprite';

  function add(p) { p.t0 = p.t0 || now(); parts.push(p); if (!raf) raf = requestAnimationFrame(loop); }
  // nảy class CSS (bỏ rồi gắn lại để chạy lại animation)
  function bump(el, cls, ms) {
    if (!el) return;
    el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls);
    setTimeout(() => el.classList.remove(cls), ms);
  }

  // ---------- hạt cơ bản ----------
  function burst(x, y, n, col, o = {}) {
    for (let i = 0; i < n; i++) {
      const a = o.up ? rand(-Math.PI * 0.95, -Math.PI * 0.05) : rand(0, Math.PI * 2), v = rand(o.vmin || 60, o.vmax || 260);
      add({ k: 'dot', x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, g: o.g != null ? o.g : 380, life: rand(350, o.life || 750),
        r: rand(o.rmin || 1.5, o.rmax || 3.5), col: col[i % col.length], glow: o.glow });
    }
  }
  const ring = (x, y, col, o = {}) => add({ k: 'ring', x, y, r0: o.r0 || 6, r1: o.r1 || 60, life: o.life || 450, col, w: o.w || 3 });
  const text = (x, y, s, col, size) => add({ k: 'text', x, y, s, col, size: size || 22, life: 900 });
  const flash = (col, a, life) => add({ k: 'flash', col, a: a || 0.35, life: life || 220 });

  // vật bay từ A tới B rồi gọi `hit` khi tới
  function fly(from, to, draw, dur, hit) {
    add({ k: 'fly', x0: from.x, y0: from.y, x1: to.x, y1: to.y, draw, life: dur, hit, done: false });
  }

  function impact(t, col, crit) {
    burst(t.x, t.y, crit ? 30 : 14, col, { vmax: crit ? 380 : 240, glow: true });
    ring(t.x, t.y, col[1], { r1: crit ? 90 : 55 });
    bump(t.el, 'fx-hit', 320);
    if (crit) {
      text(t.x, t.y - t.h * 0.55, 'CHÍ MẠNG!', '#ffcf5a', 24);
      shake(true);
    }
  }
  function shake(big) { bump(document.getElementById('view'), big ? 'fx-shake-big' : 'fx-shake', 380); }

  // ---------- các loại sự kiện ----------
  const EV = {
    attack(e) {
      const me = spot(ME), t = spot(MON);
      if (!t) return;
      if (me) bump(me.el, 'fx-lunge', 300);
      const from = me || { x: t.x, y: t.y + 120 };
      if (e.cls === 'elf') {
        fly(from, t, (c, x, y, ang) => { c.strokeStyle = '#f5e6c0'; c.lineWidth = 2; c.beginPath(); c.moveTo(x - Math.cos(ang) * 18, y - Math.sin(ang) * 18); c.lineTo(x, y); c.stroke();
          c.fillStyle = '#fff'; c.beginPath(); c.arc(x, y, 2.5, 0, Math.PI * 2); c.fill(); }, 180, () => impact(t, COLORS.none, e.crit));
      } else if (e.cls === 'dw') {
        fly(from, t, orb(COLORS.water), 260, () => impact(t, COLORS.water, e.crit));
      } else {
        // kiếm: hai vệt chém vòng cung chéo qua quái
        add({ k: 'slash', x: t.x, y: t.y, r: t.w * 0.55, life: 260, col: e.crit ? '#ffd24a' : '#ffffff', dir: 1 });
        add({ k: 'slash', x: t.x, y: t.y, r: t.w * 0.45, life: 260, col: e.crit ? '#ff8a3d' : '#cfe0ff', dir: -1, t0: now() + 70 });
        setTimeout(() => impact(t, COLORS.none, e.crit), 120);
      }
    },
    skill(e) {
      const me = spot(ME), t = spot(MON), col = COLORS[e.element] || COLORS.none;
      if (!t) return;
      if (me) { ring(me.x, me.y + me.h * 0.35, col[1], { r0: 4, r1: 34, life: 380, w: 2 }); bump(me.el, 'fx-cast', 360); }
      const from = me || { x: t.x, y: t.y + 120 };
      switch (e.element) {
        case 'fire':
          fly(from, t, orb(col, 9), 320, () => { impact(t, col, e.crit); burst(t.x, t.y, 24, col, { up: true, g: -60, vmin: 30, vmax: 140, life: 1100, glow: true }); flash('#ff7a2b', 0.18); });
          break;
        case 'lightning':
          for (let i = 0; i < 3; i++) add({ k: 'bolt', x: t.x + rand(-12, 12), y0: Math.max(0, t.y - 260), y1: t.y, life: 160, col: col[1], t0: now() + i * 70 });
          setTimeout(() => { flash('#dff0ff', 0.4, 160); impact(t, col, e.crit); shake(e.crit); }, 90);
          break;
        case 'wind':
          for (let i = 0; i < 3; i++) setTimeout(() => fly(from, t, blade(col), 240, () => impact(t, col, e.crit && i === 2)), i * 90);
          add({ k: 'swirl', x: t.x, y: t.y, r: t.w * 0.6, life: 700, col: col[1], t0: now() + 240 });
          break;
        case 'earth':
          for (let i = 0; i < 4; i++) add({ k: 'rock', x: t.x + rand(-t.w * 0.4, t.w * 0.4), y0: t.y - 240, y1: t.y + rand(-6, 10), life: 260, col: col[i % 3], t0: now() + i * 60 });
          setTimeout(() => { impact(t, col, e.crit); burst(t.x, t.y + t.h * 0.3, 20, ['#b9a38a', '#8a7560'], { vmax: 160, g: 120 }); shake(true); }, 300);
          break;
        case 'dark':
          fly(from, t, orb(col, 8), 340, () => { add({ k: 'implode', x: t.x, y: t.y, r: t.w * 0.9, life: 420, col: col[1] }); setTimeout(() => impact(t, col, e.crit), 300); });
          break;
        case 'light':
          add({ k: 'beam', x: t.x, y: t.y, w: t.w * 0.5, life: 520, col: col[1] });
          setTimeout(() => impact(t, col, e.crit), 160);
          break;
        default:
          fly(from, t, orb(col, 8), 300, () => impact(t, col, e.crit));
      }
    },
    buff(e) {
      const me = spot(ME), col = e.heal ? ['#eaffea', '#7ee08a', '#2fa84a'] : (COLORS[e.element] || COLORS.light);
      if (!me) return;
      for (let i = 0; i < 3; i++) ring(me.x, me.y + me.h * 0.3, col[1], { r0: 6, r1: 40 + i * 10, life: 600, w: 2, t0: now() + i * 120 });
      burst(me.x, me.y + me.h * 0.3, 18, col, { up: true, g: -80, vmin: 20, vmax: 90, life: 1100, glow: true });
      if (e.heal) for (let i = 0; i < 6; i++) add({ k: 'plus', x: me.x + rand(-me.w, me.w), y: me.y + rand(-4, 10), life: 900, col: col[1], t0: now() + i * 80 });
      bump(me.el, 'fx-cast', 360);
    },
    miss() {
      const t = spot(MON);
      if (!t) return;
      bump(t.el, 'fx-dodge', 360);
      burst(t.x - t.w * 0.4, t.y + t.h * 0.3, 8, ['#d8d0c0', '#a89c88'], { vmax: 90, g: 60, life: 500 });
    },
    hurt(e) {
      const me = spot(ME);
      if (!me) return;
      add({ k: 'claw', x: me.x, y: me.y, r: Math.max(26, me.w * 0.7), life: 260, col: '#ff4a3d' });
      burst(me.x, me.y, e.crit ? 18 : 8, ['#ff6b5a', '#c0392b', '#ffd0c0'], { vmax: 200 });
      flash('#ff2a1a', e.crit ? 0.3 : 0.16, 260);
      if (e.crit) shake(false);
    },
    kill() {
      const t = spot(MON);
      if (!t) return;
      t.el.classList.add('fx-dying');
      for (let i = 0; i < 36; i++) {
        add({ k: 'dot', x: t.x + rand(-t.w * 0.4, t.w * 0.4), y: t.y + rand(-t.h * 0.4, t.h * 0.4), vx: rand(-30, 30), vy: rand(-140, -40), g: -20,
          life: rand(600, 1200), r: rand(1.5, 3), col: ['#e8dcc8', '#a8a090', '#ffd27a'][i % 3], glow: i % 3 === 2 });
      }
      // vàng bay về số vàng trên đầu trang
      const gold = spot('.hud-who .gold');
      if (gold) for (let i = 0; i < 7; i++) {
        setTimeout(() => fly({ x: t.x + rand(-20, 20), y: t.y + rand(-10, 20) }, gold, coin, 520, () => bump(gold.el, 'fx-pop', 260)), 260 + i * 60);
      }
    },
    loot(e) {
      const t = spot(MON) || spot('#view .stage');
      if (!t) return;
      const items = (e.items || []).slice(0, 6);
      let rare = false;
      items.forEach((it, i) => setTimeout(() => {
        const big = it.tier === 'anc' || it.tier === 'exc';
        const x = t.x + (i - (items.length - 1) / 2) * 34, y = t.y + t.h * 0.35;
        add({ k: 'pillar', x, y, w: big ? 22 : 12, h: big ? 260 : 120, col: it.col, life: big ? 1400 : 900, big });
        burst(x, y, big ? 26 : 10, [it.col, '#ffffff'], { up: true, g: 60, vmin: 40, vmax: big ? 260 : 150, life: 1000, glow: true });
        if (big) {
          ring(x, y, it.col, { r1: 110, life: 700, w: 4 });
          text(x, Math.max(36, y - 150), it.tier === 'anc' ? `★ ${it.name}` : `✦ ${it.name}`, it.col, 18);
          if (!rare) { rare = true; flash(it.col, 0.25, 300); shake(true); if (window.Sound) window.Sound.play('rare'); }
        }
      }, i * 160));
    },
    forge(e) {
      const W = canvas.width / dpr, H = canvas.height / dpr, x = W / 2, y = H * 0.42, AT = 800, LIFE = 1700;
      const img = e.icon ? Object.assign(new Image(), { src: e.icon }) : null;
      add({ k: 'dim', a: 0.55, life: LIFE });
      add({ k: 'icon', img, x, y, size: 72, life: LIFE, at: AT, outcome: e.outcome });
      // nguyên liệu bay vào: ngọc (ép), vật liệu xoáy (Máy Hỗn Nguyên), ngọc xanh (Sinh Mệnh)
      const cols = e.mode === 'chaos' ? ['#ff8a5a', '#c49bff', '#9fd8ff', '#ffe08a'] : e.mode === 'life' ? ['#7ee08a'] : ['#9fd8ff', '#c49bff'];
      const n = e.mode === 'chaos' ? Math.min(8, Math.max(3, e.n || 4)) : e.mode === 'life' ? 1 : 2;
      for (let i = 0; i < n; i++) add({ k: 'spiral', x, y, r: 150, a0: (i / n) * Math.PI * 2, col: cols[i % cols.length], life: 560, t0: now() + i * 50 });
      // búa gõ / lò rung: tia lửa nhỏ
      for (const ms of [300, 500, 680]) setTimeout(() => { burst(x, y + 10, 8, ['#ffd27a', '#fff3b0'], { vmax: 200, g: 500, life: 500 }); ring(x, y, '#ffe9b0', { r0: 20, r1: 48, life: 260, w: 2 }); }, ms);
      setTimeout(() => {
        const lv = e.level || 0;
        if (e.outcome === 'success') {
          const col = lv >= 10 ? '#ff8a3d' : lv >= 9 ? '#ffd24a' : lv >= 7 ? '#6fb4ff' : '#ffffff';
          burst(x, y, lv >= 10 ? 60 : 34, [col, '#ffffff', '#fff3b0'], { vmax: lv >= 10 ? 420 : 300, g: 200, glow: true, life: 900 });
          ring(x, y, col, { r1: lv >= 10 ? 200 : 130, life: 650, w: 5 });
          if (lv >= 7) add({ k: 'rays', x, y, col, life: 900 });
          text(x, y - 70, e.mode === 'upgrade' && lv ? `+${lv}` : e.mode === 'life' ? '+1 dòng' : 'THÀNH CÔNG', col, lv >= 10 ? 40 : 30);
          if (lv >= 10) { flash(col, 0.35, 400); shake(true); }
          if (window.Sound) window.Sound.play(lv >= 7 ? 'levelup' : 'forge');
        } else if (e.outcome === 'destroy') {
          for (let i = 0; i < 22; i++) {
            const a = Math.random() * Math.PI * 2, v = 120 + Math.random() * 260;
            add({ k: 'dot', x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, g: 500, life: 900, r: 2 + Math.random() * 4, col: ['#b8a890', '#6b5a48', '#e0d0b0'][i % 3] });
          }
          flash('#ff2a1a', 0.35, 400); shake(true);
          text(x, y - 60, '💥 VỠ ĐỒ', '#ff6b5a', 32);
          if (window.Sound) window.Sound.play('error');
        } else {
          const segs = [[-4, -30, 6, -6], [6, -6, -8, 10], [-8, 10, 4, 30], [6, -6, 22, 4]];
          add({ k: 'crack', x, y, segs, life: 900 });
          burst(x, y - 10, 16, ['#8a8a8a', '#5a5a5a', '#b0b0b0'], { up: true, g: -40, vmin: 20, vmax: 80, life: 1100, rmin: 3, rmax: 6 });
          shake(false);
          text(x, y - 60, e.outcome === 'reset' ? 'VỀ +0' : e.outcome === 'down' ? 'TỤT CẤP' : 'THẤT BẠI', '#c8c8c8', 28);
          if (window.Sound) window.Sound.play('error');
        }
      }, AT);
    },
    pet(e) {
      const me = spot(ME), t = spot(MON);
      if (!t) return;
      const from = me ? { x: me.x + me.w * 0.6, y: me.y } : { x: t.x - 80, y: t.y + 140 };
      const img = e.img ? Object.assign(new Image(), { src: e.img }) : null;
      fly(from, t, (c, x, y, ang, k) => {
        if (img && img.complete && img.naturalWidth) { const sz = 34 + Math.sin(k * Math.PI) * 10; c.drawImage(img, x - sz / 2, y - sz / 2, sz, sz); }
        else { c.fillStyle = '#ff9ad5'; c.beginPath(); c.arc(x, y, 8, 0, Math.PI * 2); c.fill(); }
      }, 260, () => {
        add({ k: 'claw', x: t.x, y: t.y, r: t.w * 0.4, life: 300, col: '#ff9ad5' });
        burst(t.x, t.y, 10, ['#ff9ad5', '#ffffff'], { vmax: 200 });
        if (e.dmg) text(t.x + t.w * 0.35, t.y - t.h * 0.2, `🐾 -${e.dmg}`, '#ff9ad5', 18);
        bump(t.el, 'fx-hit', 260);
        if (e.tidal) EV.tidal(e);
      });
    },
    tidal() {
      const t = spot(MON);
      if (!t) return;
      add({ k: 'pillar', x: t.x, y: t.y + t.h * 0.45, w: t.w * 0.7, h: t.h * 2.2, col: '#4aa8e8', life: 900, big: true });
      burst(t.x, t.y + t.h * 0.4, 30, COLORS.water, { up: true, vmin: 120, vmax: 380, g: 600, life: 900 });
      ring(t.x, t.y + t.h * 0.45, '#9fe0ff', { r1: t.w, life: 600, w: 4 });
      shake(true);
      EV.dragon();
    },
    dragon() {
      const W = canvas.width / dpr, H = canvas.height / dpr;
      add({ k: 'dragon', W, y: H * 0.32, life: 1500 });
      flash('#ffd24a', 0.18, 400);
    },
    // rương bật nắp (Rương Gia Truyền / mua rương): nắp mở, sáng vàng, vật phẩm bay ra
    chest() {
      const W = canvas.width / dpr, H = canvas.height / dpr, x = W / 2, y = H * 0.45;
      add({ k: 'chest', x, y, life: 1300 });
      setTimeout(() => {
        burst(x, y - 14, 26, ['#ffd24a', '#fff3b0', '#9fd8ff', '#c49bff'], { up: true, vmin: 160, vmax: 360, g: 420, glow: true, life: 1100 });
        ring(x, y - 10, '#ffe9a0', { r1: 110, life: 600, w: 4 });
      }, 380);
    },
    boss(e) { if (window.Celebrate) window.Celebrate.boss(e.name); shake(true); flash('#ffd24a', 0.3, 500); },
    ghost(e) {
      const bar = document.querySelector('#view .stage .bar');
      const fill = bar && bar.querySelector('i');
      if (!fill || e.from == null) return;
      const g = document.createElement('b');
      g.className = 'fx-ghost';
      g.style.width = e.from + '%';
      bar.insertBefore(g, fill);
      requestAnimationFrame(() => requestAnimationFrame(() => { g.style.width = fill.style.width; }));
      setTimeout(() => g.remove(), 1100);
    },
  };

  // ---------- hình vẽ của vật bay ----------
  function orb(col, r = 6) {
    return (c, x, y, ang, k) => {
      for (let i = 4; i > 0; i--) { c.fillStyle = col[2]; c.globalAlpha = 0.12 * i; c.beginPath(); c.arc(x - Math.cos(ang) * i * 6, y - Math.sin(ang) * i * 6, r * (1 - i * 0.12), 0, Math.PI * 2); c.fill(); }
      c.globalAlpha = 1;
      const g = c.createRadialGradient(x, y, 0, x, y, r * 1.6);
      g.addColorStop(0, col[0]); g.addColorStop(0.5, col[1]); g.addColorStop(1, 'rgba(0,0,0,0)');
      c.fillStyle = g; c.beginPath(); c.arc(x, y, r * 1.6, 0, Math.PI * 2); c.fill();
    };
  }
  function blade(col) {
    return (c, x, y, ang) => { c.save(); c.translate(x, y); c.rotate(ang); c.strokeStyle = col[1]; c.lineWidth = 3; c.beginPath(); c.arc(-6, 0, 12, -1.1, 1.1); c.stroke(); c.restore(); };
  }
  function coin(c, x, y) { c.fillStyle = '#ffd24a'; c.strokeStyle = '#8a6a10'; c.lineWidth = 1; c.beginPath(); c.arc(x, y, 4, 0, Math.PI * 2); c.fill(); c.stroke(); }

  // ---------- vòng vẽ ----------
  function loop() {
    raf = null;
    const t = now();
    const W = canvas.width / dpr, H = canvas.height / dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    for (let i = parts.length - 1; i >= 0; i--) {
      const p = parts[i], age = t - p.t0;
      if (age < 0) continue;
      const k = age / p.life;
      if (k >= 1) {
        if (p.k === 'fly' && !p.done && p.hit) { p.done = true; p.hit(); }
        parts.splice(i, 1);
        continue;
      }
      draw(p, k, age / 1000);
    }
    ctx.globalAlpha = 1;
    if (parts.length) raf = requestAnimationFrame(loop);
    else ctx.clearRect(0, 0, W, H);
  }

  function draw(p, k, s) {
    const c = ctx;
    c.globalAlpha = 1;
    switch (p.k) {
      case 'dot': {
        const x = p.x + p.vx * s, y = p.y + p.vy * s + 0.5 * p.g * s * s;
        c.globalAlpha = 1 - k;
        if (p.glow) { c.fillStyle = p.col; c.globalAlpha = (1 - k) * 0.35; c.beginPath(); c.arc(x, y, p.r * 2.6, 0, Math.PI * 2); c.fill(); c.globalAlpha = 1 - k; }
        c.fillStyle = p.col; c.beginPath(); c.arc(x, y, p.r * (1 - k * 0.5), 0, Math.PI * 2); c.fill();
        break;
      }
      case 'ring':
        c.globalAlpha = 1 - k; c.strokeStyle = p.col; c.lineWidth = p.w * (1 - k) + 0.5;
        c.beginPath(); c.arc(p.x, p.y, p.r0 + (p.r1 - p.r0) * (1 - (1 - k) * (1 - k)), 0, Math.PI * 2); c.stroke();
        break;
      case 'text':
        c.globalAlpha = k < 0.7 ? 1 : (1 - k) / 0.3;
        c.font = `800 ${p.size}px system-ui, sans-serif`; c.textAlign = 'center';
        c.lineWidth = 4; c.strokeStyle = '#000'; c.strokeText(p.s, p.x, p.y - k * 30);
        c.fillStyle = p.col; c.fillText(p.s, p.x, p.y - k * 30);
        break;
      case 'flash': {
        const W = canvas.width / dpr, H = canvas.height / dpr;
        const g = c.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.25, W / 2, H / 2, Math.max(W, H) * 0.75);
        g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, p.col);
        c.globalAlpha = p.a * (1 - k); c.fillStyle = g; c.fillRect(0, 0, W, H);
        break;
      }
      case 'fly': {
        const e = k * k * (3 - 2 * k), x = p.x0 + (p.x1 - p.x0) * e, y = p.y0 + (p.y1 - p.y0) * e - Math.sin(k * Math.PI) * 18;
        p.draw(c, x, y, Math.atan2(p.y1 - p.y0, p.x1 - p.x0), k);
        break;
      }
      case 'slash': {
        const a0 = p.dir > 0 ? -2.4 : -0.7, sweep = 1.9 * Math.min(1, k * 2) * p.dir;
        c.globalAlpha = 1 - k; c.strokeStyle = p.col; c.lineCap = 'round';
        for (let w = 6; w > 0; w -= 2) { c.lineWidth = w; c.globalAlpha = (1 - k) * (w === 2 ? 1 : 0.3); c.beginPath(); c.arc(p.x, p.y, p.r, a0, a0 + sweep, p.dir < 0); c.stroke(); }
        break;
      }
      case 'bolt': {
        c.globalAlpha = k < 0.5 ? 1 : (1 - k) * 2; c.strokeStyle = p.col; c.lineWidth = 3; c.shadowColor = '#bfe0ff'; c.shadowBlur = 12;
        c.beginPath(); c.moveTo(p.x, p.y0);
        const n = 7;
        for (let i = 1; i <= n; i++) c.lineTo(p.x + (i < n ? rand(-14, 14) : 0), p.y0 + (p.y1 - p.y0) * i / n);
        c.stroke(); c.shadowBlur = 0;
        break;
      }
      case 'swirl':
        c.globalAlpha = 1 - k; c.strokeStyle = p.col; c.lineWidth = 2;
        for (let i = 0; i < 3; i++) { const a = k * 9 + i * 2.1; c.beginPath(); c.arc(p.x, p.y, p.r * (0.4 + i * 0.25) * (1 - k * 0.3), a, a + 2); c.stroke(); }
        break;
      case 'rock': {
        const y = p.y0 + (p.y1 - p.y0) * k * k;
        c.fillStyle = p.col; c.beginPath(); c.moveTo(p.x - 7, y + 4); c.lineTo(p.x - 3, y - 6); c.lineTo(p.x + 6, y - 4); c.lineTo(p.x + 7, y + 5); c.closePath(); c.fill();
        break;
      }
      case 'implode':
        c.globalAlpha = k; c.strokeStyle = p.col; c.lineWidth = 3;
        c.beginPath(); c.arc(p.x, p.y, p.r * (1 - k), 0, Math.PI * 2); c.stroke();
        break;
      case 'beam': {
        const g = c.createLinearGradient(p.x - p.w, 0, p.x + p.w, 0);
        g.addColorStop(0, 'rgba(255,240,180,0)'); g.addColorStop(0.5, p.col); g.addColorStop(1, 'rgba(255,240,180,0)');
        c.globalAlpha = Math.sin(k * Math.PI) * 0.85; c.fillStyle = g; c.fillRect(p.x - p.w, 0, p.w * 2, p.y + 20);
        break;
      }
      case 'plus':
        c.globalAlpha = 1 - k; c.fillStyle = p.col;
        c.fillRect(p.x - 1.5, p.y - 5 - k * 34, 3, 10); c.fillRect(p.x - 5, p.y - 1.5 - k * 34, 10, 3);
        break;
      case 'pillar': {
        const a = Math.sin(Math.min(1, k * 1.4) * Math.PI) * (p.big ? 0.95 : 0.75);
        const g = c.createLinearGradient(0, p.y - p.h, 0, p.y);
        g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(0.6, p.col); g.addColorStop(1, '#ffffff');
        c.globalAlpha = a; c.fillStyle = g;
        c.fillRect(p.x - p.w / 2, p.y - p.h * Math.min(1, k * 3), p.w, p.h * Math.min(1, k * 3));
        c.globalAlpha = a * 0.5; c.beginPath(); c.ellipse(p.x, p.y, p.w * 1.4, p.w * 0.45, 0, 0, Math.PI * 2); c.fill();
        break;
      }
      case 'dim':
        c.globalAlpha = p.a * Math.min(1, k * 6, (1 - k) * 4); c.fillStyle = '#05030a';
        c.fillRect(0, 0, canvas.width / dpr, canvas.height / dpr);
        break;
      case 'icon': {
        const t = k * p.life, out = t >= p.at, sz = p.size;
        if (out && p.outcome === 'destroy') break;
        const pre = Math.min(1, t / p.at), sh = out ? 0 : pre * pre * 4;
        const pulse = out && p.outcome === 'success' ? 1 + 0.25 * Math.sin(Math.min(1, (t - p.at) / 300) * Math.PI) : 1;
        const x = p.x + (Math.random() - 0.5) * sh, y = p.y + (Math.random() - 0.5) * sh;
        c.globalAlpha = Math.min(1, k * 8, (1 - k) * 5);
        if (out && p.outcome !== 'success') c.filter = 'grayscale(1) brightness(0.6)';
        if (p.img && p.img.complete && p.img.naturalWidth) c.drawImage(p.img, x - sz * pulse / 2, y - sz * pulse / 2, sz * pulse, sz * pulse);
        else { c.fillStyle = '#ffe79a'; c.beginPath(); c.arc(x, y, sz * 0.3 * pulse, 0, Math.PI * 2); c.fill(); }
        c.filter = 'none';
        break;
      }
      case 'crack':
        c.globalAlpha = Math.min(1, (1 - k) * 3); c.strokeStyle = '#1a1210'; c.lineWidth = 2;
        for (const seg of p.segs) { c.beginPath(); c.moveTo(p.x + seg[0], p.y + seg[1]); c.lineTo(p.x + seg[2], p.y + seg[3]); c.stroke(); }
        break;
      case 'rays':
        c.globalAlpha = Math.sin(k * Math.PI) * 0.7; c.strokeStyle = p.col; c.lineWidth = 3;
        for (let i = 0; i < 12; i++) { const a = i * Math.PI / 6 + k; c.beginPath(); c.moveTo(p.x + Math.cos(a) * 30, p.y + Math.sin(a) * 30); c.lineTo(p.x + Math.cos(a) * (60 + k * 90), p.y + Math.sin(a) * (60 + k * 90)); c.stroke(); }
        break;
      case 'spiral': {
        const a = p.a0 + k * 5, r = p.r * (1 - k);
        const x = p.x + Math.cos(a) * r, y = p.y + Math.sin(a) * r * 0.8;
        c.globalAlpha = 0.9; c.fillStyle = p.col; c.beginPath(); c.arc(x, y, 5, 0, Math.PI * 2); c.fill();
        c.globalAlpha = 0.3; c.beginPath(); c.arc(x, y, 11, 0, Math.PI * 2); c.fill();
        break;
      }
      case 'dragon': {
        // thân rồng: chuỗi vảy vàng uốn lượn từ trái sang phải, đầu to, đuôi nhỏ dần
        const head = -120 + (p.W + 240) * k, n = 26;
        for (let i = n - 1; i >= 0; i--) {
          const x = head - i * 11, y = p.y + Math.sin(x / 55 + k * 6) * 26 + Math.sin(x / 23) * 4;
          const r = i === 0 ? 13 : Math.max(3, 10 - i * 0.28);
          c.globalAlpha = Math.min(1, k * 6, (1 - k) * 6) * (i === 0 ? 1 : 0.9);
          c.fillStyle = i % 3 === 0 ? '#fff0a8' : '#ffc93d';
          c.shadowColor = '#ffd24a'; c.shadowBlur = 12;
          c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.fill();
          if (i === 0) { c.fillStyle = '#8a2a00'; c.beginPath(); c.arc(x + 5, y - 3, 2.2, 0, Math.PI * 2); c.fill(); }
        }
        c.shadowBlur = 0;
        break;
      }
      case 'chest': {
        // hộp gỗ viền vàng, nắp xoay mở từ 0,25 tới 0,45 thời gian; quầng sáng từ trong rương
        const a = Math.min(1, k * 6, (1 - k) * 4), open = Math.min(1, Math.max(0, (k - 0.2) / 0.2)), w = 64, h = 40;
        c.globalAlpha = a;
        if (open > 0) {
          const g = c.createRadialGradient(p.x, p.y - h / 2, 4, p.x, p.y - h / 2, 90);
          g.addColorStop(0, `rgba(255, 230, 140, ${0.8 * open})`); g.addColorStop(1, 'rgba(255, 230, 140, 0)');
          c.fillStyle = g; c.fillRect(p.x - 90, p.y - h / 2 - 90, 180, 180);
        }
        c.fillStyle = '#6b3f1d'; c.fillRect(p.x - w / 2, p.y - h / 2, w, h);
        c.strokeStyle = '#e0b040'; c.lineWidth = 3; c.strokeRect(p.x - w / 2, p.y - h / 2, w, h);
        c.fillStyle = '#e0b040'; c.fillRect(p.x - 5, p.y - h / 2 + 4, 10, 10);
        c.save(); c.translate(p.x - w / 2, p.y - h / 2); c.rotate(-open * 1.9);
        c.fillStyle = '#7d4a22'; c.fillRect(0, -16, w, 16); c.strokeRect(0, -16, w, 16);
        c.restore();
        break;
      }
      case 'bubble': {
        const y = p.y - k * p.rise, x = p.x + Math.sin(k * 8 + p.ph) * 4;
        c.globalAlpha = (1 - k) * 0.85; c.strokeStyle = p.col; c.lineWidth = 1.5;
        c.beginPath(); c.arc(x, y, p.r * (0.6 + k * 0.6), 0, Math.PI * 2); c.stroke();
        c.globalAlpha = (1 - k) * 0.35; c.fillStyle = p.col; c.fill();
        break;
      }
      case 'drop': {
        const y = p.y + k * k * 40;
        c.globalAlpha = 1 - k; c.fillStyle = p.col;
        c.beginPath(); c.moveTo(p.x, y - 6); c.quadraticCurveTo(p.x + 4, y + 1, p.x, y + 3); c.quadraticCurveTo(p.x - 4, y + 1, p.x, y - 6); c.fill();
        break;
      }
      case 'stars': {
        const a0 = now() / 260;
        for (let i = 0; i < 3; i++) {
          const a = a0 + i * (Math.PI * 2 / 3), x = p.x + Math.cos(a) * p.r, y = p.y + Math.sin(a) * p.r * 0.35;
          c.globalAlpha = 0.95; c.fillStyle = '#ffe066'; c.font = '700 14px system-ui, sans-serif'; c.textAlign = 'center';
          c.fillText('★', x, y + 5);
        }
        break;
      }
      case 'spark': {
        const y = p.y + (p.vy || 0) * k;
        c.globalAlpha = Math.sin(k * Math.PI) * (p.a || 1); c.fillStyle = p.col;
        c.shadowColor = p.col; c.shadowBlur = 6;
        c.beginPath(); c.arc(p.x, y, p.r, 0, Math.PI * 2); c.fill();
        c.shadowBlur = 0;
        break;
      }
      case 'claw':
        c.globalAlpha = 1 - k; c.strokeStyle = p.col; c.lineWidth = 3; c.lineCap = 'round';
        for (let i = -1; i <= 1; i++) { const d = Math.min(1, k * 3); c.beginPath(); c.moveTo(p.x - p.r * 0.6 + i * 8, p.y - p.r * 0.6); c.lineTo(p.x - p.r * 0.6 + i * 8 + p.r * 1.2 * d, p.y - p.r * 0.6 + p.r * 1.2 * d); c.stroke(); }
        break;
    }
  }

  // ---------- hiệu ứng nền ở màn trận (trạng thái, hào quang, cánh) ----------
  let amb = null, ambTimer = null;
  const AURA_COL = { 7: ['#6fb4ff', '#cfe6ff'], 9: ['#ffd24a', '#fff3b0'], 11: ['#ff6a2a', '#ffb35a'] };
  function ambientTick() {
    if (!amb || !on() || document.hidden) return;
    const t = spot(MON), me = spot(ME);
    if (!t && !me) return;
    const status = (s, list, under) => {
      if (!s) return;
      for (const id of list) {
        if (id === 'poison' && Math.random() < 0.7) add({ k: 'bubble', x: s.x + rand(-s.w * 0.3, s.w * 0.3), y: s.y + s.h * 0.2, rise: rand(30, 60), r: rand(3, 6), ph: rand(0, 6), col: '#8fe05a', life: 900 });
        if (id === 'burn') add({ k: 'spark', x: s.x + rand(-s.w * 0.3, s.w * 0.3), y: s.y + s.h * 0.3, vy: -rand(30, 60), r: rand(1.5, 3), col: ['#ffb03d', '#ff4a1f', '#fff3b0'][Math.floor(rand(0, 3))], life: 700 });
        if (id === 'bleed' && Math.random() < 0.6) add({ k: 'drop', x: s.x + rand(-s.w * 0.25, s.w * 0.25), y: s.y + rand(-4, s.h * 0.2), col: '#d61f2c', life: 600 });
        if (id === 'stun' && !under) add({ k: 'stars', x: s.x, y: s.y - s.h * 0.55, r: Math.max(14, s.w * 0.3), life: 150 });
      }
    };
    status(t, amb.mon || []);
    status(me, amb.me || [], true);
    if (me && AURA_COL[amb.aura]) {
      const col = AURA_COL[amb.aura], n = amb.aura >= 11 ? 2 : 1;
      for (let i = 0; i < n; i++) if (amb.aura >= 9 || Math.random() < 0.5) add({ k: 'spark', x: me.x + rand(-me.w * 0.45, me.w * 0.45), y: me.y + me.h * 0.35, vy: -rand(25, 55), r: rand(1.2, 2.6), col: col[i % 2], a: 0.9, life: 900 });
    }
    if (me && amb.wing && Math.random() < 0.5) add({ k: 'spark', x: me.x + (Math.random() < 0.5 ? -1 : 1) * rand(me.w * 0.25, me.w * 0.6), y: me.y - me.h * 0.2, vy: rand(25, 45), r: rand(1, 2), col: '#e8f4ff', a: 0.8, life: 900 });
  }

  window.BattleFx = {
    enabled: on,
    // trạng thái nền của màn trận: { mon: [id], me: [id], aura, wing } hoặc null (rời trận)
    ambient(state) {
      amb = state && ((state.mon || []).length || (state.me || []).length || state.aura || state.wing) ? state : null;
      if (amb && !ambTimer && on() && ensure()) ambTimer = setInterval(ambientTick, 150);
      if (!amb && ambTimer) { clearInterval(ambTimer); ambTimer = null; }
    },
    run(events) {
      if (!events || !events.length || !on() || !ensure()) return;
      // chờ màn trận vẽ xong (ui.js render) rồi mới lấy vị trí
      const play = (e) => { try { (EV[e.type] || (() => {}))(e); } catch (err) { /* hiệu ứng lỗi không làm hỏng trận */ } };
      requestAnimationFrame(() => events.forEach((e) => (e.delay ? setTimeout(() => play(e), e.delay) : play(e))));
    },
  };
})();

/* Khoảnh khắc thành tích (docs/FX_PLAN.md đợt 4): lên cấp, chuyển sinh, thẻ thành tựu, dải thông báo cả server.
 * Phần tử DOM phủ lên màn hình (không bắt chuột trừ khi bấm tắt), tự gỡ; "giảm chuyển động" thì CSS tắt chuyển động. */
(function () {
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const sound = (id) => { if (window.Sound) window.Sound.play(id); };
  function mount(cls, html, ms) {
    const el = document.createElement('div');
    el.className = cls;
    el.setAttribute('aria-hidden', 'true');
    el.innerHTML = html;
    document.body.appendChild(el);
    if (ms) setTimeout(() => el.remove(), ms);
    return el;
  }

  // đặt ngay dưới thanh trên cùng (tên, máu, vàng) để không che
  function belowHud(el, gap) {
    const hud = document.getElementById('hud');
    const r = hud && !hud.hidden && hud.getBoundingClientRect();
    if (r && r.height) el.style.top = `${Math.round(r.bottom + gap)}px`;
  }

  // dải thông báo: xếp hàng, mỗi lần một dải chạy ngang đầu màn hình
  const queue = [];
  let showing = false;
  // loại theo biểu tượng / chữ đầu dòng (server gửi chữ, client tô màu)
  function kindOf(text) {
    if (/^🐉/.test(text)) return 'dragon';
    if (/^✨/.test(text) || /Đồ Thần/.test(text)) return 'anc';
    if (/^📢/.test(text) && /\+1[01]\b|ép thành công|ghép thành công/.test(text)) return 'forge';
    if (/^(👑|🐲|🔥)/.test(text) || /Trùm|trùm thế giới|Rồng Đỏ|Phù Thủy/.test(text)) return 'boss';
    if (/^(⚔|🏰|🏆|🎉)/.test(text)) return 'event';
    return 'info';
  }
  function next() {
    const text = queue.shift();
    if (!text) { showing = false; return; }
    showing = true;
    const k = kindOf(text);
    // dòng đã mở đầu bằng biểu tượng thì dùng luôn biểu tượng đó (không lặp)
    const lead = text.match(/^(\p{Extended_Pictographic}\uFE0F?)\s*/u);
    const icon = lead ? lead[1] : { dragon: '🐉', anc: '★', forge: '⚒', boss: '👑', event: '⚔', info: '📢' }[k];
    const body = lead ? text.slice(lead[0].length) : text;
    const el = mount(`ticker t-${k}`, `<span class="ti">${icon}</span><span class="tt"><span>${esc(body)}</span></span>`, 0);
    belowHud(el, 6);
    const t = el.querySelector('.tt span');
    // chữ dài thì chạy ngang, ngắn thì đứng giữa
    requestAnimationFrame(() => {
      const over = t.scrollWidth - el.querySelector('.tt').clientWidth;
      if (over > 0) { t.style.setProperty('--run', `-${over + 24}px`); t.classList.add('run'); }
    });
    if (k !== 'info') sound('rare');
    setTimeout(() => { el.classList.add('out'); setTimeout(() => { el.remove(); next(); }, 400); }, 5200);
  }

  window.Celebrate = {
    banner(text) { if (!text) return; queue.push(text); if (queue.length > 5) queue.shift(); if (!showing) next(); },
    badge(text) {
      const m = String(text).match(/(Thành tựu mới|Danh hiệu mới)[:\s]*(.*)/);
      belowHud(mount('badge-card', `<span class="bi">🏅</span><span class="bt"><b>${esc(m ? m[1] : 'Thành tựu')}</b><span>${esc(m ? m[2] : text)}</span></span>`, 3600), 52);
      sound('achieve');
    },
    // lines: ['+120 máu', …]
    levelUp(level, lines) {
      const el = mount('lvup', `<div class="lv-rays"></div><div class="lv-t">LEVEL UP</div><div class="lv-n">Cấp ${level}</div>
        <div class="lv-lines">${(lines || []).map((l, i) => `<span style="animation-delay:${0.35 + i * 0.12}s">${esc(l)}</span>`).join('')}</div>`, 2600);
      return el;
    },
    // màn chuyển cảnh chuyển sinh: bấm để tắt sớm
    rebirth(n, doll, name) {
      const el = mount('rebirth-fx', `<div class="rb-swirl"></div><img class="rb-doll" src="${doll}" alt=""><div class="rb-t">CHUYỂN SINH</div>
        <div class="rb-n">Lần thứ ${n}</div><div class="rb-name">${esc(name || '')}</div>`, 4200);
      el.addEventListener('click', () => el.remove());
      sound('levelup');
    },
    boss(name) {
      mount('boss-down', `<div class="bd-t">TRÙM ĐÃ GỤC</div><div class="bd-n">${esc(name || '')}</div>`, 2400);
      sound('win');
    },
  };
})();
