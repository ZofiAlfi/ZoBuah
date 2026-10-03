import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { useToast } from "../components/AppShell";
import { Alert, Badge, ErrorBox, Field, Loading, Modal } from "../components/ui";
import { api } from "../lib/api";
import { dateInputToIsoDate, dateShort, dateTime, healthLabel, money, num, planLabel, relative, statusLabel } from "../lib/format";
import { useFetch } from "../lib/useFetch";
import type { AdminSale, AdminSaleDetail, ImpersonateResult, Paged, Plan, StoreDetail, StoreProductLite } from "../lib/types";
import { DamageTab } from "./store/DamageTab";
import { HistoryTab } from "./store/HistoryTab";
import { PaymentsTab } from "./store/PaymentsTab";
import { PeopleTab } from "./store/PeopleTab";
import { ProductsTab } from "./store/ProductsTab";
import { SalesTab } from "./store/SalesTab";
import { StockTab } from "./store/StockTab";
import { SummaryTab } from "./store/SummaryTab";

const PLAN_TONE: Record<Plan, string> = {
  PRO: "ok",
  BASIC: "info",
  TRIAL: "warn",
  UNLIMITED: "ok",
};

const TABS = [
  { key: "summary", label: "Ringkasan", icon: "bi-grid-1x2" },
  { key: "damage", label: "Barang Rusak", icon: "bi-exclamation-triangle" },
  { key: "stock", label: "Pergerakan Stok", icon: "bi-arrow-left-right" },
  { key: "history", label: "Riwayat Produk", icon: "bi-clock-history" },
  { key: "products", label: "Produk", icon: "bi-box-seam" },
  { key: "sales", label: "Penjualan", icon: "bi-receipt" },
  { key: "payments", label: "Pembayaran", icon: "bi-credit-card" },
  { key: "people", label: "Kategori & Pengguna", icon: "bi-people" },
] as const;

export function StoreDetailPage() {
  const { storeId = "" } = useParams();
  const toast = useToast();

  const store = useFetch<StoreDetail>(`/admin/stores/${storeId}`);

  const [tab, setTab] = useState<(typeof TABS)[number]["key"]>("summary");
  const [editing, setEditing] = useState(false);
  const [addingUser, setAddingUser] = useState(false);
  const [impersonating, setImpersonating] = useState<ImpersonateResult | null>(null);
  const [viewingSale, setViewingSale] = useState<AdminSale | null>(null);
  const [editingSale, setEditingSale] = useState<AdminSale | null>(null);
  const [deletingSale, setDeletingSale] = useState<AdminSale | null>(null);
  const [salesToken, setSalesToken] = useState(0);
  // Tab PeopleTab punya tabelnya sendiri yang diambil dari API, jadi menambah
  // pengguna tidak cukup dengan me-reload kartu toko: tabel di dalam tab juga
  // perlu tahu bahwa datanya berubah.
  const [peopleToken, setPeopleToken] = useState(0);

  if (store.loading) return <Loading />;
  if (store.error) return <ErrorBox message={store.error} onRetry={store.reload} />;
  if (!store.data) return <ErrorBox message="Toko tidak ditemukan." />;

  const s = store.data;
  const h = healthLabel(s.health);
  const st = statusLabel(s.status);
  const storeLabel = `${s.name} (${s.code})`;

  return (
    <>
      <div className="d-flex flex-wrap align-items-center gap-2">
        <Link className="btn btn-soft btn-sm" to="/toko">
          <i className="bi bi-arrow-left" aria-hidden />
          Kembali ke daftar
        </Link>
        <div className="flex-grow-1" />
        <button className="btn btn-outline-primary" type="button" onClick={() => setEditing(true)}>
          <i className="bi bi-pencil" aria-hidden />
          Ubah data toko
        </button>
        <button
          className="btn btn-primary"
          type="button"
          onClick={async () => {
            try {
              /* store_id di body itu wajib, bukan opsional. Endpoint ini
               * menerima store_id dua kali (path dan body); kalau body
               * dikosongkan server membalas 422 dan tombol ini tidak akan
               * pernah berhasil. */
              const res = await api.post<ImpersonateResult>(
                `/admin/stores/${storeId}/impersonate`,
                { store_id: storeId },
              );
              setImpersonating(res);
            } catch (e) {
              toast(e instanceof Error ? e.message : "Gagal membuat token tinjauan.", "bad");
            }
          }}
        >
          <i className="bi bi-eye" aria-hidden />
          Tinjau sebagai BOS
        </button>
      </div>

      <div className="neo-card">
        <div className="d-flex flex-wrap align-items-start justify-content-between gap-3">
          <div>
            <h1>{s.name}</h1>
            <p className="muted mb-2">
              {s.code} - {s.owner_name}
              {s.phone ? ` - ${s.phone}` : ""}
            </p>
            <div className="d-flex flex-wrap align-items-center gap-2">
              <Badge tone={PLAN_TONE[s.plan]}>{planLabel(s.plan)}</Badge>
              <Badge tone={st.tone}>{st.text}</Badge>
              <Badge tone={h.tone}>{h.text}</Badge>
              {s.pending_damage_count > 0 ? (
                <Badge tone="warn">{num(s.pending_damage_count)} laporan rusak menunggu</Badge>
              ) : null}
              <span className="small muted">Sinkron {relative(s.last_sync_at)}</span>
            </div>
          </div>
          <dl className="kv" style={{ minWidth: 230 }}>
            <dt>Masa aktif</dt>
            <dd>{s.plan_expires_at ? dateShort(s.plan_expires_at) : "Tanpa batas"}</dd>
            <dt>Bergabung</dt>
            <dd>{dateShort(s.created_at)}</dd>
            <dt>Alamat</dt>
            <dd style={{ fontWeight: 400 }}>{s.address ?? "-"}</dd>
          </dl>
        </div>
      </div>

      <div className="tab-bar no-print" role="tablist" aria-label="Data toko">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            role="tab"
            id={`tab-${t.key}`}
            aria-selected={tab === t.key}
            aria-controls={`panel-${t.key}`}
            className={`tab-btn${tab === t.key ? " is-active" : ""}`}
            onClick={() => setTab(t.key)}
          >
            <i className={`bi ${t.icon}`} aria-hidden />
            {t.label}
            {t.key === "damage" && s.pending_damage_count > 0 ? (
              <span className="rail-count">{num(s.pending_damage_count)}</span>
            ) : null}
          </button>
        ))}
      </div>

      <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`}>
        {tab === "summary" ? <SummaryTab store={s} onJump={(key) => setTab(key as (typeof TABS)[number]["key"])} /> : null}
        {tab === "damage" ? <DamageTab storeId={storeId} storeLabel={storeLabel} /> : null}
        {tab === "stock" ? <StockTab storeId={storeId} storeLabel={storeLabel} /> : null}
        {tab === "history" ? <HistoryTab storeId={storeId} storeLabel={storeLabel} /> : null}
        {tab === "products" ? <ProductsTab storeId={storeId} storeLabel={storeLabel} /> : null}
        {tab === "sales" ? (
          <SalesTab
            storeId={storeId}
            storeLabel={storeLabel}
            onView={setViewingSale}
            onEdit={setEditingSale}
            onDelete={setDeletingSale}
            refreshToken={salesToken}
          />
        ) : null}
        {tab === "payments" ? <PaymentsTab storeId={storeId} storeLabel={storeLabel} /> : null}
        {tab === "people" ? (
          <PeopleTab
            storeId={storeId}
            storeLabel={storeLabel}
            refreshToken={peopleToken}
            onAddUser={() => setAddingUser(true)}
          />
        ) : null}
      </div>

      {editing ? (
        <EditStoreModal
          store={s}
          onClose={() => setEditing(false)}
          onDone={() => {
            setEditing(false);
            store.reload();
          }}
        />
      ) : null}

      {addingUser ? (
        <AddStoreUserModal
          storeCode={s.code}
          storeId={storeId}
          onClose={() => setAddingUser(false)}
          onDone={() => {
            setAddingUser(false);
            setPeopleToken((n) => n + 1);
            store.reload();
          }}
        />
      ) : null}

      {viewingSale ? (
        <SaleDetailModal
          storeId={storeId}
          sale={viewingSale}
          onClose={() => setViewingSale(null)}
        />
      ) : null}

      {editingSale ? (
        <EditSaleModal
          storeId={storeId}
          sale={editingSale}
          onClose={() => setEditingSale(null)}
          onDone={() => {
            setEditingSale(null);
            setSalesToken((n) => n + 1);
            store.reload();
          }}
        />
      ) : null}

      {deletingSale ? (
        <DeleteSaleModal
          storeId={storeId}
          sale={deletingSale}
          onClose={() => setDeletingSale(null)}
          onDone={() => {
            setDeletingSale(null);
            setSalesToken((n) => n + 1);
            store.reload();
          }}
        />
      ) : null}

      {impersonating ? (
        <Modal title="Token tinjauan siap" onClose={() => setImpersonating(null)}>
          <Alert tone="info" title="Akses hanya baca">
            Token ini memakai hak BOS toko {s.code} dan berlaku {impersonating.expires_in_minutes} menit.
            Semua permintaan tulis akan ditolak, jadi aman dipakai untuk melihat masalah yang dilaporkan
            karyawan.
          </Alert>

          <p className="small muted mb-1">
            Simpan token ini bila perlu memeriksa dari alat lain. Setelah dipakai, tekan "Kembali ke
            Owner" untuk menyimpan token Owner yang sekarang.
          </p>

          <textarea
            className="form-control mono"
            readOnly
            value={impersonating.access_token}
            rows={5}
            aria-label="Token tinjauan"
          />

          <div className="d-flex gap-2">
            <button
              className="btn btn-primary"
              type="button"
              onClick={() => {
                navigator.clipboard?.writeText(impersonating.access_token);
                setImpersonating(null);
                toast("Token tinjauan disalin.");
              }}
            >
              Salin token
            </button>
            <button className="btn btn-soft" type="button" onClick={() => setImpersonating(null)}>
              Kembali ke Owner
            </button>
          </div>
        </Modal>
      ) : null}
    </>
  );
}

function AddStoreUserModal({
  storeId,
  storeCode,
  onClose,
  onDone,
}: {
  storeId: string;
  storeCode: string;
  onClose: () => void;
  onDone: () => void;
}) {
  const toast = useToast();
  const [username, setUsername] = useState("");
  const [fullName, setFullName] = useState("");
  const [role, setRole] = useState("KARYAWAN");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      await api.post(`/admin/stores/${storeId}/users`, {
        username: username.trim(),
        full_name: fullName,
        role,
        password,
      });
      toast(`${username} ditambahkan ke ${storeCode}.`);
      onDone();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menambah pengguna.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      title={`Tambah pengguna di ${storeCode}`}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-soft" type="button" onClick={onClose} disabled={busy}>
            Batal
          </button>
          <button
            className="btn btn-primary"
            type="button"
            onClick={submit}
            disabled={busy || username.trim().length < 3 || password.length < 8}
          >
            {busy ? "Menyimpan..." : "Tambah pengguna"}
          </button>
        </>
      }
    >
      {error ? (
        <div className="alert alert-bad" role="alert">
          <i className="bi bi-exclamation-triangle-fill" aria-hidden />
          <div className="alert-body">
            <div className="alert-msg">{error}</div>
          </div>
        </div>
      ) : null}

      <Field label="Nama pengguna" hint="Minimal 3 karakter.">
        <input
          className="form-control"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          placeholder={`mis. kar${storeCode.toLowerCase()}5`}
          minLength={3}
          maxLength={50}
        />
      </Field>

      <Field label="Nama lengkap">
        <input className="form-control" value={fullName} onChange={(e) => setFullName(e.target.value)} required />
      </Field>

      <Field label="Peran" hint="BOS punya hak ubah produk, harga, dan lihat laporan toko.">
        <select className="form-select" value={role} onChange={(e) => setRole(e.target.value)}>
          <option value="KARYAWAN">Karyawan</option>
          <option value="BOS">BOS</option>
        </select>
      </Field>

      <Field label="Kata sandi awal" hint="Minimal 8 karakter. Sampaikan ke pengguna lewat jalur aman.">
        <input
          className="form-control"
          type="text"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          minLength={8}
          maxLength={128}
          autoComplete="new-password"
        />
      </Field>
    </Modal>
  );
}

function EditStoreModal({
  store,
  onClose,
  onDone,
}: {
  store: StoreDetail;
  onClose: () => void;
  onDone: () => void;
}) {
  const toast = useToast();
  const [name, setName] = useState(store.name);
  const [ownerName, setOwnerName] = useState(store.owner_name);
  const [phone, setPhone] = useState(store.phone ?? "");
  const [address, setAddress] = useState(store.address ?? "");
  const [plan, setPlan] = useState<Plan>(store.plan);
  const [expires, setExpires] = useState(store.plan_expires_at?.slice(0, 10) ?? "");
  const [status, setStatus] = useState<string>(store.status);
  const [isActive, setIsActive] = useState(store.is_active);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      await api.patch(`/admin/stores/${store.id}`, {
        name,
        owner_name: ownerName,
        phone: phone || null,
        address: address || null,
        plan,
        plan_expires_at: dateInputToIsoDate(expires),
        status,
        is_active: isActive,
      });
      toast(`Toko ${store.code} diperbarui.`);
      onDone();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menyimpan perubahan.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      title={`Ubah ${store.code}`}
      onClose={onClose}
      wide
      footer={
        <>
          <button className="btn btn-soft" type="button" onClick={onClose} disabled={busy}>
            Batal
          </button>
          <button className="btn btn-primary" type="button" onClick={submit} disabled={busy}>
            {busy ? "Menyimpan..." : "Simpan"}
          </button>
        </>
      }
    >
      {error ? (
        <div className="alert alert-bad" role="alert">
          <i className="bi bi-exclamation-triangle-fill" aria-hidden />
          <div className="alert-body">
            <div className="alert-msg">{error}</div>
          </div>
        </div>
      ) : null}

      <div className="row g-3">
        <div className="col-12 col-md-6">
          <Field label="Nama toko">
            <input className="form-control" value={name} onChange={(e) => setName(e.target.value)} />
          </Field>
        </div>
        <div className="col-12 col-md-6">
          <Field label="Nama pemilik">
            <input className="form-control" value={ownerName} onChange={(e) => setOwnerName(e.target.value)} />
          </Field>
        </div>
        <div className="col-12 col-md-6">
          <Field label="Telepon">
            <input className="form-control" value={phone} onChange={(e) => setPhone(e.target.value)} />
          </Field>
        </div>
        <div className="col-12 col-md-6">
          <Field label="Alamat">
            <input className="form-control" value={address} onChange={(e) => setAddress(e.target.value)} />
          </Field>
        </div>
        <div className="col-12 col-md-4">
          <Field label="Paket">
            <select className="form-select" value={plan} onChange={(e) => setPlan(e.target.value as Plan)}>
              <option value="TRIAL">Uji coba</option>
              <option value="BASIC">Dasar</option>
              <option value="PRO">Pro</option>
              <option value="UNLIMITED">Tak terbatas</option>
            </select>
          </Field>
        </div>
        <div className="col-12 col-md-4">
          <Field label="Berlaku sampai">
            <input className="form-control" type="date" value={expires} onChange={(e) => setExpires(e.target.value)} />
          </Field>
        </div>
        <div className="col-12 col-md-4">
          <Field label="Status">
            <select className="form-select" value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="ACTIVE">Aktif</option>
              <option value="SUSPENDED">Ditangguhkan</option>
              <option value="EXPIRED">Kedaluwarsa</option>
            </select>
          </Field>
        </div>
        <div className="col-12">
          <Field label="Aktif">
            <select
              className="form-select"
              value={isActive ? "yes" : "no"}
              onChange={(e) => setIsActive(e.target.value === "yes")}
            >
              <option value="yes">Ya, karyawan bisa login</option>
              <option value="no">Tidak, kunci akses POS</option>
            </select>
          </Field>
        </div>
      </div>

      <p className="small muted mb-0">
        Menonaktifkan toko akan membuat semua sesi POS di toko ini berhenti saat token berikutnya
        diperiksa.
      </p>
    </Modal>
  );
}

function SaleDetailModal({
  storeId,
  sale,
  onClose,
}: {
  storeId: string;
  sale: AdminSale;
  onClose: () => void;
}) {
  const [detail, setDetail] = useState<AdminSaleDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    api
      .get<AdminSaleDetail>(`/admin/stores/${storeId}/sales/${sale.id}`)
      .then((d) => {
        if (active) setDetail(d);
      })
      .catch((e) => {
        if (active) setError(e instanceof Error ? e.message : "Gagal memuat detail transaksi.");
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [storeId, sale.id]);

  return (
    <Modal title={sale.transaction_number} onClose={onClose} wide>
      {error ? (
        <Alert tone="bad" title="Gagal memuat detail">
          {error}
        </Alert>
      ) : loading || !detail ? (
        <Loading label="Memuat detail transaksi" pattern="lines" />
      ) : (
        <>
          <div className="small muted mb-2">
            Kasir {detail.employee_name ?? "-"} - {dateTime(detail.created_at)}
          </div>

          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Produk</th>
                  <th className="text-end">Harga</th>
                  <th className="text-end">Qty</th>
                  <th className="text-end">Subtotal</th>
                </tr>
              </thead>
              <tbody>
                {detail.items.map((it) => (
                  <tr key={it.id}>
                    <td>{it.product_name}</td>
                    <td className="text-end">{money(it.unit_price)}</td>
                    <td className="text-end">
                      {num(it.quantity)} {it.unit}
                    </td>
                    <td className="text-end">{money(it.subtotal)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="d-flex flex-wrap justify-content-end align-items-center gap-2 mb-1">
            <span className="muted">Diskon</span>
            <span>-{money(detail.discount)}</span>
          </div>
          <div className="d-flex flex-wrap justify-content-end align-items-center gap-2 fw-semibold">
            <span>Total</span>
            <span>{money(detail.total_amount)}</span>
          </div>

          <hr style={{ borderColor: "var(--neo-border)" }} />

          <dl className="kv" style={{ minWidth: 200 }}>
            <dt>Pembayaran</dt>
            <dd>
              {detail.payment
                ? `${detail.payment.method} - ${money(detail.payment.amount)}`
                : "-"}
            </dd>
            {detail.payment?.reference ? (
              <>
                <dt>Referensi</dt>
                <dd className="mono">{detail.payment.reference}</dd>
              </>
            ) : null}
            {sale.status === "CANCELED" ? (
              <>
                <dt>Alasan batal</dt>
                <dd>{sale.canceled_reason ?? "-"}</dd>
              </>
            ) : null}
            <dt>Modal</dt>
            <dd>{money(detail.total_modal)}</dd>
            <dt>Laba</dt>
            <dd>{money(detail.total_profit)}</dd>
          </dl>

          {detail.edit_history.length > 0 ? (
            <>
              <h3 className="h6 mt-3 mb-2">Riwayat koreksi</h3>
              {detail.edit_history.map((log) => {
                let ringkas: string | null = null;
                try {
                  const parsed = JSON.parse(log.details ?? "null") as {
                    transaction_number?: string;
                    reason?: string;
                  };
                  ringkas = parsed.reason ?? null;
                } catch {
                  ringkas = null;
                }
                return (
                  <div
                    key={log.id}
                    className="neo-panel p-3 mb-2 d-flex flex-column gap-1"
                    style={{ background: "var(--neo-panel)" }}
                  >
                    <div className="d-flex flex-wrap gap-2 align-items-center">
                      <Badge tone={log.action === "SALE_DELETE" ? "bad" : "warn"}>
                        {log.action === "SALE_DELETE" ? "Dihapus owner" : "Dikoreksi"}
                      </Badge>
                      <span className="small">{log.username ?? "Owner"}</span>
                      <span className="small muted">{dateTime(log.created_at)}</span>
                    </div>
                    {ringkas ? <div className="small">{ringkas}</div> : null}
                    <details>
                      <summary className="small muted" style={{ cursor: "pointer" }}>
                        Lihat detail sebelum/sesudah
                      </summary>
                      <pre
                        className="mono small mt-2 p-2"
                        style={{
                          whiteSpace: "pre-wrap",
                          maxHeight: 240,
                          overflow: "auto",
                          background: "var(--neo-inset)",
                          borderRadius: 8,
                          margin: 0,
                        }}
                      >
                        {(() => {
                          try {
                            return JSON.stringify(JSON.parse(log.details ?? "null"), null, 2);
                          } catch {
                            return log.details ?? "";
                          }
                        })()}
                      </pre>
                    </details>
                  </div>
                );
              })}
            </>
          ) : null}
        </>
      )}
    </Modal>
  );
}

type EditLine = { product_id: string; quantity: string; unit_price: string };

function EditSaleModal({
  storeId,
  sale,
  onClose,
  onDone,
}: {
  storeId: string;
  sale: AdminSale;
  onClose: () => void;
  onDone: () => void;
}) {
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [products, setProducts] = useState<StoreProductLite[]>([]);
  const [lines, setLines] = useState<EditLine[]>([]);
  const [discount, setDiscount] = useState("0");
  const [reason, setReason] = useState("");
  const [method, setMethod] = useState("CASH");
  const [amount, setAmount] = useState("");
  const [cashReceived, setCashReceived] = useState("");
  const [changeAmount, setChangeAmount] = useState("");
  const [reference, setReference] = useState("");

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const [detail, prod] = await Promise.all([
          api.get<AdminSaleDetail>(`/admin/stores/${storeId}/sales/${sale.id}`),
          api.get<Paged<StoreProductLite>>(`/admin/stores/${storeId}/products`),
        ]);
        if (!active) return;
        setProducts(prod.items);
        setLines(
          detail.items.map((it) => ({
            product_id: it.product_id,
            quantity: String(it.quantity),
            unit_price: String(it.unit_price),
          })),
        );
        setDiscount(String(detail.discount));
        setMethod(detail.payment?.method ?? "CASH");
        setAmount(detail.payment ? String(detail.payment.amount) : "0");
        setCashReceived(detail.payment?.cash_received != null ? String(detail.payment.cash_received) : "");
        setChangeAmount(detail.payment?.change_amount != null ? String(detail.payment.change_amount) : "");
        setReference(detail.payment?.reference ?? "");
      } catch (e) {
        if (active) setError(e instanceof Error ? e.message : "Gagal memuat data transaksi.");
      } finally {
        if (active) setLoading(false);
      }
    })();
    return () => {
      active = false;
    };
  }, [storeId, sale.id]);

  const used = new Set(lines.map((l) => l.product_id));
  const totalBeforeDiscount = lines.reduce((acc, l) => {
    const q = parseFloat(l.quantity) || 0;
    const p = parseFloat(l.unit_price) || 0;
    return acc + q * p;
  }, 0);
  const disc = Math.max(0, parseFloat(discount) || 0);
  const total = Math.max(0, totalBeforeDiscount - disc);

  function addLine() {
    const fallback =
      products.find((p) => p.is_active && !used.has(p.id)) ??
      products.find((p) => p.is_active);
    if (!fallback) return;
    setLines((prev) => [
      ...prev,
      { product_id: fallback.id, quantity: "1", unit_price: String(fallback.selling_price || 0) },
    ]);
  }

  function setLine(index: number, patch: Partial<EditLine>) {
    setLines((prev) => prev.map((l, i) => (i === index ? { ...l, ...patch } : l)));
  }

  function removeLine(index: number) {
    setLines((prev) => prev.filter((_, i) => i !== index));
  }

  function isLineValid(line: EditLine): boolean {
    return !!line.product_id && (parseFloat(line.quantity) || 0) > 0;
  }

  async function submit() {
    if (lines.length === 0 || !lines.every(isLineValid)) {
      setError("Pastikan minimal satu item dengan jumlah lebih dari 0.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await api.patch(`/admin/stores/${storeId}/sales/${sale.id}`, {
        reason: reason.trim() || null,
        items: lines.map((l) => ({
          product_id: l.product_id,
          quantity: parseFloat(l.quantity),
          unit_price: parseFloat(l.unit_price) || 0,
        })),
        discount: disc,
        payment: {
          method,
          amount: parseFloat(amount) || 0,
          cash_received: cashReceived !== "" ? parseFloat(cashReceived) : null,
          change_amount: changeAmount !== "" ? parseFloat(changeAmount) : null,
          reference: reference.trim() || null,
        },
      });
      toast(`${sale.transaction_number} dikoreksi. Stok item disesuaikan otomatis.`);
      onDone();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menyimpan koreksi.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      title={`Koreksi ${sale.transaction_number}`}
      onClose={onClose}
      wide
      footer={
        <>
          <button className="btn btn-soft" type="button" onClick={onClose} disabled={busy}>
            Batal
          </button>
          <button
            className="btn btn-primary"
            type="button"
            onClick={submit}
            disabled={busy || loading || lines.length === 0}
          >
            {busy ? "Menyimpan..." : "Simpan koreksi"}
          </button>
        </>
      }
    >
      {error ? (
        <div className="alert alert-bad mb-3" role="alert">
          <i className="bi bi-exclamation-triangle-fill" aria-hidden />
          <div className="alert-body">
            <div className="alert-msg">{error}</div>
          </div>
        </div>
      ) : null}

      {loading ? (
        <Loading label="Memuat data untuk koreksi" pattern="lines" />
      ) : (
        <>
          <Alert tone="info" title="Stok disesuaikan otomatis">
            Item lama dikembalikan ke stok, item baru dipotong dari stok. Selisih jumlah & harga
            diperhitungkan dari data yang kamu masukkan sekarang.
          </Alert>

          <div className="d-flex flex-column gap-2 mt-3">
            {lines.map((line, i) => {
              const active =
                products.find((p) => p.id === line.product_id) ?? null;
              const subtotal = (parseFloat(line.quantity) || 0) * (parseFloat(line.unit_price) || 0);
              return (
                <div key={i} className="row g-2 align-items-center">
                  <div className="col-12 col-md-4">
                    <select
                      className="form-select"
                      value={line.product_id}
                      onChange={(e) => setLine(i, { product_id: e.target.value })}
                      aria-label={`Produk item ke-${i + 1}`}
                    >
                      {products.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.name} {p.is_active ? "" : "(nonaktif)"}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div className="col-4 col-md-2">
                    <input
                      className="form-control text-end"
                      type="number"
                      min="0"
                      step="any"
                      value={line.quantity}
                      onChange={(e) => setLine(i, { quantity: e.target.value })}
                      aria-label={`Jumlah item ke-${i + 1}`}
                    />
                  </div>
                  <div className="col-4 col-md-2">
                    <input
                      className="form-control text-end"
                      type="number"
                      min="0"
                      step="any"
                      value={line.unit_price}
                      onChange={(e) => setLine(i, { unit_price: e.target.value })}
                      aria-label={`Harga item ke-${i + 1}`}
                    />
                  </div>
                  <div className="col-4 col-md-3 text-end small muted">
                    {money(subtotal)}
                    {active ? <span className="ms-2 text-nowrap">stok {num(active.stock)}</span> : null}
                  </div>
                  <div className="col-12 col-md-1 d-flex justify-content-end">
                    <button
                      className="btn btn-soft btn-sm"
                      type="button"
                      onClick={() => removeLine(i)}
                      aria-label={`Hapus item ke-${i + 1}`}
                    >
                      <i className="bi bi-trash" aria-hidden />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>

          <button
            className="btn btn-outline-secondary btn-sm mt-2"
            type="button"
            onClick={addLine}
            disabled={products.length === 0}
          >
            <i className="bi bi-plus-lg" aria-hidden />
            Tambah item
          </button>

          <div className="row g-3 mt-1">
            <div className="col-12 col-md-6">
              <Field label="Diskon">
                <input
                  className="form-control text-end"
                  type="number"
                  min="0"
                  step="any"
                  value={discount}
                  onChange={(e) => setDiscount(e.target.value)}
                />
              </Field>
            </div>
            <div className="col-12 col-md-6">
              <Field label="Alasan koreksi" hint="Wajib diisi kalau mau ada catatan jelas di riwayat.">
                <input
                  className="form-control"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  maxLength={500}
                  placeholder="mis. qty salah ketik, uang kembalian keliru"
                />
              </Field>
            </div>
          </div>

          <div className="d-flex flex-wrap justify-content-end align-items-center gap-2 fw-semibold mt-3">
            <span className="muted fw-normal">Total setelah diskon</span>
            <span>{money(total)}</span>
          </div>

          <hr style={{ borderColor: "var(--neo-border)" }} />

          <div className="row g-3">
            <div className="col-12 col-md-4">
              <Field label="Metode pembayaran">
                <select className="form-select" value={method} onChange={(e) => setMethod(e.target.value)}>
                  <option value="CASH">Tunai</option>
                  <option value="TRANSFER">Transfer</option>
                  <option value="QRIS">QRIS</option>
                </select>
              </Field>
            </div>
            <div className="col-12 col-md-4">
              <Field label="Jumlah bayar">
                <input
                  className="form-control text-end"
                  type="number"
                  min="0"
                  step="any"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                />
              </Field>
            </div>
            <div className="col-12 col-md-4">
              <Field label="Referensi">
                <input
                  className="form-control"
                  value={reference}
                  onChange={(e) => setReference(e.target.value)}
                  maxLength={100}
                  placeholder="mis. nomor transfer"
                />
              </Field>
            </div>
            {method === "CASH" ? (
              <>
                <div className="col-12 col-md-6">
                  <Field label="Uang diterima">
                    <input
                      className="form-control text-end"
                      type="number"
                      min="0"
                      step="any"
                      value={cashReceived}
                      onChange={(e) => setCashReceived(e.target.value)}
                    />
                  </Field>
                </div>
                <div className="col-12 col-md-6">
                  <Field label="Kembalian">
                    <input
                      className="form-control text-end"
                      type="number"
                      min="0"
                      step="any"
                      value={changeAmount}
                      onChange={(e) => setChangeAmount(e.target.value)}
                    />
                  </Field>
                </div>
              </>
            ) : null}
          </div>
        </>
      )}
    </Modal>
  );
}

function DeleteSaleModal({
  storeId,
  sale,
  onClose,
  onDone,
}: {
  storeId: string;
  sale: AdminSale;
  onClose: () => void;
  onDone: () => void;
}) {
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reason, setReason] = useState("");

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      await api.post(`/admin/stores/${storeId}/sales/${sale.id}/delete`, {
        reason: reason.trim() || null,
      });
      toast(`${sale.transaction_number} dihapus. Stok item dikembalikan otomatis.`);
      onDone();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menghapus transaksi.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      title={`Hapus ${sale.transaction_number}`}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-soft" type="button" onClick={onClose} disabled={busy}>
            Batal
          </button>
          <button
            className="btn btn-danger"
            type="button"
            onClick={submit}
            disabled={busy || reason.trim().length === 0}
          >
            {busy ? "Menghapus..." : "Ya, hapus transaksi"}
          </button>
        </>
      }
    >
      {error ? (
        <div className="alert alert-bad mb-3" role="alert">
          <i className="bi bi-exclamation-triangle-fill" aria-hidden />
          <div className="alert-body">
            <div className="alert-msg">{error}</div>
          </div>
        </div>
      ) : null}

      <Alert tone="bad" title="Ini tindakan permanen">
        Transaksi {sale.transaction_number} ({sale.employee_name ?? "-"}, {money(sale.total_amount)})
        akan dibatalkan, <strong>stok semua item dikembalikan</strong>, dan transaksi
        tidak lagi dihitung dalam omzet/laporan. Riwayat transaksi & jejak audit
        tetap tersimpan.
      </Alert>

      <Field label="Alasan penghapusan" hint="Diperlukan supaya ada catatan jelas di riwayat.">
        <input
          className="form-control"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          maxLength={500}
          placeholder="mis. transaksi salah dimasukkan, duplikat"
        />
      </Field>
    </Modal>
  );
}