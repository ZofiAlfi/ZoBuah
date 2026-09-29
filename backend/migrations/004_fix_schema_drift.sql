-- ============================================================================
-- 004_fix_schema_drift.sql
--
-- Menutup selisih antara model SQLAlchemy dan skema yang benar-benar ada di
-- database. Dua kolom ini sudah dipakai kode tapi tidak pernah ada di
-- migrations/init.sql, jadi fitur terkait rusak di database yang dibuat dari
-- berkas itu:
--
--   products.photo_path        -> upload/hapus foto produk
--   damage_reports.qty_in_base_unit -> persetujuan laporan kerusakan
--
-- Both statements IDEMPOTEN, aman dijalankan berulang maupun di DB kosong.
-- ============================================================================

-- ---------- products.photo_path ----------
ALTER TABLE products ADD COLUMN IF NOT EXISTS photo_path VARCHAR(255);

-- ---------- damage_reports.qty_in_base_unit ----------
ALTER TABLE damage_reports ADD COLUMN IF NOT EXISTS qty_in_base_unit NUMERIC(12,3);

-- Backfill: laporan lama belum punya nilai konversi, isi dengan quantity
-- mentah. Selain menghindari NULL saat reduce, ini juga mencegah None di
-- respons API.
UPDATE damage_reports
   SET qty_in_base_unit = quantity
 WHERE qty_in_base_unit IS NULL;
