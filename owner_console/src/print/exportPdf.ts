/* Ekspor PDF lewat dialog cetak browser, bukan pustaka PDF.
 *
 * Alasannya sederhana: tabel Owner Console sudah berupa tabel HTML dengan
 * kolom yang rata kanan-kiri, dan dialog cetak memberi pengguna kendali
 * penuh atas ukuran kertas dan orientasi. Pustaka PDF akan menambah
 * dependensi, menghasilkan tabel yang terpotong, dan mengubah tampilan
 * yang sudah rapi.
 */

const PRINT_CLASS = "is-printing";

function safeFileName(value: string): string {
  return value
    .replace(/[\\/:*?"<>|]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 80);
}

export type ExportPdfOptions = {
  /** Judul dokumen, dipakai untuk nama berkas hasil "Simpan sebagai PDF". */
  title: string;
  /** Keterangan filter aktif, dicetak di kepala halaman. */
  subtitle?: string;
};

export function exportTablePdf({ title, subtitle }: ExportPdfOptions): void {
  const previousTitle = document.title;
  document.title = safeFileName(title);

  const head = document.querySelector("[data-print-subtitle]");
  if (head && subtitle) head.textContent = subtitle;

  document.body.classList.add(PRINT_CLASS);

  let cleaned = false;
  const cleanup = () => {
    if (cleaned) return;
    cleaned = true;
    document.body.classList.remove(PRINT_CLASS);
    document.title = previousTitle;
    window.removeEventListener("afterprint", cleanup);
  };

  window.addEventListener("afterprint", cleanup);
  window.print();

  /* Beberapa peramban tidak menembak afterprint kalau jendela cetak
   * ditutup dengan cara lain.Timeout ini memastikan kelas cetak tidak
   * tertinggal dan ikut memotong tampilan setelah selesai. */
  window.setTimeout(cleanup, 1500);
}

/** Ringkasan filter aktif untuk dicetak di kepala laporan. */
export function describeFilters(parts: (string | null | undefined)[]): string {
  const kept = parts.filter((p): p is string => !!p && p.length > 0);
  return kept.join(" - ");
}
