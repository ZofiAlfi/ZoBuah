import uuid as _uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.user import User, UserRole
from ..models.product import Product
from ..models.category import Category
from ..models.sale import Sale, SaleItem, Payment
from ..models.damage_report import DamageReport, DamagePhoto
from ..models.stock_movement import StockMovement
from ..models.sync_event import SyncEvent
from ..schemas.sync import SyncPushRequest, SyncPullRequest, SyncPullResponse
from ..security import get_current_user, register_device, log_audit

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post("/push")
def push_data(
    body: SyncPushRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.device_id:
        register_device(db, body.device_id, platform="android", device_name="android-device")

    accepted = 0
    rejected = 0
    results = []

    for item in body.items:
        entity_type = item.entity_type
        entity_id = item.entity_id
        data = item.data or {}

        try:
            # Idempotency check: skip if entity already exists on server
            if entity_type == "sale":
                existing = db.query(Sale).filter(Sale.id == entity_id).first()
                if existing:
                    db.add(SyncEvent(
                        event_type="SKIP_DUPLICATE",
                        entity_type="sale",
                        entity_id=entity_id,
                        device_id=body.device_id,
                        status="PROCESSED",
                    ))
                    db.commit()
                    rejected += 1
                    results.append({"entity_id": entity_id, "status": "duplicate"})
                    continue

                employee_id = data.get("employee_id") or str(current_user.id)
                if current_user.role == UserRole.KARYAWAN.value:
                    employee_id = str(current_user.id)
                transaction_number = data.get("transaction_number") or _uuid.uuid4().__str__()[:8].upper()

                sale = Sale(
                    id=entity_id,
                    transaction_number=transaction_number,
                    employee_id=employee_id,
                    total_amount=data.get("total_amount", 0),
                    total_modal=data.get("total_modal", 0),
                    total_profit=data.get("total_profit", 0),
                    discount=data.get("discount", 0),
                    status=data.get("status", "COMPLETED"),
                    created_at=datetime.fromisoformat(data["created_at"]) if data.get("created_at") else datetime.utcnow(),
                )
                db.add(sale)
                db.flush()

                for si in data.get("items", []):
                    product = db.query(Product).filter(Product.id == si["product_id"]).first()
                    if product:
                        db.add(SaleItem(
                            sale_id=sale.id,
                            product_id=si["product_id"],
                            product_name=si.get("product_name", product.name),
                            unit=si.get("unit", product.unit),
                            unit_price=si.get("unit_price", 0),
                            modal_price=si.get("modal_price", 0),
                            quantity=si.get("quantity", 0),
                            subtotal=si.get("subtotal", 0),
                        ))
                        # Recompute local stock deductions for offline sales on server's product
                        from ..services.stock_service import record_sale_quantity
                        try:
                            record_sale_quantity(db, product, sale.id, si.get("quantity", 0), current_user)
                        except Exception:
                            db.rollback()
                            return HTTPException(status_code=400, detail="Stok tidak mencukupi")

                pay = data.get("payment")
                if pay:
                    db.add(Payment(
                        sale_id=sale.id,
                        method=pay.get("method", "CASH"),
                        amount=pay.get("amount", 0),
                        cash_received=pay.get("cash_received"),
                        change_amount=pay.get("change_amount"),
                        reference=pay.get("reference"),
                    ))

                db.add(SyncEvent(
                    event_type="PUSH",
                    entity_type="sale",
                    entity_id=entity_id,
                    device_id=body.device_id,
                    server_reference=str(sale.id),
                    status="PROCESSED",
                ))
                db.commit()
                accepted += 1
                results.append({"entity_id": entity_id, "status": "ok"})

            elif entity_type == "damage_report":
                existing = db.query(DamageReport).filter(DamageReport.id == entity_id).first()
                if existing:
                    db.add(SyncEvent(
                        event_type="SKIP_DUPLICATE",
                        entity_type="damage_report",
                        entity_id=entity_id,
                        device_id=body.device_id,
                        status="PROCESSED",
                    ))
                    db.commit()
                    rejected += 1
                    results.append({"entity_id": entity_id, "status": "duplicate"})
                    continue

                product = db.query(Product).filter(Product.id == data.get("product_id")).first()
                if not product:
                    rejected += 1
                    results.append({"entity_id": entity_id, "status": "product_not_found"})
                    continue

                emp_id = data.get("employee_id") or current_user.id
                if current_user.role == UserRole.KARYAWAN.value:
                    emp_id = current_user.id

                report = DamageReport(
                    id=entity_id,
                    product_id=data["product_id"],
                    quantity=data["quantity"],
                    unit=data.get("unit", product.unit),
                    reason=data.get("reason", "OTHER"),
                    description=data.get("description"),
                    status="PENDING",
                    employee_id=emp_id,
                    created_at=datetime.fromisoformat(data["created_at"]) if data.get("created_at") else datetime.utcnow(),
                )
                db.add(report)

                for i, photo in enumerate(data.get("photos", [])):
                    try:
                        import base64
                        from ..services.storage import storage
                        photo_bytes = base64.b64decode(photo)
                        fname = f"{entity_id}_{i}.jpg"
                        rel_key = f"damage/{fname}"
                        storage.save_bytes(rel_key, photo_bytes, "image/jpeg")
                        db.add(DamagePhoto(
                            damage_report_id=report.id,
                            file_path=rel_key,
                            file_url=storage.url(rel_key),
                        ))
                    except Exception:
                        pass

                db.add(SyncEvent(
                    event_type="PUSH",
                    entity_type="damage_report",
                    entity_id=entity_id,
                    device_id=body.device_id,
                    status="PROCESSED",
                ))
                db.commit()
                accepted += 1
                results.append({"entity_id": entity_id, "status": "ok"})

            else:
                rejected += 1
                results.append({"entity_id": entity_id, "status": f"unsupported_type:{entity_type}"})

        except Exception as e:
            db.rollback()
            db.add(SyncEvent(
                event_type="PUSH_FAILED",
                entity_type=entity_type,
                entity_id=entity_id,
                device_id=body.device_id,
                status="FAILED",
                error_message=str(e),
            ))
            db.commit()
            rejected += 1
            results.append({"entity_id": entity_id, "status": "error", "message": str(e)})

    return {"accepted": accepted, "rejected": rejected, "results": results}


@router.post("/pull", response_model=SyncPullResponse)
def pull_data(
    body: SyncPullRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.device_id:
        register_device(db, body.device_id, platform="android", device_name="android-device")

    products = db.query(Product).all()
    categories = db.query(Category).all()

    damage_query = db.query(DamageReport)
    sales_query = db.query(Sale)

    if current_user.role == UserRole.KARYAWAN.value:
        # Karyawan hanya mendapat laporan & transaksi miliknya, dan status approval terbaru
        damage_query = damage_query.filter(DamageReport.employee_id == current_user.id)
        sales_query = sales_query.filter(Sale.employee_id == current_user.id)

    if body.last_sync_at:
        since = body.last_sync_at
        damage_query = damage_query.filter(DamageReport.updated_at >= since)
        sales_query = sales_query.filter(Sale.updated_at >= since)

    damage_reports = damage_query.order_by(DamageReport.created_at.desc()).all()
    sales = sales_query.order_by(Sale.created_at.desc()).limit(500).all()
    movements = db.query(StockMovement).all()

    return SyncPullResponse(
        products=[p.to_dict() for p in products],
        categories=[c.to_dict() for c in categories],
        damage_reports=[r.to_dict() for r in damage_reports],
        stock_movements=[m.to_dict() for m in movements],
        sales=[s.to_dict() for s in sales],
        server_time=datetime.utcnow().isoformat(),
    )