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
