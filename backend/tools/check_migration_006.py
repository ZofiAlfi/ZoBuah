"""Verifikasi idempotensi migrasi 006 terhadap DB UAT lokal.

Migrasi 006 dijalankan secara bersyarat: dilewati kalau prasyarat sudah
terpenuhi. Fungsi ini memanggil ulang SQL-nya di database yang sudah
termigrasi dan memastikan tidak ada efek samping, terutama

    UPDATE products SET is_active = FALSE WHERE ...

yang masih bisa mengubah baris kalau dijalankan dua kali.

Jalankan dari folder backend:
    venv/Scripts/python.exe tools/check_migration_006.py
"""
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+psycopg2://tester:tester@127.0.0.1:5432/zbtest",
)

from sqlalchemy import text  # noqa: E402

from app.database import engine  # noqa: E402
from app.main import _soft_delete_propagation  # noqa: E402

MIGRATION = pathlib.Path(__file__).resolve().parent.parent / "migrations" / "006_soft_delete_propagation.sql"


def check_migration_006() -> list:
    fails = []

    sql = MIGRATION.read_text(encoding="utf-8")

    # Prasyarat yang belum terpenuhi BUKAN kegagalan di sini: itu justru
    # kondisi yang diharapkan saat migrasi memang tertunda. Yang diverifikasi
    # adalah bahwa setelah migrasi dijalankan, prasyaratnya jadi terpenuhi.
    sudah_terpasang = _soft_delete_propagation()
    print("prasyarat sebelum dijalankan :", sudah_terpasang)
    if not sudah_terpasang:
        print("  -> migrasi tertunda, akan diterapkan sekarang")

    with engine.begin() as c:
        before = c.execute(text("select count(*) from products")).scalar()
        active_before = c.execute(text("select count(*) from products where is_active")).scalar()
        c.exec_driver_sql(sql)  # SQL mentah multi-pernyataan, bukan text()
        after = c.execute(text("select count(*) from products")).scalar()
        active_after = c.execute(text("select count(*) from products where is_active")).scalar()
        idx = c.execute(
            text("select count(*) from pg_indexes where indexname = 'ux_products_store_name_active'")
        ).scalar()
        nulls = c.execute(text("select count(*) from products where is_active is null")).scalar()
        cat_nulls = c.execute(text("select count(*) from categories where is_active is null")).scalar()

    if not _soft_delete_propagation():
        fails.append("prasyarat 006 masih belum terpenuhi sesudah migrasi dijalankan")
    if before != after:
        fails.append("jumlah produk berubah %s -> %s, migrasi tidak idempoten" % (before, after))
    if active_before != active_after:
        fails.append("produk aktif berubah %s -> %s, dedupe tidak idempoten" % (active_before, active_after))
    if idx != 1:
        fails.append("index parsial ux_products_store_name_active hilang")
    if nulls:
        fails.append("products.is_active NULL tersisa: %s baris" % nulls)
    if cat_nulls:
        fails.append("categories.is_active NULL tersisa: %s baris" % cat_nulls)

    return fails


def main() -> int:
    fails = check_migration_006()
    if fails:
        print("GAGAL:")
        for f in fails:
            print("  " + f)
        return 1
    print("LULUS: migrasi 006 idempoten, index parsial utuh, tidak ada is_active NULL.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
