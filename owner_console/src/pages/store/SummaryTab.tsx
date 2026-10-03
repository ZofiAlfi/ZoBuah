import { Alert, Badge, Kpi } from "../../components/ui";
import { CountUp } from "../../components/countup";
import { dateShort, healthLabel, num, planLabel, relative, statusLabel } from "../../lib/format";
import type { Plan, StoreDetail } from "../../lib/types";

const PLAN_TONE: Record<Plan, string> = {
  PRO: "ok",
  BASIC: "info",
  TRIAL: "warn",
  UNLIMITED: "ok",
};

export function SummaryTab({
  store,
  onJump,
}: {
  store: StoreDetail;
  onJump: (tab: string) => void;
}) {
  const health = healthLabel(store.health);
  const status = statusLabel(store.status);

  return (
    <>
      {store.status !== "ACTIVE" ? (
        <Alert tone="bad" title="Toko ini sedang tidak aktif">
          Karyawan tidak bisa masuk POS di toko ini sampai statusnya dikembalikan ke Aktif.
        </Alert>
      ) : null}

      <div className="row g-3">
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-cash-stack"
            label="Omzet 30 hari"
            value={<CountUp value={store.revenue_30d} format={(v) => `Rp ${num(v)}`} />}
            sub={<><CountUp value={store.sale_count_30d} format={num} /> transaksi</>}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-exclamation-triangle"
            label="Laporan rusak menunggu"
            value={<CountUp value={store.pending_damage_count} format={num} />}
            sub="Butuh keputusan owner"
            tone={store.pending_damage_count > 0 ? "warn" : "ok"}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-box-seam"
            label="Produk aktif"
            value={<CountUp value={store.product_count} format={num} />}
            sub={`${num(store.category_count)} kategori`}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-3">
          <Kpi
            icon="bi-phone"
            label="Perangkat"
            value={<CountUp value={store.device_count} format={num} />}
            sub={`${num(store.failed_sync_count_7d)} sync gagal 7h`}
            tone={store.failed_sync_count_7d > 0 ? "warn" : "ok"}
          />
        </div>
      </div>

      <div className="row g-3">
        <div className="col-12 col-lg-6">
          <div className="neo-card h-100">
            <div className="card-head">
              <h2>Data toko</h2>
            </div>
            <dl className="kv">
              <dt>Kode toko</dt>
              <dd className="mono">{store.code}</dd>
              <dt>Pemilik</dt>
              <dd>{store.owner_name}</dd>
              <dt>Telepon</dt>
              <dd>{store.phone ?? "-"}</dd>
              <dt>Alamat</dt>
              <dd style={{ fontWeight: 400 }}>{store.address ?? "-"}</dd>
              <dt>Paket</dt>
              <dd>
                <Badge tone={PLAN_TONE[store.plan]}>{planLabel(store.plan)}</Badge>
              </dd>
              <dt>Masa aktif</dt>
              <dd>{store.plan_expires_at ? dateShort(store.plan_expires_at) : "Tanpa batas"}</dd>
              <dt>Bergabung</dt>
              <dd>{dateShort(store.created_at)}</dd>
            </dl>
          </div>
        </div>

        <div className="col-12 col-lg-6">
          <div className="neo-card h-100">
            <div className="card-head">
              <h2>Kondisi data</h2>
            </div>
            <dl className="kv">
              <dt>Status toko</dt>
              <dd>
                <Badge tone={status.tone}>{status.text}</Badge>
              </dd>
              <dt>Kesehatan sinkron</dt>
              <dd>
                <Badge tone={health.tone}>{health.text}</Badge>
              </dd>
              <dt>Sinkron terakhir</dt>
              <dd>{relative(store.last_sync_at)}</dd>
              <dt>Omzet total</dt>
              <dd>{num(store.lifetime_revenue)}</dd>
              <dt>Transaksi total</dt>
              <dd>{num(store.total_sales)}</dd>
              <dt>Stok menipis</dt>
              <dd>{num(store.low_stock_count)} produk</dd>
            </dl>
          </div>
        </div>
      </div>

      <div className="neo-card">
        <div className="card-head">
          <h2>Langsung cek data</h2>
        </div>
        <p className="small muted">
          Semua tab di bawah membaca data toko yang sama. Pilih tab yang paling sering dipakai saat
          menerima laporan dari karyawan.
        </p>
        <div className="d-flex flex-wrap gap-2">
          <button className="btn btn-soft btn-sm" type="button" onClick={() => onJump("damage")}>
            <i className="bi bi-exclamation-triangle" aria-hidden />
            Laporan barang rusak
          </button>
          <button className="btn btn-soft btn-sm" type="button" onClick={() => onJump("stock")}>
            <i className="bi bi-arrow-left-right" aria-hidden />
            Pergerakan stok
          </button>
          <button className="btn btn-soft btn-sm" type="button" onClick={() => onJump("sales")}>
            <i className="bi bi-receipt" aria-hidden />
            Penjualan
          </button>
          <button className="btn btn-soft btn-sm" type="button" onClick={() => onJump("payments")}>
            <i className="bi bi-credit-card" aria-hidden />
            Pembayaran
          </button>
          <button className="btn btn-soft btn-sm" type="button" onClick={() => onJump("people")}>
            <i className="bi bi-people" aria-hidden />
            Kategori dan pengguna
          </button>
        </div>
      </div>
    </>
  );
}
