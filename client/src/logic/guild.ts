// Guild (P4-M3, P4-5): quyền từng vai trò để biết hiện nút nào. Chỉ là gợi ý giao diện — server
// (`Mu.Guild`) vẫn kiểm mọi thao tác.
import type { GuildMember, GuildPayload } from "../net/protocol.js";

export type GuildRole = GuildMember["role"];

export const ROLE_LABEL: Record<GuildRole, string> = { master: "Chủ guild", assistant: "Phó guild", member: "Thành viên" };

/** Vai trò của `me` trong guild (null = không có guild / không thấy mình). */
export function myRole(g: GuildPayload | null, me: string): GuildRole | null {
  return g?.members.find((m) => m.name === me)?.role ?? null;
}

/** Master + assistant mời được. */
export const canInvite = (role: GuildRole | null): boolean => role === "master" || role === "assistant";

/** Master đuổi mọi người (trừ mình), assistant đuổi member. */
export function canKick(role: GuildRole | null, target: GuildRole): boolean {
  return (role === "master" && target !== "master") || (role === "assistant" && target === "member");
}

/** Chỉ master phong (member → assistant, còn chỗ) / hạ (assistant → member). */
export function canPromote(role: GuildRole | null, target: GuildRole, g: GuildPayload, maxAssistants: number): boolean {
  return role === "master" && target === "member" && g.members.filter((m) => m.role === "assistant").length < maxAssistants;
}

export const canDemote = (role: GuildRole | null, target: GuildRole): boolean => role === "master" && target === "assistant";

/** Tên guild hợp lệ theo `guild.namePattern` (server gửi trong config). */
export function validGuildName(name: string, pattern: string): boolean {
  try {
    return new RegExp(pattern).test(name.trim());
  } catch {
    return name.trim().length > 0;
  }
}
