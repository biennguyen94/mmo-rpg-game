/* Hiệu ứng trận đánh (docs/FX_PLAN.md, hướng A): một canvas trong suốt phủ cả màn hình, không bắt chuột; vị trí lấy từ
 * hình quái (`#view .stage > .sprite`) và hình nhân vật (`#view .me .sprite`) lúc phát, nên mọi chế độ dùng bảng trận
 * (đánh tay, tự đánh, tháp, sự kiện, đấu trường, đồ sát) đều có. Chỉ là hình: server vẫn quyết định sát thương.
 *
 * BattleFx.run(events): events là mảng { type, ... }:
 *   attack { cls, crit }        đòn thường của mình (kiếm chém / tên bay / cầu phép theo lớp)
 *   skill  { element, crit }    kỹ năng gây sát thương, hình theo hệ nguyên tố
 *   buff   { element, heal }    kỹ năng lên mình (hồi máu, tăng sức)
 *   miss                        đòn của mình trượt
 *   hurt   { crit, element }    quái / đối thủ đánh trúng mình; `element`: kỹ năng quái theo hệ (hạt màu hệ bay sang)
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
/* Hiệu ứng trên mặt đất (DECISIONS "Hiệu ứng kỹ năng trên mặt đất"): vẽ dẹt theo phối cảnh mặt đất, dùng chung cho màn
 * trận (canvas "mặt đất" trong sân đấu, dưới hình quái) và bản đồ (map.js vẽ sau ô đất, trước nhân vật).
 *   cast  vòng niệm chú dưới chân người ra chiêu (xoay, sáng dần)
 *   wave  sóng chạm đất loang ra từ chân mục tiêu, bụi / hạt văng sát đất
 *   mark  dấu để lại theo hệ, mờ dần: lửa cháy sém + than + lửa nhỏ, băng mảng băng + gai, sét vết cháy ngoằn ngoèo +
 *         tia điện, gió vệt xoáy + lá, đất vết nứt + đá vụn bật lên, bóng tối vũng tím + xúc tu trồi lên, ánh sáng vòng
 *         ký tự vàng; đòn thường: vết chém (Kiếm Sĩ, Đấu Sĩ), mũi tên cắm đất (Tiên Nữ), vết cháy nhỏ (Pháp Sư)
 * GroundFx.make(kind, el, x, y, r, { crit, cls, delay, life }) → dấu; GroundFx.draw(ctx, dấu, now, ox, oy) → false khi hết. */
window.GroundFx = (function () {
  const COL = {
    fire: ['#fff3b0', '#ffb03d', '#ff4a1f'], lightning: ['#ffffff', '#cfeaff', '#7fb8ff'], wind: ['#f0fff8', '#a8ecd0', '#5fc9a0'],
    earth: ['#f0d29a', '#b07f40', '#6b4a22'], dark: ['#e6ccff', '#9a5ce0', '#46207a'], light: ['#fffbe6', '#ffe79a', '#ffc93d'],
    water: ['#f0ffff', '#9fe0ff', '#4aa8e8'], ice: ['#f0ffff', '#bfefff', '#6cc4f0'], poison: ['#e8ffc0', '#9ad855', '#4f8a2a'],
    none: ['#ffffff', '#ffe08a', '#c9a24a'],
  };
  const LIFE = { cast: 650, wave: 560, mark: 1800 };
  const FLAT = 0.42; // mặt đất nhìn nghiêng: dẹt theo chiều dọc
  const TAU = Math.PI * 2;
  // số giả ngẫu nhiên cố định theo dấu (hình không nhảy giữa các khung)
  const rnd = (seed, i) => { const x = Math.sin(seed * 12.9898 + i * 78.233) * 43758.5453; return x - Math.floor(x); };
  const col = (el) => COL[el] || COL.none;

  function make(kind, el, x, y, r, o = {}) {
    return { kind, el: el || 'none', x, y, r: r * (o.crit ? 1.4 : 1), crit: !!o.crit, cls: o.cls, dark: !!o.dark, t0: performance.now() + (o.delay || 0),
      life: o.life || LIFE[kind] || 1000, seed: Math.random() * 1000 };
  }

  // độ mờ: hiện nhanh, giữ, mờ dần ở 40% cuối
  const fade = (k) => (k < 0.12 ? k / 0.12 : k > 0.6 ? (1 - k) / 0.4 : 1);

  function flat(c, x, y, fn) { c.save(); c.translate(x, y); c.scale(1, FLAT); fn(); c.restore(); }
  function radial(c, r, inner, outer) {
    const g = c.createRadialGradient(0, 0, 0, 0, 0, r);
    g.addColorStop(0, inner); g.addColorStop(1, outer);
    c.fillStyle = g; c.beginPath(); c.arc(0, 0, r, 0, TAU); c.fill();
  }
  // điểm ngẫu nhiên cố định trong hình tròn bán kính r (tọa độ mặt đất, chưa dẹt)
  const pt = (d, i, rr) => { const a = rnd(d.seed, i) * TAU, q = Math.sqrt(rnd(d.seed, i + 50)) * rr; return [Math.cos(a) * q, Math.sin(a) * q]; };
  // tia ngoằn ngoèo từ tâm ra ngoài (vết nứt, vết sét)
  function rays(c, d, n, len, jag, w, stroke, branch) {
    c.strokeStyle = stroke; c.lineWidth = w; c.lineCap = 'round';
    for (let i = 0; i < n; i++) {
      let a = (i / n) * TAU + rnd(d.seed, i) * 0.6, x = 0, y = 0;
      const L = len * (0.6 + 0.4 * rnd(d.seed, i + 9)), seg = 4;
      c.beginPath(); c.moveTo(0, 0);
      for (let s = 1; s <= seg; s++) {
        a += (rnd(d.seed, i * 7 + s) - 0.5) * jag;
        x += Math.cos(a) * (L / seg); y += Math.sin(a) * (L / seg);
        c.lineTo(x, y);
        if (branch && s === 2) {
          const b = a + (rnd(d.seed, i + 30) > 0.5 ? 0.7 : -0.7);
          c.moveTo(x, y); c.lineTo(x + Math.cos(b) * L * 0.3, y + Math.sin(b) * L * 0.3); c.moveTo(x, y);
        }
      }
      c.stroke();
    }
  }

  function cast(c, d, k, t, X, Y) {
    const cl = col(d.el), a = k < 0.25 ? k / 0.25 : k > 0.7 ? (1 - k) / 0.3 : 1, r = d.r * (0.45 + 0.55 * Math.min(1, k / 0.3));
    flat(c, X, Y, () => {
      c.globalAlpha = 0.35 * a; radial(c, r * 1.3, cl[1], 'rgba(0,0,0,0)');
      c.globalAlpha = 0.9 * a; c.strokeStyle = cl[1]; c.lineWidth = 2;
      c.beginPath(); c.arc(0, 0, r, 0, TAU); c.stroke();
      c.beginPath(); c.arc(0, 0, r * 0.72, 0, TAU); c.stroke();
      const rot = t / 260;
      c.strokeStyle = cl[0]; c.lineWidth = 1.5;
      for (let i = 0; i < 12; i++) { const q = rot + (i / 12) * TAU; c.beginPath(); c.moveTo(Math.cos(q) * r * 0.76, Math.sin(q) * r * 0.76); c.lineTo(Math.cos(q) * r * 0.96, Math.sin(q) * r * 0.96); c.stroke(); }
      // ngôi sao sáu cánh xoay ngược
      for (let tri = 0; tri < 2; tri++) {
        c.beginPath();
        for (let i = 0; i <= 3; i++) { const q = -rot * 0.7 + tri * Math.PI / 3 + (i / 3) * TAU; const px = Math.cos(q) * r * 0.66, py = Math.sin(q) * r * 0.66; i ? c.lineTo(px, py) : c.moveTo(px, py); }
        c.stroke();
      }
    });
  }

  function wave(c, d, k, t, X, Y) {
    const cl = col(d.el);
    flat(c, X, Y, () => {
      for (let j = 0; j < 2; j++) {
        const kk = k - j * 0.18;
        if (kk <= 0) continue;
        c.globalAlpha = Math.max(0, 1 - kk) * 0.85; c.strokeStyle = j ? cl[0] : cl[1]; c.lineWidth = Math.max(0.5, 5 * (1 - kk));
        c.beginPath(); c.arc(0, 0, d.r * (0.3 + 2.1 * kk), 0, TAU); c.stroke();
      }
      c.globalAlpha = Math.max(0, 1 - k) * 0.8;
      for (let i = 0; i < 12; i++) {
        const a = (i / 12) * TAU + rnd(d.seed, i), q = d.r * (0.3 + 1.9 * k * (0.7 + 0.3 * rnd(d.seed, i + 3)));
        c.fillStyle = i % 2 ? cl[2] : '#cdbfa8'; c.beginPath(); c.arc(Math.cos(a) * q, Math.sin(a) * q, 2.2 * (1 - k) + 0.6, 0, TAU); c.fill();
      }
    });
  }

  function mark(c, d, k, t, X, Y) {
    const cl = col(d.el), a = fade(k), r = d.r, flick = (i) => 0.55 + 0.45 * Math.sin(t / 90 + i * 1.7);
    // đòn thường theo lớp
    if (d.el === 'none' || d.el === 'water') {
      if (d.cls === 'elf') {
        // mũi tên cắm đất (đứng, không dẹt)
        c.globalAlpha = a; c.strokeStyle = '#c9b48a'; c.lineWidth = 2;
        const [px, py] = pt(d, 1, r * 0.4); const x0 = X + px, y0 = Y + py * FLAT;
        c.beginPath(); c.moveTo(x0, y0); c.lineTo(x0 + r * 0.25, y0 - r * 0.45); c.stroke();
        c.fillStyle = '#f5e6c0'; c.beginPath(); c.moveTo(x0 + r * 0.25, y0 - r * 0.45); c.lineTo(x0 + r * 0.33, y0 - r * 0.55); c.lineTo(x0 + r * 0.19, y0 - r * 0.52); c.fill();
        flat(c, x0, y0, () => { c.globalAlpha = 0.4 * a; radial(c, r * 0.25, 'rgba(40,30,20,0.8)', 'rgba(0,0,0,0)'); });
        return;
      }
      if (d.cls === 'dw' || d.el === 'water') {
        flat(c, X, Y, () => { c.globalAlpha = 0.55 * a; radial(c, r * 0.7, 'rgba(40,60,90,0.8)', 'rgba(0,0,0,0)'); c.globalAlpha = 0.8 * a * flick(1); radial(c, r * 0.3, 'rgba(160,220,255,0.6)', 'rgba(0,0,0,0)'); });
        return;
      }
      // vết chém xước (Kiếm Sĩ, Đấu Sĩ)
      flat(c, X, Y, () => {
        c.globalAlpha = 0.65 * a; c.strokeStyle = 'rgba(35,22,12,0.9)'; c.lineWidth = 3; c.lineCap = 'round';
        for (let i = -1; i <= 1; i += 2) { c.beginPath(); c.moveTo(-r * 0.8, i * r * 0.35); c.quadraticCurveTo(0, i * r * 0.1, r * 0.8, -i * r * 0.35); c.stroke(); }
        if (k < 0.3) { c.globalAlpha = (1 - k / 0.3) * 0.9; c.strokeStyle = d.crit ? '#ffd24a' : '#ffffff'; c.lineWidth = 1.5; for (let i = -1; i <= 1; i += 2) { c.beginPath(); c.moveTo(-r * 0.8, i * r * 0.35); c.quadraticCurveTo(0, i * r * 0.1, r * 0.8, -i * r * 0.35); c.stroke(); } }
      });
      return;
    }
    // quầng sáng màu hệ dưới dấu (cộng sáng): nổi trên nền sân đấu tối, trên cỏ thì như đất hắt sáng
    flat(c, X, Y, () => {
      c.globalCompositeOperation = 'lighter';
      c.globalAlpha = 0.55 * a * (k < 0.4 ? 1 : 0.6 + 0.4 * (1 - k));
      radial(c, r * 1.15, cl[1], 'rgba(0,0,0,0)');
      c.globalCompositeOperation = 'source-over';
    });
    switch (d.el) {
      case 'fire': {
        flat(c, X, Y, () => {
          c.globalAlpha = 0.7 * a; radial(c, r, 'rgba(25,8,0,0.85)', 'rgba(25,8,0,0)');
          c.globalAlpha = 0.5 * a; radial(c, r * 0.45, 'rgba(255,90,20,0.5)', 'rgba(255,90,20,0)');
          for (let i = 0; i < 12; i++) { const [px, py] = pt(d, i, r * 0.85); c.globalAlpha = a * flick(i); c.fillStyle = i % 3 ? '#ff7a2b' : '#ffd27a'; c.beginPath(); c.arc(px, py, 1.6, 0, TAU); c.fill(); }
        });
        if (k < 0.65) {
          for (let i = 0; i < 6; i++) {
            const [px, py] = pt(d, i + 20, r * 0.7), h = r * (d.dark ? 0.8 : 0.55) * (1 - k / 0.65) * (0.6 + 0.4 * Math.sin(t / 70 + i * 2)), x0 = X + px, y0 = Y + py * FLAT;
            const g = c.createLinearGradient(x0, y0, x0, y0 - h); g.addColorStop(0, cl[2]); g.addColorStop(0.6, cl[1]); g.addColorStop(1, 'rgba(255,243,176,0)');
            c.globalAlpha = 0.9 * a; c.fillStyle = g;
            c.beginPath(); c.moveTo(x0 - h * 0.22, y0); c.quadraticCurveTo(x0 - h * 0.2, y0 - h * 0.6, x0, y0 - h); c.quadraticCurveTo(x0 + h * 0.2, y0 - h * 0.6, x0 + h * 0.22, y0); c.fill();
          }
        }
        break;
      }
      case 'ice': {
        flat(c, X, Y, () => {
          c.globalAlpha = 0.6 * a; radial(c, r, 'rgba(210,245,255,0.75)', 'rgba(150,215,255,0)');
          rays(c, d, 8, r * 0.95, 0.5, 1.2, `rgba(240,255,255,${0.8 * a})`, true);
        });
        if (k < 0.55) {
          const s = Math.sin((k / 0.55) * Math.PI);
          for (let i = 0; i < 7; i++) {
            const q = (i / 7) * TAU + rnd(d.seed, i), x0 = X + Math.cos(q) * r * 0.62, y0 = Y + Math.sin(q) * r * 0.62 * FLAT, h = r * 0.5 * s * (0.6 + 0.4 * rnd(d.seed, i + 4));
            c.globalAlpha = 0.9 * a; c.fillStyle = cl[1]; c.strokeStyle = cl[0]; c.lineWidth = 1;
            c.beginPath(); c.moveTo(x0 - 4, y0); c.lineTo(x0, y0 - h); c.lineTo(x0 + 4, y0); c.closePath(); c.fill(); c.stroke();
          }
        }
        break;
      }
      case 'lightning': {
        flat(c, X, Y, () => {
          c.globalAlpha = 0.5 * a; radial(c, r * 0.5, 'rgba(20,20,30,0.8)', 'rgba(0,0,0,0)');
          rays(c, d, 6, r * 1.1, 1.3, 3, `rgba(25,25,35,${0.6 * a})`, true);
          if (k < 0.55 && Math.sin(t / 40) > -0.2) rays(c, d, 6, r * 1.1, 1.3, 1.2, `rgba(200,235,255,${0.9 * a})`, true);
          for (let i = 0; i < 5; i++) { if (Math.sin(t / 55 + i * 3) < 0.3) continue; const [px, py] = pt(d, i + 40, r); c.globalAlpha = a; c.fillStyle = cl[0]; c.beginPath(); c.arc(px, py, 2, 0, TAU); c.fill(); }
        });
        break;
      }
      case 'wind': {
        flat(c, X, Y, () => {
          c.globalAlpha = 0.25 * a; radial(c, r, 'rgba(180,230,200,0.5)', 'rgba(0,0,0,0)');
          c.strokeStyle = cl[1]; c.lineWidth = 2; c.lineCap = 'round';
          for (let arm = 0; arm < 3; arm++) {
            c.globalAlpha = 0.7 * a; c.beginPath();
            for (let s = 0; s <= 24; s++) { const th = (s / 24) * 2.6 * Math.PI, q = th + arm * (TAU / 3) + t / 280, rr = r * (0.12 + 0.88 * s / 24); s ? c.lineTo(Math.cos(q) * rr, Math.sin(q) * rr) : c.moveTo(Math.cos(q) * rr, Math.sin(q) * rr); }
            c.stroke();
          }
        });
        for (let i = 0; i < 7; i++) {
          const q = t / 380 + (i / 7) * TAU, rr = r * (0.5 + 0.35 * rnd(d.seed, i)), x0 = X + Math.cos(q) * rr, y0 = Y + Math.sin(q) * rr * FLAT - 4 - 4 * Math.sin(t / 200 + i);
          c.globalAlpha = 0.85 * a; c.fillStyle = i % 2 ? '#7fbf5a' : '#c9a45a';
          c.save(); c.translate(x0, y0); c.rotate(q * 2); c.beginPath(); c.ellipse(0, 0, 3.5, 1.6, 0, 0, TAU); c.fill(); c.restore();
        }
        break;
      }
      case 'earth': {
        flat(c, X, Y, () => {
          c.globalAlpha = 0.35 * a; radial(c, r * 1.1, 'rgba(90,60,30,0.8)', 'rgba(0,0,0,0)');
          rays(c, d, 9, r * 1.15, 0.7, 3, `rgba(40,25,10,${0.75 * a})`, true);
          rays(c, d, 9, r * 1.15, 0.7, d.dark ? 1.6 : 1, `rgba(220,190,140,${(d.dark ? 0.75 : 0.35) * a})`, true);
        });
        if (k < 0.5) {
          for (let i = 0; i < 8; i++) {
            const [px, py] = pt(d, i + 60, r * 0.9), up = r * 0.7 * Math.sin((k / 0.5) * Math.PI) * (0.5 + 0.5 * rnd(d.seed, i));
            c.globalAlpha = a; c.fillStyle = cl[i % 3]; c.beginPath(); c.arc(X + px, Y + py * FLAT - up, 2.2 + rnd(d.seed, i + 5) * 2, 0, TAU); c.fill();
          }
        }
        break;
      }
      case 'dark': {
        flat(c, X, Y, () => {
          const g = c.createRadialGradient(0, 0, 0, 0, 0, r);
          g.addColorStop(0, 'rgba(25,0,45,0.9)'); g.addColorStop(0.7, 'rgba(70,30,120,0.55)'); g.addColorStop(1, 'rgba(70,30,120,0)');
          c.globalAlpha = 0.85 * a; c.fillStyle = g; c.beginPath();
          for (let i = 0; i <= 24; i++) { const q = (i / 24) * TAU, rr = r * (0.85 + 0.15 * Math.sin(i * 1.7 + t / 260)); i ? c.lineTo(Math.cos(q) * rr, Math.sin(q) * rr) : c.moveTo(Math.cos(q) * rr, Math.sin(q) * rr); }
          c.fill();
        });
        if (k < 0.7) {
          const grow = Math.sin(Math.min(1, k / 0.35) * Math.PI / 2) * (k > 0.5 ? (0.7 - k) / 0.2 : 1);
          c.strokeStyle = cl[1]; c.lineWidth = 3; c.lineCap = 'round';
          for (let i = 0; i < 5; i++) {
            const [px, py] = pt(d, i + 80, r * 0.6), x0 = X + px, y0 = Y + py * FLAT, h = r * 0.9 * grow, sw = Math.sin(t / 150 + i) * 8;
            c.globalAlpha = 0.85 * a; c.beginPath(); c.moveTo(x0, y0); c.bezierCurveTo(x0 + sw, y0 - h * 0.35, x0 - sw, y0 - h * 0.7, x0 + sw * 0.5, y0 - h); c.stroke();
          }
        }
        break;
      }
      case 'light': {
        flat(c, X, Y, () => {
          c.globalAlpha = 0.45 * a; radial(c, r * 1.1, 'rgba(255,240,170,0.7)', 'rgba(255,220,120,0)');
          c.globalAlpha = 0.9 * a; c.strokeStyle = cl[2]; c.lineWidth = 2;
          c.beginPath(); c.arc(0, 0, r * 0.9, 0, TAU); c.stroke();
          c.beginPath(); c.arc(0, 0, r * 0.62, 0, TAU); c.stroke();
          const rot = t / 1400;
          c.fillStyle = cl[1];
          for (let i = 0; i < 12; i++) { const q = rot + (i / 12) * TAU; c.save(); c.translate(Math.cos(q) * r * 0.76, Math.sin(q) * r * 0.76); c.rotate(q); c.fillRect(-1.5, -3, 3, 6); c.restore(); }
        });
        break;
      }
      default: {
        flat(c, X, Y, () => { c.globalAlpha = 0.55 * a; radial(c, r * 0.8, cl[2], 'rgba(0,0,0,0)'); });
      }
    }
  }

  function draw(c, d, t, ox = 0, oy = 0) {
    const age = t - d.t0;
    if (age < 0) return true;
    const k = age / d.life;
    if (k >= 1) return false;
    const X = d.x - ox, Y = d.y - oy;
    c.save();
    if (d.kind === 'cast') cast(c, d, k, t, X, Y);
    else if (d.kind === 'wave') wave(c, d, k, t, X, Y);
    else mark(c, d, k, t, X, Y);
    // nền tối (sân đấu màn trận): cộng sáng thêm một lớp màu hệ đè lên, vết cháy / nứt tối mới không chìm vào nền
    if (d.dark && d.kind === 'mark' && d.el !== 'none') {
      const cl = col(d.el);
      flat(c, X, Y, () => { c.globalCompositeOperation = 'lighter'; c.globalAlpha = 0.65 * fade(k); radial(c, d.r * 0.9, d.el === 'earth' ? cl[0] : cl[1], 'rgba(0,0,0,0)'); c.globalCompositeOperation = 'source-over'; });
    }
    c.restore();
    return true;
  }

  // vẽ cả danh sách, bỏ dấu đã hết; giữ tối đa `max` dấu (bỏ dấu cũ nhất)
  function paint(c, list, t, ox, oy, max = 14) {
    if (list.length > max) list.splice(0, list.length - max);
    // cũ trước, mới đè lên
    for (let i = 0; i < list.length;) { if (draw(c, list[i], t, ox, oy)) i++; else list.splice(i, 1); }
  }

  return { make, draw, paint, LIFE };
})();

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
    // cỡ hiển thị đúng bằng vùng vẽ: trên điện thoại 100vh cao hơn innerHeight (thanh địa chỉ) làm canvas bị kéo giãn
    // dọc → hiệu ứng lệch xuống dưới (anh báo "lệch xuống 1 ô")
    canvas.style.width = window.innerWidth + 'px';
    canvas.style.height = window.innerHeight + 'px';
  }
  window.addEventListener('resize', resize);
  if (window.visualViewport) window.visualViewport.addEventListener('resize', resize);

  // tâm (và cỡ) một phần tử trên màn hình
  // ⚡ Đánh nhanh (ở lại bản đồ): vị trí quái / mình lấy từ bản đồ (`run(events, anchors)`), không có phần tử DOM
  let anchors = null;
  function spot(sel) {
    if (anchors && (sel === MON || sel === ME)) {
      const a = anchors();
      const s = a && (sel === MON ? a.mon : a.me);
      return s ? { x: s.x, y: s.y, w: s.w, h: s.h, el: null } : null;
    }
    const el = document.querySelector(sel);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    if (!r.width) return null;
    return { x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height, el };
  }
  const MON = '#view .stage > .sprite', ME = '#view .me .sprite';

  function add(p) { p.t0 = p.t0 || now(); parts.push(p); if (!raf) raf = requestAnimationFrame(loop); }

  // ---------- mặt đất (GroundFx) ----------
  // màn trận: canvas "mặt đất" chèn đầu sân đấu (`.stage`, dưới hình quái, trên nền); sân vẽ lại mỗi lượt thì chèn lại.
  // Dấu lưu theo tọa độ trong sân. Dưới chân mình (hàng `.me`, không phải mặt đất sân) vẽ trên canvas phủ như hạt.
  // ⚡ trên bản đồ: MapView.groundMark vẽ trên ô đất của bản đồ.
  const ground = [];
  let gcanvas = null;
  function groundMount() {
    const st = document.querySelector('#view .stage');
    if (!st) return null;
    if (!gcanvas) { gcanvas = document.createElement('canvas'); gcanvas.className = 'bfx-ground'; gcanvas.setAttribute('aria-hidden', 'true'); }
    if (gcanvas.parentElement !== st) st.insertBefore(gcanvas, st.firstChild);
    const w = st.clientWidth, h = st.clientHeight;
    if (gcanvas.width !== Math.round(w * dpr) || gcanvas.height !== Math.round(h * dpr)) { gcanvas.width = Math.round(w * dpr); gcanvas.height = Math.round(h * dpr); }
    return st;
  }
  function groundTick(t) {
    if (!ground.length) return;
    const st = groundMount();
    if (!st) { ground.length = 0; return; }
    const g = gcanvas.getContext('2d');
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, gcanvas.width, gcanvas.height);
    window.GroundFx.paint(g, ground, t, 0, 0);
  }
  // `who`: 'mon' (chân quái / đối thủ) | 'me' (chân mình); kind: cast | wave | mark
  function groundAt(who, kind, el, o = {}) {
    if (anchors) { if (window.MapView && window.MapView.groundMark) window.MapView.groundMark(who, kind, el, o); return; }
    const s = spot(who === 'mon' ? MON : ME);
    if (!s) return;
    const f = kind === 'cast' ? 0.42 : kind === 'wave' ? 0.34 : 0.46;
    if (who === 'mon') {
      const st = document.querySelector('#view .stage');
      if (!st) return;
      const b = st.getBoundingClientRect();
      // cỡ theo sân đấu (hình quái có khi chỉ 32px ở bố cục gọn), 1/8 chiều rộng sân, trong khoảng 30–72px
      const r = Math.min(72, Math.max(30, b.width * 0.125)) * (f / 0.46);
      ground.push(window.GroundFx.make(kind, el, s.x - b.left, s.y + s.h * 0.4 - b.top, r, { ...o, dark: true }));
      if (!raf) raf = requestAnimationFrame(loop);
    } else if (kind !== 'mark') {
      add({ k: 'ground', d: window.GroundFx.make(kind, el, s.x, s.y + s.h * 0.45, Math.max(18, s.w * f * 0.8), o), life: (window.GroundFx.LIFE[kind] || 600) + (o.delay || 0) });
    }
  }
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
      // `rev`: đối thủ là người dùng kỹ năng lên mình (đồ sát / đấu trực tiếp): bay từ đối thủ về mình
      const a = spot(ME), b = spot(MON), me = e.rev ? b : a, t = e.rev ? a : b, col = COLORS[e.element] || COLORS.none;
      if (!t) return;
      if (me) { ring(me.x, me.y + me.h * 0.35, col[1], { r0: 4, r1: 34, life: 380, w: 2 }); bump(me.el, 'fx-cast', 360); }
      const from = me || { x: t.x, y: t.y + 120 };
      switch (e.element) {
        // DECISIONS "Hiệu ứng kỹ năng theo nguyên tố" (Phase 7): mỗi hệ một màn riêng, cùng độ "đã" như Sét
        case 'fire':
          // quả cầu lửa kéo đuôi tàn lửa → nổ bùng, lưỡi lửa bốc lên, vòng nhiệt, chớp cam
          fly(from, t, orb(col, 10), 320, () => {
            impact(t, col, e.crit); flash('#ff7a2b', 0.24); shake(e.crit);
            ring(t.x, t.y, col[1], { r0: 8, r1: t.w * 0.9, life: 380, w: 4 });
            for (let i = 0; i < 7; i++) add({ k: 'flame', x: t.x + rand(-t.w * 0.35, t.w * 0.35), y: t.y + t.h * 0.3, h: rand(30, 70), life: rand(500, 800), col, t0: now() + i * 40 });
            burst(t.x, t.y, 26, col, { up: true, g: -60, vmin: 30, vmax: 150, life: 1100, glow: true });
          });
          for (let i = 1; i <= 5; i++) setTimeout(() => { const q = { x: from.x + (t.x - from.x) * i / 6, y: from.y + (t.y - from.y) * i / 6 }; burst(q.x, q.y, 3, col, { vmax: 40, life: 380, glow: true }); }, i * 50);
          break;
        case 'ice': {
          // ba mũi băng bay tới → nổ thành mảnh băng tỏa tròn, bông tuyết, vòng sương lạnh, chớp xanh nhạt
          const iceHit = () => {
            impact(t, col, e.crit); flash('#cfefff', 0.3, 200); shake(e.crit);
            for (let i = 0; i < 10; i++) add({ k: 'shard', x: t.x, y: t.y, a: (i / 10) * Math.PI * 2 + rand(-0.2, 0.2), len: rand(14, 26), d: rand(30, 70), life: 520, col });
            for (let i = 0; i < 5; i++) add({ k: 'frost', x: t.x + rand(-t.w * 0.5, t.w * 0.5), y: t.y + rand(-t.h * 0.4, t.h * 0.3), r: rand(5, 9), life: rand(700, 1000), col: col[0], t0: now() + i * 60 });
            ring(t.x, t.y, col[1], { r0: 6, r1: t.w, life: 520, w: 2 });
          };
          for (let i = 0; i < 3; i++) setTimeout(() => fly(from, t, shardDraw(col), 260, () => i === 2 && iceHit()), i * 80);
          break;
        }
        case 'lightning':
          for (let i = 0; i < 3; i++) add({ k: 'bolt', x: t.x + rand(-12, 12), y0: Math.max(0, t.y - 260), y1: t.y, life: 160, col: col[1], t0: now() + i * 70 });
          setTimeout(() => { flash('#dff0ff', 0.4, 160); impact(t, col, e.crit); shake(e.crit); }, 90);
          break;
        case 'wind':
          // lưỡi gió chém liên tiếp → lốc xoáy dựng đứng cuốn lá / bụi quanh mục tiêu
          for (let i = 0; i < 3; i++) setTimeout(() => fly(from, t, blade(col), 240, () => impact(t, col, e.crit && i === 2)), i * 90);
          add({ k: 'tornado', x: t.x, y: t.y + t.h * 0.4, w: t.w * 0.7, h: t.h * 1.4, life: 900, col, t0: now() + 220 });
          setTimeout(() => burst(t.x, t.y, 16, col, { vmin: 80, vmax: 220, life: 700 }), 300);
          break;
        case 'earth':
          for (let i = 0; i < 5; i++) add({ k: 'rock', x: t.x + rand(-t.w * 0.4, t.w * 0.4), y0: t.y - 240, y1: t.y + rand(-6, 10), life: 260, col: col[i % 3], t0: now() + i * 55 });
          setTimeout(() => {
            impact(t, col, e.crit); shake(true);
            // đất nứt tỏa ra dưới chân + vòng bụi
            const segs = []; for (let i = 0; i < 6; i++) { const a = rand(0, Math.PI * 2), r1 = rand(8, 16), r2 = rand(26, 44); segs.push([Math.cos(a) * r1, Math.sin(a) * r1 * 0.45, Math.cos(a) * r2, Math.sin(a) * r2 * 0.45]); }
            add({ k: 'crack', x: t.x, y: t.y + t.h * 0.42, segs, life: 900 });
            ring(t.x, t.y + t.h * 0.42, '#b9a38a', { r0: 6, r1: t.w * 0.9, life: 500, w: 5 });
            burst(t.x, t.y + t.h * 0.3, 24, ['#b9a38a', '#8a7560', '#6b4a22'], { vmax: 170, g: 140, up: true });
          }, 320);
          break;
        case 'dark':
          // cầu bóng tối → xúc tu tím quấn lấy mục tiêu, hút vào tâm, chớp tím
          fly(from, t, orb(col, 9), 340, () => {
            for (let i = 0; i < 6; i++) add({ k: 'tendril', x: t.x, y: t.y, a: (i / 6) * Math.PI * 2, r: t.w * 0.85, life: 650, col: col[1] });
            add({ k: 'implode', x: t.x, y: t.y, r: t.w * 0.95, life: 420, col: col[1] });
            setTimeout(() => { impact(t, col, e.crit); flash('#5a2a90', 0.28, 220); shake(e.crit); burst(t.x, t.y, 18, col, { vmax: 120, life: 700, glow: true }); }, 300);
          });
          break;
        case 'light':
          // cột sáng giáng xuống, vòng vàng, sao lấp lánh tỏa ra
          add({ k: 'beam', x: t.x, y: t.y, w: t.w * 0.55, life: 560, col: col[1] });
          add({ k: 'rays', x: t.x, y: t.y, life: 600, col: col[1] });
          setTimeout(() => {
            impact(t, col, e.crit); flash('#fff6c8', 0.32, 200);
            ring(t.x, t.y, col[2], { r0: 6, r1: t.w, life: 500, w: 3 });
            for (let i = 0; i < 8; i++) add({ k: 'twinkle', x: t.x + rand(-t.w * 0.7, t.w * 0.7), y: t.y + rand(-t.h * 0.6, t.h * 0.4), r: rand(4, 8), life: rand(500, 800), col: col[0], t0: now() + i * 50 });
          }, 160);
          break

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
      // kỹ năng quái theo hệ: luồng hạt màu hệ bay từ quái sang mình, nổ màu hệ
      const ec = e.element && COLORS[e.element];
      if (ec) {
        const t = spot(MON);
        if (t) for (let i = 0; i < 16; i++) {
          const life = rand(280, 380);
          add({ k: 'dot', x: t.x + rand(-8, 8), y: t.y + rand(-8, 8), vx: (me.x - t.x) / (life / 1000), vy: (me.y - t.y) / (life / 1000) + rand(-40, 40),
            g: 0, life, r: rand(2, 4), col: ec[i % 3], glow: true });
        }
        burst(me.x, me.y, 14, ec, { vmax: 180 });
        flash(ec[2], 0.22, 300);
      }
      add({ k: 'claw', x: me.x, y: me.y, r: Math.max(26, me.w * 0.7), life: 260, col: '#ff4a3d' });
      burst(me.x, me.y, e.crit ? 18 : 8, ['#ff6b5a', '#c0392b', '#ffd0c0'], { vmax: 200 });
      flash('#ff2a1a', e.crit ? 0.3 : 0.16, 260);
      if (e.crit) shake(false);
    },
    kill() {
      const t = spot(MON);
      if (!t) return;
      if (t.el) t.el.classList.add('fx-dying');
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
    // thông thạo kỹ năng lên cấp: sách sáng + chữ vàng trên đầu nhân vật
    mastery(e) {
      const me = spot(ME);
      if (!me) return;
      ring(me.x, me.y, '#ffd24a', { r1: 70, life: 600, w: 3 });
      burst(me.x, me.y - me.h * 0.3, 14, ['#ffd24a', '#fff3b0', '#9fd8ff'], { up: true, vmax: 180, glow: true, life: 900 });
      text(me.x, me.y - me.h * 0.7, `📘 ${e.text}`, '#ffd24a', 17);
      if (window.Sound) window.Sound.play('achieve');
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
  // mũi băng nhọn bay theo hướng
  function shardDraw(col) {
    return (c, x, y, ang) => {
      c.save(); c.translate(x, y); c.rotate(ang);
      c.fillStyle = col[1]; c.strokeStyle = col[0]; c.lineWidth = 1;
      c.beginPath(); c.moveTo(12, 0); c.lineTo(-6, -4); c.lineTo(-3, 0); c.lineTo(-6, 4); c.closePath(); c.fill(); c.stroke();
      c.globalAlpha = 0.4; c.fillStyle = col[0]; c.fillRect(-14, -1, 10, 2); c.restore();
    };
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
    groundTick(t);
    if (parts.length || ground.length) raf = requestAnimationFrame(loop);
    else ctx.clearRect(0, 0, W, H);
  }

  function draw(p, k, s) {
    const c = ctx;
    c.globalAlpha = 1;
    if (p.k === 'ground') { window.GroundFx.draw(c, p.d, now()); return; }
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
      case 'flame': {
        // lưỡi lửa bốc lên, đỉnh nhọn lay động, mờ dần
        const h = p.h * Math.sin(Math.min(1, k * 1.6) * Math.PI / 2) * (1 - k * 0.4), sw = Math.sin(k * 18 + p.x) * 4;
        c.globalAlpha = 1 - k; c.shadowColor = p.col[2]; c.shadowBlur = 10;
        const g = c.createLinearGradient(0, p.y, 0, p.y - h);
        g.addColorStop(0, p.col[2]); g.addColorStop(0.5, p.col[1]); g.addColorStop(1, p.col[0]);
        c.fillStyle = g; c.beginPath(); c.moveTo(p.x - 7, p.y); c.quadraticCurveTo(p.x - 8 + sw, p.y - h * 0.5, p.x + sw, p.y - h); c.quadraticCurveTo(p.x + 8 + sw, p.y - h * 0.5, p.x + 7, p.y); c.closePath(); c.fill();
        c.shadowBlur = 0;
        break;
      }
      case 'shard': {
        const d = p.d * Math.min(1, k * 2.2), x = p.x + Math.cos(p.a) * d, y = p.y + Math.sin(p.a) * d;
        c.globalAlpha = 1 - k; c.save(); c.translate(x, y); c.rotate(p.a);
        c.fillStyle = p.col[1]; c.strokeStyle = p.col[0]; c.lineWidth = 1;
        c.beginPath(); c.moveTo(p.len * 0.6, 0); c.lineTo(-p.len * 0.4, -3); c.lineTo(-p.len * 0.4, 3); c.closePath(); c.fill(); c.stroke(); c.restore();
        break;
      }
      case 'frost': {
        // bông tuyết sáu cánh xoay chậm
        c.globalAlpha = Math.sin(k * Math.PI); c.strokeStyle = p.col; c.lineWidth = 1.4;
        for (let i = 0; i < 6; i++) {
          const a = i * Math.PI / 3 + k * 1.5, ex = p.x + Math.cos(a) * p.r, ey = p.y + Math.sin(a) * p.r;
          c.beginPath(); c.moveTo(p.x, p.y); c.lineTo(ex, ey); c.stroke();
          const mx = p.x + Math.cos(a) * p.r * 0.6, my = p.y + Math.sin(a) * p.r * 0.6;
          c.beginPath(); c.moveTo(mx, my); c.lineTo(mx + Math.cos(a + 0.7) * 3, my + Math.sin(a + 0.7) * 3); c.moveTo(mx, my); c.lineTo(mx + Math.cos(a - 0.7) * 3, my + Math.sin(a - 0.7) * 3); c.stroke();
        }
        break;
      }
      case 'tornado': {
        // lốc xoáy: các vòng elip chồng lên, hẹp dưới rộng trên, xoay theo thời gian
        c.globalAlpha = Math.sin(k * Math.PI) * 0.85; c.lineWidth = 2;
        for (let i = 0; i < 7; i++) {
          const f = i / 6, y = p.y - f * p.h, rw = p.w * (0.25 + f * 0.75) / 2, ph = k * 14 + i;
          c.strokeStyle = p.col[i % 3]; c.beginPath(); c.ellipse(p.x + Math.sin(ph) * 4, y, rw, rw * 0.28, 0, ph % (Math.PI * 2), ph % (Math.PI * 2) + Math.PI * 1.4); c.stroke();
        }
        break;
      }
      case 'tendril': {
        // xúc tu bóng tối uốn lượn từ ngoài vào tâm
        const r = p.r * (1 - k * 0.8);
        c.globalAlpha = Math.sin(k * Math.PI); c.strokeStyle = p.col; c.lineWidth = 3; c.lineCap = 'round';
        c.beginPath();
        for (let i = 0; i <= 10; i++) {
          const f = i / 10, rr = r * (1 - f), a = p.a + f * 1.8 + Math.sin(k * 10 + f * 6) * 0.25;
          const x = p.x + Math.cos(a) * rr, y = p.y + Math.sin(a) * rr;
          if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
        }
        c.stroke();
        break;
      }
      case 'twinkle': {
        // sao bốn cánh lấp lánh
        const r = p.r * Math.sin(k * Math.PI);
        c.globalAlpha = Math.sin(k * Math.PI); c.fillStyle = p.col; c.shadowColor = '#fff3a0'; c.shadowBlur = 8;
        c.beginPath(); c.moveTo(p.x, p.y - r * 2); c.lineTo(p.x + r * 0.4, p.y - r * 0.4); c.lineTo(p.x + r * 2, p.y); c.lineTo(p.x + r * 0.4, p.y + r * 0.4);
        c.lineTo(p.x, p.y + r * 2); c.lineTo(p.x - r * 0.4, p.y + r * 0.4); c.lineTo(p.x - r * 2, p.y); c.lineTo(p.x - r * 0.4, p.y - r * 0.4); c.closePath(); c.fill();
        c.shadowBlur = 0;
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

  // ms từ lúc phát tới lúc đòn trúng (lần trúng cuối), khớp với EV.attack / EV.skill ở trên
  const IMPACT = { fire: 320, ice: 420, lightning: 90, wind: 420, earth: 320, dark: 640, light: 160 };
  const impactMs = (e) => (e.type === 'attack' ? (e.cls === 'elf' ? 180 : e.cls === 'dw' ? 260 : 120) : IMPACT[e.element] || 300);
  const KILL_AFTER = 160; // để thấy nổ trúng một nhịp rồi mới gục
  let hitUntil = 0;

  window.BattleFx = {
    enabled: on,
    // trạng thái nền của màn trận: { mon: [id], me: [id], aura, wing } hoặc null (rời trận)
    ambient(state) {
      amb = state && ((state.mon || []).length || (state.me || []).length || state.aura || state.wing) ? state : null;
      if (amb && !ambTimer && on() && ensure()) ambTimer = setInterval(ambientTick, 150);
      if (!amb && ambTimer) { clearInterval(ambTimer); ambTimer = null; }
    },
    // `at`: hàm trả { mon, me } (tọa độ màn hình) khi hiệu ứng không bám vào màn trận (⚡ Đánh nhanh trên bản đồ)
    run(events, at) {
      if (!events || !events.length || !on() || !ensure()) return;
      // quái gục chỉ bắt đầu mờ sau khi đòn cuối của lượt đã trúng (mỗi hệ bay / rơi lâu khác nhau, DECISIONS
      // "Hiệu ứng: quái gục sau khi đòn trúng")
      const t = now() + 16;
      for (const e of events) if (e.type === 'attack' || e.type === 'skill') hitUntil = Math.max(hitUntil, t + (e.delay || 0) + impactMs(e));
      // mặt đất (DECISIONS "Hiệu ứng kỹ năng trên mặt đất"): vòng niệm chú dưới người ra chiêu lúc phát, sóng + dấu dưới
      // mục tiêu lúc trúng; kỹ năng quái theo hệ trúng mình: dấu dưới chân mình (bản đồ)
      const gq = [];
      for (const e of events) {
        const d0 = e.delay || 0;
        if (e.type === 'skill') {
          const from = e.rev ? 'mon' : 'me', to = e.rev ? 'me' : 'mon';
          gq.push([from, 'cast', e.element, { delay: d0 }]);
          gq.push([to, 'wave', e.element, { delay: d0 + impactMs(e), crit: e.crit }]);
          gq.push([to, 'mark', e.element, { delay: d0 + impactMs(e), crit: e.crit }]);
        } else if (e.type === 'attack') {
          gq.push(['mon', 'mark', 'none', { delay: d0 + impactMs(e), crit: e.crit, cls: e.cls }]);
        } else if (e.type === 'hurt' && e.element) {
          gq.push(['me', 'wave', e.element, { delay: d0 + 120 }]);
          gq.push(['me', 'mark', e.element, { delay: d0 + 120 }]);
        }
      }
      for (const e of events) if (e.type === 'kill' || e.type === 'loot') e.delay = Math.max(e.delay || 0, Math.ceil(hitUntil - t) + (e.type === 'kill' ? KILL_AFTER : KILL_AFTER + 330));
      // chờ màn trận vẽ xong (ui.js render) rồi mới lấy vị trí
      const play = (e) => {
        anchors = at || null;
        try { (EV[e.type] || (() => {}))(e); } catch (err) { /* hiệu ứng lỗi không làm hỏng trận */ }
        anchors = null;
      };
      requestAnimationFrame(() => {
        events.forEach((e) => (e.delay ? setTimeout(() => play(e), e.delay) : play(e)));
        // dấu đặt lúc phát với `delay` (GroundFx chờ tới giờ mới vẽ); vị trí lấy ngay lúc này
        const a = at || null;
        for (const [who, kind, el, o] of gq) { anchors = a; try { groundAt(who, kind, el, o); } catch (err) { /* hình lỗi không làm hỏng trận */ } anchors = null; }
      });
    },
    // thời điểm (performance.now) đòn đã xếp lịch cuối cùng trúng: bản đồ (map.js) chờ tới đó mới cho quái tan
    hitUntil: () => hitUntil,
  };
})();

/* Khoảnh khắc thành tích (docs/FX_PLAN.md đợt 4): lên cấp, chuyển sinh, thẻ thành tựu, dải thông báo cả server.
 * Phần tử DOM phủ lên màn hình (không bắt chuột trừ khi bấm tắt), tự gỡ; "giảm chuyển động" thì CSS tắt chuyển động. */
(function () {
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const sound = (id) => { if (window.Sound) window.Sound.play(id); };
  // công tắc "Hiệu ứng động" (Cài đặt): tắt thì không có màn gặp trùm, pháo sáng (DECISIONS "Bản đồ đẹp hơn")
  const fxOn = () => !(window.MapView && window.MapView.fxOn) || window.MapView.fxOn();
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
      // B8: pháo sáng — 4 chùm nổ lệch giờ quanh chữ, mỗi chùm 14 tia
      const cols = ['#ffd24a', '#ff6a4a', '#9fd8ff', '#c49bff', '#7fe08a'];
      let fw = '';
      for (let b = 0; b < (fxOn() ? 4 : 0); b++) {
        const x = 18 + ((b * 37) % 64), y = 18 + ((b * 23) % 34), c = cols[b % cols.length], d = (0.25 + b * 0.35).toFixed(2);
        fw += `<div class="fw" style="left:${x}%;top:${y}%;--c:${c};animation-delay:${d}s">`;
        for (let i = 0; i < 14; i++) fw += `<i style="--a:${Math.round((360 / 14) * i)}deg;animation-delay:${d}s"></i>`;
        fw += '</div>';
      }
      mount('boss-down', `${fw}<div class="bd-t">TRÙM ĐÃ GỤC</div><div class="bd-n">${esc(name || '')}</div>`, 2800);
      sound('win');
      if (fw) [0.25, 0.6, 0.95, 1.3].forEach((s) => setTimeout(() => sound('firework'), s * 1000));
    },
    // Hắc Long nở (DECISIONS "Đồi Sáo Diều, Chim Lạc, Hắc Long"): trứng vỡ, rồng đen vươn lên, chữ LINH VẬT HẮC LONG
    hatch(name, img) {
      const el = mount('hatch-fx', `<div class="hx-dark"></div><div class="hx-rays"></div><img class="hx-img" src="${img}" alt=""><div class="hx-t">CON RỒNG CHÁU TIÊN</div><div class="hx-n">${esc(name || '')}</div>`, 4200);
      el.addEventListener('click', () => el.remove());
      sound('roar');
      setTimeout(() => sound('levelup'), 700);
    },
    // E1 (DECISIONS "Sự kiện, đấu trường, chiến bang trực quan"): vào trận đánh người — hai hình trượt vào, chữ VS
    // a / b: { name, doll (url ảnh), sub }
    vs(a, b, title) {
      if (!fxOn()) return;
      const side = (x, cls) => `<div class="vs-side ${cls}"><img src="${x.doll || ''}" alt=""><b>${esc(x.name || '')}</b>${x.sub ? `<span>${esc(x.sub)}</span>` : ''}</div>`;
      mount('vs-fx', `<div class="vs-dark"></div>${title ? `<div class="vs-title">${esc(title)}</div>` : ''}<div class="vs-row">${side(a, 'l')}<div class="vs-t">VS</div>${side(b, 'r')}</div>`, 2000);
      sound('encounter');
    },
    // E1: trận đánh người xong — K.O. (thắng: vàng, thua: đỏ)
    ko(win, sub) {
      if (!fxOn()) return;
      mount(`ko-fx ${win ? 'win' : 'lose'}`, `<div class="ko-t">K.O.</div><div class="ko-s">${esc(sub || '')}</div>`, 1900);
      sound(win ? 'win' : 'lose');
    },
    // B8: gặp trùm — tối sầm, chớp đỏ, chữ TRÙM XUẤT HIỆN + tên, tiếng gầm, rung màn
    bossIn(name, sub) {
      if (!fxOn()) return;
      mount('boss-in', `<div class="bi-dark"></div><div class="bi-t">⚠ TRÙM XUẤT HIỆN</div><div class="bi-n">${esc(name || '')}</div>${sub ? `<div class="bi-s">${esc(sub)}</div>` : ''}`, 2300);
      sound('roar');
      const v = document.getElementById('view');
      if (v) { v.classList.remove('fx-shake-big'); void v.offsetWidth; v.classList.add('fx-shake-big'); setTimeout(() => v.classList.remove('fx-shake-big'), 420); }
    },
  };
})();
