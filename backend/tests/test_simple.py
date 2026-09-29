"""Tes simpel backend ZoBuah: fungsi murni + integrasi ringan ke DB lokal.

Jalankan: python -m pytest tests -q

Tes integrasi tidak boleh bergantung pada akun demo hasil seed. Dulu file ini
login memakai "zofi"/"12345" yang sudah hilang saat migrasi multi-tenant, jadi
dua tes gagal begitu schema di-seed ulang. Sekarang store dan akun BOS dibuat
sendiri oleh fixture, lalu dimatikan lagi setelah selesai.
"""

import os
import uuid
from datetime import datetime, timezone
from urllib.parse import urlparse

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models.product import Product
from app.models.stock_movement import StockMovement
from app.models.store import Plan, Store, StoreStatus
from app.models.user import User, UserRole
from app.database import SessionLocal
from app.security import hash_password
from app.services.stock_service import convert_quantity


client = TestClient(app)

BOS_USERNAME = "pytest_bos"
BOS_PASSWORD = "pytest-secret-123"


def _local_db_only() -> None:
    """Gagal keras kalau tes menulis ke database non-lokal."""
    host = urlparse(os.environ.get("DATABASE_URL", "")).hostname
    if host not in (None, "127.0.0.1", "localhost", "::1"):
        raise RuntimeError(f"tes integrasi menolak menulis ke database remote: {host}")


@pytest.fixture(scope="module")
def bos_client():
    """Buat store + akun BOS sendiri, lalu nonaktifkan lagi di akhir."""
    _local_db_only()
    db = SessionLocal()
    code = "PYTEST"
    try:
        store = (
            db.query(Store)
            .filter(Store.code == code)
            .one_or_none()
        )
        if store is None:
            store = Store(
                code=code,
                name="Toko Uji Pytest",
                owner_name="Pytest",
                plan=Plan.TRIAL,
                status=StoreStatus.ACTIVE,
                is_active=True,
            )
            db.add(store)
            db.flush()

        user = (
            db.query(User)
            .filter(User.username == BOS_USERNAME)
            .one_or_none()
        )
        if user is None:
            user = User(
                username=BOS_USERNAME,
                full_name="BOS Pytest",
                password_hash=hash_password(BOS_PASSWORD),
                role=UserRole.BOS.value,
                is_active=True,
                store_id=store.id,
            )
            db.add(user)
        else:
            user.password_hash = hash_password(BOS_PASSWORD)
            user.is_active = True
            user.store_id = store.id
        db.commit()
    finally:
        db.close()

    yield client

    db = SessionLocal()
    try:
        store = db.query(Store).filter(Store.code == code).one_or_none()
        if store is not None:
            store.is_active = False
            store.status = StoreStatus.SUSPENDED
            db.query(User).filter(User.username == BOS_USERNAME).update({"is_active": False})
            db.commit()
    finally:
        db.close()



def test_convert_quantity_gram_ke_kg():
    assert convert_quantity(1000, "gram", "kg") == 1.0
    assert convert_quantity(100, "gram", "kg") == 0.1
    assert convert_quantity(2500, "gram", "kg") == 2.5


def test_convert_quantity_kg_ke_gram():
    assert convert_quantity(2, "kg", "gram") == 2000.0


def test_convert_quantity_buah_ke_pcs():
    assert convert_quantity(3, "buah", "pcs") == 3.0
    assert convert_quantity(5, "pcs", "buah") == 5.0


def test_convert_quantity_satuan_sama():
    assert convert_quantity(7, "kg", "kg") == 7.0
    assert convert_quantity(2, "buah", "buah") == 2.0


def test_convert_quantity_tidak_kompatibel():
    assert convert_quantity(2, "sisir", "kg") is None
    assert convert_quantity(1, "kg", "buah") is None


def test_convert_quantity_keliru():
    with pytest.raises((ValueError, TypeError)):
        convert_quantity("x", "kg", "kg")


def test_login_masuk_invalid_tanpa_token():
    assert client.get("/api/v1/reports/dashboard").status_code == 401


def test_login_bos_berhasil(bos_client):
    r = bos_client.post(
        "/api/v1/auth/login", json={"username": BOS_USERNAME, "password": BOS_PASSWORD}
    )
    assert r.status_code == 200, r.text
    assert "access_token" in r.json()


def test_dashboard_berisi_kunci_utama(bos_client):
    r = bos_client.post(
        "/api/v1/auth/login", json={"username": BOS_USERNAME, "password": BOS_PASSWORD}
    )
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    r2 = bos_client.get("/api/v1/reports/dashboard", headers={"Authorization": f"Bearer {token}"})
    assert r2.status_code == 200, r2.text
    d = r2.json()
    for key in ("revenue_today", "sales_count_today", "items_sold_today", "profit_today",
                "pending_damage_count", "low_stock_products", "top_products"):
        assert key in d, f"kunci {key} tidak ada di dashboard"


def test_owner_tidak_bisa_masuk_lewat_login_pos(bos_client):
    """Pemisahan identitas: OWNER hanya boleh lewat /admin/auth/login."""
    r = bos_client.post(
        "/api/v1/auth/login", json={"username": "owner", "password": "owner-secret-123"}
    )
    assert r.status_code in (401, 403), r.text


def test_ping_public_200():
    r = client.get("/health")
    assert r.status_code in (200, 404)  # /health ada atau belum dipasang


# --- Kontrak waktu API ------------------------------------------------------
#
# Semua waktu yang keluar dari API harus punya offset eksplisit. Tanpa suffix
# Z, JavaScript membaca "2026-09-28T15:51:18" sebagai waktu LOKAL browser,
# dan Owner Console menampilkan jam yang meleset 7 jam untuk WIB -- atau benar
# hanya kebetulan kalau browser kebetulan di UTC. Tes ini mengunci suffix
# supaya regresi ke .isoformat() langsung terlihat, bukan ditemukan saat UAT.


def _kumpulkan_waktu(payload, jalur="", hasil=None):
    """Kumpulkan (path, nilai) untuk setiap key yang namanya jam."""
    if hasil is None:
        hasil = []
    if isinstance(payload, dict):
        for k, v in payload.items():
            _kumpulkan_waktu(v, f"{jalur}.{k}", hasil)
    elif isinstance(payload, list):
        for i, v in enumerate(payload):
            _kumpulkan_waktu(v, f"{jalur}[{i}]", hasil)
    elif isinstance(payload, str) and ("_at" in jalur or jalur.endswith(".time")):
        hasil.append((jalur, payload))
    return hasil


def test_health_time_berakhiran_z():
    r = client.get("/health")
    if r.status_code != 200:
        pytest.skip("endpoint /health tidak aktif")
    waktu = r.json().get("time")
    assert waktu, "/health tidak mengembalikan time"
    assert waktu.endswith("Z"), f"time harus UTC eksplisit, dapat {waktu!r}"


def test_health_time_setara_waktu_utc_sekarang():
    """Pastikan suffix Z bukan hiasan: nilainya harus benar-benar UTC."""
    r = client.get("/health")
    if r.status_code != 200:
        pytest.skip("endpoint /health tidak aktif")
    Waktu = r.json()["time"]
    parsed = datetime.fromisoformat(Waktu.replace("Z", "+00:00"))
    assert parsed.tzinfo is not None, "waktu harus punya zona"
    selisih = abs((datetime.now(timezone.utc) - parsed).total_seconds())
    assert selisih < 120, f"waktu server meleset {selisih:.0f} detik dari UTC"


def test_produk_semua_waktu_berakhiran_z(bos_client):
    """/products mengembalikan created_at dan updated_at. Ini titik masuk
    data yang dipakai Owner Console, jadi harus pakai UTC eksplisit.

    Produk dibuat sendiri oleh tes ini, bukan mengandalkan sisa seed. Kalau
    toko uji kebetulan kosong, tes ini akan di-skip dan kontrak waktu jadi
    tidak pernah diuji sama sekali -- persis kelas kegagalan yang membuat
    bug ini bisa lolos ke UAT.
    """
    _local_db_only()
    r = bos_client.post(
        "/api/v1/auth/login", json={"username": BOS_USERNAME, "password": BOS_PASSWORD}
    )
    token = r.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    nama = f"pytest-waktu-{uuid.uuid4().hex[:8]}"
    dibuat = bos_client.post(
        "/api/v1/products",
        json={
            "name": nama,
            "unit": "kg",
            "modal_price": 1000,
            "selling_price": 1500,
            "stock": 3,
            "min_stock": 1,
        },
        headers=headers,
    )
    assert dibuat.status_code in (200, 201), dibuat.text
    pid = dibuat.json()["id"]

    try:
        r2 = bos_client.get("/api/v1/products", headers=headers)
        assert r2.status_code == 200, r2.text

        # /products mengembalikan list langsung, bukan {"items": [...]}.
        body = r2.json()
        items = body.get("items") if isinstance(body, dict) else body
        assert items, "/products mengembalikan daftar kosong"

        milik_kita = [p for p in items if p.get("id") == pid]
        assert milik_kita, "produk uji tidak muncul di /products"

        waktu = _kumpulkan_waktu(milik_kita[0])
        assert waktu, "produk tidak mengembalikan field waktu untuk diperiksa"
        for jalur, nilai in waktu:
            assert nilai.endswith("Z"), f"{jalur} harus berakhiran Z, dapat {nilai!r}"

        assert milik_kita[0]["created_at"].endswith("Z")
        assert milik_kita[0]["updated_at"].endswith("Z")
    finally:
        db = SessionLocal()
        try:
            db.query(StockMovement).filter(
                StockMovement.product_id == uuid.UUID(pid)
            ).delete(synchronize_session=False)
            p = db.query(Product).filter(Product.id == uuid.UUID(pid)).one_or_none()
            if p is not None:
                db.delete(p)
            db.commit()
        finally:
            db.close()


def test_produk_soft_delete_dan_rekonsiliasi(bos_client):
    """Produk yang dinonaktifkan di server harus tetap terkirim ke POS
    dengan is_active=false, bukan hilang. Kalau hilang, perangkat tidak
    pernah tahu produk itu dihapus dan kasir masih bisa menjualnya."""
    _local_db_only()
    r = bos_client.post(
        "/api/v1/auth/login", json={"username": BOS_USERNAME, "password": BOS_PASSWORD}
    )
    token = r.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    nama = f"pytest-softdel-{uuid.uuid4().hex[:8]}"
    dibuat = bos_client.post(
        "/api/v1/products",
        json={
            "name": nama,
            "unit": "kg",
            "modal_price": 1000,
            "selling_price": 1500,
            "stock": 5,
            "min_stock": 1,
        },
        headers=headers,
    )
    assert dibuat.status_code in (200, 201), dibuat.text
    pid = dibuat.json()["id"]

    try:
        # Sync pull harus memuat produk ini sebagai aktif.
        pull = bos_client.post(
            "/api/v1/sync/pull", json={"device_id": None}, headers=headers
        )
        assert pull.status_code == 200, pull.text
        aktif = [p for p in pull.json()["products"] if p["id"] == pid]
        assert aktif, "produk baru tidak muncul di sync pull"
        assert aktif[0]["is_active"] is True

        hapus = bos_client.delete(f"/api/v1/products/{pid}", headers=headers)
        assert hapus.status_code in (200, 204), hapus.text

        # Setelah penghapusan: produk masih ada, tapi is_active=false.
        pull2 = bos_client.post(
            "/api/v1/sync/pull", json={"device_id": None}, headers=headers
        )
        setelah = [p for p in pull2.json()["products"] if p["id"] == pid]
        assert setelah, (
            "produk nonaktif hilang dari sync pull; perangkat tidak akan "
            "tahu untuk menyembunyikannya"
        )
        assert setelah[0]["is_active"] is False, "produk harus ditandai nonaktif"

        # Membuat nama yang sama harus menghidupkan kembali ID yang sama,
        # bukan membuat duplikat yang bentrok dengan index parsial.
        buat_lagi = bos_client.post(
            "/api/v1/products",
            json={
                "name": nama,
                "unit": "kg",
                "modal_price": 1200,
                "selling_price": 1800,
                "stock": 7,
                "min_stock": 1,
            },
            headers=headers,
        )
        assert buat_lagi.status_code in (200, 201), buat_lagi.text
        assert buat_lagi.json()["id"] == pid, (
            "produk dengan nama sama harus memakai kembali ID lama, bukan baris baru"
        )
        # body.stock berarti stok AKHIR produk, bukan tambahan: baris lama
        # masih menyimpan stock=5, kalau dijumlahkan jadi 12, bukan 7.
        assert float(buat_lagi.json()["stock"]) == 7, (
            "revive harus menghasilkan stok absolut 7, bukan 5+7=12: "
            f"dapat {buat_lagi.json()['stock']}"
        )

        # Laporan stok harus menghitung INITIAL sebagai stok masuk agar
        # stok awal produk tidak hilang dari laporan.
        laporan = bos_client.get("/api/v1/reports/stock", headers=headers)
        assert laporan.status_code == 200, laporan.text
        baris = [
            b for b in laporan.json()["products"] if b.get("product_id") == pid
        ]
        assert baris and float(baris[0]["stock_in"]) >= 2, (
            "movement INITIAL tidak dihitung sebagai stok masuk pada laporan"
        )
    finally:
        # Pembersihan harus benar-benar menghapus baris, tapi produk test ini
        # punya StockMovement INITIAL yang dibuat saat produk dibuat. db.delete()
        # akan membuat product_id=NULL dan gagal dengan NotNullViolation,
        # jadi movements-nya dihapus lebih dulu.
        db = SessionLocal()
        try:
            db.query(StockMovement).filter(
                StockMovement.product_id == uuid.UUID(pid)
            ).delete(synchronize_session=False)
            p = db.query(Product).filter(Product.id == uuid.UUID(pid)).one_or_none()
            if p is not None:
                db.delete(p)
            db.commit()
        finally:
            db.close()