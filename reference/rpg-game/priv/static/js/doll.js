/* Hình nhân vật ghép từ nhiều lớp (bộ tile Dungeon Crawl, assets/doll): thân, quần, giày,
 * giáp, tóc theo lớp nhân vật, vũ khí, khiên. `look` do server gửi (Engine.look):
 * { hair, weapon, armor, shield, wing, pet } với mỗi lớp là đường dẫn trong assets/doll; riêng
 * `wing` là { cls, tier } và được vẽ bằng code (không cần ảnh), nằm dưới lớp thân.
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

  const layers = (look) => BASE.concat([look && look.armor, look && look.hair, look && look.weapon, look && look.shield].filter(Boolean));
  const wingKey = (look) => (look && look.wing ? `wing:${look.wing.cls}:${look.wing.tier}` : '');
  const key = (look) => layers(look).join('|') + wingKey(look);

  // Màu cánh theo lớp nhân vật: [viền, thân, sáng]
  const WING_COLORS = {
    dk: ['#5a0f12', '#c0392b', '#ff8a6b'],
    dw: ['#0f2a5a', '#3c6fc8', '#a2c4ff'],
    elf: ['#5a4310', '#e0b437', '#fff1b0'],
    mg: ['#2a0f45', '#7d3cc8', '#c9a2ff'],
  };

  // Hai cánh sau vai (khung 32×32, nhân vật đứng giữa). Cánh cấp 2 to hơn và có thêm lớp lông.
  function drawWing(g, wing) {
    const [edge, body, light] = WING_COLORS[wing.cls] || WING_COLORS.dk;
    const big = wing.tier >= 2;
    const half = (dir) => {
      const cx = 16, top = big ? 4 : 7, tip = big ? 1 : 3, bottom = big ? 24 : 21;
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
    };
    g.save();
    g.globalAlpha = 0.95;
    half(-1);
    half(1);
    g.restore();
  }

  function image(path) {
    if (!images[path]) {
      const im = new Image();
      im.onload = () => {
        // gom nhiều hình tải xong gần nhau thành một lần vẽ lại
        if (!notifyTimer) notifyTimer = setTimeout(() => { notifyTimer = null; listeners.forEach((f) => f()); }, 30);
      };
      im.src = 'assets/doll/' + path + '.png';
      images[path] = im;
    }
    return images[path];
  }

  function canvas(look) {
    const k = key(look);
    if (done[k]) return done[k];
    const ims = layers(look).map(image);
    if (!ims.every((im) => im.complete && im.naturalWidth)) return null;
    const c = document.createElement('canvas');
    c.width = 32; c.height = 32;
    const g = c.getContext('2d');
    if (look && look.wing) drawWing(g, look.wing);
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

  window.Doll = { canvas, url, onReady: (f) => listeners.push(f) };
})();
