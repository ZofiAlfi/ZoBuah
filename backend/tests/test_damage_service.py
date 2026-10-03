"""Unit test logika bersama persetujuan laporan barang rusak.

Test ini sengaja TIDAK memakai database. Modellnya memakai `postgresql.UUID`
yang tidak bisa dikompilasi ke SQLite, dan test integrasi yang ada semuanya
menunjuk ke SessionLocal -- yaitu database produksi. Untuk logika albumin yang
sUDAH dibungkus di satu service, kita tidak perlu database sama sekali:
persetujuan cukup dicek dari status laporan dan isi fieldnya.

Fokus test:
  - quantity yang dipotong diambil dari qty_in_base_unit, dengan fallback ke quantity
  - laporan non-PENDING ditolak di kedua pintu masuk
  - alasan penolakan wajib >= 10 karakter
  - reject_core mengisi field penolakan dan menjunky stok
"""

import pytest
from fastapi import HTTPException

from app.services.damage_service import (
    _deductable_quantity,
    approve_core,
    reject_core,
)


class FakeReport:
    """Cukup untuk biznis, tanpa kolom database."""

    def __init__(self, status="PENDING", quantity=3.0, qty_in_base_unit=None, product_id="p1"):
        self.id = "r1"
        self.store_id = "s1"
        self.product_id = product_id
        self.quantity = quantity
        self.qty_in_base_unit = qty_in_base_unit
        self.status = status
        self.reason = "bocor"
        self.product_name = "Susu UHT"
        self.unit = "pcs"
        self.rejected_by = None
        self.rejected_at = None
        self.rejection_reason = None
        self.approved_by = None
        self.approved_at = None


class FakeActor:
    id = "u1"
    store_id = None


class FakeDb:
    """Mencatat panggilan tanpa menyentuh database."""

    def __init__(self):
        self.committed = 0
        self.added = []
        self.rolled_back = 0

    def add(self, obj):
        self.added.append(obj)

    def commit(self):
        self.committed += 1

    def refresh(self, obj):
        pass

    def rollback(self):
        self.rolled_back += 1


class FakeQuery:
    def __init__(self, result):
        self._result = result

    def filter(self, *a, **kw):
        return self

    def first(self):
        return self._result


class FakeProduct:
    """Field yang dipakai record_stock_movement: id, name, stock, store_id."""

    id = "p1"
    store_id = "s1"
    name = "Susu UHT"
    unit = "pcs"
    stock = 10.0


def db_returning_product(product=FakeProduct()):
    """Session palsu yang selalu mengembalikan `product` saat .query().first().

    Objeknya sekaligus jadi sumber data: `.committed`, `.added`, dan
    `.rolled_back` bisa dibaca setelah operasi.
    """

    class Q:
        def __init__(self):
            self.committed = 0
            self.added = []
            self.rolled_back = 0

        def query(self, model):
            return FakeQuery(product)

        def add(self, obj):
            self.added.append(obj)

        def commit(self):
            self.committed += 1

        def refresh(self, obj):
            pass

        def rollback(self):
            self.rolled_back += 1

    return Q()


class TestDeductableQuantity:
    def test_pakai_qty_in_base_unit_kalau_ada(self):
        report = FakeReport(quantity=2.0, qty_in_base_unit=1.5)
        assert _deductable_quantity(report) == 1.5

    def test_fallback_ke_quantity_kalau_base_kosong(self):
        assert _deductable_quantity(FakeReport(quantity=4.0)) == 4.0
        assert _deductable_quantity(FakeReport(quantity=4.0, qty_in_base_unit=0.0)) == 4.0

    def test_fallback_ke_quantity_kalau_base_bukan_angka(self):
        report = FakeReport(quantity=5.0, qty_in_base_unit="bukan-angka")
        assert _deductable_quantity(report) == 5.0

    def test_nol_di_keduanya_ditolak(self):
        with pytest.raises(HTTPException) as exc:
            _deductable_quantity(FakeReport(quantity=0.0))
        assert exc.value.status_code == 400

    def test_nol_kosong_di_keduanya_ditolak(self):
        with pytest.raises(HTTPException) as exc:
            _deductable_quantity(FakeReport(quantity=None, qty_in_base_unit=None))
        assert exc.value.status_code == 400


class TestStateMachine:
    @pytest.mark.parametrize("status", ["APPROVED", "REJECTED"])
    def test_approve_menolak_laporan_yang_sudah_final(self, status):
        with pytest.raises(HTTPException) as exc:
            approve_core(
                FakeDb(), FakeReport(status=status), FakeActor(),
                audit_action="DAMAGE_REPORT_APPROVE", request=None,
            )
        assert exc.value.status_code == 400

    @pytest.mark.parametrize("status", ["APPROVED", "REJECTED"])
    def test_reject_menolak_laporan_yang_sudah_final(self, status):
        with pytest.raises(HTTPException) as exc:
            reject_core(
                FakeDb(), FakeReport(status=status), FakeActor(),
                reason="alasan yang cukup panjang",
                audit_action="DAMAGE_REPORT_REJECT", request=None,
            )
        assert exc.value.status_code == 400

    def test_reject_tanpa_alasan_ditolak(self):
        with pytest.raises(HTTPException) as exc:
            reject_core(
                FakeDb(), FakeReport(), FakeActor(),
                reason="kurang",
                audit_action="DAMAGE_REPORT_REJECT", request=None,
            )
        assert exc.value.status_code == 422

    def test_produk_hilang_memberi_404(self):
        with pytest.raises(HTTPException) as exc:
            approve_core(
                db_returning_product(product=None), FakeReport(), FakeActor(),
                audit_action="DAMAGE_REPORT_APPROVE", request=None,
            )
        assert exc.value.status_code == 404


class TestApproveCore:
    def test_stok_terpotong_sesuai_qty_in_base_unit(self):
        """Efek samping terpenting dari approve adalah pemotongan stok.

        Laporan 2 pcs dengan qty_in_base_unit 1.5 harus mengurangi stok 1.5,
        bukan 2. Salah di sini berarti barang rusak menguras stok dua kali.
        """
        product = FakeProduct()
        product.stock = 10.0
        approve_core(
            db_returning_product(product=product),
            FakeReport(quantity=2.0, qty_in_base_unit=1.5),
            FakeActor(),
            audit_action="DAMAGE_REPORT_APPROVE", request=None,
        )
        assert product.stock == 8.5

    def test_movemen_stok_tercatat_sebagai_DAMAGE(self):
        db = db_returning_product()
        approve_core(
            db, FakeReport(quantity=2.0, qty_in_base_unit=2.0), FakeActor(),
            audit_action="DAMAGE_REPORT_APPROVE", request=None,
        )
        movements = [o for o in db.added if type(o).__name__ == "StockMovement"]
        assert len(movements) == 1
        assert movements[0].movement_type == "DAMAGE"

    def test_approve_mengisi_field_dan_commit(self):
        db = db_returning_product()
        report = FakeReport(quantity=2.0, qty_in_base_unit=2.0)

        result = approve_core(
            db, report, FakeActor(),
            audit_action="DAMAGE_REPORT_APPROVE", request=None,
        )

        assert result.status == "APPROVED"
        assert result.approved_by == "u1"
        assert result.approved_at is not None
        assert db.committed >= 1

    def test_audit_action_dari_pemanggil_masuk_ke_log(self):
        db = db_returning_product()
        approve_core(
            db, FakeReport(quantity=2.0, qty_in_base_unit=2.0), FakeActor(),
            audit_action="DAMAGE_REPORT_APPROVE_ADMIN", request=None,
        )
        actions = [getattr(o, "action", None) for o in db.added]
        assert "DAMAGE_REPORT_APPROVE_ADMIN" in actions

    def test_aksi_bos_tidak_bocor_ke_log_admin(self):
        db = db_returning_product()
        approve_core(
            db, FakeReport(quantity=2.0, qty_in_base_unit=2.0), FakeActor(),
            audit_action="DAMAGE_REPORT_APPROVE", request=None,
        )
        actions = [getattr(o, "action", None) for o in db.added]
        assert "DAMAGE_REPORT_APPROVE_ADMIN" not in actions


class TestRejectCore:
    def test_reject_mengisi_field_penolakan(self):
        db = db_returning_product()
        report = FakeReport()

        result = reject_core(
            db, report, FakeActor(),
            reason="barang masih layak jual ulang",
            audit_action="DAMAGE_REPORT_REJECT", request=None,
        )

        assert result.status == "REJECTED"
        assert result.rejected_by == "u1"
        assert result.rejected_at is not None
        assert result.rejection_reason == "barang masih layak jual ulang"
        assert db.committed >= 1

    def test_alasan_dipangkas_spasi(self):
        db = db_returning_product()
        result = reject_core(
            db, FakeReport(), FakeActor(),
            reason="   masih layak dijual   ",
            audit_action="DAMAGE_REPORT_REJECT", request=None,
        )
        assert result.rejection_reason == "masih layak dijual"

    def test_reject_tidak_pernah_menyentuh_stok(self):
        """Menolak berarti barang dianggap masih layak jual.

        Kalau service ini diam-diam memanggil movements, stok toko akan berkurang
        untuk barang yang tidak benar-benar rusak. Ini termasuk bug yang paling
        mahal karena saldo tidak pernah cocok, tapi tidak ada error yang muncul.
        """
        db = db_returning_product()
        reject_core(
            db, FakeReport(), FakeActor(),
            reason="barang masih layak jual ulang",
            audit_action="DAMAGE_REPORT_REJECT", request=None,
        )
        movements = [o for o in db.added if type(o).__name__ == "StockMovement"]
        assert movements == []

    def test_admin_reject_menulis_aksi_admin(self):
        db = db_returning_product()
        reject_core(
            db, FakeReport(), FakeActor(),
            reason="barang masih layak jual ulang",
            audit_action="DAMAGE_REPORT_REJECT_ADMIN", request=None,
        )
        actions = [getattr(o, "action", None) for o in db.added]
        assert "DAMAGE_REPORT_REJECT_ADMIN" in actions
