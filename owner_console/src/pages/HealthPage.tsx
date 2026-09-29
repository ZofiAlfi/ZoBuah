import { Link } from "react-router-dom";

import { Badge, Empty, ErrorBox, Kpi, Loading } from "../components/ui";
import { CountUp } from "../components/countup";
import { dateTime, healthLabel, num, relative } from "../lib/format";
import { useFetch } from "../lib/useFetch";
import type { HealthRow } from "../lib/types";

export function HealthPage() {
  const { data, loading, error, reload } = useFetch<HealthRow[]>("/admin/stores/health");

  if (loading) return <Loading />;
  if (error) return <ErrorBox message={error} onRetry={reload} />;

  const items = data ?? [];
  if (items.length === 0) return <Empty>Belum ada toko.</Empty>;

  const count = (h: string) => items.filter((i) => i.health === h).length;
  const failed = items.reduce((s, i) => s + i.failed_sync_7d, 0);

  return (
    <>
      <div className="row g-3">
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-check-circle"
            label="Sehat"
            value={<CountUp value={count("OK")} format={num} />}
            sub="Sinkron dalam 24 jam"
            tone="ok"
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-clock-history"
            label="Jarang sinkron"
            value={<CountUp value={count("STALE")} format={num} />}
            sub="lebih dari 24 jam"
            tone={count("STALE") > 0 ? "warn" : undefined}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-x-octagon"
            label="Tidak aktif"
            value={<CountUp value={count("DEAD")} format={num} />}
            sub="lebih dari 72 jam"
            tone={count("DEAD") > 0 ? "bad" : undefined}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-arrow-repeat"
            label="Sync gagal 7 hari"
            value={<CountUp value={failed} format={num} />}
            sub="Seluruh toko"
          />
        </div>
      </div>

      <div className="neo-panel">
        <div className="table-responsive">
          <table className="table">
            <thead>
              <tr>
                <th>Toko</th>
                <th>Kondisi</th>
                <th>Sinkron terakhir</th>
                <th className="right">Jam sejak sinkron</th>
                <th className="right">Perangkat</th>
                <th className="right">Sync gagal 7h</th>
                <th className="right">Aksi</th>
              </tr>
            </thead>
            <tbody>
              {items.map((h) => {
                const meta = healthLabel(h.health);
                return (
                  <tr key={h.store_id}>
                    <td>
                      <div className="fw-semibold">{h.store_name}</div>
                      <div className="small muted">{h.code}</div>
                    </td>
                    <td>
                      <Badge tone={meta.tone}>{meta.text}</Badge>
                    </td>
                    <td>
                      <div>{relative(h.last_sync_at)}</div>
                      <div className="small muted">{dateTime(h.last_sync_at)}</div>
                    </td>
                    <td className="right num">
                      {h.hours_since_sync === null ? "-" : `${num(h.hours_since_sync)} jam`}
                    </td>
                    <td className="right num">{num(h.device_count)}</td>
                    <td className="right num">
                      {h.failed_sync_7d > 0 ? (
                        <span style={{ color: "var(--neo-bad)", fontWeight: 700 }}>{num(h.failed_sync_7d)}</span>
                      ) : (
                        0
                      )}
                    </td>
                    <td className="right">
                      <Link className="btn btn-outline-primary btn-sm" to={`/toko/${h.store_id}`}>
                        Detail
                      </Link>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}