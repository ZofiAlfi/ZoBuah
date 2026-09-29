import { useState, type FormEvent } from "react";

import { useToast } from "../components/AppShell";
import { Badge, Empty, ErrorBox, Field, Loading, Modal } from "../components/ui";
import { api } from "../lib/api";
import { dateTime, instantToLocalInput, localInputToIsoUtc } from "../lib/format";
import { useFetch } from "../lib/useFetch";
import type { Broadcast, StoreListItem } from "../lib/types";

const LEVEL_TONE = { INFO: "info", WARNING: "warn", MAINTENANCE: "bad" } as const;
const LEVEL_ICON = { INFO: "bi-info-circle", WARNING: "bi-exclamation-triangle", MAINTENANCE: "bi-tools" } as const;
const LEVEL_LABEL = { INFO: "Info", WARNING: "Peringatan", MAINTENANCE: "Pemeliharaan" } as const;

type Draft = {
  title: string;
  body: string;
  level: "INFO" | "WARNING" | "MAINTENANCE";
  target: "ALL" | "STORE";
  store_id: string;
  starts_at: string;
  expires_at: string;
};

const EMPTY: Draft = {
  title: "",
  body: "",
  level: "INFO",
  target: "ALL",
  store_id: "",
  /* Default "sekarang" ditulis sebagai WIB, bukan waktu lokal mesin. Kalau
   * admin membuka console dari luar Indonesia, angka jam yang diketik harus
   * tetap berarti WIB -- itu yang membuat broadcast tayang pada jam yang
   * dijanjikan. */
  starts_at: instantToLocalInput(new Date().toISOString()),
  expires_at: "",
};

export function BroadcastsPage() {
  const toast = useToast();
  const [showInactive, setShowInactive] = useState(true);
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<Broadcast | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const list = useFetch<{ items: Broadcast[] }>("/admin/broadcasts?page_size=100");
  const stores = useFetch<{ items: StoreListItem[] }>("/admin/stores?page_size=100");

  const now = Date.now();
  /* Perbandingan ini benar karena backend mengirim UTC dengan suffix Z.
   * Tanpa suffix itu, new Date() akan menafsirkan angka UTC sebagai waktu
   * lokal browser dan status "sudah tayang" bisa meleset 7 jam -- broadcast
   * yang baru dibuat terlihat belum aktif, atau yang sudah berakhir masih
   * tampil. Jangan diubah jadi .slice(0,16) seperti nilai input form. */
  const visible = (list.data?.items ?? []).filter((b) => {
    const started = new Date(b.starts_at).getTime() <= now;
    const notExpired = !b.expires_at || new Date(b.expires_at).getTime() > now;
    return showInactive || (b.is_active && started && notExpired);
  });

  async function deactivate(id: string, title: string) {
    if (!window.confirm(`Nonaktifkan broadcast "${title}"? Toko tidak akan melihatnya lagi.`)) return;
    setBusyId(id);
    try {
      await api.del(`/admin/broadcasts/${id}`);
      toast(`Broadcast "${title}" dinonaktifkan.`);
      list.reload();
    } catch (e) {
      toast(e instanceof Error ? e.message : "Gagal menonaktifkan broadcast.", "bad");
    } finally {
      setBusyId(null);
    }
  }

  return (
    <>
      <div className="neo-card">
        <div className="d-flex flex-wrap align-items-center gap-2" style={{ marginBottom: 0 }}>
          <h2 className="fs-5 mb-0">Broadcast ke aplikasi POS</h2>
          <div className="flex-grow-1" />
          <label className="d-flex align-items-center gap-2 small muted" style={{ cursor: "pointer" }}>
            <input
              type="checkbox"
              className="form-check-input mt-0"
              checked={showInactive}
              onChange={(e) => setShowInactive(e.target.checked)}
            />
            Tampilkan yang tidak aktif
          </label>
          <button className="btn btn-primary" type="button" onClick={() => setCreating(true)}>
            <i className="bi bi-plus-lg" aria-hidden />
            Broadcast baru
          </button>
        </div>
      </div>

      {list.loading ? (
        <Loading />
      ) : list.error ? (
        <ErrorBox message={list.error} onRetry={list.reload} />
      ) : visible.length === 0 ? (
        <Empty>Belum ada broadcast.</Empty>
      ) : (
        <div className="row g-3">
          {visible.map((b) => {
            const started = new Date(b.starts_at).getTime() <= now;
            const expired = b.expires_at !== null && new Date(b.expires_at).getTime() <= now;
            const live = b.is_active && started && !expired;

            return (
              <div className="col-12 col-xl-6" key={b.id}>
                <div className="neo-card neo-card-hover h-100">
                  <div className="card-head">
                    <Badge tone={LEVEL_TONE[b.level]}>{LEVEL_LABEL[b.level]}</Badge>
                    <Badge tone={live ? "ok" : "muted"}>
                      {live ? "Ditayangkan" : expired ? "Sudah lewat" : !b.is_active ? "Nonaktif" : "Terjadwal"}
                    </Badge>
                    <div className="spacer" />
                    <button
                      className="btn btn-soft btn-sm"
                      type="button"
                      onClick={() => setEditing(b)}
                    >
                      <i className="bi bi-pencil" aria-hidden />
                      Ubah
                    </button>
                    {b.is_active ? (
                      <button
                        className="btn btn-outline-primary btn-sm"
                        type="button"
                        disabled={busyId === b.id}
                        onClick={() => deactivate(b.id, b.title)}
                      >
                        Nonaktifkan
                      </button>
                    ) : null}
                  </div>

                  <h3 className="d-flex align-items-center gap-2">
                    <i className={`bi ${LEVEL_ICON[b.level]}`} style={{ color: "var(--neo-acc)" }} aria-hidden />
                    {b.title}
                  </h3>
                  <p className="mb-3" style={{ whiteSpace: "pre-wrap" }}>
                    {b.body}
                  </p>

                  <dl className="kv">
                    <dt>Target</dt>
                    <dd style={{ fontWeight: 500 }}>
                      {b.target === "ALL" ? "Semua toko" : (b.store_name ?? b.store_id)}
                    </dd>
                    <dt>Mulai</dt>
                    <dd>{dateTime(b.starts_at)}</dd>
                    <dt>Berakhir</dt>
                    <dd>{b.expires_at ? dateTime(b.expires_at) : "Tanpa akhir"}</dd>
                    <dt>Dibuat oleh</dt>
                    <dd style={{ fontWeight: 500 }}>{b.created_by ?? "-"}</dd>
                  </dl>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {creating ? (
        <CreateBroadcastModal
          stores={stores.data?.items ?? []}
          onClose={() => setCreating(false)}
          onDone={() => {
            setCreating(false);
            list.reload();
          }}
        />
      ) : null}
      {editing ? (
        <EditBroadcastModal
          broadcast={editing}
          onClose={() => setEditing(null)}
          onDone={() => {
            setEditing(null);
            list.reload();
          }}
        />
      ) : null}
    </>
  );
}

function EditBroadcastModal({
  broadcast,
  onClose,
  onDone,
}: {
  broadcast: Broadcast;
  onClose: () => void;
  onDone: () => void;
}) {
  const toast = useToast();
  const [title, setTitle] = useState(broadcast.title);
  const [body, setBody] = useState(broadcast.body);
  const [level, setLevel] = useState(broadcast.level);
  /* Disalin sebagai WIB, bukan slice(0,16). Memotong "2026-09-28T16:51:18Z"
   * menghasilkan "2026-09-28T16:51" -- jam UTC yang lalu ditampilkan di
   * input dan disimpan kembali apa adanya, jadi setiap edit menggeser jadwal
   * 7 jam tanpa disadari. */
  const [startsAt, setStartsAt] = useState(instantToLocalInput(broadcast.starts_at));
  const [expiresAt, setExpiresAt] = useState(
    broadcast.expires_at ? instantToLocalInput(broadcast.expires_at) : "",
  );
  const [isActive, setIsActive] = useState(broadcast.is_active);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      await api.patch(`/admin/broadcasts/${broadcast.id}`, {
        title,
        body,
        level,
        is_active: isActive,
        starts_at: localInputToIsoUtc(startsAt),
        expires_at: expiresAt ? localInputToIsoUtc(expiresAt) : null,
      });
      toast(`Broadcast "${title}" diperbarui.`);
      onDone();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menyimpan broadcast.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      title="Ubah broadcast"
      onClose={onClose}
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

      <Field label="Judul">
        <input className="form-control" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={120} required />
      </Field>

      <Field label="Isi pesan">
        <textarea className="form-control" value={body} onChange={(e) => setBody(e.target.value)} maxLength={4000} required />
      </Field>

      <div className="row g-3">
        <div className="col-12 col-md-6">
          <Field label="Tingkat">
            <select className="form-select" value={level} onChange={(e) => setLevel(e.target.value as Broadcast["level"])}>
              <option value="INFO">Info</option>
              <option value="WARNING">Peringatan</option>
              <option value="MAINTENANCE">Pemeliharaan</option>
            </select>
          </Field>
        </div>

        <div className="col-12 col-md-6">
          <Field label="Status">
            <select className="form-select" value={isActive ? "yes" : "no"} onChange={(e) => setIsActive(e.target.value === "yes")}>
              <option value="yes">Aktif</option>
              <option value="no">Nonaktif</option>
            </select>
          </Field>
        </div>

        <div className="col-12 col-md-6">
          <Field label="Mulai tayang" hint="Waktu Indonesia Barat (WIB).">
            <input
              className="form-control"
              type="datetime-local"
              value={startsAt}
              onChange={(e) => setStartsAt(e.target.value)}
              required
            />
          </Field>
        </div>

        <div className="col-12 col-md-6">
          <Field label="Berakhir" hint="WIB. Kosongkan bila tanpa batas waktu.">
            <input
              className="form-control"
              type="datetime-local"
              value={expiresAt}
              onChange={(e) => setExpiresAt(e.target.value)}
            />
          </Field>
        </div>
      </div>

      <p className="small muted mb-0">
        Target tidak bisa diubah setelah broadcast dibuat, supaya riwayat yang sudah dibaca toko
        tetap punya arti. Nonaktifkan dan buat yang baru bila targetnya salah.
      </p>
    </Modal>
  );
}

function CreateBroadcastModal({
  stores,
  onClose,
  onDone,
}: {
  stores: StoreListItem[];
  onClose: () => void;
  onDone: () => void;
}) {
  const toast = useToast();
  const [draft, setDraft] = useState<Draft>(EMPTY);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const set = <K extends keyof Draft>(key: K, value: Draft[K]) =>
    setDraft((d) => ({ ...d, [key]: value }));

  /* Aturan yang sama juga diperiksa server. Menegur di sini menghemat satu
   * klik, tapi validasi server tetap jadi penentu. */
  const targetInvalid = draft.target === "STORE" && !draft.store_id;

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api.post("/admin/broadcasts", {
        title: draft.title,
        body: draft.body,
        level: draft.level,
        target: draft.target,
        store_id: draft.target === "STORE" ? draft.store_id : null,
        starts_at: localInputToIsoUtc(draft.starts_at),
        expires_at: draft.expires_at ? localInputToIsoUtc(draft.expires_at) : null,
      });
      toast(`Broadcast "${draft.title}" dikirim.`);
      onDone();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal mengirim broadcast.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      title="Broadcast baru"
      onClose={onClose}
      wide
      footer={
        <>
          <button className="btn btn-soft" type="button" onClick={onClose} disabled={busy}>
            Batal
          </button>
          <button
            className="btn btn-primary"
            type="submit"
            form="create-broadcast"
            disabled={busy || targetInvalid}
          >
            {busy ? "Mengirim..." : "Kirim broadcast"}
          </button>
        </>
      }
    >
      <form id="create-broadcast" onSubmit={submit}>
        {error ? (
          <div className="alert alert-bad mb-3" role="alert">
            <i className="bi bi-exclamation-triangle-fill" aria-hidden />
            <div className="alert-body">
              <div className="alert-msg">{error}</div>
            </div>
          </div>
        ) : null}

        <Field label="Judul">
          <input
            className="form-control"
            value={draft.title}
            onChange={(e) => set("title", e.target.value)}
            placeholder="Pemeliharaan malam ini"
            required
            maxLength={120}
          />
        </Field>

        <Field label="Isi pesan">
          <textarea
            className="form-control"
            value={draft.body}
            onChange={(e) => set("body", e.target.value)}
            placeholder="Server akan dinonaktifkan pukul 23.00 WIB. Simpan transaksi sebelum jam itu."
            required
          />
        </Field>

        <div className="row g-3">
          <div className="col-12 col-md-6">
            <Field label="Tingkat">
              <select className="form-select" value={draft.level} onChange={(e) => set("level", e.target.value as Draft["level"])}>
                <option value="INFO">Info</option>
                <option value="WARNING">Peringatan</option>
                <option value="MAINTENANCE">Pemeliharaan</option>
              </select>
            </Field>
          </div>

          <div className="col-12 col-md-6">
            <Field label="Target" error={targetInvalid ? "Pilih toko tujuan." : undefined}>
              <select className="form-select" value={draft.target} onChange={(e) => set("target", e.target.value as Draft["target"])}>
                <option value="ALL">Semua toko</option>
                <option value="STORE">Satu toko</option>
              </select>
            </Field>
          </div>

          {draft.target === "STORE" ? (
            <div className="col-12 col-md-6">
              <Field label="Toko tujuan">
                <select className="form-select" value={draft.store_id} onChange={(e) => set("store_id", e.target.value)}>
                  <option value="">Pilih toko...</option>
                  {stores.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.code} - {s.name}
                    </option>
                  ))}
                </select>
              </Field>
            </div>
          ) : null}

          <div className="col-12 col-md-6">
            <Field label="Mulai tayang" hint="Waktu Indonesia Barat (WIB).">
              <input
                className="form-control"
                type="datetime-local"
                value={draft.starts_at}
                onChange={(e) => set("starts_at", e.target.value)}
                required
              />
            </Field>
          </div>

          <div className="col-12 col-md-6">
            <Field label="Berakhir" hint="WIB. Kosongkan bila tidak ada batas waktu.">
              <input
                className="form-control"
                type="datetime-local"
                value={draft.expires_at}
                onChange={(e) => set("expires_at", e.target.value)}
              />
            </Field>
          </div>
        </div>

        <p className="small muted mb-0">
          Broadcast hanya dibaca, jadi aplikasi POS mengambilnya lewat sync. Untuk hal yang tidak
          boleh terlewat, sampaikan juga lewat telepon ke toko tujuan.
        </p>
      </form>
    </Modal>
  );
}