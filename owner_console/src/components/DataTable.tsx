import { useMemo, useState, type ReactNode } from "react";

import { Empty, ErrorBox, Loading } from "./ui";

export type Column<T> = {
  key: string;
  header: string;
  align?: "start" | "end";
  /** Kolom ini bisa diurutkan di sisi peramban. */
  sortable?: boolean;
  /** Nilai yang dipakai saat pengurutan. Kosong berarti pakai teks sel. */
  sortValue?: (row: T) => string | number;
  render: (row: T) => ReactNode;
};

export type SortState = { key: string; dir: "asc" | "desc" };

export function SummaryBar({ items }: { items: { label: string; value: ReactNode; tone?: string }[] }) {
  if (items.length === 0) return null;
  return (
    <div className="summary-bar no-print-summary">
      {items.map((it) => (
        <div className="summary-cell" key={it.label}>
          <span className="summary-label">{it.label}</span>
          <span className={`summary-value${it.tone ? ` tone-${it.tone}` : ""}`}>{it.value}</span>
        </div>
      ))}
    </div>
  );
}

export type ToolbarFilter = {
  key: string;
  label: string;
  value: string;
  options: { value: string; label: string }[];
  onChange: (value: string) => void;
};

export function DataToolbar({
  search,
  onSearch,
  searchPlaceholder,
  filters = [],
  onReset,
  hasFilter,
  children,
}: {
  search?: string;
  onSearch?: (value: string) => void;
  searchPlaceholder?: string;
  filters?: ToolbarFilter[];
  onReset?: () => void;
  hasFilter?: boolean;
  children?: ReactNode;
}) {
  return (
    <div className="data-toolbar no-print">
      {onSearch ? (
        <div className="search" style={{ minWidth: 210 }}>
          <i className="bi bi-search" aria-hidden />
          <input
            className="form-control"
            type="search"
            value={search ?? ""}
            placeholder={searchPlaceholder ?? "Cari..."}
            aria-label={searchPlaceholder ?? "Cari data"}
            onChange={(e) => onSearch(e.target.value)}
          />
        </div>
      ) : null}

      {filters.map((f) => (
        <select
          key={f.key}
          className="form-select"
          style={{ width: "auto" }}
          value={f.value}
          aria-label={f.label}
          onChange={(e) => f.onChange(e.target.value)}
        >
          {f.options.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
      ))}

      {children}

      {onReset && hasFilter ? (
        <button className="btn btn-soft btn-sm" type="button" onClick={onReset}>
          <i className="bi bi-x-circle" aria-hidden />
          Bersihkan filter
        </button>
      ) : null}
    </div>
  );
}

export function DateRange({
  from,
  to,
  onFrom,
  onTo,
}: {
  from: string | null;
  to: string | null;
  onFrom: (value: string | null) => void;
  onTo: (value: string | null) => void;
}) {
  return (
    <>
      <input
        className="form-control"
        type="date"
        style={{ width: "auto" }}
        value={from ?? ""}
        aria-label="Tanggal mulai"
        onChange={(e) => onFrom(e.target.value || null)}
      />
      <span className="muted small">s/d</span>
      <input
        className="form-control"
        type="date"
        style={{ width: "auto" }}
        value={to ?? ""}
        aria-label="Tanggal akhir"
        onChange={(e) => onTo(e.target.value || null)}
      />
    </>
  );
}

export function PrintHead({
  title,
  storeLabel,
  subtitle,
}: {
  title: string;
  storeLabel: string;
  subtitle: string;
}) {
  return (
    <div className="print-head">
      <div className="print-head-title">{storeLabel} - {title}</div>
      <div className="print-head-sub" data-print-subtitle>
        {subtitle}
      </div>
      <div className="print-head-meta">
        Dicetak {new Date().toLocaleString("id-ID")} dari ZoBuah Owner Console
      </div>
    </div>
  );
}

export function DataTable<T>({
  columns,
  rows,
  rowKey,
  loading,
  error,
  onRetry,
  empty = "Belum ada data.",
  sort,
  onSortChange,
  onRowClick,
}: {
  columns: Column<T>[];
  rows: T[];
  rowKey: (row: T) => string;
  loading: boolean;
  error: string | null;
  onRetry?: () => void;
  empty?: string;
  sort?: SortState | null;
  onSortChange?: (next: SortState) => void;
  onRowClick?: (row: T) => void;
}) {
  /* Pengurutan dilakukan di sisi peramban untuk halaman yang sedang
   * tampil. Endpoint ini belum menerima parameter sort, jadi urutan
   * pada tabel hanya berlaku untuk baris di halaman ini, bukan seluruh data.
   * Catatan ini ikut dicetak supaya pembaca laporan tidak salah paham. */
  const sorted = useMemo(() => {
    if (!sort) return rows;
    const col = columns.find((c) => c.key === sort.key);
    if (!col) return rows;
    const read = col.sortValue ?? ((row: T) => String(col.render(row) ?? ""));
    const dir = sort.dir === "asc" ? 1 : -1;
    return [...rows].sort((a, b) => {
      const av = read(a);
      const bv = read(b);
      if (typeof av === "number" && typeof bv === "number") return (av - bv) * dir;
      return String(av).localeCompare(String(bv), "id-ID", { numeric: true }) * dir;
    });
  }, [rows, sort, columns]);

  if (loading) return <Loading label="Memuat data" pattern="lines" />;
  if (error) return <ErrorBox message={error} onRetry={onRetry} />;
  if (sorted.length === 0) return <Empty>{empty}</Empty>;

  return (
    <div className="table-responsive">
      <table className="table">
        <thead>
          <tr>
            {columns.map((col) => {
              const isSorted = sort?.key === col.key;
              const ariaSort = isSorted ? (sort!.dir === "asc" ? "ascending" : "descending") : "none";
              const cell = (
                <>
                  {col.header}
                  {col.sortable ? (
                    <i
                      className={`bi ms-1 ${isSorted ? (sort!.dir === "asc" ? "bi-caret-up-fill" : "bi-caret-down-fill") : "bi-arrow-down-up"}`}
                      aria-hidden
                    />
                  ) : null}
                </>
              );
              return (
                <th
                  key={col.key}
                  className={col.align === "end" ? "text-end" : undefined}
                  aria-sort={col.sortable ? ariaSort : undefined}
                >
                  {col.sortable && onSortChange ? (
                    <button
                      type="button"
                      className="th-sort"
                      onClick={() =>
                        onSortChange({
                          key: col.key,
                          dir: isSorted && sort!.dir === "asc" ? "desc" : "asc",
                        })
                      }
                    >
                      {cell}
                    </button>
                  ) : (
                    cell
                  )}
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody>
          {sorted.map((row) => (
            <tr
              key={rowKey(row)}
              className={onRowClick ? "row-clickable" : undefined}
              onClick={onRowClick ? () => onRowClick(row) : undefined}
            >
              {columns.map((col) => (
                <td key={col.key} className={col.align === "end" ? "text-end" : undefined}>
                  {col.render(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function Pagination({
  meta,
  page,
  onPage,
  pageSize,
  onPageSize,
  unit = "baris",
}: {
  meta: { total: number; total_pages: number; page: number } | null;
  page: number;
  onPage: (page: number) => void;
  pageSize: number;
  onPageSize: (size: number) => void;
  unit?: string;
}) {
  const totalPages = meta?.total_pages ?? 1;
  const total = meta?.total ?? 0;
  const first = total === 0 ? 0 : (page - 1) * pageSize + 1;
  const last = Math.min(page * pageSize, total);

  return (
    <div className="pager no-print">
      <span className="small muted">
        Menampilkan {first}-{last} dari {total} {unit}
      </span>

      <div className="d-flex align-items-center gap-2">
        <select
          className="form-select form-select-sm"
          style={{ width: "auto" }}
          value={pageSize}
          aria-label="Jumlah baris per halaman"
          onChange={(e) => onPageSize(Number(e.target.value))}
        >
          {[20, 50, 100, 200].map((n) => (
            <option key={n} value={n}>
              {n} / halaman
            </option>
          ))}
        </select>

        <button
          className="btn btn-soft btn-sm"
          type="button"
          disabled={page <= 1}
          onClick={() => onPage(page - 1)}
        >
          <i className="bi bi-chevron-left" aria-hidden />
          <span className="visually-hidden">Halaman sebelumnya</span>
        </button>

        <span className="small">
          Halaman {page} / {Math.max(1, totalPages)}
        </span>

        <button
          className="btn btn-soft btn-sm"
          type="button"
          disabled={page >= totalPages}
          onClick={() => onPage(page + 1)}
        >
          <i className="bi bi-chevron-right" aria-hidden />
          <span className="visually-hidden">Halaman berikutnya</span>
        </button>
      </div>
    </div>
  );
}

/** Sortir state yang dipakai bersama beberapa tab. */
export function useSort(initial: SortState | null = null) {
  const [sort, setSort] = useState<SortState | null>(initial);
  const toggle = (next: SortState) =>
    setSort((prev) => (prev?.key === next.key && prev.dir === next.dir ? null : next));
  return { sort, setSort: toggle };
}
