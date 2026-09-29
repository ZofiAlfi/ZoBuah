from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from pathlib import Path
import mimetypes
import re
import time

from .config import settings
from .database import Base, engine, SessionLocal
from .utilities.helpers import iso_utc
from .services.storage import storage
from .routes import (
    auth,
    product,
    sale,
    stock,
    damage_report,
    sync,
    report,
    audit,
    admin,
    admin_auth,
)


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Fruit POS API - Manajemen toko buah online/offline",
)

# Origin POS dan Origin Owner Console digabung dalam satu daftar karena
# keduanya dilayani API yang sama. Kalau dipisah, dashboard owner yang
# dibangun tanpa proxy Vite akan gagal preflight padahal owner sudah
# didaftarkan di ADMIN_ORIGINS.
_CORS_ORIGINS = sorted(
    set(settings.ALLOWED_ORIGINS) | set(settings.ADMIN_ORIGINS),
    key=lambda o: o.strip(),
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def impersonation_write_guard(request: Request, call_next):
    """Blokir semua metode tulis untuk token impersonate OWNER.

    Token impersonate memakai identitas BOS toko dan sengaja dibuat supaya
    owner bisa melihat apa yang dilihat kasir. Kalau penolakan tulis diletakkan
    di tiap route, satu route yang lupa akan menjadi jalur mengubah data
    pelanggan tanpa jejak. Di middleware, kelengkapan dijamin karena hanya
    ada satu titik yang perlu dijaga.

    GET, HEAD, dan OPTIONS diteruskan supaya dashboard bisa memuat halaman dan
    browser tetap bisa melakukan preflight CORS.
    """
    if request.method not in ("GET", "HEAD", "OPTIONS"):
        header = request.headers.get("authorization", "")
        if header.lower().startswith("bearer "):
            from .security import decode_token, is_impersonation_token

            payload = decode_token(header[7:].strip())
            if is_impersonation_token(payload):
                return JSONResponse(
                    status_code=403,
                    content={
                        "detail": "Token tinjauan bersifat baca-saja dan tidak bisa mengubah data."
                    },
                )
    return await call_next(request)


@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    response.headers["X-Process-Time"] = str(process_time)
    return response


@app.on_event("startup")
def on_startup():
    if settings.STORAGE != "s3":
        upload_dir = Path(settings.UPLOAD_DIR)
        (upload_dir / "damage").mkdir(parents=True, exist_ok=True)
        (upload_dir / "product").mkdir(parents=True, exist_ok=True)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={"detail": f"Internal server error: {str(exc)}"},
    )


@app.get("/")
def root():
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "ok",
    }


def _payment_photo_columns_exist() -> bool:
    """True bila kolom file_path & file_url sudah ada di tabel payments."""
    from sqlalchemy import text

    try:
        with engine.connect() as conn:
            count = conn.execute(
                text(
                    "SELECT count(*) FROM information_schema.columns "
                    "WHERE table_name='payments' AND column_name IN ('file_path','file_url')"
                )
            ).scalar()
            return count == 2
    except Exception:
        return False


# Tabel yang seluruh barisnya pasti milik satu toko, jadi store_id NULL berarti
# data yatim yang harus dipindahkan. Satu daftar untuk /health dan
# _unscoped_row_count(); menambah tabel baru cukup di satu tempat.
#
# users tidak masuk daftar: akun OWNER memang lintas-toko. audit_logs juga
# tidak: aksi owner lintas-toko (ADMIN_LOGIN, STORE_CREATE, BROADCAST_*,
# IMPERSONATE_START) dicatat dengan store_id NULL secara sah.
TENANT_SCOPED_TABLES = (
    "categories",
    "products",
    "sales",
    "stock_movements",
    "damage_reports",
    "devices",
    "sync_events",
)


def _multitenant_ready() -> dict:
    """Ringkasan kesiapan multi-tenant untuk /health.

    Dipakai sebagai pemeriksaan cepat sebelum deploy: kalau tabel tenant belum
    ada atau masih ada baris tanpa store_id, dashboard owner akan menampilkan
    angka yang salah tanpa error yang mencolok.
    """
    from sqlalchemy import text

    out = {"tables_ready": False, "orphan_rows": None, "stores": None}
    try:
        with engine.connect() as conn:
            # Semua tabel yang nanti dipakai di bawah harus ikut diambil. Kalau
            # tidak, `if table in present` diam-diam melewati tabel yang belum
            # ada, dan orphan_rows dilaporkan lebih kecil dari kenyataannya.
            present = set(
                conn.execute(
                    text(
                        "SELECT table_name FROM information_schema.tables "
                        "WHERE table_schema='public' AND table_name IN "
                        "('stores','broadcasts','users',"
                        + ",".join(f"'{t}'" for t in TENANT_SCOPED_TABLES)
                        + ")"
                    )
                ).scalars()
            )
            if not {"stores", "users"}.issubset(present):
                return out

            out["tables_ready"] = True
            out["stores"] = conn.execute(text("SELECT count(*) FROM stores")).scalar()

            # Tabel data toko (store_id NOT NULL) tidak boleh punya baris null
            # setelah migrasi 003. Pengecualian wajib untuk users: akun OWNER
            # memang sengaja tanpa toko, jadi menghitungnya sebagai baris yatim
            # akan selalu melaporkan sistem tidak sehat.
            orphans = 0
            for table in TENANT_SCOPED_TABLES:
                if table in present:
                    orphans += (
                        conn.execute(
                            text(f"SELECT count(*) FROM {table} WHERE store_id IS NULL")  # noqa: S608
                        ).scalar()
                        or 0
                    )
            if "users" in present:
                orphans += (
                    conn.execute(
                        text(
                            "SELECT count(*) FROM users "
                            "WHERE store_id IS NULL AND role <> 'OWNER'"
                        )
                    ).scalar()
                    or 0
                )
            out["orphan_rows"] = orphans
    except Exception as exc:  # health tidak boleh ikut gagal karena audit
        out["error"] = str(exc)
    return out


@app.get("/health")
def health():
    return {
        "status": "ok",
        "time": iso_utc(__import__("datetime").datetime.utcnow()),
        "payment_photo_columns": _payment_photo_columns_exist(),
        "multitenant": _multitenant_ready(),
    }


app.include_router(auth.router, prefix="/api/v1")
app.include_router(product.router, prefix="/api/v1")
app.include_router(sale.router, prefix="/api/v1")
app.include_router(stock.router, prefix="/api/v1")
app.include_router(damage_report.router, prefix="/api/v1")
app.include_router(sync.router, prefix="/api/v1")
app.include_router(report.router, prefix="/api/v1")
app.include_router(audit.router, prefix="/api/v1")
app.include_router(admin_auth.router, prefix="/api/v1")
app.include_router(admin.router, prefix="/api/v1")

if settings.STORAGE != "s3" and Path(settings.UPLOAD_DIR).exists():
    app.mount("/uploads", StaticFiles(directory=settings.UPLOAD_DIR), name="uploads")
else:

    @app.get("/uploads/{key:path}")
    def uploads_proxy(key: str):
        """Mode s3: stream file dari Backblaze B2 (bucket tidak perlu publik)."""
        try:
            data = storage.read_bytes(key)
        except FileNotFoundError:
            raise HTTPException(status_code=404, detail="File tidak ditemukan")
        media_type = mimetypes.guess_type(key)[0] or "application/octet-stream"
        return Response(content=data, media_type=media_type)


def _migrate_payment_photo_columns():
    """Idempoten: tambah kolom foto bukti pembayaran di tabel payments existing.

    Dijalankan per-pernyataan dalam mode AUTOCOMMIT agar kompatibel dengan
    koneksi pooling Supabase (pgbouncer) yang sering menolak DDL di dalam
    transaksi multi-statement eksplisit.
    """
    from sqlalchemy import text

    for stmt in (
        "ALTER TABLE payments ADD COLUMN IF NOT EXISTS file_path VARCHAR(255)",
        "ALTER TABLE payments ADD COLUMN IF NOT EXISTS file_url VARCHAR(500)",
    ):
        try:
            with engine.connect().execution_options(isolation_level="AUTOCOMMIT") as conn:
                conn.execute(text(stmt))
        except Exception as exc:
            print(f"[startup] GAGAL migrasi kolom foto pembayaran ({stmt[:40]}...): {exc!r}", flush=True)
    ok = _payment_photo_columns_exist()
    print(f"[startup] migrasi kolom foto pembayaran: ok={ok}", flush=True)


# Host yang dianggap "lokal" untuk tujuan gerbang DDL.
_LOCAL_DB_HOSTS = {"", "localhost", "127.0.0.1", "::1", "0.0.0.0", "test", "postgres"}


def _database_host() -> str:
    from urllib.parse import urlparse

    try:
        return (urlparse(settings.DATABASE_URL).hostname or "").lower()
    except Exception:
        return ""


def _ddl_allowed() -> bool:
    """Boleh mengubah skema ke database ini?

    Hanya lokal, atau remote yang ALLOW_REMOTE_DDL=1 disetel eksplisit.
    Ini mencegah create_all() dan migration runner ikut menyentuh produksi
    karena mis. script UAT salah urutan import, atau ada service yang start
    dengan .env produksi tanpa sengaja menjalankan migrasi.
    """
    if _database_host() in _LOCAL_DB_HOSTS:
        return True
    return settings.ALLOW_REMOTE_DDL.strip().lower() in {"1", "true", "yes", "on"}


def create_tables():
    if not _ddl_allowed():
        print(
            f"[startup] DITOLAK: tidak mengubah skema database remote "
            f"'{_database_host()}'. Set ALLOW_REMOTE_DDL=1 bila memang "
            f"ingin menerapkan migrasi ke sana.",
            flush=True,
        )
        return

    Base.metadata.create_all(bind=engine)
    _migrate_payment_photo_columns()
    _run_migrations()


# Tag dollar-quote PostgreSQL: $$ atau $nama$.
_DOLLAR_TAG = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$")


def _split_sql_statements(raw):
    """Pecah SQL jadi daftar pernyataan lengkap.

    Pemecah naif yang memotong per baris berakhiri ';' akan menghancurkan
    blok DO $$ ... $$ jadi potongan tidak valid, sehingga migrasi ber-DO-block
    selalu gagal diam-diam. Parser ini menghormati:

    - dollar-quote ($$ dan $tag$) yang isinya boleh berisi ';' sesuka hati
    - string '...' dengan escape '' (doubled quote)
    - komentar -- satu baris dan /* blok */ yang boleh bersarang
    """
    statements = []
    buf = []
    i = 0
    n = len(raw)
    dollar_tag = None
    block_depth = 0

    while i < n:
        ch = raw[i]

        if dollar_tag is not None:
            if raw.startswith(dollar_tag, i):
                buf.append(dollar_tag)
                i += len(dollar_tag)
                dollar_tag = None
            else:
                buf.append(ch)
                i += 1
            continue

        if block_depth > 0:
            if raw.startswith("/*", i):
                block_depth += 1
                i += 2
            elif raw.startswith("*/", i):
                block_depth -= 1
                i += 2
            else:
                if ch == "\n":
                    buf.append(ch)
                i += 1
            continue

        if raw.startswith("--", i):
            newline = raw.find("\n", i)
            if newline < 0:
                break
            i = newline
            continue

        if raw.startswith("/*", i):
            block_depth = 1
            i += 2
            continue

        if ch == "'":
            buf.append(ch)
            i += 1
            while i < n:
                if raw[i] == "'":
                    if i + 1 < n and raw[i + 1] == "'":
                        buf.append("''")
                        i += 2
                        continue
                    buf.append("'")
                    i += 1
                    break
                buf.append(raw[i])
                i += 1
            continue

        if ch == "$":
            match = _DOLLAR_TAG.match(raw, i)
            if match:
                dollar_tag = match.group(0)
                buf.append(dollar_tag)
                i += len(dollar_tag)
                continue

        if ch == ";":
            stmt = "".join(buf).strip()
            if stmt:
                statements.append(stmt)
            buf = []
            i += 1
            continue

        buf.append(ch)
        i += 1

    tail = "".join(buf).strip()
    if tail:
        statements.append(tail)
    return statements


def _run_ddl_statements(statements, label):
    """Jalankan DDL satu per pernyataan dalam mode AUTOCOMMIT.

    Kompatibel dengan koneksi pooling Supabase (pgbouncer) yang menolak DDL
    di dalam transaksi multi-statement eksplisit. Kegagalan per pernyataan
    dicetak, tidak menghentikan startup.
    """
    from sqlalchemy import text

    failures = []
    for stmt in statements:
        try:
            with engine.connect().execution_options(isolation_level="AUTOCOMMIT") as conn:
                conn.execute(text(stmt))
        except Exception as exc:
            failures.append((stmt, exc))
            print(f"[startup] GAGAL {label} ({stmt[:60]}...): {exc!r}", flush=True)
    if not failures:
        print(f"[startup] {label}: {len(statements)} pernyataan OK", flush=True)
    return failures


def _multitenant_tables_exist() -> bool:
    """True bila seluruh schema multi-tenant sudah terpasang.

    Catatan: jangan hanya cek tabel + users.store_id. Kalau migrasi pernah
    gagal di tengah (misal proses mati setelah tabel dibuat), token_version
    bisa hilang sementara syarat di atas tetap terpenuhi -> migrasi dilewati
    selamanya dan app jalan dengan kolom yang tidak ada.
    """
    from sqlalchemy import text

    try:
        with engine.connect() as conn:
            tables = conn.execute(
                text(
                    "SELECT count(*) FROM information_schema.tables "
                    "WHERE table_schema = current_schema() "
                    "AND table_name IN ('stores','broadcasts')"
                )
            ).scalar()
            columns = conn.execute(
                text(
                    "SELECT count(*) FROM information_schema.columns "
                    "WHERE table_schema = current_schema() "
                    "AND (table_name = 'users' AND column_name IN ('store_id','token_version') "
                    "OR table_name = 'broadcasts' AND column_name = 'store_id')"
                )
            ).scalar()
            return tables == 2 and columns == 3
    except Exception:
        return False


def _unscoped_row_count() -> int:
    """Jumlah baris tenant yang masih punya store_id NULL.

    Memakai TENANT_SCOPED_TABLES yang sama dengan /health, supaya kedua
    pemeriksaan tidak bisa punya definisi yang berbeda.

    users tidak dihitung karena akun OWNER memang lintas-toko, dan
    audit_logs tidak dihitung karena aksi owner seperti ADMIN_LOGIN,
    STORE_CREATE, BROADCAST_* dan IMPERSONATE_START memang dicatat dengan
    store_id NULL.

    audit_logs sempat ikut di daftar ini dan itu keliru. Setiap login owner
    memenuhi syarat, sehingga _ensure_legacy_store selalu membuat toko
    "Toko Legacy" di instalasi baru yang datanya bersih.
    """
    from sqlalchemy import text

    try:
        with engine.connect() as conn:
            total = 0
            for table in TENANT_SCOPED_TABLES:
                total += conn.execute(
                    text(f"SELECT count(*) FROM {table} WHERE store_id IS NULL")
                ).scalar() or 0
            return total
    except Exception:
        return -1


def _schema_drift_fixed() -> bool:
    """True bila kolom yang tadinya tertinggal di init.sql sudah ada."""
    from sqlalchemy import text

    try:
        with engine.connect() as conn:
            n = conn.execute(
                text(
                    "SELECT count(*) FROM information_schema.columns "
                    "WHERE table_schema = current_schema() AND ("
                    "(table_name = 'products' AND column_name = 'photo_path') OR "
                    "(table_name = 'damage_reports' AND column_name = 'qty_in_base_unit')"
                    ")"
                )
            ).scalar()
            return n == 2
    except Exception:
        return False


def _sales_txn_number_per_store() -> bool:
    """True bila nomor transaksi sudah unik per toko.

    Syaratnya dua: unique komposit (store_id, transaction_number) terpasang,
    DAN tidak ada lagi unique global di kolom transaction_number.

    Predicate unique global WAJIB menyebut transaction_number. Kalau hanya
    "UNIQUE dan tidak mengandung store_id", sales_pkey ikut terhitung dan
    syaratnya tidak akan pernah terpenuhi -- akibatnya migrasi 005
    dijalankan ulang di setiap startup.
    """
    from sqlalchemy import text

    try:
        with engine.connect() as conn:
            composite = conn.execute(
                text(
                    "SELECT count(*) FROM pg_constraint c "
                    "JOIN pg_class t ON t.oid = c.conrelid "
                    "JOIN pg_namespace n ON n.oid = t.relnamespace "
                    "WHERE c.conname = 'ux_sales_store_transaction_number' "
                    "AND t.relname = 'sales' AND n.nspname = current_schema()"
                )
            ).scalar()
            global_unique = conn.execute(
                text(
                    "SELECT count(*) FROM pg_indexes "
                    "WHERE tablename = 'sales' AND schemaname = current_schema() "
                    "AND indexdef ILIKE '%UNIQUE%' "
                    "AND indexdef ILIKE '%transaction_number%' "
                    "AND indexdef NOT ILIKE '%store_id%'"
                )
            ).scalar()
            return composite == 1 and global_unique == 0
    except Exception:
        return False


def _soft_delete_propagation() -> bool:
    """True bila penghapusan produk/kategori bisa sampai ke perangkat kasir.

    Tiga syarat, dan semuanya harus benar:
    - categories punya kolom is_active
    - products.is_active sudah NOT NULL (kalau masih nullable, NULL di
      database dibaca sebagai aktif oleh klien sehingga produk nonaktif
      masih bisa terjual)
    - index unik parsial ux_products_store_name_active terpasang (satu
      produk aktif per nama per toko, mencegah duplikasi di grid kasir)
    """
    from sqlalchemy import text

    try:
        with engine.connect() as conn:
            cat_column = conn.execute(
                text(
                    "SELECT count(*) FROM information_schema.columns "
                    "WHERE table_schema = current_schema() "
                    "AND table_name = 'categories' AND column_name = 'is_active'"
                )
            ).scalar()
            not_null = conn.execute(
                text(
                    "SELECT is_nullable FROM information_schema.columns "
                    "WHERE table_schema = current_schema() "
                    "AND table_name = 'products' AND column_name = 'is_active'"
                )
            ).scalar()
            partial_index = conn.execute(
                text(
                    "SELECT count(*) FROM pg_indexes "
                    "WHERE tablename = 'products' AND schemaname = current_schema() "
                    "AND indexname = 'ux_products_store_name_active'"
                )
            ).scalar()
            return cat_column == 1 and not_null == "NO" and partial_index == 1
    except Exception:
        return False


# (label, nama file, fungsi prasyarat). Prasyarat True = migrasi dilewati.
# Urutan penting: 004 dan 005 bergantung pada kolom yang dibuat 003.
_MIGRATIONS = (
    ("perbaikan drift skema", "004_fix_schema_drift.sql", "_schema_drift_fixed"),
    ("migrasi multi-tenant", "003_multi_tenant.sql", "_multitenant_tables_exist"),
    ("nomor transaksi per toko", "005_sales_transaction_number_per_store.sql", "_sales_txn_number_per_store"),
    ("penghapusan sampai ke perangkat", "006_soft_delete_propagation.sql", "_soft_delete_propagation"),
)


def _migrations_dir() -> Path:
    """Temukan folder migrations/.

    main.py ada di backend/app/main.py, jadi migrations/ ada di backend/
    -- itu parent.parent, bukan parent.parent.parent. Versi sebelumnya
    memakai parent.parent.parent dan berakhir menunjuk ke folder proyek,
    sehingga TIDAK ADA file migrasi yang pernah terbaca. Kegagalan ini
    tidak terlihat karena prasyarat sering sudah terpenuhi di DB kosong,
    tapi di database lama migrasi penting akan dilewati diam-diam.
    """
    here = Path(__file__).resolve()
    for candidate in (here.parent.parent / "migrations", here.parent / "migrations"):
        if candidate.is_dir():
            return candidate
    return here.parent.parent / "migrations"


def _run_migrations():
    """Jalankan migrasi SQL yang prasyaratnya belum terpenuhi.

    Tabel-driven supaya menambah migrasi cukup satu baris, bukan salin-tempel
    parser. Semua idempoten dan dijalankan per-pernyataan dalam mode AUTOCOMMIT
    (lihat _run_ddl_statements) agar aman lewat koneksi pooling.
    """
    migrations_dir = _migrations_dir()

    for label, filename, precondition_name in _MIGRATIONS:
        precondition = globals().get(precondition_name)
        if precondition is not None and precondition():
            continue

        sql_path = migrations_dir / filename
        try:
            raw = sql_path.read_text(encoding="utf-8")
        except Exception as exc:
            print(f"[startup] GAGAL baca {sql_path.name}: {exc!r}", flush=True)
            continue

        statements = _split_sql_statements(raw)
        print(f"[startup] {label} ({filename}): {len(statements)} pernyataan", flush=True)
        _run_ddl_statements(statements, label)

        applied = precondition() if precondition is not None else True
        print(f"[startup] {label} selesai: terpasang={applied}", flush=True)

        if precondition_name == "_multitenant_tables_exist":
            print(f"[startup] baris tenant tanpa store_id: {_unscoped_row_count()}", flush=True)


@app.on_event("startup")
def create_tables_on_start():
    # Seed juga menulis (membuat store LEGACY-01, akun OWNER/BOS, kategori),
    # jadi ikut digerbang DDL. Produksi tidak boleh ikut ter-seed diam-diam.
    if not _ddl_allowed():
        print("[startup] DITOLAK: seed data dilewati karena database remote.", flush=True)
        return
    create_tables()
    seed_initial_data()


def _ensure_legacy_store(db):
    """Toko pertama untuk seluruh data yang sudah ada sebelum migrasi 003.

    Hanya dibuat bila memang ada baris tanpa store_id yang harus dipindah ke
    suatu toko. Instalasi baru yang masih kosong tidak butuh placeholder: toko
    pertama dibuat lewat onboarding di Owner Console, lengkap dengan akun BOS
    dan kategorinya. Tanpa guard ini, setiap DB lokal yang baru di-seed akan
    dapat satu toko "Toko Legacy" tanpa pengguna, yang muncul juga di dashboard
    Owner dan hanya menambah kebisingan.

    Idempoten. Dipisah dari migrasi SQL supaya aman juga bila tabel hanya
    dibuat oleh Base.metadata.create_all tanpa menjalankan file .sql.
    """
    from .models.store import Store, StoreStatus, Plan

    store = db.query(Store).filter(Store.code == "LEGACY-01").first()
    if store is not None:
        return store

    if _unscoped_row_count() <= 0:
        return None

    store = Store(
        code="LEGACY-01",
        name="Toko Legacy",
        owner_name="Pemilik Toko",
        plan=Plan.TRIAL,
        status=StoreStatus.ACTIVE,
        is_active=True,
    )
    db.add(store)
    db.commit()
    print("[startup] Toko LEGACY-01 dibuat", flush=True)
    return store


def seed_initial_data():
    """Seed akun OWNER global, akun BOS toko pertama, dan kategori dasar.

    Semua baris wajib punya store_id kecuali OWNER (akun lintas-toko).
    Kategori kini unik per toko, jadi pengecekan WAJIB menyertakan store_id.
    """
    from .models.user import User, UserRole
    from .models.category import Category
    from .security import hash_password

    db = SessionLocal()
    try:
        store = _ensure_legacy_store(db)

        # --- Akun OWNER (global, store_id sengaja NULL) ---
        owner = db.query(User).filter(User.role == UserRole.OWNER.value).first()
        if owner is None:
            # Tanpa OWNER_PASSWORD di env, akun dibuat nonaktif supaya tidak
            # ada password default yang bisa dipakai masuk ke seluruh data toko.
            pw = settings.OWNER_PASSWORD
            owner = User(
                username=settings.OWNER_USERNAME,
                full_name=settings.OWNER_FULL_NAME,
                password_hash=hash_password(pw) if pw else "TIDAK-DIATUR",
                role=UserRole.OWNER.value,
                is_active=bool(pw),
                store_id=None,
            )
            db.add(owner)
            db.commit()
            if pw:
                print(f"[startup] Akun OWNER dibuat: username={settings.OWNER_USERNAME}")
            else:
                print(
                    "[startup] Akun OWNER NONAKTIF dibuat. Set OWNER_PASSWORD lalu "
                    "aktifkan manual sebelum pakai owner console."
                )

        # --- Akun BOS toko pertama + kategori bawaan ---
        # Hanya berjalan bila _ensure_legacy_store benar-benar menghasilkan
        # toko. Kalau tidak, tidak ada yang perlu di-bulkir: baik database
        # masih kosong (toko pertama dibuat dari Owner Console), atau sudah
        # punya toko sendiri yang seluruh penggunanya sudah diatur.
        if store is None:
            from sqlalchemy import func as _func

            from .models.store import Store as _Store

            n = db.query(_func.count(_Store.id)).scalar() or 0
            if n == 0:
                print(
                    "[startup] Database kosong, toko pertama belum ada. "
                    "Buat toko pertama dari Owner Console.",
                    flush=True,
                )
            else:
                print(
                    f"[startup] {n} toko sudah ada, akun BOS dan kategori bawaan "
                    "dilewati. Tambah pengguna lewat Owner Console.",
                    flush=True,
                )
            return

        bos = db.query(User).filter(User.role == UserRole.BOS.value).first()
        if bos is None:
            bos = User(
                username="bos",
                full_name="Pemilik Toko",
                password_hash=hash_password("bos12345"),
                role=UserRole.BOS.value,
                is_active=True,
                store_id=store.id,
            )
            db.add(bos)
            db.commit()
            print("[startup] Akun BOS default dibuat: username=bos password=bos12345")
        elif bos.store_id is None:
            # Data lama belum ter-backfill (mis. tabel dibuat tanpa migrasi SQL).
            bos.store_id = store.id
            db.commit()
            print(f"[startup] Akun '{bos.username}' ditugaskan ke toko {store.code}")

        # --- Backfill sisa baris yang masih tanpa store_id ---
        # Dijalankan tiap startup: murah, dan menjamin tidak ada data yatim
        # yang lolos ke seluruh toko karena filter store_id tidak berlaku.
        orphans = 0
        for model in (Category,):
            orphans += (
                db.query(model).filter(model.store_id.is_(None)).update({model.store_id: store.id})
            )
        if orphans:
            db.commit()
            print(f"[startup] Backfill store_id: {orphans} baris orphan -> {store.code}")

        # --- Kategori dasar, unik per toko ---
        for cat_name in ["Apel", "Jeruk", "Mangga", "Pisang", "Semangka", "Alpukat", "Nanas", "Kelapa", "Lainnya"]:
            exists = (
                db.query(Category)
                .filter(Category.name == cat_name, Category.store_id == store.id)
                .first()
            )
            if exists is None:
                db.add(Category(name=cat_name, store_id=store.id))
        db.commit()

        # --- Sanity check: tidak boleh ada data toko tanpa store_id ---
        from .models.product import Product
        from .models.sale import Sale

        for model, label in ((Category, "categories"), (Product, "products"), (Sale, "sales")):
            n = db.query(model).filter(model.store_id.is_(None)).count()
            if n:
                print(
                    f"[startup] PERINGATAN: {n} baris {label} tanpa store_id. "
                    "Baris ini tidak akan terlihat POS mana pun.",
                    flush=True,
                )
    finally:
        db.close()