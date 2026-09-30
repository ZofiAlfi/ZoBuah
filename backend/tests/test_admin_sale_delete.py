"""Integrasi: hapus transaksi oleh OWNER (soft delete, stok kembali).

Mengikuti aturan test_simple: seluruh data uji dibuat sendiri oleh fixture
lalu dibersihkan di akhir module; tidak bergantung akun demo hasil seed.

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
STORE_CODE = f"DEL{SUFFIX[:3].upper()}"
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
            name="Toko Uji Delete",
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
                    .filter(User.username.in_([OWNER_USERNAME, BOS_USERNAME]))
                    .all()
                ]
            ))
        ).delete(synchronize_session=False)
        for s in rows:
            db.delete(s)
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


def test_owner_bisa_hapus_transaksi(env):
    sale = _create_sale(env)
    sid = sale["id"]
    store_id = env["store_id"]

    r = client.post(
        f"/api/v1/admin/stores/{store_id}/sales/{sid}/delete",
        headers=env["owner_headers"],
        json={"reason": "Duplikat, salah input"},
    )
    assert r.status_code == 200, r.text
    d = r.json()

    assert d["id"] == sid
    assert d["status"] == "CANCELED"
    assert d["canceled_reason"] == "Duplikat, salah input"

    db = SessionLocal()
    try:
        a = db.query(Product).filter(Product.id == env["p1_id"]).one()
        # 50 - 2 (jual) + 2 (kembali) = 50 utuh.
        assert float(a.stock) == 50.0, f"stok p1 harus kembali 50, dapat {a.stock}"

        types = {
            m.reference_type
            for m in db.query(StockMovement)
            .filter(
                StockMovement.store_id == uuid.UUID(store_id),
                StockMovement.reference_id == uuid.UUID(sid),
            )
            .all()
        }
        assert "sale" in types, "transaksi asli harus mencatat SALE"
        assert "sale_delete" in types, "penghapusan harus mencatat RETURN"

        audit = (
            db.query(AuditLog)
            .filter(AuditLog.action == "SALE_DELETE", AuditLog.entity_id == sid)
            .first()
        )
        assert audit is not None, "harus ada jejak audot SALE_DELETE"
    finally:
        db.close()

    detail = client.get(
        f"/api/v1/admin/stores/{store_id}/sales/{sid}",
        headers=env["owner_headers"],
    )
    assert detail.status_code == 200, detail.text
    actions = [h["action"] for h in detail.json()["edit_history"]]
    assert "SALE_DELETE" in actions, "detail harus menampilkan riwayat hapus"


def test_hapus_transaksi_canceled_ditolak(env):
    sale = _create_sale(env)
    sid = sale["id"]
    store_id = env["store_id"]

    cancel = client.post(
        f"/api/v1/sales/{sid}/cancel",
        headers=env["bos_headers"],
        json={"reason": "Tidak jadi"},
    )
    assert cancel.status_code == 200, cancel.text

    r = client.post(
        f"/api/v1/admin/stores/{store_id}/sales/{sid}/delete",
        headers=env["owner_headers"],
        json={"reason": "Coba hapus yang sudah batal"},
    )
    assert r.status_code == 400, r.text
    assert r.json()["detail"]


def test_hapus_hanya_untuk_owner(env):
    sale = _create_sale(env)
    sid = sale["id"]
    store_id = env["store_id"]

    r = client.post(
        f"/api/v1/admin/stores/{store_id}/sales/{sid}/delete",
        headers=env["bos_headers"],
        json={"reason": "Bos mencoba"},
    )
    assert r.status_code in (401, 403), r.text


def test_hapus_transaksi_tidak_ada_404(env):
    store_id = env["store_id"]
    r = client.post(
        f"/api/v1/admin/stores/{store_id}/sales/{str(uuid.uuid4())}/delete",
        headers=env["owner_headers"],
        json={"reason": "Tidak ada"},
    )
    assert r.status_code == 404, r.text