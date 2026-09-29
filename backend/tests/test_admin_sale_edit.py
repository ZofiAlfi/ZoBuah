"""Integrasi: koreksi/edit transaksi oleh OWNER (FASE 11).

Mengikuti aturan test_simple: tidak bergantung pada akun demo hasil seed;
seluruh data uji dibuat sendiri oleh fixture lalu dibersihkan di akhir module.

Jalankan (baris tunggal, PowerShell):
  $env:DATABASE_URL='postgresql+psycopg2://tester:tester@127.0.0.1:5432/zbtest'; python -m pytest tests -q
"""

import os
import uuid
from urllib.parse import urlparse

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.database import SessionLocal
from app.models.audit_log import AuditLog
from app.models.product import Product
from app.models.sale import Payment, Sale, SaleItem
from app.models.stock_movement import StockMovement
from app.models.store import Plan, Store, StoreStatus
from app.models.user import User, UserRole
from app.security import hash_password

client = TestClient(app)

SUFFIX = uuid.uuid4().hex[:6]
STORE_CODE = f"EDIT{SUFFIX[:3].upper()}"
OWNER_USERNAME = f"pytest_owner_{SUFFIX}"
BOS_USERNAME = f"pytest_bos_{SUFFIX}"
PASSWORD = "pytest-secret-123"


def _local_db_only() -> None:
    host = urlparse(os.environ.get("DATABASE_URL", "")).hostname
    if host not in (None, "127.0.0.1", "localhost", "::1"):
        raise RuntimeError(f"tes butuh database lokal, dapat: {host}")


def _login(url: str, username: str, password: str) -> str:
    r = client.post(url, json={"username": username, "password": password})
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


@pytest.fixture(scope="module")
def env():
    _local_db_only()
    db = SessionLocal()
    store_id = p1_id = p2_id = None
    try:
        store = Store(
            code=STORE_CODE,
            name="Toko Uji Edit",
            owner_name="Pytest",
            plan=Plan.TRIAL,
            status=StoreStatus.ACTIVE,
            is_active=True,
        )
        db.add(store)
        db.flush()

        owner = User(
            username=OWNER_USERNAME,
            full_name="Owner Uji",
            password_hash=hash_password(PASSWORD),
            role=UserRole.OWNER.value,
            is_active=True,
            store_id=None,
        )
        bos = User(
            username=BOS_USERNAME,
            full_name="BOS Uji",
            password_hash=hash_password(PASSWORD),
            role=UserRole.BOS.value,
            is_active=True,
            store_id=store.id,
        )
        db.add_all([owner, bos])
        db.flush()

        p1 = Product(
            name=f"Apel Uji-{SUFFIX}", unit="kg", modal_price=1000,
            selling_price=1500, stock=50, min_stock=1, is_active=True,
            store_id=store.id,
        )
        p2 = Product(
            name=f"Mangga Uji-{SUFFIX}", unit="kg", modal_price=2000,
            selling_price=3000, stock=30, min_stock=1, is_active=True,
            store_id=store.id,
        )
        db.add_all([p1, p2])
        db.commit()

        # Tangkap id SEBELUM session ditutup supaya tidak terjadi
        # DetachedInstanceError saat akses setelah fixture selesai.
        store_id = str(store.id)
        p1_id = str(p1.id)
        p2_id = str(p2.id)
    finally:
        db.close()

    owner_token = _login("/api/v1/admin/auth/login", OWNER_USERNAME, PASSWORD)
    bos_token = _login("/api/v1/auth/login", BOS_USERNAME, PASSWORD)

    yield {
        "store_id": store_id,
        "p1_id": p1_id,
        "p2_id": p2_id,
        "owner_headers": {"Authorization": f"Bearer {owner_token}"},
        "bos_headers": {"Authorization": f"Bearer {bos_token}"},
}

    del owner_token, bos_token

    db = SessionLocal()
    try:
        sid_uuid = uuid.UUID(store_id)
        rows = db.query(Sale).filter(Sale.store_id == sid_uuid).all()
        ids = [s.id for s in rows]
        if ids:
            db.query(SaleItem).filter(SaleItem.sale_id.in_(ids)).delete(
                synchronize_session=False
            )
            db.query(Payment).filter(Payment.sale_id.in_(ids)).delete(
                synchronize_session=False
            )
        db.query(StockMovement).filter(StockMovement.store_id == sid_uuid).delete(
            synchronize_session=False
        )
        db.query(AuditLog).filter(
            (AuditLog.store_id == sid_uuid)
            | (AuditLog.user_id.in_(
                [
                    u.id
                    for u in db.query(User)
                    .filter(
                        User.username.in_([OWNER_USERNAME, BOS_USERNAME])
                    )
                    .all()
                ]
            ))
        ).delete(synchronize_session=False)
        for s in rows:
            db.delete(s)
        # DELETE sales diproses di flush dulu: db.query(User).delete()
        # langsung mengirim SQL, sedangkan db.delete(obj) menunggu flush.
        db.flush()
        for pid in (p1_id, p2_id):
            row = db.query(Product).filter(Product.id == uuid.UUID(pid)).one_or_none()
            if row is not None:
                db.delete(row)
        db.query(User).filter(User.store_id == sid_uuid).delete(
            synchronize_session=False
        )
        db.query(User).filter(User.username == OWNER_USERNAME).delete(
            synchronize_session=False
        )
        row = db.query(Store).filter(Store.id == sid_uuid).one_or_none()
        if row is not None:
            db.delete(row)
        db.commit()
    finally:
        db.close()


def _create_sale(env, product_id=None, quantity=2, unit_price=1500) -> dict:
    product_id = product_id or env["p1_id"]
    r = client.post(
        "/api/v1/sales",
        headers=env["bos_headers"],
        json={
            "items": [
                {"product_id": product_id, "quantity": quantity,
                 "unit_price": unit_price}
            ],
            "payment": {
                "method": "CASH", "amount": unit_price * quantity,
                "cash_received": unit_price * quantity, "change_amount": 0,
            },
            "discount": 0,
        },
    )
    assert r.status_code == 201, r.text
    return r.json()


def test_owner_bisa_edit_transaksi(env):
    sale = _create_sale(env)
    sid = sale["id"]
    store_id = env["store_id"]

    r = client.patch(
        f"/api/v1/admin/stores/{store_id}/sales/{sid}",
        headers=env["owner_headers"],
        json={
            "reason": "Salah kasir, barang diganti",
            "items": [
                {"product_id": str(env["p2_id"]), "quantity": 1, "unit_price": 1000},
            ],
            "discount": 0,
            "payment": {"method": "TRANSFER", "amount": 1000, "reference": "TF-EDIT"},
        },
    )
    assert r.status_code == 200, r.text
    d = r.json()

    # Total dihitung ulang dari item baru (diskon 0).
    assert d["id"] == sid
    assert d["transaction_number"] == sale["transaction_number"]
    assert d["status"] == "COMPLETED"
    assert d["total_amount"] == 1000.0
    assert d["total_modal"] == 2000.0
    assert d["total_profit"] == -1000.0
    assert len(d["items"]) == 1
    assert d["items"][0]["product_id"] == str(env["p2_id"])
    assert d["payment"]["method"] == "TRANSFER"
    assert d["edit_history"], "riwayat edit harus terisi setelah koreksi"

    db = SessionLocal()
    try:
        a = db.query(Product).filter(Product.id == env["p1_id"]).one()
        b = db.query(Product).filter(Product.id == env["p2_id"]).one()
        # p1: 2 unit dijual, lalu dikembalikan -> 50 utuh
        assert float(a.stock) == 50.0, f"stok p1 harus kembali 50, dapat {a.stock}"
        # p2: 1 unit terpotong dari 30 -> 29
        assert float(b.stock) == 29.0, f"stok p2 harus 29, dapat {b.stock}"

        types = {
            m.reference_type
            for m in db.query(StockMovement)
            .filter(
                StockMovement.store_id == uuid.UUID(store_id),
                StockMovement.reference_id == uuid.UUID(sid),
            )
            .all()
        }
        assert "sale_edit_old" in types, "stok lama harus dicatat RETURN"
        assert "sale_edit" in types, "stok baru harus dicatat SALE"
    finally:
        db.close()


def test_edit_transaksi_canceled_ditolak(env):
    sale = _create_sale(env)
    sid = sale["id"]
    store_id = env["store_id"]

    cancel = client.post(
        f"/api/v1/sales/{sid}/cancel",
        headers=env["bos_headers"],
        json={"reason": "Tidak jadi diuji"},
    )
    assert cancel.status_code == 200, cancel.text

    r = client.patch(
        f"/api/v1/admin/stores/{store_id}/sales/{sid}",
        headers=env["owner_headers"],
        json={"items": [{"product_id": str(env["p1_id"]), "quantity": 1,
                         "unit_price": 1500}]},
    )
    assert r.status_code == 400, r.text
    assert r.json()["detail"], "detail error harus ada"


def test_edit_transaksi_toko_lain_ditolak(env):
    nonexistent_store = str(uuid.uuid4())
    nonexistent_sale = str(uuid.uuid4())
    r = client.patch(
        f"/api/v1/admin/stores/{nonexistent_store}/sales/{nonexistent_sale}",
        headers=env["owner_headers"],
        json={"items": [{"product_id": str(env["p1_id"]), "quantity": 1,
                         "unit_price": 1500}]},
    )
    assert r.status_code == 404, r.text


def test_edit_stok_tidak_cukup_rollback_total(env):
    sale = _create_sale(env)
    sid = sale["id"]
    store_id = env["store_id"]

    r = client.patch(
        f"/api/v1/admin/stores/{store_id}/sales/{sid}",
        headers=env["owner_headers"],
        json={"items": [{"product_id": str(env["p1_id"]), "quantity": 1000,
                         "unit_price": 1500}]},
    )
    assert r.status_code == 400, r.text

    db = SessionLocal()
    try:
        a = db.query(Product).filter(Product.id == env["p1_id"]).one()
        # Transaksi asli masih utuh: stok belum dikembalikan, belum dipotong.
        assert float(a.stock) == 48.0, f"stok harus tetap 48, dapat {a.stock}"
        s2 = db.query(Sale).filter(Sale.id == uuid.UUID(sid)).one()
        assert len(s2.sale_items) == 1
        assert float(s2.total_amount) == 3000.0
        pay = db.query(Payment).filter(Payment.sale_id == uuid.UUID(sid)).first()
        assert pay is not None and pay.method == "CASH"
    finally:
        db.close()


def test_owner_bisa_list_dan_detail_transaksi(env):
    sale = _create_sale(env)
    sid = sale["id"]
    store_id = env["store_id"]

    lst = client.get(
        f"/api/v1/admin/stores/{store_id}/sales",
        headers=env["owner_headers"],
    )
    assert lst.status_code == 200, lst.text
    body = lst.json()
    milik = [s for s in body["items"] if s["id"] == sid]
    assert milik, "transaksi harus muncul di daftar sales toko"
    assert milik[0]["item_count"] == 1
    assert milik[0]["status"] == "COMPLETED"
    assert milik[0]["employee_name"]

    detail = client.get(
        f"/api/v1/admin/stores/{store_id}/sales/{sid}",
        headers=env["owner_headers"],
    )
    assert detail.status_code == 200, detail.text
    d = detail.json()
    assert len(d["items"]) == 1
    assert d["payment"]["method"] == "CASH"
    assert not d["edit_history"], "belum ada edit, riwayat harus kosong"


def test_owner_bisa_list_produk_toko(env):
    store_id = env["store_id"]
    r = client.get(
        f"/api/v1/admin/stores/{store_id}/products",
        headers=env["owner_headers"],
    )
    assert r.status_code == 200, r.text
    rows = r.json()["items"]
    pids = {p["id"] for p in rows}
    assert str(env["p1_id"]) in pids
    assert str(env["p2_id"]) in pids
