import { useState } from "react";
import { Link } from "react-router-dom";

import { RankBars, RevenueChart } from "../components/charts";
import { CountUp } from "../components/countup";
import { Alert, Aurora, Empty, ErrorBox, Kpi, Loading } from "../components/ui";
import { money, moneyShort, num, planLabel } from "../lib/format";
import { useFetch } from "../lib/useFetch";
import { useAuth } from "../lib/auth";
import type { DashboardPayload, RevenuePoint } from "../lib/types";

const SEVERITY_TONE = { CRITICAL: "bad", WARNING: "warn", INFO: "info" } as const;

export function DashboardPage() {
  const { data, loading, error, reload } = useFetch<DashboardPayload>("/admin/dashboard");
  const { owner } = useAuth();
  const [storeFilter, setStoreFilter] = useState("all");

  if (loading) return <Loading />;
  if (error) return <ErrorBox message={error} onRetry={reload} />;
  if (!data) return <ErrorBox message="Data dashboard tidak tersedia." />;

  const { overview: ov, revenue_30d: series, top_stores: tops, plans, alerts } = data;

  return (
    <>
      <div className="neo-card position-relative overflow-hidden" style={{ padding: "var(--sp-5)" }}>
        <Aurora intensity={0.55} />
        <div className="position-relative" style={{ zIndex: 1 }}>
          <h1 className="mb-1">Selamat datang, {owner?.full_name.split(" ")[0] ?? "Owner"}</h1>
          <p className="muted mb-0">
            Ringkasan seluruh jaringan ZoBuah — omzet, laba, dan kesehatan toko dalam 30 hari
            terakhir.
          </p>
        </div>
      </div>

      <div className="row g-3">
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-shop"
            label="Toko terdaftar"
            value={<CountUp value={ov.total_stores} format={num} />}
            sub={<><CountUp value={ov.active_stores} format={num} /> aktif</>}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-cash-stack"
            label="Omzet 30 hari"
            value={<CountUp value={ov.revenue_30d} format={moneyShort} />}
            sub={<><CountUp value={ov.total_sales_30d} format={num} /> transaksi</>}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-graph-up-arrow"
            label="Laba 30 hari"
            value={<CountUp value={ov.profit_30d} format={moneyShort} />}
            sub={
              ov.revenue_30d > 0
                ? `Margin ${Math.round((ov.profit_30d / ov.revenue_30d) * 100)}%`
                : "-"
            }
            tone={ov.profit_30d >= 0 ? "ok" : "bad"}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-heart-pulse"
            label="Toko sehat"
            value={<CountUp value={ov.healthy_stores} format={num} />}
            sub={`${num(ov.stale_stores)} jarang sinkron, ${num(ov.dead_stores)} mati`}
            tone={ov.dead_stores > 0 ? "warn" : "ok"}
          />
        </div>
      </div>

      {alerts.length > 0 ? (
        <div className="row g-3">
          {alerts.slice(0, 6).map((a) => (
            <div key={`${a.code}-${a.store_id ?? "global"}`} className="col-12 col-xl-6">
              <Alert tone={SEVERITY_TONE[a.severity]} title={a.title}>
                {a.message}
                {a.store_id ? (
                  <>
                    {" "}
                    <Link to={`/toko/${a.store_id}`}>Lihat toko</Link>
                  </>
                ) : null}
              </Alert>
            </div>
          ))}
        </div>
      ) : null}

      <div className="neo-card">
        <div className="card-head">
          <h2>Tren omzet</h2>
          <div className="spacer" />
          <label className="d-flex align-items-center gap-2 small muted" htmlFor="store-filter">
            Toko
            <select
              id="store-filter"
              className="form-select form-select-sm"
              value={storeFilter}
              onChange={(e) => setStoreFilter(e.target.value)}
              style={{ width: "auto", minWidth: 180 }}
            >
              <option value="all">Semua toko</option>
              {tops.map((s) => (
                <option key={s.store_id} value={s.store_id}>
                  {s.code} - {s.store_name}
                </option>
              ))}
            </select>
          </label>
        </div>

        {storeFilter === "all" ? <RevenueChart points={series} /> : <StoreTrend storeId={storeFilter} />}
      </div>

      <div className="row g-3">
        <div className="col-12 col-xxl-6">
          <div className="neo-card neo-card-hover h-100">
            <div className="card-head">
              <h2>Toko teratas</h2>
              <div className="spacer" />
              <Link className="small" to="/toko">
                Semua toko
              </Link>
            </div>
            <RankBars
              rows={tops.map((s) => ({
                id: s.store_id,
                label: `${s.code} - ${s.store_name}`,
                value: s.revenue,
                sub: `${num(s.transactions)} transaksi, laba ${money(s.profit)}`,
              }))}
              emptyText="Belum ada transaksi 30 hari terakhir."
            />
          </div>
        </div>

        <div className="col-12 col-xxl-6">
          <div className="neo-card neo-card-hover h-100">
            <div className="card-head">
              <h2>Sebaran paket</h2>
            </div>
            <RankBars
              rows={plans.map((p) => ({
                id: p.plan,
                label: planLabel(p.plan),
                value: p.store_count,
                tone: "var(--neo-acc)",
                sub: `${num(p.active_store_count)} aktif dari ${num(p.store_count)} toko, omzet ${money(p.revenue_30d)}`,
              }))}
              emptyText="Belum ada toko."
            />
          </div>
        </div>
      </div>

      <div className="row g-3">
        <div className="col-12 col-md-6 col-xxl-4">
          <div className="neo-card">
            <div className="card-head">
              <h3>Data terkumpul</h3>
            </div>
            <dl className="kv">
              <dt>Pengguna</dt>
              <dd className="num">{num(ov.total_users)}</dd>
              <dt>Produk</dt>
              <dd className="num">{num(ov.total_products)}</dd>
              <dt>Perangkat</dt>
              <dd className="num">{num(ov.total_devices)}</dd>
            </dl>
          </div>
        </div>

        <div className="col-12 col-md-6 col-xxl-4">
          <div className="neo-card">
            <div className="card-head">
              <h3>Perlu perhatian</h3>
            </div>
            <dl className="kv">
              <dt>Laporan rusak pending</dt>
              <dd className="num">{num(ov.pending_damage_total)}</dd>
              <dt>Paket hampir habis</dt>
              <dd className="num">{num(ov.expiring_soon)}</dd>
              <dt>Toko uji coba</dt>
              <dd className="num">{num(ov.trial_stores)}</dd>
            </dl>
          </div>
        </div>

        <div className="col-12 col-md-6 col-xxl-4">
          <div className="neo-card">
            <div className="card-head">
              <h3>Rata-rata per toko</h3>
            </div>
            <dl className="kv">
              <dt>Omzet 30 hari</dt>
              <dd className="num">{money(ov.avg_revenue_per_store_30d)}</dd>
              <dt>Toko ditangguhkan</dt>
              <dd className="num">{num(ov.suspended_stores)}</dd>
              <dt>Toko kedaluwarsa</dt>
              <dd className="num">{num(ov.expired_stores)}</dd>
            </dl>
          </div>
        </div>
      </div>
    </>
  );
}

function StoreTrend({ storeId }: { storeId: string }) {
  const { data, loading, error } = useFetch<RevenuePoint[]>(
    `/admin/metrics/revenue?days=30&store_id=${storeId}`,
  );
  if (loading) return <Loading label="Memuat tren toko" pattern="lines" />;
  if (error) return <ErrorBox message={error} />;
  if (!data || data.length === 0) return <Empty>Belum ada transaksi toko ini.</Empty>;
  return <RevenueChart points={data} />;
}