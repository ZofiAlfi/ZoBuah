import { useId } from "react";

import { money, moneyShort } from "../lib/format";
import type { RevenuePoint } from "../lib/types";

/**
 * Grafik tren omzet, digambar langsung sebagai SVG (tanpa dependensi chart).
 * Warna mengikuti token tema sehingga ikut light/dark. Garis digambar dengan
 * animasi "draw" ala CodePen (stroke-dashoffset), area memudar masuk.
 */
export function RevenueChart({ points }: { points: RevenuePoint[] }) {
  const gradientId = useId();

  if (points.length < 2) {
    return <div className="empty">Belum ada transaksi untuk digrafik.</div>;
  }

  const W = 720;
  const H = 220;
  const padL = 52;
  const padR = 12;
  const padT = 12;
  const padB = 26;

  const values = points.map((p) => p.revenue);
  const max = Math.max(...values, 1);
  const min = Math.min(...values, 0);

  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const x = (i: number) => padL + (i / (points.length - 1)) * innerW;
  const y = (v: number) => padT + innerH - ((v - min) / (max - min || 1)) * innerH;

  const line = points
    .map((p, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(p.revenue).toFixed(1)}`)
    .join(" ");
  const area = `${line} L${x(points.length - 1).toFixed(1)},${(padT + innerH).toFixed(1)} L${padL},${(padT + innerH).toFixed(1)} Z`;

  const ticks = [0, 0.25, 0.5, 0.75, 1].map((t) => min + (max - min) * t);
  /* Tiap titik diberi label tanggal hanya 5 label supaya tidak bertabrakan. */
  const labelStep = Math.max(1, Math.ceil(points.length / 5));

  return (
    <figure style={{ margin: 0 }}>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" role="img" aria-label="Tren omzet 30 hari terakhir">
        <defs>
          <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--neo-acc)" stopOpacity="0.28" />
            <stop offset="100%" stopColor="var(--neo-acc)" stopOpacity="0" />
          </linearGradient>
        </defs>

        {ticks.map((t) => (
          <g key={t}>
            <line
              x1={padL}
              x2={W - padR}
              y1={y(t)}
              y2={y(t)}
              stroke="var(--neo-line)"
              strokeWidth="1"
            />
            <text x={padL - 8} y={y(t) + 4} textAnchor="end" fontSize="10" fill="var(--neo-muted)">
              {t === 0 ? "0" : moneyShort(t).replace("Rp ", "")}
            </text>
          </g>
        ))}

        <path className="chart-area" d={area} fill={`url(#${gradientId})`} />
        <path
          className="chart-line"
          d={line}
          pathLength={1}
          fill="none"
          stroke="var(--neo-acc)"
          strokeWidth="2.5"
          strokeLinejoin="round"
        />

        {points.map((p, i) =>
          p.transactions > 0 && i % labelStep === 0 ? (
            <circle
              key={p.date}
              className="chart-dot"
              cx={x(i)}
              cy={y(p.revenue)}
              r="3.5"
              fill="var(--neo-surface)"
              stroke="var(--neo-acc)"
              strokeWidth="2"
            >
              <title>
                {p.date}: {money(p.revenue)} dari {p.transactions} transaksi
              </title>
            </circle>
          ) : null,
        )}

        {points.map((p, i) =>
          i % labelStep === 0 ? (
            <text key={`t-${p.date}`} x={x(i)} y={H - 8} textAnchor="middle" fontSize="10" fill="var(--neo-muted)">
              {p.date.slice(8, 10)}/{p.date.slice(5, 7)}
            </text>
          ) : null,
        )}
      </svg>
      <figcaption className="small muted" style={{ marginTop: 6 }}>
        Omzet 30 hari terakhir, {money(points.reduce((s, p) => s + p.revenue, 0))} dari{" "}
        {points.reduce((s, p) => s + p.transactions, 0)} transaksi.
      </figcaption>
    </figure>
  );
}

/** Bar horizontal untuk daftar peringkat. Panjang bar proporsional ke nilai. */
export function RankBars({
  rows,
  formatValue = (v: number) => money(v),
  emptyText = "Belum ada data.",
}: {
  rows: { id: string; label: string; sub?: string; value: number; tone?: string }[];
  formatValue?: (value: number) => string;
  emptyText?: string;
}) {
  if (rows.length === 0) return <div className="empty">{emptyText}</div>;

  const max = Math.max(...rows.map((r) => Math.abs(r.value)), 1);

  return (
    <div className="d-flex flex-column gap-3">
      {rows.map((r) => (
        <div key={r.id}>
          <div className="d-flex align-items-center justify-content-between gap-2">
            <span
              className="fw-semibold"
              style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}
            >
              {r.label}
            </span>
            <span className="num small muted" style={{ whiteSpace: "nowrap" }}>
              {formatValue(r.value)}
            </span>
          </div>
          <div className="chart-bar-track" style={{ marginTop: 5 }}>
            <div
              className="chart-bar-fill"
              style={{
                width: `${Math.max(2, (Math.abs(r.value) / max) * 100)}%`,
                background: r.tone ?? "var(--neo-acc)",
              }}
            />
          </div>
          {r.sub ? (
            <div className="small muted" style={{ marginTop: 3 }}>
              {r.sub}
            </div>
          ) : null}
        </div>
      ))}
    </div>
  );
}