import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";

import { useToast } from "../components/AppShell";
import { Alert, Badge, Empty, ErrorBox, Field, Kpi, Loading, Modal } from "../components/ui";
import { CountUp } from "../components/countup";
import { api } from "../lib/api";
import { dateInputToIsoDate, dateShort, dateTime, healthLabel, money, num, planLabel, relative, roleLabel, statusLabel } from "../lib/format";
import { useFetch } from "../lib/useFetch";
import type { AdminSale, AdminSaleDetail, AdminUser, ImpersonateResult, Paged, Plan, StoreDetail, StoreProductLite } from "../lib/types";

const PLAN_TONE: Record<Plan, string> = {
  PRO: "ok",
  BASIC: "info",
  TRIAL: "warn",
  UNLIMITED: "ok",
};

export function StoreDetailPage() {
  const { storeId = "" } = useParams();
  const toast = useToast();

  const store = useFetch<StoreDetail>(`/admin/stores/${storeId}`);
  const users = useFetch<{ items: AdminUser[] }>(`/admin/stores/${storeId}/users`);
  const sales = useFetch<Paged<AdminSale>>(`/admin/stores/${storeId}/sales`);

  const [editing, setEditing] = useState(false);
  const [addingUser, setAddingUser] = useState(false);
  const [impersonating, setImpersonating] = useState<ImpersonateResult | null>(null);
  const [viewingSale, setViewingSale] = useState<AdminSale | null>(null);
  const [editingSale, setEditingSale] = useState<AdminSale | null>(null);

  if (store.loading) return <Loading />;
  if (store.error) return <ErrorBox message={store.error} onRetry={store.reload} />;
  if (!store.data) return <ErrorBox message="Toko tidak ditemukan." />;

  const s = store.data;
  const h = healthLabel(s.health);
  const st = statusLabel(s.status);

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

      {s.status !== "ACTIVE" ? (
        <Alert tone="bad" title="Toko ini sedang tidak aktif">
          Karyawan tidak bisa masuk POS di toko ini sampai statusnya dikembalikan ke Aktif.
        </Alert>
      ) : null}

      <div className="row g-3">
        <div className="col-12 col-sm-6 col-xl-4 col-xxl-2">
          <Kpi
            icon="bi-cash-stack"
            label="Omzet 30 hari"
            value={<CountUp value={s.revenue_30d} format={money} />}
            sub={<><CountUp value={s.sale_count_30d} format={num} /> transaksi</>}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-4 col-xxl-2">
          <Kpi
            icon="bi-wallet2"
            label="Omzet total"
            value={<CountUp value={s.lifetime_revenue} format={money} />}
            sub={<><CountUp value={s.total_sales} format={num} /> transaksi</>}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-4 col-xxl-2">
          <Kpi
            icon="bi-people"
            label="Pengguna"
            value={<CountUp value={s.user_count} format={num} />}
            sub={`${num(users.data?.items.length ?? 0)} dimuat`}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-4 col-xxl-2">
          <Kpi
            icon="bi-box-seam"
            label="Produk"
            value={<CountUp value={s.product_count} format={num} />}
            sub={`${num(s.category_count)} kategori`}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-4 col-xxl-2">
          <Kpi
            icon="bi-phone"
            label="Perangkat"
            value={<CountUp value={s.device_count} format={num} />}
            sub={`${num(s.failed_sync_count_7d)} sync gagal 7h`}
          />
        </div>
        <div className="col-12 col-sm-6 col-xl-4 col-xxl-2">
          <Kpi
            icon="bi-exclamation-triangle"
            label="Stok menipis"
            value={<CountUp value={s.low_stock_count} format={num} />}
            sub={`${num(s.pending_damage_count)} laporan rusak pending`}
            tone={s.low_stock_count > 0 ? "warn" : "ok"}
          />
        </div>
      </div>

      <div className="neo-card">
        <div className="card-head">
          <h2>Transaksi toko ini</h2>
          <div className="spacer" />
          <span className="small muted">{num(sales.data?.meta.total ?? 0)} total</span>
        </div>

        {sales.loading ? (
          <Loading label="Memuat transaksi" pattern="lines" />
        ) : sales.error ? (
          <ErrorBox message={sales.error} onRetry={sales.reload} />
        ) : (sales.data?.items.length ?? 0) === 0 ? (
          <Empty>Belum ada transaksi tercatat di toko ini.</Empty>
        ) : (
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Nomor</th>
                  <th>Waktu</th>
                  <th>Kasir</th>
                  <th className="text-end">Item</th>
                  <th className="text-end">Total</th>
                  <th>Status</th>
                  <th aria-label="Aksi" />
                </tr>
              </thead>
              <tbody>
                {sales.data!.items.map((sale) => (
                  <tr key={sale.id}>
                    <td className="mono">{sale.transaction_number}</td>
                    <td className="small muted">{dateTime(sale.created_at)}</td>
                    <td>{sale.employee_name ?? "-"}</td>
                    <td className="text-end">{num(sale.item_count)}</td>
                    <td className="text-end">{money(sale.total_amount)}</td>
                    <td>
                      <Badge tone={sale.status === "COMPLETED" ? "ok" : "muted"}>
                        {sale.status === "COMPLETED" ? "Selesai" : "Batal"}
                      </Badge>
                    </td>
                    <td>
                      <div className="d-flex gap-1 justify-content-end">
                        <button
                          className="btn btn-soft btn-sm"
                          type="button"
                          onClick={() => setViewingSale(sale)}
                          title="Lihat detail transaksi"
                        >
                          <i className="bi bi-eye" aria-hidden />
                          <span className="visually-hidden">Detail {sale.transaction_number}</span>
                        </button>
                        {sale.status === "COMPLETED" ? (
                          <button
                            className="btn btn-outline-primary btn-sm"
                            type="button"
                            onClick={() => setEditingSale(sale)}
                            title="Koreksi transaksi ini kalau ada data yang salah"
                          >
                            <i className="bi bi-pencil-square" aria-hidden />
                            Koreksi
                          </button>
                        ) : null}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="neo-card">
        <div className="card-head">
          <h2>Pengguna toko ini</h2>
          <div className="spacer" />
          <button className="btn btn-outline-primary btn-sm" type="button" onClick={() => setAddingUser(true)}>
            <i className="bi bi-person-plus" aria-hidden />
            Tambah pengguna
          </button>
          <Link className="small" to="/pengguna">
            Kelola semua pengguna
          </Link>
        </div>

        {users.loading ? (
          <Loading label="Memuat pengguna" pattern="lines" />
        ) : users.error ? (
          <ErrorBox message={users.error} onRetry={users.reload} />
        ) : (users.data?.items.length ?? 0) === 0 ? (
          <Empty>Belum ada pengguna di toko ini.</Empty>
        ) : (
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Nama pengguna</th>
                  <th>Nama lengkap</th>
                  <th>Peran</th>
                  <th>Status</th>
                  <th>Bergabung</th>
                </tr>
              </thead>
              <tbody>
                {users.data!.items.map((u) => (
                  <tr key={u.id}>
                    <td className="mono">{u.username}</td>
                    <td>{u.full_name}</td>
                    <td>{roleLabel(u.role)}</td>
                    <td>
                      <Badge tone={u.is_active ? "ok" : "bad"}>
                        {u.is_active ? "Aktif" : "Nonaktif"}
                      </Badge>
                    </td>
                    <td className="small muted">{dateShort(u.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
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
            users.reload();
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
            sales.reload();
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
                      <Badge tone="warn">Dikoreksi</Badge>
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