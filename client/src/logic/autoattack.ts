// Hành vi tấn công (§19.9): chọn "Tấn công thường" hoặc một skill → tự đánh liên tục theo nhịp
// cooldown tới khi quái chết / người chơi click-to-move / mất mục tiêu. Ngoài tầm → move_to
// tiến lại gần (đi thẳng). P2-M3: skill đã chọn được LẶP LẠI (DW đánh bằng Energy Ball);
// NO_MANA → bỏ skill, đánh thường.
import { chebyshev } from "../net/protocol.js";

export type Action =
  | { act: "attack"; target: string }
  | { act: "skill"; id: string; target: string }
  | { act: "move_to"; x: number; y: number };

export interface Pos {
  x: number;
  y: number;
}

export interface TargetInfo extends Pos {
  alive: boolean;
}

export class AutoAttack {
  target: string | null = null;
  /** Skill dùng mỗi lượt (null = đánh thường). */
  pendingSkill: string | null = null;
  private nextAt = 0;
  private lastMove: string | null = null;

  start(target: string, skill: string | null = null): void {
    this.target = target;
    this.pendingSkill = skill;
    this.nextAt = 0;
    this.lastMove = null;
  }

  stop(): void {
    this.target = null;
    this.pendingSkill = null;
  }

  /** Server báo NO_MANA cho skill: bỏ skill, đánh thường. */
  skillFailed(): void {
    this.pendingSkill = null;
  }

  /** Server báo COOLDOWN: thử lại sau một chút. */
  retryAfter(now: number, ms: number): void {
    this.nextAt = now + ms;
  }

  /**
   * Gọi đều (vd. mỗi frame): trả hành động cần gửi lúc này (hoặc null).
   * `range`: tầm của skill sắp dùng; `cooldownMs`: từ `view` (server tính).
   */
  tick(now: number, me: Pos, target: TargetInfo | null, range: number, cooldownMs: number): Action | null {
    if (!this.target) return null;
    if (!target || !target.alive) {
      this.stop();
      return null;
    }
    if (chebyshev(me.x, me.y, target.x, target.y) > range) {
      const step = approach(me, target);
      const key = `${step.x},${step.y}`;
      if (key === this.lastMove) return null; // đã gửi, đang đi
      this.lastMove = key;
      return { act: "move_to", ...step };
    }
    this.lastMove = null;
    if (now < this.nextAt) return null;
    this.nextAt = now + cooldownMs;
    if (this.pendingSkill) return { act: "skill", id: this.pendingSkill, target: this.target };
    return { act: "attack", target: this.target };
  }
}

/** Ô kề mục tiêu, phía người chơi (đi thẳng tới, chưa cần pathfinding phía client). */
export function approach(me: Pos, t: Pos): Pos {
  return { x: t.x + Math.sign(me.x - t.x), y: t.y + Math.sign(me.y - t.y) };
}
