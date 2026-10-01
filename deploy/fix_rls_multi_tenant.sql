-- ============================================================================
-- fix_rls_multi_tenant.sql
--
-- MASALAH
--   Seluruh tabel produksi memakai RLS dengan policy yang seragam:
--       CREATE POLICY app_all ON <tabel>
--         FOR ALL TO zobuah_app USING (true) WITH CHECK (true)
--
--   Isolasi tenant TIDAK dilakukan oleh policy ini. Policy ini hanya
--   memberi izin lewat untuk role aplikasi; pemisahan data per toko
--   ditegakkan di kode (backend/app/tenancy.py) lewat filter store_id.
--
--   Tabel stores dan broadcasts dibuat oleh 003_multi_tenant.sql yang TIDAK
--   menyertakan policy, padahal RLS sudah menyala di produksi. RLS tanpa
--   policy = default deny, jadi role aplikasi tidak bisa membaca stores
--   maupun menulis broadcasts:
--       new row violates row-level security policy for table "stores"
--   Akibatnya baris LEGACY-01 tidak pernah tercipta dan tabel stores kosong.
--
-- CARA JALANKAN
--   Supabase Dashboard > SQL Editor > New query > tempel > Run (peran postgres).
--   Policy hanya bisa dibuat oleh pemilik tabel; di produksi pemiliknya
--   adalah postgres, bukan role aplikasi.
--
-- KEAMANAN
--   Tidak menyentuh data. Hanya menyamakan hak akses stores dan broadcasts
--   dengan 13 tabel lainnya, jadi tidak ada celah baru.
--   Idempotent: aman dijalankan berulang.
-- ============================================================================

ALTER TABLE stores     ENABLE ROW LEVEL SECURITY;
ALTER TABLE broadcasts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_all ON stores;
CREATE POLICY app_all ON stores
    FOR ALL TO zobuah_app
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS app_all ON broadcasts;
CREATE POLICY app_all ON broadcasts
    FOR ALL TO zobuah_app
    USING (true)
    WITH CHECK (true);

-- Policy harus dibuat oleh pemilik tabel. Kalau RLS sudah menyala tapi
-- policy-nya hilang, kedua tabel di atas akan terlihat kosong bagi role
-- aplikasi meski tabelnya ada. Untuk memastikan, jalankan:
--     SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public';
-- yang harus memuat 15 baris: satu app_all per tabel.