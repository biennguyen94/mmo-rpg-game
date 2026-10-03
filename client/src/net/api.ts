// HTTP API (OPEN_QUESTIONS P1, DEC-10): lỗi dạng {error: MÃ, message}.

export interface ApiError {
  status: number;
  error: string;
  message: string;
}

export interface CharacterSummary {
  id: string;
  name: string;
  class: string;
  level: number;
  mapId: string;
}

const TOKEN_KEY = "mu.token";

// localStorage có thể ném lỗi (chế độ riêng tư): không làm hỏng game
export function loadToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

export function saveToken(token: string | null): void {
  try {
    if (token) localStorage.setItem(TOKEN_KEY, token);
    else localStorage.removeItem(TOKEN_KEY);
  } catch {
    /* bỏ qua */
  }
}

async function call<T>(method: string, path: string, body?: object, token?: string | null): Promise<T> {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw { status: res.status, error: data.error ?? "HTTP", message: data.message ?? `Lỗi ${res.status}` } as ApiError;
  }
  return data as T;
}

export const api = {
  register: (username: string, password: string) =>
    call<{ token: string; username: string }>("POST", "/register", { username, password }),
  login: (username: string, password: string) =>
    call<{ token: string; username: string }>("POST", "/login", { username, password }),
  logout: (token: string) => call<{ ok: boolean }>("POST", "/logout", undefined, token),
  wsTicket: (token: string) => call<{ ticket: string }>("POST", "/ws-ticket", undefined, token),
  characters: (token: string) => call<{ characters: CharacterSummary[] }>("GET", "/characters", undefined, token),
  createCharacter: (token: string, name: string) =>
    call<{ character: CharacterSummary }>("POST", "/characters", { name }, token),
};
