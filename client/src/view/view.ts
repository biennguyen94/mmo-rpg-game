// Ranh giới giữa logic game và phần vẽ. Phần vẽ (Phaser 3) chỉ đọc World/MapData và báo lại
// thao tác của người chơi; không gửi `cmd`, không tính luật.
import type { CombatPayload, MapData } from "../net/protocol.js";
import type { Entity, World } from "../state/world.js";

export interface ViewCallbacks {
  /** Click/tap ô đất trống (tọa độ ô) — click-to-move. */
  onGround(x: number, y: number): void;
  /** Click/tap entity (quái, NPC, đồ dưới đất, người chơi khác) tại vị trí màn hình. */
  onEntity(e: Entity, screenX: number, screenY: number): void;
}

export interface GameView {
  /** Thời điểm vẽ (ms, đồng hồ server) cho nội suy; view gọi mỗi frame. */
  setClock(now: () => number): void;
  setSelf(entityId: string): void;
  /** Hiệu ứng đòn đánh (số sát thương bay lên, "Trượt"). */
  combat(ev: CombatPayload): void;
  /** Điểm đánh dấu chỗ click-to-move. */
  marker(x: number, y: number): void;
  destroy(): void;
}

export type ViewFactory = (container: HTMLElement, map: MapData, world: World, cb: ViewCallbacks) => GameView;
