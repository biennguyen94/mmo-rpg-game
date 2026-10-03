// Game view TẠM bằng Canvas 2D (placeholder hình học, KB_ASSETS: chưa có tileset/sprite thật).
// Cài đặt interface GameView để logic không phụ thuộc thư viện vẽ; PhaserView (Phaser 3, đã
// chốt) thay vào khi tải được npm (docs/OPEN_QUESTIONS.md E7). Ô 32×32 (KB_ASSETS §3).
import type { CombatPayload, MapData } from "../net/protocol.js";
import type { Entity, World } from "../state/world.js";
import type { GameView, ViewCallbacks } from "./view.js";

const TILE = 32;

// màu theo `legend` của map (placeholder, không phải asset)
const COLORS: Record<string, string> = {
  grass: "#2f4f2a",
  road: "#6b5a3e",
  town_floor: "#5a5a62",
  wall: "#2b2b33",
  tree: "#1d3a1a",
  water: "#1e3d66",
  rock: "#55524c",
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

  // tô sẵn nền map một lần
  const bg = document.createElement("canvas");
  bg.width = map.width * TILE;
  bg.height = map.height * TILE;
  const bgc = bg.getContext("2d")!;
  map.tiles.forEach((row, y) =>
    [...row].forEach((ch, x) => {
      bgc.fillStyle = COLORS[map.legend[ch]] ?? "#000";
      bgc.fillRect(x * TILE, y * TILE, TILE, TILE);
      if (map.legend[ch] === "tree") {
        bgc.fillStyle = "#2d5a27";
        bgc.beginPath();
        bgc.arc(x * TILE + 16, y * TILE + 16, 12, 0, Math.PI * 2);
        bgc.fill();
      }
    }),
  );
  for (const z of map.safeZones) {
    bgc.strokeStyle = "rgba(217,180,90,0.35)";
    bgc.setLineDash([6, 6]);
    bgc.strokeRect(z.x * TILE + 1, z.y * TILE + 1, z.w * TILE - 2, z.h * TILE - 2);
  }

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
    // entity gần điểm bấm nhất (trong nửa ô), trừ chính mình
    let best: Entity | null = null;
    let bestD = 0.75;
    for (const e of world.entities.values()) {
      if (e.id === selfId) continue;
      const p = pos(e);
      const d = Math.hypot(p.x + 0.5 - wx, p.y + 0.5 - wy);
      if (d < bestD) {
        best = e;
        bestD = d;
      }
    }
    if (best) cb.onEntity(best, ev.clientX, ev.clientY);
    else cb.onGround(Math.floor(wx), Math.floor(wy));
  };
  canvas.addEventListener("pointerdown", onPointer);

  return {
    setClock: (fn) => (clock = fn),
    setSelf: (id) => (selfId = id),
    combat: (c: CombatPayload) => {
      const t = world.entities.get(c.target);
      if (!t) return;
      floaters.push({
        x: t.x,
        y: t.y,
        text: c.dmg > 0 ? String(c.dmg) : "Trượt",
        color: c.target === selfId ? "#ff6b6b" : c.attacker === selfId ? "#ffe08a" : "#cccccc",
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

function drawEntity(g: CanvasRenderingContext2D, e: Entity, x: number, y: number, self: boolean): void {
  const dead = e.state === "dead";
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
  g.font = "11px system-ui";
  g.textAlign = "center";
  g.fillStyle = "#fff";
  g.fillText(e.kind === "npc" ? "Potion Merchant" : e.name, x, y - 18);
  if (e.hp !== null && e.maxHp && e.kind !== "npc" && !dead) {
    g.fillStyle = "#300";
    g.fillRect(x - 14, y + 14, 28, 4);
    g.fillStyle = "#d33";
    g.fillRect(x - 14, y + 14, (28 * Math.max(0, e.hp)) / e.maxHp, 4);
  }
}
