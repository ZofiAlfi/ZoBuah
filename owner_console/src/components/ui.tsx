import { createPortal } from "react-dom";
import type { ReactNode } from "react";

export function Aurora({ intensity = 1 }: { intensity?: number }) {
  return (
    <div className="aurora" aria-hidden>
      <div
        className="aurora-blob"
        style={{
          width: 460,
          height: 460,
          top: "-12%",
          left: "-6%",
          background: `radial-gradient(circle, var(--aurora-1) 0%, transparent 70%)`,
          opacity: 0.55 * intensity,
        }}
      />
      <div
        className="aurora-blob"
        style={{
          width: 380,
          height: 380,
          top: "35%",
          right: "-8%",
          background: `radial-gradient(circle, var(--aurora-2) 0%, transparent 72%)`,
          opacity: 0.5 * intensity,
        }}
      />
      <div
        className="aurora-blob"
        style={{
          width: 320,
          height: 320,
          bottom: "-10%",
          left: "28%",
          background: `radial-gradient(circle, var(--aurora-3) 0%, transparent 72%)`,
          opacity: 0.42 * intensity,
        }}
      />
    </div>
  );
}

export function Badge({ tone, children }: { tone: string; children: ReactNode }) {
  const safe = ["ok", "warn", "bad", "info", "muted"].includes(tone) ? tone : "muted";
  return <span className={`badge badge-${safe}`}>{children}</span>;
}

export function Kpi({
  label,
  value,
  sub,
  tone,
  icon,
}: {
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  tone?: "ok" | "warn" | "bad";
  icon?: string;
}) {
  return (
    <div className="kpi">
      <div className="kpi-label">
        {icon ? <i className={`bi ${icon}`} aria-hidden /> : null}
        {label}
      </div>
      <div className={`kpi-value${tone ? ` tone-${tone}` : ""}`}>{value}</div>
      {sub ? <div className="kpi-sub">{sub}</div> : null}
    </div>
  );
}

export function Alert({
  tone,
  title,
  children,
  action,
}: {
  tone: "bad" | "warn" | "ok" | "info";
  title: string;
  children?: ReactNode;
  action?: ReactNode;
}) {
  const icon = { bad: "bi-exclamation-circle-fill", warn: "bi-exclamation-triangle-fill", ok: "bi-check-circle-fill", info: "bi-info-circle-fill" }[tone];
  return (
    <div className={`alert alert-${tone}`} role="alert">
      <i className={`bi ${icon}`} aria-hidden />
      <div className="alert-body">
        <div className="alert-title">{title}</div>
        {children ? <div className="alert-msg">{children}</div> : null}
      </div>
      {action}
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return (
    <div className="neo-card d-flex flex-column align-items-center justify-content-center gap-2 text-center">
      <i className="bi bi-inbox" style={{ fontSize: 34, color: "var(--neo-muted)" }} aria-hidden />
      <div className="muted">{children}</div>
    </div>
  );
}

export function SkeletonCards({ count = 4 }: { count?: number }) {
  return (
    <div className="row g-3">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="col-12 col-sm-6 col-xl-3">
          <div className="sk sk-card" />
        </div>
      ))}
    </div>
  );
}

export function SkeletonLines({ count = 6 }: { count?: number }) {
  return (
    <div className="neo-panel p-4 d-flex flex-column gap-3">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="sk sk-line" style={{ width: `${88 - (i % 3) * 12}%` }} />
      ))}
    </div>
  );
}

export function Loading({ label = "Memuat data", pattern = "cards" }: { label?: string; pattern?: "cards" | "lines" }) {
  return (
    <div role="status" aria-label={label}>
      <span className="visually-hidden">{label}...</span>
      {pattern === "cards" ? <SkeletonCards /> : <SkeletonLines />}
    </div>
  );
}

export function ErrorBox({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <Alert tone="bad" title="Gagal memuat data" action={
      onRetry ? (
        <button className="btn btn-outline-primary btn-sm" onClick={onRetry} type="button">
          Coba lagi
        </button>
      ) : undefined
    }>
      {message}
    </Alert>
  );
}

export function Modal({
  title,
  onClose,
  children,
  footer,
  wide,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
  footer?: ReactNode;
  wide?: boolean;
}) {
  return createPortal(
    <div
      className="overlay"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        style={wide ? { width: "min(880px, 100%)" } : undefined}
      >
        <div className="modal-head">
          <h2 className="flex-grow-1">{title}</h2>
          <button className="btn btn-ico" onClick={onClose} type="button" aria-label="Tutup">
            <i className="bi bi-x-lg" aria-hidden />
          </button>
        </div>
        <div className="modal-body">{children}</div>
        {footer ? <div className="modal-foot">{footer}</div> : null}
</div>
    </div>,
    document.body,
  );
}

export function Field({
  label,
  hint,
  error,
  children,
}: {
  label: string;
  hint?: string;
  error?: string;
  children: ReactNode;
}) {
  return (
    <div className="d-flex flex-column gap-1">
      <label className="form-label fw-semibold mb-0" style={{ fontSize: 13 }}>
        {label}
      </label>
      {children}
      {error ? (
        <small style={{ color: "var(--neo-bad)" }} role="alert">
          {error}
        </small>
      ) : hint ? (
        <small className="muted">{hint}</small>
      ) : null}
    </div>
  );
}