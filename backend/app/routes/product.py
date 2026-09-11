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
from ..config import settings
from ..services.storage import storage

router = APIRouter(prefix="/products", tags=["products"])

ALLOWED_PHOTO_EXT = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
ALLOWED_PHOTO_MIME = {"image/jpeg", "image/png", "image/webp", "image/gif"}


@router.get("/categories", response_model=list[CategoryResponse])
def list_categories(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return db.query(Category).order_by(Category.name.asc()).all()


@router.post("/categories", response_model=CategoryResponse, status_code=status.HTTP_201_CREATED)
def create_category(
    body: CategoryCreate,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    existing = db.query(Category).filter(Category.name == body.name).first()
    if existing:
        raise HTTPException(status_code=400, detail="Kategori sudah ada")
    cat = Category(name=body.name, description=body.description)
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
    cat = db.query(Category).filter(Category.id == category_id).first()
    if not cat:
        raise HTTPException(status_code=404, detail="Kategori tidak ditemukan")

    changes = {}
    if body.name is not None:
        existing = db.query(Category).filter(
            Category.name == body.name, Category.id != category_id
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
    cat = db.query(Category).filter(Category.id == category_id).first()
    if not cat:
        raise HTTPException(status_code=404, detail="Kategori tidak ditemukan")

    has_products = db.query(Product).filter(Product.category_id == category_id).first()
    if has_products:
        raise HTTPException(
            status_code=400,
            detail="Kategori masih digunakan oleh produk, tidak dapat dihapus",
        )

    db.delete(cat)
    db.commit()
    log_audit(db, current_user, "CATEGORY_DELETE", "category", category_id,
              {"name": cat.name}, request)
    return {"message": "Kategori dihapus"}


@router.get("", response_model=list[ProductResponse])
def list_products(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    category_id: UUID | None = None,
    is_active: bool | None = None,
    search: str = "",
):
    query = db.query(Product)
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
    product = db.query(Product).filter(Product.id == product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")
    return product.to_dict()


@router.post("", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)
def create_product(
    body: ProductCreate,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
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
    )
    db.add(product)
    db.commit()
    db.refresh(product)
    log_audit(db, current_user, "PRODUCT_CREATE", "product", product.id,
              {"name": product.name, "modal_price": body.modal_price,
               "selling_price": body.selling_price, "stock": body.stock}, request)

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
    product = db.query(Product).filter(Product.id == product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")

    changes = {}
    if body.name is not None:
        product.name = body.name
        changes["name"] = body.name
    if body.category_id is not None:
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
    product = db.query(Product).filter(Product.id == product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")

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
    product = db.query(Product).filter(Product.id == product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")

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
    from ..models.sale import SaleItem
    from ..models.stock_movement import StockMovement

    product = db.query(Product).filter(Product.id == product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")

    has_references = (
        db.query(SaleItem).filter(SaleItem.product_id == product_id).first()
        or db.query(StockMovement).filter(StockMovement.product_id == product_id).first()
    )
    if has_references:
        # Produk sudah pernah tercatat dalam transaksi/stok: nonaktifkan saja, jangan hapus
        product.is_active = False
        db.commit()
        db.refresh(product)
        log_audit(db, current_user, "PRODUCT_DEACTIVATE", "product", product.id,
                  {"name": product.name, "reason": "produk sudah memiliki histori"}, request)
        return {"message": "Produk memiliki histori transaksi, dinonaktifkan", "product": product.to_dict()}

    db.delete(product)
    db.commit()
    log_audit(db, current_user, "PRODUCT_DELETE", "product", product_id,
              {"name": product.name}, request)
    return {"message": "Produk dihapus"}