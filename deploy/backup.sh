#!/bin/bash
set -e

# Backup PostgreSQL database ke file terkompresi
# Cara pakai: bash deploy/backup.sh [nama-file]

STAMP=$(date +%Y%m%d_%H%M%S)
OUT="deploy/backup/fruitpos_${STAMP}.sql.gz"

mkdir -p deploy/backup

echo "Membuat backup database ke $OUT ..."

docker exec fruitpos-db pg_dump -U fruitpos -d fruitpos | gzip > "$OUT"

echo "Backup selesai: $OUT"
ls -lh "$OUT"