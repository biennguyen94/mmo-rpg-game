// Game view của Phase 1 bằng Canvas 2D (DEC-53: anh chọn phương án b vì registry npm bị chặn).
// Cài đặt interface GameView nên logic/UI không phụ thuộc thư viện vẽ; PhaserView thay vào ở phase
// sau mà không đổi phần khác (docs/BACKLOG.md).
// Ô 32×32 (KB_ASSETS §3). Tile/sprite: DCSS CC0 (CREDITS.md, assets/mapping.json); ảnh nào thiếu
// hoặc tải lỗi thì vẽ hình học thay thế, không crash (KB_ASSETS §5).
import { nameColor } from "../logic/pvp.js";
import type { CombatPayload, MapData } from "../net/protocol.js";
import type { Entity, World } from "../state/world.js";
import type { GameView, ViewCallbacks } from "./view.js";

const TILE = 32;

/** Tải ảnh; lỗi thì trả null (dùng hình học thay thế). */
function loadImage(src: string): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => {
      console.warn(`Thiếu asset ${src} — dùng placeholder`);
      resolve(null);
    };
    img.src = src;
  });
}

const sprites = new Map<string, HTMLImageElement | null>();

/** Sprite theo entity (id asset trùng id trong data: KB_ASSETS §5). */
function spriteKey(e: Entity): string | null {
  if (e.kind === "monster") return `/assets/sprites/monsters/${e.templateId}.png`;
  if (e.kind === "npc") return `/assets/sprites/npcs/${e.templateId}.png`;
  if (e.kind === "player") return `/assets/sprites/characters/${(e.class ?? "DK").toLowerCase()}/body.png`;
  return null;
}

function sprite(e: Entity): HTMLImageElement | null {
  const key = spriteKey(e);
  if (!key) return null;
  if (!sprites.has(key)) {
    sprites.set(key, null);
    void loadImage(key).then((img) => sprites.set(key, img));
  }
  return sprites.get(key) ?? null;
}

// màu dự phòng theo `legend` khi chưa/không tải được tile
const COLORS: Record<string, string> = {
  grass: "#2f4f2a",
  road: "#6b5a3e",
  town_floor: "#5a5a62",
  wall: "#2b2b33",
  tree: "#1d3a1a",
  water: "#1e3d66",
  rock: "#55524c",
  portal: "#5b3f8a",
};

interface Floater {
  x: number;
  y: number;
  text: string;
  color: string;
  born: number;
}

export function createCanvasView(container: HTMLElement, map: MapData, world: World, cb: ViewCallbacks): GameView {
  const canvas = document.createElement("canvas");
  canvas.setAttribute("data-test", "game-canvas");
  container.prepend(canvas);
  const g = canvas.getContext("2d")!;
  let clock = () => Date.now();
  let selfId = "";
  let marker: { x: number; y: number; at: number } | null = null;
  const floaters: Floater[] = [];
  let cam = { x: 0, y: 0 };
  let raf = 0;

  // tô sẵn nền map: vẽ ngay bằng màu, vẽ lại bằng tile khi tải xong (tiles/{mapId}/{legend}.png)
  const bg = document.createElement("canvas");
  bg.width = map.width * TILE;
  bg.height = map.height * TILE;
  const bgc = bg.getContext("2d")!;
  const paint = (tiles: Map<string, HTMLImageElement | null>) => {
    map.tiles.forEach((row, y) =>
      [...row].forEach((ch, x) => {
        const kind = map.legend[ch];
        const img = tiles.get(kind);
        // cây / cổng có nền trong suốt: vẽ cỏ / đường bên dưới
        const under = kind === "tree" ? tiles.get("grass") : kind === "portal" ? tiles.get("road") : null;
        if (under) bgc.drawImage(under, x * TILE, y * TILE);
        else if (!img) {
          bgc.fillStyle = COLORS[kind] ?? "#000";
          bgc.fillRect(x * TILE, y * TILE, TILE, TILE);
        }
        if (img) bgc.drawImage(img, x * TILE, y * TILE);
        else if (kind === "tree") {
          bgc.fillStyle = "#2d5a27";
          bgc.beginPath();
          bgc.arc(x * TILE + 16, y * TILE + 16, 12, 0, Math.PI * 2);
          bgc.fill();
        }
      }),
    );
    // cổng (P2-M4): nhãn tên map đích + cấp yêu cầu
    for (const p of map.portals ?? []) {
      const label = `→ ${p.to.charAt(0).toUpperCase()}${p.to.slice(1)}${p.levelRequired ? ` (cấp ${p.levelRequired})` : ""}`;
      bgc.font = "bold 12px system-ui";
      bgc.textAlign = "center";
      bgc.fillStyle = "rgba(0,0,0,0.6)";
      const cx = (p.x + p.w / 2) * TILE;
      bgc.fillRect(cx - 50, p.y * TILE - 18, 100, 16);
      bgc.fillStyle = "#e6d7ff";
      bgc.fillText(label, cx, p.y * TILE - 6);
    }
    for (const z of map.safeZones) {
      bgc.strokeStyle = "rgba(217,180,90,0.45)";
      bgc.setLineDash([6, 6]);
      bgc.strokeRect(z.x * TILE + 1, z.y * TILE + 1, z.w * TILE - 2, z.h * TILE - 2);
    }
  };
  paint(new Map());
  const kinds = [...new Set(Object.values(map.legend))];
  void Promise.all(kinds.map((k) => loadImage(`/assets/tiles/${map.id}/${k}.png`))).then((imgs) =>
    paint(new Map(kinds.map((k, i) => [k, imgs[i]]))),
  );

  const resize = () => {
    const r = container.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(r.width * dpr);
    canvas.height = Math.round(r.height * dpr);
    canvas.style.width = `${r.width}px`;
    canvas.style.height = `${r.height}px`;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
  };
  const ro = new ResizeObserver(resize);
  ro.observe(container);
  resize();

  const pos = (e: Entity) => e.interp.at(clock()) ?? { x: e.x, y: e.y };

  const draw = () => {
    raf = requestAnimationFrame(draw);
    const w = canvas.clientWidth;
    const hgt = canvas.clientHeight;
    const me = world.entities.get(selfId);
    if (me) {
      const p = pos(me);
      cam = { x: p.x * TILE + TILE / 2 - w / 2, y: p.y * TILE + TILE / 2 - hgt / 2 };
    }
    g.fillStyle = "#0b0c10";
    g.fillRect(0, 0, w, hgt);
    g.drawImage(bg, -cam.x, -cam.y);

    if (marker && Date.now() - marker.at < 800) {
      g.strokeStyle = "#d9b45a";
      g.strokeRect(marker.x * TILE - cam.x + 4, marker.y * TILE - cam.y + 4, TILE - 8, TILE - 8);
    }

    const order = [...world.entities.values()].sort((a, b) => kindOrder(a) - kindOrder(b));
    for (const e of order) {
      const p = pos(e);
      const cx = p.x * TILE - cam.x + TILE / 2;
      const cy = p.y * TILE - cam.y + TILE / 2;
      if (cx < -TILE || cy < -TILE || cx > w + TILE || cy > hgt + TILE) continue;
      drawEntity(g, e, cx, cy, e.id === selfId);
    }

    const now = Date.now();
    for (let i = floaters.length - 1; i >= 0; i--) {
      const f = floaters[i];
      const age = now - f.born;
      if (age > 900) {
        floaters.splice(i, 1);
        continue;
      }
      g.globalAlpha = 1 - age / 900;
      g.fillStyle = f.color;
      g.font = "bold 14px system-ui";
      g.textAlign = "center";
      g.fillText(f.text, f.x * TILE - cam.x + TILE / 2, f.y * TILE - cam.y - age / 30);
      g.globalAlpha = 1;
    }
  };
  raf = requestAnimationFrame(draw);

  const onPointer = (ev: PointerEvent) => {
    const r = canvas.getBoundingClientRect();
    const wx = (ev.clientX - r.left + cam.x) / TILE;
    const wy = (ev.clientY - r.top + cam.y) / TILE;
    // entity gần điểm bấm nhất (trong 0,75 ô); quái / đồ / NPC thắng người chơi khác (P3-M4: bấm
    // người chơi mở menu — đứng sát quái đang đánh không được che quái). Chính mình (menu tự
    // thân, P2-M3) chỉ thắng người chơi khác khi gần bằng hoặc hơn (nhiều người đứng chung ô hồi
    // sinh → click ô mình là chọn mình)
    let best: Entity | null = null;
    let player: Entity | null = null;
    let self: Entity | null = null;
    let bestD = 0.75;
    let playerD = 0.75;
    let selfD = Infinity;
    for (const e of world.entities.values()) {
      const p = pos(e);
      const d = Math.hypot(p.x + 0.5 - wx, p.y + 0.5 - wy);
      if (e.id === selfId) {
        if (d < 0.75) [self, selfD] = [e, d];
      } else if (e.kind === "player") {
        if (d < playerD) [player, playerD] = [e, d];
      } else if (d < bestD) {
        [best, bestD] = [e, d];
      }
    }
    if (!best && player) [best, bestD] = [player, playerD];
    if (self && (!best || (best.kind === "player" && selfD <= bestD))) best = self;
    if (best) cb.onEntity(best, ev.clientX, ev.clientY, Math.floor(wx), Math.floor(wy));
    else cb.onGround(Math.floor(wx), Math.floor(wy));
  };
  canvas.addEventListener("pointerdown", onPointer);

  return {
    setClock: (fn) => (clock = fn),
    setSelf: (id) => (selfId = id),
    setEnemyGuild: (name) => (enemyGuild = name),
    combat: (c: CombatPayload) => {
      const t = world.entities.get(c.target);
      if (!t) return;
      floaters.push({
        x: t.x,
        y: t.y,
        text: c.heal !== undefined ? `+${c.heal}` : c.buff !== undefined ? `▲${c.buff}` : c.dmg > 0 ? String(c.dmg) : "Trượt",
        color:
          c.heal !== undefined
            ? "#7dff8a"
            : c.buff !== undefined
              ? "#7fd3ff"
              : c.target === selfId
                ? "#ff6b6b"
                : c.attacker === selfId
                  ? "#ffe08a"
                  : "#cccccc",
        born: Date.now(),
      });
    },
    marker: (x, y) => (marker = { x, y, at: Date.now() }),
    destroy: () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      canvas.removeEventListener("pointerdown", onPointer);
      canvas.remove();
    },
  };
}

function kindOrder(e: Entity): number {
  return e.kind === "item" ? 0 : e.kind === "npc" ? 1 : e.kind === "monster" ? 2 : 3;
}

// màu cánh theo loại (P6-4 (4): vẽ hình học, không asset MU)
const WING_COLOR: Record<string, [string, string]> = {
  wing_elf: ["rgba(120,220,140,0.85)", "#2f7a45"],
  wing_heaven: ["rgba(235,240,255,0.9)", "#7f8fb8"],
  wing_satan: ["rgba(150,30,40,0.9)", "#3a0a10"],
  // cánh cấp 2 (P7-M3): to hơn, thêm một lớp lông bên trong
  wing_spirit: ["rgba(90,230,200,0.85)", "#1d6b5c"],
  wing_soul: ["rgba(150,170,255,0.88)", "#3b3f8f"],
  wing_dragon: ["rgba(200,150,40,0.9)", "#5a3a08"],
  wing_darkness: ["rgba(70,40,110,0.92)", "#1a0b2e"],
};
const WING_TIER2 = new Set(["wing_spirit", "wing_soul", "wing_dragon", "wing_darkness"]);

/** Đôi cánh sau lưng người chơi: hai nửa đối xứng, đập nhẹ theo thời gian. */
export function drawWings(g: CanvasRenderingContext2D, wing: string, x: number, y: number, dead: boolean): void {
  const [fill, edge] = WING_COLOR[wing] ?? ["rgba(200,200,200,0.85)", "#555"];
  const flap = Math.sin(performance.now() / 300) * 2;
  const tier2 = WING_TIER2.has(wing);
  g.save();
  g.globalAlpha = dead ? 0.35 : 1;
  g.strokeStyle = edge;
  g.lineWidth = 1.5;
  // cấp 2: lớp ngoài to 1,4 lần + lớp trong nhạt hơn
  const layers: [number, string][] = tier2 ? [[1.4, fill], [0.85, "rgba(255,255,255,0.35)"]] : [[1, fill]];
  for (const [k, color] of layers) {
    g.fillStyle = color;
    for (const side of [-1, 1]) {
      const s = side * k;
      g.beginPath();
      g.moveTo(x + side * 3, y - 4);
      g.quadraticCurveTo(x + s * 20, y - (22 + flap) * k, x + s * 22, y - 6 * k);
      g.quadraticCurveTo(x + s * 18, y + 2, x + s * 14, y + (6 + flap / 2) * k);
      g.quadraticCurveTo(x + s * 10, y + 2, x + side * 3, y + 4);
      g.closePath();
      g.fill();
      g.stroke();
    }
  }
  g.restore();
}

function drawEntity(g: CanvasRenderingContext2D, e: Entity, x: number, y: number, self: boolean): void {
  const dead = e.state === "dead";
  const img = sprite(e);
  // P6-M4: cánh vẽ trước (nằm sau thân)
  if (e.kind === "player" && e.wing) drawWings(g, e.wing, x, y, dead);
  if (img) {
    // vòng dưới chân phân biệt mình / người khác / NPC
    if (e.kind !== "monster") {
      g.fillStyle = e.kind === "npc" ? "rgba(217,180,90,0.5)" : self ? "rgba(79,163,255,0.6)" : "rgba(92,207,122,0.55)";
      g.beginPath();
      g.ellipse(x, y + 12, 12, 5, 0, 0, Math.PI * 2);
      g.fill();
    }
    g.globalAlpha = dead ? 0.35 : 1;
    if (e.golden && !dead) {
      // quái vàng (P6-M5): quầng vàng dưới chân
      g.fillStyle = "rgba(255,210,60,0.45)";
      g.beginPath();
      g.ellipse(x, y + 10, 16, 7, 0, 0, Math.PI * 2);
      g.fill();
    }
    // boss (P6-M5): vẽ to gấp rưỡi
    const size = e.boss ? TILE * 1.5 : TILE;
    g.drawImage(img, x - size / 2, y - size / 2 - (e.boss ? 8 : 0), size, size);
    g.globalAlpha = 1;
    label(g, e, x, y, dead);
    return;
  }
  if (e.kind === "item") {
    g.fillStyle = "#e8c66a";
    g.beginPath();
    g.moveTo(x, y - 7);
    g.lineTo(x + 7, y);
    g.lineTo(x, y + 7);
    g.lineTo(x - 7, y);
    g.fill();
    return;
  }
  if (e.kind === "monster") {
    // Spider: thân + 8 chân (hình học)
    g.strokeStyle = dead ? "#555" : "#c9a27a";
    g.lineWidth = 2;
    for (let i = 0; i < 4; i++) {
      const dy = -6 + i * 4;
      g.beginPath();
      g.moveTo(x - 4, y + dy / 2);
      g.lineTo(x - 13, y + dy);
      g.moveTo(x + 4, y + dy / 2);
      g.lineTo(x + 13, y + dy);
      g.stroke();
    }
    g.fillStyle = dead ? "#444" : "#7a3b2e";
    g.beginPath();
    g.arc(x, y, 8, 0, Math.PI * 2);
    g.fill();
  } else {
    g.fillStyle = e.kind === "npc" ? "#d9b45a" : self ? "#4fa3ff" : "#5ccf7a";
    g.beginPath();
    g.arc(x, y, 11, 0, Math.PI * 2);
    g.fill();
    if (dead) {
      g.strokeStyle = "#000";
      g.beginPath();
      g.moveTo(x - 7, y - 7);
      g.lineTo(x + 7, y + 7);
      g.stroke();
    }
  }
  label(g, e, x, y, dead);
}

/** Guild địch đang war (P4-M4): tên vẽ màu tím. Một view sống một lúc nên giữ ở mức module. */
let enemyGuild: string | null = null;

function label(g: CanvasRenderingContext2D, e: Entity, x: number, y: number, dead: boolean): void {
  g.font = "11px system-ui";
  g.textAlign = "center";
  // P4-M3 (P4-5): `<Tên guild>` dưới tên nhân vật — có guild thì tên lên cao một dòng
  const guild = e.kind === "player" && e.guild ? `<${e.guild}>` : null;
  const ny = guild ? y - 32 : y - 20;
  g.fillStyle = "#000";
  const name = e.name;
  g.fillText(name, x + 1, ny + 1);
  // P4-M1: màu tên theo PK; kẻ gây sự nhấp nháy (2 lần / giây)
  g.fillStyle =
    e.kind === "player"
      ? nameColor(e.pkState, e.aggressor, Math.floor(performance.now() / 250) % 2 === 0, enemyGuild !== null && e.guild === enemyGuild)
      : e.boss
        ? "#ff6a5a"
        : e.golden
          ? "#ffd23c"
          : "#fff";
  g.fillText(name, x, ny);
  if (guild) {
    g.fillStyle = "#000";
    g.fillText(guild, x + 1, y - 19);
    g.fillStyle = "#7fc4ff";
    g.fillText(guild, x, y - 20);
  }
  if (e.hp !== null && e.maxHp && e.kind !== "npc" && !dead) {
    // boss: thanh máu dài hơn
    const w = e.boss ? 56 : 28;
    g.fillStyle = "#300";
    g.fillRect(x - w / 2, y + 16, w, 4);
    g.fillStyle = "#d33";
    g.fillRect(x - w / 2, y + 16, (w * Math.max(0, e.hp)) / e.maxHp, 4);
  }
}
