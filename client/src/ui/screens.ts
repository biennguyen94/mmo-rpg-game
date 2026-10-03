// Màn hình trước khi vào game: đăng nhập/đăng ký → chọn/tạo nhân vật (1 nhân vật/tài khoản;
// Phase 2: chọn class DK / DW / ELF).
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
  try {
    ({ characters: list, classes } = await api.characters(token));
  } catch (e) {
    if ((e as ApiError).status === 401) return onLogout();
    throw e;
  }

  const err = h("div", { class: "error", role: "alert" });
  const logout = h("button", { type: "button", class: "link", onclick: onLogout }, "Đăng xuất");

  if (list.length > 0) {
    const c = list[0];
    mount(
      root,
      h(
        "div",
        { class: "screen" },
        h(
          "div",
          { class: "card" },
          h("h1", {}, "Nhân vật"),
          h("div", { style: "text-align:center" }, h("b", {}, c.name), ` · ${c.class} · Cấp ${c.level}`),
          h("button", { type: "button", onclick: () => onEnter(c), autofocus: true }, "Vào game"),
          logout,
        ),
      ),
    );
    return;
  }

  // 1 nhân vật/tài khoản tới Phase 3 (Q13); class do server liệt kê, mục đầu chọn sẵn
  const name = h("input", { name: "name", placeholder: "Tên nhân vật (4–10 chữ/số)", maxlength: 10 }) as HTMLInputElement;
  const submit = h("button", { type: "submit" }, "Tạo nhân vật") as HTMLButtonElement;
  let chosen = classes[0]?.id ?? "DK";
  const picker = h(
    "div",
    { class: "classpick", role: "radiogroup", "data-test": "class-picker" },
    classes.map((c, i) =>
      h(
        "label",
        { class: "classopt" },
        h("input", { type: "radio", name: "class", value: c.id, checked: i === 0, onchange: () => (chosen = c.id) }),
        h("img", { src: `/assets/sprites/characters/${c.id.toLowerCase()}/body.png`, alt: "", draggable: "false" }),
        h("span", {}, `${c.name} (${c.id})`),
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
        logout,
      ),
    ),
  );
  name.focus();
}
