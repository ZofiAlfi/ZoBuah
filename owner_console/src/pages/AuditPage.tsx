import { Fragment, useState } from "react";

import { Badge, Empty, ErrorBox, Loading } from "../components/ui";
import { dateTime, num } from "../lib/format";
import { useFetch } from "../lib/useFetch";
import type { AuditLog, Paged } from "../lib/types";

/* Peta aksi ke warna lencana. Aksi yang tidak terdaftar tetap tampil biru
 * supaya jenis baru tidak ikut hilang dari bacaan. */
const ACTION_TONE: Record<string, string> = {
  LOGIN: "info",
  LOGIN_FAILED: "bad",
  LOGOUT: "muted",
  REFRESH: "muted",
  CREATE: "ok",
  UPDATE: "warn",
  DELETE: "bad",
  FORCE_LOGOUT: "bad",
  RESET_PASSWORD: "bad",
  IMPERSONATE: "warn",
  BROADCAST_CREATE: "info",
  BROADCAST_DEACTIVATE: "muted",
};

const ACTION_LABEL: Record<string, string> = {
  FORCE_LOGOUT: "Paksa keluar",
  RESET_PASSWORD: "Atur ulang sandi",
  IMPERSONATE: "Tinjau toko",
  BROADCAST_CREATE: "Buat broadcast",
  BROADCAST_DEACTIVATE: "Nonaktifkan broadcast",
  LOGIN_FAILED: "Gagal login",
};

export function AuditPage() {
  const [action, setAction] = useState("");
  const [page, setPage] = useState(1);
  const [expanded, setExpanded] = useState<string | null>(null);

  const query = new URLSearchParams({ page: String(page), page_size: "30" });
  if (action) query.set("action", action);

  const logs = useFetch<Paged<AuditLog>>(`/admin/audit-logs?${query.toString()}`, [action, page]);

  const items = logs.data?.items ?? [];

  return (
    <>
      <div className="neo-card">
        <div className="d-flex flex-wrap align-items-center gap-2" style={{ marginBottom: 0 }}>
          <h2 className="fs-5 mb-0">Jejak audit</h2>
          <div className="flex-grow-1" />
          <select
            className="form-select"
            value={action}
            onChange={(e) => {
              setAction(e.target.value);
              setPage(1);
            }}
            style={{ width: "auto", minWidth: 210 }}
            aria-label="Saring jenis aktivitas"
          >
            <option value="">Semua aktivitas</option>
            <option value="LOGIN">Login</option>
            <option value="LOGIN_FAILED">Gagal login</option>
            <option value="CREATE">Pembuatan data</option>
            <option value="UPDATE">Perubahan data</option>
            <option value="FORCE_LOGOUT">Paksa keluar</option>
            <option value="RESET_PASSWORD">Atur ulang sandi</option>
            <option value="IMPERSONATE">Tinjau toko</option>
          </select>
        </div>
      </div>

      {logs.loading ? (
        <Loading />
      ) : logs.error ? (
        <ErrorBox message={logs.error} onRetry={logs.reload} />
      ) : items.length === 0 ? (
        <Empty>Belum ada aktivitas yang tercatat.</Empty>
      ) : (
        <div className="neo-panel">
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Waktu</th>
                  <th>Aktor</th>
                  <th>Aktivitas</th>
                  <th>Toko</th>
                  <th>Keterangan</th>
                  <th>IP</th>
                </tr>
              </thead>
              <tbody>
                {items.map((log) => {
                  const isOpen = expanded === log.id;
                  const tone = ACTION_TONE[log.action] ?? "info";
                  const label = ACTION_LABEL[log.action] ?? log.action.replaceAll("_", " ").toLowerCase();

                  return (
                    <Fragment key={log.id}>
                      <tr>
                        <td className="small" style={{ whiteSpace: "nowrap" }}>
                          {dateTime(log.created_at)}
                        </td>
                        <td>
                          <div className="mono">{log.username ?? "sistem"}</div>
                        </td>
                        <td>
                          <Badge tone={tone}>{label}</Badge>
                          {log.entity_type ? (
                            <div className="small muted" style={{ marginTop: 3 }}>
                              {log.entity_type}
                            </div>
                          ) : null}
                        </td>
                        <td className="small">{log.store_name ?? "-"}</td>
                        <td className="small">
                          {log.details ? (
                            <div className="d-flex flex-column gap-1">
                              <span
                                style={{
                                  display: isOpen ? "block" : "none",
                                  whiteSpace: "pre-wrap",
                                  wordBreak: "break-word",
                                }}
                              >
                                {log.details}
                              </span>
                              <button
                                className="btn btn-soft btn-sm"
                                type="button"
                                onClick={() => setExpanded(isOpen ? null : log.id)}
                              >
                                {isOpen ? "Sembunyikan" : "Lihat"}
                              </button>
                            </div>
                          ) : (
                            "-"
                          )}
                        </td>
                        <td className="small mono">{log.ip_address ?? "-"}</td>
                      </tr>
                    </Fragment>
                  );
                })}
              </tbody>
            </table>
          </div>

          {logs.data && logs.data.meta.total_pages > 1 ? (
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
                Halaman {logs.data.meta.page} dari {logs.data.meta.total_pages} ({num(logs.data.meta.total)}{" "}
                baris)
              </span>
              <button
                className="btn btn-soft btn-sm"
                type="button"
                disabled={page >= logs.data.meta.total_pages}
                onClick={() => setPage((p) => p + 1)}
              >
                Berikutnya
              </button>
            </div>
          ) : null}
        </div>
      )}
    </>
  );
}