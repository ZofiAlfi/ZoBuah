import {
  DataTable,
  DataToolbar,
  Pagination,
  PrintHead,
  useSort,
} from "../../components/DataTable";
import type { Column } from "../../components/DataTable";
import { Badge } from "../../components/ui";
import { money, num, qty } from "../../lib/format";
import { usePagedTable } from "../../lib/usePagedTable";
import type { StoreProductLite } from "../../lib/types";
import { describeFilters, exportTablePdf } from "../../print/exportPdf";

export function ProductsTab({ storeId, storeLabel }: { storeId: string; storeLabel: string }) {
  const table = usePagedTable<StoreProductLite>(`/admin/stores/${storeId}/products`, {
    pageSize: 100,
  });
  const { sort, setSort } = useSort({ key: "name", dir: "asc" });

  const subtitle = describeFilters([
    table.filters.is_active === "true"
      ? "Hanya produk aktif"
      : table.filters.is_active === "false"
        ? "Hanya produk nonaktif"
        : null,
    table.search ? `cari "${table.search}"` : null,
  ]);

  const columns: Column<StoreProductLite>[] = [
    {
      key: "name",
      header: "Produk",
      sortable: true,
      sortValue: (r) => r.name,
      render: (r) => (
        <>
          <div>{r.name}</div>
          <div className="small muted">{r.category_name ?? "Tanpa kategori"}</div>
        </>
      ),
    },
    {
      key: "modal",
      header: "Modal",
      align: "end",
      sortable: true,
      sortValue: (r) => r.modal_price,
      render: (r) => <span className="small">{money(r.modal_price)}</span>,
    },
    {
      key: "selling",
      header: "Harga jual",
      align: "end",
      sortable: true,
      sortValue: (r) => r.selling_price,
      render: (r) => money(r.selling_price),
    },
    {
      key: "margin",
      header: "Margin",
      align: "end",
      sortable: true,
      sortValue: (r) => r.selling_price - r.modal_price,
      render: (r) => (
        <span className="small muted">{money(r.selling_price - r.modal_price)}</span>
      ),
    },
    {
      key: "stock",
      header: "Stok",
      align: "end",
      sortable: true,
      sortValue: (r) => r.stock,
      render: (r) => qty(r.stock),
    },
    {
      key: "active",
      header: "Status",
      render: (r) => <Badge tone={r.is_active ? "ok" : "muted"}>{r.is_active ? "Aktif" : "Nonaktif"}</Badge>,
    },
  ];

  const totalStock = table.items.reduce((acc, p) => acc + (p.stock || 0), 0);

  return (
    <div className="neo-card">
      <PrintHead title="Produk" storeLabel={storeLabel} subtitle={subtitle} />

      <div className="card-head">
        <h2>Produk toko ini</h2>
        <div className="spacer" />
        <button
          className="btn btn-outline-primary btn-sm no-print"
          type="button"
          onClick={() =>
            exportTablePdf({
              title: `Produk ${storeLabel}`,
              subtitle: `${subtitle}${subtitle ? " - " : ""}${num(table.meta?.total ?? 0)} produk`,
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
        searchPlaceholder="Cari nama produk..."
        onReset={table.clearFilters}
        hasFilter={Object.keys(table.filters).length > 0 || !!table.search}
        filters={[
          {
            key: "is_active",
            label: "Saring status produk",
            value: table.filters.is_active ?? "",
            onChange: (v) => table.setFilter("is_active", v),
            options: [
              { value: "", label: "Aktif dan nonaktif" },
              { value: "true", label: "Hanya aktif" },
              { value: "false", label: "Hanya nonaktif" },
            ],
          },
        ]}
      />

      <DataTable
        columns={columns}
        rows={table.items}
        rowKey={(r) => r.id}
        loading={table.loading}
        error={table.error}
        onRetry={table.reload}
        empty="Belum ada produk di toko ini."
        sort={sort}
        onSortChange={setSort}
      />

      <p className="small muted mb-2">
        Total stok pada halaman ini: {num(totalStock)}. Halaman memuat {num(table.meta?.total ?? 0)} produk.
      </p>

      <Pagination
        meta={table.meta}
        page={table.page}
        onPage={table.goToPage}
        pageSize={table.pageSize}
        onPageSize={table.setPageSize}
        unit="produk"
      />
    </div>
  );
}
