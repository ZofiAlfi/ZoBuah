from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session, joinedload
from typing import Optional
from uuid import UUID
import uuid as _uuid

from ..database import get_db
from ..models.user import User, UserRole
from ..models.product import Product
from ..models.sale import Sale, SaleItem, Payment
from ..schemas.sale import SaleCreate, SaleCancelRequest, SaleResponse
from ..security import get_current_user, require_bos, log_audit
from ..services.stock_service import record_sale_quantity, InsufficientStockError


def generate_transaction_number(db: Session) -> str:
    from datetime import datetime
    today = datetime.now()
    date_part = today.strftime("%Y%m%d")
    prefix = f"TRX-{date_part}-"
    nums = []
    for (tn,) in (
        db.query(Sale.transaction_number)
        .filter(Sale.transaction_number.like(f"{prefix}%"))
        .all()
    ):
        try:
            nums.append(int(tn.rsplit("-", 1)[-1]))
        except ValueError:
            # Nomor transaksi offline dari HP bisa berformat hex (mis. 6E0);
            # abaikan, jangan sampai memicu crash pembuatan nomor baru.
            continue
    new_num = (max(nums) + 1) if nums else 1
    return f"{prefix}{new_num:03d}"


def _save_payment_photo(sale_id, photo_b64: str) -> dict:
    """Simpan foto bukti pembayaran; kembalikan {"file_path", "file_url"}."""
    import base64
    from ..services.storage import storage

    try:
        photo_bytes = base64.b64decode(photo_b64)
    except Exception:
        return {}
    if not photo_bytes:
        return {}
    rel_key = f"payment/{sale_id}_0.jpg"
    storage.save_bytes(rel_key, photo_bytes, "image/jpeg")
    return {"file_path": rel_key, "file_url": storage.url(rel_key)}


router = APIRouter(prefix="/sales", tags=["sales"])


@router.post("", status_code=status.HTTP_201_CREATED)
def create_sale(
    body: SaleCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    sale_id = body.id or _uuid.uuid4()
    if body.id:
        existing = db.query(Sale).filter(Sale.id == body.id).first()
        if existing:
            raise HTTPException(status_code=409, detail="Transaksi sudah tercatat")

    employee_id = body.employee_id or current_user.id
    employee = db.query(User).filter(User.id == employee_id).first()
    if not employee:
        raise HTTPException(status_code=404, detail="Karyawan tidak ditemukan")

    transaction_number = body.transaction_number or generate_transaction_number(db)

    total_amount = 0
    total_modal = 0
    items_to_add = []

    for item in body.items:
        product = db.query(Product).filter(Product.id == item.product_id).first()
        if not product:
            raise HTTPException(status_code=404, detail="Produk tidak ditemukan")
        if not product.is_active:
            raise HTTPException(
                status_code=400, detail=f"Produk {product.name} tidak aktif"
            )

        unit_price = item.unit_price
        subtotal = round(unit_price * item.quantity, 2)
        modal_total = round(float(product.modal_price or 0) * item.quantity, 2)
        total_amount += subtotal
        total_modal += modal_total

        items_to_add.append({
            "product": product,
            "quantity": item.quantity,
            "unit_price": unit_price,
            "modal_price": float(product.modal_price or 0),
            "unit": product.unit,
        })

    if body.discount:
        total_amount = max(0, total_amount - body.discount)

    total_profit = round(total_amount - total_modal, 2)

    sale = Sale(
        id=sale_id,
        transaction_number=transaction_number,
        employee_id=employee.id,
        total_amount=total_amount,
        total_modal=total_modal,
        total_profit=total_profit,
        discount=body.discount or 0,
        status="COMPLETED",
    )

    db.add(sale)
    db.flush()

    for data in items_to_add:
        try:
            record_sale_quantity(db, data["product"], sale.id, data["quantity"], current_user)
        except InsufficientStockError as e:
            db.rollback()
            raise HTTPException(status_code=400, detail=str(e))

        sale_item = SaleItem(
            sale_id=sale.id,
            product_id=data["product"].id,
            product_name=data["product"].name,
            unit=data["unit"],
            unit_price=data["unit_price"],
            modal_price=data["modal_price"],
            quantity=data["quantity"],
            subtotal=round(data["unit_price"] * data["quantity"], 2),
        )
        db.add(sale_item)

    if body.payment:
        payment_kwargs = {}
        if body.payment.photo:
            payment_kwargs.update(_save_payment_photo(sale.id, body.payment.photo))
        payment = Payment(
            sale_id=sale.id,
            method=body.payment.method,
            amount=body.payment.amount,
            cash_received=body.payment.cash_received,
            change_amount=body.payment.change_amount,
            reference=body.payment.reference,
            **payment_kwargs,
        )
        db.add(payment)

    db.commit()
    db.refresh(sale)
    log_audit(db, current_user, "SALE_CREATE", "sale", sale.id,
              {"transaction_number": transaction_number, "total": total_amount}, request)

    return {**sale.to_dict(), "items": [i.to_dict() for i in sale.sale_items]}


@router.get("", response_model=list[SaleResponse])
def list_sales(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
):
    query = db.query(Sale)
    if current_user.role == UserRole.KARYAWAN.value:
        query = query.filter(Sale.employee_id == current_user.id)
    if date_from:
        query = query.filter(Sale.created_at >= date_from)
    if date_to:
        query = query.filter(Sale.created_at <= f"{date_to} 23:59:59")
    return [
        {**sale.to_dict(), "items": [i.to_dict() for i in sale.sale_items]}
        for sale in query.options(
            joinedload(Sale.employee),
            joinedload(Sale.sale_items),
            joinedload(Sale.payment),
        )
        .order_by(Sale.created_at.desc())
        .all()
    ]


@router.get("/{sale_id}")
def get_sale(
    sale_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    sale = (
        db.query(Sale)
        .options(joinedload(Sale.sale_items), joinedload(Sale.payment))
        .filter(Sale.id == sale_id)
        .first()
    )
    if not sale:
        raise HTTPException(status_code=404, detail="Transaksi tidak ditemukan")
    if current_user.role == UserRole.KARYAWAN.value and sale.employee_id != current_user.id:
        raise HTTPException(status_code=403, detail="Akses ditolak")
    return sale.to_dict()


@router.post("/{sale_id}/cancel")
def cancel_sale(
    sale_id: UUID,
    body: SaleCancelRequest,
    request: Request,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
):
    from datetime import datetime
    sale = db.query(Sale).filter(Sale.id == sale_id).first()
    if not sale:
        raise HTTPException(status_code=404, detail="Transaksi tidak ditemukan")
    if sale.status != "COMPLETED":
        raise HTTPException(status_code=400, detail="Transaksi tidak dapat dibatalkan")

    sale.status = "CANCELED"
    sale.canceled_at = datetime.utcnow()
    sale.canceled_by = current_user.id
    sale.canceled_reason = body.reason

    for item in sale.sale_items:
        product = db.query(Product).filter(Product.id == item.product_id).first()
        if product:
            from ..services.stock_service import record_stock_movement
            record_stock_movement(
                db, product, "RETURN", float(item.quantity), current_user,
                reference_id=sale.id, reference_type="sale_cancel",
                notes=f"Pembatalan transaksi {sale.transaction_number}",
            )

    db.commit()
    db.refresh(sale)
    log_audit(db, current_user, "SALE_CANCEL", "sale", sale.id,
              {"transaction_number": sale.transaction_number, "reason": body.reason}, request)
    return sale.to_dict()