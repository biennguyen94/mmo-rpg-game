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

  // Màu cánh theo lớp nhân vật: [viền, thân, sáng]
  const WING_COLORS = {
    dk: ['#5a0f12', '#c0392b', '#ff8a6b'],
    dw: ['#0f2a5a', '#3c6fc8', '#a2c4ff'],
    elf: ['#5a4310', '#e0b437', '#fff1b0'],
    mg: ['#2a0f45', '#7d3cc8', '#c9a2ff'],
  };

  // Hai cánh sau vai (khung 32×32, nhân vật đứng giữa). Cánh cấp 2 to hơn và có thêm lớp lông;
  // cấp 3 (Phase 15e) to nhất, thêm viền sáng ngoài cùng.
  function drawWingCode(g, wing) {
    const [edge, body, light] = WING_COLORS[wing.cls] || WING_COLORS.dk;
    const big = wing.tier >= 2, huge = wing.tier >= 3;
    const half = (dir) => {
      const cx = 16, top = huge ? 2 : big ? 4 : 7, tip = huge ? 0 : big ? 1 : 3, bottom = huge ? 27 : big ? 24 : 21;
      const x = (v) => cx + dir * v;
      g.beginPath();
      g.moveTo(x(2), 11);
      g.quadraticCurveTo(x(8), top, x(16 - tip), top + 1);
      g.quadraticCurveTo(x(13), 13, x(15 - tip), bottom - 4);
      g.quadraticCurveTo(x(9), bottom - 2, x(3), 17);
      g.closePath();
      g.fillStyle = body;
      g.fill();
      g.lineWidth = 1;
      g.strokeStyle = edge;
      g.stroke();
      // lông vũ
      g.strokeStyle = light;
      for (let i = 0; i < (big ? 4 : 3); i++) {
        g.beginPath();
        g.moveTo(x(4), 12 + i);
        g.lineTo(x(12 - i), top + 4 + i * 3);
        g.stroke();
      }
      if (big) {
        g.beginPath();
        g.moveTo(x(3), 15);
        g.quadraticCurveTo(x(9), 22, x(13), bottom);
        g.strokeStyle = edge;
        g.stroke();
      }
      if (huge) {
        g.beginPath();
        g.moveTo(x(2), 11);
        g.quadraticCurveTo(x(8), top, x(16 - tip), top + 1);
        g.strokeStyle = light;
        g.stroke();
      }
    };
    g.save();
    g.globalAlpha = 0.95;
    half(-1);
    half(1);
    g.restore();
  }

  // Cánh rồng của bộ tile (DECISIONS "Hình nhân vật Dungeon Crawl đủ lớp"): màu theo lớp; cấp 2 thêm viền sáng màu lớp,
  // cấp 3 viền sáng dày hơn và đốm sáng quanh cánh (hạt sáng bay của cánh vẫn vẽ ở map.js / fx.js như cũ).
  // Ảnh cánh tải hỏng thì vẽ cánh bằng code như trước.
  const WING_IMG = { dk: 'wing/draconic_wing_red', dw: 'wing/draconic_wing_purple', elf: 'wing/draconic_wing_yellow', mg: 'wing/draconic_wing_black' };
  const wingPath = (wing) => (wing ? WING_IMG[wing.cls] || WING_IMG.dk : null);
  function drawWing(g, wing, im) {
    if (!im) { drawWingCode(g, wing); return; }
    const light = (WING_COLORS[wing.cls] || WING_COLORS.dk)[2];
    if (wing.tier >= 2) {
      // viền: hình cánh tô một màu, vẽ lệch 1px bốn phía (cấp 3: thêm bốn góc) dưới cánh thật
      const t = document.createElement('canvas');
      t.width = 32; t.height = 32;
      const tg = t.getContext('2d');
      tg.drawImage(im, 0, 0);
      tg.globalCompositeOperation = 'source-in';
      tg.fillStyle = light;
      tg.fillRect(0, 0, 32, 32);
      const offs = [[1, 0], [-1, 0], [0, 1], [0, -1]].concat(wing.tier >= 3 ? [[1, 1], [-1, -1], [1, -1], [-1, 1]] : []);
      g.save();
      g.globalAlpha = wing.tier >= 3 ? 0.95 : 0.8;
      offs.forEach(([x, y]) => g.drawImage(t, x, y));
      g.restore();
    }
    g.drawImage(im, 0, 0);
    if (wing.tier >= 3) {
      g.fillStyle = '#ffffff';
      [[3, 4], [28, 3], [1, 11], [30, 12], [6, 1], [25, 8]].forEach(([x, y]) => g.fillRect(x, y, 1, 1));
      g.fillStyle = light;
      [[4, 4], [27, 3], [2, 11], [29, 12]].forEach(([x, y]) => g.fillRect(x, y, 1, 1));
    }
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
    const wp = look && look.wing && wingPath(look.wing);
    const wim = wp && !failed[wp] ? image(wp) : null;
    if (!ims.length || !ims.every((im) => im.complete && im.naturalWidth)) return null;
    if (wim && !(wim.complete && wim.naturalWidth)) return null;
    const c = document.createElement('canvas');
    c.width = 32; c.height = 32;
    const g = c.getContext('2d');
    if (look && look.wing) drawWing(g, look.wing, wim);
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

  window.Doll = { canvas, url, src, fix, onReady: (f) => listeners.push(f) };
})();
