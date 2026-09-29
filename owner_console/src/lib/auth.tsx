import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

import { api, setUnauthorizedHandler, tokens } from "./api";
import type { AdminToken, Owner } from "./types";

type AuthState = {
  owner: Owner | null;
  loading: boolean;
  error: string | null;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
};

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [owner, setOwner] = useState<Owner | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const logout = useCallback(() => {
    tokens.clear();
    setOwner(null);
  }, []);

  useEffect(() => {
    setUnauthorizedHandler(() => setOwner(null));
  }, []);

  /* Saat halaman di-refresh, token masih ada di localStorage. Token itu
   * harus diverifikasi ke server karena bisa saja kedaluwarsa atau sudah
   * dicabut lewat force-logout. Menyimpan owner di localStorage tanpa
   * verifikasi akan menampilkan dashboard kosong lalu-many error. */
  useEffect(() => {
    let cancelled = false;

    async function restore() {
      if (!tokens.access()) {
        setLoading(false);
        return;
      }
      try {
        const me = await api.get<Owner>("/admin/auth/me");
        if (!cancelled) setOwner(me);
      } catch {
        if (!cancelled) {
          tokens.clear();
          setOwner(null);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    void restore();
    return () => {
      cancelled = true;
    };
  }, []);

  const login = useCallback(async (username: string, password: string) => {
    setError(null);
    try {
      const res = await api.post<AdminToken>("/admin/auth/login", { username, password });
      tokens.save(res.access_token, res.refresh_token);
      setOwner(res.owner);
    } catch (e) {
      const message = e instanceof Error ? e.message : "Login gagal";
      setError(message);
      throw e;
    }
  }, []);

  const value = useMemo<AuthState>(
    () => ({ owner, loading, error, login, logout }),
    [owner, loading, error, login, logout],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth harus dipakai di dalam AuthProvider");
  return ctx;
}
