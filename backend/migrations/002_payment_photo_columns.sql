-- Migrasi inkremental: kolom foto bukti pembayaran di tabel payments.
-- Jalankan di Supabase SQL Editor dengan role yang punya hak DDL (admin/postgres),
-- JANGAN lewat role app zobuah_app.* (least-privilege, tanpa hak ALTER).
ALTER TABLE payments ADD COLUMN IF NOT EXISTS file_path VARCHAR(255);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS file_url  VARCHAR(500);