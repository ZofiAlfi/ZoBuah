#!/bin/bash
set -e

# Jalankan terhadap container database PostgreSQL Fruit POS.
# Pastikan docker compose sudah up (container fruitpos-db berjalan).

DB_CONTAINER="${DB_CONTAINER:-fruitpos-db}"
DB_USER="${DB_USER:-fruitpos}"
DB_NAME="${DB_NAME:-fruitpos}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Menerapkan skema + data awal ke database ${DB_NAME} ==="
echo "Container : ${DB_CONTAINER}"

# Salin skrip ke dalam container lalu eksekusi
docker cp "$SCRIPT_DIR/init.sql" "${DB_CONTAINER}:/tmp/init.sql"
docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -f /tmp/init.sql

echo ""
echo "Selesai. Akun Bos default: username=bos password=bos12345 (SEGERA diganti!)"
