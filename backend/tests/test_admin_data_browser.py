"""Uji endpoint baca Data Browser tanpa menyentuh database.

Tujuan test ini bukan memeriksa nilai kembalinya, melainkan dua hal yang tidak
terlihat kalau endpoint-nya salah tapi berbahaya kalau benar:

  1. SQL-nya benar-benar terkompilasi untuk PostgreSQL, bukan hanya valid
     secara sintaks Python.
  2. Setiap query dibatasi store_id dari path. Tanpa filter ini, satu UUID
     toko cukup untuk membaca seluruh data toko lain.

Cara kerjanya: Session diganti pembungkus yang mencatat setiap query lalu
tidak pernah mengeksekusinya. count() dan all() mengembalikan kosong,
sedangkan statement-nya dikompilasi menjadi SQL. Tidak ada soket yang
pernah dibuka ke database produksi.
"""

import inspect
from datetime import date

import pytest
from fastapi import HTTPException, params
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.routes import admin as admin_routes

STORE_ID = "9f4c83b0-b719-477c-96e9-85146854643f"

ENDPOINTS = {
    "damage-reports": "store_damage_reports",
    "stock-movements": "store_stock_movements",
    "payments": "store_payments",
    "product-history": "store_product_history",
    "categories": "store_categories",
}


class DryQuery:
    """Pembungkus Query: mencatat rantai filter, tidak pernah mengeksekusi."""

    def __init__(self, inner, log):
        self._q = inner
        self._log = log

    def _wrap(self, inner):
        wrapper = DryQuery(inner, self._log)
        self._log.append(wrapper)
        return wrapper

    def filter(self, *a, **kw):
        return self._wrap(self._q.filter(*a, **kw))

    def outerjoin(self, *a, **kw):
        return self._wrap(self._q.outerjoin(*a, **kw))

    def join(self, *a, **kw):
        return self._wrap(self._q.join(*a, **kw))

    def options(self, *a, **kw):
        return self._wrap(self._q.options(*a, **kw))

    def order_by(self, *a):
        return self._wrap(self._q.order_by(*a))

    def offset(self, n):
        return self._wrap(self._q.offset(n))

    def limit(self, n):
        return self._wrap(self._q.limit(n))

    def group_by(self, *a):
        return self._wrap(self._q.group_by(*a))

    def count(self):
        return 0

    def all(self):
        return []

    def first(self):
        return None

    @property
    def sql(self):
        """SQL dengan nilai ditulis literal.

        Tanpa literal_binds, tanggal dan UUID muncul sebagai placeholder
        (%(created_at_1)s) sehingga batas filter tanggal tidak bisa diperiksa
        dari teks SQL sama sekali.
        """
        return str(
            self._q.statement.compile(
                dialect=self._q.session.bind.dialect,
                compile_kwargs={"literal_binds": True},
            )
        )


class DrySession:
    """Session yang membangun query sungguhan lalu membuang eksekusinya.

    Query dibangun di Session asli supaya model dan relasinya ter-resolve,
    karena di situlah kesalahan nama kolom akan muncul.
    """

    def __init__(self, engine):
        self._factory = sessionmaker(bind=engine)
        self.log = []

    def query(self, *a, **kw):
        session = self._factory()
        try:
            q = session.query(*a, **kw)
        finally:
            session.close()
        wrapper = DryQuery(q, self.log)
        self.log.append(wrapper)
        return wrapper

    @property
    def sql(self):
        return "\n".join(q.sql for q in self.log)


@pytest.fixture
def dry(monkeypatch):
    engine = create_engine("postgresql+psycopg2://u:p@localhost/nodb")
    session = DrySession(engine)
    monkeypatch.setattr(admin_routes, "get_store_or_404", lambda db, sid: object())
    return session


def call(fn, session, **overrides):
    """Panggil handler dengan penanda FastAPI diganti nilai nyata.

    Default parameter handler bukan nilai biasa: yang ada di sana adalah objek
    Query/Depends. Dipanggil langsung, `status` akan menerima objek Query
    (yang selalu dianggap benar) dan `db` akan menerima Depends, bukan
    session -- itu sebabnya test perlu melepas keduanya secara eksplisit.
    """
    kwargs = {}
    for name, param in inspect.signature(fn).parameters.items():
        if name in overrides:
            kwargs[name] = overrides[name]
            continue
        default = param.default
        if isinstance(default, params.Depends):
            kwargs[name] = None
        elif isinstance(default, params.Param):
            # Query(None) -> None, Query(20) -> 20, Query(None, le=200) -> None
            kwargs[name] = default.default
        elif default is not inspect.Parameter.empty:
            kwargs[name] = default
        else:
            # Parameter wajib tanpa default (mis. request: Request, body:
            # Skema). Test yang butuh nilainya menyediakannya lewat overrides;
            # sisanya dibiarkan None karena handler tidak akan menacainya --
            # body dan request baru disentuh setelah service dipanggil, dan
            # di situlah test memasang stub-nya.
            kwargs[name] = None
    kwargs["db"] = session
    return fn(**kwargs)


class TestSqlCompiles:
    @pytest.mark.parametrize("endpoint", sorted(ENDPOINTS))
    def test_sql_bisa_dikompilasi_untuk_postgres(self, dry, endpoint):
        fn = getattr(admin_routes, ENDPOINTS[endpoint])
        call(fn, dry, store_id=STORE_ID)

        assert dry.log, "endpoint tidak menghasilkan query sama sekali"
        for q in dry.log:
            assert "SELECT" in q.sql.upper()

    @pytest.mark.parametrize("endpoint", sorted(ENDPOINTS))
    def test_semua_query_lewat_pembungkus(self, dry, endpoint):
        """Tidak boleh ada jalur yang membangun query di luar pembungkus.

        Kalau satu jalur memakai session sungguhan, test ini akan mencoba
        konek ke database produksi -- persis hal yang tidak boleh terjadi
        di test unit.
        """
        fn = getattr(admin_routes, ENDPOINTS[endpoint])
        call(fn, dry, store_id=STORE_ID)
        assert dry.log
        assert all(isinstance(q, DryQuery) for q in dry.log)


class TestStoreIsolation:
    def test_damage_reports_dibatasi_store(self, dry):
        call(admin_routes.store_damage_reports, dry, store_id=STORE_ID)
        assert "damage_reports.store_id" in dry.sql

    def test_stock_movements_dibatasi_store(self, dry):
        call(admin_routes.store_stock_movements, dry, store_id=STORE_ID)
        assert "stock_movements.store_id" in dry.sql

    def test_product_history_dibatasi_store(self, dry):
        call(admin_routes.store_product_history, dry, store_id=STORE_ID)
        assert "audit_logs.store_id" in dry.sql

    def test_categories_dibatasi_store(self, dry):
        call(admin_routes.store_categories, dry, store_id=STORE_ID)
        assert "categories.store_id" in dry.sql

    def test_payments_dibatasi_lewat_sale(self, dry):
        """payments tidak punya kolom store_id.

        Filter harus ikut ke sales.store_id. Kalau hanya payments.id yang
        dibatasi, endpoint ini bisa membaca pembayaran toko mana pun hanya
        dengan menebak sale_id.
        """
        call(admin_routes.store_payments, dry, store_id=STORE_ID)
        assert "sales.store_id" in dry.sql


class TestDateRangeFilter:
    """Batas tanggal harus inklusif per hari dan dianggap UTC naive."""

    def _sql(self, dry, endpoint, **over):
        call(getattr(admin_routes, ENDPOINTS[endpoint]), dry, store_id=STORE_ID, **over)
        return dry.sql

    def test_date_from_menambahkan_batas_bawah(self, dry):
        sql = self._sql(dry, "damage-reports", date_from=date(2026, 1, 1))
        assert ">= " in sql or ">=" in sql

    def test_date_to_menggunakan_hari_berikutnya(self, dry):
        """date_to=2026-01-31 harus menyertakan jam 23:59 tanggal itu.

        Pakai <= tanggal membuat semua transaksi setelah jam 00:00 hilang,
        dan hilang tanpa jejak: totalnya terlihat benar, isinya kurang
        satu hari penuh.
        """
        sql = self._sql(dry, "damage-reports", date_to=date(2026, 1, 31))
        where = sql.split("WHERE", 1)[-1]
        assert "<=" not in where
        assert "2026-02-01" in where

    def test_tanpa_tanggal_tidak_ada_batas(self, dry):
        call(admin_routes.store_damage_reports, dry, store_id=STORE_ID)
        assert "2026" not in dry.sql
        assert "2025" not in dry.sql


class TestStoreGuardRunsFirst:
    @pytest.mark.parametrize("endpoint", sorted(ENDPOINTS))
    def test_toko_tidak_ada_menghasilkan_404(self, monkeypatch, endpoint):
        """get_store_or_404 harus jalan sebelum query apa pun.

        Kalau tidak, UUID acak akan membalas 200 dengan data kosong, dan
        pengguna tidak bisa membedakan "toko ini belum ada transaksi" dari
        "toko ini tidak ada".
        """
        called = {}

        def boom(db, sid):
            called["yes"] = True
            raise HTTPException(status_code=404, detail="Toko tidak ditemukan")

        monkeypatch.setattr(admin_routes, "get_store_or_404", boom)
        with pytest.raises(HTTPException) as exc:
            call(getattr(admin_routes, ENDPOINTS[endpoint]), object(),
                 store_id=STORE_ID)
        assert exc.value.status_code == 404
        assert called.get("yes")


class TestUnauthenticated:
    @pytest.mark.parametrize("endpoint", sorted(ENDPOINTS))
    def test_endpoint_menolak_tanpa_token(self, endpoint):
        """Semua endpoint wajib di balik require_owner().

        Kalau satu lupa, data operasional toko terbuka untuk siapa saja yang
        menemukan URL-nya.
        """
        client = TestClient(app)
        url = "/api/v1/admin/stores/%s/%s" % (STORE_ID, endpoint)
        assert client.get(url).status_code == 401


REPORT_ID = "1c1f0d2e-3a4b-5c6d-7e8f-9a0b1c2d3e4f"
OTHER_STORE_ID = "00000000-0000-0000-0000-000000000001"


class StubReport:
    """Laporan minimal yang cukup untuk _damage_item."""

    id = REPORT_ID
    store_id = STORE_ID
    product_id = "11111111-1111-1111-1111-111111111111"
    product = None
    employee_id = None
    approved_by = None
    rejected_by = None
    approved_at = None
    rejected_at = None
    rejection_reason = None
    created_at = None
    quantity = 1.0
    unit = "pcs"
    qty_in_base_unit = None
    reason = "bocor"
    description = None
    status = "PENDING"
    photos = []


class StubBody:
    def __init__(self, reason):
        self.reason = reason


class TestAdminDamageActions:
    """Dua endpoint persetujuan dari Owner Console."""

    def test_laporan_toko_lain_tidak_bisa_disetujui(self, dry):
        """Ini pemblrean paling berbahaya di blok ini di blok ini.

        store_id di path dan store_id laporan harus cocok. Kalau hanya
        report_id yang dipakai, owner bisa menulis path toko A lalu menyebut
        ID laporan toko B -- stok toko B berkurang tanpa ditanyakan ke siapa
        pun, dan tidak ada jejak di AuditLog toko B karena store_id-nya NULL.
        """
        db = FindReportStub(report=None)
        with pytest.raises(HTTPException) as exc:
            admin_routes._damage_report_for_store(db, STORE_ID, REPORT_ID)
        assert exc.value.status_code == 404

    def test_laporan_yang_cocok_dikembalikan(self, dry):
        db = FindReportStub(report=StubReport())
        found = admin_routes._damage_report_for_store(db, STORE_ID, REPORT_ID)
        assert found.id == REPORT_ID

    def test_approve_memakai_aksi_audit_admin(self, monkeypatch):
        seen = {}

        def fake_approve(db, report, actor, *, audit_action, request):
            seen["audit_action"] = audit_action
            return report

        monkeypatch.setattr(admin_routes, "approve_core", fake_approve)
        monkeypatch.setattr(admin_routes, "get_store_or_404", lambda db, sid: object())

        db = FindReportStub(report=StubReport())
        call(
            admin_routes.admin_approve_damage_report,
            db,
            store_id=STORE_ID,
            report_id=REPORT_ID,
            request=None,
        )
        assert seen["audit_action"] == "DAMAGE_REPORT_APPROVE_ADMIN"

    def test_reject_memakai_aksi_audit_admin(self, monkeypatch):
        seen = {}

        def fake_reject(db, report, actor, *, reason, audit_action, request):
            seen["audit_action"] = audit_action
            seen["reason"] = reason
            return report

        monkeypatch.setattr(admin_routes, "reject_core", fake_reject)
        monkeypatch.setattr(admin_routes, "get_store_or_404", lambda db, sid: object())

        db = FindReportStub(report=StubReport())
        call(
            admin_routes.admin_reject_damage_report,
            db,
            store_id=STORE_ID,
            report_id=REPORT_ID,
            reason="barang masih layak jual",
            body=StubBody("barang masih layak jual"),
            request=None,
        )
        assert seen["audit_action"] == "DAMAGE_REPORT_REJECT_ADMIN"
        assert seen["reason"] == "barang masih layak jual"

    def test_kegagalan_service_tidak_meninggalkan_sesi_kotor(self, monkeypatch):
        """Exception dari service harus rollback.

        Tanpa rollback, sesi itu masih memegang transaksi yang gagal dan
        permintaan berikutnya di sesi yang sama bisa ikut gagal atau, lebih
        buruk, commit perubahan setengah jadi.
        """

        def boom(db, report, actor, *, audit_action, request):
            raise RuntimeError("stok tidak cukup")

        monkeypatch.setattr(admin_routes, "approve_core", boom)
        monkeypatch.setattr(admin_routes, "get_store_or_404", lambda db, sid: object())

        db = FindReportStub(report=StubReport())
        with pytest.raises(HTTPException) as exc:
            call(
                admin_routes.admin_approve_damage_report,
                db,
                store_id=STORE_ID,
                report_id=REPORT_ID,
                request=None,
            )
        assert exc.value.status_code == 400
        assert db.rolled_back == 1

    @pytest.mark.parametrize("action", ["approve", "reject"])
    def test_tidak_bisa_tanpa_token(self, action):
        client = TestClient(app)
        url = "/api/v1/admin/stores/%s/damage-reports/%s/%s" % (
            STORE_ID,
            REPORT_ID,
            action,
        )
        assert client.post(url, json={"reason": "x" * 20}).status_code == 401


class FindReportStub:
    """Session yang mengembalikan satu laporan atau tidak sama sekali."""

    def __init__(self, report):
        self.report = report
        self.rolled_back = 0

    def query(self, *a, **kw):
        outer = self

        class Q:
            def filter(self, *a, **kw):
                return self

            def first(self):
                return outer.report

        return Q()

    def rollback(self):
        self.rolled_back += 1
