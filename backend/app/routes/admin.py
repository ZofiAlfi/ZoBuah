"""Endpoint dashboard OWNER untuk ZoBuah.

Setiap handler di file ini memakai require_owner(), tanpa kecuali. Bandingkan
dengan route POS yang memakai get_current_user: satu require_role sudah cukup
sebagai pagar tunggal untuk seluruh dashboard.

Endpoint administrasi satu toko WAJIB menyebut store_id di path. Tidak ada
"lihat semua tanpa target" untuk data per toko; agregat lintas-toko hanya
melewati /metrics/*.
"""
import json
from datetime import date, datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import func, or_
from sqlalchemy.orm import Session, joinedload

from ..database import get_db
from ..models.audit_log import AuditLog
from ..schemas.damage_report import DamageReportReject
from ..models.broadcast import Broadcast, BroadcastTarget
from ..models.category import Category
from ..models.damage_report import DamageReport
from ..models.device import Device
from ..models.product import Product
from ..models.sale import Payment, Sale, SaleItem
from ..models.stock_movement import StockMovement
from ..models.store import Store, StoreStatus
from ..models.sync_event import SyncEvent
from ..models.user import User, UserRole
from ..schemas.admin import (
    AdminSaleData,
    AdminSaleDetail,
    AdminSaleListItem,
    AdminSaleListResponse,
    AdminUserCreate,
    AdminUserItem,
    AdminUserListResponse,
    AdminUserUpdate,
    AlertItem,
    AuditLogItem,
    AuditLogListResponse,
    BroadcastCreate,
    BroadcastItem,
    BroadcastListResponse,
    BroadcastUpdate,
    ForceLogoutResult,
    HealthRow,
    ImpersonateRequest,
    ImpersonateResult,
    OverviewResponse,
    PageMeta,
    PasswordResetResult,
    PlanRow,
    RevenuePoint,
    CategoryItem,
    CategoryListResponse,
    DamageReportItem,
    DamageReportListResponse,
    PaymentItem,
    PaymentListResponse,
    ProductHistoryItem,
    ProductHistoryResponse,
    StockMovementItem,
    StockMovementListResponse,
SaleEditRequest,
    SaleDeleteRequest,
    StoreCreate,
    StoreDetail,
    StoreListItem,
    StoreListResponse,
    StoreProductItem,
    StoreProductListResponse,
    StoreUpdate,
    StoreUsage,
    TopStore,
)
from ..services.stock_service import InsufficientStockError
from ..services.damage_service import approve_core, reject_core
from ..services.storage import storage
from ..security import (
    create_impersonation_token,
    log_audit,
    require_owner,
    revoke_all_tokens,
)
from ..services import admin_alerts, admin_metrics
from ..services.store_service import (
    create_store,
    create_store_user,
    get_store_or_404,
    update_store,
    update_store_user,
)
from ..utilities.helpers import iso_utc

router = APIRouter(prefix="/admin", tags=["admin"])


def _page(page: int, page_size: int, total: int) -> PageMeta:
    return PageMeta(
        page=page,
        page_size=page_size,
        total=total,
        total_pages=max(1, (total + page_size - 1) // page_size),
    )


# --------------------------------------------------------------------------
# Dashboard
# --------------------------------------------------------------------------
@router.get("/dashboard", response_model=dict)
def dashboard(db: Session = Depends(get_db), owner: User = Depends(require_owner())):
    """Semua yang dibutuhkan layar depan dalam satu panggilan.

    Satu endpoint, bukan lima, karena dashboard akan menampilkan lima kartu
    sekaligus; lima request terpisah berarti lima kali lambat dan angka yang
    saling tidak cocok kalau ada penjualan di antaranya.
    """
    return {
        "overview": admin_metrics.overview(db),
        "revenue_30d": admin_metrics.revenue_series(db, days=30),
        "top_stores": admin_metrics.top_stores(db, days=30, limit=5),
        "plans": admin_metrics.plan_breakdown(db),
        "alerts": admin_alerts.collect_alerts(db)[:10],
    }


@router.get("/metrics/overview", response_model=OverviewResponse)
def metrics_overview(db: Session = Depends(get_db), owner: User = Depends(require_owner())):
    return admin_metrics.overview(db)


@router.get("/metrics/revenue", response_model=list)
def metrics_revenue(
    days: int = Query(30, ge=1, le=365),
    store_id: Optional[UUID] = None,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    return admin_metrics.revenue_series(db, days=days, store_id=store_id)


@router.get("/metrics/top-stores", response_model=list)
def metrics_top_stores(
    days: int = Query(30, ge=1, le=365),
    limit: int = Query(5, ge=1, le=50),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    return admin_metrics.top_stores(db, days=days, limit=limit)


@router.get("/metrics/plans", response_model=list)
def metrics_plans(db: Session = Depends(get_db), owner: User = Depends(require_owner())):
    return admin_metrics.plan_breakdown(db)


@router.get("/metrics/usage", response_model=list)
def metrics_usage(
    store_id: Optional[UUID] = None,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    return admin_metrics.store_usage(db, store_id=store_id)


@router.get("/stores/health", response_model=list)
def stores_health(db: Session = Depends(get_db), owner: User = Depends(require_owner())):
    return admin_metrics.store_health(db)


@router.get("/alerts", response_model=list)
def list_alerts(db: Session = Depends(get_db), owner: User = Depends(require_owner())):
    return admin_alerts.collect_alerts(db)


# --------------------------------------------------------------------------
# Toko
# --------------------------------------------------------------------------
@router.get("/stores", response_model=StoreListResponse)
def list_stores(
    q: Optional[str] = Query(None, max_length=100),
    plan: Optional[str] = None,
    status_filter: Optional[str] = Query(None, alias="status"),
    is_active: Optional[bool] = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    query = db.query(Store)

    if q:
        like = f"%{q.strip()}%"
        query = query.filter(
            or_(
                func.lower(Store.name).like(like.lower()),
                func.lower(Store.code).like(like.lower()),
                func.lower(Store.owner_name).like(like.lower()),
            )
        )
    if plan:
        query = query.filter(Store.plan == plan)
    if status_filter:
        query = query.filter(Store.status == status_filter)
    if is_active is not None:
        query = query.filter(Store.is_active.is_(is_active))

    total = query.count()
    rows = query.order_by(Store.created_at.desc()).offset((page - 1) * page_size).limit(page_size).all()

    sync_map = admin_metrics.last_sync_map(db)
    window_start = admin_metrics._window_start(30)

    # store_id -> (jumlah transaksi, total omzet). Baris agregat punya tiga
    # kolom, jadi tidak bisa langsung diempar ke dict().
    sales = {
        row[0]: (int(row[1] or 0), float(row[2] or 0))
        for row in db.query(
            Sale.store_id,
            func.count(Sale.id),
            func.coalesce(func.sum(Sale.total_amount), 0),
        )
        .filter(Sale.status == "COMPLETED", Sale.created_at >= window_start)
        .group_by(Sale.store_id)
        .all()
    }
    users = dict(
        db.query(User.store_id, func.count(User.id))
        .filter(User.store_id.isnot(None))
        .group_by(User.store_id)
        .all()
    )
    products = dict(
        db.query(Product.store_id, func.count(Product.id))
        .filter(Product.store_id.isnot(None), Product.is_active.is_(True))
        .group_by(Product.store_id)
        .all()
    )

    items = []
    for store in rows:
        row = sales.get(store.id)
        items.append(
            StoreListItem(
                id=store.id,
                code=store.code,
                name=store.name,
                owner_name=store.owner_name,
                phone=store.phone,
                address=store.address,
                plan=store.plan,
                plan_expires_at=store.plan_expires_at,
                days_to_expiry=store.days_to_expiry(),
                status=store.status,
                is_active=store.is_active,
                health=admin_metrics.health_of(store, sync_map.get(store.id)),
                last_sync_at=sync_map.get(store.id),
                user_count=users.get(store.id, 0),
                product_count=products.get(store.id, 0),
                sale_count_30d=int(row[0]) if row else 0,
                revenue_30d=round(row[1] if row else 0, 2),
                created_at=store.created_at,
            )
        )

    return StoreListResponse(items=items, meta=_page(page, page_size, total))


@router.post("/stores", response_model=StoreDetail, status_code=status.HTTP_201_CREATED)
def post_store(
    request: Request,
    body: StoreCreate,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    store = create_store(db, body, owner, request)
    return _store_detail(db, store)


def _store_detail(db: Session, store: Store) -> StoreDetail:
    sync_map = admin_metrics.last_sync_map(db)
    window_start = admin_metrics._window_start(30)

    row = (
        db.query(
            func.count(Sale.id),
            func.coalesce(func.sum(Sale.total_amount), 0),
        )
        .filter(Sale.store_id == store.id, Sale.status == "COMPLETED", Sale.created_at >= window_start)
        .first()
    )
    lifetime = (
        db.query(func.count(Sale.id), func.coalesce(func.sum(Sale.total_amount), 0))
        .filter(Sale.store_id == store.id, Sale.status == "COMPLETED")
        .first()
    )
    return StoreDetail(
        id=store.id,
        code=store.code,
        name=store.name,
        owner_name=store.owner_name,
        phone=store.phone,
        address=store.address,
        plan=store.plan,
        plan_expires_at=store.plan_expires_at,
        days_to_expiry=store.days_to_expiry(),
        status=store.status,
        is_active=store.is_active,
        health=admin_metrics.health_of(store, sync_map.get(store.id)),
        last_sync_at=sync_map.get(store.id),
        user_count=db.query(func.count(User.id)).filter(User.store_id == store.id).scalar() or 0,
        product_count=(
            db.query(func.count(Product.id))
            .filter(Product.store_id == store.id, Product.is_active.is_(True))
            .scalar()
            or 0
        ),
        sale_count_30d=int(row[0] or 0),
        revenue_30d=round(admin_metrics._f(row[1]), 2),
        created_at=store.created_at,
        device_count=(
            db.query(func.count(Device.id))
            .filter(Device.store_id == store.id, Device.is_active.is_(True))
            .scalar()
            or 0
        ),
        category_count=(
            db.query(func.count(Category.id)).filter(Category.store_id == store.id).scalar() or 0
        ),
        low_stock_count=(
            db.query(func.count(Product.id))
            .filter(
                Product.store_id == store.id,
                Product.is_active.is_(True),
                Product.min_stock > 0,
                Product.stock <= Product.min_stock,
            )
            .scalar()
            or 0
        ),
        pending_damage_count=(
            db.query(func.count(DamageReport.id))
            .filter(DamageReport.store_id == store.id, DamageReport.status == "PENDING")
            .scalar()
            or 0
        ),
        failed_sync_count_7d=(
            db.query(func.count(SyncEvent.id))
            .filter(
                SyncEvent.store_id == store.id,
                SyncEvent.status == "FAILED",
                SyncEvent.created_at >= admin_metrics._window_start(7),
            )
            .scalar()
            or 0
        ),
        total_sales=int(lifetime[0] or 0),
        lifetime_revenue=round(admin_metrics._f(lifetime[1]), 2),
    )


@router.get("/stores/{store_id}", response_model=StoreDetail)
def get_store(
    store_id: UUID,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    return _store_detail(db, get_store_or_404(db, store_id))


@router.patch("/stores/{store_id}", response_model=StoreDetail)
def patch_store(
    store_id: UUID,
    body: StoreUpdate,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    store = get_store_or_404(db, store_id)
    return _store_detail(db, update_store(db, store, body, owner, request))


@router.get("/stores/{store_id}/users", response_model=AdminUserListResponse)
def store_users(
    store_id: UUID,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    store = get_store_or_404(db, store_id)
    query = db.query(User).filter(User.store_id == store.id)
    total = query.count()
    rows = query.order_by(User.created_at.asc()).offset((page - 1) * page_size).limit(page_size).all()
    return AdminUserListResponse(
        items=[_user_item(u) for u in rows],
        meta=_page(page, page_size, total),
    )


@router.post("/stores/{store_id}/users", response_model=AdminUserItem, status_code=status.HTTP_201_CREATED)
def post_store_user(
    store_id: UUID,
    body: AdminUserCreate,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    store = get_store_or_404(db, store_id)
    user = create_store_user(
        db, store, body.username, body.password, body.full_name, body.role, owner, request
    )
    return _user_item(user)


def _user_item(user: User) -> AdminUserItem:
    return AdminUserItem(
        id=user.id,
        username=user.username,
        full_name=user.full_name,
        role=user.role,
        is_active=user.is_active,
        store_id=user.store_id,
        store_name=user.store_name,
        created_at=user.created_at,
    )


@router.get("/users", response_model=AdminUserListResponse)
def list_users(
    q: Optional[str] = Query(None, max_length=100),
    store_id: Optional[UUID] = None,
    role: Optional[str] = None,
    is_active: Optional[bool] = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    query = db.query(User).filter(User.role != UserRole.OWNER.value)
    if q:
        like = f"%{q.strip()}%"
        query = query.filter(
            or_(func.lower(User.username).like(like.lower()), func.lower(User.full_name).like(like.lower()))
        )
    if store_id is not None:
        query = query.filter(User.store_id == store_id)
    if role:
        query = query.filter(User.role == role)
    if is_active is not None:
        query = query.filter(User.is_active.is_(is_active))

    total = query.count()
    rows = query.order_by(User.created_at.desc()).offset((page - 1) * page_size).limit(page_size).all()
    return AdminUserListResponse(
        items=[_user_item(u) for u in rows],
        meta=_page(page, page_size, total),
    )


@router.patch("/users/{user_id}", response_model=AdminUserItem)
def patch_user(
    user_id: UUID,
    body: AdminUserUpdate,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    user = db.query(User).filter(User.id == user_id).first()
    if user is None or user.role == UserRole.OWNER.value:
        # OWNER tidak diatur dari sini: dashboard tidak boleh bisa mengunci
        # atau menurunkan akses dirinya sendiri lewat panel user toko.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User tidak ditemukan atau bukan user toko",
        )
    changes = body.model_dump(exclude_unset=True)
    updated = update_store_user(db, user, changes, owner, request)
    return _user_item(updated)


@router.post("/users/{user_id}/reset-password", response_model=PasswordResetResult)
def reset_password(
    user_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    user = db.query(User).filter(User.id == user_id, User.role != UserRole.OWNER.value).first()
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User tidak ditemukan")

    temporary = _make_temporary_password()
    user.password_hash = _hash(temporary)
    revoke_all_tokens(db, user)

    log_audit(
        db,
        owner,
        "USER_PASSWORD_RESET",
        "user",
        user.id,
        {"username": user.username, "store_id": str(user.store_id)},
        request,
    )
    return PasswordResetResult(
        user_id=user.id,
        username=user.username,
        temporary_password=temporary,
        message="Sandi sementara dibuat. Semua sesi user ini langsung keluar.",
    )


def _make_temporary_password() -> str:
    import secrets
    import string

    alphabet = string.ascii_letters + string.digits
    # huruf besar/kecil/angka dipaksakan supaya sandi sementara tidak
    # ditolak validator yang butuh kombinasi jenis karakter.
    while True:
        candidate = "Zo" + "".join(secrets.choice(alphabet) for _ in range(8))
        if (
            any(c.islower() for c in candidate)
            and any(c.isupper() for c in candidate)
            and any(c.isdigit() for c in candidate)
        ):
            return candidate


def _hash(password: str) -> str:
    from ..security import hash_password

    return hash_password(password)


@router.post("/users/{user_id}/force-logout", response_model=ForceLogoutResult)
def force_logout(
    user_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    user = db.query(User).filter(User.id == user_id, User.role != UserRole.OWNER.value).first()
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User tidak ditemukan")

    new_version = revoke_all_tokens(db, user)
    log_audit(
        db,
        owner,
        "USER_FORCE_LOGOUT",
        "user",
        user.id,
        {"username": user.username, "store_id": str(user.store_id), "token_version": new_version},
        request,
    )
    return ForceLogoutResult(
        user_id=user.id,
        username=user.username,
        token_version=new_version,
        message="Semua sesi user ini sudah dikeluarkan.",
    )


@router.post("/stores/{store_id}/impersonate", response_model=ImpersonateResult)
def impersonate(
    store_id: UUID,
    body: ImpersonateRequest,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    """Token baca-saja untuk melihat satu toko seperti POS-nya.

    Token memakai identitas BOS toko tersebut, jadi seluruh route POS sudah
    ter-scope dengan benar tanpa perlu endpoint bayangan. Yang membuatnya
    read-only adalah middleware write_guard di main.py.
    """
    store = get_store_or_404(db, store_id)
    if body.store_id != store.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="store_id tidak cocok")
    if not store.is_active or store.status != StoreStatus.ACTIVE:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Toko sedang tidak aktif, tidak bisa ditinjau",
        )

    bos = (
        db.query(User)
        .filter(
            User.store_id == store.id,
            User.role == UserRole.BOS.value,
            User.is_active.is_(True),
        )
        .order_by(User.created_at.asc())
        .first()
    )
    if bos is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Toko ini tidak punya BOS aktif, tidak ada identitas untuk ditinjau",
        )

    from ..config import settings

    token = create_impersonation_token(str(bos.id), bos.role, str(store.id), bos.token_version or 0)
    log_audit(
        db,
        owner,
        "IMPERSONATE_START",
        "store",
        store.id,
        {
            "store_code": store.code,
            "as_user": bos.username,
            "expires_in_minutes": settings.IMPERSONATION_EXPIRE_MINUTES,
        },
        request,
    )
    return ImpersonateResult(
        access_token=token,
        expires_in_minutes=settings.IMPERSONATION_EXPIRE_MINUTES,
        store=store.to_dict(),
    )


# --------------------------------------------------------------------------
# Broadcast
# --------------------------------------------------------------------------
def _naive_utc(value):
    """Samakan basis waktu sebelum disimpan ke kolom timestamp.

    Kolom starts_at dan expires_at bertipe timestamp tanpa zona waktu, sementara
    klien mengirim ISO ber-suffix Z, misalnya "2026-09-28T02:46:53.239Z". psycopg2
    mengubah datetime yang punya zona waktu menjadi waktu lokal mesin sebelum
    menulis, sehingga jam 02:46 UTC tersimpan sebagai 09:46 di zona +07:00.

    Semua perbandingan di kode ini memakai datetime.utcnow(). Kalau yang
    tersimpan memakai jam lokal, pengumuman yang baru dibuat terbaca "belum
    mulai" selama selisih zona waktu, dan pengumuman yang sudah lewat
    tidak pernah berhenti.

    Karena itu semua waktu dari klien dinormalkan ke UTC naive lebih dulu.
    """
    if value is None:
        return None
    if value.tzinfo is not None:
        return value.astimezone(timezone.utc).replace(tzinfo=None)
    return value


def _validate_broadcast_target(db: Session, target: str, store_id: Optional[UUID]) -> None:
    if target == BroadcastTarget.STORE:
        if store_id is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Broadcast per toko wajib menyertakan store_id",
            )
        get_store_or_404(db, store_id)
    elif store_id is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="store_id hanya boleh diisi bila target=STORE",
        )


@router.get("/broadcasts", response_model=BroadcastListResponse)
def list_broadcasts(
    is_active: Optional[bool] = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    query = db.query(Broadcast)
    if is_active is not None:
        query = query.filter(Broadcast.is_active.is_(is_active))
    total = query.count()
    rows = (
        query.order_by(Broadcast.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return BroadcastListResponse(
        items=[_broadcast_item(b) for b in rows],
        meta=_page(page, page_size, total),
    )


def _broadcast_item(b: Broadcast) -> BroadcastItem:
    return BroadcastItem(
        id=b.id,
        title=b.title,
        body=b.body,
        level=b.level,
        target=b.target,
        store_id=b.store_id,
        store_name=b.store.name if b.store else None,
        starts_at=b.starts_at,
        expires_at=b.expires_at,
        is_active=b.is_active,
        created_by=b.created_by,
        created_at=b.created_at,
    )


@router.post("/broadcasts", response_model=BroadcastItem, status_code=status.HTTP_201_CREATED)
def post_broadcast(
    request: Request,
    body: BroadcastCreate,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    _validate_broadcast_target(db, body.target, body.store_id)
    broadcast = Broadcast(
        title=body.title.strip(),
        body=body.body.strip(),
        level=body.level,
        target=body.target,
        store_id=body.store_id,
        starts_at=_naive_utc(body.starts_at) or datetime.utcnow(),
        expires_at=_naive_utc(body.expires_at),
        is_active=body.is_active,
        created_by=owner.id,
    )
    db.add(broadcast)
    db.commit()
    db.refresh(broadcast)
    log_audit(
        db,
        owner,
        "BROADCAST_CREATE",
        "broadcast",
        broadcast.id,
        {"title": broadcast.title, "target": broadcast.target, "store_id": str(broadcast.store_id)},
        request,
    )
    return _broadcast_item(broadcast)


@router.patch("/broadcasts/{broadcast_id}", response_model=BroadcastItem)
def patch_broadcast(
    broadcast_id: UUID,
    body: BroadcastUpdate,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    broadcast = db.query(Broadcast).filter(Broadcast.id == broadcast_id).first()
    if broadcast is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Broadcast tidak ditemukan")

    changes = body.model_dump(exclude_unset=True)
    target = changes.get("target", broadcast.target)
    store_id = changes.get("store_id", broadcast.store_id)
    if "store_id" in changes and store_id is None and target == BroadcastTarget.STORE:
        changes["target"] = BroadcastTarget.ALL
        target = BroadcastTarget.ALL
    _validate_broadcast_target(db, target, store_id)

    # Sama seperti pada pembuatan: normalkan dulu supaya perbandingan di bawah
    # dan kolomnya satu basis waktu.
    for field in ("starts_at", "expires_at"):
        if field in changes:
            changes[field] = _naive_utc(changes[field])

    starts_at = changes.get("starts_at", broadcast.starts_at)
    expires_at = changes.get("expires_at", broadcast.expires_at)
    if expires_at is not None and expires_at <= starts_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Waktu berakhir harus setelah waktu mulai",
        )

    for field, value in changes.items():
        setattr(broadcast, field, value)

    db.commit()
    db.refresh(broadcast)
    log_audit(db, owner, "BROADCAST_UPDATE", "broadcast", broadcast.id, {"changes": list(changes)}, request)
    return _broadcast_item(broadcast)


@router.delete("/broadcasts/{broadcast_id}")
def delete_broadcast(
    broadcast_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    broadcast = db.query(Broadcast).filter(Broadcast.id == broadcast_id).first()
    if broadcast is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Broadcast tidak ditemukan")
    # Nonaktifkan, bukan hapus: perangkat yang sedang offline masih menarik
    # lewat sync/pull, dan menghapus baris akan membuat banner hilang diam-diam
    # tanpa jejak kapan sebenarnya dicabut.
    broadcast.is_active = False
    db.commit()
    log_audit(
        db,
        owner,
        "BROADCAST_DEACTIVATE",
        "broadcast",
        broadcast.id,
        {"title": broadcast.title},
        request,
    )
    return {"ok": True, "id": str(broadcast.id)}


@router.delete("/broadcasts/{broadcast_id}/purge")
def purge_broadcast(
    broadcast_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    """Hapus permanen broadcast yang sudah dinonaktifkan.

    Menonaktifkan (`DELETE /broadcasts/{id}`) hanya menyembunyikan banner dari
    perangkat, tapi barisnya tetap menetap selamanya di daftar owner, jadi
    daftar itu lama-lama jadi penuh sisa pengumuman yang sudah tidak berlaku.
    Endpoint ini membersihkan sisanya.

    Broadcast yang masih aktif DITOLAK dihapus. Kalau baris hilang sementara
    perangkat sedang offline, banner yang sudah tayang hilang dari daftar tanpa
    ada jejak kapan dicabut, dan owner bisa mengira broadcast-nya tidak pernah
    terkirim. Menonaktifkan dulu, lalu hapus, jadi dua langkah itu selalu
    terlihat di audit log.
    """
    broadcast = db.query(Broadcast).filter(Broadcast.id == broadcast_id).first()
    if broadcast is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Broadcast tidak ditemukan")
    if broadcast.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Nonaktifkan dulu broadcast ini sebelum dihapus permanen.",
        )
    snapshot = {"title": broadcast.title, "store_id": broadcast.store_id}
    db.delete(broadcast)
    db.commit()
    log_audit(
        db,
        owner,
        "BROADCAST_DELETE",
        "broadcast",
        broadcast_id,
        snapshot,
        request,
    )
    return {"ok": True, "id": str(broadcast_id)}


# --------------------------------------------------------------------------
# Audit
# --------------------------------------------------------------------------
@router.get("/audit-logs", response_model=AuditLogListResponse)
def list_audit_logs(
    store_id: Optional[UUID] = None,
    user_id: Optional[UUID] = None,
    action: Optional[str] = Query(None, max_length=60),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    query = db.query(AuditLog)
    if store_id is not None:
        query = query.filter(AuditLog.store_id == store_id)
    if user_id is not None:
        query = query.filter(AuditLog.user_id == user_id)
    if action:
        query = query.filter(AuditLog.action == action)

    total = query.count()
    rows = (
        query.order_by(AuditLog.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )

    users = {
        u.id: u
        for u in db.query(User)
        .filter(User.id.in_([r.user_id for r in rows if r.user_id]))
        .all()
    }
    stores = {
        s.id: s
        for s in db.query(Store)
        .filter(Store.id.in_([r.store_id for r in rows if r.store_id]))
        .all()
    }

    items = []
    for row in rows:
        actor = users.get(row.user_id)
        store = stores.get(row.store_id)
        items.append(
            AuditLogItem(
                id=row.id,
                user_id=row.user_id,
                username=actor.username if actor else None,
                store_id=row.store_id,
                store_name=store.name if store else None,
                action=row.action,
                entity_type=row.entity_type,
                entity_id=row.entity_id,
                details=row.details,
                ip_address=row.ip_address,
                created_at=row.created_at,
            )
        )
    return AuditLogListResponse(items=items, meta=_page(page, page_size, total))


# --- Transaksi toko: koreksi data salah input oleh OWNER -----------------------
#
# Stok dikoreksi otomatis: item lama dikembalikan (RETURN), item baru dipotong
# (SALE). Keduanya dicatat sebagai StockMovement dengan reference_type
# sale_edit_old / sale_edit sehingga ledger tetap bisa diaudit mundur.
# Seluruh edit diproses dalam satu transaksi; kalau satu item gagal (stok baru
# tidak cukup, produk nonaktif), semuanya ikut rollback.


def _apply_stock(
    db: Session,
    product: Product,
    movement_type: str,
    quantity: float,
    user: User,
    reference_id,
    reference_type: str,
    notes: str,
):
    """Mirror record_stock_movement TANPA commit: commit dilakukan sekali di
    akhir edit supaya koreksi transaksi bersifat atomik."""
    stock_before = float(product.stock or 0)
    if movement_type in ("SALE", "DAMAGE", "ADJUSTMENT_NEGATIVE", "RETURN_OUT"):
        stock_after = stock_before - quantity
        if stock_after < 0:
            raise InsufficientStockError(
                f"Stok tidak mencukupi. Tersedia {stock_before}, diminta {quantity}"
            )
    else:
        stock_after = stock_before + quantity
    product.stock = stock_after
    db.add(
        StockMovement(
            product_id=product.id,
            movement_type=movement_type,
            quantity=quantity,
            stock_before=stock_before,
            stock_after=stock_after,
            reference_id=reference_id,
            reference_type=reference_type,
            notes=notes,
            user_id=user.id,
            # Milik toko produk, bukan toko actor (OWNER lintas-toko).
            store_id=product.store_id,
            created_at=datetime.utcnow(),
        )
    )


def _get_store_sale_or_404(db: Session, store_id: UUID, sale_id: UUID) -> Sale:
    sale = (
        db.query(Sale)
        .options(
            joinedload(Sale.employee),
            joinedload(Sale.sale_items),
            joinedload(Sale.payment),
        )
        .filter(Sale.id == sale_id, Sale.store_id == store_id)
        .first()
    )
    if not sale:
        raise HTTPException(status_code=404, detail="Transaksi tidak ditemukan")
    return sale


def _sale_edit_snapshot(sale: Sale) -> dict:
    """Ringkasan isi transaksi untuk jejak audit sebelum/sesudah edit."""
    return {
        "total_amount": float(sale.total_amount),
        "total_modal": float(sale.total_modal),
        "total_profit": float(sale.total_profit),
        "discount": float(sale.discount),
        "items": [
            {
                "product_name": it.product_name,
                "quantity": float(it.quantity),
                "unit_price": float(it.unit_price),
                "subtotal": float(it.subtotal),
            }
            for it in sale.sale_items
        ],
        "payment": (
            {
                "method": sale.payment.method,
                "amount": float(sale.payment.amount),
                "reference": sale.payment.reference,
            }
            if sale.payment
            else None
        ),
    }


def _sale_edit_history(db: Session, sale: Sale) -> list:
    # OWNER lintas-toko: log_audit menyimpan store_id=NULL untuk actor owner,
    # jadi riwayat difilter via entity_id (UUID sale, unik global), bukan store.
    rows = (
        db.query(AuditLog)
        .filter(
            AuditLog.action.in_(["SALE_EDIT", "SALE_DELETE"]),
            AuditLog.entity_id == str(sale.id),
        )
        .order_by(AuditLog.created_at.desc())
        .all()
    )
    users = {
        u.id: u
        for u in db.query(User)
        .filter(User.id.in_([r.user_id for r in rows if r.user_id]))
        .all()
    }
    return [
        AuditLogItem(
            id=r.id,
            user_id=r.user_id,
            username=users.get(r.user_id).username if users.get(r.user_id) else None,
            store_id=r.store_id,
            store_name=None,
            action=r.action,
            entity_type=r.entity_type,
            entity_id=r.entity_id,
            details=r.details,
            ip_address=r.ip_address,
            created_at=r.created_at,
        )
        for r in rows
    ]


def _as_admin_sale_detail(db: Session, sale: Sale) -> AdminSaleDetail:
    return AdminSaleDetail(
        id=sale.id,
        store_id=sale.store_id,
        transaction_number=sale.transaction_number,
        employee_id=sale.employee_id,
        employee_name=sale.employee.full_name if sale.employee else None,
        total_amount=float(sale.total_amount),
        total_modal=float(sale.total_modal),
        total_profit=float(sale.total_profit),
        discount=float(sale.discount),
        status=sale.status,
        canceled_at=iso_utc(sale.canceled_at),
        canceled_by=sale.canceled_by,
        canceled_reason=sale.canceled_reason,
        created_at=iso_utc(sale.created_at),
        updated_at=iso_utc(sale.updated_at),
        items=[it.to_dict() for it in sale.sale_items],
        payment=sale.payment.to_dict() if sale.payment else None,
        edit_history=_sale_edit_history(db, sale),
    )


@router.get("/stores/{store_id}/products", response_model=StoreProductListResponse)
def store_products(
    store_id: UUID,
    q: Optional[str] = Query(None, max_length=100),
    is_active: Optional[bool] = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    get_store_or_404(db, store_id)
    query = db.query(Product).filter(Product.store_id == store_id)
    if q:
        query = query.filter(Product.name.ilike(f"%{q}%"))
    if is_active is not None:
        query = query.filter(Product.is_active.is_(is_active))
    total = query.count()
    rows = (
        query.order_by(Product.name.asc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return StoreProductListResponse(
        items=[
            StoreProductItem(
                id=p.id,
                store_id=p.store_id,
                name=p.name,
                category_name=p.category.name if p.category else None,
                unit=p.unit,
                modal_price=float(p.modal_price or 0),
                selling_price=float(p.selling_price or 0),
                stock=float(p.stock or 0),
                is_active=bool(p.is_active),
            )
            for p in rows
        ],
        meta=_page(page, page_size, total),
    )


@router.get("/stores/{store_id}/sales", response_model=AdminSaleListResponse)
def store_sales(
    store_id: UUID,
    trx_status: Optional[str] = Query(None, max_length=20),
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    q: Optional[str] = Query(None, max_length=100),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    """Daftar transaksi toko.

    Pencarian dan rentang tanggal ditambahkan supaya seragam dengan tab lain
    di Data Browser. Tanpa keduanya, memverifikasi satu transaksi berarti
    membuka seluruh halaman satu per satu -- dan karena urutannya berdasarkan
    waktu, transaksi yang dicari bisa berada di halaman mana saja.
    """
    get_store_or_404(db, store_id)
    query = db.query(Sale).filter(Sale.store_id == store_id)
    if trx_status in ("COMPLETED", "CANCELED"):
        query = query.filter(Sale.status == trx_status)
    query = _apply_created_range(query, Sale.created_at, date_from, date_to)
    if q:
        query = query.filter(Sale.transaction_number.ilike(f"%{q}%"))
    total = query.count()
    rows = (
        query.options(joinedload(Sale.employee), joinedload(Sale.sale_items))
        .order_by(Sale.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    items = [
        AdminSaleListItem(
            id=s.id,
            store_id=s.store_id,
            transaction_number=s.transaction_number,
            employee_id=s.employee_id,
            employee_name=s.employee.full_name if s.employee else None,
            total_amount=float(s.total_amount),
            total_modal=float(s.total_modal),
            total_profit=float(s.total_profit),
            discount=float(s.discount),
            status=s.status,
            canceled_at=iso_utc(s.canceled_at),
            canceled_by=s.canceled_by,
            canceled_reason=s.canceled_reason,
            created_at=iso_utc(s.created_at),
            updated_at=iso_utc(s.updated_at),
            item_count=len(s.sale_items),
        )
        for s in rows
    ]
    return AdminSaleListResponse(items=items, meta=_page(page, page_size, total))


@router.get("/stores/{store_id}/sales/{sale_id}", response_model=AdminSaleDetail)
def store_sale_detail(
    store_id: UUID,
    sale_id: UUID,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    sale = _get_store_sale_or_404(db, store_id, sale_id)
    return _as_admin_sale_detail(db, sale)


@router.patch("/stores/{store_id}/sales/{sale_id}", response_model=AdminSaleDetail)
def edit_store_sale(
    store_id: UUID,
    sale_id: UUID,
    body: SaleEditRequest,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    sale = _get_store_sale_or_404(db, store_id, sale_id)
    if sale.status != "COMPLETED":
        raise HTTPException(
            status_code=400, detail="Hanya transaksi berstatus selesai yang bisa diedit"
        )

    before = _sale_edit_snapshot(sale)

    # Kembalikan stok item lama.
    for item in sale.sale_items:
        product = db.query(Product).filter(
            Product.id == item.product_id, Product.store_id == store_id
        ).first()
        if product is not None:
            _apply_stock(
                db, product, "RETURN", float(item.quantity), owner,
                sale.id, "sale_edit_old",
                f"Koreksi transaksi {sale.transaction_number}",
            )

    db.query(SaleItem).filter(SaleItem.sale_id == sale.id).delete(
        synchronize_session=False
    )

    total_amount = 0
    total_modal = 0
    new_items = []
    try:
        for item in body.items:
            product = db.query(Product).filter(
                Product.id == item.product_id, Product.store_id == store_id
            ).first()
            if not product:
                raise HTTPException(status_code=404, detail="Produk tidak ditemukan")
            if not product.is_active:
                raise HTTPException(
                    status_code=400, detail=f"Produk {product.name} tidak aktif"
                )

            subtotal = round(item.unit_price * item.quantity, 2)
            modal_total = round(float(product.modal_price or 0) * item.quantity, 2)
            total_amount += subtotal
            total_modal += modal_total

            _apply_stock(
                db, product, "SALE", item.quantity, owner,
                sale.id, "sale_edit",
                f"Koreksi transaksi {sale.transaction_number}",
            )

            new_items.append(
                SaleItem(
                    sale_id=sale.id,
                    product_id=product.id,
                    product_name=product.name,
                    unit=product.unit,
                    unit_price=item.unit_price,
                    modal_price=float(product.modal_price or 0),
                    quantity=item.quantity,
                    subtotal=subtotal,
                )
            )
    except InsufficientStockError as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e))

    if body.discount:
        total_amount = max(0, total_amount - body.discount)
    sale.total_amount = total_amount
    sale.total_modal = total_modal
    sale.total_profit = round(total_amount - total_modal, 2)
    sale.discount = body.discount or 0
    sale.updated_at = datetime.utcnow()

    for ni in new_items:
        db.add(ni)

    payment = sale.payment
    if body.payment:
        if payment is None:
            payment = Payment(sale_id=sale.id)
            db.add(payment)
            db.flush()
        payment.method = body.payment.method
        payment.amount = body.payment.amount
        payment.cash_received = body.payment.cash_received
        payment.change_amount = body.payment.change_amount
        payment.reference = body.payment.reference

    db.commit()
    db.refresh(sale)
    log_audit(
        db, owner, "SALE_EDIT", "sale", sale.id,
        {
            "transaction_number": sale.transaction_number,
            "reason": body.reason,
            "before": before,
            "after": _sale_edit_snapshot(sale),
        },
        request,
    )
    return _as_admin_sale_detail(db, sale)


@router.post("/stores/{store_id}/sales/{sale_id}/delete", response_model=AdminSaleDetail)
def delete_store_sale(
    store_id: UUID,
    sale_id: UUID,
    body: SaleDeleteRequest,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    """Hapus (soft) transaksi oleh owner: status jadi batal, stok kembali.

    Bukan penghapusan fisik — riwayat, laporan, dan audit tetap ada supaya bisa
    dikontrol/kontrol. Mirip cancel milik BOS, tapi dicatat sebagai SALE_DELETE
    dan boleh ditarik kembali tanpa syarat jam. Fisik yang "hilang" hanya dari
    statistik: seluruh KPI owner memfilter status COMPLETED."""
    sale = _get_store_sale_or_404(db, store_id, sale_id)
    if sale.status != "COMPLETED":
        raise HTTPException(
            status_code=400, detail="Hanya transaksi berstatus selesai yang bisa dihapus"
        )

    before = _sale_edit_snapshot(sale)

    # Kembalikan stok item transaksi ke gudang, satu transaksi atomik.
    for item in sale.sale_items:
        product = db.query(Product).filter(
            Product.id == item.product_id, Product.store_id == store_id
        ).first()
        if product is not None:
            _apply_stock(
                db, product, "RETURN", float(item.quantity), owner,
                sale.id, "sale_delete",
                f"Hapus transaksi {sale.transaction_number}",
            )

    sale.status = "CANCELED"
    sale.canceled_at = datetime.utcnow()
    sale.canceled_by = owner.id
    sale.canceled_reason = body.reason
    sale.updated_at = datetime.utcnow()

    db.commit()
    db.refresh(sale)
    log_audit(
        db, owner, "SALE_DELETE", "sale", sale.id,
        {
            "transaction_number": sale.transaction_number,
            "reason": body.reason,
            "before": before,
            "after": _sale_edit_snapshot(sale),
        },
        request,
    )
    return _as_admin_sale_detail(db, sale)


# --------------------------------------------------------------------------
# Data Browser per toko
# --------------------------------------------------------------------------
# Endpoint di blok ini hanya MEMBACA. Satu-satunya endpoint yang mengubah
# state adalah persetujuan barang rusak di bagian akhir blok ini.
#
# Semuanya memakai pola yang sama: get_store_or_404 lebih dulu, baru filter
# dengan store_id dari path. Pengecekan toko bukan opsional di sini -- tanpa
# itu, satu UUID toko cukup untuk membaca seluruh data toko lain.

_PRODUCT_ACTIONS = (
    "PRODUCT_CREATE",
    "PRODUCT_UPDATE",
    "PRODUCT_DEACTIVATE",
    "PRODUCT_REACTIVATE",
    "PRODUCT_PHOTO_UPLOAD",
    "PRODUCT_PHOTO_DELETE",
)


def _apply_created_range(query, column, date_from, date_to):
    """Batas tanggal inklusif per hari.

    Kolom created_at disimpan sebagai UTC naive (datetime.utcnow tanpa
    tzinfo), sedangkan parameter tanggal dari query string tidak pernah punya
    timezone. Membandingkan keduanya secara langsung akan menggeser hasil
    sebesar selisih zona waktu lokal.

    Batas atas memakai < (tanggal + 1 hari), bukan <= tanggal. Dengan <=,
    semua transaksi setelah jam 00:00 pada tanggal akhir akan hilang.
    """
    if date_from is not None:
        start = datetime(date_from.year, date_from.month, date_from.day)
        query = query.filter(column >= start)
    if date_to is not None:
        end_exclusive = datetime(date_to.year, date_to.month, date_to.day)
        query = query.filter(column < end_exclusive + timedelta(days=1))
    return query


def _user_names(db, user_ids):
    """Nama pelaku untuk sekumpulan user_id, satu query.

    Meload per baris berarti satu query tambahan untuk setiap baris tabel.
    Di halaman berisi 200 baris, itu 200 request ke database hanya untuk
    menampilkan nama.
    """
    ids = [u for u in set(user_ids) if u]
    if not ids:
        return {}
    return {
        u.id: (u.full_name or u.username)
        for u in db.query(User).filter(User.id.in_(ids)).all()
    }


def _damage_photo_url(report):
    for photo in report.photos:
        if photo.file_url:
            return photo.file_url
        if photo.file_path:
            return storage.url_for(photo.file_path)
    return None


def _damage_item(db, report) -> DamageReportItem:
    """Bentuk satu laporan untuk respons.

    Daftar dan aksi setujui/tolak memakai helper yang sama supaya kolomnya
    tidak bisa berbeda. Kalau keduanya dirangkai sendiri, perm approving
    akan mengembalikan bentuk berbeda dari yang digambar tabel di layar.
    """
    actors = _user_names(
        db, [report.employee_id, report.approved_by, report.rejected_by]
    )
    return DamageReportItem(
        id=report.id,
        store_id=report.store_id,
        product_id=report.product_id,
        product_name=report.product.name if report.product else None,
        quantity=float(report.quantity or 0),
        unit=report.unit,
        qty_in_base_unit=(
            float(report.qty_in_base_unit) if report.qty_in_base_unit is not None else None
        ),
        reason=report.reason,
        description=report.description,
        status=report.status,
        employee_id=report.employee_id,
        employee_name=actors.get(report.employee_id),
        approved_by_name=actors.get(report.approved_by) if report.approved_by else None,
        approved_at=iso_utc(report.approved_at),
        rejected_by_name=actors.get(report.rejected_by) if report.rejected_by else None,
        rejected_at=iso_utc(report.rejected_at),
        rejection_reason=report.rejection_reason,
        photos=[u for u in [_damage_photo_url(report)] if u],
        created_at=iso_utc(report.created_at),
    )


@router.get("/stores/{store_id}/damage-reports", response_model=DamageReportListResponse)
def store_damage_reports(
    store_id: UUID,
    status: Optional[str] = Query(None, max_length=20),
    reason: Optional[str] = Query(None, max_length=50),
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    q: Optional[str] = Query(None, max_length=100),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    get_store_or_404(db, store_id)

    query = db.query(DamageReport).filter(DamageReport.store_id == store_id)
    if status in ("PENDING", "APPROVED", "REJECTED"):
        query = query.filter(DamageReport.status == status)
    if reason:
        query = query.filter(DamageReport.reason == reason)
    query = _apply_created_range(query, DamageReport.created_at, date_from, date_to)

    if q:
        query = query.outerjoin(Product, DamageReport.product_id == Product.id)
        like = f"%{q}%"
        query = query.filter(
            or_(
                Product.name.ilike(like),
                DamageReport.description.ilike(like),
                DamageReport.reason.ilike(like),
            )
        )

    total = query.count()
    rows = (
        query.options(
            joinedload(DamageReport.product),
            joinedload(DamageReport.employee),
            joinedload(DamageReport.photos),
        )
        .order_by(DamageReport.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )

    items = [_damage_item(db, r) for r in rows]

    # Ringkasan dihitung dari seluruh laporan toko, bukan dari baris halaman
    # ini. Kalau dihitung dari rows, angkanya akan ikut berubah setiap kali
    # pengguna pindah halaman atau mengganti filter.
    counts = dict(
        db.query(DamageReport.status, func.count(DamageReport.id))
        .filter(DamageReport.store_id == store_id)
        .group_by(DamageReport.status)
        .all()
    )
    return DamageReportListResponse(
        items=items,
        meta=_page(page, page_size, total),
        summary={
            "total": sum(counts.values()),
            "pending": counts.get("PENDING", 0),
            "approved": counts.get("APPROVED", 0),
            "rejected": counts.get("REJECTED", 0),
        },
    )


@router.get("/stores/{store_id}/stock-movements", response_model=StockMovementListResponse)
def store_stock_movements(
    store_id: UUID,
    movement_type: Optional[str] = Query(None, max_length=20),
    product_id: Optional[UUID] = None,
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    q: Optional[str] = Query(None, max_length=100),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    get_store_or_404(db, store_id)

    query = db.query(StockMovement).filter(StockMovement.store_id == store_id)
    if movement_type:
        query = query.filter(StockMovement.movement_type == movement_type)
    if product_id is not None:
        query = query.filter(StockMovement.product_id == product_id)
    query = _apply_created_range(query, StockMovement.created_at, date_from, date_to)

    if q:
        query = query.outerjoin(Product, StockMovement.product_id == Product.id)
        like = f"%{q}%"
        query = query.filter(
            or_(Product.name.ilike(like), StockMovement.notes.ilike(like))
        )

    total = query.count()
    rows = (
        query.options(joinedload(StockMovement.product))
        .order_by(StockMovement.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    actors = _user_names(db, [r.user_id for r in rows])

    items = [
        StockMovementItem(
            id=r.id,
            product_id=r.product_id,
            product_name=r.product.name if r.product else None,
            movement_type=r.movement_type,
            quantity=float(r.quantity or 0),
            stock_before=float(r.stock_before or 0),
            stock_after=float(r.stock_after or 0),
            reference_type=r.reference_type,
            notes=r.notes,
            user_name=actors.get(r.user_id),
            created_at=iso_utc(r.created_at),
        )
        for r in rows
    ]

    per_type = (
        db.query(
            StockMovement.movement_type,
            func.count(StockMovement.id),
            func.coalesce(func.sum(StockMovement.quantity), 0),
        )
        .filter(StockMovement.store_id == store_id)
        .group_by(StockMovement.movement_type)
        .all()
    )

    def _sum_of(kind):
        return sum(float(qt) for t, _, qt in per_type if t == kind)

    return StockMovementListResponse(
        items=items,
        meta=_page(page, page_size, total),
        summary={
            "total_movements": sum(int(c) for _, c, _ in per_type),
            "in": _sum_of("IN"),
            "out": _sum_of("OUT"),
            "sale": _sum_of("SALE"),
            "opening": _sum_of("OPENING"),
            "adjustment": _sum_of("ADJUSTMENT"),
            "damage": _sum_of("DAMAGE"),
        },
    )


@router.get("/stores/{store_id}/payments", response_model=PaymentListResponse)
def store_payments(
    store_id: UUID,
    method: Optional[str] = Query(None, max_length=20),
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    q: Optional[str] = Query(None, max_length=100),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    get_store_or_404(db, store_id)

    # Payment tidak punya kolom store_id sendiri, jadi kepemilikannya mengikuti
    # Sale. Join ke Sale bukan cuma untuk menampilkan nomor transaksi --
    # tanpa filter Sale.store_id, endpoint ini bisa membaca pembayaran toko
    # mana pun hanya dengan menebak sale_id.
    query = (
        db.query(Payment, Sale)
        .join(Sale, Payment.sale_id == Sale.id)
        .filter(Sale.store_id == store_id)
    )
    if method:
        query = query.filter(Payment.method == method)
    query = _apply_created_range(query, Payment.created_at, date_from, date_to)
    if q:
        query = query.filter(Sale.transaction_number.ilike(f"%{q}%"))

    total = query.count()
    rows = (
        query.options(joinedload(Payment.sale))
        .order_by(Payment.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    actors = _user_names(db, [p.sale.employee_id for p, _ in rows if p.sale])

    items = [
        PaymentItem(
            id=p.id,
            sale_id=p.sale_id,
            transaction_number=p.sale.transaction_number if p.sale else None,
            method=p.method,
            amount=float(p.amount or 0),
            cash_received=(
                float(p.cash_received) if p.cash_received is not None else None
            ),
            change_amount=(
                float(p.change_amount) if p.change_amount is not None else None
            ),
            reference=p.reference,
            file_url=p.file_url,
            employee_name=actors.get(p.sale.employee_id) if p.sale else None,
            sale_status=p.sale.status if p.sale else None,
            created_at=iso_utc(p.created_at),
        )
        for p, _ in rows
    ]

    per_method = (
        db.query(
            Payment.method,
            func.coalesce(func.sum(Payment.amount), 0),
            func.count(Payment.id),
        )
        .join(Sale, Payment.sale_id == Sale.id)
        .filter(Sale.store_id == store_id)
        .group_by(Payment.method)
        .all()
    )
    return PaymentListResponse(
        items=items,
        meta=_page(page, page_size, total),
        summary={
            "total_amount": sum(float(v) for _, v, _ in per_method),
            "total_payments": sum(int(c) for _, _, c in per_method),
            "by_method": {m: float(v) for m, v, _ in per_method},
        },
    )


@router.get("/stores/{store_id}/product-history", response_model=ProductHistoryResponse)
def store_product_history(
    store_id: UUID,
    action: Optional[str] = Query(None, max_length=60),
    date_from: Optional[date] = None,
    date_to: Optional[date] = None,
    q: Optional[str] = Query(None, max_length=100),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    """Riwayat tambah dan ubah produk.

    Sumbernya audit_logs, bukan tabel produk. Tabel products tidak menyimpan
    siapa yang membuat produk atau kapan terakhir diubah, jadi pertanyaan
    "barang ini siapa yang tambahkan" tidak bisa dijawab dari sana.

    Keterbatasan yang perlu diketahui: audit_logs.store_id mengikuti store_id
    pelaku. Bila owner platform melakukan aksinya sendiri, store_id-nya NULL
    dan baris itu tidak muncul di riwayat toko mana pun. Aksi produk saat
    ini seluruhnya dilakukan BOS atau karyawan toko, jadi belum jadi
    masalah -- tapi akan jadi begitu owner bisa menambah produk dari console.
    """
    get_store_or_404(db, store_id)

    query = db.query(AuditLog).filter(
        AuditLog.store_id == store_id,
        AuditLog.action.in_(_PRODUCT_ACTIONS),
    )
    if action:
        query = query.filter(AuditLog.action == action)
    query = _apply_created_range(query, AuditLog.created_at, date_from, date_to)
    if q:
        like = f"%{q}%"
        query = query.filter(
            or_(
                AuditLog.details.ilike(like),
                AuditLog.entity_id.ilike(like),
            )
        )

    total = query.count()
    rows = (
        query.order_by(AuditLog.created_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    actors = _user_names(db, [r.user_id for r in rows])

    items = []
    for r in rows:
        details = None
        if r.details:
            try:
                details = json.loads(r.details)
            except (ValueError, TypeError):
                details = {"raw": r.details}
        name = None
        if isinstance(details, dict):
            name = details.get("name")
            changes = details.get("changes")
            if name is None and isinstance(changes, dict):
                name = changes.get("name")
        items.append(
            ProductHistoryItem(
                id=r.id,
                action=r.action,
                product_id=r.entity_id,
                product_name=name,
                details=details,
                user_name=actors.get(r.user_id),
                ip_address=r.ip_address,
                created_at=iso_utc(r.created_at),
            )
        )
    return ProductHistoryResponse(items=items, meta=_page(page, page_size, total))


@router.get("/stores/{store_id}/categories", response_model=CategoryListResponse)
def store_categories(
    store_id: UUID,
    q: Optional[str] = Query(None, max_length=100),
    is_active: Optional[bool] = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    get_store_or_404(db, store_id)

    query = db.query(Category).filter(Category.store_id == store_id)
    if q:
        query = query.filter(Category.name.ilike(f"%{q}%"))
    if is_active is not None:
        query = query.filter(Category.is_active.is_(is_active))

    total = query.count()
    rows = (
        query.order_by(Category.name.asc())
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )

    # Jumlah produk per kategori dihitung satu query agregat, bukan satu COUNT
    # per kategori. Versi per-kategori mengulang query sebanyak jumlah baris.
    counts = dict(
        db.query(Product.category_id, func.count(Product.id))
        .filter(
            Product.store_id == store_id,
            Product.category_id.isnot(None),
        )
        .group_by(Product.category_id)
        .all()
    )

    items = [
        CategoryItem(
            id=c.id,
            name=c.name,
            description=c.description,
            is_active=bool(c.is_active),
            product_count=int(counts.get(c.id, 0)),
            created_at=iso_utc(c.created_at),
        )
        for c in rows
    ]
    return CategoryListResponse(items=items, meta=_page(page, page_size, total))

# --------------------------------------------------------------------------
# Persetujuan barang rusak dari Owner Console
# --------------------------------------------------------------------------
# Dua endpoint di bawah ini memanggil damage_service yang sama dengan yang
# dipakai aplikasi POS. Bedanya hanya siapa yang boleh memanggil dan AuditLog
# mana yang ditulis, bukan logikanya.
#
# Kenapa bukan langsung memanggil route POS: route itu memakai
# require_bos() dan mengambil store_id dari user. Owner platform punya
# store_id NULL, jadi tidak akan pernah cocok dengan store_id di path --
# setiap permintaan akan berakhir 404.


def _damage_report_for_store(db: Session, store_id: UUID, report_id: UUID) -> DamageReport:
    """    Laporan yang store_id-nya sama dengan toko di path.

    store_id ikut jadi filter, bukan hanya report_id. Tanpa itu, owner bisa
    menyetujui laporan toko A dengan menyebut ID-nya di path toko B, dan stok
    toko A berkurang tanpa pernah ditanyakan ke anyone.
    """
    report = db.query(DamageReport).filter(
        DamageReport.id == report_id,
        DamageReport.store_id == store_id,
    ).first()
    if not report:
        raise HTTPException(status_code=404, detail="Laporan tidak ditemukan")
    return report


@router.post(
    "/stores/{store_id}/damage-reports/{report_id}/approve",
    response_model=DamageReportItem,
)
def admin_approve_damage_report(
    store_id: UUID,
    report_id: UUID,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    get_store_or_404(db, store_id)
    report = _damage_report_for_store(db, store_id, report_id)
    try:
        approve_core(
            db,
            report,
            owner,
            audit_action="DAMAGE_REPORT_APPROVE_ADMIN",
            request=request,
        )
    except HTTPException:
        # approve_core sudah menolak sebelum menyentuh stok kalau statusnya
        # bukan PENDING atau produknya hilang. Rollback di sini memastikan
        # sesi bersih untuk permintaan berikutnya.
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(exc))
    return _damage_item(db, report)


@router.post(
    "/stores/{store_id}/damage-reports/{report_id}/reject",
    response_model=DamageReportItem,
)
def admin_reject_damage_report(
    store_id: UUID,
    report_id: UUID,
    body: DamageReportReject,
    request: Request,
    db: Session = Depends(get_db),
    owner: User = Depends(require_owner()),
):
    get_store_or_404(db, store_id)
    report = _damage_report_for_store(db, store_id, report_id)
    reject_core(
        db,
        report,
        owner,
        reason=body.reason,
        audit_action="DAMAGE_REPORT_REJECT_ADMIN",
        request=request,
    )
    return _damage_item(db, report)
