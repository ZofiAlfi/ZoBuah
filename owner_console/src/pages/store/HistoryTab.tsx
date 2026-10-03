import { useState } from "react";

import {
  DataTable,
  DataToolbar,
  DateRange,
  Pagination,
  PrintHead,
  useSort,
} from "../../components/DataTable";
import type { Column } from "../../components/DataTable";
import { Badge } from "../../components/ui";
import { dateTime, num } from "../../lib/format";
import { usePagedTable } from "../../lib/usePagedTable";
import type { ProductHistoryEntry } from "../../lib/types";
import { describeFilters, exportTablePdf } from "../../print/exportPdf";
import { PRODUCT_ACTIONS, actionLabel } from "./shared";

export function HistoryTab({ storeId, storeLabel }: { storeId: string; storeLabel: string }) {
  const table = usePagedTable<ProductHistoryEntry>(
    `/admin/stores/${storeId}/product-history`,
    { pageSize: 20 },
  );
  const { sort, setSort } = useSort({ key: "created", dir: "desc" });
  const [expanded, setExpanded] = useState<string | null>(null);

  const subtitle = describeFilters([
    table.filters.action ? actionLabel(table.filters.action).label : null,
    table.dateFrom,
    table.dateTo,
    table.search ? `cari "${table.search}"` : null,
  ]);

  const columns: Column<ProductHistoryEntry>[] = [
    {
      key: "created",
      header: "Waktu",
      sortable: true,
      sortValue: (r) => r.created_at ?? "",
      render: (r) => <span className="small muted">{dateTime(r.created_at)}</span>,
    },
    {
      key: "action",
      header: "Aktivitas",
      sortable: true,
      sortValue: (r) => r.action,
      render: (r) => {
        const a = actionLabel(r.action);
        return <Badge tone={a.tone}>{a.label}</Badge>;
      },
    },
    {
      key: "product",
      header: "Produk",
      sortable: true,
      sortValue: (r) => r.product_name ?? "",
      render: (r) => (
        <>
          <div>{r.product_name ?? "-"}</div>
          <div className="small muted mono">{r.product_id ?? "-"}</div>
        </>
      ),
    },
    {
      key: "user",
      header: "Pelaku",
      render: (r) => (
        <>
          <div className="small">{r.user_name ?? "-"}</div>
          {r.ip_address ? <div className="small muted mono">{r.ip_address}</div> : null}
        </>
      ),
    },
    {
      key: "details",
      header: "Rincian",
      align: "end",
      render: (r) => (
        <button
          className="btn btn-soft btn-sm"
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            setExpanded((prev) => (prev === r.id ? null : r.id));
          }}
          aria-expanded={expanded === r.id}
        >
          {expanded === r.id ? "Tutup" : "Lihat"}
        </button>
      ),
    },
  ];

  const openRow = table.items.find((r) => r.id === expanded);

  return (
    <div className="neo-card">
      <PrintHead title="Riwayat Produk" storeLabel={storeLabel} subtitle={subtitle} />

      <div className="card-head">
        <h2>Riwayat produk</h2>
        <div className="spacer" />
        <button
          className="btn btn-outline-primary btn-sm no-print"
          type="button"
          onClick={() =>
            exportTablePdf({
              title: `Riwayat Produk ${storeLabel}`,
              subtitle: `${subtitle}${subtitle ? " - " : ""}${num(table.meta?.total ?? 0)} aktivitas`,
            })
          }
        >
          <i className="bi bi-file-earmark-pdf" aria-hidden />
          Ekspor PDF
        </button>
      </div>

      <p className="small muted">
        Sumbernya jejak audit, bukan tabel produk. Tabel produk tidak menyimpan siapa yang menambah atau
        mengubah barang, jadi daftar perubahan hanya bisa dibaca dari audit.
      </p>

      <DataToolbar
        search={table.search}
        onSearch={table.setSearch}
        searchPlaceholder="Cari nama produk atau id..."
        onReset={table.clearFilters}
        hasFilter={Object.keys(table.filters).length > 0 || !!table.dateFrom || !!table.dateTo || !!table.search}
        filters={[
          {
            key: "action",
            label: "Saring aktivitas",
            value: table.filters.action ?? "",
            onChange: (v) => table.setFilter("action", v),
            options: PRODUCT_ACTIONS.map((a) => ({ value: a.value, label: a.label })),
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
        empty="Belum ada riwayat perubahan produk di toko ini."
        sort={sort}
        onSortChange={setSort}
      />

      {openRow ? (
        <pre
          className="mono small mt-2 p-2"
          style={{
            whiteSpace: "pre-wrap",
            maxHeight: 280,
            overflow: "auto",
            background: "var(--neo-inset)",
            borderRadius: 8,
            margin: 0,
          }}
        >
          {JSON.stringify(openRow.details ?? {}, null, 2)}
        </pre>
      ) : null}

      <Pagination
        meta={table.meta}
        page={table.page}
        onPage={table.goToPage}
        pageSize={table.pageSize}
        onPageSize={table.setPageSize}
        unit="aktivitas"
      />
    </div>
  );
}
