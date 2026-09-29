from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import Optional

from ..database import get_db
from ..models.audit_log import AuditLog
from ..models.user import User
from ..security import require_bos
from ..tenancy import require_store_id

router = APIRouter(prefix="/audit", tags=["audit"])


@router.get("/logs")
def list_audit_logs(
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    user_id: Optional[str] = None,
    action: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    limit: int = 200,
):
    # Log audit toko ini saja. Log berisi siapa melakukan apa, jadi membocorkan
    # log antar toko berarti membocorkan struktur internal toko lain.
    query = db.query(AuditLog).filter(
        AuditLog.store_id == require_store_id(current_user)
    )
    if user_id:
        query = query.filter(AuditLog.user_id == user_id)
    if action:
        query = query.filter(AuditLog.action == action)
    if date_from:
        query = query.filter(AuditLog.created_at >= date_from)
    if date_to:
        query = query.filter(AuditLog.created_at <= f"{date_to} 23:59:59")
    logs = query.order_by(AuditLog.created_at.desc()).limit(limit).all()
    return [log.to_dict() for log in logs]