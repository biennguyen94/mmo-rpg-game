// Chat (P2-M5, KB_GAME_DESIGN §16): đọc dòng người chơi gõ thành lệnh `chat` (§5) và định dạng
// tin nhận được. Hiển thị bằng text node (không HTML) nên không cần escape.
import type { ChatPayload } from "../net/protocol.js";

export interface ChatCommand {
  channel: "NORMAL" | "WHISPER" | "PARTY" | "GUILD";
  text: string;
  to?: string;
}

/** Số tin giữ trong khung chat. */
export const CHAT_KEEP = 50;

/**
 * Dòng gõ → lệnh: `/w Tên nội dung` (hoặc `/m`) = nhắn riêng, `/p nội dung` = nhóm (P3-M4), `/g nội dung` = guild (P4-M3), còn lại = NORMAL.
 * `null` nếu trống / thiếu tên hoặc nội dung. Server vẫn làm sạch, cắt độ dài, lọc từ cấm.
 */
export function parseChat(line: string): ChatCommand | null {
  const s = line.trim();
  if (!s) return null;
  const m = /^\/(?:w|m)\s+(\S+)\s+(.+)$/i.exec(s);
  if (m) return { channel: "WHISPER", to: m[1], text: m[2].trim() };
  if (/^\/(?:w|m)\b/i.test(s)) return null;
  const p = /^\/p\s+(.+)$/i.exec(s);
  if (p) return { channel: "PARTY", text: p[1].trim() };
  if (/^\/p\b/i.test(s)) return null;
  const g = /^\/g\s+(.+)$/i.exec(s);
  if (g) return { channel: "GUILD", text: g[1].trim() };
  if (/^\/g\b/i.test(s)) return null;
  return { channel: "NORMAL", text: s };
}

/** Một dòng trong khung chat: lớp CSS + phần đầu + nội dung. */
export function chatLine(c: ChatPayload, me: string): { cls: string; head: string; text: string } {
  switch (c.channel) {
    case "SYSTEM":
      return { cls: "sys", head: `[${c.from}] `, text: c.text };
    case "WHISPER":
      return c.to !== undefined || c.from === me
        ? { cls: "whisper", head: `[Mật → ${c.to ?? "?"}] `, text: c.text }
        : { cls: "whisper", head: `[Mật] ${c.from}: `, text: c.text };
    case "PARTY":
      return { cls: "party", head: `[Nhóm] ${c.from}: `, text: c.text };
    case "GUILD":
      return { cls: "guild", head: `[Guild] ${c.from}: `, text: c.text };
    default:
      return { cls: c.from === me ? "me" : "normal", head: `${c.from}: `, text: c.text };
  }
}

/** Thêm tin, giữ tối đa `CHAT_KEEP` tin mới nhất. */
export function pushChat(log: ChatPayload[], c: ChatPayload): ChatPayload[] {
  const next = [...log, c];
  return next.length > CHAT_KEEP ? next.slice(next.length - CHAT_KEEP) : next;
}
