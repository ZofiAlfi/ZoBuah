"""UAT M2: isolasi peran, scoping, dan read-only impersonate.

Fokusnya bukan "endpoint jalan", tapi "endpoint tidak bisa disalahgunakan".
Tiga pagar yang diuji di sini:

  1. User toko tidak bisa menyentuh /api/v1/admin/* sama sekali.
  2. OWNER tidak bisa menyentuh endpoint POS yang scoped per toko.
  3. Token impersonate bisa membaca satu toko, tidak bisa menulis, dan tidak
     bisa membaca toko lain.

Semua assertion sengaja memakai status code, bukan isi body, supaya test ini
tidak ikut lulus kalau format response berubah.
"""
import os
import sys
from datetime import datetime, timedelta
from urllib.parse import urlparse
from uuid import uuid4

from dotenv import load_dotenv

# Path diturunkan dari letak file ini, bukan ditulis absolute, supaya folder
# project bisa dipindah atau di-clone di mana saja tanpa suntingan.
BACKEND = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "backend")
)
sys.path.insert(0, BACKEND)

# override=False, bukan True. .env di repo menunjuk ke produksi, dan
# override=True akan menimpa DATABASE_URL yang sudah disetel jadi lokal --
# persis jebakan yang dulu membuat create_all() mencoba DDL ke produksi.
# Env yang sudah ada di shell selalu menang atas isi .env.
load_dotenv(os.path.join(BACKEND, ".env"), override=False)

# Host harus dicocokkan sebagai hostname utuh. Cek substring pernah membiarkan
# "db-localhost.contoh" lewat karena memuat kata "localhost" di dalamnya, dan
# skrip ini tugasnya justru melindungi produksi.
LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1", "[::1]"}
_url = os.environ.get("DATABASE_URL", "")
_host = (urlparse(_url).hostname or "").strip()
if _host not in LOCAL_HOSTS:
    print("GAGAL: DATABASE_URL bukan host lokal. UAT ini tidak boleh jalan ke produksi.")
    print(f"       host terbaca: {_host!r}")
    print(f"       yang terbaca: {_url[:60]}")
    sys.exit(2)
print(f"UAT memakai: {_url}")

os.environ.setdefault("OWNER_PASSWORD", "owner-secret-123")
os.environ["STORAGE"] = "local"

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.database import SessionLocal, engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models.store import Store  # noqa: E402
from app.models.user import User, UserRole  # noqa: E402
from app.security import hash_password  # noqa: E402

PASS, FAIL = [], []


def check(name, condition, detail=""):
    if condition:
        PASS.append(name)
        print(f"  LULUS  {name}")
    else:
        FAIL.append((name, detail))
        print(f"  GAGAL  {name}  {detail}")


def reset_db():
    with engine.begin() as conn:
        conn.execute(text("DROP SCHEMA public CASCADE"))
        conn.execute(text("CREATE SCHEMA public"))
    from app.database import Base

    import app.models  # noqa: F401

    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        owner = User(
            username="owner",
            password_hash=hash_password(os.environ["OWNER_PASSWORD"]),
            full_name="Pemilik Layanan",
            role=UserRole.OWNER.value,
            is_active=True,
            store_id=None,
        )
        db.add(owner)
        db.commit()

        stores = []
        for code, name in (("T01", "Toko Buah Satu"), ("T02", "Toko Buah Dua")):
            s = Store(
                code=code,
                name=name,
                owner_name=f"Pemilik {code}",
                phone="0800",
                plan="PRO",
                plan_expires_at=(datetime.utcnow() + timedelta(days=60)).date(),
                status="ACTIVE",
                is_active=True,
            )
            db.add(s)
            db.commit()
            db.refresh(s)
            db.add(
                User(
                    username=f"bos{code.lower()}",
                    password_hash=hash_password("bos-secret-123"),
                    full_name=f"BOS {code}",
                    role=UserRole.BOS.value,
                    is_active=True,
                    store_id=s.id,
                )
            )
            db.add(
                User(
                    username=f"kar{code.lower()}",
                    password_hash=hash_password("kar-secret-123"),
                    full_name=f"Karyawan {code}",
                    role=UserRole.KARYAWAN.value,
                    is_active=True,
                    store_id=s.id,
                )
            )
            db.commit()
            stores.append(s)
        return stores
    finally:
        db.close()


def _seed_sales(*stores):
    """Isi transaksi nyata per toko.

    Wajib ada. Endpoint agregat yang salah (mis. baris tiga kolom diempar ke
    dict()) TIDAK akan salah kalau tabelnya kosong, karena perulangan tidak
    pernah jalan. Bug seperti itu baru muncul begitu ada baris sungguhan --
    itulah yang terjadi saat UAT pertama masih 41/41 hijau tapi /admin/stores
    langsung crash begitu UAT diisi 332 transaksi.
    """
    from app.models.category import Category
    from app.models.product import Product
    from app.models.sale import Sale, SaleItem
    from datetime import timedelta

    db = SessionLocal()
    try:
        total = 0
        for idx, store in enumerate(stores):
            products = (
                db.query(Product)
                .filter(Product.store_id == store.id)
                .order_by(Product.name)
                .limit(3)
                .all()
            )
            if not products:
                cat = Category(name="Buah Uji", store_id=store.id)
                db.add(cat)
                db.commit()
                db.refresh(cat)
                products = [
                    Product(
                        name=f"Buah Uji {i}",
                        category_id=cat.id,
                        unit="kg",
                        modal_price=10000,
                        selling_price=15000,
                        stock=50,
                        min_stock=5,
                        is_active=True,
                        store_id=store.id,
                    )
                    for i in (1, 2, 3)
                ]
                db.add_all(products)
                db.commit()

            kar = (
                db.query(User)
                .filter(User.store_id == store.id, User.role == "KARYAWAN")
                .first()
            )
            bos = (
                db.query(User)
                .filter(User.store_id == store.id, User.role == "BOS")
                .first()
            )
            actor = kar or bos

            for day in range(10):
                when = datetime.utcnow() - timedelta(days=day)
                for n in range(1, 4):
                    prod = products[n % len(products)]
                    amount = 15000 * n
                    sale = Sale(
                        transaction_number=f"TRX-{store.code}-{day:02d}-{n:02d}",
                        employee_id=actor.id,
                        total_amount=amount,
                        total_modal=10000 * n,
                        total_profit=5000 * n,
                        discount=0,
                        status="COMPLETED",
                        store_id=store.id,
                        created_at=when,
                    )
                    db.add(sale)
                    db.commit()
                    db.refresh(sale)
                    db.add(
                        SaleItem(
                            sale_id=sale.id,
                            product_id=prod.id,
                            product_name=prod.name,
                            unit="kg",
                            unit_price=15000 * n,
                            modal_price=10000 * n,
                            quantity=n,
                            subtotal=amount,
                        )
                    )
                    db.commit()
                    total += 1
        print(f"  (transaksi UAT: {total} baris di {len(stores)} toko)")
        return total
    finally:
        db.close()


def main():
    print("=" * 72)
    print("UAT M2 - ISOLASI ADMIN OWNER CONSOLE")
    print("=" * 72)

    reset_db()
    client = TestClient(app)

    s1, s2 = SessionLocal().query(Store).order_by(Store.code).all()[0:2]
    _seed_sales(s1, s2)

    # --- login admin ---------------------------------------------------
    r = client.post(
        "/api/v1/admin/auth/login",
        json={"username": "owner", "password": os.environ["OWNER_PASSWORD"]},
    )
    check("OWNER bisa login ke admin", r.status_code == 200, f"status={r.status_code} {r.text[:200]}")
    owner_token = r.json()["access_token"] if r.status_code == 200 else None
    oh = {"Authorization": f"Bearer {owner_token}"} if owner_token else {}

    r = client.get("/api/v1/admin/auth/me", headers=oh)
    check("GET /admin/auth/me jalan untuk OWNER", r.status_code == 200, f"status={r.status_code}")

    # --- pagar 1: user toko tidak boleh masuk admin --------------------
    r = client.post(
        "/api/v1/admin/auth/login",
        json={"username": "bost01", "password": "bos-secret-123"},
    )
    check("BOS ditolak di login admin", r.status_code == 403, f"status={r.status_code}")

    r = client.post(
        "/api/v1/auth/login",
        json={"username": "owner", "password": os.environ["OWNER_PASSWORD"]},
    )
    check("OWNER ditolak di login POS", r.status_code == 403, f"status={r.status_code}")

    r = client.post(
        "/api/v1/auth/login",
        json={"username": "bost01", "password": "bos-secret-123"},
    )
    bos_token = r.json()["access_token"] if r.status_code == 200 else None
    bh = {"Authorization": f"Bearer {bos_token}"} if bos_token else {}
    check("BOS bisa login POS", r.status_code == 200, f"status={r.status_code}")

    # Setiap endpoint admin harus menolak token toko. Ini disalin dari daftar
    # route nyata supaya route baru yang lupa dites akan terlihat di sini.
    admin_gets = [
        "/api/v1/admin/dashboard",
        "/api/v1/admin/metrics/overview",
        "/api/v1/admin/metrics/revenue",
        "/api/v1/admin/metrics/top-stores",
        "/api/v1/admin/metrics/plans",
        "/api/v1/admin/metrics/usage",
        "/api/v1/admin/alerts",
        "/api/v1/admin/stores",
        "/api/v1/admin/stores/health",
        f"/api/v1/admin/stores/{s1.id}",
        f"/api/v1/admin/stores/{s1.id}/users",
        "/api/v1/admin/users",
        "/api/v1/admin/broadcasts",
        "/api/v1/admin/audit-logs",
    ]
    leaked = []
    for path in admin_gets:
        rr = client.get(path, headers=bh)
        if rr.status_code not in (401, 403):
            leaked.append(f"{path}->{rr.status_code}")
    check("BOS ditolak di semua 14 endpoint admin", not leaked, f"bocor: {leaked}")

    r = client.post("/api/v1/admin/stores", headers=bh, json={})
    check("BOS tidak bisa buat toko", r.status_code in (401, 403), f"status={r.status_code}")

    # --- pagar 2: OWNER tidak boleh memakai endpoint POS ----------------
    # Path dan method diambil dari daftar route POS yang nyata, bukan karangan,
    # supaya test ini tidak diam-diam lulus karena 404 atau 405.
    pos_leak = []
    for method, path in (
        ("GET", "/api/v1/sales"),
        ("GET", "/api/v1/products"),
        ("GET", "/api/v1/auth/users"),
        ("GET", "/api/v1/reports/dashboard"),
        ("GET", "/api/v1/reports/monthly"),
        ("GET", "/api/v1/damage-reports"),
        ("GET", "/api/v1/audit/logs"),
        ("POST", "/api/v1/sync/pull"),
    ):
        rr = client.request(method, path, headers=oh, json={"device_id": "probe"})
        if rr.status_code != 403:
            pos_leak.append(f"{method} {path}->{rr.status_code}")
    check("OWNER ditolak di 8 endpoint POS scoped", not pos_leak, f"bocor: {pos_leak}")

    # --- dashboard & metrics -------------------------------------------
    r = client.get("/api/v1/admin/dashboard", headers=oh)
    ok = r.status_code == 200
    check("GET /admin/dashboard jalan", ok, f"status={r.status_code} {r.text[:300]}")
    if ok:
        d = r.json()
        for key in ("overview", "revenue_30d", "top_stores", "plans", "alerts"):
            check(f"dashboard berisi '{key}'", key in d)
        check("revenue_30d punya 30 titik", len(d["revenue_30d"]) == 30, f"n={len(d['revenue_30d'])}")
        check("overview menghitung 2 toko", d["overview"]["total_stores"] == 2, str(d["overview"]))

        # Tren harus benar-benar berisi angka, bukan 30 titik nol. Bug kunci
        # date-vs-string pernah membuat seluruh grafik kosong padahal ada
        # ratusan transaksi.
        series_total = sum(p["revenue"] for p in d["revenue_30d"])
        filled = sum(1 for p in d["revenue_30d"] if p["transactions"] > 0)
        check("tren revenue berisi angka", series_total > 0, f"total={series_total}")
        check("tren punya hari berisi transaksi", filled > 0, f"terisi={filled}/30")
        check(
            "tren cocok dengan overview",
            abs(series_total - d["overview"]["revenue_30d"]) < 1,
            f"tren={series_total} overview={d['overview']['revenue_30d']}",
        )

    # --- endpoint agregat dengan data nyata --------------------------------
    r = client.get("/api/v1/admin/stores", headers=oh)
    check("GET /admin/stores jalan saat ada transaksi", r.status_code == 200, f"status={r.status_code} {r.text[:250]}")
    if r.status_code == 200:
        with_sales = [i for i in r.json()["items"] if i["sale_count_30d"] > 0]
        check("daftar toko melaporkan jumlah transaksi", len(with_sales) >= 2, f"toko dg transaksi={len(with_sales)}")
        check("revenue per toko > 0", all(i["revenue_30d"] > 0 for i in with_sales), str([(i["code"], i["revenue_30d"]) for i in with_sales]))

    r = client.get("/api/v1/admin/metrics/usage", headers=oh)
    check("GET /admin/metrics/usage jalan", r.status_code == 200, f"status={r.status_code} {r.text[:250]}")
    if r.status_code == 200:
        check("usage melaporkan transaksi per toko", all(u["sale_count_30d"] > 0 for u in r.json()), str(r.json()[:1]))

    r = client.get("/api/v1/admin/metrics/top-stores", headers=oh)
    check("GET /admin/metrics/top-stores jalan", r.status_code == 200, f"status={r.status_code}")
    if r.status_code == 200:
        tops = r.json()
        check("top stores punya omzet", tops and tops[0]["revenue"] > 0, str(tops[:1]))
        check("top stores terurut menurun", all(tops[i]["revenue"] >= tops[i + 1]["revenue"] for i in range(len(tops) - 1)))

    r = client.get("/api/v1/admin/metrics/plans", headers=oh)
    if r.status_code == 200:
        check("paket punya omzet terhitung", sum(p["revenue_30d"] for p in r.json()) > 0, str(r.json()))

    r = client.get(f"/api/v1/admin/metrics/revenue?days=30&store_id={s1.id}", headers=oh)
    check("tren per-toko jalan", r.status_code == 200, f"status={r.status_code}")
    if r.status_code == 200:
        per = r.json()
        check("tren per-toko hanya berisi toko itu", sum(p["transactions"] for p in per) > 0, f"n={sum(p['transactions'] for p in per)}")

    # --- onboarding atomik ---------------------------------------------
    before = SessionLocal().query(Store).count()
    r = client.post(
        "/api/v1/admin/stores",
        headers=oh,
        json={
            "code": "t03",
            "name": "Toko Rollback",
            "owner_name": "Pemilik T03",
            "bos_username": "bost03",
            "bos_password": "bos-secret-123",
            "bos_full_name": "BOS T03",
            "category_names": ["Buah Naga", "Buah Naga"],
        },
    )
    check("POST /admin/stores membuat toko", r.status_code == 201, f"status={r.status_code} {r.text[:300]}")
    if r.status_code == 201:
        body = r.json()
        check("kode toko dinormalisasi jadi huruf besar", body["code"] == "T03", body["code"])
        check("kategori duplikat dibuang", r.status_code == 201)

    r = client.post(
        "/api/v1/admin/stores",
        headers=oh,
        json={
            "code": "T04",
            "name": "Toko Gagal",
            "owner_name": "Pemilik T04",
            "bos_username": "bost01",
            "bos_password": "bos-secret-123",
            "bos_full_name": "BOS T04",
        },
    )
    after = SessionLocal().query(Store).count()
    check("onboarding gagal saat username bentrok", r.status_code == 400, f"status={r.status_code} {r.text[:200]}")
    check("tidak ada toko yatim setelah onboarding gagal", after == before + 1, f"sebelum={before} sesudah={after}")

    r = client.post(
        "/api/v1/admin/stores",
        headers=oh,
        json={
            "code": "T05",
            "name": "X",
            "owner_name": "P",
            "bos_username": "bost05",
            "bos_password": "pendek",
            "bos_full_name": "B",
        },
    )
    check("sandi terlalu pendek ditolak", r.status_code == 422, f"status={r.status_code}")

    # --- last BOS guard -------------------------------------------------
    bos_id = (
        SessionLocal().query(User).filter(User.username == "bost01").first().id
    )
    r = client.patch(f"/api/v1/admin/users/{bos_id}", headers=oh, json={"role": "KARYAWAN"})
    check("BOS terakhir tidak bisa diturunkan jadi KARYAWAN", r.status_code == 400, f"status={r.status_code}")

    r = client.patch(f"/api/v1/admin/users/{bos_id}", headers=oh, json={"is_active": False})
    check("BOS terakhir tidak bisa dinonaktifkan", r.status_code == 400, f"status={r.status_code}")

    # --- force logout benar-benar mematikan token ------------------------
    r = client.get("/api/v1/products", headers=bh)
    check("token BOS valid sebelum force-logout", r.status_code == 200, f"status={r.status_code}")
    r = client.post(f"/api/v1/admin/users/{bos_id}/force-logout", headers=oh)
    check("force-logout OWNER jalan", r.status_code == 200, f"status={r.status_code}")
    r = client.get("/api/v1/products", headers=bh)
    check("token BOS mati setelah force-logout", r.status_code == 401, f"status={r.status_code}")

    # --- pagar 3: impersonate hanya baca, satu toko --------------------
    r = client.post(f"/api/v1/admin/stores/{s2.id}/impersonate", headers=oh, json={"store_id": str(s2.id)})
    check("impersonate toko aktif berhasil", r.status_code == 200, f"status={r.status_code} {r.text[:300]}")
    imp_token = r.json()["access_token"] if r.status_code == 200 else None
    ih = {"Authorization": f"Bearer {imp_token}"} if imp_token else {}

    r = client.get("/api/v1/products", headers=ih)
    check("impersonate boleh baca POS (GET)", r.status_code == 200, f"status={r.status_code}")

    writes = [
        ("POST", "/api/v1/sales", {}),
        ("PATCH", f"/api/v1/admin/stores/{s2.id}", {"name": "Diretas"}),
        ("DELETE", f"/api/v1/admin/broadcasts/{uuid4()}", None),
        ("POST", f"/api/v1/admin/stores/{s2.id}/users", {"username": "x", "password": "abcdefgh", "full_name": "X"}),
    ]
    not_blocked = []
    for method, path, payload in writes:
        rr = client.request(method, path, headers=ih, json=payload)
        if rr.status_code != 403:
            not_blocked.append(f"{method} {path}->{rr.status_code}")
    check("impersonate diblokir di semua 4 metode tulis", not not_blocked, f"tidak diblokir: {not_blocked}")

    r = client.post(f"/api/v1/admin/stores/{s2.id}/users", headers=ih, json={"username": "x", "password": "abcdefgh", "full_name": "X"})
    check("impersonate ditolak buat user toko", r.status_code == 403, f"status={r.status_code}")

    r = client.get("/api/v1/admin/dashboard", headers=ih)
    check("impersonate ditolak di endpoint admin", r.status_code == 403, f"status={r.status_code}")

    # --- broadcast validation -------------------------------------------
    r = client.post(
        "/api/v1/admin/broadcasts",
        headers=oh,
        json={"title": "Uji", "body": "Isi", "level": "INFO", "target": "STORE"},
    )
    check("broadcast target=STORE tanpa store_id ditolak", r.status_code == 400, f"status={r.status_code}")

    r = client.post(
        "/api/v1/admin/broadcasts",
        headers=oh,
        json={"title": "Uji", "body": "Isi", "level": "INFO", "target": "ALL", "store_id": str(s1.id)},
    )
    check("broadcast target=ALL dengan store_id ditolak", r.status_code == 400, f"status={r.status_code}")

    r = client.post(
        "/api/v1/admin/broadcasts",
        headers=oh,
        json={"title": "Maintenance", "body": "ServerFRA jam 12", "level": "MAINTENANCE", "target": "ALL"},
    )
    check("broadcast global berhasil dibuat", r.status_code == 201, f"status={r.status_code} {r.text[:200]}")
    if r.status_code == 201:
        bid = r.json()["id"]
        r = client.delete(f"/api/v1/admin/broadcasts/{bid}", headers=oh)
        check("broadcast dinonaktifkan, bukan dihapus", r.status_code == 200, f"status={r.status_code}")
        r = client.get(f"/api/v1/admin/broadcasts", headers=oh)
        found = [b for b in r.json()["items"] if b["id"] == bid]
        check("broadcast nonaktif masih ada di daftar", len(found) == 1 and found[0]["is_active"] is False)

    # --- CORS ------------------------------------------------------------
    r = client.options(
        "/api/v1/admin/dashboard",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "GET",
        },
    )
    has_origin = "http://localhost:5173" in (r.headers.get("access-control-allow-origin") or "")
    check("CORS mengizinkan origin Owner Console (5173)", has_origin, f" ACAO={r.headers.get('access-control-allow-origin')}")

    r = client.options(
        "/api/v1/admin/dashboard",
        headers={
            "Origin": "http://localhost:8080",
            "Access-Control-Request-Method": "GET",
        },
    )
    has_pos = "http://localhost:8080" in (r.headers.get("access-control-allow-origin") or "")
    check("CORS tetap mengizinkan origin POS (8080)", has_pos, f" ACAO={r.headers.get('access-control-allow-origin')}")

    # --- /health ---------------------------------------------------------
    r = client.get("/health")
    mt = r.json().get("multitenant", {})
    check("/health melaporkan multitenant siap", mt.get("tables_ready") is True, str(mt))
    check("/health melaporkan 0 baris tanpa store_id", mt.get("orphan_rows") == 0, str(mt))

    print("=" * 72)
    print(f"LULUS {len(PASS)}   GAGAL {len(FAIL)}")
    if FAIL:
        print("-" * 72)
        for name, detail in FAIL:
            print(f"  GAGAL  {name}  {detail}")
    print("=" * 72)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
