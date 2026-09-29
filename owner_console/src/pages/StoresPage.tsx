import { useMemo, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";

import { useToast } from "../components/AppShell";
import { Badge, Empty, ErrorBox, Field, Modal, SkeletonLines } from "../components/ui";
import { api } from "../lib/api";
import { dateInputToIsoDate, healthLabel, money, num, planLabel, relative, statusLabel } from "../lib/format";
import { useFetch } from "../lib/useFetch";
import type { Paged, Plan, StoreListItem } from "../lib/types";

type Draft = {
  code: string;
  name: string;
  owner_name: string;
  phone: string;
  address: string;
  plan: Plan;
  plan_expires_at: string;
  bos_username: string;
  bos_full_name: string;
  bos_password: string;
};

const EMPTY_DRAFT: Draft = {
  code: "",
  name: "",
  owner_name: "",
  phone: "",
  address: "",
  plan: "BASIC",
  plan_expires_at: "",
  bos_username: "",
  bos_full_name: "",
  bos_password: "",
};

const PLAN_TONE: Record<Plan, string> = {
  PRO: "ok",
  BASIC: "info",
  TRIAL: "warn",
  UNLIMITED: "ok",
};

export function StoresPage() {
  const [search, setSearch] = useState("");
  const [plan, setPlan] = useState("all");
  const [status, setStatus] = useState("all");
  const [creating, setCreating] = useState(false);

  const query = new URLSearchParams({ page_size: "100" });
  if (plan !== "all") query.set("plan", plan);
  if (status !== "all") query.set("status", status);

  const { data, loading, error, reload } = useFetch<Paged<StoreListItem>>(
    `/admin/stores?${query.toString()}`,
    [plan, status],
  );

  const items = useMemo(() => {
    const list = data?.items ?? [];
    const q = search.trim().toLowerCase();
    if (!q) return list;
    return list.filter(
      (s) =>
        s.code.toLowerCase().includes(q) ||
        s.name.toLowerCase().includes(q) ||
        s.owner_name.toLowerCase().includes(q),
    );
  }, [data, search]);

  return (
    <>
      <div className="neo-card">
        <div className="d-flex flex-wrap align-items-center gap-2" style={{ marginBottom: 0 }}>
          <div className="search">
            <i className="bi bi-search" aria-hidden />
            <input
              className="form-control"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Cari kode, nama, atau pemilik"
              aria-label="Cari toko"
            />
          </div>

          <select
            className="form-select"
            value={plan}
            onChange={(e) => setPlan(e.target.value)}
            style={{ width: "auto", minWidth: 160 }}
            aria-label="Saring paket"
          >
            <option value="all">Semua paket</option>
            <option value="TRIAL">Uji coba</option>
            <option value="BASIC">Dasar</option>
            <option value="PRO">Pro</option>
            <option value="UNLIMITED">Tak terbatas</option>
          </select>

          <select
            className="form-select"
            value={status}
            onChange={(e) => setStatus(e.target.value)}
            style={{ width: "auto", minWidth: 160 }}
            aria-label="Saring status"
          >
            <option value="all">Semua status</option>
            <option value="ACTIVE">Aktif</option>
            <option value="SUSPENDED">Ditangguhkan</option>
            <option value="EXPIRED">Kedaluwarsa</option>
          </select>

          <div className="flex-grow-1" />

          <button className="btn btn-primary" type="button" onClick={() => setCreating(true)}>
            <i className="bi bi-plus-lg" aria-hidden />
            Tambah toko
          </button>
        </div>
      </div>

      {loading ? (
        <SkeletonLines count={10} />
      ) : error ? (
        <ErrorBox message={error} onRetry={reload} />
      ) : items.length === 0 ? (
        <Empty>Tidak ada toko yang cocok dengan filter ini.</Empty>
      ) : (
        <div className="neo-panel">
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Toko</th>
                  <th>Paket</th>
                  <th>Status</th>
                  <th>Sync</th>
                  <th className="right">Pengguna</th>
                  <th className="right">Produk</th>
                  <th className="right">Transaksi 30h</th>
                  <th className="right">Omzet 30h</th>
                  <th className="right">Aksi</th>
                </tr>
              </thead>
              <tbody>
                {items.map((s) => {
                  const h = healthLabel(s.health);
                  const st = statusLabel(s.status);
                  return (
                    <tr key={s.id}>
                      <td>
                        <div className="fw-semibold">{s.name}</div>
                        <div className="small muted">
                          {s.code} - {s.owner_name}
                        </div>
                      </td>
                      <td>
                        <Badge tone={PLAN_TONE[s.plan]}>{planLabel(s.plan)}</Badge>
                        <div className="small muted" style={{ marginTop: 3 }}>
                          {s.days_to_expiry === null
                            ? "Tanpa masa aktif"
                            : s.days_to_expiry < 0
                              ? `Kedaluwarsa ${Math.abs(s.days_to_expiry)} hari lalu`
                              : `${s.days_to_expiry} hari lagi`}
                        </div>
                      </td>
                      <td>
                        <Badge tone={st.tone}>{st.text}</Badge>
                      </td>
                      <td>
                        <Badge tone={h.tone}>{h.text}</Badge>
                        <div className="small muted" style={{ marginTop: 3 }}>
                          {relative(s.last_sync_at)}
                        </div>
                      </td>
                      <td className="right num">{num(s.user_count)}</td>
                      <td className="right num">{num(s.product_count)}</td>
                      <td className="right num">{num(s.sale_count_30d)}</td>
                      <td className="right num">{money(s.revenue_30d)}</td>
                      <td className="right">
                        <Link className="btn btn-outline-primary btn-sm" to={`/toko/${s.id}`}>
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
      )}

      {creating ? (
        <CreateStoreModal
          onClose={() => setCreating(false)}
          onDone={() => {
            setCreating(false);
            reload();
          }}
        />
      ) : null}
    </>
  );
}

function CreateStoreModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const toast = useToast();
  const [draft, setDraft] = useState<Draft>(EMPTY_DRAFT);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const set = <K extends keyof Draft>(key: K, value: Draft[K]) =>
    setDraft((d) => ({ ...d, [key]: value }));

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await api.post<{ store: StoreListItem; bos_created: boolean }>("/admin/stores", {
        code: draft.code,
        name: draft.name,
        owner_name: draft.owner_name,
        phone: draft.phone || null,
        address: draft.address || null,
        plan: draft.plan,
        /* Kolom ini DATE, bukan momen waktu. new Date("2026-12-31") dibaca
         * sebagai tengah malam UTC lalu di-toISOString(); kolom DATE di
         * server memotong bagian tanggalnya, dan konversi bolak-balik
         * itulah yang membuat tanggal berakhir bergeser sehari. Kirim
         * kalender apa adanya. */
        plan_expires_at: dateInputToIsoDate(draft.plan_expires_at),
        bos_username: draft.bos_username,
        bos_full_name: draft.bos_full_name,
        bos_password: draft.bos_password,
      });
      toast(`Toko ${res.store.code} dibuat${res.bos_created ? " beserta akun BOS" : ""}.`);
      onDone();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal membuat toko.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      title="Tambah toko"
      onClose={onClose}
      wide
      footer={
        <>
          <button className="btn btn-soft" type="button" onClick={onClose} disabled={busy}>
            Batal
          </button>
          <button className="btn btn-primary" type="submit" form="create-store" disabled={busy}>
            {busy ? "Menyimpan..." : "Buat toko"}
          </button>
        </>
      }
    >
      <form id="create-store" onSubmit={submit}>
        {error ? (
          <div className="alert alert-bad mb-3" role="alert">
            <i className="bi bi-exclamation-triangle-fill" aria-hidden />
            <div className="alert-body">
              <div className="alert-msg">{error}</div>
            </div>
          </div>
        ) : null}

        <div className="row g-3">
          <div className="col-12 col-md-4">
            <Field label="Kode toko" hint="Maksimal 10 karakter, jadi huruf besar.">
              <input
                className="form-control"
                value={draft.code}
                onChange={(e) => set("code", e.target.value.toUpperCase())}
                placeholder="T05"
                required
                maxLength={10}
              />
            </Field>
          </div>

          <div className="col-12 col-md-4">
            <Field label="Nama toko">
              <input
                className="form-control"
                value={draft.name}
                onChange={(e) => set("name", e.target.value)}
                placeholder="Toko Buah Segar"
                required
              />
            </Field>
          </div>

          <div className="col-12 col-md-4">
            <Field label="Nama pemilik">
              <input
                className="form-control"
                value={draft.owner_name}
                onChange={(e) => set("owner_name", e.target.value)}
                placeholder="Budi Santoso"
                required
              />
            </Field>
          </div>

          <div className="col-12 col-md-4">
            <Field label="Telepon">
              <input
                className="form-control"
                value={draft.phone}
                onChange={(e) => set("phone", e.target.value)}
                placeholder="08123456789"
              />
            </Field>
          </div>

          <div className="col-12 col-md-4">
            <Field label="Paket">
              <select className="form-select" value={draft.plan} onChange={(e) => set("plan", e.target.value as Plan)}>
                <option value="TRIAL">Uji coba</option>
                <option value="BASIC">Dasar</option>
                <option value="PRO">Pro</option>
                <option value="UNLIMITED">Tak terbatas</option>
              </select>
            </Field>
          </div>

          <div className="col-12 col-md-4">
            <Field label="Berlaku sampai" hint="Kosongkan untuk paket tanpa masa aktif.">
              <input
                className="form-control"
                type="date"
                value={draft.plan_expires_at}
                onChange={(e) => set("plan_expires_at", e.target.value)}
              />
            </Field>
          </div>

          <div className="col-12">
            <Field label="Alamat">
              <input
                className="form-control"
                value={draft.address}
                onChange={(e) => set("address", e.target.value)}
                placeholder="Jl. Merdeka No. 10"
              />
            </Field>
          </div>
        </div>

        <hr className="mt-4" style={{ borderColor: "var(--neo-line)" }} />

        <h3 className="mb-3">Akun BOS pertama</h3>
        <div className="row g-3">
          <div className="col-12 col-md-4">
            <Field label="Nama pengguna BOS">
              <input
                className="form-control"
                value={draft.bos_username}
                onChange={(e) => set("bos_username", e.target.value)}
                placeholder="bost05"
                required
                minLength={3}
              />
            </Field>
          </div>

          <div className="col-12 col-md-4">
            <Field label="Nama lengkap BOS">
              <input className="form-control" value={draft.bos_full_name} onChange={(e) => set("bos_full_name", e.target.value)} required />
            </Field>
          </div>

          <div className="col-12 col-md-4">
            <Field label="Kata sandi" hint="Minimal 8 karakter.">
              <input
                className="form-control"
                type="password"
                value={draft.bos_password}
                onChange={(e) => set("bos_password", e.target.value)}
                required
                minLength={8}
                autoComplete="new-password"
              />
            </Field>
          </div>
        </div>
      </form>
    </Modal>
  );
}