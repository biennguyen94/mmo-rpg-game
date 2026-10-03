// Bộ điều khiển game phía client: nhận event server → cập nhật World/player → vẽ lại UI;
// thao tác người chơi → `cmd`. Không tính luật: tầm/cooldown phía client chỉ để biết khi nào gửi,
// server vẫn quyết định (KB_TECHNICAL §5–§6).
import { Sound } from "../audio/sound.js";
import { api, saveToken, type CharacterSummary } from "../net/api.js";
import { Connection } from "../net/connection.js";
import {
  ERROR_TEXT,
  chebyshev,
  type CombatPayload,
  type ErrorCode,
  type ItemView,
  type JoinReply,
  type Player,
  type ShopPayload,
  type SkillInfo,
  type SnapshotPayload,
  type SpawnPayload,
} from "../net/protocol.js";
import { AutoAttack, approach } from "../logic/autoattack.js";
import type { Stat } from "../logic/alloc.js";
import type { IconMap } from "../logic/icons.js";
import { equipSlotFor, firstFreeSlot, pickPotion, type Templates } from "../logic/items.js";
import { NoticeLog, diffPlayer } from "../logic/notices.js";
import { ServerClock } from "../state/interp.js";
import { World, type Entity } from "../state/world.js";
import { GameUI, type PanelName, type UiState } from "../ui/game_ui.js";
import type { GameView, ViewFactory } from "../view/view.js";

/** Lỗi không cần báo trong panel Thông báo khi do tự đánh (nhịp mạng lệch vài ms). */
const QUIET_AUTO: string[] = ["COOLDOWN", "OUT_OF_RANGE", "RATE_LIMITED"];

export class GameClient {
  private conn: Connection;
  private ui: GameUI;
  private view: GameView | null = null;
  private world = new World();
  private clock = new ServerClock();
  private auto = new AutoAttack();
  private notices = new NoticeLog();
  private state: UiState | null = null;
  private join: JoinReply | null = null;
  private selfId = "";
  private shop: ShopPayload | null = null;
  private pending: { kind: "npc" | "pickup"; id: string } | null = null;
  private timer: number | null = null;

  constructor(
    parent: HTMLElement,
    private readonly token: string,
    character: CharacterSummary,
    private readonly makeView: ViewFactory,
    private readonly onExit: (reason?: string) => void,
    private readonly iconMap: IconMap | null,
  ) {
    this.ui = new GameUI(parent, {
      togglePanel: (p) => this.togglePanel(p),
      closePanel: () => this.setPanel(null),
      alloc: (stat, points) => void this.alloc(stat, points),
      equip: (it) => void this.equip(it),
      unequip: (slot) => void this.unequip(slot),
      itemCommand: (c) => void this.send(c.act, c.payload),
      split: (it, n) => void this.split(it, n),
      useItem: (it) => void this.send("use_item", { itemId: it.id }).then((ok) => ok && Sound.play("potion")),
      buy: (tid) => void this.send("buy", { npcId: this.shop?.npcId, templateId: tid, quantity: 1 }),
      sell: (it) => void this.send("sell", { npcId: this.shop?.npcId, itemId: it.id }),
      usePotion: (type) => void this.usePotion(type),
      pickupNearest: () => this.pickupNearest(),
      logout: () => void this.logout(),
      setSound: (on) => (Sound.set(on), this.render()),
      noticesSeen: () => (this.notices.markAllRead(), this.render()),
      clearNotices: () => (this.notices.clear(), this.render()),
      attack: (target, skill) => this.startAttack(target, skill),
    });

    this.conn = new Connection(token, character.id, {
      onJoin: (r) => this.onJoin(r),
      onEvent: (ev, p) => this.onEvent(ev, p),
      onStatus: (st) => this.onStatus(st),
    });
  }

  start(): void {
    void this.conn.start();
    this.timer = window.setInterval(() => this.tick(), 50);
  }

  stop(): void {
    this.conn.stop();
    if (this.timer !== null) clearInterval(this.timer);
    this.view?.destroy();
    this.ui.destroy();
  }

  // ---------- Từ server ----------

  private onJoin(r: JoinReply): void {
    this.join = r;
    this.selfId = r.entityId;
    this.world = new World();
    const templates: Templates = new Map(r.data.items.map((t) => [t.templateId, t]));
    const skills = new Map<string, SkillInfo>(r.data.skills.map((s) => [s.id, s]));
    this.state = {
      player: r.player,
      map: r.map,
      templates,
      skills,
      iconMap: this.iconMap,
      notices: this.notices,
      panel: null, // không panel nào mở khi vào game (§19.1)
      shop: null,
      netStatus: null,
      soundOn: Sound.on,
    };
    this.view?.destroy();
    this.view = this.makeView(this.ui.view, r.map, this.world, {
      onGround: (x, y) => this.moveTo(x, y),
      onEntity: (e, sx, sy) => this.clickEntity(e, sx, sy),
    });
    const delay = r.config.interpolationDelayMs;
    this.view.setClock(() => this.clock.now(Date.now()) - delay);
    this.view.setSelf(r.entityId);
    // hook chỉ-đọc cho test e2e/debug: chỉ chứa dữ liệu server đã gửi cho client này
    (window as unknown as { __mu: object }).__mu = {
      entities: () => [...this.world.entities.values()].map(({ interp: _i, ...e }) => e),
      player: () => this.state?.player,
      selfId: this.selfId,
    };
    this.render();
  }

  private onEvent(ev: string, p: any): void {
    if (!this.state) return;
    const now = this.clock.now(Date.now());
    switch (ev) {
      case "spawn":
        this.world.spawn(p as SpawnPayload, now);
        if ((p as SpawnPayload).kind === "item") Sound.play("click");
        break;
      case "despawn":
        this.world.despawn(p.id);
        break;
      case "snapshot": {
        const s = p as SnapshotPayload;
        this.clock.observe(s.t, Date.now());
        this.world.snapshot(s);
        const me = this.world.entities.get(this.selfId);
        if (me) this.state.player = { ...this.state.player, x: me.x, y: me.y, hp: me.hp ?? this.state.player.hp };
        this.arrive();
        this.closeShopIfFar();
        break;
      }
      case "combat":
        this.onCombat(p as CombatPayload);
        break;
      case "player":
        this.onPlayer(p as Player);
        break;
      case "shop":
        this.shop = p as ShopPayload;
        this.state.shop = this.shop;
        this.state.panel = "shop";
        break;
    }
    this.render();
  }

  private onCombat(c: CombatPayload): void {
    this.world.setHp(c.target, c.hp);
    if (c.target === this.selfId && this.state) {
      this.state.player = { ...this.state.player, hp: c.hp };
      if (c.dmg > 0) Sound.play("hurt");
    } else if (c.attacker === this.selfId) {
      Sound.play(c.dmg > 0 ? "hit" : "miss");
    }
    this.view?.combat(c);
  }

  private onPlayer(p: Player): void {
    if (!this.state) return;
    for (const n of diffPlayer(this.state.player, p, this.state.templates)) {
      this.notices.add(n.type, n.text, n.sub);
      if (n.type === "LEVEL_UP") Sound.play("levelup");
      if (n.type === "ITEM_PICKUP") Sound.play("pickup");
    }
    // vị trí lấy từ snapshot (mới hơn), còn lại lấy từ server
    const me = this.world.entities.get(this.selfId);
    this.state.player = me ? { ...p, x: me.x, y: me.y } : p;
  }

  private onStatus(st: string): void {
    if (st === "online") {
      if (this.state) this.state.netStatus = null;
    } else if (st === "reconnecting") {
      if (this.state) this.state.netStatus = "Mất kết nối, đang kết nối lại…";
    } else if (st === "kicked") {
      return this.exit("Tài khoản đã vào game ở nơi khác.");
    } else if (st === "version") {
      return this.exit("Phiên bản client đã cũ, hãy tải lại trang.");
    } else {
      return this.exit();
    }
    this.render();
  }

  // ---------- Thao tác ----------

  private async send(act: string, payload: object = {}, quiet: string[] = []): Promise<boolean> {
    const r = await this.conn.cmd(act, payload);
    if (!r.ok && !quiet.includes(r.error)) {
      this.notices.add("ERROR", ERROR_TEXT[r.error as ErrorCode] ?? `Lỗi: ${r.error}`);
      this.render();
    }
    return r.ok;
  }

  private moveTo(x: number, y: number): void {
    this.auto.stop();
    this.pending = null;
    this.ui.closeContext();
    this.view?.marker(x, y);
    void this.send("move_to", { x, y });
  }

  private clickEntity(e: Entity, sx: number, sy: number): void {
    const me = this.world.entities.get(this.selfId);
    if (!me || !this.join) return;
    if (e.kind === "monster" && e.state !== "dead") {
      this.ui.monsterMenu(e.id, sx, sy);
    } else if (e.kind === "npc") {
      this.reach("npc", e, this.join.config.npcRange);
    } else if (e.kind === "item") {
      this.reach("pickup", e, this.join.config.pickupRange);
    } else {
      this.moveTo(e.x, e.y);
    }
  }

  /** Trong tầm thì làm ngay; ngoài tầm thì đi tới rồi làm khi tới (`arrive`). */
  private reach(kind: "npc" | "pickup", e: Entity, range: number): void {
    const me = this.world.entities.get(this.selfId)!;
    this.auto.stop();
    if (chebyshev(me.x, me.y, e.x, e.y) <= range) return this.act(kind, e.id);
    this.pending = { kind, id: e.id };
    const step = kind === "pickup" ? { x: e.x, y: e.y } : approach(me, e);
    this.view?.marker(step.x, step.y);
    void this.send("move_to", step);
  }

  private arrive(): void {
    if (!this.pending || !this.join) return;
    const me = this.world.entities.get(this.selfId);
    const target = this.world.entities.get(this.pending.id);
    if (!me || !target) return void (this.pending = null);
    const range = this.pending.kind === "npc" ? this.join.config.npcRange : this.join.config.pickupRange;
    if (chebyshev(me.x, me.y, target.x, target.y) <= range) {
      const p = this.pending;
      this.pending = null;
      this.act(p.kind, p.id);
    }
  }

  private act(kind: "npc" | "pickup", id: string): void {
    if (kind === "npc") void this.send("npc_open", { npcId: id });
    else void this.send("pickup", { id });
  }

  private pickupNearest(): void {
    const me = this.world.entities.get(this.selfId);
    if (!me || !this.join) return;
    const items = this.world
      .ofKind("item")
      .map((e) => ({ e, d: chebyshev(me.x, me.y, e.x, e.y) }))
      .filter((x) => x.d <= this.join!.config.pickupRange)
      .sort((a, b) => a.d - b.d);
    if (items[0]) void this.send("pickup", { id: items[0].e.id });
  }

  private startAttack(target: string, skill: string | null): void {
    this.pending = null;
    this.auto.start(target, skill);
  }

  private async usePotion(type: "HP" | "MP"): Promise<void> {
    if (!this.state) return;
    const stack = pickPotion(this.state.player.inventory, this.state.templates, type);
    if (!stack) return; // hết potion: không gửi gì (§19.6)
    if (await this.send("use_item", { itemId: stack.id })) Sound.play("potion");
  }

  private async equip(it: ItemView): Promise<void> {
    if (!this.state) return;
    const t = this.state.templates.get(it.templateId);
    const slot = t ? equipSlotFor(t, this.state.player.equipment) : null;
    if (slot !== null) await this.send("equip", { itemId: it.id, slot });
  }

  private async split(it: ItemView, quantity: number): Promise<void> {
    if (!this.state) return;
    const p = this.state.player;
    const toSlot = firstFreeSlot(p.inventory, p.view.inventorySize);
    await this.send("split", { itemId: it.id, quantity: Math.floor(quantity), toSlot });
  }

  private async unequip(slot: number): Promise<void> {
    if (!this.state) return;
    const p = this.state.player;
    await this.send("unequip", { slot, toSlot: firstFreeSlot(p.inventory, p.view.inventorySize) });
  }

  private async alloc(stat: Stat, points: number): Promise<void> {
    await this.send("alloc", { stat, points });
  }

  private togglePanel(p: PanelName): void {
    if (!this.state) return;
    this.setPanel(this.state.panel === p ? null : p);
  }

  private setPanel(p: PanelName | null): void {
    if (!this.state) return;
    this.state.panel = p;
    if (p === "notices") this.notices.markAllRead();
    if (p !== "shop") this.shop = null;
    this.render();
  }

  /** Shop tự đóng khi rời tầm NPC (§19.7). */
  private closeShopIfFar(): void {
    if (!this.state || this.state.panel !== "shop" || !this.shop || !this.join) return;
    const me = this.world.entities.get(this.selfId);
    const npc = this.world.entities.get(`npc_${this.shop.npcId}`);
    if (me && npc && chebyshev(me.x, me.y, npc.x, npc.y) > this.join.config.npcRange) this.state.panel = null;
  }

  private tick(): void {
    if (!this.auto.target || !this.state) return;
    const me = this.world.entities.get(this.selfId);
    const t = this.world.entities.get(this.auto.target);
    if (!me) return;
    const range = this.state.skills.get(this.auto.pendingSkill ?? "basic_attack")?.range ?? 1;
    const action = this.auto.tick(
      Date.now(),
      me,
      t ? { x: t.x, y: t.y, alive: t.state !== "dead" } : null,
      range,
      this.state.player.view.cooldownMs,
    );
    if (!action) return;
    const { act, ...payload } = action;
    void this.conn.cmd(act, payload).then((r) => {
      if (r.ok || !this.state) return;
      if (r.error === "NO_MANA") {
        this.auto.skillFailed();
        this.notices.add("ERROR", ERROR_TEXT.NO_MANA);
      } else if (r.error === "COOLDOWN") {
        this.auto.retryAfter(Date.now(), 100);
      } else if (r.error === "INVALID_TARGET" || r.error === "FORBIDDEN") {
        this.auto.stop();
      } else if (!QUIET_AUTO.includes(r.error)) {
        this.notices.add("ERROR", ERROR_TEXT[r.error as ErrorCode] ?? r.error);
      }
      this.render();
    });
  }

  private async logout(): Promise<void> {
    try {
      await api.logout(this.token);
    } catch {
      /* token có thể đã hết hạn */
    }
    saveToken(null);
    this.exit();
  }

  private exit(reason?: string): void {
    this.stop();
    this.onExit(reason);
  }

  private render(): void {
    if (this.state) this.ui.update({ ...this.state, soundOn: Sound.on });
  }
}
