// Nội suy vị trí entity (KB_TECH_STACK §6): vẽ tại `now - interpolationDelayMs` theo đồng hồ
// server, giữa hai snapshot gần nhất. Chưa đủ mẫu thì đứng ở mẫu cuối (không ngoại suy).

export interface Sample {
  t: number;
  x: number;
  y: number;
}

export class InterpBuffer {
  private samples: Sample[] = [];
  constructor(private readonly max = 20) {}

  push(t: number, x: number, y: number): void {
    const last = this.samples[this.samples.length - 1];
    if (last && t < last.t) return; // gói đến trễ, bỏ
    if (last && t === last.t) this.samples[this.samples.length - 1] = { t, x, y };
    else this.samples.push({ t, x, y });
    if (this.samples.length > this.max) this.samples.shift();
  }

  /** Đặt lại (teleport: hồi sinh, spawn lại) — không trượt từ chỗ cũ. */
  reset(t: number, x: number, y: number): void {
    this.samples = [{ t, x, y }];
  }

  at(time: number): { x: number; y: number } | null {
    const s = this.samples;
    if (s.length === 0) return null;
    if (time <= s[0].t) return { x: s[0].x, y: s[0].y };
    for (let i = s.length - 1; i > 0; i--) {
      const a = s[i - 1];
      const b = s[i];
      if (time >= a.t && time <= b.t) {
        const k = b.t === a.t ? 1 : (time - a.t) / (b.t - a.t);
        return { x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k };
      }
    }
    const last = s[s.length - 1];
    return { x: last.x, y: last.y };
  }
}

/**
 * Ước lượng chênh lệch đồng hồ server − client từ `snapshot.t`: lấy mức nhỏ nhất quan sát
 * được (gói đến sớm nhất ≈ trễ mạng nhỏ nhất), trượt chậm lên khi mạng ổn định trở lại.
 */
export class ServerClock {
  private offset: number | null = null;

  observe(serverT: number, clientNow: number): void {
    const o = serverT - clientNow;
    if (this.offset === null || o > this.offset) this.offset = o;
    else this.offset = this.offset * 0.99 + o * 0.01;
  }

  now(clientNow: number): number {
    return clientNow + (this.offset ?? 0);
  }
}

/**
 * Trượt đều về vị trí server mới nhất (DEC-186, ý từ cách vẽ của repo nền Hắc Long): hình chạy
 * với **tốc độ không đổi** (ô / giây, đo từ nhịp đổi ô của chính entity đó; mặc định
 * `defaultTps`) thẳng về vị trí mới nhất server gửi. Đi liên tục thì hình luôn đang chạy — không có
 * nhịp "đứng chờ gói rồi trượt bù" như nội suy giữa hai snapshot. Tụt lại hơn một ô (mạng giật) thì
 * chạy nhanh hơn cho kịp. Server vẫn quyết định vị trí; nhảy xa (hồi sinh, cổng) thì đặt thẳng.
 * Cùng giao diện với `InterpBuffer`.
 */
export class Glide {
  private x = 0;
  private y = 0;
  private tx = 0;
  private ty = 0;
  private tps: number;
  private lastChange = -Infinity;
  private lastTime: number | null = null;
  private started = false;

  constructor(
    defaultTps = 5,
    private readonly snapTiles = 3,
  ) {
    this.tps = defaultTps;
  }

  push(t: number, x: number, y: number): void {
    if (this.started && x === this.tx && y === this.ty) return;
    const d = Math.hypot(x - this.tx, y - this.ty);
    if (!this.started || Math.max(Math.abs(x - this.tx), Math.abs(y - this.ty)) > this.snapTiles) return this.reset(t, x, y);
    const gap = t - this.lastChange;
    // tốc độ thật của entity (ô Euclid / giây) từ nhịp đổi ô liên tiếp; đứng lâu thì giữ số cũ
    if (gap > 0 && gap < 1000) this.tps = this.tps * 0.6 + Math.min(Math.max((d * 1000) / gap, 1), 15) * 0.4;
    this.lastChange = t;
    this.tx = x;
    this.ty = y;
  }

  reset(t: number, x: number, y: number): void {
    this.x = this.tx = x;
    this.y = this.ty = y;
    this.lastChange = t;
    this.lastTime = null;
    this.started = true;
  }

  at(time: number): { x: number; y: number } | null {
    if (!this.started) return null;
    const dt = this.lastTime === null ? 0 : Math.max(0, Math.min(time - this.lastTime, 250));
    this.lastTime = time;
    const dx = this.tx - this.x;
    const dy = this.ty - this.y;
    const dist = Math.hypot(dx, dy);
    if (dist > 0) {
      // tụt hơn một ô: đuổi nhanh theo khoảng cách
      const step = (this.tps * Math.max(1, dist) * dt) / 1000;
      if (step >= dist) {
        this.x = this.tx;
        this.y = this.ty;
      } else {
        this.x += (dx / dist) * step;
        this.y += (dy / dist) * step;
      }
    }
    return { x: this.x, y: this.y };
  }
}
