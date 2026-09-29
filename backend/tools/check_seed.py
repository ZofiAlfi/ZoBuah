"""Verifikasi data seed UAT: stok akhir, low-stock, dan tidak ada stok negatif.

Seed membuat 668 transaksi historis. Kalau stok produk tidak disetel ulang
SETELAH riwayat itu, produkambaik dan tidak ada satu pun yang low-stock --
persis kondisi yang membuat UAT transaksi pertama gagal dengan
insufficient_stock.
"""
import os
import pathlib
import sys
from urllib.parse import urlparse

import sqlalchemy as sa

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "backend"))

url = os.environ.get("DATABASE_URL", "")
host = urlparse(url).hostname
if host not in ("127.0.0.1", "localhost", "::1"):
    print("GAGAL: DATABASE_URL bukan host lokal: %r" % host)
    sys.exit(2)

engine = sa.create_engine(url)
fails = []

with engine.connect() as c:
    print("=== stok per toko ===")
    rows = c.execute(
        sa.text(
            """
            select s.code,
                   count(*) filter (where p.stock <= p.min_stock) as low,
                   count(*) filter (where p.stock >  p.min_stock) as sehat,
                   min(p.stock) as min_stok,
                   sum(p.stock) as total_stok
              from products p join stores s on s.id = p.store_id
             where p.is_active = true
          group by s.code order by s.code
            """
        )
    ).fetchall()
    for code, low, sehat, min_stok, total in rows:
        print("  %-4s low=%-3d sehat=%-3d min=%-6s total=%s" % (code, low, sehat, min_stok, total))
        if low < 3 or sehat < 11:
            fails.append("%s: low=%s sehat=%s (harapan 3 dan 11)" % (code, low, sehat))
        if total is None or total <= 0:
            fails.append("%s: total stok %r, tidak boleh nol" % (code, total))

    negatif = c.execute(
        sa.text("select count(*) from products where stock < 0")
    ).scalar()
    print("=== produk stok negatif: %s ===" % negatif)
    if negatif:
        fails.append("%d produk punya stok negatif" % negatif)

    nol = c.execute(
        sa.text("select count(*) from products where stock = 0 and is_active = true")
    ).scalar()
    print("=== produk aktif stok 0: %s ===" % nol)
    if nol:
        fails.append("%d produk aktif punya stok 0" % nol)

    movements = c.execute(
        sa.text(
            """
            select m.movement_type, count(*)
              from stock_movements m group by m.movement_type order by 2 desc
            """
        )
    ).fetchall()
    print("=== ledger stock_movements ===")
    for tipe, n in movements:
        print("  %-12s %s" % (tipe, n))

    restock = c.execute(
        sa.text(
            "select count(*) from stock_movements where reference_type = 'seed_restock'"
        )
    ).scalar()
    print("=== seed_restock: %s ===" % restock)
    if restock == 0:
        fails.append("tidak ada movement seed_restock; stok tidak disetel ulang")

    # Konvensi app: arah dari movement_type, quantity selalu positif.
    # Tanda negatif membuat kolom stock_in di laporan bernilai minus.
    negatif = c.execute(
        sa.text("select count(*) from stock_movements where quantity < 0")
    ).scalar()
    print("=== movement quantity negatif: %s ===" % negatif)
    if negatif:
        fails.append("%d movement punya quantity negatif" % negatif)

    # Tipe yang tidak dikenali laporan stok akan hilang diam-diam dari
    # ringkasan: sale_out selalu 0 padahal ada ribuan penjualan.
    tipe_asing = c.execute(
        sa.text(
            """
            select movement_type, count(*) from stock_movements
             where movement_type not in
               ('SALE','DAMAGE','RETURN','STOCK_IN','ADJUSTMENT','ADJUSTMENT_NEGATIVE')
             group by 1
            """
        )
    ).fetchall()
    print("=== movement_type di luar daftar laporan: %s ===" % tipe_asing)
    if tipe_asing:
        fails.append("movement_type tak dikenal laporan: %s" % tipe_asing)

    sales_leader = c.execute(
        sa.text("select count(*) from stock_movements where movement_type = 'SALE'")
    ).scalar()
    print("=== movement SALE: %s ===" % sales_leader)
    if sales_leader == 0:
        fails.append("tidak ada movement SALE; laporan stok akan melaporkan sale_out=0")

    sales = c.execute(sa.text("select count(*) from sales")).scalar()
    print("=== transaksi: %s ===" % sales)

    nonaktif = c.execute(
        sa.text("select count(*) from products where is_active = false")
    ).scalar()
    print("=== produk nonaktif: %s ===" % nonaktif)

    tidak_ada_store = c.execute(
        sa.text("select count(*) from products where store_id is null")
    ).scalar()
    print("=== produk tanpa store_id: %s ===" % tidak_ada_store)
    if tidak_ada_store:
        fails.append("%d produk tanpa store_id" % tidak_ada_store)

    # Syarat skema hasil migrasi 006. Seed --reset membangun skema lewat
    # create_all, yang tidak menjalankan migrasi, jadi tanpa cek ini seed
    # bisa melaporkan sukses padahal index anti-duplikasi belum ada.
    idx = c.execute(
        sa.text(
            "select count(*) from pg_indexes where tablename = 'products' "
            "and schemaname = current_schema() "
            "and indexname = 'ux_products_store_name_active'"
        )
    ).scalar()
    print("=== index parsial produk: %s ===" % idx)
    if idx != 1:
        fails.append(
            "index ux_products_store_name_active belum ada; nama produk ganda "
            "bisa masuk ke grid kasir (jalankan server sekilas atau "
            "backend/tools/check_migration_006.py)"
        )

    cat_col = c.execute(
        sa.text(
            "select count(*) from information_schema.columns "
            "where table_schema = current_schema() "
            "and table_name = 'categories' and column_name = 'is_active'"
        )
    ).scalar()
    print("=== categories.is_active: %s ===" % cat_col)
    if cat_col != 1:
        fails.append("categories.is_active belum ada; kategori tidak bisa dihapus di perangkat")

    prod_nullable = c.execute(
        sa.text(
            "select is_nullable from information_schema.columns "
            "where table_schema = current_schema() "
            "and table_name = 'products' and column_name = 'is_active'"
        )
    ).scalar()
    print("=== products.is_active nullable: %s ===" % prod_nullable)
    if prod_nullable != "NO":
        fails.append("products.is_active masih nullable; NULL dibaca aktif oleh klien")

if fails:
    print("\nGAGAL:")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("\nLULUS: stok akhir benar, low-stock ada, tidak ada stok negatif, skema 006 terpasang.")
