import { useCallback, useEffect, useState } from "react";

import { ApiError, api } from "./api";
import type { Paged, PageMeta } from "./types";

/**
 * State dan pemuatan data untuk satu tabel berpaginasi.
 *
 * Tiga hal sengaja dikerjakan di sini, bukan diulang di tiap tab:
 *
 *  - Pembatalan request sebelumnya. Mengetik di kotak pencarian menembak
 *    server beberapa kali dalam hitungan detik. Tanpa pembatalan, respons
 *    yang datang lebih lambat bisa menimpa respons yang lebih baru sehingga
 *    daftar menampilkan hasil untuk ketikan yang sudah dihapus.
 *
 *  - Penundaan pencarian 350 ms. Cukup lama untuk tidak menembak server
 *    tiap huruf, cukup singkat untuk tetap terasa responsif.
 *
 *  - Reset halaman ke 1 saat filter berubah. Tanpa ini, pengguna yang
 *    sedang di halaman 5 lalu menyaring dan mendapat 0 hasil akan mengira
 *    datanya memang kosong.
 */

export type PagedQuery = {
  q?: string;
  page?: number;
  page_size?: number;
  status?: string;
  reason?: string;
  movement_type?: string;
  method?: string;
  action?: string;
  product_id?: string;
  is_active?: boolean;
  trx_status?: string;
  date_from?: string | null;
  date_to?: string | null;
};

export type PagedState<T, S = Record<string, never>> = {
  items: T[];
  meta: PageMeta | null;
  summary: S | null;
  loading: boolean;
  error: string | null;
  page: number;
  pageSize: number;
  search: string;
  dateFrom: string | null;
  dateTo: string | null;
  filters: Record<string, string>;
  setSearch: (value: string) => void;
  setFilter: (key: string, value: string) => void;
  setDateFrom: (value: string | null) => void;
  setDateTo: (value: string | null) => void;
  clearFilters: () => void;
  goToPage: (page: number) => void;
  setPageSize: (size: number) => void;
  reload: () => void;
  /** Dipanggil setelah aksi tulis supaya baris yang diperbarui langsung terlihat. */
  patchItem: (id: string, next: T) => void;
};

export const EMPTY_META: PageMeta = {
  page: 1,
  page_size: 20,
  total: 0,
  total_pages: 1,
};

const DEBOUNCE_MS = 350;

function buildUrl(path: string, query: PagedQuery): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value === undefined || value === null || value === "") continue;
    params.set(key, String(value));
  }
  const qs = params.toString();
  return qs ? `${path}?${qs}` : path;
}

export function usePagedTable<T, S = Record<string, never>>(
  path: string,
  options: {
    pageSize?: number;
    /** Filter tetap milik tab ini, mis. status damage. */
    baseFilters?: PagedQuery;
    searchable?: boolean;
    /** Dinaikkan oleh pemanggil untuk memuat ulang setelah aksi di luar tab. */
    refreshToken?: unknown;
  } = {},
): PagedState<T, S> {
  const {
    pageSize: initialPageSize = 20,
    baseFilters,
    searchable = true,
    refreshToken,
  } = options;

  const [page, setPage] = useState(1);
  const [pageSize, setPageSizeState] = useState(initialPageSize);
  const [search, setSearchState] = useState("");
  const [sentSearch, setSentSearch] = useState("");
  const [filters, setFilters] = useState<Record<string, string>>({});
  const [dateFrom, setDateFromState] = useState<string | null>(null);
  const [dateTo, setDateToState] = useState<string | null>(null);

  const [items, setItems] = useState<T[]>([]);
  const [meta, setMeta] = useState<PageMeta | null>(null);
  const [summary, setSummary] = useState<S | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);

  // Teks yang diketik tampil seketika, teks yang dikirim ke server
  // menunggu jeda supaya tidak ada request per huruf.
  useEffect(() => {
    if (!searchable) return;
    const timer = setTimeout(() => setSentSearch(search.trim()), DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [search, searchable]);

  // URL dibangun sebagai nilai, bukan objek query, sehingga dependensi
  // effect cukup berupa teksnya. Objek filter yang dibuat ulang tiap
  // render tidak akan memicu permintaan berulang.
  const url = buildUrl(path, {
    ...baseFilters,
    ...filters,
    q: sentSearch || undefined,
    page,
    page_size: pageSize,
    date_from: dateFrom,
    date_to: dateTo,
  });

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError(null);

    api
      .get<Paged<T> & { summary?: S }>(url, controller.signal)
      .then((res) => {
        // Pembatalan biasanya menghentikan browser lebih dulu, tapi tidak
        // selalu, jadi respons usang tetap diperiksa lewat sinyal abort.
        if (controller.signal.aborted) return;
        setItems(res.items ?? []);
        setMeta(res.meta ?? null);
        setSummary((res.summary ?? null) as S | null);
      })
      .catch((e: unknown) => {
        if (controller.signal.aborted) return;
        setItems([]);
        setMeta(null);
        setSummary(null);
        setError(e instanceof ApiError ? e.message : "Gagal memuat data.");
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    return () => controller.abort();
  }, [url, tick, refreshToken]);

  const setSearch = useCallback((value: string) => {
    setSearchState(value);
    setPage(1);
  }, []);

  const setFilter = useCallback((key: string, value: string) => {
    setFilters((prev) => {
      const next = { ...prev };
      if (value === "") delete next[key];
      else next[key] = value;
      return next;
    });
    setPage(1);
  }, []);

  const setDateFrom = useCallback((value: string | null) => {
    setDateFromState(value);
    setPage(1);
  }, []);

  const setDateTo = useCallback((value: string | null) => {
    setDateToState(value);
    setPage(1);
  }, []);

  const clearFilters = useCallback(() => {
    setFilters({});
    setSearchState("");
    setSentSearch("");
    setDateFromState(null);
    setDateToState(null);
    setPage(1);
  }, []);

  const goToPage = useCallback((next: number) => setPage(Math.max(1, next)), []);

  const setPageSize = useCallback((size: number) => {
    setPageSizeState(size);
    setPage(1);
  }, []);

  const reload = useCallback(() => setTick((n) => n + 1), []);

  const patchItem = useCallback((id: string, next: T) => {
    setItems((prev) => prev.map((it) => (String((it as { id?: unknown }).id) === id ? next : it)));
  }, []);

  return {
    items,
    meta,
    summary,
    loading,
    error,
    page,
    pageSize,
    search,
    dateFrom,
    dateTo,
    filters,
    setSearch,
    setFilter,
    setDateFrom,
    setDateTo,
    clearFilters,
    goToPage,
    setPageSize,
    reload,
    patchItem,
  };
}
