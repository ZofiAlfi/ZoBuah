import { useState } from "react";
import { Link } from "react-router-dom";

import { RankBars } from "../components/charts";
import { Badge, Empty, ErrorBox, Loading } from "../components/ui";
import { healthLabel, money, num, planLabel, relative } from "../lib/format";
import { useFetch } from "../lib/useFetch";
import type { StoreUsage } from "../lib/types";

export function UsagePage() {
  const [sort, setSort] = useState<"revenue" | "sales" | "products">("revenue");
  const { data, loading, error, reload } = useFetch<StoreUsage[]>("/admin/metrics/usage");

  if (loading) return <Loading />;
  if (error) return <ErrorBox message={error} onRetry={reload} />;

  const items = data ?? [];

  const sorted = [...items].sort((a, b) =>
    sort === "revenue"
      ? b.revenue_30d - a.revenue_30d
      : sort === "sales"
        ? b.sale_count_30d - a.sale_count_30d
        : b.product_count - a.product_count,
  );

  const totals = items.reduce(
    (acc, i) => ({
      revenue: acc.revenue + i.revenue_30d,
      sales: acc.sales + i.sale_count_30d,
      products: acc.products + i.product_count,
      users: acc.users + i.user_count,
    }),
    { revenue: 0, sales: 0, products: 0, users: 0 },
  );

  if (items.length === 0) return <Empty>Belum ada toko.</Empty>;

  return (
    <>
      <div className="row g-3">
        <div className="col-12 col-xxl-8">
          <div className="neo-card h-100">
            <div className="card-head">
              <h2>Omzet per toko</h2>
              <div className="spacer" />
              <select
                className="form-select form-select-sm"
                value={sort}
                onChange={(e) => setSort(e.target.value as typeof sort)}
                style={{ width: "auto", minWidth: 180 }}
                aria-label="Urutkan menurut"
              >
                <option value="revenue">Omzet</option>
                <option value="sales">Jumlah transaksi</option>
                <option value="products">Jumlah produk</option>
              </select>
            </div>
            <RankBars
              rows={sorted.slice(0, 10).map((u) => ({
                id: u.store_id,
                label: `${u.code} - ${u.store_name}`,
                value:
                  sort === "revenue" ? u.revenue_30d : sort === "sales" ? u.sale_count_30d : u.product_count,
                sub: `${num(u.sale_count_30d)} transaksi, omzet ${money(u.revenue_30d)}`,
              }))}
              formatValue={(v) =>
                sort === "revenue" ? money(v) : `${num(v)} ${sort === "sales" ? "transaksi" : "produk"}`
              }
            />
          </div>
        </div>

        <div className="col-12 col-xxl-4">
          <div className="neo-card h-100">
            <div className="card-head">
              <h2>Total lintas toko</h2>
            </div>
            <dl className="kv">
              <dt>Omzet 30 hari</dt>
              <dd className="num">{money(totals.revenue)}</dd>
              <dt>Transaksi 30 hari</dt>
              <dd className="num">{num(totals.sales)}</dd>
              <dt>Produk terdaftar</dt>
              <dd className="num">{num(totals.products)}</dd>
              <dt>Pengguna toko</dt>
              <dd className="num">{num(totals.users)}</dd>
              <dt>Rata-rata omzet per toko</dt>
              <dd className="num">{money(items.length ? totals.revenue / items.length : 0)}</dd>
            </dl>
          </div>
        </div>
      </div>

      <div className="neo-panel">
        <div className="table-responsive">
          <table className="table">
            <thead>
              <tr>
                <th>Toko</th>
                <th>Paket</th>
                <th>Sync</th>
                <th className="right">Pengguna</th>
                <th className="right">Produk</th>
                <th className="right">Kategori</th>
                <th className="right">Perangkat</th>
                <th className="right">Transaksi 30h</th>
                <th className="right">Omzet 30h</th>
                <th className="right">Aksi</th>
              </tr>
            </thead>
            <tbody>
              {sorted.map((u) => {
                const h = healthLabel(u.health);
                return (
                  <tr key={u.store_id}>
                    <td>
                      <div className="fw-semibold">{u.store_name}</div>
                      <div className="small muted">{u.code}</div>
                    </td>
                    <td>
                      <Badge tone="info">{planLabel(u.plan)}</Badge>
                    </td>
                    <td>
                      <Badge tone={h.tone}>{h.text}</Badge>
                      <div className="small muted" style={{ marginTop: 3 }}>
                        {relative(u.last_sync_at)}
                      </div>
                    </td>
                    <td className="right num">{num(u.user_count)}</td>
                    <td className="right num">{num(u.product_count)}</td>
                    <td className="right num">{num(u.category_count)}</td>
                    <td className="right num">{num(u.device_count)}</td>
                    <td className="right num">{num(u.sale_count_30d)}</td>
                    <td className="right num">{money(u.revenue_30d)}</td>
                    <td className="right">
                      <Link className="btn btn-outline-primary btn-sm" to={`/toko/${u.store_id}`}>
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