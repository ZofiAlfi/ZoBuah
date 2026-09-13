from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from pathlib import Path
import mimetypes
import time

from .config import settings
from .database import Base, engine, SessionLocal
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
)


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Fruit POS API - Manajemen toko buah online/offline",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


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


@app.get("/health")
def health():
    return {
        "status": "ok",
        "time": __import__("datetime").datetime.utcnow().isoformat(),
        "payment_photo_columns": _payment_photo_columns_exist(),
    }


app.include_router(auth.router, prefix="/api/v1")
app.include_router(product.router, prefix="/api/v1")
app.include_router(sale.router, prefix="/api/v1")
app.include_router(stock.router, prefix="/api/v1")
app.include_router(damage_report.router, prefix="/api/v1")
app.include_router(sync.router, prefix="/api/v1")
app.include_router(report.router, prefix="/api/v1")
app.include_router(audit.router, prefix="/api/v1")

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


def create_tables():
    Base.metadata.create_all(bind=engine)
    _migrate_payment_photo_columns()


@app.on_event("startup")
def create_tables_on_start():
    create_tables()
    seed_initial_data()


def seed_initial_data():
    """Membuat akun Bos default jika belum ada + kategori buah dasar."""
    from .models.user import User, UserRole
    from .models.category import Category
    from .security import hash_password

    db = SessionLocal()
    try:
        existing = db.query(User).filter(User.role == UserRole.BOS.value).first()
        if existing is None:
            user = User(
                username="bos",
                full_name="Pemilik Toko",
                password_hash=hash_password("bos12345"),
                role=UserRole.BOS.value,
                is_active=True,
            )
            db.add(user)
            db.commit()
            print("[startup] Akun BOS default dibuat: username=bos password=bos12345")

        for cat_name in ["Apel", "Jeruk", "Mangga", "Pisang", "Semangka", "Alpukat", "Nanas", "Kelapa", "Lainnya"]:
            existing_cat = db.query(Category).filter(Category.name == cat_name).first()
            if existing_cat is None:
                db.add(Category(name=cat_name))
        db.commit()
    finally:
        db.close()