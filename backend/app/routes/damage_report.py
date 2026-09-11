import uuid as _uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from typing import Optional
from uuid import UUID

from ..database import get_db
from ..models.user import User, UserRole
from ..models.product import Product
from ..models.damage_report import DamageReport, DamagePhoto
from ..schemas.damage_report import (
    DamageReportCreate,
    DamageReportApprove,
    DamageReportReject,
)
from ..services.stock_service import record_damage
from ..security import get_current_user, require_bos, log_audit
from ..config import settings
from ..services.storage import storage

router = APIRouter(prefix="/damage-reports", tags=["damage-reports"])


@router.post("", status_code=status.HTTP_201_CREATED)
def create_damage_report(
    body: DamageReportCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.id:
        existing = db.query(DamageReport).filter(DamageReport.id == body.id).first()
        if existing:
            raise HTTPException(status_code=409, detail="Laporan sudah tercatat")

    product = db.query(Product).filter(Product.id == body.product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")

    employee_id = body.employee_id or current_user.id

    report_id = body.id or _uuid.uuid4()
    report = DamageReport(
        id=report_id,
        product_id=body.product_id,
        quantity=body.quantity,
        unit=body.unit,
        reason=body.reason,
        description=body.description,
        status="PENDING",
        employee_id=employee_id,
        created_at=body.created_at or datetime.utcnow(),
    )
    db.add(report)
    db.flush()

    for i, photo_b64 in enumerate(body.photos):
        try:
            import base64
            photo_bytes = base64.b64decode(photo_b64)
            fname = f"{report_id}_{i}.jpg"
            rel_key = f"damage/{fname}"
            storage.save_bytes(rel_key, photo_bytes, "image/jpeg")
            db.add(DamagePhoto(
                damage_report_id=report.id,
                file_path=rel_key,
                file_url=storage.url(rel_key),
            ))
        except Exception:
            continue

    db.commit()
    db.refresh(report)
    log_audit(db, current_user, "DAMAGE_REPORT_CREATE", "damage_report", report.id,
              {"product": product.name, "quantity": body.quantity, "reason": body.reason}, request)
    return report.to_dict()


@router.get("")
def list_damage_reports(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    status_filter: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    product_id: Optional[UUID] = None,
    employee_id: Optional[UUID] = None,
    reason: Optional[str] = None,
):
    query = db.query(DamageReport)
    if current_user.role == UserRole.KARYAWAN.value:
        query = query.filter(DamageReport.employee_id == current_user.id)
    if status_filter:
        query = query.filter(DamageReport.status == status_filter)
    if date_from:
        query = query.filter(DamageReport.created_at >= date_from)
    if date_to:
        query = query.filter(DamageReport.created_at <= f"{date_to} 23:59:59")
    if product_id:
        query = query.filter(DamageReport.product_id == product_id)
    if employee_id:
        query = query.filter(DamageReport.employee_id == employee_id)
    if reason:
        query = query.filter(DamageReport.reason == reason)
    reports = query.order_by(DamageReport.created_at.desc()).all()
    return [r.to_dict() for r in reports]


@router.get("/{report_id}")
def get_damage_report(
    report_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    report = db.query(DamageReport).filter(DamageReport.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Laporan tidak ditemukan")
    if current_user.role == UserRole.KARYAWAN.value and report.employee_id != current_user.id:
        raise HTTPException(status_code=403, detail="Akses ditolak")
    return report.to_dict()


@router.post("/{report_id}/approve")
def approve_damage_report(
    report_id: UUID,
    body: DamageReportApprove,
    request: Request,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
):
    report = db.query(DamageReport).filter(DamageReport.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Laporan tidak ditemukan")
    if report.status != "PENDING":
        raise HTTPException(status_code=400, detail="Hanya laporan PENDING yang dapat disetujui")

    product = db.query(Product).filter(Product.id == report.product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")

    try:
        record_damage(db, product, report.id, float(report.quantity), current_user)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e))

    report.status = "APPROVED"
    report.approved_by = current_user.id
    report.approved_at = datetime.utcnow()
    db.commit()
    db.refresh(report)
    log_audit(db, current_user, "DAMAGE_REPORT_APPROVE", "damage_report", report.id,
              {"product": product.name, "quantity": float(report.quantity)}, request)
    return report.to_dict()


@router.post("/{report_id}/reject")
def reject_damage_report(
    report_id: UUID,
    body: DamageReportReject,
    request: Request,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
):
    report = db.query(DamageReport).filter(DamageReport.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Laporan tidak ditemukan")
    if report.status != "PENDING":
        raise HTTPException(status_code=400, detail="Hanya laporan PENDING yang dapat ditolak")

    report.status = "REJECTED"
    report.rejected_by = current_user.id
    report.rejected_at = datetime.utcnow()
    report.rejection_reason = body.reason
    db.commit()
    db.refresh(report)
    log_audit(db, current_user, "DAMAGE_REPORT_REJECT", "damage_report", report.id,
              {"reason": body.reason}, request)
    return report.to_dict()