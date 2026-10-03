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
