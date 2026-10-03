// Điểm vào client: đăng nhập → nhân vật → game. Dữ liệu tĩnh nhận lúc join (KB_TECH_STACK §6);
// icon_map.json tải một lần (thiếu file thì mọi item dùng placeholder, không crash).
import { loadToken, saveToken, type CharacterSummary } from "./net/api.js";
import type { IconMap } from "./logic/icons.js";
import { GameClient } from "./game/game.js";
import { h, mount } from "./ui/dom.js";
import { characterScreen, loginScreen } from "./ui/screens.js";
import { createCanvasView } from "./view/canvas_view.js";

const root = document.getElementById("app")!;
let iconMap: IconMap | null = null;

async function loadIconMap(): Promise<void> {
  try {
    const r = await fetch("/assets/icon_map.json");
    if (r.ok) iconMap = await r.json();
    else console.warn("Chưa có icon_map.json — dùng placeholder (chạy mix mu.icons.index)");
  } catch {
    console.warn("Không tải được icon_map.json — dùng placeholder");
  }
}

function toLogin(message?: string): void {
  loginScreen(root, (token) => toCharacters(token));
  if (message) root.querySelector(".error")!.textContent = message;
}

function toCharacters(token: string): void {
  characterScreen(root, token, (c) => toGame(token, c), () => {
    saveToken(null);
    toLogin();
  }).catch(() => {
    mount(root, h("div", { class: "screen" }, h("div", { class: "card" }, "Không kết nối được server.", h("button", { onclick: () => toCharacters(token) }, "Thử lại"))));
  });
}

function toGame(token: string, c: CharacterSummary): void {
  const game = new GameClient(
    root,
    token,
    c,
    createCanvasView,
    (reason) => {
      const token = loadToken();
      if (!token) return toLogin(reason);
      toCharacters(token);
      // vd. bị đá vì vào game ở tab khác: hiện lý do trên màn hình nhân vật
      if (reason) setTimeout(() => root.querySelector(".card")?.prepend(h("div", { class: "error" }, reason)), 300);
    },
    iconMap,
  );
  game.start();
}

void loadIconMap().then(() => {
  const token = loadToken();
  if (token) toCharacters(token);
  else toLogin();
});
