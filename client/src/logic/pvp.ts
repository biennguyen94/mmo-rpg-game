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

/**
 * Hiện nút [⚔ Tấn công] không: PvP bật, cả hai đủ cấp, không ai đứng trong safe zone; đang duel
 * thì chỉ đánh đối thủ, không duel thì không đánh người đang duel; không đánh người cùng nhóm.
 */
export function canAttackPlayer(
  me: { level: number; x: number; y: number },
  target: { id: string; name: string; level: number | null; x: number; y: number; dueling?: boolean },
  map: Pick<MapData, "safeZones">,
  pvp: { enabled: boolean; minLevel: number },
  ctx: { duelOpponentId: string | null; partyNames: string[] },
): boolean {
  if (ctx.partyNames.includes(target.name)) return false;
  if (ctx.duelOpponentId !== null && target.id !== ctx.duelOpponentId) return false;
  // người đang duel với người khác: "vùng riêng" (P4-4)
  if (ctx.duelOpponentId === null && target.dueling) return false;
  return canShowAttack(me, target, map, pvp);
}

/** Hiện nút [⚔ Thách đấu] không: PvP bật, cả hai đủ cấp, mình chưa duel. */
export function canChallenge(me: { level: number }, target: { level: number | null; dueling?: boolean }, pvp: { enabled: boolean; minLevel: number }, inDuel: boolean): boolean {
  return pvp.enabled && !inDuel && !target.dueling && me.level >= pvp.minLevel && (target.level ?? 0) >= pvp.minLevel;
}

/** Dòng thông báo khi duel kết thúc. */
export function duelResultText(result: string | undefined, opponent: string | null): string {
  const o = opponent ?? "?";
  switch (result) {
    case "win":
      return `Bạn thắng ${o} trong trận đấu tay đôi.`;
    case "lose":
      return `Bạn thua ${o} trong trận đấu tay đôi.`;
    case "draw":
      return `Hòa với ${o}: hết giờ đấu tay đôi.`;
    case "declined":
      return `${o} từ chối đấu tay đôi.`;
    default:
      return `${o} đã hủy lời mời đấu tay đôi.`;
  }
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
