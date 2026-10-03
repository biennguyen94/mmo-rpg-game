// Màn hình trước khi vào game: đăng nhập/đăng ký → chọn/tạo nhân vật (Phase 3, P3-3: tối đa
// `maxCharacters` nhân vật / tài khoản, chưa cho xóa; MG khóa tới khi có nhân vật đạt cấp mở, P3-M5).
import { api, saveToken, type ApiError, type CharacterSummary, type ClassOption } from "../net/api.js";
import { h, mount } from "./dom.js";

export function loginScreen(root: HTMLElement, onToken: (token: string) => void): void {
  let registering = false;
  const user = h("input", { name: "username", placeholder: "Tên đăng nhập", autocomplete: "username" }) as HTMLInputElement;
  const pass = h("input", { name: "password", type: "password", placeholder: "Mật khẩu", autocomplete: "current-password" }) as HTMLInputElement;
  const err = h("div", { class: "error", role: "alert" });
  const submit = h("button", { type: "submit" }, "Đăng nhập") as HTMLButtonElement;
  const toggle = h("button", { type: "button", class: "link" }, "Chưa có tài khoản? Đăng ký");

  toggle.addEventListener("click", () => {
    registering = !registering;
    submit.textContent = registering ? "Đăng ký" : "Đăng nhập";
    toggle.textContent = registering ? "Đã có tài khoản? Đăng nhập" : "Chưa có tài khoản? Đăng ký";
    err.textContent = "";
  });

  const form = h(
    "form",
    {
      class: "card",
      onsubmit: async (ev: Event) => {
        ev.preventDefault();
        submit.disabled = true;
        err.textContent = "";
        try {
          const r = registering ? await api.register(user.value, pass.value) : await api.login(user.value, pass.value);
          saveToken(r.token);
          onToken(r.token);
        } catch (e) {
          err.textContent = (e as ApiError).message ?? "Lỗi kết nối";
        } finally {
          submit.disabled = false;
        }
      },
    },
    h("h1", {}, "MU Web"),
    user,
    pass,
    err,
    submit,
    toggle,
  );

  mount(root, h("div", { class: "screen" }, form));
  user.focus();
}

export async function characterScreen(
  root: HTMLElement,
  token: string,
  onEnter: (c: CharacterSummary) => void,
  onLogout: () => void,
): Promise<void> {
  let list: CharacterSummary[];
  let classes: ClassOption[];
  let max: number;
  try {
    ({ characters: list, classes, maxCharacters: max } = await api.characters(token));
  } catch (e) {
    if ((e as ApiError).status === 401) return onLogout();
    throw e;
  }
  if (list.length === 0) return createScreen(root, token, classes, onEnter, onLogout, null);

  const logout = h("button", { type: "button", class: "link", onclick: onLogout }, "Đăng xuất");
  const mapName = (id: string) => id.charAt(0).toUpperCase() + id.slice(1);
  mount(
    root,
    h(
      "div",
      { class: "screen" },
      h(
        "div",
        { class: "card charlist", "data-test": "character-list" },
        h("h1", {}, "Chọn nhân vật"),
        list.map((c, i) =>
          h(
            "div",
            { class: "charrow", "data-character": c.name },
            h("img", { src: `/assets/sprites/characters/${c.class.toLowerCase()}/body.png`, alt: "", draggable: "false" }),
            h("div", { class: "info" }, h("b", {}, c.name), h("div", { class: "hint" }, `${c.class} · Cấp ${c.level} · ${mapName(c.mapId)}`)),
            h("button", { type: "button", "data-enter": c.name, onclick: () => onEnter(c), autofocus: i === 0 }, "Vào game"),
          ),
        ),
        h("div", { class: "hint", style: "text-align:center" }, `${list.length}/${max} nhân vật`),
        list.length < max
          ? h(
              "button",
              { type: "button", class: "secondary", "data-test": "new-character", onclick: () => createScreen(root, token, classes, onEnter, onLogout, () => void characterScreen(root, token, onEnter, onLogout)) },
              "+ Tạo nhân vật",
            )
          : null,
        logout,
      ),
    ),
  );
}

/** Form tạo nhân vật; `back` = quay lại danh sách (null khi chưa có nhân vật nào). */
function createScreen(
  root: HTMLElement,
  token: string,
  classes: ClassOption[],
  onEnter: (c: CharacterSummary) => void,
  onLogout: () => void,
  back: (() => void) | null,
): void {
  const err = h("div", { class: "error", role: "alert" });
  const name = h("input", { name: "name", placeholder: "Tên nhân vật (4–10 chữ/số)", maxlength: 10 }) as HTMLInputElement;
  const submit = h("button", { type: "submit" }, "Tạo nhân vật") as HTMLButtonElement;
  // class do server liệt kê, mục đầu (mặc định) chọn sẵn; class khóa (MG) không chọn được
  let chosen = classes.find((c) => !c.locked)?.id ?? "DK";
  const picker = h(
    "div",
    { class: "classpick", role: "radiogroup", "data-test": "class-picker" },
    classes.map((c) =>
      h(
        "label",
        { class: `classopt${c.locked ? " locked" : ""}`, title: c.locked ? `Cần một nhân vật đạt cấp ${c.unlockLevel}` : "" },
        h("input", { type: "radio", name: "class", value: c.id, checked: c.id === chosen, disabled: c.locked === true, onchange: () => (chosen = c.id) }),
        h("img", { src: `/assets/sprites/characters/${c.id.toLowerCase()}/body.png`, alt: "", draggable: "false" }),
        h("span", {}, `${c.name} (${c.id})`),
        c.locked ? h("small", { class: "lockhint" }, `🔒 cần nhân vật cấp ${c.unlockLevel}`) : null,
      ),
    ),
  );
  mount(
    root,
    h(
      "div",
      { class: "screen" },
      h(
        "form",
        {
          class: "card",
          onsubmit: async (ev: Event) => {
            ev.preventDefault();
            submit.disabled = true;
            try {
              const r = await api.createCharacter(token, name.value, chosen);
              onEnter(r.character);
            } catch (e) {
              err.textContent = (e as ApiError).message;
            } finally {
              submit.disabled = false;
            }
          },
        },
        h("h1", {}, "Tạo nhân vật"),
        picker,
        name,
        err,
        submit,
        back ? h("button", { type: "button", class: "link", "data-test": "back", onclick: back }, "← Danh sách nhân vật") : null,
        h("button", { type: "button", class: "link", onclick: onLogout }, "Đăng xuất"),
      ),
    ),
  );
  name.focus();
}
