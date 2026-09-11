from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from typing import Optional
from uuid import UUID

from ..database import get_db
from ..models.user import User
from ..models.product import Product
from ..models.stock_movement import StockMovement
from ..schemas.product import StockInRequest
from ..services.stock_service import record_stock_in, record_stock_adjustment
from ..security import get_current_user, require_bos, log_audit

router = APIRouter(prefix="/stock", tags=["stock"])


@router.get("")
def get_stock(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    products = db.query(Product).all()
    result = []
    for p in products:
        d = p.to_dict()
        d["status"] = "LOW" if float(p.stock or 0) <= float(p.min_stock or 0) and p.is_active else "OK"
        result.append(d)
    return result


@router.post("/in")
def stock_in(
    body: StockInRequest,
    request: Request,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
):
    product = db.query(Product).filter(Product.id == body.product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")

    movement = record_stock_in(
        db, product, product.id, body.quantity, current_user,
        "STOCK_IN", notes=body.notes or "Stok masuk",
    )
    log_audit(db, current_user, "STOCK_IN", "product", product.id,
              {"product": product.name, "quantity": body.quantity}, request)
    db.refresh(product)
    return {"movement": movement.to_dict(), "product": product.to_dict()}


@router.get("/movements")
def get_movements(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    product_id: Optional[str] = None,
    movement_type: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    limit: int = 100,
):
    query = db.query(StockMovement)
    if product_id:
        query = query.filter(StockMovement.product_id == product_id)
    if movement_type:
        query = query.filter(StockMovement.movement_type == movement_type)
    if date_from:
        query = query.filter(StockMovement.created_at >= date_from)
    if date_to:
        query = query.filter(StockMovement.created_at <= f"{date_to} 23:59:59")
    movements = query.order_by(StockMovement.created_at.desc()).limit(limit).all()

    result = []
    for m in movements:
        d = m.to_dict()
        product = db.query(Product).filter(Product.id == m.product_id).first()
        d["product_name"] = product.name if product else None
        result.append(d)
    return result


@router.post("/adjustment")
def stock_adjustment(
    body: dict,
    request: Request,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
):
    product_id = body.get("product_id")
    quantity = float(body.get("quantity", 0))
    notes = body.get("notes")

    if not product_id or quantity == 0:
        raise HTTPException(status_code=400, detail="product_id dan quantity (non-zero) diperlukan")

    product = db.query(Product).filter(Product.id == product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")

    try:
        movement = record_stock_adjustment(db, product, quantity, current_user, notes)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e))

    log_audit(db, current_user, "STOCK_ADJUSTMENT", "product", product.id,
              {"product": product.name, "quantity": quantity, "notes": notes}, request)
    db.refresh(product)
    return {"movement": movement.to_dict(), "product": product.to_dict()}