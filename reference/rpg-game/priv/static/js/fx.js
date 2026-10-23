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
      case 'claw':
        c.globalAlpha = 1 - k; c.strokeStyle = p.col; c.lineWidth = 3; c.lineCap = 'round';
        for (let i = -1; i <= 1; i++) { const d = Math.min(1, k * 3); c.beginPath(); c.moveTo(p.x - p.r * 0.6 + i * 8, p.y - p.r * 0.6); c.lineTo(p.x - p.r * 0.6 + i * 8 + p.r * 1.2 * d, p.y - p.r * 0.6 + p.r * 1.2 * d); c.stroke(); }
        break;
    }
  }

  window.BattleFx = {
    run(events) {
      if (!events || !events.length || !on() || !ensure()) return;
      // chờ màn trận vẽ xong (ui.js render) rồi mới lấy vị trí
      const play = (e) => { try { (EV[e.type] || (() => {}))(e); } catch (err) { /* hiệu ứng lỗi không làm hỏng trận */ } };
      requestAnimationFrame(() => events.forEach((e) => (e.delay ? setTimeout(() => play(e), e.delay) : play(e))));
    },
  };
})();
