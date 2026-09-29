import { BrowserRouter, Navigate, Route, Routes, useLocation } from "react-router-dom";
import type { ReactElement } from "react";

import "./styles/app.css";
import { AppShell, ToastProvider } from "./components/AppShell";
import { AuthProvider, useAuth } from "./lib/auth";
import { ThemeProvider } from "./lib/theme";
import { Aurora } from "./components/ui";
import { AuditPage } from "./pages/AuditPage";
import { BroadcastsPage } from "./pages/BroadcastsPage";
import { DashboardPage } from "./pages/DashboardPage";
import { HealthPage } from "./pages/HealthPage";
import { LoginPage } from "./pages/LoginPage";
import { StoreDetailPage } from "./pages/StoreDetailPage";
import { StoresPage } from "./pages/StoresPage";
import { UsagePage } from "./pages/UsagePage";
import { UsersPage } from "./pages/UsersPage";

/** Halaman yang butuh sesi Owner. Menyimpan halaman tujuan supaya setelah
 * login user kembali ke tempat yang tadi dibuka, bukan ke dashboard. */
function RequireAuth({ children }: { children: ReactElement }) {
  const { owner, loading } = useAuth();
  const location = useLocation();

  if (loading)
    return (
      <div className="login-wrap">
        <div
          className="d-flex flex-column align-items-center gap-3"
          style={{ position: "relative", zIndex: 1 }}
        >
          <span className="rail-logo" style={{ width: 46, height: 46, fontSize: 22 }} aria-hidden>
            Z
          </span>
          <div className="sk sk-line" style={{ width: 140 }} />
        </div>
        <Aurora />
      </div>
    );
  if (!owner) return <Navigate to="/masuk" replace state={{ from: location.pathname }} />;
  return children;
}

export default function App() {
  return (
    <BrowserRouter>
      <ThemeProvider>
        <AuthProvider>
          <ToastProvider>
            <Routes>
              <Route path="/masuk" element={<LoginPage />} />
              <Route
                element={
                  <RequireAuth>
                    <AppShell />
                  </RequireAuth>
                }
              >
                <Route path="/" element={<DashboardPage />} />
                <Route path="/toko" element={<StoresPage />} />
                <Route path="/toko/:storeId" element={<StoreDetailPage />} />
                <Route path="/pengguna" element={<UsersPage />} />
                <Route path="/broadcast" element={<BroadcastsPage />} />
                <Route path="/pemakaian" element={<UsagePage />} />
                <Route path="/kesehatan" element={<HealthPage />} />
                <Route path="/audit" element={<AuditPage />} />
              </Route>
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
          </ToastProvider>
        </AuthProvider>
      </ThemeProvider>
    </BrowserRouter>
  );
}