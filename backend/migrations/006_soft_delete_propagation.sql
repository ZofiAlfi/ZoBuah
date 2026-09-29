-- Penghapusan produk dan kategori harus sampai ke perangkat kasir.
--
-- Sebelumnya DELETE /products/{id} memakai db.delete() kalau produk belum
-- pernah punya histori. Baris itu hilang dari server, tapi tidak ada sinyal
-- apa pun yang dikirim ke sync/pull, jadi produknya tetap nempel di HP
-- karyawan: masih tampil di grid, masih bisa dicari, masih bisa dijual.
-- Kalau BOS lalu membuat produk dengan nama sama, id baru ikut ter-pull
-- dan di HP muncul dua produk dengan nama yang sama.
--
-- Solusinya tidak perlu tabel tombstone: products dan categories di-pull
-- sebagai full dump setiap sync tanpa filter last_sync, jadi cukup membuat
-- penghapusan selalu berupa soft delete. Baris dengan is_active = false
-- tetap dikirim dan menimpa baris lokal lewat upsert.

-- 1. Kategori belum punya penanda aktif sama sekali, jadi kategori yang
--    dihapus MUSTAHIL dihapus dari perangkat.
ALTER TABLE categories ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

-- 2. products.is_active nullable tanpa default. Nilai NULL di database
--    terbaca sebagai AKTIF di sisi klien (json['is_active'] ?? true), jadi
--    produk yang sebenarnya tidak aktif masih bisa terjual. Backfill dulu
--    baru kunci NOT NULL.
UPDATE products SET is_active = TRUE WHERE is_active IS NULL;
ALTER TABLE products ALTER COLUMN is_active SET DEFAULT TRUE;
ALTER TABLE products ALTER COLUMN is_active SET NOT NULL;

-- 3. products tidak punya unique (store_id, name), jadi nama yang sama
--    bisa hidup berdampingan. Itu sumber duplikasi di perangkat. Unique
--    penuh tidak bisa dipasang karena soft delete tetap menempati nama.
--    Yang bisa dijaga: satu produk AKTIF per nama per toko, lewat index
--    parsial. Baris nonaktif di luar index, jadi produk lama bisa di-revive
--    tanpa bentrok dan produk baru dengan nama sama tidak akan muncul dua
--    kali di grid kasir.
--
--    Duplikat yang sudah terlanjur ada harus dinonaktifkan dulu, kalau tidak
--    CREATE UNIQUE INDEX gagal dan seluruh startup ikut gagal. Yang
--    dipertahankan aktif adalah baris paling lama per nama, supaya produk
--    yang punya histori penjualan tetap yang di-represented.
UPDATE products p
SET is_active = FALSE
WHERE p.is_active = TRUE
  AND EXISTS (
    SELECT 1 FROM products o
    WHERE o.store_id IS NOT DISTINCT FROM p.store_id
      AND o.name = p.name
      AND o.id <> p.id
      AND (
        o.created_at < p.created_at
        OR (o.created_at IS NOT DISTINCT FROM p.created_at AND o.id < p.id)
      )
  );

DROP INDEX IF EXISTS ux_products_store_name_active;
CREATE UNIQUE INDEX IF NOT EXISTS ux_products_store_name_active
    ON products (store_id, name)
    WHERE is_active = TRUE;

-- 4. Category tetap unique penuh karena halamannya hanya source of truth
--    dari server dan tidak pernah dibuat offline di perangkat. Produk yang
--    menunjuk kategori nonaktif tidak di-touch di sini: is_active kategori
--    tidak grieving, dan produknya sendiri bisa diaktifkan ulang.
