// Panel Thông báo (§19.11): tối đa 50, cũ nhất tự xóa, có "chưa đọc". Loại: LEVEL_UP,
// ITEM_DROP, ITEM_PICKUP, EXP_GAIN, ERROR, SYSTEM. Client tự suy ra từ chênh lệch `player`
// (P4/M3-3), không có event riêng.
import type { Player } from "../net/protocol.js";
import type { Templates } from "./items.js";

export type NoticeType = "LEVEL_UP" | "ITEM_DROP" | "ITEM_PICKUP" | "EXP_GAIN" | "ERROR" | "SYSTEM";

export interface Notice {
  id: number;
  type: NoticeType;
  text: string;
  sub?: string;
  at: number;
  read: boolean;
}

export const NOTICE_ICON: Record<NoticeType, string> = {
  LEVEL_UP: "⚡",
  ITEM_DROP: "🎁",
  ITEM_PICKUP: "🎁",
  EXP_GAIN: "✨",
  ERROR: "⚠️",
  SYSTEM: "ℹ️",
};

export class NoticeLog {
  private items: Notice[] = [];
  private seq = 0;
  constructor(private readonly max = 50) {}

  add(type: NoticeType, text: string, sub?: string, at = Date.now()): Notice {
    const n: Notice = { id: ++this.seq, type, text, sub, at, read: false };
    this.items.unshift(n);
    if (this.items.length > this.max) this.items.length = this.max;
    return n;
  }

  list(onlyUnread = false): Notice[] {
    return onlyUnread ? this.items.filter((n) => !n.read) : [...this.items];
  }

  unread(): number {
    return this.items.filter((n) => !n.read).length;
  }

  markAllRead(): void {
    for (const n of this.items) n.read = true;
  }

  clear(): void {
    this.items = [];
  }
}

/** Thông báo suy ra từ hai trạng thái `player` liên tiếp. */
export function diffPlayer(prev: Player, next: Player, templates: Templates): { type: NoticeType; text: string; sub?: string }[] {
  const out: { type: NoticeType; text: string; sub?: string }[] = [];
  if (next.level > prev.level) {
    out.push({ type: "LEVEL_UP", text: "Level up!", sub: `Level ${prev.level} → ${next.level}` });
  } else if (next.experience > prev.experience) {
    out.push({ type: "EXP_GAIN", text: `+${next.experience - prev.experience} EXP` });
  }
  if (next.zen > prev.zen && next.inventory.length === prev.inventory.length) {
    // Zen từ quái (bán đồ thì túi đổi, đã có thông báo riêng của panel Shop)
    out.push({ type: "SYSTEM", text: `+${next.zen - prev.zen} Zen` });
  }
  // P4-M1: điểm PK đổi
  const pk0 = prev.view?.pkPoints ?? 0;
  const pk1 = next.view?.pkPoints ?? 0;
  if (pk1 > pk0) {
    out.push({ type: "ERROR", text: `Bạn đã giết người chơi — điểm PK ${pk1}`, sub: next.view?.pkState === "MURDERER" ? "Sát nhân: không dùng được NPC, dễ rơi đồ khi chết" : "Cảnh báo" });
  } else if (pk1 < pk0) {
    out.push({ type: "SYSTEM", text: `Điểm PK giảm còn ${pk1}` });
  }
  const before = new Map(prev.inventory.map((i) => [i.id, i.quantity]));
  for (const it of next.inventory) {
    const old = before.get(it.id) ?? 0;
    if (it.quantity > old && next.zen >= prev.zen) {
      const name = templates.get(it.templateId)?.name ?? it.templateId;
      const n = it.quantity - old;
      out.push({ type: "ITEM_PICKUP", text: `Nhận: ${name}${n > 1 ? ` ×${n}` : ""}` });
    }
  }
  return out;
}
