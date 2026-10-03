import {
  DataTable,
  DataToolbar,
  Pagination,
  PrintHead,
  useSort,
} from "../../components/DataTable";
import type { Column } from "../../components/DataTable";
import { Badge } from "../../components/ui";
import { dateShort, num, roleLabel } from "../../lib/format";
import { usePagedTable } from "../../lib/usePagedTable";
import type { AdminUser, StoreCategory } from "../../lib/types";
import { describeFilters, exportTablePdf } from "../../print/exportPdf";

export function PeopleTab({
  storeId,
  storeLabel,
  onAddUser,
}: {
  storeId: string;
  storeLabel: string;
  onAddUser: () => void;
}) {
  const categories = usePagedTable<StoreCategory>(`/admin/stores/${storeId}/categories`, {
    pageSize: 50,
  });
  const users = usePagedTable<AdminUser>(`/admin/stores/${storeId}/users`, {
    pageSize: 50,
    searchable: false,
  });
  const { sort, setSort } = useSort({ key: "name", dir: "asc" });

  const categorySubtitle = describeFilters([
    categories.filters.is_active === "true"
      ? "Hanya kategori aktif"
      : categories.filters.is_active === "false"
        ? "Hanya kategori nonaktif"
        : null,
    categories.search ? `cari "${categories.search}"` : null,
  ]);

  const categoryColumns: Column<StoreCategory>[] = [
    {
      key: "name",
      header: "Kategori",
      sortable: true,
      sortValue: (r) => r.name,
      render: (r) => (
        <>
          <div>{r.name}</div>
          {r.description ? <div className="small muted">{r.description}</div> : null}
        </>
      ),
    },
    {
      key: "products",
      header: "Jumlah produk",
      align: "end",
      sortable: true,
      sortValue: (r) => r.product_count,
      render: (r) => num(r.product_count),
    },
    {
      key: "active",
      header: "Status",
      render: (r) => <Badge tone={r.is_active ? "ok" : "muted"}>{r.is_active ? "Aktif" : "Nonaktif"}</Badge>,
    },
    {
      key: "created",
      header: "Dibuat",
      align: "end",
      sortable: true,
      sortValue: (r) => r.created_at ?? "",
      render: (r) => <span className="small muted">{dateShort(r.created_at)}</span>,
    },
  ];

  const userColumns: Column<AdminUser>[] = [
    {
      key: "username",
      header: "Nama pengguna",
      sortable: true,
      sortValue: (r) => r.username,
      render: (r) => <span className="mono">{r.username}</span>,
    },
    {
      key: "full_name",
      header: "Nama lengkap",
      sortable: true,
      sortValue: (r) => r.full_name,
      render: (r) => r.full_name,
    },
    {
      key: "role",
      header: "Peran",
      sortable: true,
      sortValue: (r) => r.role,
      render: (r) => roleLabel(r.role),
    },
    {
      key: "active",
      header: "Status",
      render: (r) => <Badge tone={r.is_active ? "ok" : "bad"}>{r.is_active ? "Aktif" : "Nonaktif"}</Badge>,
    },
    {
      key: "created",
      header: "Bergabung",
      align: "end",
      sortable: true,
      sortValue: (r) => r.created_at ?? "",
      render: (r) => <span className="small muted">{dateShort(r.created_at)}</span>,
    },
  ];

  return (
    <>
      <div className="neo-card">
        <PrintHead title="Kategori Produk" storeLabel={storeLabel} subtitle={categorySubtitle} />

        <div className="card-head">
          <h2>Kategori produk</h2>
          <div className="spacer" />
          <button
            className="btn btn-outline-primary btn-sm no-print"
            type="button"
            onClick={() =>
              exportTablePdf({
                title: `Kategori Produk ${storeLabel}`,
                subtitle: `${num(categories.meta?.total ?? 0)} kategori`,
              })
            }
          >
            <i className="bi bi-file-earmark-pdf" aria-hidden />
            Ekspor PDF
          </button>
        </div>

        <DataToolbar
          search={categories.search}
          onSearch={categories.setSearch}
          searchPlaceholder="Cari kategori..."
          onReset={categories.clearFilters}
          hasFilter={Object.keys(categories.filters).length > 0 || !!categories.search}
          filters={[
            {
              key: "is_active",
              label: "Saring status kategori",
              value: categories.filters.is_active ?? "",
              onChange: (v) => categories.setFilter("is_active", v),
              options: [
                { value: "", label: "Aktif dan nonaktif" },
                { value: "true", label: "Hanya aktif" },
                { value: "false", label: "Hanya nonaktif" },
              ],
            },
          ]}
        />

        <DataTable
          columns={categoryColumns}
          rows={categories.items}
          rowKey={(r) => r.id}
          loading={categories.loading}
          error={categories.error}
          onRetry={categories.reload}
          empty="Belum ada kategori di toko ini."
          sort={sort}
          onSortChange={setSort}
        />

        <Pagination
          meta={categories.meta}
          page={categories.page}
          onPage={categories.goToPage}
          pageSize={categories.pageSize}
          onPageSize={categories.setPageSize}
          unit="kategori"
        />
      </div>

      <div className="neo-card">
        <PrintHead title="Pengguna Toko" storeLabel={storeLabel} subtitle="" />

        <div className="card-head">
          <h2>Pengguna toko ini</h2>
          <div className="spacer" />
          <button
            className="btn btn-outline-primary btn-sm no-print"
            type="button"
            onClick={() =>
              exportTablePdf({
                title: `Pengguna Toko ${storeLabel}`,
                subtitle: `${num(users.meta?.total ?? 0)} pengguna`,
              })
            }
          >
            <i className="bi bi-file-earmark-pdf" aria-hidden />
            Ekspor PDF
          </button>
          <button className="btn btn-outline-primary btn-sm no-print" type="button" onClick={onAddUser}>
            <i className="bi bi-person-plus" aria-hidden />
            Tambah pengguna
          </button>
        </div>

        <DataTable
          columns={userColumns}
          rows={users.items}
          rowKey={(r) => r.id}
          loading={users.loading}
          error={users.error}
          onRetry={users.reload}
          empty="Belum ada pengguna di toko ini."
          sort={sort}
          onSortChange={setSort}
        />

        <Pagination
          meta={users.meta}
          page={users.page}
          onPage={users.goToPage}
          pageSize={users.pageSize}
          onPageSize={users.setPageSize}
          unit="pengguna"
        />
      </div>
    </>
  );
}
