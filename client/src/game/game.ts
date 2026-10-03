// Bộ điều khiển game phía client: nhận event server → cập nhật World/player → vẽ lại UI;
// thao tác người chơi → `cmd`. Không tính luật: tầm/cooldown phía client chỉ để biết khi nào gửi,
// server vẫn quyết định (KB_TECHNICAL §5–§6).
import { duelResultText, warResultText } from "../logic/pvp.js";
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
  type WarehousePayload,
  type SkillInfo,
  type SnapshotPayload,
  type SpawnPayload,
  type MapChangePayload,
  type ChatPayload,
  type MailPayload,
  type PartyPayload,
  type DuelPayload,
  type GuildPayload,
  type GuildWarPayload,
  type UpgradePayload,
  type TradePayload,
  type RankingPayload,
  type MapData,
} from "../net/protocol.js";
import { AutoAttack, approach } from "../logic/autoattack.js";
import type { Stat } from "../logic/alloc.js";
import type { IconMap } from "../logic/icons.js";
import { BAG_COLUMNS, autoSlot, equipSlotFor, firstFreeSlot, pickPotion, tradeResultText, twoHandConflict, type Templates } from "../logic/items.js";
import { NoticeLog, diffPlayer } from "../logic/notices.js";
import { parseChat, pushChat } from "../logic/chat.js";
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
  /** Skill đang chờ chọn ô (teleport, P2-M3); null = click đất là đi. */
  private aiming: string | null = null;
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
      // đóng panel giao dịch = hủy giao dịch (không để giao dịch treo sau màn hình)
      closePanel: () => (this.state?.panel === "trade" && this.state.trade ? void this.send("trade_cancel") : this.setPanel(null)),
      alloc: (stat, points) => void this.alloc(stat, points),
      equip: (it) => void this.equip(it),
      unequip: (slot) => void this.unequip(slot),
      itemCommand: (c) =>
        void (c.act === "equip" ? this.equipTo(c.payload.itemId as string, c.payload.slot as number) : this.send(c.act, c.payload)),
      split: (it, n) => void this.split(it, n),
      useItem: (it) => void this.send("use_item", { itemId: it.id }).then((ok) => ok && Sound.play("potion")),
      buy: (tid) => void this.send("buy", { npcId: this.shop?.npcId, templateId: tid, quantity: 1 }),
      sell: (it) => void this.send("sell", { npcId: this.shop?.npcId, itemId: it.id }),
      deposit: (it) => void this.transfer(it, "WAREHOUSE"),
      withdraw: (it) => void this.transfer(it, "INVENTORY"),
      usePotion: (type) => void this.usePotion(type),
      pickupNearest: () => this.pickupNearest(),
      logout: () => void this.logout(),
      switchCharacter: () => void this.conn.leave().then(() => this.exit()),
      setSound: (on) => (Sound.set(on), this.render()),
      noticesSeen: () => (this.notices.markAllRead(), this.render()),
      clearNotices: () => (this.notices.clear(), this.render()),
      attack: (target, skill) => this.startAttack(target, skill),
      cast: (skill, target) => void this.cast(skill, target),
      aim: (skill) => ((this.aiming = skill), this.ui.closeContext(), this.render()),
      cancelAim: () => ((this.aiming = null), this.render()),
      sendChat: (line) => void this.sendChat(line),
      claimMail: (id) => void this.send("mail_claim", { mailId: id }).then((ok) => ok && Sound.play("pickup")),
      deleteReadMail: () => void this.send("mail_delete", { read: true }),
      partyInvite: (name) => void this.send("party_invite", { to: name }).then((ok) => ok && this.notices.add("SYSTEM", `Đã mời ${name} vào nhóm.`)),
      partyAnswer: (from, accept) => {
        if (this.state) this.state.partyInvite = null;
        this.render();
        void this.send(accept ? "party_accept" : "party_decline", { from });
      },
      partyLeave: () => void this.send("party_leave"),
      goTo: (x, y) => this.moveTo(x, y),
      partyKick: (name) => void this.send("party_kick", { name }),
      partyDisband: () => void this.send("party_disband"),
      duelRequest: (name) => void this.send("duel_request", { to: name }).then((ok) => ok && this.notices.add("SYSTEM", `Đã thách đấu ${name}.`)),
      duelAnswer: (from, accept) => {
        if (this.state) this.state.duelAsk = null;
        this.render();
        void this.send(accept ? "duel_accept" : "duel_decline", { from });
      },
      duelCancel: () => void this.send("duel_cancel"),
      guildCreate: (name) => void this.send("guild_create", { name }).then((ok) => ok && this.notices.add("SYSTEM", `Đã lập guild ${name}.`)),
      guildInvite: (name) => void this.send("guild_invite", { to: name }).then((ok) => ok && this.notices.add("SYSTEM", `Đã mời ${name} vào guild.`)),
      guildAnswer: (guild, accept) => {
        if (this.state) this.state.guildInvite = null;
        this.render();
        void this.send(accept ? "guild_accept" : "guild_decline", { guild });
      },
      guildLeave: () => void this.send("guild_leave"),
      guildKick: (name) => void this.send("guild_kick", { name }),
      guildPromote: (name) => void this.send("guild_promote", { name }),
      guildDemote: (name) => void this.send("guild_demote", { name }),
      guildDisband: () => void this.send("guild_disband"),
      warDeclare: (guild) => void this.send("guild_war_declare", { guild }).then((ok) => ok && this.notices.add("SYSTEM", `Đã tuyên chiến với guild ${guild}.`)),
      warAnswer: (guild, accept) => {
        if (this.state) this.state.warAsk = null;
        this.render();
        void this.send(accept ? "guild_war_accept" : "guild_war_decline", { guild });
      },
      warSurrender: () => void this.send("guild_war_surrender"),
      tradeRequest: (name) => void this.send("trade_request", { to: name }).then((ok) => ok && this.notices.add("SYSTEM", `Đã mời ${name} giao dịch.`)),
      tradeAnswer: (from, accept) => {
        if (this.state) this.state.tradeAsk = null;
        this.render();
        void this.send(accept ? "trade_accept" : "trade_decline", { from });
      },
      tradePut: (itemId) => void this.send("trade_put", { itemId }),
      tradeTake: (itemId) => void this.send("trade_take", { itemId }),
      tradeZen: (amount) => void this.send("trade_zen", { amount }),
      tradeLock: () => void this.send("trade_lock"),
      tradeConfirm: () => void this.send("trade_confirm"),
      tradeCancel: () => void this.send("trade_cancel"),
      ranking: (board) => void this.send("ranking", { board }),
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
      warehouse: null,
      netStatus: null,
      soundOn: Sound.on,
      aiming: null,
      serverNow: Date.now(),
      chat: this.state?.chat ?? [],
      mailUnread: this.state?.mailUnread ?? 0,
      mail: this.state?.mail ?? [],
      // nhóm sống trên server (RAM): vào lại thì event `party` tới sau
      party: this.state?.party ?? null,
      pvp: r.config.pvp ?? { enabled: false, minLevel: 0 },
      levelBonus: r.config.items?.levelBonus ?? {},
      optionBonus: r.config.items?.optionBonus ?? 0,
      // giao dịch bị hủy khi mất kết nối (KB_TECHNICAL §10): vào lại thì không còn
      trade: null,
      tradeAsk: null,
      ranking: null,
      partyInvite: null,
      // guild: event `guild` tới ngay sau join (Session đẩy)
      guild: this.state?.guild ?? null,
      guildCfg: r.config.guild ?? null,
      guildInvite: null,
      // war sống trên server (RAM): vào lại thì event `guild_war start` tới sau
      war: null,
      warAsk: null,
      duel: null,
      duelAsk: null,
    };
    this.buildView(r.map);
    this.render();
  }

  /** Dựng game view cho `map` (vào game hoặc qua cổng). */
  private buildView(map: MapData): void {
    if (!this.join) return;
    this.view?.destroy();
    this.view = this.makeView(this.ui.view, map, this.world, {
      onGround: (x, y) => (this.aiming ? void this.castAt(this.aiming, x, y) : this.moveTo(x, y)),
      onEntity: (e, sx, sy, tx, ty) => this.clickEntity(e, sx, sy, tx, ty),
    });
    const delay = this.join.config.interpolationDelayMs;
    this.view.setClock(() => this.clock.now(Date.now()) - delay);
    this.view.setSelf(this.selfId);
    this.view.setEnemyGuild(this.state?.war?.enemy ?? null);
    // hook chỉ-đọc cho test e2e/debug: chỉ chứa dữ liệu server đã gửi cho client này
    (window as unknown as { __mu: object }).__mu = {
      entities: () => [...this.world.entities.values()].map(({ interp: _i, ...e }) => e),
      player: () => this.state?.player,
      map: () => this.state?.map.id,
      selfId: this.selfId,
    };
  }

  /** Qua cổng (P2-M4): thế giới mới, view mới; `spawn` của map mới tới ngay sau event này. */
  private onMapChange(p: MapChangePayload): void {
    if (!this.state) return;
    this.auto.stop();
    this.pending = null;
    this.aiming = null;
    this.shop = null;
    this.ui.closeContext();
    this.selfId = p.entityId;
    this.world = new World();
    this.state.map = p.map;
    this.state.player = p.player;
    this.state.shop = null;
    this.state.warehouse = null;
    if (this.state.panel === "shop" || this.state.panel === "warehouse") this.state.panel = null;
    this.notices.add("SYSTEM", `Đã vào ${p.map.name}`);
    this.buildView(p.map);
  }

  private onEvent(ev: string, p: any): void {
    if (!this.state) return;
    const now = this.clock.now(Date.now());
    switch (ev) {
      case "spawn":
        this.world.spawn(p as SpawnPayload, now);
        // chính mình xuất hiện lại (hồi sinh ở thị trấn, P4-M1 tìm ra): HUD lấy vị trí / HP mới
        if (p.id === this.selfId) this.state.player = { ...this.state.player, x: p.x, y: p.y, hp: p.hp ?? this.state.player.hp };
        // tiếng rơi đồ: chỉ khi rơi gần mình (AOI P3-M1: đồ ở xa đi vào tầm nhìn cũng là `spawn`)
        if ((p as SpawnPayload).kind === "item" && Math.max(Math.abs(p.x - this.state.player.x), Math.abs(p.y - this.state.player.y)) <= 3) Sound.play("click");
        break;
      case "despawn":
        this.world.despawn(p.id);
        break;
      case "snapshot": {
        const s = p as SnapshotPayload;
        this.clock.observe(s.t, Date.now());
        this.world.snapshot(s);
        const me = this.world.entities.get(this.selfId);
        if (me) this.state.player = { ...this.state.player, x: me.x, y: me.y, hp: me.hp ?? this.state.player.hp, mp: me.mp ?? this.state.player.mp };
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
      case "mail": {
        const m = p as MailPayload;
        this.state.mailUnread = m.unread;
        if (m.items) this.state.mail = m.items;
        break;
      }
      case "chat":
        this.state.chat = pushChat(this.state.chat, p as ChatPayload);
        break;
      case "map_change":
        this.onMapChange(p as MapChangePayload);
        break;
      case "error":
        // lỗi không gắn lệnh (rid null): bước vào cổng khi thiếu cấp
        if (p.rid === null && p.reason === "portal") {
          const name = String(p.map).charAt(0).toUpperCase() + String(p.map).slice(1);
          this.notices.add("ERROR", `Cần cấp ${p.levelRequired} để vào ${name}.`);
        }
        break;
      case "shop":
        this.shop = p as ShopPayload;
        this.state.shop = this.shop;
        this.state.panel = "shop";
        break;
      case "party": {
        const pp = p as PartyPayload;
        this.state.party = pp.members.length ? pp : null;
        break;
      }
      case "duel":
        this.onDuel(p as DuelPayload);
        break;
      case "guild": {
        const g = p as GuildPayload;
        this.state.guild = g.id ? g : null;
        // rời / bị đuổi / giải tán: hết war
        if (!g.id) this.setWar(null);
        break;
      }
      case "guild_war":
        this.onWar(p as GuildWarPayload);
        break;
      case "upgrade":
        this.onUpgrade(p as UpgradePayload);
        break;
      case "ranking":
        this.state.ranking = p as RankingPayload;
        break;
      case "trade_invite":
        this.state.tradeAsk = { from: p.from, until: Date.now() + (p.seconds ?? 30) * 1000 };
        Sound.play("click");
        break;
      case "trade": {
        const tr = p as TradePayload;
        if (tr.state === "open") {
          this.state.trade = tr;
          this.state.tradeAsk = null;
          this.state.panel = "trade";
        } else {
          this.state.trade = null;
          if (this.state.panel === "trade") this.state.panel = null;
          if (this.state.tradeAsk?.from === tr.partner) this.state.tradeAsk = null;
          this.notices.add(tr.result === "done" ? "SYSTEM" : "ERROR", tradeResultText(tr.result, tr.partner, tr.by));
          if (tr.result === "done") Sound.play("pickup");
        }
        break;
      }
      case "guild_invite":
        this.state.guildInvite = { from: p.from, guild: p.guild, until: Date.now() + (this.join?.config.guild?.inviteSeconds ?? 30) * 1000 };
        Sound.play("click");
        break;
      case "party_invite":
        this.state.partyInvite = { from: p.from, until: Date.now() + (this.join?.config.partyInviteSeconds ?? 30) * 1000 };
        Sound.play("click");
        break;
      case "warehouse":
        // mở Thủ kho hoặc kho đổi sau gửi / rút (P3-M3)
        this.state.warehouse = p as WarehousePayload;
        this.state.panel = "warehouse";
        break;
    }
    this.render();
  }

  /** Kết quả ép jewel (P5-M2): thông báo + âm thanh. */
  private onUpgrade(u: UpgradePayload): void {
    if (!this.state) return;
    const name = this.state.templates.get(u.templateId)?.name ?? u.templateId;
    const life = u.jewel === "jewel_life";
    const what = life ? `${name} option +${u.option * this.state.optionBonus}` : `${name} +${u.level}`;
    if (u.destroyed) this.notices.add("ERROR", `Ép thất bại: ${name} bị hỏng.`);
    else if (u.ok) this.notices.add("SYSTEM", `Ép thành công: ${what}.`);
    else this.notices.add("ERROR", `Ép thất bại: ${what}.`);
    Sound.play(u.ok ? "levelup" : "miss");
  }

  /** Guild war (P4-M4): lời tuyên chiến / bắt đầu / điểm / kết thúc. */
  private onWar(w: GuildWarPayload): void {
    if (!this.state) return;
    const until = Date.now() + w.secondsLeft * 1000;
    if (w.state === "request") {
      this.state.warAsk = { enemy: w.enemy, from: w.from ?? "?", until };
      Sound.play("click");
    } else if (w.state === "end") {
      this.setWar(null);
      this.notices.add(w.result === "lose" ? "ERROR" : "SYSTEM", warResultText(w));
    } else {
      if (w.state === "start") this.state.warAsk = null;
      this.setWar({ enemy: w.enemy, score: w.score ?? 0, enemyScore: w.enemyScore ?? 0, scoreToWin: w.scoreToWin ?? 0, until });
    }
  }

  private setWar(war: NonNullable<UiState["war"]> | null): void {
    if (!this.state) return;
    // hết war: dừng tự đánh người guild địch (khỏi thành PK)
    const old = this.state.war?.enemy;
    if (!war && old && this.auto.target && this.world.entities.get(this.auto.target)?.guild === old) this.auto.stop();
    this.state.war = war;
    this.view?.setEnemyGuild(war?.enemy ?? null);
  }

  /** Duel (P4-M2): lời mời / bắt đầu / kết thúc. Kết thúc thì dừng tự đánh đối thủ (khỏi thành PK). */
  private onDuel(d: DuelPayload): void {
    if (!this.state) return;
    if (d.state === "request") {
      this.state.duelAsk = { from: d.opponent ?? "?", until: Date.now() + (this.join?.config.duelInviteSeconds ?? 30) * 1000 };
      Sound.play("click");
    } else if (d.state === "start") {
      this.state.duelAsk = null;
      this.state.duel = { opponent: d.opponent ?? "?", opponentId: d.opponentId ?? "", endsAt: d.endsAt ?? 0 };
      this.notices.add("SYSTEM", `Bắt đầu đấu tay đôi với ${d.opponent}.`);
    } else {
      const opp = this.state.duel?.opponentId;
      if (opp && this.auto.target === opp) this.auto.stop();
      this.state.duel = null;
      if (this.state.duelAsk?.from === d.opponent) this.state.duelAsk = null;
      this.notices.add(d.result === "lose" ? "ERROR" : "SYSTEM", duelResultText(d.result, d.opponent));
    }
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
    // vị trí + MP lấy từ snapshot (mới hơn: MapServer giữ MP, Session có thể chưa đọc lại), còn lại từ server
    const me = this.world.entities.get(this.selfId);
    this.state.player = me ? { ...p, x: me.x, y: me.y, mp: me.mp ?? p.mp } : p;
  }

  private onStatus(st: string): void {
    if (st === "online") {
      if (this.state?.netStatus) this.notices.add("SYSTEM", "Đã kết nối lại.");
      if (this.state) this.state.netStatus = null;
    } else if (st === "reconnecting") {
      // server giữ nhân vật đứng yên (vẫn bị đánh) trong lúc chờ: dừng tự đánh (P3-M2)
      this.auto.stop();
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
      // P4-M1: sát nhân bị NPC từ chối
      const murderer = r.error === "FORBIDDEN" && this.state?.player.view.pkState === "MURDERER" && ["npc_open", "buy", "sell", "move_item"].includes(act);
      this.notices.add("ERROR", murderer ? "Sát nhân không được dùng dịch vụ NPC." : (ERROR_TEXT[r.error as ErrorCode] ?? `Lỗi: ${r.error}`));
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

  private clickEntity(e: Entity, sx: number, sy: number, tx = e.x, ty = e.y): void {
    const me = this.world.entities.get(this.selfId);
    if (!me || !this.join) return;
    if (this.aiming) return void this.castAt(this.aiming, e.x, e.y);
    if (e.kind === "player") {
      // menu skill hỗ trợ / teleport (P2-M3); không có gì thì như cũ: đi tới
      if (!this.ui.playerMenu(e.id, e.id === this.selfId, sx, sy, e.name, { x: tx, y: ty }, e) && e.id !== this.selfId) this.moveTo(tx, ty);
    } else if (e.kind === "monster" && e.state !== "dead") {
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

  /** Chat (P2-M5): `/w Tên …` = nhắn riêng; lỗi hiện ở panel Thông báo. */
  private async sendChat(line: string): Promise<void> {
    const c = parseChat(line);
    if (!c) return;
    const r = await this.conn.cmd("chat", c);
    if (r.ok || !this.state) return;
    if (r.error === "INVALID_TARGET" && c.channel === "WHISPER") this.notices.add("ERROR", `Không có người chơi "${c.to}" đang online.`);
    else if (r.error === "INVALID_TARGET" && c.channel === "PARTY") this.notices.add("ERROR", "Bạn chưa có nhóm.");
    else if (r.error === "INVALID_TARGET" && c.channel === "GUILD") this.notices.add("ERROR", "Bạn chưa có guild.");
    else if (r.error !== "FORBIDDEN") this.notices.add("ERROR", ERROR_TEXT[r.error as ErrorCode] ?? `Lỗi: ${r.error}`);
    this.render();
  }

  /** Skill hỗ trợ (heal/buff) lên người chơi `target` (null = bản thân). */
  private async cast(skill: string, target: string | null): Promise<void> {
    this.ui.closeContext();
    await this.send("skill", target ? { id: skill, target } : { id: skill });
  }

  /** Skill chọn ô (teleport): gửi `{id, x, y}`, thoát chế độ chọn ô. */
  private async castAt(skill: string, x: number, y: number): Promise<void> {
    this.aiming = null;
    this.auto.stop();
    this.view?.marker(x, y);
    this.render();
    await this.send("skill", { id: skill, x, y });
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
    if (slot !== null) await this.equipTo(it.id, slot);
  }

  private async equipTo(itemId: string, slot: number): Promise<void> {
    if (!this.state) return;
    const p = this.state.player;
    const t = this.state.templates.get(p.inventory.find((i) => i.id === itemId)?.templateId ?? "");
    if (t && twoHandConflict(t, slot, p.equipment, this.state.templates, this.join?.config.twoHandedWeaponTypes ?? [])) {
      this.notices.add("ERROR", "Cung cần hai tay — tháo khiên trước.");
      this.render();
      return;
    }
    await this.send("equip", { itemId, slot });
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
    // mở Hộp thư: xin danh sách (server đánh dấu đã đọc → badge về 0)
    if (p === "mail") void this.send("mail_list");
    // mở Xếp hạng: xin bảng đang xem (mặc định "Tất cả")
    if (p === "ranking") void this.send("ranking", { board: this.state.ranking?.board ?? "level" });
    if (p !== "shop") this.shop = null;
    this.render();
  }

  /** Shop / kho tự đóng khi rời tầm NPC (§19.7). */
  /** [Gửi] / [Rút] (P3-M3): ô đích tự chọn (gộp stack cùng loại, không thì ô trống thấp nhất). */
  private async transfer(it: ItemView, to: "WAREHOUSE" | "INVENTORY"): Promise<void> {
    const wh = this.state?.warehouse;
    if (!this.state || !wh) return;
    const slot =
      to === "WAREHOUSE"
        ? autoSlot(wh.items, wh.slots, it, this.state.templates)
        : autoSlot(this.state.player.inventory, BAG_COLUMNS * BAG_COLUMNS, it, this.state.templates);
    if (slot === null) {
      this.notices.add("ERROR", to === "WAREHOUSE" ? "Kho đã đầy." : ERROR_TEXT.INVENTORY_FULL);
      return this.render();
    }
    await this.send("move_item", { itemId: it.id, to: { location: to, slot } });
  }

  private closeShopIfFar(): void {
    if (!this.state || !this.join) return;
    const npcId = this.state.panel === "shop" ? this.shop?.npcId : this.state.panel === "warehouse" ? this.state.warehouse?.npcId : null;
    if (!npcId) return;
    const me = this.world.entities.get(this.selfId);
    const npc = this.world.entities.get(`npc_${npcId}`);
    if (me && npc && chebyshev(me.x, me.y, npc.x, npc.y) > this.join.config.npcRange) this.state.panel = null;
  }

  private tick(): void {
    if (!this.auto.target || !this.state) return;
    const me = this.world.entities.get(this.selfId);
    const t = this.world.entities.get(this.auto.target);
    if (!me) return;
    // đánh thường: tầm theo vũ khí đang cầm (`view.attackRange`, server tính — P2-5)
    const skill = this.auto.pendingSkill ? this.state.skills.get(this.auto.pendingSkill) : undefined;
    const range = skill ? skill.range : this.state.player.view.attackRange;
    const action = this.auto.tick(
      Date.now(),
      me,
      t ? { x: t.x, y: t.y, alive: t.state !== "dead" } : null,
      range,
      skill?.cooldownMs ?? ((skill?.magic && this.state.player.view.cooldownMsMagic) || this.state.player.view.cooldownMs),
    );
    if (!action) return;
    let { act, ...payload } = action as { act: string } & Record<string, unknown>;
    // skill AOE tại ô (Flame): bắn vào ô của quái đang đánh
    if (act === "skill" && skill?.center === "point" && t) payload = { id: skill.id, x: t.x, y: t.y };
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
    await this.conn.leave();
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
    if (this.state) this.ui.update({ ...this.state, soundOn: Sound.on, aiming: this.aiming, serverNow: this.clock.now(Date.now()) });
  }
}
