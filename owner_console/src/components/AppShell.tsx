import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { NavLink, Outlet, useLocation } from "react-router-dom";

import { useFetch } from "../lib/useFetch";
import { useAuth } from "../lib/auth";
import { useTheme } from "../lib/theme";
import type { Alert } from "../lib/types";

/* ===================== TOAST ===================== */
type Toast = { id: number; text: string; tone: "ok" | "bad" };

const ToastContext = createContext<(text: string, tone?: "ok" | "bad") => void>(() => {});

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<Toast[]>([]);

  const push = useCallback((text: string, tone: "ok" | "bad" = "ok") => {
    const id = Date.now() + Math.random();
    setItems((prev) => [...prev, { id, text, tone }]);
    setTimeout(() => setItems((prev) => prev.filter((t) => t.id !== id)), 4500);
  }, []);

  return (
    <ToastContext.Provider value={push}>
      {children}
      <div className="toast-container position-fixed bottom-0 end-0 p-3" style={{ zIndex: 400 }}>
        {items.map((t) => (
          <div key={t.id} className={`toast-custom toast-${t.tone}`} role="status">
            <i
              className={`bi ${t.tone === "ok" ? "bi-check-circle-fill" : "bi-exclamation-circle-fill"}`}
              style={{ color: t.tone === "ok" ? "var(--neo-ok)" : "var(--neo-bad)" }}
              aria-hidden
            />
            <span>{t.text}</span>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  return useContext(ToastContext);
}

/* ===================== BANNER PERINGATAN ===================== */
function CriticalBanner({ alerts }: { alerts: Alert[] }) {
  const critical = alerts.filter((a) => a.severity === "CRITICAL");
  if (critical.length === 0) return null;

  const first = critical[0];
  return (
    <div className="banner" role="alert">
      <i className="bi bi-exclamation-octagon-fill" aria-hidden />
      <span>
        {critical.length} toko perlu tindakan segera. {first.title}
        {first.store_name ? ` - ${first.store_name}` : ""}
      </span>
    </div>
  );
}

/* ===================== SHELL ===================== */
const NAV = [
  {
    group: "Ringkasan",
    items: [
      { to: "/", label: "Dashboard", icon: "bi-grid-1x2-fill", end: true },
      { to: "/toko", label: "Toko", icon: "bi-shop" },
      { to: "/pengguna", label: "Pengguna", icon: "bi-people-fill" },
    ],
  },
  {
    group: "Operasional",
    items: [
      { to: "/broadcast", label: "Broadcast", icon: "bi-broadcast" },
      { to: "/pemakaian", label: "Pemakaian Toko", icon: "bi-bar-chart-fill" },
      { to: "/kesehatan", label: "Kesehatan Sync", icon: "bi-activity" },
    ],
  },
  {
    group: "Jejak Audit",
    items: [{ to: "/audit", label: "Log Audit", icon: "bi-journal-text" }],
  },
];

const TITLES: Record<string, string> = {
  "/": "Dashboard",
  "/toko": "Daftar Toko",
  "/pengguna": "Pengguna Toko",
  "/broadcast": "Broadcast",
  "/pemakaian": "Pemakaian Toko",
  "/kesehatan": "Kesehatan Sync",
  "/audit": "Log Audit",
};

export function AppShell() {
  const { owner, logout } = useAuth();
  const toast = useToast();
  const { theme, toggle } = useTheme();
  const location = useLocation();
  const { data: dash } = useFetch<{ alerts: Alert[] }>("/admin/dashboard");

  const criticalCount = (dash?.alerts ?? []).filter((a) => a.severity === "CRITICAL").length;

  const title = useMemo(() => {
    if (location.pathname.startsWith("/toko/")) return "Detail Toko";
    return TITLES[location.pathname] ?? "Owner Console";
  }, [location.pathname]);

  useEffect(() => {
    document.title = `${title} - ZoBuah Owner`;
  }, [title]);

  return (
    <div className="shell">
      <aside className="rail">
        <div className="rail-brand">
          <span className="rail-logo" aria-hidden>
            Z
          </span>
          <span>
            ZoBuah <span className="muted">Owner</span>
          </span>
        </div>

        <nav className="rail-nav" aria-label="Menu utama">
          {NAV.map((section) => (
            <div key={section.group} className="mb-1">
              <div className="rail-group">{section.group}</div>
              {section.items.map((item) => (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end={item.end}
                  className={({ isActive }) => `rail-link${isActive ? " is-active" : ""}`}
                >
                  <i className={`bi ${item.icon}`} aria-hidden />
                  <span>{item.label}</span>
                  {item.to === "/toko" && criticalCount > 0 ? (
                    <span className="rail-count">{criticalCount}</span>
                  ) : null}
                </NavLink>
              ))}
            </div>
          ))}
        </nav>

        <div className="rail-foot d-flex align-items-center gap-2">
          <div className="flex-grow-1 min-w-0">
            <div className="fw-semibold text-truncate">{owner?.full_name ?? "-"}</div>
            <div style={{ opacity: 0.75 }}>{owner?.username}</div>
          </div>
        </div>
      </aside>

      <div className="main">
        <header className="topbar">
          <i className="bi bi-command" aria-hidden style={{ color: "var(--neo-acc)", fontSize: 20 }} />
          <span className="topbar-title">{title}</span>
          <div className="topbar-spacer" />
          <span className="badge badge-info d-none d-sm-inline-flex">
            <i className="bi bi-person-badge" aria-hidden />
            Owner
          </span>
          <button
            className="btn-ico"
            type="button"
            aria-label={theme === "light" ? "Ganti ke tema gelap" : "Ganti ke tema terang"}
            title={theme === "light" ? "Tema gelap" : "Tema terang"}
            onClick={toggle}
          >
            <i className={`bi ${theme === "light" ? "bi-moon-stars" : "bi-brightness-high"}`} aria-hidden />
          </button>
          <button
            className="btn-ico"
            type="button"
            aria-label="Keluar"
            title="Keluar"
            onClick={() => {
              toast("Sesi ditutup.");
              logout();
            }}
          >
            <i className="bi bi-box-arrow-right" aria-hidden />
          </button>
        </header>

        {dash?.alerts ? <CriticalBanner alerts={dash.alerts} /> : null}

        <main className="content" style={{ position: "relative", zIndex: 1 }}>
          <Outlet />
        </main>
      </div>
    </div>
  );
}