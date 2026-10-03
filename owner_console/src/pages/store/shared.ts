/* Label dan pilihan filter untuk Data Browser.
 *
 * Nilai di backend disimpan sebagai kode bahasa Inggris supaya konsisten
 * dengan isi kolom di database. Yang ditampilkan ke owner adalah bahasa
 * Indonesia supaya tabel tidak perlu dibaca dua kali.
 */

export const DAMAGE_STATUS: Record<string, { label: string; tone: string }> = {
  PENDING: { label: "Menunggu", tone: "warn" },
  APPROVED: { label: "Disetujui", tone: "ok" },
  REJECTED: { label: "Ditolak", tone: "bad" },
};

export const DAMAGE_REASONS: { value: string; label: string }[] = [
  { value: "", label: "Semua alasan" },
  { value: "BUSUK", label: "Busuk" },
  { value: "RUSAK_FISIK", label: "Rusak fisik" },
  { value: "JATUH", label: "Jatuh" },
  { value: "KADALUARSA", label: "Kedaluwarsa" },
  { value: "SUSUT", label: "Susut" },
  { value: "LAINNYA", label: "Lainnya" },
];

export function reasonLabel(value: string): string {
  return DAMAGE_REASONS.find((r) => r.value === value)?.label ?? value.replaceAll("_", " ");
}

export const MOVEMENT_TYPES: { value: string; label: string }[] = [
  { value: "", label: "Semua jenis" },
  { value: "OPENING", label: "Stok awal" },
  { value: "IN", label: "Barang masuk" },
  { value: "OUT", label: "Barang keluar" },
  { value: "SALE", label: "Penjualan" },
  { value: "RETURN", label: "Retur masuk" },
  { value: "RETURN_OUT", label: "Retur keluar" },
  { value: "DAMAGE", label: "Barang rusak" },
  { value: "ADJUSTMENT", label: "Penyesuaian (+)" },
  { value: "ADJUSTMENT_NEGATIVE", label: "Penyesuaian (-)" },
];

export function movementLabel(value: string): { label: string; tone: string } {
  const found = MOVEMENT_TYPES.find((m) => m.value === value);
  const label = found?.label ?? value.replaceAll("_", " ");
  if (["SALE", "IN", "RETURN"].includes(value)) return { label, tone: "ok" };
  if (["OUT", "DAMAGE", "RETURN_OUT", "ADJUSTMENT_NEGATIVE"].includes(value)) {
    return { label, tone: "bad" };
  }
  return { label, tone: "info" };
}

export const PAYMENT_METHODS: { value: string; label: string }[] = [
  { value: "", label: "Semua metode" },
  { value: "CASH", label: "Tunai" },
  { value: "TRANSFER", label: "Transfer" },
  { value: "QRIS", label: "QRIS" },
];

export function methodLabel(value: string): string {
  return PAYMENT_METHODS.find((m) => m.value === value)?.label ?? value;
}

export const PRODUCT_ACTIONS: { value: string; label: string; tone: string }[] = [
  { value: "", label: "Semua aktivitas", tone: "info" },
  { value: "PRODUCT_CREATE", label: "Produk ditambah", tone: "ok" },
  { value: "PRODUCT_UPDATE", label: "Produk diubah", tone: "warn" },
  { value: "PRODUCT_DEACTIVATE", label: "Produk dinonaktifkan", tone: "muted" },
  { value: "PRODUCT_REACTIVATE", label: "Produk diaktifkan lagi", tone: "ok" },
  { value: "PRODUCT_PHOTO_UPLOAD", label: "Foto produk ditambahkan", tone: "info" },
  { value: "PRODUCT_PHOTO_DELETE", label: "Foto produk dihapus", tone: "muted" },
];

export function actionLabel(value: string): { label: string; tone: string } {
  const found = PRODUCT_ACTIONS.find((a) => a.value === value);
  return {
    label: found?.label ?? value.replaceAll("_", " ").toLowerCase(),
    tone: found?.tone ?? "info",
  };
}
