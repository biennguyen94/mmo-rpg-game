// Giao diện trong game theo KB_GAME_DESIGN §19 (DOM phủ lên game view). Chỉ hiển thị số do
// server gửi (`player.view`), không tính công thức, không cập nhật lạc quan: UI đổi khi server trả.
import type { ChatPayload, ItemView, MailView, MapData, Player, ShopPayload, SkillInfo } from "../net/protocol.js";
import { AllocBatcher, type Stat } from "../logic/alloc.js";
import { iconPath, type IconMap } from "../logic/icons.js";
import {
  BAG_COLUMNS,
  EQUIP_GRID,
  SLOT_LABEL,
  defaultSplit,
  dragCommand,
  equipmentInBag,
  requirements,
  shortDesc,
  type DragEnd,
  type DragStart,
  type ItemCommand,
  type Templates,
} from "../logic/items.js";
import { NOTICE_ICON, type NoticeLog } from "../logic/notices.js";
import { chatLine } from "../logic/chat.js";
import { clear, h, mount } from "./dom.js";

export type PanelName = "character" | "inventory" | "map" | "notices" | "mail" | "shop" | "settings";

export interface UiState {
  player: Player;
  map: MapData;
  templates: Templates;
  skills: Map<string, SkillInfo>;
  iconMap: IconMap | null;
  notices: NoticeLog;
  panel: PanelName | null;
  shop: ShopPayload | null;
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
  usePotion(type: "HP" | "MP"): void;
  pickupNearest(): void;
  logout(): void;
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
      h("button", { onclick: () => (this.closeMenu(), this.a.togglePanel("settings")) }, "⚙️ Cài đặt"),
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
          : s.panel === "settings"
            ? s.soundOn
            : s.panel === "mail"
              ? [this.mailFilter, s.mail, Math.floor(Date.now() / 60_000)]
              : s.panel === "map"
                ? [s.map.id, s.player.x, s.player.y]
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
          h("hr", { class: "sep" }),
          kv("Dmg", `${v.attackMin} ~ ${v.attackMax}`),
          kv("Defense", v.defense),
          kv("Atk Speed", v.attackSpeed),
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
        const locked = slot === 7; // features.wings = false (Phase 1)
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
          onclick: (ev: MouseEvent) => it && this.showTooltip(it, ev, { bag: true }),
          ondragstart: (ev: DragEvent) => it && this.dragStart(ev, { kind: "bag", item: it }),
          ...this.dropTarget({ kind: "bag", slot }),
        },
        it ? this.icon(it) : null,
        it && it.quantity > 1 ? h("span", { class: "qty" }, it.quantity) : null,
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
        const c = dragCommand(from, to, this.state.player, this.state.templates);
        if (!c) return;
        if (c.confirm) this.confirmDrop(from.item, ev.clientX, ev.clientY);
        else this.a.itemCommand(c);
      },
    };
  }

  /** Hỏi trước khi vứt (P2-8): vứt cả stack xuống ô đang đứng. */
  private confirmDrop(item: ItemView, x: number, y: number): void {
    this.hideTooltip();
    const name = this.state.templates.get(item.templateId)?.name ?? item.templateId;
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

  private showTooltip(item: ItemView, ev: MouseEvent, opts: { unequip?: number; bag?: boolean }): void {
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
      h("b", {}, item.quantity > 1 ? `${t.name} ×${item.quantity}` : t.name),
      h("div", {}, shortDesc(t)),
      reqs.map((r) => h("div", { class: r.ok ? "" : "bad" }, r.value ? `${r.label} ≥ ${r.value}` : r.label)),
      opts.unequip !== undefined ? h("button", { onclick: () => (this.hideTooltip(), this.a.unequip(opts.unequip!)) }, "Tháo") : null,
      bagBtns,
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
  playerMenu(targetId: string, isSelf: boolean, screenX: number, screenY: number): boolean {
    this.closeContext();
    const mine = this.state.player.view.skills.map((id) => this.state.skills.get(id)).filter((x) => x !== undefined);
    const ally = mine.filter((sk) => sk.targetType === "ALLY");
    const point = isSelf ? mine.filter((sk) => sk.targetType === "POINT") : [];
    if (ally.length + point.length === 0) return false;
    const menu = h(
      "div",
      { class: "ctxmenu", "data-test": "playermenu" },
      ally.map((sk) =>
        h("button", { "data-skill": sk.id, onclick: () => (this.closeContext(), this.a.cast(sk.id, isSelf ? null : targetId)) }, `${sk.name} (${sk.manaCost} MP)`),
      ),
      point.map((sk) => h("button", { "data-skill": sk.id, onclick: () => this.a.aim(sk.id) }, `${sk.name}… (${sk.manaCost} MP)`)),
      h("hr", {}),
      h("button", { onclick: () => this.closeContext() }, "Hủy"),
    );
    this.place(menu, screenX + 24, screenY + 8);
    this.ctx = menu;
    return true;
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
    if (this.state.netStatus) this.view.append(h("div", { class: "netbar" }, this.state.netStatus));
    if (this.state.aiming) {
      const name = this.state.skills.get(this.state.aiming)?.name ?? this.state.aiming;
      this.view.append(h("div", { class: "aimbar", "data-test": "aimbar" }, `${name}: chọn ô đích (Esc để hủy)`));
    }
  }

  // ---------- Phím tắt (§19.2), click ngoài ----------

  private onKey = (ev: KeyboardEvent) => {
    if (!this.state || (ev.target as HTMLElement)?.tagName === "INPUT") return;
    const k = ev.key;
    if (k === "Escape") {
      if (this.state.aiming) this.a.cancelAim();
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
