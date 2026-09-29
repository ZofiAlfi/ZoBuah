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
