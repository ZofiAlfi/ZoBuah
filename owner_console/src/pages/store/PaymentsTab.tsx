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
import { Badge } from "../../components/ui";
import { dateTime, money, num } from "../../lib/format";
import { usePagedTable } from "../../lib/usePagedTable";
import type { Payment, PaymentSummary } from "../../lib/types";
import { describeFilters, exportTablePdf } from "../../print/exportPdf";
import { PAYMENT_METHODS, methodLabel } from "./shared";

export function PaymentsTab({ storeId, storeLabel }: { storeId: string; storeLabel: string }) {
  const table = usePagedTable<Payment, PaymentSummary>(`/admin/stores/${storeId}/payments`, {
    pageSize: 20,
  });
  const { sort, setSort } = useSort({ key: "created", dir: "desc" });
  const summary = table.summary;
  const byMethod = summary?.by_method ?? {};

  const subtitle = describeFilters([
    table.filters.method ? methodLabel(table.filters.method) : null,
    table.dateFrom,
    table.dateTo,
    table.search ? `cari "${table.search}"` : null,
  ]);

  const columns: Column<Payment>[] = [
    {
      key: "created",
      header: "Waktu",
      sortable: true,
      sortValue: (r) => r.created_at ?? "",
      render: (r) => <span className="small muted">{dateTime(r.created_at)}</span>,
    },
    {
      key: "trx",
      header: "Transaksi",
      sortable: true,
      sortValue: (r) => r.transaction_number ?? "",
      render: (r) => (
        <>
          <div className="mono">{r.transaction_number ?? "-"}</div>
          <div className="small muted">{r.employee_name ?? "-"}</div>
        </>
      ),
    },
    {
      key: "method",
      header: "Metode",
      sortable: true,
      sortValue: (r) => r.method,
      render: (r) => <Badge tone="info">{methodLabel(r.method)}</Badge>,
    },
    {
      key: "amount",
      header: "Nominal",
      align: "end",
      sortable: true,
      sortValue: (r) => r.amount,
      render: (r) => <span className="fw-semibold">{money(r.amount)}</span>,
    },
    {
      key: "cash",
      header: "Diterima / kembalian",
      align: "end",
      render: (r) => (
        <span className="small muted">
          {r.cash_received != null ? money(r.cash_received) : "-"}
          {r.change_amount != null ? ` / ${money(r.change_amount)}` : ""}
        </span>
      ),
    },
    {
      key: "reference",
      header: "Referensi",
      render: (r) => (
        <>
          <div className="small mono">{r.reference ?? "-"}</div>
          {r.sale_status === "CANCELED" ? (
            <Badge tone="muted">Transaksi batal</Badge>
          ) : r.file_url ? (
            <a className="small" href={r.file_url} target="_blank" rel="noreferrer">
              Lihat bukti
            </a>
          ) : null}
        </>
      ),
    },
  ];

  return (
    <div className="neo-card">
      <PrintHead title="Pembayaran" storeLabel={storeLabel} subtitle={subtitle} />

      <div className="card-head">
        <h2>Pembayaran</h2>
        <div className="spacer" />
        <button
          className="btn btn-outline-primary btn-sm no-print"
          type="button"
          onClick={() =>
            exportTablePdf({
              title: `Pembayaran ${storeLabel}`,
              subtitle: `${subtitle}${subtitle ? " - " : ""}${num(summary?.total_payments ?? 0)} pembayaran`,
            })
          }
        >
          <i className="bi bi-file-earmark-pdf" aria-hidden />
          Ekspor PDF
        </button>
      </div>

      <SummaryBar
        items={[
          { label: "Total diterima", value: money(summary?.total_amount ?? 0) },
          { label: "Jumlah pembayaran", value: num(summary?.total_payments ?? 0) },
          ...PAYMENT_METHODS.filter((m) => m.value !== "").map((m) => ({
            label: m.label,
            value: money(byMethod[m.value] ?? 0),
          })),
        ]}
      />

      <DataToolbar
        search={table.search}
        onSearch={table.setSearch}
        searchPlaceholder="Cari nomor transaksi..."
        onReset={table.clearFilters}
        hasFilter={Object.keys(table.filters).length > 0 || !!table.dateFrom || !!table.dateTo || !!table.search}
        filters={[
          {
            key: "method",
            label: "Saring metode pembayaran",
            value: table.filters.method ?? "",
            onChange: (v) => table.setFilter("method", v),
            options: PAYMENT_METHODS,
          },
        ]}
      >
        <DateRange from={table.dateFrom} to={table.dateTo} onFrom={table.setDateFrom} onTo={table.setDateTo} />
      </DataToolbar>

      <DataTable
        columns={columns}
        rows={table.items}
        rowKey={(r) => r.id}
        loading={table.loading}
        error={table.error}
        onRetry={table.reload}
        empty="Belum ada pembayaran tercatat di toko ini."
        sort={sort}
        onSortChange={setSort}
      />

      <Pagination
        meta={table.meta}
        page={table.page}
        onPage={table.goToPage}
        pageSize={table.pageSize}
        onPageSize={table.setPageSize}
        unit="pembayaran"
      />
    </div>
  );
}
