import { useState, type FormEvent } from "react";
import { Navigate, useLocation, useNavigate } from "react-router-dom";

import { useAuth } from "../lib/auth";
import { Aurora, Field } from "../components/ui";

export function LoginPage() {
  const { owner, loading, login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const [username, setUsername] = useState("owner");
  const [password, setPassword] = useState("owner-secret-123");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (loading)
    return (
      <div className="login-wrap">
        <div className="d-flex flex-column align-items-center gap-3">
          <span className="rail-logo" style={{ width: 46, height: 46, fontSize: 22 }} aria-hidden>
            Z
          </span>
          <div className="sk sk-line" style={{ width: 140 }} />
        </div>
        <Aurora />
      </div>
    );
  if (owner) return <Navigate to="/" replace />;

  const from = (location.state as { from?: string } | null)?.from ?? "/";

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await login(username.trim(), password);
      navigate(from, { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login gagal.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-wrap">
      <Aurora intensity={0.8} />

      <form className="login-card" onSubmit={submit}>
        <div className="login-logo" aria-hidden>
          Z
        </div>

        <div>
          <h1>ZoBuah Owner Console</h1>
          <p className="muted" style={{ margin: "4px 0 0" }}>
            Pantau seluruh toko dari satu tempat.
          </p>
        </div>

        {error ? (
          <div className="alert alert-bad" role="alert">
            <i className="bi bi-exclamation-triangle-fill" aria-hidden />
            <div className="alert-body">
              <div className="alert-msg">{error}</div>
            </div>
          </div>
        ) : null}

        <Field label="Nama pengguna">
          <input
            className="form-control"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            autoComplete="username"
            autoFocus
            required
          />
        </Field>

        <Field label="Kata sandi">
          <input
            className="form-control"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
            required
          />
        </Field>

        <button className="btn btn-primary w-100" type="submit" disabled={busy}>
          {busy ? (
            <>
              <span className="spinner-border spinner-border-sm" aria-hidden />
              Memproses...
            </>
          ) : (
            "Masuk"
          )}
        </button>

        <div className="login-hint">
          Akun UAT: <strong>owner</strong> / <strong>owner-secret-123</strong>
          <br />
          Akun BOS tidak bisa masuk ke sini. Gunakan <strong>bost01</strong> di aplikasi
          POS.
        </div>
      </form>
    </div>
  );
}