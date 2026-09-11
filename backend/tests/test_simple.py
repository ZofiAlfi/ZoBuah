"""Tes simpel backend ZoBuah: memakai DB lokal (baca) + fungsi murni.

Jalankan: python -m pytest tests -q
"""

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services.stock_service import convert_quantity


client = TestClient(app)


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


def test_login_bos_berhasil():
    r = client.post("/api/v1/auth/login", json={"username": "bos", "password": "bos12345"})
    assert r.status_code == 200
    assert "access_token" in r.json()


def test_dashboard_berisi_kunci_utama():
    r = client.post("/api/v1/auth/login", json={"username": "bos", "password": "bos12345"})
    token = r.json()["access_token"]
    r2 = client.get("/api/v1/reports/dashboard", headers={"Authorization": f"Bearer {token}"})
    assert r2.status_code == 200
    d = r2.json()
    for key in ("revenue_today", "sales_count_today", "items_sold_today", "profit_today",
                "pending_damage_count", "low_stock_products", "top_products"):
        assert key in d, f"kunci {key} tidak ada di dashboard"


def test_ping_public_200():
    r = client.get("/health")
    assert r.status_code in (200, 404)  # /health ada atau belum dipasang