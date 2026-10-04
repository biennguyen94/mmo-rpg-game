/* Hàm thuần của giao diện (không đụng DOM, không đọc trạng thái toàn cục): tìm đường, chọn hình đồ
 * theo cấp, tỉ lệ máy ghép, cấp thú cưng, gom lệnh cộng điểm... Trình duyệt dùng qua `window.HLLogic`
 * (ui.js, map.js); `node --test test/js` gọi trực tiếp để kiểm (FEATURE_CATALOG N2). */
(function (root) {
  const DIRS = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };

  // Hướng bước đầu tiên trên đường ngắn nhất từ (sx, sy) tới (tx, ty), hoặc null.
  // `passable(x, y, goal)`: ô đi qua được không (`goal`: ô đích, thường được dễ hơn: đánh quái, qua cổng).
  function firstStep(sx, sy, tx, ty, passable) {
    if (sx === tx && sy === ty) return null;
    const key = (x, y) => y * 1000 + x;
    const prev = new Map([[key(sx, sy), null]]);
    const queue = [[sx, sy]];
    while (queue.length) {
      const [x, y] = queue.shift();
      for (const [dir, [dx, dy]] of Object.entries(DIRS)) {
        const nx = x + dx, ny = y + dy, k = key(nx, ny);
        if (prev.has(k)) continue;
        const goal = nx === tx && ny === ty;
        if (!passable(nx, ny, goal)) continue;
        prev.set(k, [x, y, dir]);
        if (goal) {
          // lần ngược về ô xuất phát để lấy bước đầu
          let step = dir;
          for (let p = prev.get(key(nx, ny)); p; p = prev.get(key(p[0], p[1]))) step = p[2];
          return step;
        }
        queue.push([nx, ny]);
      }
    }
    return null;
  }

  // Hình riêng theo cấp nâng: `levels` = { "0": "items/a.png", "7": "items/a_7.png", ... };
  // lấy mức lớn nhất ≤ `level`. Không có mức nào hợp thì null (dùng icon cũ).
  function iconForLevel(levels, level) {
    if (!levels) return null;
    const lv = Object.keys(levels).filter((k) => /^\d+$/.test(k) && +k <= (level || 0)).map(Number).sort((a, b) => b - a)[0];
    return lv === undefined ? null : levels[lv];
  }

  // Cấp tính chỉ số: từ `doubleFrom` (+10) mỗi cấp tính gấp đôi (như Engine.effective_level).
  const effLevel = (l, doubleFrom) => l + Math.max(0, l - doubleFrom + 1);
  // Màu viền theo cấp nâng (+7, +9, +11).
  const upClass = (l) => (l >= 11 ? ' up11' : l >= 9 ? ' up9' : l >= 7 ? ' up7' : '');

  // Tỉ lệ thành công của công thức máy ghép `r` khi đặt món đồ +`up` (như Chaos.rate).
  function chaosRate(r, up) {
    const extra = r.gear ? (r.per_up || 0) * Math.max(0, up - r.gear.min_up) : 0;
    return Math.min(r.max_rate || 1, r.rate + extra);
  }

  // Số trận thắng cần để thú lên cấp `lv`; cấp hiện tại từ số trận đã thắng (như Pets.level).
  const petXpFor = (lv, coef) => coef * lv * (lv - 1);
  function petLevel(xp, coef, maxLevel) {
    let lv = 1;
    while (lv < maxLevel && petXpFor(lv + 1, coef) <= xp) lv++;
    return { lv, xp, next: lv < maxLevel ? petXpFor(lv + 1, coef) : null, from: petXpFor(lv, coef) };
  }
  // Giá thuần phục loài quái `m` (như Pets.tame_price).
  const tamePrice = (m, base, perLevel) => base + m.level * perLevel;

  // Gom lệnh cộng điểm: bấm + nhiều lần thì cộng dồn ở client, gửi một lệnh mỗi chỉ số.
  // Trả về bảng chờ mới, hoặc null nếu đã hết điểm (`points` - số đang chờ).
  function allocAdd(pending, stat, points) {
    const total = Object.values(pending).reduce((a, b) => a + b, 0);
    if (points - total <= 0) return null;
    return Object.assign({}, pending, { [stat]: (pending[stat] || 0) + 1 });
  }
  const allocBatches = (pending) => Object.entries(pending).filter(([, n]) => n > 0).map(([stat, n]) => ({ act: 'alloc', stat, n }));

  const Logic = { DIRS, firstStep, iconForLevel, effLevel, upClass, chaosRate, petXpFor, petLevel, tamePrice, allocAdd, allocBatches };
  if (typeof module !== 'undefined' && module.exports) module.exports = Logic;
  root.HLLogic = Logic;
})(typeof window !== 'undefined' ? window : globalThis);
