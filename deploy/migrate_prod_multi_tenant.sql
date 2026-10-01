-- ============================================================================
-- migrate_prod_multi_tenant.sql
--
-- Menjalankan migrasi 003 + 005 + 006 pada database yang SUDAH berisi data
-- (produksi), dalam satu kali tempel.
--
-- CARA JALANKAN
--   Supabase Dashboard > SQL Editor > New query > tempel seluruh isi berkas ini
--   > Run. Peran harus postgres (atau pemilik tabel), bukan role aplikasi.
--
-- KENAPA DIJALANKAN MANUAL
--   Role aplikasi produksi (zobuah_app) dibuat least-privilege: boleh INSERT /
--   UPDATE / DELETE, tapi bukan owner tabel, jadi ALTER TABLE ADD COLUMN,
--   CREATE INDEX, dan DROP CONSTRAINT ditolak dengan InsufficientPrivilege.
--   Menambah hak ALTER ke role aplikasi justru membuka celah baru dan tidak
--   perlu: migrasi jarang, jadi cukup satu kali manual.
--
-- KEAMANAN
--   Semua kolom baru NULLABLE / punya DEFAULT, jadi migrasi ini tidak memutus
--   kode lama yang masih berjalan selama jendela transisi.
--   Tidak ada DROP TABLE, tidak ada DELETE, tidak ada truncation.
--   Semua pernyataan IDEMPOTEN: aman dijalankan berulang.
--
-- URUTAN WAJIB
--   005 dan 006 bergantung pada kolom yang dibuat 003, jadi 003 harus lebih dulu.
--
-- SETELAH DIJALANKAN
--   Verifikasi dengan: temp\opencode\migrate_prod_mt.py --apply
--   (semua migrasi akan dilaporkan LEWATI / prasyarat sudah terpenuhi).
-- ============================================================================



-- ============================================================================
-- MIGRASI 003 - multi tenant
-- sumber: backend/migrations/003_multi_tenant.sql
-- ============================================================================

-- ============================================================================
-- 003_multi_tenant.sql
--
-- Menambahkan dukungan multi-tenant pada Laporan Buah.
-- App POS tetap berjalan: semua kolom baru NULLABLE, jadi migrasi ini
-- tidak memutus data yang sudah ada.
--
-- Cara menjalankan:
--   (a) Supabase SQL Editor sebagai admin  -> salin & jalankan sekali
--   (b) Otomatis saat startup backend      -> app/main.py::_migrate_multitenant
--       memakai isolation_level="AUTOCOMMIT" karena koneksi Supabase lewat
--       pgbouncer menolak DDL multi-statement dalam satu transaksi.
--
-- Script ini IDEMPOTEN: aman dijalankan berulang.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tabel baru: stores (satu baris per toko)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stores (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code             VARCHAR(20)  NOT NULL UNIQUE,
    name             VARCHAR(100) NOT NULL,
    owner_name       VARCHAR(100) NOT NULL,
    phone            VARCHAR(20),
    address          TEXT,
    plan             VARCHAR(20)  NOT NULL DEFAULT 'TRIAL',
    plan_expires_at  DATE,
    status           VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    is_active        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP    NOT NULL DEFAULT now(),
    updated_at       TIMESTAMP    NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_stores_status      ON stores (status);
CREATE INDEX IF NOT EXISTS ix_stores_plan_expires ON stores (plan_expires_at);

-- ---------------------------------------------------------------------------
-- 2. Tabel baru: broadcasts (pengumuman owner ke client)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS broadcasts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title       VARCHAR(120) NOT NULL,
    body        TEXT         NOT NULL,
    level       VARCHAR(20)  NOT NULL DEFAULT 'INFO',
    target      VARCHAR(20)  NOT NULL DEFAULT 'ALL',
    store_id    UUID         REFERENCES stores(id),
    starts_at   TIMESTAMP    NOT NULL DEFAULT now(),
    expires_at  TIMESTAMP,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by  UUID         REFERENCES users(id),
    created_at  TIMESTAMP    NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_broadcasts_active ON broadcasts (is_active, starts_at DESC);

-- ---------------------------------------------------------------------------
-- 3. Backfill: satu store untuk seluruh data yang sudah ada
--    Dev bersih, tapi script tetap aman kalau dijalankan di DB berisi data.
-- ---------------------------------------------------------------------------
INSERT INTO stores (code, name, owner_name, plan, status)
SELECT 'LEGACY-01', 'Toko Legacy', 'Pemilik Toko', 'LEGACY', 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM stores);

-- ---------------------------------------------------------------------------
-- 4. Tambah store_id ke 9 tabel
--    NULLABLE dengan sengaja:
--      - user OWNER tidak punya toko
--      - migrasi tidak boleh gagal di tengah jalan
--    NOT NULL ditambahkan pada fase 2, setelah backfill stabil.
-- ---------------------------------------------------------------------------
ALTER TABLE users           ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES stores(id);
ALTER TABLE categories      ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES stores(id);
ALTER TABLE products        ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES stores(id);
ALTER TABLE sales           ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES stores(id);
ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES stores(id);
ALTER TABLE damage_reports  ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES stores(id);
ALTER TABLE audit_logs      ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES stores(id);
ALTER TABLE devices         ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES stores(id);
ALTER TABLE sync_events     ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES stores(id);

-- ---------------------------------------------------------------------------
-- 5. Backfill store_id
--    User OWNER sengaja TIDAK diberi store_id (akun global, bukan milik toko).
-- ---------------------------------------------------------------------------
UPDATE users           SET store_id = (SELECT id FROM stores WHERE code = 'LEGACY-01')
WHERE store_id IS NULL AND role <> 'OWNER';

UPDATE categories      SET store_id = (SELECT id FROM stores WHERE code = 'LEGACY-01') WHERE store_id IS NULL;
UPDATE products        SET store_id = (SELECT id FROM stores WHERE code = 'LEGACY-01') WHERE store_id IS NULL;
UPDATE sales           SET store_id = (SELECT id FROM stores WHERE code = 'LEGACY-01') WHERE store_id IS NULL;
UPDATE stock_movements SET store_id = (SELECT id FROM stores WHERE code = 'LEGACY-01') WHERE store_id IS NULL;
UPDATE damage_reports  SET store_id = (SELECT id FROM stores WHERE code = 'LEGACY-01') WHERE store_id IS NULL;
UPDATE audit_logs      SET store_id = (SELECT id FROM stores WHERE code = 'LEGACY-01') WHERE store_id IS NULL;
UPDATE devices         SET store_id = (SELECT id FROM stores WHERE code = 'LEGACY-01') WHERE store_id IS NULL;
UPDATE sync_events     SET store_id = (SELECT id FROM stores WHERE code = 'LEGACY-01') WHERE store_id IS NULL;

-- ---------------------------------------------------------------------------
-- 6. categories: unique GLOBAL -> unique per toko
--    Wajib. Tanpa ini toko kedua tidak bisa punya kategori "Apel" karena
--    kategori itu sudah dipakai toko pertama.
-- ---------------------------------------------------------------------------
ALTER TABLE categories DROP CONSTRAINT IF EXISTS categories_name_key;
CREATE UNIQUE INDEX IF NOT EXISTS ux_categories_store_name ON categories (store_id, name);

-- ---------------------------------------------------------------------------
-- 7. Force logout: token_version
--    TOKEN_BLACKLIST di security.py hanya in-memory, hilang saat restart dan
--    tidak dibagi antar worker. Naikkan token_version = seluruh refresh token
--    lama mati, dan itu bertahan setelah restart.
-- ---------------------------------------------------------------------------
ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 8. Index untuk query monitoring di owner console
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_sales_store_created    ON sales (store_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_sales_store_status     ON sales (store_id, status);
CREATE INDEX IF NOT EXISTS ix_products_store_active  ON products (store_id, is_active);
CREATE INDEX IF NOT EXISTS ix_damage_store_status    ON damage_reports (store_id, status);
CREATE INDEX IF NOT EXISTS ix_audit_store_created    ON audit_logs (store_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_devices_store          ON devices (store_id);
CREATE INDEX IF NOT EXISTS ix_sync_store_created     ON sync_events (store_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_users_store            ON users (store_id);

-- ============================================================================
-- MIGRASI 005 - nomor transaksi unik per toko
-- sumber: backend/migrations/005_sales_transaction_number_per_store.sql
-- ============================================================================

-- 005_sales_transaction_number_per_store.sql
--
-- MASALAH:
--   sales.transaction_number punya UNIQUE global. 003_multi_tenant.sql sudah
--   menghitung nomor PER TOKO (TRX-YYYYMMDD-001 diulang di setiap toko), tapi
--   constraint global masih ada. Akibatnya transaksi kedua toko pada hari
--   yang sama langsung kena UniqueViolation.
--
-- SOLUSI:
--   Lepas unique global, pasang unique komposit (store_id, transaction_number).
--
-- URUTAN:
--   WAJIB dijalankan SETELAH 003_multi_tenant.sql karena kolom store_id harus
--   sudah ada.
--
-- CATATAN store_id NULL:
--   Di SQL, NULL <> NULL, jadi baris dengan store_id NULL lolos unique
--   komposit. Semua baris sales produksi selalu punya store_id (dijamin app
--   lewat require_store_id), jadi ini cuma menyisakan data lama yang belum
--   ter-backfill -- tetap jauh lebih baik daripada menabrak constraint global.
--
-- IDEMPOTEN: aman dijalankan berkali-kali.

-- 1) Unique global yang berupa CONSTRAINT. Men-drop constraint ikut
--    membawa index-nya, jadi harus lewat ALTER TABLE. Men-drop index-nya
--    langsung akan gagal dengan "cannot drop index ... because constraint
--    ... requires it".
ALTER TABLE sales DROP CONSTRAINT IF EXISTS sales_transaction_number_key;
ALTER TABLE sales DROP CONSTRAINT IF EXISTS ix_sales_transaction_number;
ALTER TABLE sales DROP CONSTRAINT IF EXISTS ux_sales_transaction_number;
ALTER TABLE sales DROP CONSTRAINT IF EXISTS uq_sales_transaction_number;

-- 2) Unique global yang berupa index longgar (SQLAlchemy membuat
--    index=True + unique=True sebagai index, bukan constraint).
--
--    Predicate-nya HARUS menyebut transaction_number. Dulu hanya
--    "UNIQUE dan tidak mengandung store_id", dan itu ikut menyasar
--    sales_pkey (UNIQUE di kolom id) sehingga migrasi gagal dengan
--    "cannot drop index sales_pkey because constraint sales_pkey on table
--    sales requires it".
DO $$
DECLARE
    idx RECORD;
BEGIN
    FOR idx IN
        SELECT i.indexname
        FROM pg_indexes i
        WHERE i.tablename = 'sales'
          AND i.schemaname = current_schema()
          AND i.indexdef ILIKE '%UNIQUE%'
          AND i.indexdef ILIKE '%transaction_number%'
          AND i.indexdef NOT ILIKE '%store_id%'
          -- Jangan sentuh index yang menopang sebuah constraint.
          AND NOT EXISTS (
              SELECT 1 FROM pg_constraint c
              WHERE c.conindid = (quote_ident(i.indexname))::regclass
          )
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS %I', idx.indexname);
        RAISE NOTICE '005: unique global salesLepas dari index %', idx.indexname;
    END LOOP;
END $$;

-- 3) Unique komposit per toko. Dijaga DO block karena ADD CONSTRAINT tidak
--    punya varian IF NOT EXISTS di PostgreSQL.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE c.conname = 'ux_sales_store_transaction_number'
          AND t.relname = 'sales'
          AND n.nspname = current_schema()
    ) THEN
        ALTER TABLE sales
            ADD CONSTRAINT ux_sales_store_transaction_number
            UNIQUE (store_id, transaction_number);
    END IF;
END $$;

-- 4) Index non-unique untuk pencarian nomor transaksi.
CREATE INDEX IF NOT EXISTS idx_sales_transaction_number
    ON sales (transaction_number);

-- ============================================================================
-- MIGRASI 006 - penghapusan produk/kategori sampai ke perangkat
-- sumber: backend/migrations/006_soft_delete_propagation.sql
-- ============================================================================

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


-- ============================================================================
-- AKHIR
--
-- Yang DIHARAPKAN setelah berkas ini selesai:
--   - tabel stores berisi 1 baris (LEGACY-01), tabel broadcasts ada
--   - 9 tabel punya kolom store_id, semua baris ter-backfill ke LEGACY-01
--   - users.token_version ada, default 0
--   - categories: UNIQUE(name)(global) hilang, jadi UNIQUE(store_id, name)
--   - sales: UNIQUE global transaction_number hilang,
--     jadi UNIQUE (store_id, transaction_number)
--   - categories.is_active ada, products.is_active NOT NULL DEFAULT TRUE
--
-- Langkah berikutnya: ganti kode/name store LEGACY-01 menjadi FRUIT-01 -
-- "Toko Buah" dan buat akun OWNER. Itu dilakukan lewat skrip aplikasi
-- (butuh hash bcrypt), BUKAN lewat SQL Editor.
-- ============================================================================
