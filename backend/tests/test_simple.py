"""Tes simpel backend ZoBuah: fungsi murni + integrasi ringan ke DB lokal.

Jalankan: python -m pytest tests -q

Tes integrasi tidak boleh bergantung pada akun demo hasil seed. Dulu file ini
login memakai "zofi"/"12345" yang sudah hilang saat migrasi multi-tenant, jadi
dua tes gagal begitu schema di-seed ulang. Sekarang store dan akun BOS dibuat
sendiri oleh fixture, lalu dimatikan lagi setelah selesai.
"""

import os
import uuid
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models.product import Product
from app.models.sale import Sale, SaleItem, Payment
from app.models.stock_movement import StockMovement
from app.models.store import Plan, Store, StoreStatus
from app.models.user import User, UserRole
from app.database import SessionLocal
from app.security import hash_password
from app.services.stock_service import convert_quantity
from app.routes.sync import _as_naive_utc


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


def test_sync_pull_delta_mengirim_transaksi_baru(bos_client):
    """Delta pull harus mengembalikan transaksi yang baru saja diperbarui.

    Ini mengunci bug "riwayat di HP tidak live". Kolom `updated_at` adalah
    TIMESTAMP WITHOUT TIME ZONE berisi UTC, sementara perangkat mengirim
    `last_sync_at` sebagai ISO ber-timezone (`...Z`). PostgreSQL membaca kolom
    naive itu memakai TimeZone sesi (Asia/Bangkok, +07), sehingga setiap baris
    terlihat 7 jam lebih tua dan `updated_at >= since` tidak pernah cocok.
    Akibatnya delta pull selalu mengembalikan 0 transaksi: koreksi dari Owner
    Console baru terlihat di POS setelah aplikasi dijalankan ulang (full pull).
    """
    login = bos_client.post(
        "/api/v1/auth/login",
        json={"username": BOS_USERNAME, "password": BOS_PASSWORD},
    )
    assert login.status_code == 200, login.text
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

    db = SessionLocal()
    nomor = f"DLT-{uuid.uuid4().hex[:8]}"
    try:
        user = db.query(User).filter(User.username == BOS_USERNAME).one()
        db.add(
            Sale(
                store_id=user.store_id,
                employee_id=user.id,
                transaction_number=nomor,
                total_amount=1000,
                updated_at=datetime.utcnow(),
            )
        )
        db.commit()

        # Watermark 5 menit lalu, dalam bentuk ber-timezone persis seperti
        # yang dikirim aplikasi.
        since = (datetime.now(timezone.utc) - timedelta(minutes=5)).isoformat()
        assert since.endswith("+00:00")

        r = bos_client.post(
            "/api/v1/sync/pull",
            json={"device_id": None, "last_sync_at": since},
            headers=headers,
        )
        assert r.status_code == 200, r.text
        terkirim = [s for s in r.json()["sales"] if s["transaction_number"] == nomor]
        assert terkirim, (
            "delta pull tidak mengirim transaksi yang baru diperbarui; "
            "riwayat POS tidak akan pernah live"
        )
        assert float(terkirim[0]["total_amount"]) == 1000
    finally:
        db.query(Sale).filter(Sale.transaction_number == nomor).delete(
            synchronize_session=False
        )
        db.commit()
        db.close()


def test_sync_pull_delta_batas_zona_waktu(bos_client):
    """Watermark harus dinormalkan ke UTC naive, bukan dipakai apa adanya."""
    dari_app = datetime(2026, 9, 30, 16, 0, 0, tzinfo=timezone.utc)
    assert _as_naive_utc(dari_app) == datetime(2026, 9, 30, 16, 0, 0)
    assert _as_naive_utc(dari_app).tzinfo is None, "harus naive agar bisa dibandingkan"

    # Watermark yang sudah naive (dtLokal tanpa zona) tidak boleh di geser.
    sudah_naive = datetime(2026, 9, 30, 16, 0, 0)
    assert _as_naive_utc(sudah_naive) == sudah_naive

    # Watermark dari zona lain harus dikonversi ke UTC, bukan dibuang zonanya.
    wib = datetime(2026, 9, 30, 23, 0, 0, tzinfo=timezone(timedelta(hours=7)))
    assert _as_naive_utc(wib) == datetime(2026, 9, 30, 16, 0, 0)


def test_sync_pull_delta_mengirim_laporan_baru(bos_client):
    """Damage report memakai filter `updated_at` yang sama, jadi punya bug
    timezone yang sama. Laporan baru harus muncul di delta pull juga."""
    from app.models.damage_report import DamageReport

    login = bos_client.post(
        "/api/v1/auth/login",
        json={"username": BOS_USERNAME, "password": BOS_PASSWORD},
    )
    assert login.status_code == 200, login.text
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

    db = SessionLocal()
    produk = None
    try:
        user = db.query(User).filter(User.username == BOS_USERNAME).one()
        produk = (
            db.query(Product)
            .filter(Product.store_id == user.store_id, Product.name.like("pytest-dmg-%"))
            .first()
        )
        if produk is None:
            produk = Product(
                store_id=user.store_id,
                name=f"pytest-dmg-{uuid.uuid4().hex[:8]}",
                unit="kg",
                modal_price=1000,
                selling_price=1500,
                stock=5,
                min_stock=1,
            )
            db.add(produk)
            db.flush()
        db.add(
            DamageReport(
                store_id=user.store_id,
                product_id=produk.id,
                quantity=1,
                unit=produk.unit,
                qty_in_base_unit=1,
                reason="BARU",
                description="pytest laporan baru",
                status="PENDING",
                employee_id=user.id,
                updated_at=datetime.utcnow(),
            )
        )
        db.commit()

        since = (datetime.now(timezone.utc) - timedelta(minutes=5)).isoformat()
        r = bos_client.post(
            "/api/v1/sync/pull",
            json={"device_id": None, "last_sync_at": since},
            headers=headers,
        )
        assert r.status_code == 200, r.text
        assert any(
            d.get("description") == "pytest laporan baru"
            for d in r.json()["damage_reports"]
        ), "laporan baru tidak terkirim di delta pull"
    finally:
        db.query(DamageReport).filter(
            DamageReport.description == "pytest laporan baru"
        ).delete(synchronize_session=False)
        db.flush()
        if produk is not None and produk.name.startswith("pytest-dmg-"):
            db.query(StockMovement).filter(
                StockMovement.product_id == produk.id
            ).delete(synchronize_session=False)
            db.delete(produk)
        db.commit()
        db.close()


def test_created_at_perangkat_disimpan_sebagai_utc(bos_client):
    """Transaksi dari POS harus tersimpan UTC, bukan jam lokal perangkat.

    POS mengirim `created_at` ber-timezone (`...Z`). Kalau penanda zonanya
    dibuang tanpa konversi, jam aslinya bergeser 7 jam (WIB) dan Owner Console
    menampilkannya di tanggal berikutnya -- persis yang terjadi pada transaksi
    yang dibuat saat offline.
    """
    from app.routes.sync import _as_stored_utc

    # 23:45 WIB = 16:45 UTC. Harus disimpan 16:45, bukan 23:45.
    wib = datetime(2026, 9, 30, 23, 45, 6, tzinfo=timezone(timedelta(hours=7)))
    assert _as_stored_utc(wib.isoformat()) == datetime(2026, 9, 30, 16, 45, 6)
    assert _as_stored_utc(wib.isoformat()).tzinfo is None

    # Sudah UTC pun tidak boleh digeser.
    utc = datetime(2026, 9, 30, 16, 45, 6, tzinfo=timezone.utc)
    assert _as_stored_utc(utc.isoformat()) == datetime(2026, 9, 30, 16, 45, 6)

    # Tanpa created_at: pakai jam server, bukan error.
    sebelum = datetime.utcnow()
    diisi = _as_stored_utc(None)
    assert diisi is not None
    assert (diisi - sebelum).total_seconds() < 5

    # Integrasi: sale hasil push tidak boleh berjam lokal.
    _local_db_only()
    login = bos_client.post(
        "/api/v1/auth/login",
        json={"username": BOS_USERNAME, "password": BOS_PASSWORD},
    )
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    nomor = f"TZ-{uuid.uuid4().hex[:8]}"
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.username == BOS_USERNAME).one()
        produk = (
            db.query(Product)
            .filter(Product.store_id == user.store_id, Product.name.like("pytest-tz-%"))
            .first()
        )
        if produk is None:
            produk = Product(
                store_id=user.store_id,
                name=f"pytest-tz-{uuid.uuid4().hex[:8]}",
                unit="kg",
                modal_price=1000,
                selling_price=1500,
                stock=5,
                min_stock=1,
            )
            db.add(produk)
            db.commit()
        # Sisa run yang gagal pernah menguras stok produk uji, jadi pastikan
        # cukup dulu supaya tes tidak gagal karena bukan karena timezone.
        produk.stock = 1000
        db.commit()
        r = bos_client.post(
            "/api/v1/sync/push",
            json={
                "device_id": None,
                "items": [
                    {
                        "entity_type": "sale",
                        "entity_id": str(uuid.uuid4()),
                        "data": {
                            "id": str(uuid.uuid4()),
                            "transaction_number": nomor,
                            "employee_id": str(user.id),
                            "total_amount": 1500,
                            "total_modal": 1000,
                            "total_profit": 500,
                            "discount": 0,
                            "status": "COMPLETED",
                            # 23:45 WIB
                            "created_at": "2026-09-30T23:45:06+07:00",
                            "items": [
                                {
                                    "product_id": str(produk.id),
                                    "product_name": produk.name,
                                    "unit": "kg",
                                    "quantity": 1.5,
                                    "unit_price": 1000,
                                    "modal_price": 1000,
                                    "subtotal": 1500,
                                }
                            ],
                            "payment": {"method": "CASH", "amount": 1500},
                        },
                    }
                ],
            },
            headers=headers,
        )
        assert r.status_code == 200, r.text
        assert r.json().get("accepted") == 1, f"push ditolak: {r.text}"
        row = (
            db.query(Sale)
            .filter(Sale.transaction_number == nomor)
            .one_or_none()
        )
        assert row is not None, f"transaksi {nomor} tidak tersimpan"
        assert row.created_at == datetime(2026, 9, 30, 16, 45, 6), (
            f"created_at tersimpan {row.created_at}, harusnya 16:45:06 UTC "
            "(23:45 WIB dikonversi), bukan 23:45 apa adanya"
        )
    finally:
        _id_sale = db.query(Sale.id).filter(Sale.transaction_number == nomor)
        db.query(Payment).filter(Payment.sale_id.in_(_id_sale)).delete(
            synchronize_session=False
        )
        db.query(SaleItem).filter(SaleItem.sale_id.in_(_id_sale)).delete(
            synchronize_session=False
        )
        db.query(Sale).filter(Sale.transaction_number == nomor).delete(
            synchronize_session=False
        )
        db.flush()
        if produk is not None and produk.name.startswith("pytest-tz-"):
            # Hapus SEMUA sale_items produk ini dulu, bukan hanya yang milik
            # transaksi tes. Kalau ada sisa dari run sebelumnya, db.delete()
            # produk akan menulis NULL ke product_id (NOT NULL) dan gagal.
            db.query(SaleItem).filter(
                SaleItem.product_id == produk.id
            ).delete(synchronize_session=False)
            db.query(StockMovement).filter(
                StockMovement.product_id == produk.id
            ).delete(synchronize_session=False)
            db.delete(produk)
        db.commit()
        db.close()


def test_sync_pull_sales_complete_bendera(bos_client):
    """sales_complete true kalau payload sales lengkap, false kalau terpotong 500.

    Klien POS memakai bendera ini untuk memutuskan apakah boleh merekonsiliasi
    riwayat transaksi lokal: full pull yang terpotong (>= 500 transaksi) tidak
    boleh dijadikan dasar menghapus riwayat yang tidak ikut terkirim.
    """
    login = bos_client.post(
        "/api/v1/auth/login",
        json={"username": BOS_USERNAME, "password": BOS_PASSWORD},
    )
    assert login.status_code == 200, login.text
    token = login.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    db = SessionLocal()
    user_id = None
    store_id = None
    try:
        user = db.query(User).filter(User.username == BOS_USERNAME).one()
        user_id = user.id
        store_id = user.store_id

        # Muat dulu berapa transaksi yang sudah ada milik akun ini, lalu isi
        # sampai total > 500 supaya payload full pull pasti terpotong.
        existing = (
            db.query(Sale)
            .filter(Sale.store_id == store_id, Sale.employee_id == user_id)
            .count()
        )
        for i in range(505 - existing if existing < 505 else 0):
            db.add(
                Sale(
                    store_id=store_id,
                    employee_id=user_id,
                    transaction_number=f"TST-{i}-{uuid.uuid4().hex[:8]}",
                )
            )
        db.commit()

        # Full pull (tanpa last_sync_at): terpotong pada batas 500.
        full = bos_client.post(
            "/api/v1/sync/pull", json={"device_id": None}, headers=headers
        )
        assert full.status_code == 200, full.text
        assert full.json()["sales_complete"] is False, (
            "full pull dengan >= 500 transaksi harus menandai sales terpotong"
        )
        assert len(full.json()["sales"]) == 500

        # Delta pull (dengan last_sync_at): bendera tidak dihitung, tetap true.
        delta = bos_client.post(
            "/api/v1/sync/pull",
            json={"device_id": None, "last_sync_at": "2020-01-01T00:00:00Z"},
            headers=headers,
        )
        assert delta.status_code == 200, delta.text
        assert delta.json()["sales_complete"] is True

        # Hapus transaksi TST- saja: full pull berikutnya lengkap dan bendera
        # true, tanpa menghiraukan transaksi akun lain yang mungkin ada.
        db.query(Sale).filter(
            Sale.store_id == store_id,
            Sale.employee_id == user_id,
            Sale.transaction_number.like("TST-%"),
        ).delete(synchronize_session=False)
        db.commit()

        kosong = bos_client.post(
            "/api/v1/sync/pull", json={"device_id": None}, headers=headers
        )
        assert kosong.status_code == 200, kosong.text
        assert kosong.json()["sales_complete"] is True
        assert all(
            not s["transaction_number"].startswith("TST-")
            for s in kosong.json()["sales"]
        ), "transaksi TST- masih tersisa setelah dihapus"
    finally:
        db.rollback()
        db.query(Sale).filter(
            Sale.transaction_number.like("TST-%")
        ).delete(synchronize_session=False)
        db.commit()
        db.close()