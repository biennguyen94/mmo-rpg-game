// Ranh giới giữa logic game và phần vẽ. Phần vẽ (Phase 1: CanvasView; phase sau: PhaserView —
// docs/BACKLOG.md) chỉ đọc World/MapData và báo lại
// thao tác của người chơi; không gửi `cmd`, không tính luật.
import type { CombatPayload, MapData } from "../net/protocol.js";
import type { Entity, World } from "../state/world.js";

export interface ViewCallbacks {
  /** Click/tap ô đất trống (tọa độ ô) — click-to-move. */
  onGround(x: number, y: number): void;
  /** Click/tap entity (quái, NPC, đồ dưới đất, người chơi khác) tại vị trí màn hình. */
  /** `tileX/tileY`: ô vừa bấm (để "Đi tới đây" đi đúng ô đó, P3-M6). */
  onEntity(e: Entity, screenX: number, screenY: number, tileX: number, tileY: number): void;
}

export interface GameView {
  /** Thời điểm vẽ (ms, đồng hồ server) cho nội suy; view gọi mỗi frame. */
  setClock(now: () => number): void;
  setSelf(entityId: string): void;
  /** Guild đang war với mình (P4-M4): tên thành viên guild này vẽ màu tím. */
  setEnemyGuild(name: string | null): void;
  /** Hiệu ứng đòn đánh (số sát thương bay lên, "Trượt"). */
  combat(ev: CombatPayload): void;
  /** Điểm đánh dấu chỗ click-to-move. */
  marker(x: number, y: number): void;
  destroy(): void;
}

export type ViewFactory = (container: HTMLElement, map: MapData, world: World, cb: ViewCallbacks) => GameView;
