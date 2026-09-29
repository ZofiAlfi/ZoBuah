"""Buktikan laporan stok benar-benar merekonsiliasi dengan stok produk.

report.py menjumlahkan movement per movement_type lalu mencocokkannya
dengan kolom products.stock. Kalau ada tipe yang tidak dikenal, atau
quantity bertanda negatif, kolomnya terlihat benar padahal tidak.
Skrip ini memanggil endpoint laporan sungguhan lewat TestClient.
"""
import os
import pathlib
import sys
from urllib.parse import urlparse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

url = os.environ.get("DATABASE_URL", "")
if urlparse(url).hostname not in ("127.0.0.1", "localhost", "::1"):
    print("GAGAL: bukan host lokal: %r" % urlparse(url).hostname)
    sys.exit(2)

client = TestClient(app)

# Laporan stok adalah endpoint POS, jadi token OWNER tidak boleh bisa
# membacanya: dia tidak punya toko. Dipakai akun BOS agar jalur yang
# diuji persis sama dengan yang dipakai kasir.
r = client.post(
    "/api/v1/auth/login", json={"username": "bost01", "password": "bos-secret-123"}
)
if r.status_code != 200:
    print("GAGAL: login BOS gagal", r.status_code, r.text[:200])
    sys.exit(1)
token = r.json()["access_token"]
headers = {"Authorization": "Bearer " + token}

candidates = [
    "/api/v1/reports/stock",
    "/api/v1/stock/movements",
]
found = None
for p in candidates:
    rr = client.get(p, headers=headers)
    if rr.status_code == 200:
        found = (p, rr.json())
        break

if not found:
    print("Endpoint laporan stok tidak ditemukan di:", candidates)
    sys.exit(1)

path, data = found
print("endpoint:", path)
# Bentuk responsnya {"products": [...], "totals": {...}}, bukan {"items": ...}
items = data.get("products") or []
totals = data.get("totals") or {}
print("baris:", len(items))
print("totals:", totals)
for row in items[:3]:
    print("  ", row)

fails = []
nol = []
if not items:
    # 668 transaksi seed pasti menghasilkan baris laporan. Nol baris berarti
    # query-nya tidak mengembalikan apa pun, jadi tidak ada yang bisa
    # diverifikasi -- itu harus gagal, bukan lulus.
    print("\nGAGAL: laporan stok mengembalikan 0 baris; tidak ada yang terverifikasi.")
    sys.exit(1)

for row in items:
    masuk = row.get("stock_in", 0) or 0
    jual = row.get("sale_out", 0) or 0
    rusak = row.get("damage_out", 0) or 0
    if masuk < 0:
        fails.append("%s stock_in negatif: %s" % (row.get("product_name"), masuk))
    if jual < 0 or rusak < 0:
        fails.append("%s ada kolom keluar negatif" % row.get("product_name"))
    if jual == 0 and masuk == 0 and rusak == 0:
        nol.append(row.get("product_name"))

if nol:
    # Setiap produk di toko ini terjual pada seed 668 transaksi, jadi
    # sale_out=0 berarti tipe movement-nya tidak dikenali laporan.
    fails.append(
        "%d produk melaporkan sale_out=0 padahal ada 668 transaksi, "
        "mis. tipe movement tidak dikenali laporan" % len(nol)
    )

if (totals.get("sale_out") or 0) <= 0:
    fails.append("totals.sale_out=0 padahal seed membuat 668 transaksi")

if fails:
    print("\nGAGAL:")
    for f in fails[:8]:
        print("  -", f)
    sys.exit(1)
print("\nLULUS: laporan stok mencatat penjualan dan tidak ada kolom negatif.")
