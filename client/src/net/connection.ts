// Kết nối game: lấy WS ticket (dùng một lần) trước MỖI lần mở socket, join kênh "game"
// với {clientVersion, characterId}. Mất kết nối → tự nối lại với ticket mới và join lại (nạp
// lại toàn bộ trạng thái). Server giữ nhân vật `reconnectGraceSeconds` khi mất kết nối (P3-M2);
// đăng xuất thì `leave()` kênh trước để server biết là rời có chủ ý. Học từ net.js của repo nền.
import { Channel, Socket } from "phoenix";
import { api } from "./api.js";
import { RidGen, type ErrorPayload, type JoinReply } from "./protocol.js";

export const CLIENT_VERSION = "0.1.0";

export type CmdResult = { ok: true } | { ok: false; error: string };

export interface ConnectionHandlers {
  onJoin(reply: JoinReply): void;
  onEvent(event: string, payload: any): void;
  /** Trạng thái kết nối để hiện thanh báo mất mạng. */
  onStatus(status: "online" | "reconnecting" | "kicked" | "unauthorized" | "version"): void;
}

const EVENTS = ["snapshot", "spawn", "despawn", "combat", "player", "shop", "error", "map_change", "chat", "mail", "warehouse", "party", "party_invite"];

export class Connection {
  private socket: Socket | null = null;
  private channel: Channel | null = null;
  private rids = new RidGen();
  private closed = false;
  private tries = 0;

  constructor(
    private readonly token: string,
    private readonly characterId: string,
    private readonly h: ConnectionHandlers,
  ) {}

  async start(): Promise<void> {
    this.closed = false;
    let ticket: string;
    try {
      ticket = (await api.wsTicket(this.token)).ticket;
    } catch (e: any) {
      if (e?.status === 401) return this.h.onStatus("unauthorized");
      return this.retry();
    }

    // Tự quản lý nối lại (ticket chỉ dùng một lần): tắt cơ chế nối lại của Phoenix
    const socket = new Socket("/socket", {
      params: { ticket },
      reconnectAfterMs: () => 24 * 3600 * 1000,
      rejoinAfterMs: () => 24 * 3600 * 1000,
    });
    this.socket = socket;
    socket.onError(() => this.lost());
    socket.connect();

    const ch = socket.channel("game", { clientVersion: CLIENT_VERSION, characterId: this.characterId });
    this.channel = ch;
    for (const ev of EVENTS) ch.on(ev, (p) => this.h.onEvent(ev, p));
    ch.onError(() => this.lost());
    ch.on("error", (p: ErrorPayload) => {
      // tab khác vào game (single login): server đóng kênh này
      if (p.rid === null && p.error === "FORBIDDEN") this.kicked();
    });
    ch.join()
      .receive("ok", (reply: JoinReply) => {
        this.tries = 0;
        this.h.onStatus("online");
        this.h.onJoin(reply);
      })
      .receive("error", (r: { reason?: string }) => {
        this.stop();
        this.h.onStatus(r?.reason === "clientVersion" ? "version" : "unauthorized");
      });
  }

  /** Gửi `cmd` với `rid` mới. Kết quả: ack `{rid}` hoặc lỗi `{rid, error}` (P2). */
  cmd(act: string, payload: object = {}): Promise<CmdResult> {
    return new Promise((resolve) => {
      if (!this.channel) return resolve({ ok: false, error: "FORBIDDEN" });
      this.channel
        .push("cmd", { act, rid: this.rids.next(), ...payload })
        .receive("ok", () => resolve({ ok: true }))
        .receive("error", (r: ErrorPayload) => resolve({ ok: false, error: r?.error ?? "FORBIDDEN" }))
        .receive("timeout", () => resolve({ ok: false, error: "TIMEOUT" }));
    });
  }

  /** Rời kênh có chủ ý (đăng xuất): server cho nhân vật rời map ngay (hoặc sau logoutInCombatSeconds). */
  leave(): Promise<void> {
    return new Promise<void>((resolve) => {
      const ch = this.channel;
      this.closed = true;
      if (!ch) return resolve();
      ch.leave(1000)
        .receive("ok", () => resolve())
        .receive("timeout", () => resolve());
    }).then(() => this.stop());
  }

  stop(): void {
    this.closed = true;
    this.socket?.disconnect();
    this.socket = null;
    this.channel = null;
  }

  private kicked(): void {
    this.stop();
    this.h.onStatus("kicked");
  }

  private lost(): void {
    if (this.closed) return;
    this.stop();
    this.closed = false;
    this.h.onStatus("reconnecting");
    this.retry();
  }

  private retry(): void {
    if (this.closed) return;
    this.tries += 1;
    const ms = Math.min(1000 * 2 ** Math.min(this.tries, 4), 15000);
    setTimeout(() => {
      if (!this.closed) this.start();
    }, ms);
  }
}
