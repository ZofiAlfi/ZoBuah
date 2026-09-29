from fastapi import APIRouter, Depends, HTTPException, status, Request, UploadFile, File
from sqlalchemy.orm import Session
from uuid import UUID
from pathlib import Path

from ..database import get_db
from ..models.user import User
from ..models.category import Category
from ..models.product import Product
from ..models.audit_log import AuditLog
from ..schemas.product import (
    CategoryCreate,
    CategoryUpdate,
    CategoryResponse,
    ProductCreate,
    ProductUpdate,
    ProductResponse,
    StockInRequest,
)
from ..security import get_current_user, require_bos, log_audit
from ..tenancy import require_store_id
from ..config import settings
from ..services.storage import storage

router = APIRouter(prefix="/products", tags=["products"])

ALLOWED_PHOTO_EXT = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
ALLOWED_PHOTO_MIME = {"image/jpeg", "image/png", "image/webp", "image/gif"}


def get_product_for_store(db: Session, product_id: UUID, store_id):
    """Produk milik toko tertentu, atau 404.

    Semua endpoint produk wajib lewat sini. Mengambil produk berdasarkan UUID
    saja berarti satu toko bisa membaca dan mengubah produk toko lain.
    """
    product = db.query(Product).filter(Product.id == product_id, Product.store_id == store_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")
    return product


def get_category_for_store(db: Session, category_id: UUID, store_id):
    cat = db.query(Category).filter(Category.id == category_id, Category.store_id == store_id).first()
    if not cat:
        raise HTTPException(status_code=404, detail="Kategori tidak ditemukan")
    return cat


@router.get("/categories", response_model=list[CategoryResponse])
def list_categories(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return (
        db.query(Category)
        .filter(Category.store_id == require_store_id(current_user))
        .order_by(Category.name.asc())
        .all()
    )


@router.post("/categories", response_model=CategoryResponse, status_code=status.HTTP_201_CREATED)
def create_category(
    body: CategoryCreate,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    store_id = require_store_id(current_user)
    # Unik per toko, bukan global. Kalau global, toko kedua tidak bisa punya
    # kategori "Apel" karena kategori itu sudah dipakai toko pertama.
    existing = db.query(Category).filter(
        Category.name == body.name, Category.store_id == store_id
    ).first()
    if existing:
        # Kategori yang sebelumnya dinonaktifkan di-revive dengan id yang
        # sama, bukan dibuat baru. Kalau dibuat baru, unique (store_id, name)
        # akan menolaknya dengan error 500 dari database.
        if not existing.is_active:
            existing.is_active = True
            if body.description is not None:
                existing.description = body.description
            db.commit()
            db.refresh(existing)
            log_audit(db, current_user, "CATEGORY_REACTIVATE", "category",
                      existing.id, {"name": existing.name}, request)
            return existing
        raise HTTPException(status_code=400, detail="Kategori sudah ada")
    cat = Category(name=body.name, description=body.description, store_id=store_id)
    db.add(cat)
    db.commit()
    db.refresh(cat)
    log_audit(db, current_user, "CATEGORY_CREATE", "category", cat.id, {"name": cat.name}, request)
    return cat


@router.put("/categories/{category_id}", response_model=CategoryResponse)
def update_category(
    category_id: UUID,
    body: CategoryUpdate,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    store_id = require_store_id(current_user)
    cat = get_category_for_store(db, category_id, store_id)

    changes = {}
    if body.name is not None:
        existing = db.query(Category).filter(
            Category.name == body.name,
            Category.store_id == store_id,
            Category.id != category_id,
        ).first()
        if existing:
            raise HTTPException(status_code=400, detail="Nama kategori sudah digunakan")
        cat.name = body.name
        changes["name"] = body.name
    if body.description is not None:
        cat.description = body.description
        changes["description"] = body.description

    if changes:
        db.commit()
        db.refresh(cat)
        log_audit(db, current_user, "CATEGORY_UPDATE", "category", cat.id, changes, request)
    return cat


@router.delete("/categories/{category_id}")
def delete_category(
    category_id: UUID,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    store_id = require_store_id(current_user)
    cat = get_category_for_store(db, category_id, store_id)

    has_products = db.query(Product).filter(
        Product.category_id == category_id, Product.store_id == store_id
    ).first()
    if has_products:
        raise HTTPException(
            status_code=400,
            detail="Kategori masih digunakan oleh produk, tidak dapat dihapus",
        )

    cat.is_active = False
    db.commit()
    db.refresh(cat)
    log_audit(db, current_user, "CATEGORY_DEACTIVATE", "category", category_id,
              {"name": cat.name}, request)
    return {"message": "Kategori dinonaktifkan", "category": cat.to_dict()}


@router.get("", response_model=list[ProductResponse])
def list_products(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    category_id: UUID | None = None,
    is_active: bool | None = None,
    search: str = "",
):
    store_id = require_store_id(current_user)
    query = db.query(Product).filter(Product.store_id == store_id)
    if category_id:
        query = query.filter(Product.category_id == category_id)
    if is_active is not None:
        query = query.filter(Product.is_active == is_active)
    if search:
        query = query.filter(Product.name.ilike(f"%{search}%"))
    return [p.to_dict() for p in query.order_by(Product.name.asc()).all()]


@router.get("/{product_id}", response_model=ProductResponse)
def get_product(
    product_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return get_product_for_store(db, product_id, require_store_id(current_user)).to_dict()


@router.post("", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)
def create_product(
    body: ProductCreate,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    store_id = require_store_id(current_user)
    # Kategori tujuan harus milik toko ini, kalau tidak produk akan terlihat
    # di POS tapi categoria yang ditampilkan hilang saat sync.
    if body.category_id is not None:
        get_category_for_store(db, body.category_id, store_id)

    # Produk nonaktif dengan nama sama di-revive dengan id yang sama, bukan
    # dibuat baru dengan id baru. Ini yang mencegah duplikasi di grid kasir:
    # kalau id baru dibuat, perangkat menarik produk aktif yang baru DAN
    # masih menyimpan produk nonaktif versi lama, sehingga dua kartu dengan
    # nama sama muncul berdampingan dan kasir bisa menjual dua kali.
    # Index parsial ux_products_store_name_active yang menjaga "satu produk
    # aktif per nama per toko" dibuat di migrasi 006.
    revived = db.query(Product).filter(
        Product.name == body.name, Product.store_id == store_id
    ).first()
    if revived and not revived.is_active:
        revived.is_active = True
        revived.category_id = body.category_id
        revived.unit = body.unit
        revived.modal_price = body.modal_price
        revived.selling_price = body.selling_price
        revived.min_stock = body.min_stock
        if body.description is not None:
            revived.description = body.description
        db.commit()
        db.refresh(revived)
        # Reactivasi tidak pernah menghapus baris, jadi stok lama masih
        # menempel di kolom stock. body.stock di ProductCreate berarti stok
        # AKHIR produk (sama seperti produk baru yang mulai dari 0), bukan
        # tambahan: kalau dijumlahkan di atas stok lama, stok jadi dobel
        # (13.851 + 13.851 = 27.702). Catat selisihnya sebagai movement agar
        # jejak audit tetap benar dan stok tidak pernah diam-diam hilang.
        target = float(body.stock or 0)
        current = float(revived.stock or 0)
        delta = round(target - current, 3)
        if delta != 0:
            from ..services.stock_service import record_stock_in, record_stock_movement
            if delta > 0:
                record_stock_in(db, revived, revived.id, delta, current_user,
                                "INITIAL", notes="Stok awal saat produk diaktifkan kembali")
            else:
                record_stock_movement(db, revived, "ADJUSTMENT_NEGATIVE", -delta,
                                      current_user, reference_id=revived.id,
                                      reference_type="stock_in",
                                      notes="Stok dikoreksi saat produk diaktifkan kembali")
            db.refresh(revived)
        log_audit(db, current_user, "PRODUCT_REACTIVATE", "product", revived.id,
                  {"name": revived.name, "selling_price": body.selling_price,
                   "stock": body.stock, "previous_stock": current}, request)
        return revived.to_dict()

    product = Product(
        name=body.name,
        category_id=body.category_id,
        unit=body.unit,
        modal_price=body.modal_price,
        selling_price=body.selling_price,
        stock=0,
        min_stock=body.min_stock,
        is_active=body.is_active,
        description=body.description,
        store_id=store_id,
    )
    db.add(product)
    db.commit()
    db.refresh(product)
    log_audit(db, current_user, "PRODUCT_CREATE", "product", product.id,
              {"name": product.name, "modal_price": body.modal_price,
               "selling_price": body.selling_price, "stock": body.stock,
               "store_id": str(store_id)}, request)

    if body.stock and body.stock > 0:
        from ..services.stock_service import record_stock_in
        record_stock_in(db, product, product.id, body.stock, current_user,
                        "INITIAL", notes="Stok awal")
    return product.to_dict()


@router.put("/{product_id}", response_model=ProductResponse)
def update_product(
    product_id: UUID,
    body: ProductUpdate,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    store_id = require_store_id(current_user)
    product = get_product_for_store(db, product_id, store_id)

    changes = {}
    if body.name is not None:
        product.name = body.name
        changes["name"] = body.name
    if body.category_id is not None:
        get_category_for_store(db, body.category_id, store_id)
        product.category_id = body.category_id
        changes["category_id"] = str(body.category_id)
    if body.unit is not None:
        product.unit = body.unit
        changes["unit"] = body.unit
    if body.modal_price is not None:
        product.modal_price = body.modal_price
        changes["modal_price"] = body.modal_price
    if body.selling_price is not None:
        product.selling_price = body.selling_price
        changes["selling_price"] = body.selling_price
    if body.min_stock is not None:
        product.min_stock = body.min_stock
        changes["min_stock"] = body.min_stock
    if body.is_active is not None:
        product.is_active = body.is_active
        changes["is_active"] = body.is_active
    if body.description is not None:
        product.description = body.description
        changes["description"] = body.description

    if changes:
        db.commit()
        db.refresh(product)
        log_audit(db, current_user, "PRODUCT_UPDATE", "product", product.id, changes, request)
    return product.to_dict()


def _sniff_photo(data: bytes):
    """Deteksi tipe gambar dari magic bytes -> (mime, ext) atau (None, None)."""
    if data[:3] == b"\xff\xd8\xff":
        return "image/jpeg", ".jpg"
    if data[:4] == b"\x89PNG":
        return "image/png", ".png"
    if data[:4] == b"GIF8":
        return "image/gif", ".gif"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp", ".webp"
    return None, None


@router.post("/{product_id}/photo", response_model=ProductResponse)
async def upload_product_photo(
    product_id: UUID,
    file: UploadFile = File(...),
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    """BOS mengunggah foto produk (jpg/png/webp/gif)."""
    product = get_product_for_store(db, product_id, require_store_id(current_user))

    data = await file.read()
    max_bytes = settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024
    if len(data) > max_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"Ukuran foto maksimal {settings.MAX_UPLOAD_SIZE_MB} MB",
        )

    mime, sniff_ext = _sniff_photo(data)
    if file.content_type not in ALLOWED_PHOTO_MIME:
        # Klien Flutter/Multipart mengirim biasanya 'application/octet-stream';
        # validasi tetap dilakukan lewat magic bytes agar file non-gambar ditolak.
        if file.content_type not in ("application/octet-stream", "") or mime is None:
            raise HTTPException(
                status_code=400,
                detail="Tipe file harus jpg/png/webp/gif",
            )

    ext = sniff_ext or Path(file.filename or "photo.png").suffix.lower()
    if ext not in ALLOWED_PHOTO_EXT:
        ext = ".jpg"

    if product.photo_path:
        storage.delete(product.photo_path)

    filename = f"{product_id}{ext}"
    rel_key = f"product/{filename}"
    storage.save_bytes(rel_key, data, mime or file.content_type or "application/octet-stream")

    product.photo_path = rel_key
    db.commit()
    db.refresh(product)
    log_audit(db, current_user, "PRODUCT_PHOTO_UPLOAD", "product", product.id,
              {"name": product.name, "photo_path": product.photo_path}, request)
    return product.to_dict()


@router.delete("/{product_id}/photo", response_model=ProductResponse)
def delete_product_photo(
    product_id: UUID,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    """BOS menghapus foto produk."""
    product = get_product_for_store(db, product_id, require_store_id(current_user))

    if product.photo_path:
        storage.delete(product.photo_path)
        product.photo_path = None
        db.commit()
        db.refresh(product)
        log_audit(db, current_user, "PRODUCT_PHOTO_DELETE", "product", product.id,
                  {"name": product.name}, request)
    return product.to_dict()


@router.delete("/{product_id}")
def delete_product(
    product_id: UUID,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    from ..models.sale import SaleItem, Sale
    from ..models.stock_movement import StockMovement

    store_id = require_store_id(current_user)
    product = get_product_for_store(db, product_id, store_id)

    # SELALU nonaktifkan, jangan pernah db.delete(). Baris yang hilang dari
    # server tidak memberi sinyal apa pun ke sync/pull, sehingga produknya
    # tetap nempel di HP karyawan: masih tampil di grid, masih bisa dicari,
    # masih bisa dijual. Baris nonaktif justru dikirim di full dump products
    # dan menimpa baris lokal lewat upsert.
    #
    # Tidak perlu lagi membedakan "punya histori" atau tidak. db.delete()
    # selain itu gagal dengan IntegrityError kalau produk punya DamageReport,
    # karena damage_reports.product_id tidak punya ON DELETE.
    #
    # Pengecekan referensi tetap dilakukan hanya supaya pesan audit menyebut
    # apakah produk sudah pernah terjual, dan tetap ter-scope supaya transaksi
    # toko lain tidak ikut terhitung.
    has_references = (
        db.query(SaleItem)
        .join(Sale, SaleItem.sale_id == Sale.id)
        .filter(SaleItem.product_id == product_id, Sale.store_id == store_id)
        .first()
        or db.query(StockMovement).filter(
            StockMovement.product_id == product_id, StockMovement.store_id == store_id
        ).first()
    )

    already_inactive = not product.is_active
    product.is_active = False
    db.commit()
    db.refresh(product)
    log_audit(db, current_user, "PRODUCT_DEACTIVATE", "product", product.id,
              {"name": product.name, "has_history": bool(has_references),
               "already_inactive": already_inactive}, request)
    return {
        "message": (
            "Produk dinonaktifkan"
            if has_references
            else "Produk dinonaktifkan, tidak muncul lagi di POS"
        ),
        "product": product.to_dict(),
    }