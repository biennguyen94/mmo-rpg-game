// PvP phía client (P4-M1): chỉ để hiện nút / màu / hỏi xác nhận — server quyết định mọi thứ
// (`Mu.Game.Pvp`: cấp tối thiểu, safe zone, tự vệ, PK).
import type { MapData } from "../net/protocol.js";

export type PkState = "NORMAL" | "WARNING" | "MURDERER";

/** Tên trạng thái PK hiển thị. */
export const PK_LABEL: Record<PkState, string> = { NORMAL: "Bình thường", WARNING: "Cảnh báo", MURDERER: "Sát nhân" };

/** Màu tên: WARNING cam, MURDERER đỏ; kẻ gây sự nhấp nháy cam (`blink` đổi theo thời gian). */
export function nameColor(pk: PkState | undefined, aggressor: boolean | undefined, blink: boolean): string {
  if (pk === "MURDERER") return "#ff4d4d";
  if (pk === "WARNING") return "#ffa53a";
  if (aggressor && blink) return "#ffa53a";
  return "#fff";
}

export function inSafeZone(map: Pick<MapData, "safeZones">, x: number, y: number): boolean {
  return map.safeZones.some((z) => x >= z.x && x < z.x + z.w && y >= z.y && y < z.y + z.h);
}

/** Hiện nút [⚔ Tấn công] không: PvP bật, cả hai đủ cấp, không ai đứng trong safe zone. */
export function canShowAttack(
  me: { level: number; x: number; y: number },
  target: { level: number | null; x: number; y: number },
  map: Pick<MapData, "safeZones">,
  pvp: { enabled: boolean; minLevel: number },
): boolean {
  return (
    pvp.enabled &&
    me.level >= pvp.minLevel &&
    (target.level ?? 0) >= pvp.minLevel &&
    !inSafeZone(map, me.x, me.y) &&
    !inSafeZone(map, target.x, target.y)
  );
}

/** Hỏi xác nhận trước khi đánh: người NORMAL không phải kẻ gây sự (giết sẽ bị tính PK). */
export function needsConfirm(target: { pkState?: PkState; aggressor?: boolean }): boolean {
  return (target.pkState ?? "NORMAL") === "NORMAL" && !target.aggressor;
}
