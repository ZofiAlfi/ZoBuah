import { useMemo, useState, type FormEvent } from "react";

import { useToast } from "../components/AppShell";
import { Badge, Empty, ErrorBox, Field, Loading, Modal } from "../components/ui";
import { api } from "../lib/api";
import { dateShort, num, roleLabel } from "../lib/format";
import { useFetch } from "../lib/useFetch";
import type { AdminUser, Paged, StoreListItem } from "../lib/types";

export function UsersPage() {
  const toast = useToast();
  const [search, setSearch] = useState("");
  const [store, setStore] = useState("all");
  const [role, setRole] = useState("all");
  const [page, setPage] = useState(1);
  const [resetting, setResetting] = useState<AdminUser | null>(null);
  const [loggingOut, setLoggingOut] = useState<AdminUser | null>(null);
  const [editing, setEditing] = useState<AdminUser | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const query = new URLSearchParams({ page: String(page), page_size: "25" });
  if (store !== "all") query.set("store_id", store);
  if (role !== "all") query.set("role", role);

  const users = useFetch<Paged<AdminUser>>(`/admin/users?${query.toString()}`, [store, role, page]);
  const stores = useFetch<{ items: StoreListItem[] }>("/admin/stores?page_size=100");

  const items = useMemo(() => {
    const list = users.data?.items ?? [];
    const q = search.trim().toLowerCase();
    if (!q) return list;
    return list.filter(
      (u) => u.username.toLowerCase().includes(q) || u.full_name.toLowerCase().includes(q),
    );
  }, [users.data, search]);

  async function toggleActive(u: AdminUser) {
    const next = !u.is_active;
    if (next === false && u.role === "BOS") {
      const bosCount = (users.data?.items ?? []).filter(
        (x) => x.store_id === u.store_id && x.role === "BOS" && x.is_active,
      ).length;
      if (bosCount <= 1) {
        toast("Tidak bisa menonaktifkan BOS terakhir di toko itu.", "bad");
        return;
      }
    }

    setBusyId(u.id);
    try {
      await api.patch(`/admin/users/${u.id}`, { is_active: next });
      toast(`${u.username} ${next ? "diaktifkan" : "dinonaktifkan"}.`);
      users.reload();
    } catch (e) {
      toast(e instanceof Error ? e.message : "Gagal mengubah status pengguna.", "bad");
    } finally {
      setBusyId(null);
    }
  }

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
              placeholder="Cari nama pengguna"
              aria-label="Cari pengguna"
            />
          </div>

          <select
            className="form-select"
            value={store}
            onChange={(e) => {
              setStore(e.target.value);
              setPage(1);
            }}
            style={{ width: "auto", minWidth: 180 }}
            aria-label="Saring toko"
          >
            <option value="all">Semua toko</option>
            {(stores.data?.items ?? []).map((s) => (
              <option key={s.id} value={s.id}>
                {s.code} - {s.name}
              </option>
            ))}
          </select>

          <select
            className="form-select"
            value={role}
            onChange={(e) => {
              setRole(e.target.value);
              setPage(1);
            }}
            style={{ width: "auto", minWidth: 140 }}
            aria-label="Saring peran"
          >
            <option value="all">Semua peran</option>
            <option value="BOS">BOS</option>
            <option value="KARYAWAN">Karyawan</option>
          </select>

          <div className="flex-grow-1" />
          <span className="small muted">
            {num(users.data?.meta.total ?? 0)} pengguna di seluruh toko
          </span>
        </div>
      </div>

      {users.loading ? (
        <Loading />
      ) : users.error ? (
        <ErrorBox message={users.error} onRetry={users.reload} />
      ) : items.length === 0 ? (
        <Empty>Tidak ada pengguna yang cocok.</Empty>
      ) : (
        <div className="neo-panel">
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Nama pengguna</th>
                  <th>Nama lengkap</th>
                  <th>Toko</th>
                  <th>Peran</th>
                  <th>Status</th>
                  <th>Bergabung</th>
                  <th className="right">Aksi</th>
                </tr>
              </thead>
              <tbody>
                {items.map((u) => (
                  <tr key={u.id}>
                    <td className="mono">{u.username}</td>
                    <td>{u.full_name}</td>
                    <td className="small">{u.store_name ?? "-"}</td>
                    <td>{roleLabel(u.role)}</td>
                    <td>
                      <Badge tone={u.is_active ? "ok" : "bad"}>
                        {u.is_active ? "Aktif" : "Nonaktif"}
                      </Badge>
                    </td>
                    <td className="small muted">{dateShort(u.created_at)}</td>
                    <td className="right">
                      <div className="d-flex justify-content-end gap-1 flex-wrap">
                        <button
                          className="btn btn-soft btn-sm"
                          type="button"
                          onClick={() => setEditing(u)}
                        >
                          Ubah
                        </button>
                        <button
                          className="btn btn-soft btn-sm"
                          type="button"
                          onClick={() => setResetting(u)}
                        >
                          Atur ulang sandi
                        </button>
                        <button
                          className="btn btn-warning btn-sm"
                          type="button"
                          disabled={busyId === u.id}
                          onClick={() => setLoggingOut(u)}
                        >
                          Paksa keluar
                        </button>
                        <button
                          className={`btn btn-sm ${u.is_active ? "btn-danger" : "btn-success"}`}
                          type="button"
                          disabled={busyId === u.id}
                          onClick={() => toggleActive(u)}
                        >
                          {u.is_active ? "Nonaktifkan" : "Aktifkan"}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {users.data && users.data.meta.total_pages > 1 ? (
            <div className="pager">
              <button
                className="btn btn-soft btn-sm"
                type="button"
                disabled={page <= 1}
                onClick={() => setPage((p) => p - 1)}
              >
                Sebelumnya
              </button>
              <span className="num">
                Halaman {users.data.meta.page} dari {users.data.meta.total_pages}
              </span>
              <button
                className="btn btn-soft btn-sm"
                type="button"
                disabled={page >= users.data.meta.total_pages}
                onClick={() => setPage((p) => p + 1)}
              >
                Berikutnya
              </button>
            </div>
          ) : null}
        </div>
      )}

      {resetting ? (
        <ResetPasswordModal
          user={resetting}
          onClose={() => setResetting(null)}
          onDone={() => {
            setResetting(null);
            users.reload();
          }}
        />
      ) : null}

      {loggingOut ? (
        <ForceLogoutModal
          user={loggingOut}
          onClose={() => setLoggingOut(null)}
          onDone={() => {
            setLoggingOut(null);
            users.reload();
          }}
        />
      ) : null}

      {editing ? (
        <EditUserModal
          user={editing}
          onClose={() => setEditing(null)}
          onDone={() => {
            setEditing(null);
            users.reload();
          }}
        />
      ) : null}
    </>
  );
}

function ResetPasswordModal({
  user,
  onClose,
  onDone,
}: {
  user: AdminUser;
  onClose: () => void;
  onDone: () => void;
}) {
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<{ username: string; temporary_password: string } | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      /* Tanpa body, dan memang harus begitu. Endpoint ini tidak menerima
       * sandi yang diketik owner: ia membuat sandi sementara sendiri lalu
       * mencabut semua token pengguna. Kalau body berisi new_password, field
       * itu diabaikan diam-diam dan owner berakhir mengira sandi yang dia
       * ketik sudah aktif padahal tidak. */
      const res = await api.post<{ username: string; temporary_password: string }>(
        `/admin/users/${user.id}/reset-password`,
      );
      setResult({ username: res.username, temporary_password: res.temporary_password });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Gagal mengatur ulang sandi.");
    } finally {
      setBusy(false);
    }
  }

  if (result) {
    return (
      <Modal
        title={`Sandi sementara untuk ${result.username}`}
        onClose={onDone}
        footer={
          <>
            <button
              className="btn btn-primary"
              type="button"
              onClick={() => {
                navigator.clipboard?.writeText(result.temporary_password);
                toast("Sandi sementara disalin.");
              }}
            >
              Salin sandi
            </button>
            <button className="btn btn-soft" type="button" onClick={onDone}>
              Selesai
            </button>
          </>
        }
      >
        <div className="alert alert-info" role="status">
          <i className="bi bi-info-circle-fill" aria-hidden />
          <div className="alert-body">
            <div className="alert-msg">
              Sampaikan sandi ini ke pengguna lewat jalur aman, lalu minta mereka langsung mengganti
              sandinya setelah masuk. Semua sesi pengguna ini sudah dikeluarkan.
            </div>
          </div>
        </div>

        <Field label="Sandi sementara">
          <input
            className="form-control mono"
            type="text"
            readOnly
            value={result.temporary_password}
            onFocus={(e) => e.currentTarget.select()}
          />
        </Field>
      </Modal>
    );
  }

  return (
    <Modal
      title={`Atur ulang sandi ${user.username}`}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-soft" type="button" onClick={onClose} disabled={busy}>
            Batal
          </button>
          <button className="btn btn-primary" type="submit" form="reset-password" disabled={busy}>
            {busy ? "Membuat sandi..." : "Buat sandi sementara"}
          </button>
        </>
      }
    >
      <form id="reset-password" onSubmit={submit}>
        {error ? (
          <div className="alert alert-bad mb-3" role="alert">
            <i className="bi bi-exclamation-triangle-fill" aria-hidden />
            <div className="alert-body">
              <div className="alert-msg">{error}</div>
            </div>
          </div>
        ) : null}

        <p className="small muted mb-0">
          Sistem membuat sandi sementara yang acak, sandi yang diketik tidak ada. Semua sesi aktif{" "}
          {user.username} langsung dikeluarkan, jadi pengguna harus masuk lagi dengan sandi baru ini.
        </p>
      </form>
    </Modal>
  );
}

function ForceLogoutModal({
  user,
  onClose,
  onDone,
}: {
  user: AdminUser;
  onClose: () => void;
  onDone: () => void;
}) {
  const toast = useToast();
  const [busy, setBusy] = useState(false);

  async function run() {
    setBusy(true);
    try {
      const res = await api.post<{ revoked_sessions?: number }>(`/admin/users/${user.id}/force-logout`);
      toast(`${user.username} dipaksa keluar. ${num(res.revoked_sessions ?? 0)} sesi dicabut.`);
      onDone();
    } catch (e) {
      toast(e instanceof Error ? e.message : "Gagal memaksa pengguna keluar.", "bad");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      title={`Paksa ${user.username} keluar`}
      onClose={onClose}
      footer={
        <>
          <button className="btn btn-soft" type="button" onClick={onClose} disabled={busy}>
            Batal
          </button>
          <button className="btn btn-warning" type="button" onClick={run} disabled={busy}>
            {busy ? "Memproses..." : "Paksa keluar sekarang"}
          </button>
        </>
      }
    >
      <div className="alert alert-warn">
        <i className="bi bi-exclamation-triangle-fill" aria-hidden />
        <div className="alert-body">
          <div className="alert-title">Transaksi yang belum tersinkron tetap aman</div>
          <div className="alert-msg">
            Data di perangkat tidak ikut terhapus, jadi transaksi yang belum terkirim ke server akan
            dikirim ulang setelah pengguna login kembali.
          </div>
        </div>
      </div>
      <p className="small muted mb-0">
        Gunakan ini ketika menduga kata sandi bocor atau perangkat hilang.
      </p>
    </Modal>
  );
}

function EditUserModal({
  user,
  onClose,
  onDone,
}: {
  user: AdminUser;
  onClose: () => void;
  onDone: () => void;
}) {
  const toast = useToast();
  const [fullName, setFullName] = useState(user.full_name);
  const [role, setRole] = useState<string>(user.role);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      await api.patch(`/admin/users/${user.id}`, { full_name: fullName, role });
      toast(`${user.username} diperbarui.`);
      onDone();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menyimpan perubahan.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      title={`Ubah ${user.username}`}
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

      <Field label="Nama lengkap">
        <input className="form-control" value={fullName} onChange={(e) => setFullName(e.target.value)} required />
      </Field>

      <Field
        label="Peran"
        hint="Menurunkan BOS terakhir di toko tidak diperbolehkan, supaya tidak ada toko tanpa akun pengawas."
      >
        <select className="form-select" value={role} onChange={(e) => setRole(e.target.value)}>
          <option value="KARYAWAN">Karyawan</option>
          <option value="BOS">BOS</option>
        </select>
      </Field>
    </Modal>
  );
}