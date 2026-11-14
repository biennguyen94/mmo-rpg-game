/* Hình nhân vật ghép từ nhiều lớp (bộ tile Dungeon Crawl, assets/doll; DECISIONS "Hình nhân vật Dungeon Crawl đủ lớp"):
 * `look` do server gửi (Engine.look): { body, hair, beard, helm, armor, pants, gloves, boots, cloak, weapon, shield, wing,
 * pet } với mỗi lớp là đường dẫn trong assets/doll (thiếu thì bỏ lớp đó; quần, giày trống thì dùng mặc định); riêng
 * `wing` là { cls, tier } và được vẽ bằng code (không cần ảnh), nằm dưới cùng.
 * Thứ tự (dưới lên trên): cánh, áo choàng, thân, giày, quần, giáp, găng, tóc, râu, mũ, vũ khí, khiên.
 *
 * Doll.canvas(look) trả về canvas 32×32 đã ghép (null khi hình chưa tải xong);
 * Doll.url(look) trả về ảnh dạng data URL để dùng trong <img>, tạm dùng hình mặc định khi
 * chưa xong. Tải xong thì gọi các hàm đăng ký bằng Doll.onReady để vẽ lại. */
(function () {
  const BASE = ['base/human_m', 'legs/pants_black', 'boots/short_brown2'];
  const FALLBACK = 'assets/monsters/hero.png';
  const images = {}, done = {}, urls = {};
  const listeners = [];
  let notifyTimer = null;

  // `look.body`: thân riêng theo lớp (Tiên Nữ: base/elf_f), thay thân nam mặc định
  const layers = (look) => {
    const l = look || {};
    return [l.cloak, l.body || BASE[0], l.boots || BASE[2], l.pants || BASE[1], l.armor, l.gloves, l.hair, l.beard, l.helm, l.weapon, l.shield].filter(Boolean);
  };
  const wingKey = (look) => (look && look.wing ? `wing:${look.wing.cls}:${look.wing.tier}` : '');
  const key = (look) => layers(look).join('|') + wingKey(look);

  // Cánh (DECISIONS "Cánh: bay lơ lửng, cánh ánh sáng"): không còn hình cánh ghép vào nhân vật. Cấp 1: bay lơ lửng + vòng
  // sáng dưới chân; cấp 2: thêm đôi cánh ánh sáng trong suốt màu lớp; cấp 3: cánh to, sáng hơn + hạt sáng bay quanh.
  // Trên bản đồ `fly()` vẽ mượt ở độ phân giải màn hình (nhấp nhô, cánh vỗ); hình tĩnh 32px (hồ sơ, chọn nhân vật, màn trận)
  // vẽ một khung cố định trong `canvas()`.
  const LIGHT = { dk: [255, 110, 80], dw: [120, 160, 255], elf: [255, 215, 90], mg: [190, 130, 255] };
  // nhân vật nam (Kiếm Sĩ, Phù Thủy, Đấu Sĩ): cánh sẫm màu (thân cánh tối, viền sáng màu lớp, gân tối); Tiên Nữ cánh ánh sáng
  const DARK = { dk: [70, 8, 10], dw: [12, 18, 58], mg: [38, 8, 58] };
  // nửa cánh (đơn vị: 1 = 1/32 hình nhân vật), gốc ở lưng
  const WING_PTS = [[1, 0.5], [6.5, -5.5], [11.5, -7.5], [14.5, -4.5], [12.5, 0], [10, 3], [6.5, 5], [2, 3.5]];
  function lightWings(g, x, y, s, flap, rgb, alpha, dark) {
    const [r, gg, b] = rgb;
    g.save();
    g.shadowColor = `rgba(${r}, ${gg}, ${b}, 0.9)`;
    g.shadowBlur = 6 * s;
    for (const side of [-1, 1]) {
      g.beginPath();
      WING_PTS.forEach(([ax, ay], i) => {
        const px = x + side * ax * s, py = y + (ay - flap * (ax / 14.5) * 7) * s;
        if (i) g.lineTo(px, py); else g.moveTo(px, py);
      });
      g.closePath();
      const grd = g.createLinearGradient(x, y, x + side * 14 * s, y - 6 * s);
      if (dark) {
        // thân cánh sẫm gần như đặc, đầu cánh ngả màu lớp; viền sáng màu lớp
        const [dr, dg, db] = dark, a = Math.min(1, alpha + 0.3);
        grd.addColorStop(0, `rgba(${dr >> 1}, ${dg >> 1}, ${db >> 1}, ${a})`);
        grd.addColorStop(0.6, `rgba(${dr}, ${dg}, ${db}, ${a})`);
        grd.addColorStop(1, `rgba(${(dr + r) >> 1}, ${(dg + gg) >> 1}, ${(db + b) >> 1}, ${a * 0.85})`);
      } else {
        grd.addColorStop(0, `rgba(${r}, ${gg}, ${b}, ${alpha})`);
        grd.addColorStop(1, `rgba(${Math.min(255, r + 80)}, ${Math.min(255, gg + 80)}, ${Math.min(255, b + 80)}, ${alpha * 0.55})`);
      }
      g.fillStyle = grd;
      g.fill();
      if (dark) {
        g.shadowBlur = 3 * s;
        g.strokeStyle = `rgba(${r}, ${gg}, ${b}, ${Math.min(1, alpha + 0.2)})`;
        g.lineWidth = Math.max(0.6, 0.6 * s);
        g.stroke();
      }
      // gân cánh
      g.shadowBlur = 0;
      g.strokeStyle = dark ? `rgba(0, 0, 0, ${alpha})` : `rgba(255, 255, 255, ${alpha * 0.6})`;
      g.lineWidth = Math.max(0.5, 0.5 * s);
      for (let k = 0; k < 3; k++) {
        g.beginPath();
        g.moveTo(x + side * s, y + s);
        g.lineTo(x + side * (7.5 + k * 2.5) * s, y + (-5 + k * 3 - flap * 4) * s);
        g.stroke();
      }
      g.shadowBlur = 6 * s;
    }
    g.restore();
  }
  function footRing(g, x, y, s, rgb, a) {
    const [r, gg, b] = rgb;
    g.save();
    g.shadowColor = `rgba(${r}, ${gg}, ${b}, 1)`;
    g.shadowBlur = 5 * s;
    g.strokeStyle = `rgba(${r}, ${gg}, ${b}, ${a})`;
    g.lineWidth = 1.2 * s;
    g.beginPath(); g.ellipse(x, y, 9 * s, 3 * s, 0, 0, Math.PI * 2); g.stroke();
    g.fillStyle = `rgba(${r}, ${gg}, ${b}, ${a * 0.25})`;
    g.fill();
    g.restore();
  }
  // khung tĩnh trong hình 32px: vòng sáng dưới chân, cấp 2+ cánh nhỏ sau lưng (vẽ trước các lớp nhân vật)
  function drawWing(g, wing) {
    const rgb = LIGHT[wing.cls] || LIGHT.dk;
    if (wing.tier >= 2) lightWings(g, 16, 11, wing.tier >= 3 ? 1.05 : 0.85, 0.3, rgb, wing.tier >= 3 ? 0.7 : 0.55, DARK[wing.cls]);
  }
  function drawWingFront(g, wing) {
    footRing(g, 16, 30, 0.9, LIGHT[wing.cls] || LIGHT.dk, 0.8);
  }

  /** Bản đồ: vẽ cánh / vòng chân / hạt sáng quanh nhân vật ở ô (px, py) cỡ `size` (= TILE), trả độ nhấp nhô (âm: lên trên)
   * để vẽ nhân vật lệch theo. Gọi trước khi vẽ hình nhân vật (cánh nằm sau); `fx` tắt thì đứng yên, không hạt. */
  function fly(g, look, px, py, size, t, fx) {
    const w = look && look.wing;
    if (!w) return 0;
    const s = size / 32, rgb = LIGHT[w.cls] || LIGHT.dk;
    const bob = fx ? -(0.5 + 0.5 * Math.sin(t / 520)) * 3 * s : -1.5 * s;
    const cx = px + size / 2;
    footRing(g, cx, py + size - 2 * s, s * (1 + (w.tier >= 3 ? 0.15 : 0)), rgb, fx ? 0.65 + 0.25 * Math.sin(t / 400) : 0.8);
    if (w.tier >= 2) {
      const flap = fx ? Math.sin(t / 330) * 0.35 : 0.2;
      lightWings(g, cx, py + 11 * s + bob, s * (w.tier >= 3 ? 1.35 : 1.05), flap, rgb, w.tier >= 3 ? 0.7 : 0.55, DARK[w.cls]);
    }
    const n = fx ? (w.tier >= 3 ? 8 : w.tier >= 2 ? 4 : 3) : 0;
    const [r, gg, b] = rgb;
    for (let i = 0; i < n; i++) {
      const k = ((t / 1500) + i / n) % 1, xx = cx + Math.sin(i * 2.3 + t / 700) * 11 * s;
      g.fillStyle = `rgba(${r}, ${gg}, ${b}, ${0.9 * (1 - k)})`;
      g.beginPath(); g.arc(xx, py + size - 4 * s - k * 30 * s, 1.4 * s, 0, Math.PI * 2); g.fill();
    }
    return bob;
  }

  // Ảnh lớp tải hỏng (mạng chập chờn, điện thoại vừa mở lại app): thử lại sau RETRY ms; hết lượt thì
  // bỏ lớp đó khi ghép (vẫn thấy các lớp còn lại) thay vì trả hình trần mặc định mãi mãi.
  const RETRY = [1000, 3000, 8000];
  const failed = {};
  const tries = {};
  function image(path) {
    if (!images[path]) {
      const im = new Image();
      im.onload = () => {
        // gom nhiều hình tải xong gần nhau thành một lần vẽ lại
        if (!notifyTimer) notifyTimer = setTimeout(() => { notifyTimer = null; listeners.forEach((f) => f()); }, 30);
      };
      im.onerror = () => {
        const n = tries[path] || 0;
        tries[path] = n + 1;
        if (n < RETRY.length) setTimeout(() => { delete images[path]; image(path); }, RETRY[n]);
        else { failed[path] = true; listeners.forEach((f) => f()); }
      };
      im.src = 'assets/doll/' + path + '.png' + (tries[path] ? '?r=' + tries[path] : '');
      images[path] = im;
    }
    return images[path];
  }

  function canvas(look) {
    const k = key(look);
    if (done[k]) return done[k];
    const paths = layers(look).filter((p) => !failed[p]);
    const ims = paths.map(image);
    if (!ims.length || !ims.every((im) => im.complete && im.naturalWidth)) return null;
    const c = document.createElement('canvas');
    c.width = 32; c.height = 32;
    const g = c.getContext('2d');
    if (look && look.wing) drawWing(g, look.wing);
    if (look && look.wing) drawWingFront(g, look.wing);
    ims.forEach((im) => g.drawImage(im, 0, 0));
    done[k] = c;
    return c;
  }

  function url(look) {
    const k = key(look);
    if (urls[k]) return urls[k];
    const c = canvas(look);
    if (!c) return FALLBACK;
    urls[k] = c.toDataURL();
    return urls[k];
  }

  // Thuộc tính `src` cho <img> hình nhân vật: ảnh lớp chưa tải xong thì tạm hình mặc định và đánh dấu `data-doll`,
  // tải xong thì `fix()` tự thay đúng hình (danh sách Quanh đây, hồ sơ… không vẽ lại cả trang; trước đây cứ hiện
  // hình người trần dù đang mặc đồ).
  const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
  function src(look) {
    const u = url(look);
    return u === FALLBACK ? `src="${u}" data-doll="${esc(JSON.stringify(look || {}))}"` : `src="${u}"`;
  }
  function fix() {
    if (typeof document === 'undefined') return;
    document.querySelectorAll('img[data-doll]').forEach((im) => {
      let look;
      try { look = JSON.parse(im.dataset.doll); } catch (e) { return; }
      const u = url(look);
      if (u !== FALLBACK) { im.src = u; im.removeAttribute('data-doll'); }
    });
  }
  listeners.push(fix);

  window.Doll = { canvas, url, src, fix, fly, onReady: (f) => listeners.push(f) };
})();
