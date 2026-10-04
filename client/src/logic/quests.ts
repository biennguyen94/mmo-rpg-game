// Quest (P6-M2, P6-2): chữ hiển thị tiến độ / thưởng. Server tính mọi thứ (tiến độ, đủ chưa,
// thưởng); client chỉ trình bày.
import type { QuestActive, QuestGoal, QuestRewards } from "../net/protocol.js";

/** "Hạ Spider 7/10", "Nộp Ring 0/1", "Đạt cấp 10 (8/10)"; `have` bỏ trống = chỉ yêu cầu. */
export function goalText(g: QuestGoal, have?: number): string {
  const n = have === undefined ? `${g.need}` : `${have}/${g.need}`;
  if (g.type === "kill") return `Hạ ${g.name ?? g.target} ${n}`;
  if (g.type === "collect") return `Nộp ${g.name ?? g.target} ${n}`;
  return have === undefined ? `Đạt cấp ${g.need}` : `Đạt cấp ${g.need} (${have}/${g.need})`;
}

/** "+300 EXP · +1.500 Zen · HP Potion ×5" (`itemName` tra tên template). */
export function rewardText(r: QuestRewards, itemName: (templateId: string) => string): string {
  const parts: string[] = [];
  if (r.exp > 0) parts.push(`+${r.exp.toLocaleString("vi-VN")} EXP`);
  if (r.zen > 0) parts.push(`+${r.zen.toLocaleString("vi-VN")} Zen`);
  for (const it of r.items) parts.push(`${itemName(it.templateId)} ×${it.quantity}`);
  return parts.join(" · ");
}

/** Một dòng theo dõi: "Diệt Nhện: Hạ Spider 7/10" (nhiều mục tiêu cách bằng ", "); xong thì ✔. */
export function trackerLine(q: QuestActive): string {
  if (q.complete) return `✔ ${q.name}: về Quest Master trả nhiệm vụ`;
  return `${q.name}: ${q.objectives.map((o) => goalText(o, o.have)).join(", ")}`;
}
