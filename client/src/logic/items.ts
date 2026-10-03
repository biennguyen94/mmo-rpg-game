// Quy tắc client cho túi đồ (chỉ để chọn lệnh gửi / hiển thị; server vẫn kiểm mọi thứ).
import type { ItemTemplate, ItemView, Player } from "../net/protocol.js";

/** Slot trang bị theo KB_CONFIG §6. */
export const EQUIP_SLOT: Record<string, number> = {
  HELM: 0,
  ARMOR: 1,
  PANTS: 2,
  GLOVES: 3,
  BOOTS: 4,
  WEAPON: 5,
  SHIELD: 6,
  WING: 7,
  RING1: 8,
  RING2: 9,
};

export const SLOT_LABEL: Record<number, string> = {
  0: "HELM",
  1: "ARMOR",
  2: "PANTS",
  3: "GLOVES",
  4: "BOOTS",
  5: "WEAPON",
  6: "SHIELD",
  7: "WING",
  8: "RING1",
  9: "RING2",
};

/** Lưới 3×4 của §19.4 (null = ô trống không dùng). */
export const EQUIP_GRID: (number | null)[][] = [
  [null, 0, null],
  [5, 1, 6],
  [3, 2, 4],
  [8, 7, 9],
];

export type Templates = Map<string, ItemTemplate>;

/** Ô trang bị để mặc `template`; nhẫn: RING1 nếu trống, ngược lại RING2 (§19.4). */
export function equipSlotFor(t: ItemTemplate, equipment: ItemView[]): number | null {
  if (!t.slot) return null;
  if (t.slot === "RING1" || t.slot === "RING2") {
    return equipment.some((e) => e.slot === 8) ? 9 : 8;
  }
  return EQUIP_SLOT[t.slot] ?? null;
}

/** Ô túi trống đầu tiên (cho `unequip.toSlot`), null nếu đầy. */
export function firstFreeSlot(inventory: ItemView[], size: number): number | null {
  const used = new Set(inventory.map((i) => i.slot));
  for (let s = 0; s < size; s++) if (!used.has(s)) return s;
  return null;
}

/** Stack potion để dùng: stack đầu tiên (slot thấp nhất) đúng `potionType` (§19.6). */
export function pickPotion(inventory: ItemView[], templates: Templates, type: "HP" | "MP"): ItemView | null {
  const stacks = inventory
    .filter((i) => templates.get(i.templateId)?.potionType === type)
    .sort((a, b) => a.slot - b.slot);
  return stacks[0] ?? null;
}

/** Danh sách trang bị trong túi (§19.4: không gồm potion/tiêu hao), theo slot. */
export function equipmentInBag(inventory: ItemView[], templates: Templates): ItemView[] {
  return inventory.filter((i) => templates.get(i.templateId)?.slot).sort((a, b) => a.slot - b.slot);
}

/** `items.levelBonus` (P5-3, config join): chỉ số cộng mỗi cấp cường hóa theo `type` item. */
export type LevelBonus = Record<string, { attack?: number; defense?: number }>;

/** Ép được không (P5-M2): type có trong `levelBonus` (vũ khí, khiên, giáp). */
export const upgradable = (t: ItemTemplate | undefined, bonus: LevelBonus): boolean => !!t && !!bonus[t.type];

/**
 * Template ở cấp +N và option Jewel of Life `option` (mỗi cấp + `perOption` vào đòn với vũ khí,
 * thủ với giáp / khiên) để **hiển thị** (server tính thật, `Engine.leveled/3`).
 */
export function leveled(t: ItemTemplate, level = 0, bonus: LevelBonus = {}, option = 0, perOption = 0): ItemTemplate {
  const b = bonus[t.type];
  if (!b || (level <= 0 && option <= 0)) return t;
  const opt = option * perOption;
  const atk = (b.attack ?? 0) * level + (b.attack ? opt : 0);
  const def = (b.defense ?? 0) * level + (b.attack ? 0 : opt);
  return {
    ...t,
    ...(atk ? { attackMin: (t.attackMin ?? 0) + atk, attackMax: (t.attackMax ?? 0) + atk } : {}),
    ...(def ? { defense: (t.defense ?? 0) + def } : {}),
  };
}

/** Tên đồ kèm cấp cường hóa: "Short Sword +3". */
export function itemName(t: ItemTemplate | undefined, level = 0, fallback = "?"): string {
  const name = t?.name ?? fallback;
  return level > 0 ? `${name} +${level}` : name;
}

/** Mô tả ngắn dòng 2 của §19.4 (chỉ số đã cộng theo +N nếu có `bonus`). */
export function shortDesc(base: ItemTemplate, level = 0, bonus: LevelBonus = {}, option = 0, perOption = 0): string {
  const t = leveled(base, level, bonus, option, perOption);
  const parts: string[] = [];
  if (t.attackMax) parts.push(`Tấn công +${t.attackMin ?? 0}~${t.attackMax}`);
  if (t.defense) parts.push(`Phòng thủ +${t.defense}`);
  if (t.hpBonus) parts.push(`HP +${t.hpBonus}`);
  if (t.effect?.hp) parts.push(`Hồi ${t.effect.hp} HP`);
  if (t.effect?.mp) parts.push(`Hồi ${t.effect.mp} MP`);
  return parts.join(", ");
}

const REQ_LABEL: Record<string, string> = {
  level: "Cấp",
  strength: "STR",
  agility: "AGI",
  energy: "ENE",
  vitality: "VIT",
};

/** Yêu cầu của item và có đạt không (tooltip: không đạt hiện chữ đỏ, §19.5). */
export function requirements(t: ItemTemplate, p: Player): { label: string; value: number; ok: boolean }[] {
  const out: { label: string; value: number; ok: boolean }[] = [];
  for (const [k, v] of Object.entries(t.requirements ?? {})) {
    if (!v) continue;
    const have = (p as unknown as Record<string, number>)[k] ?? 0;
    out.push({ label: REQ_LABEL[k] ?? k, value: v, ok: have >= v });
  }
  if (t.classes && !t.classes.includes(p.class)) out.push({ label: `Class ${t.classes.join("/")}`, value: 0, ok: false });
  return out;
}

/** Kích thước lưới túi đồ Phase 2 (P2-8): 8×8 = 64 ô, mỗi item một ô. */
export const BAG_COLUMNS = 8;

/** Nơi bắt đầu / kết thúc một lần kéo thả trong panel Túi đồ. */
export type DragEnd =
  | { kind: "bag"; slot: number }
  | { kind: "equip"; slot: number }
  | { kind: "trash" }
  | { kind: "wh"; slot: number };

/** `wh` = ô kho tài khoản (P3-M3). */
export type DragStart = { kind: "bag"; item: ItemView } | { kind: "equip"; item: ItemView } | { kind: "wh"; item: ItemView };

/** Kho tài khoản (P3-M3): 15 cột × 8 hàng = `warehouse.slots` (120) ô. */
export const WAREHOUSE_COLUMNS = 15;

/**
 * Ô đích khi bấm [Gửi] / [Rút]: stack cùng loại còn chỗ (gộp) trước, không có thì ô trống thấp
 * nhất; `null` = đầy. Server vẫn kiểm.
 */
export function autoSlot(target: ItemView[], size: number, item: ItemView, templates: Templates): number | null {
  const t = templates.get(item.templateId);
  if (t?.stackable && t.maxStack) {
    const stack = target
      .filter((i) => i.templateId === item.templateId && i.quantity < t.maxStack!)
      .sort((x, y) => x.slot - y.slot)[0];
    if (stack) return stack.slot;
  }
  return firstFreeSlot(target, size);
}

/** Lệnh `cmd` (KB_TECHNICAL §5) cần gửi; `confirm` = phải hỏi người chơi trước (vứt đồ). */
export interface ItemCommand {
  act: "move_item" | "equip" | "unequip" | "drop" | "upgrade";
  payload: Record<string, unknown>;
  confirm?: boolean;
}

/** Ô trang bị nhận được `t` (nhẫn: 8 hoặc 9). */
export function equipSlotsOf(t: ItemTemplate): number[] {
  if (!t.slot) return [];
  if (t.slot === "RING1" || t.slot === "RING2") return [8, 9];
  const s = EQUIP_SLOT[t.slot];
  return s === undefined ? [] : [s];
}

/**
 * Kéo thả → lệnh gửi server, `null` = không làm gì (thả về chỗ cũ, ô không hợp).
 * Server vẫn kiểm lại mọi thứ (class, yêu cầu, slot, chủ sở hữu).
 */
export function dragCommand(
  from: DragStart,
  to: DragEnd,
  p: Pick<Player, "inventory">,
  templates: Templates,
  bonus: LevelBonus = {},
): ItemCommand | null {
  // kho (P3-M3): kho ↔ túi, sắp xếp trong kho — đều là move_item
  if (to.kind === "wh") {
    if (from.kind === "equip" || (from.kind === "wh" && from.item.slot === to.slot)) return null;
    return { act: "move_item", payload: { itemId: from.item.id, to: { location: "WAREHOUSE", slot: to.slot } } };
  }
  if (from.kind === "wh") {
    if (to.kind !== "bag") return null;
    return { act: "move_item", payload: { itemId: from.item.id, to: { location: "INVENTORY", slot: to.slot } } };
  }
  if (from.kind === "bag") {
    const it = from.item;
    if (to.kind === "bag") {
      if (to.slot === it.slot) return null;
      // jewel thả lên đồ ép được trong túi → ép (P5-M2)
      const target = p.inventory.find((i) => i.slot === to.slot);
      if (target && templates.get(it.templateId)?.type === "JEWEL" && upgradable(templates.get(target.templateId), bonus))
        return { act: "upgrade", payload: { itemId: target.id, jewelId: it.id } };
      return { act: "move_item", payload: { itemId: it.id, to: { location: "INVENTORY", slot: to.slot } } };
    }
    if (to.kind === "equip") {
      const t = templates.get(it.templateId);
      if (!t || !equipSlotsOf(t).includes(to.slot)) return null;
      return { act: "equip", payload: { itemId: it.id, slot: to.slot } };
    }
    return { act: "drop", payload: { itemId: it.id }, confirm: true };
  }
  // từ ô trang bị: chỉ tháo về ô túi (trống: đúng ô đó; có đồ: ô trống thấp nhất)
  if (to.kind !== "bag") return null;
  const occupied = p.inventory.some((i) => i.slot === to.slot);
  const toSlot = occupied ? firstFreeSlot(p.inventory, BAG_COLUMNS * BAG_COLUMNS) : to.slot;
  if (toSlot === null) return null;
  return { act: "unequip", payload: { slot: from.item.slot, toSlot } };
}

/** Số mặc định khi tách stack: một nửa (làm tròn xuống), tối thiểu 1. */
export function defaultSplit(quantity: number): number {
  return Math.max(1, Math.floor(quantity / 2));
}

/**
 * Luật vũ khí hai tay (P2-5): mặc `t` vào `slot` có vướng không — cung khi đang có khiên, hoặc
 * khiên khi đang cầm cung. Chỉ để báo sớm cho người chơi; server vẫn kiểm (`INVALID_SLOT`).
 */
export function twoHandConflict(
  t: ItemTemplate,
  slot: number,
  equipment: ItemView[],
  templates: Templates,
  twoHanded: string[],
): boolean {
  const isTwo = (x: ItemTemplate | undefined) => !!x?.weaponType && twoHanded.includes(x.weaponType);
  const at = (s: number) => equipment.find((e) => e.slot === s);
  if (slot === EQUIP_SLOT.WEAPON && isTwo(t)) return at(EQUIP_SLOT.SHIELD) !== undefined;
  if (slot === EQUIP_SLOT.SHIELD) {
    const w = at(EQUIP_SLOT.WEAPON);
    return w !== undefined && isTwo(templates.get(w.templateId));
  }
  return false;
}

/** Dòng thông báo khi giao dịch đóng (P5-M4). */
export function tradeResultText(result: string | undefined, partner: string, by?: string | null): string {
  switch (result) {
    case "done":
      return `Giao dịch với ${partner} thành công.`;
    case "declined":
      return `${partner} từ chối giao dịch.`;
    case "timeout":
      return `Giao dịch với ${partner} đã hết thời gian.`;
    case "far":
      return `Giao dịch với ${partner} bị hủy: hai bên ở quá xa.`;
    case "disconnect":
      return `Giao dịch với ${partner} bị hủy: ${by ?? partner} mất kết nối.`;
    case "map":
      return `Giao dịch với ${partner} bị hủy: đổi bản đồ.`;
    case "dead":
      return `Giao dịch với ${partner} bị hủy: có người tử trận.`;
    default:
      return `Giao dịch với ${partner} đã bị hủy${by ? ` (${by})` : ""}.`;
  }
}
