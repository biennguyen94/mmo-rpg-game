// Nút [+] cộng điểm: debounce 200 ms, gộp nhiều lần bấm cùng stat thành MỘT `alloc` (§19.3).

export type Stat = "strength" | "agility" | "vitality" | "energy";

export interface Timer {
  set(fn: () => void, ms: number): unknown;
  clear(handle: unknown): void;
}

export const realTimer: Timer = {
  set: (fn, ms) => setTimeout(fn, ms),
  clear: (h) => clearTimeout(h as ReturnType<typeof setTimeout>),
};

export class AllocBatcher {
  private pending = new Map<Stat, { points: number; handle: unknown }>();

  constructor(
    private readonly send: (stat: Stat, points: number) => void,
    private readonly timer: Timer = realTimer,
    private readonly delayMs = 200,
  ) {}

  /** Bấm [+] một lần. Không cho bấm vượt `free` điểm (server vẫn kiểm). */
  click(stat: Stat, free: number): boolean {
    const total = [...this.pending.values()].reduce((a, p) => a + p.points, 0);
    if (total >= free) return false;
    const cur = this.pending.get(stat);
    if (cur) this.timer.clear(cur.handle);
    const points = (cur?.points ?? 0) + 1;
    const handle = this.timer.set(() => this.flush(stat), this.delayMs);
    this.pending.set(stat, { points, handle });
    return true;
  }

  /** Số điểm đang chờ gửi cho `stat` (hiển thị "+n" tạm, không đổi số thật). */
  pendingFor(stat: Stat): number {
    return this.pending.get(stat)?.points ?? 0;
  }

  private flush(stat: Stat): void {
    const cur = this.pending.get(stat);
    if (!cur) return;
    this.pending.delete(stat);
    this.send(stat, cur.points);
  }
}
