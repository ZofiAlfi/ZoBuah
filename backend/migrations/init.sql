-- =====================================================================
-- Fruit POS - Skema Database PostgreSQL + Data Awal
-- Jalankan:  docker exec -i fruitpos-db psql -U fruitpos -d fruitpos < init.sql
-- Catatan:  Aplikasi (FastAPI + SQLAlchemy) juga membuat tabel secara
--           otomatis saat startup. Skrip ini memberi contoh struktur
--           lengkap serta data awal (kategori & akun Bos).
-- =====================================================================

-- UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------- users ----------
CREATE TABLE IF NOT EXISTS users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username      VARCHAR(50)  NOT NULL UNIQUE,
    full_name     VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(20)  NOT NULL DEFAULT 'KARYAWAN',
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- ---------- categories ----------
CREATE TABLE IF NOT EXISTS categories (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ---------- products ----------
CREATE TABLE IF NOT EXISTS products (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          VARCHAR(200) NOT NULL,
    category_id   UUID REFERENCES categories(id),
    unit          VARCHAR(20)  NOT NULL DEFAULT 'kg',
    modal_price   NUMERIC(12,2) NOT NULL DEFAULT 0,
    selling_price NUMERIC(12,2) NOT NULL DEFAULT 0,
    stock         NUMERIC(12,3) NOT NULL DEFAULT 0,
    min_stock     NUMERIC(12,3) NOT NULL DEFAULT 0,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    description   TEXT,
    created_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ---------- stock_movements ----------
CREATE TABLE IF NOT EXISTS stock_movements (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id     UUID NOT NULL REFERENCES products(id),
    movement_type  VARCHAR(20) NOT NULL,
    quantity       NUMERIC(12,3) NOT NULL,
    stock_before   NUMERIC(12,3) NOT NULL,
    stock_after    NUMERIC(12,3) NOT NULL,
    reference_id   UUID,
    reference_type VARCHAR(50),
    notes          TEXT,
    user_id        UUID NOT NULL REFERENCES users(id),
    created_at     TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_stockm_product ON stock_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_stockm_created ON stock_movements(created_at);

-- ---------- sales ----------
CREATE TABLE IF NOT EXISTS sales (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_number VARCHAR(40) NOT NULL UNIQUE,
    employee_id       UUID NOT NULL REFERENCES users(id),
    total_amount      NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_modal       NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_profit      NUMERIC(12,2) NOT NULL DEFAULT 0,
    discount          NUMERIC(12,2) NOT NULL DEFAULT 0,
    status            VARCHAR(20) NOT NULL DEFAULT 'COMPLETED',
    canceled_at       TIMESTAMP,
    canceled_by       UUID,
    canceled_reason   TEXT,
    created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sales_created ON sales(created_at);
CREATE INDEX IF NOT EXISTS idx_sales_employee ON sales(employee_id);

-- ---------- sale_items ----------
CREATE TABLE IF NOT EXISTS sale_items (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id      UUID NOT NULL REFERENCES sales(id),
    product_id   UUID NOT NULL REFERENCES products(id),
    product_name VARCHAR(200) NOT NULL,
    unit         VARCHAR(20) NOT NULL,
    unit_price   NUMERIC(12,2) NOT NULL,
    modal_price  NUMERIC(12,2) NOT NULL DEFAULT 0,
    quantity     NUMERIC(12,3) NOT NULL,
    subtotal     NUMERIC(12,2) NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_saleitems_sale ON sale_items(sale_id);

-- ---------- payments ----------
CREATE TABLE IF NOT EXISTS payments (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id       UUID NOT NULL REFERENCES sales(id),
    method        VARCHAR(20) NOT NULL,
    amount        NUMERIC(12,2) NOT NULL,
    cash_received NUMERIC(12,2),
    change_amount NUMERIC(12,2),
    reference     VARCHAR(100),
    file_path     VARCHAR(255),
    file_url      VARCHAR(500),
    created_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ---------- damage_reports ----------
CREATE TABLE IF NOT EXISTS damage_reports (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id      UUID NOT NULL REFERENCES products(id),
    quantity        NUMERIC(12,3) NOT NULL,
    unit            VARCHAR(20) NOT NULL,
    reason          VARCHAR(50) NOT NULL,
    description     TEXT,
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    employee_id     UUID NOT NULL REFERENCES users(id),
    approved_by     UUID,
    approved_at     TIMESTAMP,
    rejected_by     UUID,
    rejected_at     TIMESTAMP,
    rejection_reason TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_damage_status ON damage_reports(status);
CREATE INDEX IF NOT EXISTS idx_damage_created ON damage_reports(created_at);

-- ---------- damage_photos ----------
CREATE TABLE IF NOT EXISTS damage_photos (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    damage_report_id  UUID NOT NULL REFERENCES damage_reports(id),
    file_path         VARCHAR(255) NOT NULL,
    file_url          VARCHAR(500),
    created_at        TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ---------- audit_logs ----------
CREATE TABLE IF NOT EXISTS audit_logs (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id),
    action      VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id   VARCHAR(100),
    details     TEXT,
    ip_address  VARCHAR(50),
    created_at  TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(user_id);

-- ---------- devices ----------
CREATE TABLE IF NOT EXISTS devices (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id     VARCHAR(100) NOT NULL UNIQUE,
    device_name   VARCHAR(100),
    platform      VARCHAR(50),
    last_sync_at  TIMESTAMP,
    registered_at TIMESTAMP NOT NULL DEFAULT NOW(),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE
);

-- ---------- sync_events ----------
CREATE TABLE IF NOT EXISTS sync_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type      VARCHAR(50) NOT NULL,
    entity_type     VARCHAR(50) NOT NULL,
    entity_id       VARCHAR(100) NOT NULL,
    device_id       VARCHAR(100),
    server_reference VARCHAR(100),
    payload         TEXT,
    status          VARCHAR(20) NOT NULL DEFAULT 'PROCESSED',
    error_message   TEXT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_syncevent_entity ON sync_events(entity_id);

-- =====================================================================
-- Data Awal: Kategori buah dasar
-- =====================================================================
INSERT INTO categories (name) VALUES
    ('Apel'), ('Jeruk'), ('Mangga'), ('Pisang'), ('Semangka'),
    ('Alpukat'), ('Nanas'), ('Kelapa'), ('Lainnya')
ON CONFLICT (name) DO NOTHING;

-- =====================================================================
-- Akun Bos default (password: bos12345 - GANTI setelah login pertama!)
-- Hash bcrypt di bawah berasal dari 'bos12345'
-- =====================================================================
INSERT INTO users (username, full_name, password_hash, role)
SELECT 'bos', 'Pemilik Toko',
       '$2b$12$hM6pkG1JqVq/q9Q4WWXpVeEvJQlPmKPy1NlBvR6lG0m2yWXyKQYhq',
       'BOS'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE role = 'BOS');
