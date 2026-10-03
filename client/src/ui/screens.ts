// Màn hình trước khi vào game: đăng nhập/đăng ký → chọn/tạo nhân vật (Phase 1: 1 DK).
import { api, saveToken, type ApiError, type CharacterSummary } from "../net/api.js";
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
  try {
    list = (await api.characters(token)).characters;
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

  // Phase 1: 1 nhân vật/tài khoản, chỉ DK (KB_00_RULES §7)
  const name = h("input", { name: "name", placeholder: "Tên nhân vật (4–10 chữ/số)", maxlength: 10 }) as HTMLInputElement;
  const submit = h("button", { type: "submit" }, "Tạo Dark Knight") as HTMLButtonElement;
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
              const r = await api.createCharacter(token, name.value);
              onEnter(r.character);
            } catch (e) {
              err.textContent = (e as ApiError).message;
            } finally {
              submit.disabled = false;
            }
          },
        },
        h("h1", {}, "Tạo nhân vật"),
        h("div", { class: "hint", style: "text-align:center" }, "Class: Dark Knight (DK)"),
        name,
        err,
        submit,
        logout,
      ),
    ),
  );
  name.focus();
}
