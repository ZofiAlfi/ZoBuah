import { useState } from "react";

import { useToast } from "../../components/AppShell";
import {
  DataTable,
  DataToolbar,
  DateRange,
  Pagination,
  PrintHead,
  SummaryBar,
  useSort,
} from "../../components/DataTable";
import type { Column } from "../../components/DataTable";
import { Alert, Badge, Modal } from "../../components/ui";
import { api } from "../../lib/api";
import { dateTime, num } from "../../lib/format";
import { usePagedTable } from "../../lib/usePagedTable";
import type { DamageReport, DamageSummary } from "../../lib/types";
import { describeFilters, exportTablePdf } from "../../print/exportPdf";
import { DAMAGE_REASONS, DAMAGE_STATUS, REJECT_REASON_MIN, reasonLabel } from "./shared";

export function DamageTab({ storeId, storeLabel }: { storeId: string; storeLabel: string }) {
  const toast = useToast();
  const table = usePagedTable<DamageReport, DamageSummary>(
    `/admin/stores/${storeId}/damage-reports`,
    { pageSize: 20 },
  );
  const { sort, setSort } = useSort({ key: "created", dir: "desc" });
  const [detail, setDetail] = useState<DamageReport | null>(null);

  const summary = table.summary;
  const subtitle = describeFilters([
    table.filters.status ? `Status ${DAMAGE_STATUS[table.filters.status]?.label ?? table.filters.status}` : null,
    table.filters.reason ? `Alasan ${reasonLabel(table.filters.reason)}` : null,
    table.dateFrom,
    table.dateTo,
    table.search ? `cari "${table.search}"` : null,
  ]);

  const columns: Column<DamageReport>[] = [
    {
      key: "created",
      header: "Waktu",
      sortable: true,
      sortValue: (r) => r.created_at ?? "",
      render: (r) => <span className="small muted">{dateTime(r.created_at)}</span>,
    },
    {
      key: "product",
      header: "Produk",
      sortable: true,
      sortValue: (r) => r.product_name ?? "",
      render: (r) => (
        <>
          <div>{r.product_name ?? "Produk sudah dihapus"}</div>
          <div className="small muted">
            {num(r.quantity)} {r.unit}
            {r.qty_in_base_unit != null ? ` (${num(r.qty_in_base_unit)} dasar)` : ""}
          </div>
        </>
      ),
    },
    {
      key: "reason",
      header: "Alasan",
      sortable: true,
      sortValue: (r) => r.reason,
      render: (r) => (
        <>
          <div>{reasonLabel(r.reason)}</div>
          {r.description ? <div className="small muted">{r.description}</div> : null}
        </>
      ),
    },
    {
      key: "employee",
      header: "Pelapor",
      render: (r) => <span className="small">{r.employee_name ?? "-"}</span>,
    },
    {
      key: "photos",
      header: "Foto",
      render: (r) =>
        r.photos.length > 0 ? (
          <i className="bi bi-camera-fill" aria-label={`${r.photos.length} foto terlampir`} />
        ) : (
          <span className="small muted">-</span>
        ),
    },
    {
      key: "status",
      header: "Status",
      sortable: true,
      sortValue: (r) => r.status,
      render: (r) => {
        const s = DAMAGE_STATUS[r.status] ?? { label: r.status, tone: "muted" };
        return (
          <Badge tone={s.tone}>
            {s.label}
            {r.status === "APPROVED" ? " - stok dipotong" : ""}
            {r.status === "REJECTED" ? " - stok utuh" : ""}
          </Badge>
        );
      },
    },
    {
      key: "action",
      header: "Aksi",
      align: "end",
      render: (r) => (
        <button
          className="btn btn-soft btn-sm"
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            setDetail(r);
          }}
        >
          <i className="bi bi-eye" aria-hidden />
          Detail
        </button>
      ),
    },
  ];

  return (
    <div className="neo-card">
      <PrintHead title="Laporan Barang Rusak" storeLabel={storeLabel} subtitle={subtitle} />

      <div className="card-head">
        <h2>Laporan barang rusak</h2>
        <div className="spacer" />
        <button
          className="btn btn-outline-primary btn-sm no-print"
          type="button"
          onClick={() =>
            exportTablePdf({
              title: `Laporan Barang Rusak ${storeLabel}`,
              subtitle: `${subtitle}${subtitle ? " - " : ""}${num(table.meta?.total ?? 0)} laporan`,
            })
          }
        >
          <i className="bi bi-file-earmark-pdf" aria-hidden />
          Ekspor PDF
        </button>
      </div>

      <SummaryBar
        items={[
          { label: "Total laporan", value: num(summary?.total ?? 0) },
          { label: "Menunggu", value: num(summary?.pending ?? 0), tone: "warn" },
          { label: "Disetujui", value: num(summary?.approved ?? 0), tone: "ok" },
          { label: "Ditolak", value: num(summary?.rejected ?? 0), tone: "bad" },
        ]}
      />

      <DataToolbar
        search={table.search}
        onSearch={table.setSearch}
        searchPlaceholder="Cari produk, alasan, keterangan..."
        onReset={table.clearFilters}
        hasFilter={Object.keys(table.filters).length > 0 || !!table.dateFrom || !!table.dateTo || !!table.search}
        filters={[
          {
            key: "status",
            label: "Saring status",
            value: table.filters.status ?? "",
            onChange: (v) => table.setFilter("status", v),
            options: [
              { value: "", label: "Semua status" },
              ...Object.entries(DAMAGE_STATUS).map(([value, s]) => ({ value, label: s.label })),
            ],
          },
          {
            key: "reason",
            label: "Saring alasan",
            value: table.filters.reason ?? "",
            onChange: (v) => table.setFilter("reason", v),
            options: DAMAGE_REASONS,
          },
        ]}
      >
        <DateRange
          from={table.dateFrom}
          to={table.dateTo}
          onFrom={table.setDateFrom}
          onTo={table.setDateTo}
        />
      </DataToolbar>

      <DataTable
        columns={columns}
        rows={table.items}
        rowKey={(r) => r.id}
        loading={table.loading}
        error={table.error}
        onRetry={table.reload}
        empty="Belum ada laporan barang rusak di toko ini."
        sort={sort}
        onSortChange={setSort}
      />

      <Pagination
        meta={table.meta}
        page={table.page}
        onPage={table.goToPage}
        pageSize={table.pageSize}
        onPageSize={table.setPageSize}
        unit="laporan"
      />

      {detail ? (
        <DamageDetailModal
          storeId={storeId}
          report={detail}
          onClose={() => setDetail(null)}
          onDone={(next, message) => {
            // Baris cukup di-patch supaya tabel tidak berkedip. Ringkasan
            // dihitung ulang dari server, jadi harus dimuat ulang: kalau tidak,
            // jumlah "Menunggu" masih yang lama padahal barisnya sudah final.
            table.patchItem(next.id, next);
            setDetail(next);
            table.reload();
            toast(message);
          }}
        />
      ) : null}
    </div>
  );
}

function DamageDetailModal({
  storeId,
  report,
  onClose,
  onDone,
}: {
  storeId: string;
  report: DamageReport;
  onClose: () => void;
  onDone: (next: DamageReport, message: string) => void;
}) {
  const toast = useToast();
  const [busy, setBusy] = useState<"approve" | "reject" | null>(null);
  const [rejecting, setRejecting] = useState(false);
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const pending = report.status === "PENDING";

  async function approve() {
    setBusy("approve");
    setError(null);
    try {
      const next = await api.post<DamageReport>(
        `/admin/stores/${storeId}/damage-reports/${report.id}/approve`,
      );
      onDone(next, `Laporan disetujui. Stok ${report.product_name ?? "produk"} sudah dipotong.`);
    } catch (e) {
      const message = e instanceof Error ? e.message : "Gagal menyetujui laporan.";
      setError(message);
      toast(message, "bad");
    } finally {
      setBusy(null);
    }
  }

  async function reject() {
    if (reason.trim().length < REJECT_REASON_MIN) {
      setError(`Alasan penolakan minimal ${REJECT_REASON_MIN} karakter.`);
      return;
    }
    setBusy("reject");
    setError(null);
    try {
      const next = await api.post<DamageReport>(
        `/admin/stores/${storeId}/damage-reports/${report.id}/reject`,
        { reason: reason.trim() },
      );
      setRejecting(false);
      setReason("");
      onDone(next, "Laporan ditolak. Stok produk tidak berubah.");
    } catch (e) {
      const message = e instanceof Error ? e.message : "Gagal menolak laporan.";
      setError(message);
      toast(message, "bad");
    } finally {
      setBusy(null);
    }
  }

  return (
    <Modal
      title={`Laporan barang rusak - ${report.product_name ?? "produk"}`}
      onClose={onClose}
      wide
      footer={
        pending ? (
          <>
            <button className="btn btn-soft" type="button" onClick={onClose} disabled={busy !== null}>
              Tutup
            </button>
            <button
              className="btn btn-outline-danger"
              type="button"
              onClick={() => setRejecting((v) => !v)}
              disabled={busy !== null}
            >
              <i className="bi bi-x-circle" aria-hidden />
              Tolak laporan
            </button>
            <button
              className="btn btn-primary"
              type="button"
              onClick={approve}
              disabled={busy !== null || rejecting}
            >
              {busy === "approve" ? "Memproses..." : "Setujui dan potong stok"}
            </button>
          </>
        ) : (
          <button className="btn btn-soft" type="button" onClick={onClose}>
            Tutup
          </button>
        )
      }
    >
      <dl className="kv" style={{ minWidth: 240 }}>
        <dt>Waktu laporan</dt>
        <dd>{dateTime(report.created_at)}</dd>
        <dt>Produk</dt>
        <dd>{report.product_name ?? "-"}</dd>
        <dt>Jumlah</dt>
        <dd>
          {num(report.quantity)} {report.unit}
          {report.qty_in_base_unit != null ? ` (${num(report.qty_in_base_unit)} satuan dasar)` : ""}
        </dd>
        <dt>Alasan</dt>
        <dd>{reasonLabel(report.reason)}</dd>
        {report.description ? (
          <>
            <dt>Keterangan</dt>
            <dd>{report.description}</dd>
          </>
        ) : null}
        <dt>Pelapor</dt>
        <dd>{report.employee_name ?? "-"}</dd>
        <dt>Status</dt>
        <dd>
          <Badge tone={DAMAGE_STATUS[report.status]?.tone ?? "muted"}>
            {DAMAGE_STATUS[report.status]?.label ?? report.status}
          </Badge>
        </dd>
        {report.approved_by_name ? (
          <>
            <dt>Disetujui oleh</dt>
            <dd>
              {report.approved_by_name} - {dateTime(report.approved_at)}
            </dd>
          </>
        ) : null}
        {report.rejected_by_name ? (
          <>
            <dt>Ditolak oleh</dt>
            <dd>
              {report.rejected_by_name} - {dateTime(report.rejected_at)}
            </dd>
            <dt>Alasan tolak</dt>
            <dd>{report.rejection_reason ?? "-"}</dd>
          </>
        ) : null}
      </dl>

      {report.photos.length > 0 ? (
        <>
          <h3 className="h6 mt-3 mb-2">Foto barang rusak</h3>
          <div className="d-flex flex-wrap gap-2">
            {report.photos.map((url) => (
              <a key={url} href={url} target="_blank" rel="noreferrer">
                <img
                  src={url}
                  alt={`Foto barang rusak ${report.product_name ?? ""}`}
                  style={{ width: 132, height: 132, objectFit: "cover", borderRadius: 10 }}
                />
              </a>
            ))}
          </div>
        </>
      ) : null}

      {error ? (
        <Alert tone="bad" title="Gagal memproses">
          {error}
        </Alert>
      ) : null}

      {rejecting ? (
        <div className="neo-panel p-3 mt-3">
          <Alert tone="warn" title="Stok tidak akan berkurang">
            Menolak laporan berarti barang dianggap tidak rusak. Stok produk tidak disentuh, jadi kalau
            barangnya memang hilang, catat lewat penyesuaian stok.
          </Alert>
          <label className="form-label fw-semibold" htmlFor="alasan-tolak">
            Alasan penolakan
          </label>
          <textarea
            id="alasan-tolak"
            className="form-control"
            rows={3}
            value={reason}
            maxLength={500}
            onChange={(e) => setReason(e.target.value)}
            placeholder="mis. barang masih layak jual, foto tidak jelas"
          />
          <div className="d-flex gap-2 mt-2">
            <button
              className="btn btn-outline-danger"
              type="button"
              onClick={reject}
              disabled={busy !== null || reason.trim().length < REJECT_REASON_MIN}
            >
              {busy === "reject" ? "Memproses..." : "Ya, tolak laporan"}
            </button>
            <button className="btn btn-soft" type="button" onClick={() => setRejecting(false)} disabled={busy !== null}>
              Batal
            </button>
          </div>
        </div>
      ) : null}
    </Modal>
  );
}
