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
import { dateTime, money, num } from "../../lib/format";
import { usePagedTable } from "../../lib/usePagedTable";
import type { AdminSale } from "../../lib/types";
import { describeFilters, exportTablePdf } from "../../print/exportPdf";

export function SalesTab({
  storeId,
  storeLabel,
  onView,
  onEdit,
  onDelete,
  refreshToken,
}: {
  storeId: string;
  storeLabel: string;
  onView: (sale: AdminSale) => void;
  onEdit: (sale: AdminSale) => void;
  onDelete: (sale: AdminSale) => void;
  refreshToken?: unknown;
}) {
  const table = usePagedTable<AdminSale>(`/admin/stores/${storeId}/sales`, {
    pageSize: 20,
    refreshToken,
  });
  const { sort, setSort } = useSort({ key: "created", dir: "desc" });

  const subtitle = describeFilters([
    table.filters.trx_status === "CANCELED" ? "Hanya transaksi batal" : null,
    table.dateFrom,
    table.dateTo,
    table.search ? `cari "${table.search}"` : null,
  ]);

  const columns: Column<AdminSale>[] = [
    {
      key: "number",
      header: "Nomor",
      sortable: true,
      sortValue: (r) => r.transaction_number,
      render: (r) => <span className="mono">{r.transaction_number}</span>,
    },
    {
      key: "created",
      header: "Waktu",
      sortable: true,
      sortValue: (r) => r.created_at ?? "",
      render: (r) => <span className="small muted">{dateTime(r.created_at)}</span>,
    },
    {
      key: "employee",
      header: "Kasir",
      sortable: true,
      sortValue: (r) => r.employee_name ?? "",
      render: (r) => r.employee_name ?? "-",
    },
    {
      key: "items",
      header: "Item",
      align: "end",
      sortable: true,
      sortValue: (r) => r.item_count,
      render: (r) => <span className="small">{num(r.item_count)}</span>,
    },
    {
      key: "profit",
      header: "Laba",
      align: "end",
      sortable: true,
      sortValue: (r) => r.total_profit,
      render: (r) => <span className="small muted">{money(r.total_profit)}</span>,
    },
    {
      key: "total",
      header: "Total",
      align: "end",
      sortable: true,
      sortValue: (r) => r.total_amount,
      render: (r) => <span className="fw-semibold">{money(r.total_amount)}</span>,
    },
    {
      key: "status",
      header: "Status",
      render: (r) => (
        <Badge tone={r.status === "COMPLETED" ? "ok" : "muted"}>
          {r.status === "COMPLETED" ? "Selesai" : "Batal"}
        </Badge>
      ),
    },
    {
      key: "action",
      header: "Aksi",
      align: "end",
      render: (r) => (
        <div className="d-flex gap-1 justify-content-end">
          <button
            className="btn btn-soft btn-sm"
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              onView(r);
            }}
            title="Lihat detail transaksi"
          >
            <i className="bi bi-eye" aria-hidden />
            <span className="visually-hidden">Detail {r.transaction_number}</span>
          </button>
          {r.status === "COMPLETED" ? (
            <>
              <button
                className="btn btn-outline-primary btn-sm"
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  onEdit(r);
                }}
                title="Koreksi transaksi ini kalau ada data yang salah"
              >
                <i className="bi bi-pencil-square" aria-hidden />
                Koreksi
              </button>
              <button
                className="btn btn-outline-danger btn-sm"
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  onDelete(r);
                }}
                title="Hapus transaksi ini (stok item akan dikembalikan)"
              >
                <i className="bi bi-trash" aria-hidden />
                Hapus
              </button>
            </>
          ) : null}
        </div>
      ),
    },
  ];

  return (
    <div className="neo-card">
      <PrintHead title="Penjualan" storeLabel={storeLabel} subtitle={subtitle} />

      <div className="card-head">
        <h2>Transaksi toko ini</h2>
        <div className="spacer" />
        <button
          className="btn btn-outline-primary btn-sm no-print"
          type="button"
          onClick={() =>
            exportTablePdf({
              title: `Penjualan ${storeLabel}`,
              subtitle: `${subtitle}${subtitle ? " - " : ""}${num(table.meta?.total ?? 0)} transaksi`,
            })
          }
        >
          <i className="bi bi-file-earmark-pdf" aria-hidden />
          Ekspor PDF
        </button>
      </div>

      <DataToolbar
        search={table.search}
        onSearch={table.setSearch}
        searchPlaceholder="Cari nomor transaksi..."
        onReset={table.clearFilters}
        hasFilter={Object.keys(table.filters).length > 0 || !!table.dateFrom || !!table.dateTo || !!table.search}
        filters={[
          {
            key: "trx_status",
            label: "Saring status transaksi",
            value: table.filters.trx_status ?? "",
            onChange: (v) => table.setFilter("trx_status", v),
            options: [
              { value: "", label: "Semua status" },
              { value: "COMPLETED", label: "Selesai" },
              { value: "CANCELED", label: "Batal" },
            ],
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
        empty="Belum ada transaksi tercatat di toko ini."
        sort={sort}
        onSortChange={setSort}
      />

      <Pagination
        meta={table.meta}
        page={table.page}
        onPage={table.goToPage}
        pageSize={table.pageSize}
        onPageSize={table.setPageSize}
        unit="transaksi"
      />
    </div>
  );
}
