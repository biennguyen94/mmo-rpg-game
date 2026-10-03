// Kiểu dữ liệu protocol (KB_TECHNICAL §5 + các bổ sung đã ghi ở docs/OPEN_QUESTIONS.md).
// Client chỉ gửi ý định (`cmd`); mọi số hiển thị lấy từ server.

export type ErrorCode =
  | "INVALID_TARGET"
  | "OUT_OF_RANGE"
  | "COOLDOWN"
  | "NO_MANA"
  | "INVENTORY_FULL"
  | "REQUIREMENT_NOT_MET"
  | "NOT_OWNER"
  | "INVALID_SLOT"
  | "NOT_ENOUGH_ZEN"
  | "RATE_LIMITED"
  | "FORBIDDEN";

export interface ItemView {
  id: string;
  serial: string;
  templateId: string;
  quantity: number;
  slot: number;
  level: number;
  durability: number | null;
  luck: boolean;
  skill: boolean;
  excellentOptions: unknown[];
}

export interface PlayerView {
  hpMax: number;
  mpMax: number;
  attackMin: number;
  attackMax: number;
  defense: number;
  attackRate: number;
  defenseRate: number;
  attackSpeed: number;
  cooldownMs: number;
  /** Tầm đánh thường (ô) theo vũ khí đang cầm. */
  attackRange: number;
  expRequired: number | null;
  maxLevel: number;
  skills: string[];
  potions: { HP: number; MP: number };
  inventoryUsed: number;
  inventorySize: number;
}

export interface Player {
  id: string;
  name: string;
  class: string;
  level: number;
  experience: number;
  strength: number;
  agility: number;
  vitality: number;
  energy: number;
  freeStatPoints: number;
  hp: number;
  mp: number;
  zen: number;
  mapId: string;
  x: number;
  y: number;
  view: PlayerView;
  inventory: ItemView[];
  equipment: ItemView[];
}

export type EntityKind = "player" | "monster" | "npc" | "item";

export interface SpawnPayload {
  id: string;
  kind: EntityKind;
  x: number;
  y: number;
  hp: number | null;
  maxHp: number | null;
  state: string;
  name: string;
  level: number | null;
  templateId?: string;
  /** Người chơi: class (DK/DW/ELF) để chọn sprite. */
  class?: string;
}

export interface SnapshotEntity {
  id: string;
  x: number;
  y: number;
  hp: number;
  state: string;
}

export interface SnapshotPayload {
  t: number;
  entities: SnapshotEntity[];
  removed: string[];
}

export interface CombatPayload {
  rid: string | null;
  attacker: string;
  target: string;
  dmg: number;
  crit: boolean;
  hp: number;
}

export interface ShopPayload {
  npcId: string;
  name: string;
  items: { templateId: string; price: number }[];
}

export interface ErrorPayload {
  rid: string | null;
  error: ErrorCode;
}

export interface ItemTemplate {
  templateId: string;
  name: string;
  type: string;
  slot: string | null;
  weaponType?: string;
  stackable: boolean;
  maxStack?: number;
  potionType?: "HP" | "MP";
  effect?: { hp: number; mp: number };
  attackMin?: number;
  attackMax?: number;
  defense?: number;
  speed?: number;
  hpBonus?: number;
  classes?: string[];
  requirements?: Record<string, number>;
  iconRef: { group: number; index: number } | { custom: string };
  buyPrice: number;
  sellPrice: number;
}

export interface SkillInfo {
  id: string;
  name: string;
  range: number;
  manaCost: number;
  requiredLevel: number;
}

export interface MapData {
  id: string;
  name: string;
  width: number;
  height: number;
  tiles: string[];
  legend: Record<string, string>;
  safeZones: { id: string; x: number; y: number; w: number; h: number }[];
  npcs: { id: string; x: number; y: number }[];
}

export interface JoinReply {
  player: Player;
  entityId: string;
  map: MapData;
  config: {
    clientVersion: string;
    interpolationDelayMs: number;
    maxLevel: number;
    pickupRange: number;
    npcRange: number;
    twoHandedWeaponTypes: string[];
  };
  data: { items: ItemTemplate[]; skills: SkillInfo[] };
}

/** Thông báo tiếng Việt cho mã lỗi (§19.8: hiện trong panel Thông báo). */
export const ERROR_TEXT: Record<ErrorCode, string> = {
  INVALID_TARGET: "Mục tiêu không hợp lệ",
  OUT_OF_RANGE: "Ở quá xa",
  COOLDOWN: "Chưa hồi chiêu",
  NO_MANA: "Không đủ mana",
  INVENTORY_FULL: "Túi đồ đã đầy",
  REQUIREMENT_NOT_MET: "Không đủ yêu cầu",
  NOT_OWNER: "Không phải đồ của bạn",
  INVALID_SLOT: "Ô không hợp lệ",
  NOT_ENOUGH_ZEN: "Không đủ Zen",
  RATE_LIMITED: "Thao tác quá nhanh",
  FORBIDDEN: "Không thực hiện được",
};

/** Sinh `rid` duy nhất cho mỗi `cmd` (KB_TECHNICAL §5). */
export class RidGen {
  private n = 0;
  constructor(private readonly prefix: string = Math.random().toString(36).slice(2, 8)) {}
  next(): string {
    this.n += 1;
    return `${this.prefix}-${this.n}`;
  }
}

/** Khoảng cách Chebyshev (G4), dùng cho tầm đánh/nhặt/NPC phía client (server vẫn kiểm). */
export function chebyshev(ax: number, ay: number, bx: number, by: number): number {
  return Math.max(Math.abs(ax - bx), Math.abs(ay - by));
}
