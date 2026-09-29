import { useEffect, useState } from "react";

export function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia?.("(prefers-reduced-motion: reduce)");
    setReduced(mq?.matches ?? false);
    const onChange = () => setReduced(mq?.matches ?? false);
    mq?.addEventListener?.("change", onChange);
    return () => mq?.removeEventListener?.("change", onChange);
  }, []);

  return reduced;
}

/**
 * Angka KPI yang "menghitung naik" ke nilai akhir (ala CodePen).
 * Berlaku hanya ke angka baru saat data pertama muncul, hormati
 * prefers-reduced-motion: kalau pengguna meminta gerak minimal,
 * angka langsung tampil penuh.
 */
export function CountUp({
  value,
  format = (n: number) => Math.round(n).toLocaleString("id-ID"),
  duration = 900,
}: {
  value: number;
  format?: (n: number) => string;
  duration?: number;
}) {
  const [display, setDisplay] = useState(value);
  const reduced = usePrefersReducedMotion();

  useEffect(() => {
    if (reduced) {
      setDisplay(value);
      return;
    }

    let raf = 0;
    const start = performance.now();
    const from = 0;

    const tick = (now: number) => {
      const p = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - p, 3);
      setDisplay(from + (value - from) * eased);
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);

    return () => cancelAnimationFrame(raf);
  }, [value, duration, reduced]);

  return <span className="num">{format(display)}</span>;
}