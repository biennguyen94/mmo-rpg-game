// Bản sao entity phía client: spawn (thêm-hoặc-cập-nhật, DEC-25), despawn, snapshot delta.
import type { SnapshotPayload, SpawnPayload } from "../net/protocol.js";
import { InterpBuffer } from "./interp.js";

export interface Entity extends SpawnPayload {
  interp: InterpBuffer;
  /** Người chơi: MP từ snapshot (P2-M3). */
  mp?: number;
}

export class World {
  readonly entities = new Map<string, Entity>();

  spawn(p: SpawnPayload, t: number): Entity {
    const old = this.entities.get(p.id);
    const interp = old?.interp ?? new InterpBuffer();
    interp.reset(t, p.x, p.y);
    const e: Entity = { ...(old ?? {}), ...p, interp };
    this.entities.set(p.id, e);
    return e;
  }

  despawn(id: string): void {
    this.entities.delete(id);
  }

  snapshot(s: SnapshotPayload): void {
    for (const u of s.entities) {
      const e = this.entities.get(u.id);
      if (!e) continue; // chưa nhận spawn: bỏ qua, spawn sẽ tới
      e.x = u.x;
      e.y = u.y;
      e.hp = u.hp;
      if (u.mp !== undefined) e.mp = u.mp;
      e.state = u.state;
      e.interp.push(s.t, u.x, u.y);
    }
    for (const id of s.removed) this.entities.delete(id);
  }

  setHp(id: string, hp: number): void {
    const e = this.entities.get(id);
    if (e) e.hp = hp;
  }

  ofKind(kind: string): Entity[] {
    return [...this.entities.values()].filter((e) => e.kind === kind);
  }
}
