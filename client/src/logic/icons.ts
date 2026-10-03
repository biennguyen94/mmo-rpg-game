// Tra icon item qua icon_map.json (KB_ITEM_REFERENCE §4): không dò file lúc runtime.
// Khóa: "group/index" hoặc "custom/{templateId}"; trong đó "{bucket}" hoặc "{bucket}e".
import type { ItemTemplate } from "../net/protocol.js";

export type IconMap = Record<string, Record<string, string> | string>;

const BUCKETS = [0, 3, 5, 7, 9, 11, 13, 15];

export function bucket(level: number): number {
  const l = Math.min(level, 15);
  return Math.max(...BUCKETS.filter((b) => b <= l));
}

/** Đường dẫn tương đối so với /assets/icons/ (luôn có: thiếu thì placeholder). */
export function iconPath(map: IconMap | null, t: ItemTemplate | undefined, level = 0, excellent = false): string {
  const placeholder = (map?._placeholder as string | undefined) ?? "placeholder.png";
  if (!map || !t) return placeholder;
  const ref = t.iconRef as { group?: number; index?: number; custom?: string };
  const key = ref.custom ? `custom/${ref.custom}` : `${ref.group}/${ref.index}`;
  const entry = map[key];
  if (!entry || typeof entry === "string") return placeholder;
  const b = bucket(level);
  const order: string[] = [];
  if (excellent) order.push(`${b}e`);
  order.push(`${b}`);
  for (const lb of BUCKETS.filter((x) => x < b).reverse()) {
    if (excellent) order.push(`${lb}e`);
    order.push(`${lb}`);
  }
  for (const k of order) if (entry[k]) return entry[k];
  return placeholder;
}
