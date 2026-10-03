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
import { dateTime, num } from "../../lib/format";
import { usePagedTable } from "../../lib/usePagedTable";
import type { StockMovement, StockSummary } from "../../lib/types";
import { describeFilters, exportTablePdf } from "../../print/exportPdf";
import { MOVEMENT_TYPES, movementLabel } from "./shared";

export function StockTab({ storeId, storeLabel }: { storeId: string; storeLabel: string }) {
  const table = usePagedTable<StockMovement, StockSummary>(
    `/admin/stores/${storeId}/stock-movements`,
    { pageSize: 20 },
  );
  const { sort, setSort } = useSort({ key: "created", dir: "desc" });
  const summary = table.summary;

  const subtitle = describeFilters([
    table.filters.movement_type ? movementLabel(table.filters.movement_type).label : null,
    table.dateFrom,
    table.dateTo,
    table.search ? `cari "${table.search}"` : null,
  ]);

  const columns: Column<StockMovement>[] = [
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
      render: (r) => <div>{r.product_name ?? "Produk sudah dihapus"}</div>,
    },
    {
      key: "type",
      header: "Jenis",
      sortable: true,
      sortValue: (r) => r.movement_type,
      render: (r) => {
        const m = movementLabel(r.movement_type);
        return <Badge tone={m.tone}>{m.label}</Badge>;
      },
    },
    {
      key: "qty",
      header: "Jumlah",
      align: "end",
      sortable: true,
      sortValue: (r) => r.quantity,
      render: (r) => (
        <span className={r.quantity < 0 ? "tone-bad" : undefined}>
          {r.quantity > 0 && r.movement_type === "IN" ? "+" : ""}
          {num(r.quantity)}
        </span>
      ),
    },
    {
      key: "stock",
      header: "Stok",
      align: "end",
      sortable: true,
      sortValue: (r) => r.stock_after,
      render: (r) => (
        <span className="small muted">
          {num(r.stock_before)} ke {num(r.stock_after)}
        </span>
      ),
    },
    {
      key: "notes",
      header: "Catatan",
      render: (r) => (
        <>
          <div className="small">{r.notes ?? "-"}</div>
          <div className="small muted">
            {r.user_name ?? "-"}
            {r.reference_type ? ` - ${r.reference_type}` : ""}
          </div>
        </>
      ),
    },
  ];

  return (
    <div className="neo-card">
      <PrintHead title="Pergerakan Stok" storeLabel={storeLabel} subtitle={subtitle} />

      <div className="card-head">
        <h2>Pergerakan stok</h2>
        <div className="spacer" />
        <button
          className="btn btn-outline-primary btn-sm no-print"
          type="button"
          onClick={() =>
            exportTablePdf({
              title: `Pergerakan Stok ${storeLabel}`,
              subtitle: `${subtitle}${subtitle ? " - " : ""}${num(table.meta?.total ?? 0)} baris`,
            })
          }
        >
          <i className="bi bi-file-earmark-pdf" aria-hidden />
          Ekspor PDF
        </button>
      </div>

      <SummaryBar
        items={[
          { label: "Total pergerakan", value: num(summary?.total_movements ?? 0) },
          { label: "Masuk", value: `+${num(summary?.in ?? 0)}`, tone: "ok" },
          { label: "Keluar", value: `-${num(summary?.out ?? 0)}`, tone: "bad" },
          { label: "Terjual", value: num(summary?.sale ?? 0) },
          { label: "Rusak", value: num(summary?.damage ?? 0), tone: "bad" },
          { label: "Penyesuaian", value: num(summary?.adjustment ?? 0) },
        ]}
      />

      <DataToolbar
        search={table.search}
        onSearch={table.setSearch}
        searchPlaceholder="Cari produk atau catatan..."
        onReset={table.clearFilters}
        hasFilter={Object.keys(table.filters).length > 0 || !!table.dateFrom || !!table.dateTo || !!table.search}
        filters={[
          {
            key: "movement_type",
            label: "Saring jenis pergerakan",
            value: table.filters.movement_type ?? "",
            onChange: (v) => table.setFilter("movement_type", v),
            options: MOVEMENT_TYPES,
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
        empty="Belum ada pergerakan stok tercatat di toko ini."
        sort={sort}
        onSortChange={setSort}
      />

      <Pagination
        meta={table.meta}
        page={table.page}
        onPage={table.goToPage}
        pageSize={table.pageSize}
        onPageSize={table.setPageSize}
        unit="pergerakan"
      />
    </div>
  );
}
