import { useCallback, useEffect, useState } from "react";

import { ApiError, api } from "./api";

type State<T> = {
  data: T | null;
  loading: boolean;
  error: string | null;
  reload: () => void;
  setData: (updater: T | ((prev: T | null) => T | null)) => void;
};

/**
 * Ambil data dari API dengan auto-cancel saat komponen dilepas.
 *
 * `reload` sengaja dibuat ulang tiap render memakai setTick, bukan
 * useCallback dengan dependensi data, supaya pemanggil bisa memaksa ambil
 * ulang tanpa menyimpan objek response di state pemanggil.
 */
export function useFetch<T>(path: string | null, deps: unknown[] = []): State<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(path !== null);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);

  const reload = useCallback(() => setTick((n) => n + 1), []);

  useEffect(() => {
    if (path === null) {
      setLoading(false);
      return;
    }

    const controller = new AbortController();
    setLoading(true);
    setError(null);

    // Menunda setData sampai response selesai mencegah layar berkedip ke
    // data lama setiap kali filter berubah.
    let active = true;

    api
      .get<T>(path, controller.signal)
      .then((res) => {
        if (active) setData(res);
      })
      .catch((e: unknown) => {
        if (!active || controller.signal.aborted) return;
        setError(e instanceof ApiError ? e.message : "Gagal memuat data.");
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
      controller.abort();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [path, tick, ...deps]);

  const update = useCallback((updater: T | ((prev: T | null) => T | null)) => {
    setData((prev) =>
      typeof updater === "function" ? (updater as (p: T | null) => T | null)(prev) : updater,
    );
  }, []);

  return { data, loading, error, reload, setData: update };
}
