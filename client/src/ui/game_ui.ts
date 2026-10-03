// Giao diện trong game theo KB_GAME_DESIGN §19 (DOM phủ lên game view). Chỉ hiển thị số do
// server gửi (`player.view`), không tính công thức, không cập nhật lạc quan: UI đổi khi server trả.
import type { ChatPayload, GuildConfig, GuildPayload, RankingPayload, TradePayload, ItemView, MailView, MapData, PartyPayload, Player, ChaosPayload, QuestActive, QuestBrief, QuestsPayload, ShopPayload, SkillInfo, SpawnPayload, WarehousePayload } from "../net/protocol.js";
import { ERROR_TEXT, type ErrorCode } from "../net/protocol.js";
import { PK_LABEL, canAttackPlayer, canChallenge, needsConfirm } from "../logic/pvp.js";
import { AllocBatcher, type Stat } from "../logic/alloc.js";
import { iconPath, type IconMap } from "../logic/icons.js";
import {
  BAG_COLUMNS,
  EQUIP_GRID,
  WAREHOUSE_COLUMNS,
  SLOT_LABEL,
  defaultSplit,
  dragCommand,
  equipmentInBag,
  requirements,
  shortDesc,
  itemName,
  upgradable,
  type LevelBonus,
  type DragEnd,
  type DragStart,
  type ItemCommand,
  type Templates,
} from "../logic/items.js";
import { NOTICE_ICON, type NoticeLog } from "../logic/notices.js";
import { chatLine } from "../logic/chat.js";
import { goalText, rewardText, trackerLine } from "../logic/quests.js";
import { ROLE_LABEL, canDemote, canInvite as canGuildInvite, canKick, canPromote, myRole, validGuildName } from "../logic/guild.js";
import { clear, h, mount } from "./dom.js";

export type PanelName = "character" | "inventory" | "map" | "notices" | "mail" | "shop" | "warehouse" | "settings" | "guild" | "trade" | "ranking" | "quests" | "chaos";

export interface UiState {
  player: Player;
  map: MapData;
  templates: Templates;
  skills: Map<string, SkillInfo>;
  iconMap: IconMap | null;
  notices: NoticeLog;
  panel: PanelName | null;
  shop: ShopPayload | null;
  /** Kho tài khoản đang mở ở Thủ kho (P3-M3). */
  warehouse: WarehousePayload | null;
  netStatus: string | null;
  soundOn: boolean;
  /** Skill đang chờ chọn ô (teleport) — hiện dòng hướng dẫn, Esc để hủy. */
  aiming: string | null;
  /** Giờ server (ms) để đếm ngược buff. */
  serverNow: number;
  /** Tin chat gần nhất (tối đa 50, P2-M5). */
  chat: ChatPayload[];
  /** Hộp thư (P2-M6): số chưa đọc (badge) + danh sách lần mở panel gần nhất. */
  mailUnread: number;
  mail: MailView[];
  /** PvP (P4-M1, từ config join). */
  pvp: { enabled: boolean; minLevel: number };
  /** Duel đang diễn ra (P4-M2): đối thủ + giờ server hết duel. */
  duel: { opponent: string; opponentId: string; endsAt: number } | null;
  /** Lời mời duel đang chờ: người mời + hạn (giờ client, ms). */
  duelAsk: { from: string; until: number } | null;
  /** Nhóm hiện tại (P3-M4), `null` = không có nhóm. */
  party: PartyPayload | null;
  /** Lời mời vào nhóm đang chờ: người mời + hạn (giờ client, ms). */
  partyInvite: { from: string; until: number } | null;
  /** Guild (P4-M3): `null` = không có guild; config tạo guild; lời mời đang chờ. */
  guild: GuildPayload | null;
  guildCfg: GuildConfig | null;
  guildInvite: { from: string; guild: string; until: number } | null;
  /** Guild war (P4-M4): war đang diễn ra (hạn = giờ client, ms); lời tuyên chiến chờ mình nhận. */
  war: { enemy: string; score: number; enemyScore: number; scoreToWin: number; until: number } | null;
  warAsk: { enemy: string; from: string; until: number } | null;
  /** `items.levelBonus` (P5-M1) — tooltip hiện chỉ số đồ +N. */
  levelBonus: LevelBonus;
  /** Chỉ số option Jewel of Life mỗi cấp (P5-M2). */
  optionBonus: number;
  /** Giao dịch đang mở (P5-M4) + lời mời giao dịch đang chờ (hạn giờ client). */
  trade: TradePayload | null;
  tradeAsk: { from: string; until: number } | null;
  /** Bảng xếp hạng đang xem (P6-M1). */
  ranking: RankingPayload | null;
  /** Quest (P6-M2): view mới nhất từ server; `questNpc` = Quest Master đang mở (hiện [Nhận] / [Trả]). */
  quests: QuestsPayload | null;
  questNpc: string | null;
  /** P6-M4: slot cánh mở (config). P6-M3: Chaos Machine đang mở (đồ đặt vào + công thức khớp). */
  wings: boolean;
  chaos: ChaosPayload | null;
}

export interface UiActions {
  togglePanel(p: PanelName): void;
  closePanel(): void;
  alloc(stat: Stat, points: number): void;
  equip(item: ItemView): void;
  unequip(slot: number): void;
  /** Lệnh túi đồ từ kéo thả / tooltip (Phase 2: move_item, equip, unequip, drop). */
  itemCommand(c: ItemCommand): void;
  split(item: ItemView, quantity: number): void;
  useItem(item: ItemView): void;
  buy(templateId: string): void;
  sell(item: ItemView): void;
  /** Kho (P3-M3): [Gửi] túi → kho, [Rút] kho → túi (ô tự chọn). */
  deposit(item: ItemView): void;
  withdraw(item: ItemView): void;
  usePotion(type: "HP" | "MP"): void;
  pickupNearest(): void;
  logout(): void;
  /** Rời game về màn chọn nhân vật (giữ đăng nhập, P3-M5). */
  switchCharacter(): void;
  setSound(on: boolean): void;
  noticesSeen(): void;
  clearNotices(): void;
  /** Chọn trong context menu quái: `skill` null = đánh thường. */
  attack(targetId: string, skill: string | null): void;
  /** Skill hỗ trợ lên người chơi `target` (null = bản thân). */
  cast(skill: string, target: string | null): void;
  /** Bắt đầu chọn ô cho skill POINT (teleport). */
  aim(skill: string): void;
  cancelAim(): void;
  /** Gửi dòng chat người chơi gõ (`/w Tên …` = nhắn riêng). */
  sendChat(line: string): void;
  claimMail(id: string): void;
  deleteReadMail(): void;
  /** Nhóm (P3-M4). */
  partyInvite(name: string): void;
  /** Đi tới ô đã bấm (mục "Đi tới đây" trong menu người chơi): giữ thao tác click-to-move. */
  goTo(x: number, y: number): void;
  partyAnswer(from: string, accept: boolean): void;
  partyLeave(): void;
  partyKick(name: string): void;
  partyDisband(): void;
  /** Duel (P4-M2). */
  duelRequest(name: string): void;
  duelAnswer(from: string, accept: boolean): void;
  duelCancel(): void;
  /** Guild (P4-M3). */
  guildCreate(name: string): void;
  guildInvite(name: string): void;
  guildAnswer(guild: string, accept: boolean): void;
  guildLeave(): void;
  guildKick(name: string): void;
  guildPromote(name: string): void;
  guildDemote(name: string): void;
  guildDisband(): void;
  /** Guild war (P4-M4, chỉ master). */
  warDeclare(guild: string): void;
  warAnswer(guild: string, accept: boolean): void;
  warSurrender(): void;
  /** Giao dịch (P5-M4). */
  tradeRequest(name: string): void;
  tradeAnswer(from: string, accept: boolean): void;
  tradePut(itemId: string): void;
  tradeTake(itemId: string): void;
  tradeZen(amount: number): void;
  tradeLock(): void;
  tradeConfirm(): void;
  tradeCancel(): void;
  /** Xin bảng xếp hạng `board` (P6-M1). */
  ranking(board: string): void;
  /** Quest (P6-M2): nhận / trả ở Quest Master đang mở; bỏ ở đâu cũng được. */
  questAccept(id: string): void;
  questTurnin(id: string): void;
  questAbandon(id: string): void;
  /** Chaos Machine (P6-M3): đặt / lấy món (server tính lại công thức), kết hợp. */
  chaosToggle(itemId: string): void;
  chaosCombine(): void;
}

const BUFF_ICON: Record<string, string> = { defense: "🛡", damageBonus: "⚔" };

// màu minimap (§19.12: nền tối) theo `legend`
const MINIMAP_COLORS: Record<string, string> = {
  grass: "#1c2b1a",
  road: "#4a3f2c",
  town_floor: "#3a3a44",
  wall: "#6b6b78",
  tree: "#0f1a0d",
  water: "#173052",
  rock: "#2c2a27",
  portal: "#7d5cc0",
};

const isMobile = () => window.matchMedia("(max-width: 1023px)").matches;

export class GameUI {
  readonly root: HTMLElement;
  readonly view: HTMLElement;
  private hud = h("div", { class: "hud" });
  private exp = h("div", { class: "expbar" });
  private dock = h("nav", { class: "dock" });
  private overlay = h("div");
  private mobile = h("div", { class: "mobilebtns" });
  private panelHost = h("div");
  private menu: HTMLElement | null = null;
  private ctx: HTMLElement | null = null;
  private tip: HTMLElement | null = null;
  private noticeFilter: "all" | "unread" = "all";
  private mailFilter: "all" | "unread" | "gift" = "all";
  private dragging: DragStart | null = null;
  // khung chat (P2-M5): log + ô nhập (ẩn tới khi Enter / nút 💬)
  private chatLog = h("div", { class: "log", "data-test": "chat-log" });
  private chatInput = h("input", {
    class: "chatinput",
    "data-test": "chat-input",
    maxlength: 100,
    placeholder: "Gõ tin · /w Tên … = nhắn riêng",
  }) as HTMLInputElement;
  private chatBox = h("div", { class: "chatbox", "data-test": "chat" }, this.chatLog, this.chatInput);
  private chatShown: ChatPayload | null | undefined = undefined;
  private alloc: AllocBatcher;
  private state!: UiState;

  constructor(
    parent: HTMLElement,
    private readonly a: UiActions,
  ) {
    this.alloc = new AllocBatcher((stat, points) => a.alloc(stat, points));
    this.view = h("div", { class: "view" }, this.chatBox, this.panelHost, this.overlay, this.mobile);
    this.chatInput.addEventListener("keydown", (ev) => {
      if (ev.key === "Enter") {
        ev.preventDefault();
        if (this.chatInput.value.trim()) this.a.sendChat(this.chatInput.value);
        this.chatInput.value = "";
        this.closeChat();
      } else if (ev.key === "Escape") {
        ev.preventDefault();
        this.closeChat();
      }
    });
    this.root = h("div", { class: "game" }, this.hud, this.exp, this.view, this.dock);
    mount(parent, this.root);
    document.addEventListener("keydown", this.onKey);
    document.addEventListener("pointerdown", this.onOutside, true);
  }

  destroy(): void {
    document.removeEventListener("keydown", this.onKey);
    document.removeEventListener("pointerdown", this.onOutside, true);
  }

  update(s: UiState): void {
    this.state = s;
    this.renderHud();
    this.renderExp();
    this.renderDock();
    this.renderPanel();
    this.renderMobile();
    this.renderNet();
    this.renderChat();
  }

  // ---------- Chat (P2-M5) ----------

  /** Dựng lại log chỉ khi có tin mới (giữ vị trí cuộn khi người chơi đang xem tin cũ). */
  private renderChat(): void {
    const last = this.state.chat[this.state.chat.length - 1] ?? null;
    if (last === this.chatShown) return;
    this.chatShown = last;
    const atBottom = this.chatLog.scrollTop + this.chatLog.clientHeight >= this.chatLog.scrollHeight - 4;
    const me = this.state.player.name;
    mount(
      this.chatLog,
      ...this.state.chat.map((c) => {
        const l = chatLine(c, me);
        return h("div", { class: `line ${l.cls}` }, h("b", {}, l.head), l.text);
      }),
    );
    if (atBottom) this.chatLog.scrollTop = this.chatLog.scrollHeight;
  }

  openChat(): void {
    this.chatBox.classList.add("typing");
    this.chatInput.focus();
  }

  private closeChat(): void {
    this.chatBox.classList.remove("typing");
    this.chatInput.blur();
  }

  // ---------- HUD + EXP (§19.1) ----------

  private renderHud(): void {
    const p = this.state.player;
    const v = p.view;
    const bar = (cls: string, cur: number, max: number) =>
      h("div", { class: `bar ${cls}` }, h("div", { class: "fill", style: `width:${pct(cur, max)}%` }), h("div", { class: "txt" }, `${cur}/${max}`));

    mount(
      this.hud,
      h(
        "div",
        { class: "hudleft" },
        h("div", { class: "where", "data-test": "where" }, `${this.state.map.name} (${p.x},${p.y})`),
        // 📬 Hộp thư (§19.10): badge số chưa đọc, tắt khi mở panel
        h(
          "button",
          { class: `mailbtn${this.state.panel === "mail" ? " active" : ""}`, "data-test": "mailbtn", title: "Hộp thư", onclick: () => this.a.togglePanel("mail") },
          "📬",
          this.state.mailUnread > 0 && this.state.panel !== "mail" ? h("span", { class: "badge" }, this.state.mailUnread) : null,
        ),
      ),
      h(
        "div",
        { class: "bars" },
        h("div", { class: "barrow" }, bar("hp", p.hp, v.hpMax), h("span", { class: "key" }, `Q ×${v.potions.HP}`)),
        h("div", { class: "barrow" }, bar("mp", p.mp, v.mpMax), h("span", { class: "key" }, `W ×${v.potions.MP}`)),
      ),
    );
  }

  private renderExp(): void {
    const p = this.state.player;
    const req = p.view.expRequired;
    mount(
      this.exp,
      h("div", { class: "fill", style: `width:${req ? pct(p.experience, req) : 100}%` }),
      h("div", { class: "txt" }, req ? `${p.experience} / ${req}` : "MAX"),
    );
  }

  // ---------- Dock 4 tab (§19.1) + submenu Menu (§19.13) ----------

  private renderDock(): void {
    const tab = (name: PanelName | "menu", icon: string, label: string, badge = 0) =>
      h(
        "button",
        {
          class: (name === "menu" ? this.menu !== null : this.state.panel === name) ? "active" : "",
          "data-tab": name,
          onclick: () => (name === "menu" ? this.toggleMenu() : this.a.togglePanel(name)),
        },
        h("span", { class: "icon" }, icon),
        h("span", { class: "label" }, label),
        badge > 0 ? h("span", { class: "badge" }, badge) : null,
      );

    mount(
      this.dock,
      tab("character", "👤", "Nhân vật"),
      tab("inventory", "🎒", "Túi đồ"),
      tab("map", "🗺️", "Bản đồ"),
      tab("notices", "🔔", "Thông báo", this.state.panel === "notices" ? 0 : this.state.notices.unread()),
      tab("menu", "☰", "Menu"),
    );
  }

  private toggleMenu(): void {
    if (this.menu) return this.closeMenu();
    this.menu = h(
      "div",
      { class: "submenu", "data-test": "submenu" },
      this.state.guildCfg?.enabled
        ? h("button", { "data-test": "guild-menu", onclick: () => (this.closeMenu(), this.a.togglePanel("guild")) }, "🛡 Guild")
        : null,
      h("button", { "data-test": "quest-menu", onclick: () => (this.closeMenu(), this.a.togglePanel("quests")) }, "📜 Nhiệm vụ"),
      h("button", { "data-test": "ranking-menu", onclick: () => (this.closeMenu(), this.a.togglePanel("ranking")) }, "🏆 Xếp hạng"),
      h("button", { onclick: () => (this.closeMenu(), this.a.togglePanel("settings")) }, "⚙️ Cài đặt"),
      h("button", { "data-test": "switch-character", onclick: () => (this.closeMenu(), this.a.switchCharacter()) }, "👥 Đổi nhân vật"),
      h("button", { onclick: () => (this.closeMenu(), this.a.logout()) }, "🚪 Đăng xuất"),
    );
    this.root.append(this.menu);
    this.renderDock();
  }

  private closeMenu(): void {
    this.menu?.remove();
    this.menu = null;
    if (this.state) this.renderDock();
  }

  // ---------- Panel ----------

  /**
   * Khóa nội dung panel: `update` chạy theo mỗi snapshot (10 Hz) nên chỉ dựng lại panel khi dữ
   * liệu nó hiển thị đổi — dựng lại giữa chừng làm mất thao tác kéo thả / click (P2-M1).
   * Panel Nhân vật vẫn dựng lại mỗi lần (hiện HP/MP hiện tại + điểm chờ gửi của AllocBatcher).
   */
  private panelKey(): string | null {
    const s = this.state;
    if (!s.panel || s.panel === "character") return null;
    const { x: _x, y: _y, hp: _hp, mp: _mp, ...p } = s.player;
    const extra =
      s.panel === "notices"
        ? [this.noticeFilter, s.notices.list().map((n) => [n.id, n.read]), Math.floor(Date.now() / 60_000)]
        : s.panel === "shop"
          ? s.shop
          : s.panel === "warehouse"
            ? s.warehouse
            : s.panel === "settings"
            ? s.soundOn
            : s.panel === "mail"
              ? [this.mailFilter, s.mail, Math.floor(Date.now() / 60_000)]
              : s.panel === "map"
                ? [s.map.id, s.player.x, s.player.y]
                : s.panel === "guild"
                  ? [s.guild, this.guildDisbandArmed, s.war && [s.war.enemy, s.war.score, s.war.enemyScore]]
                  : s.panel === "trade"
                    ? s.trade
                    : s.panel === "ranking"
                      ? s.ranking
                      : s.panel === "quests"
                        ? [s.quests, s.questNpc, this.abandonArmed]
                        : s.panel === "chaos"
                          ? s.chaos
                          : null;
    return JSON.stringify([s.panel, p, s.iconMap !== null, extra]);
  }

  private lastPanelKey: string | null = null;

  private renderPanel(force = false): void {
    const s = this.state;
    const key = this.panelKey();
    if (!force && key !== null && key === this.lastPanelKey && this.panelHost.firstChild) return;
    this.lastPanelKey = key;
    const keep = this.panelHost.querySelector(".scroll") as HTMLElement | null;
    const scroll = keep?.scrollTop ?? 0;
    clear(this.panelHost);
    if (!s.panel) return;
    const panel =
      s.panel === "character"
        ? this.characterPanel()
        : s.panel === "inventory"
          ? this.inventoryPanel()
          : s.panel === "notices"
            ? this.noticesPanel()
            : s.panel === "mail"
              ? this.mailPanel()
              : s.panel === "map"
                ? this.mapPanel()
                : s.panel === "shop"
                  ? this.shopPanel()
                  : s.panel === "warehouse"
                    ? this.warehousePanel()
                    : s.panel === "guild"
                      ? this.guildPanel()
                      : s.panel === "trade"
                        ? this.tradePanel()
                        : s.panel === "ranking"
                          ? this.rankingPanel()
                          : s.panel === "quests"
                            ? this.questPanel()
                            : s.panel === "chaos"
                              ? this.chaosPanel()
                              : this.settingsPanel();
    this.panelHost.append(panel);
    const sc = panel.querySelector(".scroll") as HTMLElement | null;
    if (sc) {
      sc.scrollTop = scroll;
      updateScrollHints(sc);
      sc.addEventListener("scroll", () => updateScrollHints(sc));
    }
  }

  private characterPanel(): HTMLElement {
    const p = this.state.player;
    const v = p.view;
    const stat = (key: Stat, label: string) => {
      const pending = this.alloc.pendingFor(key);
      return h(
        "div",
        { class: "statrow" },
        h("span", {}, label),
        h("span", {}, (p as unknown as Record<string, number>)[key], pending ? h("span", { class: "pending" }, `+${pending}`) : null),
        h(
          "button",
          {
            "data-stat": key,
            disabled: p.freeStatPoints === 0,
            onclick: () => {
              if (this.alloc.click(key, p.freeStatPoints)) this.renderPanel(true);
            },
          },
          "+",
        ),
      );
    };
    const kv = (k: string, val: string | number) => h("div", { class: "kv" }, h("span", {}, k), h("span", {}, val));

    return h(
      "section",
      { class: "panel", "data-panel": "character" },
      h("h2", {}, "NHÂN VẬT"),
      h(
        "div",
        { class: "body" },
        h(
          "div",
          { class: "charsheet" },
          h("div", { style: "font-size:18px;font-weight:700" }, p.name),
          h("div", {}, `${p.class} · Cấp ${p.level}`),
          h("hr", { class: "sep" }),
          kv("EXP", v.expRequired ? `${p.experience} / ${v.expRequired}` : "MAX"),
          h("hr", { class: "sep" }),
          stat("strength", "STR"),
          stat("agility", "AGI"),
          stat("vitality", "VIT"),
          stat("energy", "ENE"),
          kv("Điểm còn", p.freeStatPoints),
          // P4-M1: trạng thái PK
          kv("PK", v.pkState && v.pkState !== "NORMAL" ? `${PK_LABEL[v.pkState]} (${v.pkPoints})` : PK_LABEL.NORMAL),
          h("hr", { class: "sep" }),
          kv("Dmg", `${v.attackMin} ~ ${v.attackMax}`),
          // MG (P3-M5): sức mạnh / tốc độ phép
          v.attackMaxMagic != null ? kv("Dmg phép", `${v.attackMin} ~ ${v.attackMaxMagic}`) : null,
          kv("Defense", v.defense),
          kv("Atk Speed", v.attackSpeed),
          v.attackSpeedMagic != null ? kv("Tốc độ phép", v.attackSpeedMagic) : null,
          kv("Atk Rate", v.attackRate),
          kv("HP", `${p.hp} / ${v.hpMax}`),
          kv("MP", `${p.mp} / ${v.mpMax}`),
        ),
      ),
    );
  }

  private icon(item: { templateId: string; level?: number; excellentOptions?: unknown[] }, cls = "icon32"): HTMLElement {
    const t = this.state.templates.get(item.templateId);
    const path = iconPath(this.state.iconMap, t, item.level ?? 0, (item.excellentOptions?.length ?? 0) > 0);
    return h("img", { class: cls, src: `/assets/icons/${path}`, alt: t?.name ?? item.templateId, draggable: "false" });
  }

  private inventoryPanel(): HTMLElement {
    const s = this.state;
    const p = s.player;
    const bySlot = new Map(p.equipment.map((e) => [e.slot, e]));

    const grid = h(
      "div",
      { class: "grid3" },
      EQUIP_GRID.flat().map((slot) => {
        if (slot === null) return h("div", { class: "slot none" });
        const it = bySlot.get(slot);
        const locked = slot === 7 && !s.wings; // P6-M4: mở khi features.wings bật
        return h(
          "div",
          {
            class: `slot${it ? "" : " empty"}${locked ? " locked" : ""}`,
            "data-slot": slot,
            draggable: it ? "true" : "false",
            onclick: (ev: MouseEvent) => it && this.showTooltip(it, ev, { unequip: slot }),
            ondragstart: (ev: DragEvent) => it && this.dragStart(ev, { kind: "equip", item: it }),
            ...this.dropTarget({ kind: "equip", slot }),
          },
          it ? this.icon(it) : null,
          it && it.level > 0 ? h("span", { class: "lvl" }, `+${it.level}`) : null,
          h("span", { class: "lbl" }, SLOT_LABEL[slot]),
        );
      }),
    );

    const byBagSlot = new Map(p.inventory.map((i) => [i.slot, i]));
    const cells = Array.from({ length: p.view.inventorySize }, (_, slot) => {
      const it = byBagSlot.get(slot);
      return h(
        "div",
        {
          class: `cell${it ? "" : " empty"}`,
          "data-bag-slot": slot,
          "data-item": it?.id,
          draggable: it ? "true" : "false",
          onclick: (ev: MouseEvent) => it && this.bagClick(it, ev),
          ondragstart: (ev: DragEvent) => it && this.dragStart(ev, { kind: "bag", item: it }),
          ...this.dropTarget({ kind: "bag", slot }),
        },
        it ? this.icon(it) : null,
        it && it.quantity > 1 ? h("span", { class: "qty" }, it.quantity) : null,
      it && it.level > 0 ? h("span", { class: "lvl" }, `+${it.level}`) : null,
        it && it.level > 0 ? h("span", { class: "lvl" }, `+${it.level}`) : null,
      );
    });

    return h(
      "section",
      { class: "panel", "data-panel": "inventory" },
      h("h2", {}, "TÚI ĐỒ"),
      h(
        "div",
        { class: "body", style: "display:flex" },
        h(
          "div",
          { class: "inv" },
          h("div", { class: "equip" }, h("div", { class: "hint", style: "text-align:center;margin-bottom:6px" }, "Trang bị đang mặc"), grid),
          h(
            "div",
            { class: "list" },
            h("div", { class: "head" }, "Túi đồ"),
            this.jewelAimBar(),
            h("div", { class: "bag", "data-test": "bag", style: `--cols:${BAG_COLUMNS}` }, cells),
            p.inventory.length ? null : h("div", { class: "emptytext" }, "Túi trống"),
            h(
              "div",
              { class: "trash", "data-test": "trash", ...this.dropTarget({ kind: "trash" }) },
              "🗑 Kéo đồ vào đây để vứt xuống đất",
            ),
          ),
          this.bagBottom(true),
        ),
      ),
    );
  }

  // ---------- Ép jewel (P5-M2): [Ép lên…] → bấm đồ trong túi ----------

  /** Jewel đang chờ chọn đồ để ép (`null` = bấm ô túi là xem tooltip như thường). */
  private jewelAim: ItemView | null = null;

  private bagClick(it: ItemView, ev: MouseEvent): void {
    const j = this.jewelAim;
    if (!j || it.id === j.id) return this.showTooltip(it, ev, { bag: true });
    this.jewelAim = null;
    if (upgradable(this.state.templates.get(it.templateId), this.state.levelBonus))
      this.a.itemCommand({ act: "upgrade", payload: { itemId: it.id, jewelId: j.id } });
    this.renderPanel(true);
  }

  private jewelAimBar(): HTMLElement | null {
    const j = this.jewelAim;
    // jewel đã dùng hết / không còn trong túi
    if (!j || !this.state.player.inventory.some((i) => i.id === j.id)) return (this.jewelAim = null);
    const name = this.state.templates.get(j.templateId)?.name ?? j.templateId;
    return h(
      "div",
      { class: "jewelaim", "data-test": "jewel-aim-bar" },
      h("span", {}, `Chọn đồ để ép ${name} (vũ khí, khiên, giáp)`),
      h("button", { onclick: () => ((this.jewelAim = null), this.renderPanel(true)) }, "Hủy"),
    );
  }

  // ---------- Kéo thả (P2-M1, chuột; cảm ứng dùng nút trong tooltip) ----------

  private dragStart(ev: DragEvent, from: DragStart): void {
    this.hideTooltip();
    this.dragging = from;
    ev.dataTransfer?.setData("text/plain", from.item.id);
    if (ev.dataTransfer) ev.dataTransfer.effectAllowed = "move";
  }

  private dropTarget(to: DragEnd): Record<string, (ev: DragEvent) => void> {
    return {
      ondragover: (ev: DragEvent) => {
        if (!this.dragging) return;
        ev.preventDefault();
        (ev.currentTarget as HTMLElement).classList.add("over");
      },
      ondragleave: (ev: DragEvent) => (ev.currentTarget as HTMLElement).classList.remove("over"),
      ondrop: (ev: DragEvent) => {
        ev.preventDefault();
        (ev.currentTarget as HTMLElement).classList.remove("over");
        const from = this.dragging;
        this.dragging = null;
        if (!from) return;
        const c = dragCommand(from, to, this.state.player, this.state.templates, this.state.levelBonus);
        if (!c) return;
        if (c.confirm) this.confirmDrop(from.item, ev.clientX, ev.clientY);
        else this.a.itemCommand(c);
      },
    };
  }

  /** Hỏi trước khi vứt (P2-8): vứt cả stack xuống ô đang đứng. */
  private confirmDrop(item: ItemView, x: number, y: number): void {
    this.hideTooltip();
    const name = itemName(this.state.templates.get(item.templateId), item.level, item.templateId);
    const tip = h(
      "div",
      { class: "tooltip", "data-test": "confirm-drop" },
      h("b", {}, "Vứt xuống đất?"),
      h("div", {}, item.quantity > 1 ? `${name} ×${item.quantity}` : name),
      h(
        "div",
        { class: "btns" },
        h(
          "button",
          { "data-test": "confirm-drop-yes", onclick: () => (this.hideTooltip(), this.a.itemCommand({ act: "drop", payload: { itemId: item.id } })) },
          "Vứt",
        ),
        h("button", { onclick: () => this.hideTooltip() }, "Hủy"),
      ),
    );
    this.place(tip, x, y);
    this.tip = tip;
  }

  private bagBottom(withHint: boolean): HTMLElement {
    const p = this.state.player;
    return h(
      "div",
      { class: "bottom" },
      h("div", { class: "row" }, h("span", {}, `💰 Zen: ${p.zen}`), h("span", {}, `Túi: ${p.view.inventoryUsed}/${p.view.inventorySize}`)),
      h("div", { class: "row" }, h("span", {}, `Q 🧪 HP Potion ×${p.view.potions.HP}`), h("span", {}, `W 💧 MP Potion ×${p.view.potions.MP}`)),
      withHint ? h("div", { class: "hint" }, "Muốn bán đồ, hãy gặp NPC bán hàng.") : null,
    );
  }

  // ---------- Hộp thư (§19.10, P2-M6) ----------

  private mailPanel(): HTMLElement {
    const s = this.state;
    const gift = (m: MailView) => m.zen > 0 || m.item !== null;
    const list = s.mail.filter((m) => (this.mailFilter === "unread" ? !m.read : this.mailFilter === "gift" ? gift(m) : true));
    const f = (k: "all" | "unread" | "gift", label: string) =>
      h("button", { class: this.mailFilter === k ? "on" : "", "data-mail-filter": k, onclick: () => ((this.mailFilter = k), this.renderPanel(true)) }, label);
    const reward = (m: MailView) =>
      [m.zen > 0 ? `${m.zen} Zen` : null, m.item ? `${s.templates.get(m.item.templateId)?.name ?? m.item.templateId} ×${m.item.quantity}` : null]
        .filter(Boolean)
        .join(", ");
    return h(
      "section",
      { class: "panel", "data-panel": "mail" },
      h("h2", {}, "HỘP THƯ"),
      h(
        "div",
        { class: "body scroll" },
        h(
          "div",
          { class: "notices mails" },
          h("div", { class: "filters" }, f("all", "Tất cả"), f("unread", "Chưa đọc"), f("gift", "Có quà")),
          list.length
            ? list.map((m) =>
                h(
                  "div",
                  { class: `notice mail${m.read ? "" : " unread"}`, "data-mail": m.id },
                  h("div", {}, gift(m) ? "🎁" : m.kind === "WELCOME" ? "🎉" : "🔧"),
                  h(
                    "div",
                    {},
                    h("div", { class: "text" }, m.title),
                    m.body ? h("div", { class: "sub" }, m.body) : null,
                    gift(m) ? h("div", { class: "sub" }, `Quà: ${reward(m)}`) : null,
                    h("div", { class: "time" }, ago(m.createdAt)),
                    gift(m)
                      ? m.claimed
                        ? h("div", { class: "claimed" }, "✓ Đã nhận")
                        : h("button", { "data-claim": m.id, onclick: () => this.a.claimMail(m.id) }, "Nhận")
                      : null,
                  ),
                ),
              )
            : h("div", { class: "emptytext" }, "Không có thư"),
          s.mail.length ? h("div", { style: "text-align:center;margin-top:12px" }, h("button", { "data-test": "mail-delete-read", onclick: () => this.a.deleteReadMail() }, "Xóa đã đọc")) : null,
        ),
      ),
    );
  }

  // ---------- Bản đồ (§19.12, P2-M6) ----------

  private mapPanel(): HTMLElement {
    const s = this.state;
    const m = s.map;
    const SIZE = 256;
    const cell = SIZE / Math.max(m.width, m.height);
    const cv = h("canvas", { width: SIZE, height: SIZE, class: "minimap", "data-test": "minimap" }) as HTMLCanvasElement;
    const g = cv.getContext("2d");
    if (g) {
      g.fillStyle = "#0b0c10";
      g.fillRect(0, 0, SIZE, SIZE);
      m.tiles.forEach((row, y) =>
        [...row].forEach((ch, x) => {
          const kind = m.legend[ch];
          g.fillStyle = MINIMAP_COLORS[kind] ?? "#0b0c10";
          g.fillRect(x * cell, y * cell, cell, cell);
        }),
      );
      // safe zone (🏠): khung vàng mờ
      g.strokeStyle = "rgba(217,180,90,0.8)";
      for (const z of m.safeZones) g.strokeRect(z.x * cell + 0.5, z.y * cell + 0.5, z.w * cell - 1, z.h * cell - 1);
      const dot = (x: number, y: number, color: string, r: number) => {
        g.fillStyle = color;
        g.beginPath();
        g.arc((x + 0.5) * cell, (y + 0.5) * cell, r, 0, Math.PI * 2);
        g.fill();
      };
      for (const n of m.npcs) dot(n.x, n.y, "#ffd23f", 3);
      for (const p of m.portals ?? []) {
        const cx = (p.x + p.w / 2) * cell;
        const cy = (p.y + 0.5) * cell;
        g.fillStyle = "#c9a7ff";
        g.beginPath();
        g.moveTo(cx, cy - 5);
        g.lineTo(cx - 5, cy + 4);
        g.lineTo(cx + 5, cy + 4);
        g.fill();
      }
      dot(s.player.x, s.player.y, "#3ddc84", 4);
    }
    return h(
      "section",
      { class: "panel", "data-panel": "map" },
      h("h2", {}, "BẢN ĐỒ"),
      h(
        "div",
        { class: "body" },
        h(
          "div",
          { class: "mappanel" },
          h("div", { class: "mapname" }, m.name.toUpperCase()),
          cv,
          h("div", { class: "legend" }, h("span", {}, "🟢 Bạn"), h("span", {}, "🟡 NPC"), h("span", {}, "▲ Cổng"), h("span", {}, "🏠 Thị trấn")),
          (m.portals ?? []).map((p) =>
            h("div", { class: "hint" }, `▲ (${p.x},${p.y}) → ${p.to.charAt(0).toUpperCase()}${p.to.slice(1)}${p.levelRequired ? ` (cấp ${p.levelRequired})` : ""}`),
          ),
          h("div", { "data-test": "map-pos" }, `Vị trí: (${s.player.x}, ${s.player.y})`),
        ),
      ),
    );
  }

  private noticesPanel(): HTMLElement {
    const list = this.state.notices.list(this.noticeFilter === "unread");
    const f = (k: "all" | "unread", label: string) =>
      h("button", { class: this.noticeFilter === k ? "on" : "", onclick: () => ((this.noticeFilter = k), this.renderPanel(true)) }, label);
    return h(
      "section",
      { class: "panel", "data-panel": "notices" },
      h("h2", {}, "THÔNG BÁO"),
      h(
        "div",
        { class: "body scroll" },
        h(
          "div",
          { class: "notices" },
          h("div", { class: "filters" }, f("all", "Tất cả"), f("unread", "Chưa đọc")),
          list.length
            ? list.map((n) =>
                h(
                  "div",
                  { class: `notice${n.read ? "" : " unread"}` },
                  h("div", {}, NOTICE_ICON[n.type]),
                  h("div", {}, h("div", { class: "text" }, n.text), n.sub ? h("div", { class: "sub" }, n.sub) : null, h("div", { class: "time" }, ago(n.at))),
                ),
              )
            : h("div", { class: "emptytext" }, "Chưa có thông báo"),
          list.length ? h("div", { style: "text-align:center;margin-top:12px" }, h("button", { onclick: () => this.a.clearNotices() }, "Xóa tất cả")) : null,
        ),
      ),
    );
  }

  private shopPanel(): HTMLElement {
    const s = this.state;
    const shop = s.shop;
    const bag = equipmentInBag(s.player.inventory, s.templates);
    const sellables = [...bag, ...s.player.inventory.filter((i) => !s.templates.get(i.templateId)?.slot)];
    return h(
      "section",
      { class: "panel", "data-panel": "shop" },
      h(
        "div",
        { class: "body scroll", style: "padding-top:12px" },
        h(
          "div",
          { class: "shop" },
          h(
            "div",
            { class: "col" },
            h("h3", {}, "SHOP"),
            h("div", { class: "hint" }, shop?.name ?? ""),
            h("hr", { class: "sep" }),
            (shop?.items ?? []).map((it) => {
              const t = s.templates.get(it.templateId);
              return h(
                "div",
                { class: "itemrow buy", "data-buy": it.templateId, onclick: () => this.a.buy(it.templateId) },
                h("div", { class: "iconframe" }, this.icon(it)),
                h("div", { class: "info" }, h("div", { class: "name" }, t?.name ?? it.templateId), h("div", { class: "desc" }, `${it.price} Zen`)),
              );
            }),
            h("hr", { class: "sep" }),
            h("div", { class: "hint" }, "Bấm [Bán] cạnh item bên phải để bán"),
          ),
          h(
            "div",
            { class: "col" },
            h("h3", {}, "INVENTORY"),
            sellables.length
              ? sellables.map((it) => {
                  const t = s.templates.get(it.templateId);
                  return h(
                    "div",
                    { class: "itemrow", "data-item": it.id },
                    h("div", { class: "iconframe" }, this.icon(it)),
                    h(
                      "div",
                      { class: "info" },
                      h("div", { class: "name" }, `${t?.name ?? it.templateId}${it.quantity > 1 ? ` ×${it.quantity}` : ""}`),
                      h("div", { class: "desc" }, `${(t?.sellPrice ?? 0) * it.quantity} Zen`),
                    ),
                    h("button", { onclick: () => this.a.sell(it) }, "Bán"),
                  );
                })
              : h("div", { class: "emptytext" }, "Túi trống"),
            h("div", { style: "margin-top:8px" }, `💰 Zen: ${s.player.zen}`),
          ),
        ),
      ),
    );
  }

  // ---------- Kho tài khoản (P3-M3, P3-6) ----------

  /** Ô lưới (túi hoặc kho): click → tooltip có [Gửi] / [Rút], kéo thả giữa hai lưới. */
  private gridCell(it: ItemView | undefined, slot: number, kind: "bag" | "wh"): HTMLElement {
    return h(
      "div",
      {
        class: `cell${it ? "" : " empty"}`,
        [kind === "wh" ? "data-wh-slot" : "data-bag-slot"]: slot,
        "data-item": it?.id,
        draggable: it ? "true" : "false",
        onclick: (ev: MouseEvent) => it && this.showTooltip(it, ev, kind === "wh" ? { withdraw: true } : { deposit: true }),
        ondragstart: (ev: DragEvent) => it && this.dragStart(ev, { kind, item: it }),
        ...this.dropTarget({ kind, slot }),
      },
      it ? this.icon(it) : null,
      it && it.quantity > 1 ? h("span", { class: "qty" }, it.quantity) : null,
    );
  }

  private warehousePanel(): HTMLElement {
    const s = this.state;
    const wh = s.warehouse;
    const p = s.player;
    const whBySlot = new Map((wh?.items ?? []).map((i) => [i.slot, i]));
    const bagBySlot = new Map(p.inventory.map((i) => [i.slot, i]));
    const size = wh?.slots ?? 0;
    return h(
      "section",
      { class: "panel", "data-panel": "warehouse" },
      h("h2", {}, "KHO ĐỒ"),
      h(
        "div",
        { class: "body scroll" },
        h(
          "div",
          { class: "warehouse" },
          h(
            "div",
            { class: "col" },
            h("div", { class: "head" }, `Kho (dùng chung mọi nhân vật) — ${wh?.items.length ?? 0}/${size}`),
            h(
              "div",
              { class: "bag", "data-test": "warehouse", style: `--cols:${WAREHOUSE_COLUMNS}` },
              Array.from({ length: size }, (_, slot) => this.gridCell(whBySlot.get(slot), slot, "wh")),
            ),
          ),
          h(
            "div",
            { class: "col" },
            h("div", { class: "head" }, `Túi đồ — ${p.view.inventoryUsed}/${p.view.inventorySize}`),
            h(
              "div",
              { class: "bag", "data-test": "bag", style: `--cols:${BAG_COLUMNS}` },
              Array.from({ length: p.view.inventorySize }, (_, slot) => this.gridCell(bagBySlot.get(slot), slot, "bag")),
            ),
          ),
        ),
        h("div", { class: "hint", style: "text-align:center;margin-top:8px" }, "Kéo đồ giữa kho và túi, hoặc bấm vào món đồ → [Gửi] / [Rút]. Không cất Zen."),
      ),
    );
  }

  // ---------- Xếp hạng (P6-M1, P6-7) ----------

  private rankingPanel(): HTMLElement {
    const r = this.state.ranking;
    const boards: [string, string][] = [
      ["level", "Tất cả"],
      ["level_DK", "DK"],
      ["level_DW", "DW"],
      ["level_ELF", "ELF"],
      ["level_MG", "MG"],
      ["guild", "Guild"],
    ];
    const guild = r?.board === "guild";
    const me = this.state.player.name;
    const row = (x: RankingPayload["rows"][number]) =>
      guild
        ? h("tr", { "data-rank-row": x.name }, h("td", {}, x.rank), h("td", {}, x.name), h("td", {}, x.master ?? ""), h("td", {}, x.members ?? 0), h("td", {}, x.totalLevel ?? 0))
        : h(
            "tr",
            { "data-rank-row": x.name, class: x.name === me ? "me" : "" },
            h("td", {}, x.rank),
            h("td", {}, x.name),
            h("td", {}, x.class ?? ""),
            h("td", {}, x.level ?? 0),
            h("td", {}, x.guild ?? ""),
          );
    const head = guild ? ["#", "Guild", "Chủ guild", "Người", "Tổng cấp"] : ["#", "Nhân vật", "Class", "Cấp", "Guild"];
    return h(
      "section",
      { class: "panel", "data-panel": "ranking" },
      h("h2", {}, "XẾP HẠNG"),
      h(
        "div",
        { class: "body scroll" },
        h(
          "div",
          { class: "tabs filters" },
          boards.map(([b, label]) => h("button", { class: r?.board === b ? "active" : "", "data-board": b, onclick: () => this.a.ranking(b) }, label)),
        ),
        r
          ? h(
              "div",
              {},
              h("table", { class: "ranking", "data-test": "ranking-table" }, h("tr", {}, head.map((x) => h("th", {}, x))), r.rows.map(row)),
              h(
                "div",
                { class: "hint", "data-test": "ranking-me" },
                r.me ? `Hạng của bạn: #${r.me.rank}${guild ? ` (${r.me.name})` : ""}` : guild ? "Bạn chưa có guild." : "Bạn không có trong bảng này.",
                ` · cập nhật ${new Date(r.updatedAt).toLocaleTimeString("vi-VN")}`,
              ),
            )
          : h("div", { class: "hint" }, "Đang tải…"),
      ),
    );
  }

  // ---------- Nhiệm vụ (P6-M2, P6-2): đang làm / nhận được / đã xong; Quest Master: [Nhận] [Trả] ----------

  private abandonArmed: string | null = null;

  private questPanel(): HTMLElement {
    const q = this.state.quests;
    const npc = this.state.questNpc;
    const itemName = (t: string) => this.state.templates.get(t)?.name ?? t;
    const reward = (r: QuestBrief["rewards"]) => h("div", { class: "qreward" }, "Thưởng: ", rewardText(r, itemName));
    const active = (x: QuestActive) =>
      h(
        "div",
        { class: `quest${x.complete ? " done" : ""}`, "data-quest": x.id },
        h("div", { class: "qname" }, x.complete ? `✔ ${x.name}` : x.name),
        h("div", { class: "qdesc" }, x.description),
        x.objectives.map((o) => h("div", { class: `qgoal${o.have >= o.need ? " ok" : ""}` }, goalText(o, o.have))),
        reward(x.rewards),
        h(
          "div",
          { class: "btns" },
          npc && x.complete ? h("button", { "data-test": "quest-turnin", onclick: () => this.a.questTurnin(x.id) }, "Trả nhiệm vụ") : null,
          this.abandonArmed === x.id
            ? h(
                "span",
                { class: "btns" },
                h("button", { "data-test": "quest-abandon-confirm", onclick: () => ((this.abandonArmed = null), this.a.questAbandon(x.id)) }, "Bỏ thật?"),
                h("button", { onclick: () => ((this.abandonArmed = null), this.renderPanel(true)) }, "Thôi"),
              )
            : h("button", { "data-test": "quest-abandon", onclick: () => ((this.abandonArmed = x.id), this.renderPanel(true)) }, "Bỏ"),
        ),
      );
    const avail = (x: QuestBrief) =>
      h(
        "div",
        { class: "quest", "data-quest": x.id },
        h("div", { class: "qname" }, `${x.name} `, h("small", {}, `(cấp ${x.minLevel})`)),
        h("div", { class: "qdesc" }, x.description),
        x.goals.map((g) => h("div", { class: "qgoal" }, goalText(g))),
        reward(x.rewards),
        npc && (q?.active.length ?? 0) < (q?.maxActive ?? 0)
          ? h("div", { class: "btns" }, h("button", { "data-test": "quest-accept", onclick: () => this.a.questAccept(x.id) }, "Nhận"))
          : null,
      );
    return h(
      "section",
      { class: "panel", "data-panel": "quests" },
      h("h2", {}, npc ? "QUEST MASTER" : "NHIỆM VỤ"),
      h(
        "div",
        { class: "body scroll" },
        q
          ? h(
              "div",
              {},
              h("h3", {}, `Đang làm (${q.active.length}/${q.maxActive})`),
              h("div", { "data-test": "quest-active" }, q.active.length ? q.active.map(active) : h("div", { class: "hint" }, "Chưa nhận nhiệm vụ nào.")),
              h("h3", {}, "Nhận được"),
              npc || !q.available.length ? null : h("div", { class: "hint" }, "Gặp Quest Master ở Lorencia / Noria để nhận."),
              h("div", { "data-test": "quest-available" }, q.available.length ? q.available.map(avail) : h("div", { class: "hint" }, "Không còn nhiệm vụ hợp cấp.")),
              h("div", { class: "hint", "data-test": "quest-done" }, `Đã hoàn thành: ${q.done.length}`),
            )
          : h("div", { class: "hint" }, "Đang tải…"),
      ),
    );
  }

  // dòng theo dõi tiến độ góc màn hình (bấm = mở panel)
  private questTrackEl: HTMLElement | null = null;
  private questTrackKey: string | null = null;

  private renderQuestTracker(): void {
    const act = this.state.quests?.active ?? [];
    const key = JSON.stringify(act.map(trackerLine));
    // dựng lại chỉ khi tiến độ đổi (dựng lại giữa chừng làm mất click)
    if (key === this.questTrackKey && (this.questTrackEl?.isConnected || !act.length)) return;
    this.questTrackKey = key;
    this.questTrackEl?.remove();
    this.questTrackEl = null;
    if (!act.length) return;
    this.questTrackEl = h(
      "div",
      { class: "questtrack", "data-test": "quest-tracker", onclick: () => this.a.togglePanel("quests") },
      act.map((x) => h("div", { class: x.complete ? "ok" : "" }, trackerLine(x))),
    );
    this.view.append(this.questTrackEl);
  }

  // ---------- Chaos Machine (P6-M3, P6-3): bấm đồ trong túi = đặt vào máy; server báo công thức ----------

  private chaosPanel(): HTMLElement {
    const s = this.state;
    const c = s.chaos;
    const ids = new Set(c?.itemIds ?? []);
    const byId = new Map(s.player.inventory.map((i) => [i.id, i]));
    const inMachine = (c?.itemIds ?? []).map((id) => byId.get(id)).filter((i): i is ItemView => !!i);
    const bag = s.player.inventory.filter((i) => !ids.has(i.id)).sort((a, b) => a.slot - b.slot);
    const pct = (r: number) => `${Math.round(r * 1000) / 10}%`;
    const recipe = c?.recipe
      ? h(
          "div",
          { class: "chaosinfo", "data-test": "chaos-recipe" },
          h("b", {}, c.name ?? c.recipe),
          ` · tỉ lệ ${pct(c.rate ?? 0)} · phí ${(c.zen ?? 0).toLocaleString("vi-VN")} Zen`,
        )
      : h("div", { class: "hint", "data-test": "chaos-recipe" }, inMachine.length ? "Không khớp công thức nào." : "Đặt đồ vào máy để xem công thức.");
    const last = c?.result
      ? h(
          "div",
          { class: c.result.ok ? "good" : "bad", "data-test": "chaos-result" },
          c.result.ok ? `Thành công: ${s.templates.get(c.result.templateId ?? "")?.name ?? c.result.templateId}!` : "Thất bại — đồ đặt vào đã mất.",
        )
      : null;
    return h(
      "section",
      { class: "panel", "data-panel": "chaos" },
      h("h2", {}, "CHAOS MACHINE"),
      h(
        "div",
        { class: "body scroll" },
        last,
        h(
          "div",
          { class: "bag tradegrid", "data-test": "chaos-machine", style: "--cols:4" },
          inMachine.map((it) => this.tradeCell(it, { "data-chaos-in": it.id, onclick: () => this.a.chaosToggle(it.id) })),
        ),
        recipe,
        h(
          "div",
          { class: "guildform" },
          h("button", { "data-test": "chaos-combine", disabled: !c?.recipe || (c.zen ?? 0) > s.player.zen, onclick: () => this.a.chaosCombine() }, "⚗ Kết hợp"),
        ),
        h("div", { class: "hint" }, `Tối đa ${c?.maxItems ?? 8} món. Tạo cánh: 1 vũ khí / giáp / khiên +4 trở lên + 1 Jewel of Chaos. Thất bại mất hết đồ đặt vào.`),
        h("div", { class: "head" }, "Túi đồ"),
        h(
          "div",
          { class: "bag", "data-test": "chaos-bag", style: `--cols:${BAG_COLUMNS}` },
          bag.map((it) => this.tradeCell(it, { "data-chaos-bag": it.id, onclick: () => this.a.chaosToggle(it.id) })),
        ),
      ),
    );
  }

  // ---------- Giao dịch (P5-M4, P5-5): hai bàn + túi; bấm đồ trong túi = đặt lên bàn ----------

  private tradeZenDraft = "";

  private tradeCell(it: ItemView, attrs: Record<string, unknown>): HTMLElement {
    const t = this.state.templates.get(it.templateId);
    return h(
      "div",
      { class: "cell", title: itemName(t, it.level, it.templateId), ...attrs },
      this.icon(it),
      it.quantity > 1 ? h("span", { class: "qty" }, it.quantity) : null,
      it.level > 0 ? h("span", { class: "lvl" }, `+${it.level}`) : null,
    );
  }

  private tradePanel(): HTMLElement {
    const s = this.state;
    const tr = s.trade;
    if (!tr || !tr.mine || !tr.theirs) return h("section", { class: "panel", "data-panel": "trade" }, h("h2", {}, "GIAO DỊCH"));
    const mine = tr.mine;
    const theirs = tr.theirs;
    const onTable = new Set(mine.items.map((i) => i.id));
    const bag = s.player.inventory.filter((i) => !onTable.has(i.id)).sort((a, b) => a.slot - b.slot);
    const zen = h("input", { type: "number", min: 0, max: s.player.zen, "data-test": "trade-zen", value: this.tradeZenDraft || String(mine.zen) }) as HTMLInputElement;
    zen.addEventListener("input", () => (this.tradeZenDraft = zen.value));
    // panel có thể vẽ lại giữa lúc gõ và bấm (event của bên kia): đọc bản nháp, không đọc ô cũ
    const setZen = () => {
      const n = Math.max(0, Math.floor(Number(this.tradeZenDraft || zen.value) || 0));
      this.tradeZenDraft = "";
      this.a.tradeZen(n);
    };
    zen.addEventListener("keydown", (ev: KeyboardEvent) => ev.key === "Enter" && setZen());
    const status = (sd: { locked: boolean; confirmed: boolean }) =>
      sd.confirmed ? "✔ Đã đồng ý" : sd.locked ? "🔒 Đã khóa" : "Đang sắp xếp…";
    const side = (title: string, sd: typeof mine, own: boolean) =>
      h(
        "div",
        { class: `tradeside${sd.locked ? " locked" : ""}`, "data-test": own ? "trade-mine" : "trade-theirs" },
        h("div", { class: "head" }, title, h("span", { class: "tstatus" }, status(sd))),
        h(
          "div",
          { class: "bag tradegrid", style: "--cols:4" },
          sd.items.map((it) =>
            this.tradeCell(it, own ? { "data-trade-mine": it.id, onclick: () => !mine.locked && this.a.tradeTake(it.id) } : { "data-trade-theirs": it.id }),
          ),
        ),
        h("div", { class: "tzen" }, `Zen: ${sd.zen.toLocaleString("vi-VN")}`),
      );
    const bothLocked = mine.locked && theirs.locked;
    return h(
      "section",
      { class: "panel", "data-panel": "trade" },
      h("h2", {}, `GIAO DỊCH · ${tr.partner}`),
      h(
        "div",
        { class: "body scroll" },
        tr.error ? h("div", { class: "bad", "data-test": "trade-error" }, ERROR_TEXT[tr.error as ErrorCode] ?? `Lỗi: ${tr.error}`) : null,
        h("div", { class: "tradesides" }, side("Của bạn", mine, true), side(`Của ${tr.partner}`, theirs, false)),
        h(
          "div",
          { class: "guildform" },
          zen,
          h("button", { "data-test": "trade-zen-set", disabled: mine.locked, onclick: setZen }, "Đặt Zen"),
        ),
        h(
          "div",
          { class: "guildform" },
          h("button", { "data-test": "trade-lock", disabled: mine.locked, onclick: () => this.a.tradeLock() }, "🔒 Khóa"),
          h("button", { "data-test": "trade-confirm", disabled: !bothLocked || mine.confirmed, onclick: () => this.a.tradeConfirm() }, "✔ Đồng ý"),
          h("button", { class: "danger", "data-test": "trade-cancel", onclick: () => this.a.tradeCancel() }, "Hủy"),
        ),
        h("div", { class: "hint" }, "Bấm đồ trong túi để đặt lên bàn, bấm đồ trên bàn của bạn để lấy lại. Khóa xong mới đồng ý được; bên nào thay đổi thì cả hai phải khóa lại."),
        h("div", { class: "head" }, "Túi đồ"),
        h(
          "div",
          { class: "bag", "data-test": "trade-bag", style: `--cols:${BAG_COLUMNS}` },
          bag.map((it) => this.tradeCell(it, { "data-trade-bag": it.id, onclick: () => !mine.locked && this.a.tradePut(it.id) })),
        ),
      ),
    );
  }

  // ---------- Guild (P4-M3, P4-5) ----------

  /** Tên đang gõ (giữ qua lần dựng lại panel). */
  private guildDraft = "";
  private guildInviteDraft = "";
  /** Bấm [Giải tán] lần một → hiện nút xác nhận. */
  private guildDisbandArmed = false;

  private guildPanel(): HTMLElement {
    const s = this.state;
    const g = s.guild;
    const cfg = s.guildCfg;
    const me = s.player.name;
    const body = g ? this.guildMembers(g, me) : this.guildCreateForm(cfg);
    return h("section", { class: "panel", "data-panel": "guild" }, h("h2", {}, g ? `GUILD · ${g.name}` : "GUILD"), h("div", { class: "body scroll" }, body));
  }

  private guildCreateForm(cfg: GuildConfig | null): HTMLElement {
    const p = this.state.player;
    const name = h("input", { "data-test": "guild-name", maxlength: 8, placeholder: "Tên guild", value: this.guildDraft }) as HTMLInputElement;
    name.addEventListener("input", () => (this.guildDraft = name.value));
    const lackLevel = cfg ? p.level < cfg.createLevel : false;
    const lackZen = cfg ? p.zen < cfg.createZen : false;
    const create = () => {
      const v = name.value.trim();
      if (cfg && !validGuildName(v, cfg.namePattern)) return this.flashHint(hint, "Tên 3–8 ký tự, chỉ chữ cái không dấu và số.");
      this.a.guildCreate(v);
    };
    const hint = h("div", { class: "hint", "data-test": "guild-hint" }, cfg ? "Tên 3–8 ký tự, chữ cái không dấu và số." : "");
    return h(
      "div",
      { class: "charsheet" },
      h("div", {}, "Bạn chưa có guild."),
      cfg
        ? h(
            "div",
            { class: "guildreq", "data-test": "guild-req" },
            h("div", { class: lackLevel ? "bad" : "" }, `Cần cấp ${cfg.createLevel} (bạn: ${p.level})`),
            h("div", { class: lackZen ? "bad" : "" }, `Phí ${cfg.createZen.toLocaleString("vi-VN")} Zen (bạn: ${p.zen.toLocaleString("vi-VN")})`),
          )
        : null,
      h("div", { class: "guildform" }, name, h("button", { "data-test": "guild-create", disabled: lackLevel || lackZen, onclick: create }, "Tạo guild")),
      hint,
      h("div", { class: "hint" }, "Hoặc nhờ chủ / phó guild mời bạn."),
    );
  }

  /** Guild war trong panel: đang war → điểm; master chưa war → ô tuyên chiến. */
  private warDraft = "";

  private warSection(role: string | null): HTMLElement | null {
    const w = this.state.war;
    if (w) {
      return h(
        "div",
        { class: "kv", "data-test": "guild-war-info" },
        h("span", {}, `⚔ Chiến tranh với ${w.enemy}`),
        h("span", {}, `${w.score} – ${w.enemyScore} (đến ${w.scoreToWin})`),
      );
    }
    if (role !== "master") return null;
    const name = h("input", { "data-test": "guild-war-name", maxlength: 8, placeholder: "Tên guild địch", value: this.warDraft }) as HTMLInputElement;
    name.addEventListener("input", () => (this.warDraft = name.value));
    const declare = () => {
      const v = name.value.trim();
      if (!v) return;
      this.warDraft = "";
      this.a.warDeclare(v);
    };
    return h("div", { class: "guildform" }, name, h("button", { "data-test": "guild-war-declare", onclick: declare }, "⚔ Tuyên chiến"));
  }

  private flashHint(el: HTMLElement, text: string): void {
    el.textContent = text;
    el.classList.add("bad");
  }

  private guildMembers(g: GuildPayload, me: string): HTMLElement {
    const role = myRole(g, me);
    const cfg = this.state.guildCfg;
    const maxA = cfg?.maxAssistants ?? 0;
    const online = g.members.filter((m) => m.online).length;
    const invite = h("input", { "data-test": "guild-invite-name", placeholder: "Tên nhân vật", value: this.guildInviteDraft }) as HTMLInputElement;
    invite.addEventListener("input", () => (this.guildInviteDraft = invite.value));
    const sendInvite = () => {
      const v = invite.value.trim();
      if (!v) return;
      this.guildInviteDraft = "";
      this.a.guildInvite(v);
    };
    return h(
      "div",
      { class: "charsheet" },
      h("div", { class: "kv" }, h("span", {}, "Chủ guild"), h("span", {}, g.master ?? "?")),
      h("div", { class: "kv" }, h("span", {}, "Thành viên"), h("span", { "data-test": "guild-count" }, `${g.members.length}/${cfg?.maxMembers ?? "?"} · ${online} online`)),
      h("hr", { class: "sep" }),
      h(
        "div",
        { class: "guildlist" },
        g.members.map((m) =>
          h(
            "div",
            { class: `gm${m.online ? "" : " off"}`, "data-guild-member": m.name, "data-role": m.role },
            h("span", { class: `dot${m.online ? " on" : ""}`, title: m.online ? "Online" : "Offline" }),
            h("span", { class: "gmname" }, m.name),
            h("span", { class: "gmsub" }, `${ROLE_LABEL[m.role]} · ${m.class} Lv${m.level}`),
            m.name !== me && canPromote(role, m.role, g, maxA)
              ? h("button", { "data-guild-promote": m.name, title: "Phong phó guild", onclick: () => this.a.guildPromote(m.name) }, "▲")
              : null,
            m.name !== me && canDemote(role, m.role)
              ? h("button", { "data-guild-demote": m.name, title: "Hạ xuống thành viên", onclick: () => this.a.guildDemote(m.name) }, "▼")
              : null,
            m.name !== me && canKick(role, m.role)
              ? h("button", { "data-guild-kick": m.name, title: "Mời ra khỏi guild", onclick: () => this.a.guildKick(m.name) }, "✕")
              : null,
          ),
        ),
      ),
      canGuildInvite(role)
        ? h("div", { class: "guildform" }, invite, h("button", { "data-test": "guild-invite", onclick: sendInvite }, "Mời"))
        : null,
      this.warSection(role),
      h("hr", { class: "sep" }),
      role === "master"
        ? this.guildDisbandArmed
          ? h(
              "div",
              { class: "guildform" },
              h("span", { class: "bad" }, "Giải tán guild?"),
              h("button", { "data-test": "guild-disband-confirm", onclick: () => ((this.guildDisbandArmed = false), this.a.guildDisband()) }, "Giải tán"),
              h("button", { onclick: () => ((this.guildDisbandArmed = false), this.renderPanel(true)) }, "Thôi"),
            )
          : h("button", { "data-test": "guild-disband", onclick: () => ((this.guildDisbandArmed = true), this.renderPanel(true)) }, "Giải tán guild")
        : h("button", { "data-test": "guild-leave", onclick: () => this.a.guildLeave() }, "Rời guild"),
      h("div", { class: "hint" }, "Chat guild: gõ /g nội dung"),
    );
  }

  private settingsPanel(): HTMLElement {
    return h(
      "section",
      { class: "panel", "data-panel": "settings" },
      h("h2", {}, "CÀI ĐẶT"),
      h(
        "div",
        { class: "body" },
        h(
          "div",
          { class: "charsheet" },
          h(
            "label",
            { class: "kv" },
            h("span", {}, "Âm thanh"),
            h("input", {
              type: "checkbox",
              style: "width:auto",
              checked: this.state.soundOn,
              onchange: (ev: Event) => this.a.setSound((ev.target as HTMLInputElement).checked),
            }),
          ),
          h("hr", { class: "sep" }),
          h("button", { onclick: () => this.a.logout() }, "🚪 Đăng xuất"),
        ),
      ),
    );
  }

  // ---------- Tooltip (§19.5), context menu quái (§19.9) ----------

  private showTooltip(item: ItemView, ev: MouseEvent, opts: { unequip?: number; bag?: boolean; deposit?: boolean; withdraw?: boolean }): void {
    this.hideTooltip();
    const t = this.state.templates.get(item.templateId);
    if (!t) return;
    const reqs = requirements(t, this.state.player);
    // đồ trong túi: nút thay cho kéo thả (mobile) — Trang bị / Dùng / Tách / Vứt
    const qty = h("input", { type: "number", min: 1, max: item.quantity - 1, value: defaultSplit(item.quantity), "data-test": "split-qty" }) as HTMLInputElement;
    const bagBtns = opts.bag
      ? h(
          "div",
          { class: "btns" },
          t.slot ? h("button", { onclick: () => (this.hideTooltip(), this.a.equip(item)) }, "Trang bị") : null,
          t.potionType ? h("button", { onclick: () => (this.hideTooltip(), this.a.useItem(item)) }, "Dùng") : null,
          // P5-M2: chọn đồ để ép (thay cho kéo thả trên mobile)
          t.type === "JEWEL"
            ? h("button", { "data-test": "jewel-aim", onclick: () => (this.hideTooltip(), (this.jewelAim = item), this.renderPanel(true)) }, "Ép lên…")
            : null,
          t.stackable && item.quantity > 1
            ? h(
                "span",
                { class: "split" },
                qty,
                h("button", { onclick: () => (this.hideTooltip(), this.a.split(item, Number(qty.value))) }, "Tách"),
              )
            : null,
          h("button", { class: "danger", onclick: (e: MouseEvent) => this.confirmDrop(item, e.clientX, e.clientY) }, "Vứt"),
        )
      : null;
    const tip = h(
      "div",
      { class: "tooltip", "data-test": "tooltip" },
      this.icon(item, "big"),
      h("b", { "data-test": "tt-name" }, item.quantity > 1 ? `${itemName(t, item.level)} ×${item.quantity}` : itemName(t, item.level)),
      h("div", {}, shortDesc(t, item.level, this.state.levelBonus, item.optionLevel ?? 0, this.state.optionBonus)),
      (item.optionLevel ?? 0) > 0
        ? h("div", { class: "opt", "data-test": "tt-option" }, `Option Life +${(item.optionLevel ?? 0) * this.state.optionBonus} ${t.type === "WEAPON" ? "đòn" : "thủ"}`)
        : null,
      reqs.map((r) => h("div", { class: r.ok ? "" : "bad" }, r.value ? `${r.label} ≥ ${r.value}` : r.label)),
      opts.unequip !== undefined ? h("button", { onclick: () => (this.hideTooltip(), this.a.unequip(opts.unequip!)) }, "Tháo") : null,
      bagBtns,
      opts.deposit || opts.withdraw
        ? h(
            "div",
            { class: "btns" },
            opts.deposit
              ? h("button", { "data-test": "deposit", onclick: () => (this.hideTooltip(), this.a.deposit(item)) }, "Gửi")
              : h("button", { "data-test": "withdraw", onclick: () => (this.hideTooltip(), this.a.withdraw(item)) }, "Rút"),
          )
        : null,
    );
    this.place(tip, ev.clientX, ev.clientY);
    this.tip = tip;
  }

  private hideTooltip(): void {
    this.tip?.remove();
    this.tip = null;
  }

  /** Menu nổi tại vị trí click/tap quái, không che quái (đặt lệch xuống-phải). */
  monsterMenu(targetId: string, screenX: number, screenY: number): void {
    this.closeContext();
    // skill đánh quái (SINGLE / AOE) đã học; skill hỗ trợ nằm ở menu người chơi
    const learned = this.state.player.view.skills.filter((sk) => {
      const info = this.state.skills.get(sk);
      return sk !== "basic_attack" && (info?.targetType === "SINGLE" || info?.targetType === "AOE");
    });
    const menu = h(
      "div",
      { class: "ctxmenu", "data-test": "ctxmenu" },
      h("button", { onclick: () => (this.closeContext(), this.a.attack(targetId, null)) }, "Tấn công thường"),
      learned.map((id) =>
        h("button", { onclick: () => (this.closeContext(), this.a.attack(targetId, id)) }, this.state.skills.get(id)?.name ?? id),
      ),
      h("hr", {}),
      h("button", { onclick: () => this.closeContext() }, "Hủy"),
    );
    this.place(menu, screenX + 24, screenY + 8);
    this.ctx = menu;
  }

  /**
   * Menu khi click người chơi (P2-M3): skill hỗ trợ (heal/buff) đã học lên người đó; click chính
   * mình thì thêm skill chọn ô (teleport). Trả false nếu không có gì để hiện.
   */
  /** Đã xác nhận "đánh người NORMAL sẽ bị tính PK" trong phiên này (P4-M1, hỏi một lần). */
  private pvpConfirmed = false;

  playerMenu(
    targetId: string,
    isSelf: boolean,
    screenX: number,
    screenY: number,
    name?: string,
    tile?: { x: number; y: number },
    target?: SpawnPayload,
  ): boolean {
    this.closeContext();
    const mine = this.state.player.view.skills.map((id) => this.state.skills.get(id)).filter((x) => x !== undefined);
    const ally = mine.filter((sk) => sk.targetType === "ALLY");
    const point = isSelf ? mine.filter((sk) => sk.targetType === "POINT") : [];
    // mời vào nhóm (P3-M4): người khác, chưa cùng nhóm, mình chưa có nhóm hoặc là trưởng nhóm
    const party = this.state.party;
    const canInvite =
      !isSelf && name !== undefined && !party?.members.some((m) => m.name === name) && (!party || party.leader === this.state.player.name);
    // tấn công người chơi (P4-M1): đánh thường + skill đơn mục tiêu đã học
    const pvp = this.state.pvp;
    const me = this.state.player;
    const duel = this.state.duel;
    const canAttack =
      !isSelf &&
      target !== undefined &&
      canAttackPlayer(me, target, this.state.map, pvp, {
        duelOpponentId: duel?.opponentId ?? null,
        partyNames: party?.members.map((m) => m.name) ?? [],
      });
    const canDuel = !isSelf && target !== undefined && name !== undefined && canChallenge(me, target, pvp, duel !== null);
    // mời vào guild (P4-M3): mình là chủ / phó guild, người kia chưa có guild
    const canGuild = !isSelf && name !== undefined && target !== undefined && !target.guild && canGuildInvite(myRole(this.state.guild, me.name));
    const singles = canAttack ? mine.filter((sk) => sk.targetType === "SINGLE" && sk.id !== "basic_attack") : [];
    const attack = (skill: string | null) => () => {
      // đối thủ duel: không PK, không hỏi
      if (!this.pvpConfirmed && targetId !== duel?.opponentId && needsConfirm(target!, this.state.war?.enemy ?? null)) return this.confirmPk(targetId, skill, screenX, screenY);
      this.closeContext();
      this.a.attack(targetId, skill);
    };
    // giao dịch (P5-M4): người khác, mình chưa có giao dịch nào (server kiểm tầm / duel)
    const canTrade = !isSelf && name !== undefined && this.state.trade === null;
    if (ally.length + point.length === 0 && !canInvite && !canAttack && !canDuel && !canGuild && !canTrade) return false;
    const menu = h(
      "div",
      { class: "ctxmenu", "data-test": "playermenu" },
      // tên người được bấm (đông người dễ bấm nhầm, P4-M2)
      !isSelf && name ? h("div", { class: "menuhead", "data-target-name": name }, name, target?.guild ? h("span", { class: "gtag" }, ` <${target.guild}>`) : null) : null,
      canAttack ? h("button", { "data-test": "pvp-attack", onclick: attack(null) }, "⚔ Tấn công") : null,
      singles.map((sk) => h("button", { "data-pvp-skill": sk.id, onclick: attack(sk.id) }, `⚔ ${sk.name} (${sk.manaCost} MP)`)),
      ally.map((sk) =>
        h("button", { "data-skill": sk.id, onclick: () => (this.closeContext(), this.a.cast(sk.id, isSelf ? null : targetId)) }, `${sk.name} (${sk.manaCost} MP)`),
      ),
      point.map((sk) => h("button", { "data-skill": sk.id, onclick: () => this.a.aim(sk.id) }, `${sk.name}… (${sk.manaCost} MP)`)),
      canDuel ? h("button", { "data-test": "duel-request", onclick: () => (this.closeContext(), this.a.duelRequest(name!)) }, "🤺 Thách đấu") : null,
      canInvite ? h("button", { "data-test": "party-invite", onclick: () => (this.closeContext(), this.a.partyInvite(name!)) }, "👥 Mời vào nhóm") : null,
      canGuild ? h("button", { "data-test": "guild-invite-menu", onclick: () => (this.closeContext(), this.a.guildInvite(name!)) }, "🛡 Mời vào guild") : null,
      canTrade ? h("button", { "data-test": "trade-request", onclick: () => (this.closeContext(), this.a.tradeRequest(name!)) }, "🤝 Giao dịch") : null,
      // bấm trúng người chơi khác giờ mở menu (P3-M4): giữ thao tác đi bằng một mục riêng
      !isSelf && tile ? h("button", { "data-test": "player-goto", onclick: () => (this.closeContext(), this.a.goTo(tile.x, tile.y)) }, "🚶 Đi tới đây") : null,
      h("hr", {}),
      h("button", { onclick: () => this.closeContext() }, "Hủy"),
    );
    this.place(menu, screenX + 24, screenY + 8);
    this.ctx = menu;
    return true;
  }

  /** Hỏi một lần mỗi phiên trước khi đánh người NORMAL (giết sẽ bị tính PK, P4-2). */
  private confirmPk(targetId: string, skill: string | null, x: number, y: number): void {
    this.closeContext();
    const menu = h(
      "div",
      { class: "ctxmenu", "data-test": "pvp-confirm" },
      h("div", { class: "hint", style: "max-width:220px;padding:4px" }, "Người này không có PK. Nếu bạn giết họ, bạn sẽ bị tính điểm PK (Cảnh báo → Sát nhân)."),
      h(
        "button",
        {
          "data-test": "pvp-confirm-yes",
          onclick: () => {
            this.pvpConfirmed = true;
            this.closeContext();
            this.a.attack(targetId, skill);
          },
        },
        "⚔ Vẫn tấn công",
      ),
      h("button", { onclick: () => this.closeContext() }, "Hủy"),
    );
    this.place(menu, x + 24, y + 8);
    this.ctx = menu;
  }

  closeContext(): void {
    this.ctx?.remove();
    this.ctx = null;
  }

  private place(el: HTMLElement, x: number, y: number): void {
    this.view.append(el);
    const r = this.view.getBoundingClientRect();
    const w = el.offsetWidth;
    const hgt = el.offsetHeight;
    el.style.left = `${Math.max(4, Math.min(x - r.left, r.width - w - 4))}px`;
    el.style.top = `${Math.max(4, Math.min(y - r.top, r.height - hgt - 4))}px`;
  }

  // ---------- Nút mobile (§19.16), thanh mạng ----------

  private renderMobile(): void {
    const v = this.state.player.view;
    this.mobile.classList.toggle("show", this.state.panel === null);
    const btn = (icon: string, n: number | null, onclick: () => void, test: string) =>
      h("button", { class: n === 0 ? "gray" : "", "data-mobile": test, onclick }, icon, n === null ? null : h("small", {}, n));
    mount(
      this.mobile,
      btn("🧪", v.potions.HP, () => this.a.usePotion("HP"), "hp"),
      btn("💧", v.potions.MP, () => this.a.usePotion("MP"), "mp"),
      btn("✋", null, () => this.a.pickupNearest(), "pickup"),
      btn("💬", null, () => this.openChat(), "chat"),
    );
  }

  private renderNet(): void {
    this.view.querySelector(".netbar")?.remove();
    this.view.querySelector(".aimbar")?.remove();
    this.view.querySelector(".buffbar")?.remove();
    // buff đang có (P2-M3): góc trên phải vùng game, đếm ngược theo giờ server
    const buffs = this.state.player.view.buffs;
    if (buffs.length)
      this.view.append(
        h(
          "div",
          { class: "buffbar", "data-test": "buffs" },
          buffs.map((b) =>
            h(
              "span",
              { class: "buff", "data-buff": b.id, title: this.state.skills.get(b.id)?.name ?? b.id },
              `${BUFF_ICON[b.stat] ?? "✦"}+${b.value} ${Math.max(0, Math.ceil((b.expiresAt - this.state.serverNow) / 1000))}s`,
            ),
          ),
        ),
      );
    this.renderParty();
    this.renderDuel();
    this.renderGuildAsk();
    this.renderWar();
    this.renderTradeAsk();
    this.renderQuestTracker();
    if (this.state.netStatus) this.view.append(h("div", { class: "netbar" }, this.state.netStatus));
    if (this.state.aiming) {
      const name = this.state.skills.get(this.state.aiming)?.name ?? this.state.aiming;
      this.view.append(h("div", { class: "aimbar", "data-test": "aimbar" }, `${name}: chọn ô đích (Esc để hủy)`));
    }
  }

  // ---------- Nhóm (P3-M4, P3-5 (5)) ----------

  // ---------- Duel (P4-M2): thanh đối thủ + đếm giờ + [Đầu hàng]; hộp lời mời ----------

  private duelEl: HTMLElement | null = null;
  private duelKeyShown: string | null = null;

  private renderDuel(): void {
    const s = this.state;
    const ask = s.duelAsk;
    const askLeft = ask ? Math.max(0, Math.ceil((ask.until - Date.now()) / 1000)) : 0;
    const left = s.duel ? Math.max(0, Math.ceil((s.duel.endsAt - s.serverNow) / 1000)) : 0;
    const key = JSON.stringify([s.duel?.opponent, left, ask?.from, askLeft]);
    if (key === this.duelKeyShown && this.duelEl?.isConnected) return;
    this.duelKeyShown = key;
    this.duelEl?.remove();
    this.duelEl = null;
    const bar = s.duel
      ? h(
          "div",
          { class: "duelbar", "data-test": "duel-bar" },
          h("span", {}, `🤺 Đấu với ${s.duel.opponent} — ${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`),
          h("button", { "data-test": "duel-surrender", onclick: () => this.a.duelCancel() }, "Đầu hàng"),
        )
      : null;
    const box =
      ask && askLeft > 0
        ? h(
            "div",
            { class: "partyask duelask", "data-test": "duel-ask" },
            h("div", {}, `${ask.from} thách đấu tay đôi (${askLeft}s)`),
            h(
              "div",
              { class: "btns" },
              h("button", { "data-test": "duel-accept", onclick: () => this.a.duelAnswer(ask.from, true) }, "Nhận"),
              h("button", { "data-test": "duel-decline", onclick: () => this.a.duelAnswer(ask.from, false) }, "Từ chối"),
            ),
          )
        : null;
    if (!bar && !box) return;
    this.duelEl = h("div", { class: "partyhost" }, bar, box);
    this.view.append(this.duelEl);
  }

  // ---------- Guild (P4-M3): hộp lời mời ----------

  private guildAskEl: HTMLElement | null = null;
  private guildAskKey: string | null = null;

  private renderGuildAsk(): void {
    const inv = this.state.guildInvite;
    const left = inv ? Math.max(0, Math.ceil((inv.until - Date.now()) / 1000)) : 0;
    const key = JSON.stringify([inv?.guild, inv?.from, left]);
    if (key === this.guildAskKey && (this.guildAskEl?.isConnected || !inv)) return;
    this.guildAskKey = key;
    this.guildAskEl?.remove();
    this.guildAskEl = null;
    if (!inv || left <= 0) return;
    this.guildAskEl = h(
      "div",
      { class: "partyhost" },
      h(
        "div",
        { class: "partyask guildask", "data-test": "guild-ask" },
        h("div", {}, `${inv.from} mời bạn vào guild ${inv.guild} (${left}s)`),
        h(
          "div",
          { class: "btns" },
          h("button", { "data-test": "guild-accept", onclick: () => this.a.guildAnswer(inv.guild, true) }, "Đồng ý"),
          h("button", { "data-test": "guild-decline", onclick: () => this.a.guildAnswer(inv.guild, false) }, "Từ chối"),
        ),
      ),
    );
    this.view.append(this.guildAskEl);
  }

  // ---------- Giao dịch (P5-M4): hộp lời mời ----------

  private tradeAskEl: HTMLElement | null = null;
  private tradeAskKey: string | null = null;

  private renderTradeAsk(): void {
    const ask = this.state.tradeAsk;
    const left = ask ? Math.max(0, Math.ceil((ask.until - Date.now()) / 1000)) : 0;
    const key = JSON.stringify([ask?.from, left]);
    if (key === this.tradeAskKey && (this.tradeAskEl?.isConnected || !ask)) return;
    this.tradeAskKey = key;
    this.tradeAskEl?.remove();
    this.tradeAskEl = null;
    if (!ask || left <= 0) return;
    this.tradeAskEl = h(
      "div",
      { class: "partyhost" },
      h(
        "div",
        { class: "partyask tradeask", "data-test": "trade-ask" },
        h("div", {}, `${ask.from} muốn giao dịch với bạn (${left}s)`),
        h(
          "div",
          { class: "btns" },
          h("button", { "data-test": "trade-accept", onclick: () => this.a.tradeAnswer(ask.from, true) }, "Đồng ý"),
          h("button", { "data-test": "trade-decline", onclick: () => this.a.tradeAnswer(ask.from, false) }, "Từ chối"),
        ),
      ),
    );
    this.view.append(this.tradeAskEl);
  }

  // ---------- Guild war (P4-M4): thanh war (điểm, giờ, [Đầu hàng] cho master) + hộp tuyên chiến ----------

  private warEl: HTMLElement | null = null;
  private warKey: string | null = null;
  private surrenderArmed = false;

  private renderWar(): void {
    const s = this.state;
    const w = s.war;
    const ask = s.warAsk;
    const left = w ? Math.max(0, Math.ceil((w.until - Date.now()) / 1000)) : 0;
    const askLeft = ask ? Math.max(0, Math.ceil((ask.until - Date.now()) / 1000)) : 0;
    const master = myRole(s.guild, s.player.name) === "master";
    const key = JSON.stringify([w, left, ask, askLeft, master, this.surrenderArmed]);
    if (key === this.warKey && (this.warEl?.isConnected || (!w && !ask))) return;
    this.warKey = key;
    this.warEl?.remove();
    this.warEl = null;
    if (!w) this.surrenderArmed = false;
    const mmss = (n: number) => `${Math.floor(n / 60)}:${String(n % 60).padStart(2, "0")}`;
    const bar = w
      ? h(
          "div",
          { class: "duelbar warbar", "data-test": "war-bar" },
          h("span", {}, `⚔ ${s.guild?.name ?? ""} ${w.score} – ${w.enemyScore} ${w.enemy} · đến ${w.scoreToWin} · ${mmss(left)}`),
          master
            ? this.surrenderArmed
              ? h(
                  "span",
                  { class: "btns" },
                  h("button", { "data-test": "war-surrender-confirm", onclick: () => ((this.surrenderArmed = false), this.a.warSurrender()) }, "Đầu hàng?"),
                  h("button", { onclick: () => ((this.surrenderArmed = false), this.renderWar()) }, "Thôi"),
                )
              : h("button", { "data-test": "war-surrender", onclick: () => ((this.surrenderArmed = true), this.renderWar()) }, "Đầu hàng")
            : null,
        )
      : null;
    const box =
      ask && askLeft > 0
        ? h(
            "div",
            { class: "partyask warask", "data-test": "war-ask" },
            h("div", {}, `Guild ${ask.enemy} (${ask.from}) tuyên chiến với guild bạn (${askLeft}s)`),
            h(
              "div",
              { class: "btns" },
              h("button", { "data-test": "war-accept", onclick: () => this.a.warAnswer(ask.enemy, true) }, "Nhận"),
              h("button", { "data-test": "war-decline", onclick: () => this.a.warAnswer(ask.enemy, false) }, "Từ chối"),
            ),
          )
        : null;
    if (!bar && !box) return;
    this.warEl = h("div", { class: "partyhost" }, bar, box);
    this.view.append(this.warEl);
  }

  private partyEl: HTMLElement | null = null;
  private partyKeyShown: string | null = null;

  /** Khung nhóm góc trên trái vùng game + hộp lời mời; chỉ dựng lại khi dữ liệu đổi (giữ click). */
  private renderParty(): void {
    const s = this.state;
    const inv = s.partyInvite;
    const left = inv ? Math.max(0, Math.ceil((inv.until - Date.now()) / 1000)) : 0;
    const key = JSON.stringify([s.party, inv?.from, left, s.map.id, s.player.name]);
    if (key === this.partyKeyShown && this.partyEl?.isConnected) return;
    this.partyKeyShown = key;
    this.partyEl?.remove();
    this.partyEl = null;
    const me = s.player.name;
    const party = s.party;
    const lead = party?.leader === me;
    const frame = party
      ? h(
          "div",
          { class: "partyframe", "data-test": "party" },
          party.members.map((m) =>
            h(
              "div",
              { class: `pm${m.online ? "" : " off"}`, "data-member": m.name },
              h(
                "div",
                { class: "pmhead" },
                h("span", { class: "pmname" }, `${m.name === party.leader ? "★ " : ""}${m.name}`),
                h("span", { class: "pmsub" }, `${m.class} Lv${m.level}`),
                lead && m.name !== me
                  ? h("button", { class: "pmkick", title: "Mời ra khỏi nhóm", "data-kick": m.name, onclick: () => this.a.partyKick(m.name) }, "✕")
                  : null,
              ),
              h("div", { class: "bar hp" }, h("div", { class: "fill", style: `width:${pct(m.hp ?? 0, m.maxHp ?? 1)}%` })),
              !m.online ? h("div", { class: "pmnote" }, "Mất kết nối") : m.mapId !== s.map.id ? h("div", { class: "pmnote" }, `Khác map (${m.mapId ?? "?"})`) : null,
            ),
          ),
          h(
            "div",
            { class: "pmbtns" },
            h("button", { "data-test": "party-leave", onclick: () => this.a.partyLeave() }, "Rời nhóm"),
            lead ? h("button", { "data-test": "party-disband", onclick: () => this.a.partyDisband() }, "Giải tán") : null,
          ),
        )
      : null;
    const ask =
      inv && left > 0
        ? h(
            "div",
            { class: "partyask", "data-test": "party-ask" },
            h("div", {}, `${inv.from} mời bạn vào nhóm (${left}s)`),
            h(
              "div",
              { class: "btns" },
              h("button", { "data-test": "party-accept", onclick: () => this.a.partyAnswer(inv.from, true) }, "Đồng ý"),
              h("button", { "data-test": "party-decline", onclick: () => this.a.partyAnswer(inv.from, false) }, "Từ chối"),
            ),
          )
        : null;
    if (!frame && !ask) return;
    this.partyEl = h("div", { class: "partyhost" }, frame, ask);
    this.view.append(this.partyEl);
  }

  // ---------- Phím tắt (§19.2), click ngoài ----------

  private onKey = (ev: KeyboardEvent) => {
    if (!this.state || (ev.target as HTMLElement)?.tagName === "INPUT") return;
    const k = ev.key;
    if (k === "Escape") {
      if (this.jewelAim) (this.jewelAim = null), this.renderPanel(true);
      else if (this.state.aiming) this.a.cancelAim();
      else if (this.ctx) this.closeContext();
      else if (this.menu) this.closeMenu();
      else if (this.tip) this.hideTooltip();
      else this.a.closePanel();
    } else if (k === "c" || k === "C") this.a.togglePanel("character");
    else if (k === "i" || k === "I") this.a.togglePanel("inventory");
    else if (k === "m" || k === "M") this.a.togglePanel("map");
    else if (k === "q" || k === "Q") this.a.usePotion("HP");
    else if (k === "w" || k === "W") this.a.usePotion("MP");
    else if (k === " ") {
      ev.preventDefault();
      this.a.pickupNearest();
    } else if (k === "Enter" && !this.state.panel) {
      ev.preventDefault();
      this.openChat();
    } else return;
  };

  private onOutside = (ev: PointerEvent) => {
    const t = ev.target as Node;
    if (this.menu && !this.menu.contains(t) && !(t as HTMLElement).closest?.('[data-tab="menu"]')) this.closeMenu();
    if (this.ctx && !this.ctx.contains(t)) this.closeContext();
    // chạm ra ngoài khung chat khi ô nhập trống: đóng
    if (this.chatBox.classList.contains("typing") && !this.chatBox.contains(t) && !this.chatInput.value && !(t as HTMLElement).closest?.('[data-mobile="chat"]'))
      this.closeChat();
    if (this.tip && !this.tip.contains(t) && !(t as HTMLElement).closest?.("[data-slot],[data-item]")) this.hideTooltip();
  };

  get mobileLayout(): boolean {
    return isMobile();
  }
}

function pct(cur: number, max: number): number {
  return max > 0 ? Math.max(0, Math.min(100, (cur / max) * 100)) : 0;
}

function ago(at: number): string {
  const s = Math.floor((Date.now() - at) / 1000);
  if (s < 60) return "vừa xong";
  if (s < 3600) return `${Math.floor(s / 60)} phút trước`;
  return `${Math.floor(s / 3600)} giờ trước`;
}

function updateScrollHints(sc: HTMLElement): void {
  const up = sc.querySelector(".scrollhint.up") as HTMLElement | null;
  const down = sc.querySelector(".scrollhint.down") as HTMLElement | null;
  if (up) up.style.visibility = sc.scrollTop > 0 ? "visible" : "hidden";
  if (down) down.style.visibility = sc.scrollTop + sc.clientHeight < sc.scrollHeight - 1 ? "visible" : "hidden";
}
