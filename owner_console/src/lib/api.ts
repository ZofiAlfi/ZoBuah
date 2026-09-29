export const API_BASE = "/api/v1";

const TOKEN_KEY = "zobuah.owner.access";
const REFRESH_KEY = "zobuah.owner.refresh";

export class ApiError extends Error {
  status: number;
  body: unknown;

  constructor(status: number, message: string, body: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.body = body;
  }
}

export const tokens = {
  access: () => localStorage.getItem(TOKEN_KEY),
  refresh: () => localStorage.getItem(REFRESH_KEY),
  save(access: string, refresh: string) {
    localStorage.setItem(TOKEN_KEY, access);
    localStorage.setItem(REFRESH_KEY, refresh);
  },
  clear() {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(REFRESH_KEY);
  },
};

/* Dipanggil saat server membalas 401. AuthProvider yang memasang handler ini,
 * supaya lapisan api tidak perlu tahu soal React. */
let onUnauthorized: (() => void) | null = null;
export function setUnauthorizedHandler(fn: () => void) {
  onUnauthorized = fn;
}

type Options = {
  method?: string;
  body?: unknown;
  signal?: AbortSignal;
  /* Percobaan ulang otomatis setelah refresh, bukan logic pemanggil. */
  retried?: boolean;
};

/* Refresh dipusatkan di sini supaya tidak ada halaman yang harus ingat
 * melakukan refresh sendiri. Refresh yang gagal berarti sesi habis. */
let refreshing: Promise<boolean> | null = null;

async function tryRefresh(): Promise<boolean> {
  const refreshToken = tokens.refresh();
  if (!refreshToken) return false;

  // Beberapa request bisa 401 bersamaan (mis. beberapa kartu dashboard).
  // Hanya satu yang menembak server, yang lain menunggu hasil yang sama.
  refreshing ??= (async () => {
    try {
      const res = await fetch(`${API_BASE}/admin/auth/refresh`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ refresh_token: refreshToken }),
      });
      if (!res.ok) return false;
      const body = (await res.json()) as { access_token: string; refresh_token: string };
      tokens.save(body.access_token, body.refresh_token);
      return true;
    } catch {
      return false;
    } finally {
      refreshing = null;
    }
  })();

  return refreshing;
}

export async function request<T>(path: string, options: Options = {}): Promise<T> {
  const { method = "GET", body, signal, retried = false } = options;
  const headers: Record<string, string> = { Accept: "application/json" };

  if (body !== undefined) headers["Content-Type"] = "application/json";

  const access = tokens.access();
  if (access) headers.Authorization = `Bearer ${access}`;

  let res: Response;
  try {
    res = await fetch(`${API_BASE}${path}`, {
      method,
      headers,
      signal,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, "Tidak bisa menghubungi server API.", null);
  }

  if (res.status === 401) {
    /* 401 pada endpoint login, refresh, atau me tidak boleh memicu refresh
     * lagi, kalau tidak akan berputar sendiri. */
    const isAuthEndpoint =
      path === "/admin/auth/login" || path === "/admin/auth/refresh" || path === "/admin/auth/me";

    if (!retried && !isAuthEndpoint && (await tryRefresh())) {
      return request<T>(path, { method, body, signal, retried: true });
    }

    tokens.clear();
    onUnauthorized?.();
    throw new ApiError(401, "Sesi berakhir. Silakan login kembali.", null);
  }

  if (res.status === 204) return undefined as T;

  const raw = await res.text();
  let parsed: unknown = null;
  if (raw) {
    try {
      parsed = JSON.parse(raw);
    } catch {
      parsed = raw;
    }
  }

  if (!res.ok) {
    throw new ApiError(res.status, describe(res.status, parsed), parsed);
  }

  return parsed as T;
}

function describe(status: number, body: unknown): string {
  if (body && typeof body === "object" && "detail" in body) {
    const detail = (body as { detail: unknown }).detail;
    if (typeof detail === "string") return detail;
    // FastAPI mengirim array detail untuk galat validasi pydantic.
    if (Array.isArray(detail) && detail.length) {
      const first = detail[0] as { msg?: string; loc?: unknown[] };
      const field = Array.isArray(first.loc)
        ? first.loc.filter((p) => p !== "body").join(".")
        : "";
      const msg = (first.msg ?? "Data tidak valid").replace(/^Value error, /, "");
      return field ? `${field}: ${msg}` : msg;
    }
  }
  if (status === 403) return "Akses ditolak.";
  if (status === 404) return "Data tidak ditemukan.";
  if (status >= 500) return "Server mengalami masalah. Coba lagi sebentar.";
  return `Permintaan gagal (${status}).`;
}

export const api = {
  get: <T,>(path: string, signal?: AbortSignal) => request<T>(path, { signal }),
  post: <T,>(path: string, body?: unknown) => request<T>(path, { method: "POST", body }),
  patch: <T,>(path: string, body?: unknown) => request<T>(path, { method: "PATCH", body }),
  del: <T,>(path: string) => request<T>(path, { method: "DELETE" }),
};
