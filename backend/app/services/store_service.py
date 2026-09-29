"""Operasi administersi toko milik OWNER: onboarding, ubah paket, status.

Aturan yang dijaga modul ini:
  - Satu transaksi database per operasi. Gagal di tengah tidak boleh meninggalkan
    toko tanpa BOS atau setengah kategori.
  - Onboarding selalu membuat user BOS pertama, karena tanpa BOS toko tidak
    bisa dipakai dan tidak ada yang bisa masuk untuk membuat user lain.
  - Tidak ada satu pun operasi yang menerima user toko. Semua lewat OWNER.
"""
from datetime import date
from typing import Optional
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..models.category import Category
from ..models.sale import Sale
from ..models.store import Plan, Store, StoreStatus
from ..models.user import User, UserRole
from ..schemas.admin import StoreCreate, StoreUpdate
from ..security import hash_password, log_audit, revoke_all_tokens


class OnboardingError(HTTPException):
    """Kegagalan onboarding. 400 karena input/konflik, bukan bug server."""


def _code_taken(db: Session, code: str, exclude_id: Optional[UUID] = None) -> bool:
    q = db.query(Store.id).filter(func.upper(Store.code) == code)
    if exclude_id is not None:
        q = q.filter(Store.id != exclude_id)
    return q.first() is not None


def _username_taken(db: Session, username: str) -> bool:
    return db.query(User.id).filter(User.username == username).first() is not None


def get_store_or_404(db: Session, store_id: UUID) -> Store:
    store = db.query(Store).filter(Store.id == store_id).first()
    if store is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Toko tidak ditemukan",
        )
    return store


def create_store(
    db: Session,
    payload: StoreCreate,
    actor: User,
    request=None,
) -> Store:
    """Daftarkan toko baru lengkap dengan BOS pertama dan kategorinya."""
    if _code_taken(db, payload.code):
        raise OnboardingError(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Kode toko '{payload.code}' sudah dipakai",
        )
    if _username_taken(db, payload.bos_username):
        raise OnboardingError(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Username '{payload.bos_username}' sudah dipakai",
        )

    store = Store(
        code=payload.code,
        name=payload.name.strip(),
        owner_name=payload.owner_name.strip(),
        phone=payload.phone,
        address=payload.address,
        plan=payload.plan,
        plan_expires_at=payload.plan_expires_at,
        status=payload.status,
        is_active=True,
    )
    db.add(store)
    # flush, bukan commit: butuh id toko untuk BOS dan kategori, tapi
    # perubahan belum harus terlihat sebelum seluruh operasi sukses.
    db.flush()

    bos = User(
        username=payload.bos_username.strip(),
        password_hash=hash_password(payload.bos_password),
        full_name=payload.bos_full_name.strip(),
        role=UserRole.BOS.value,
        is_active=True,
        store_id=store.id,
    )
    db.add(bos)

    for name in payload.category_names:
        db.add(Category(name=name, store_id=store.id))

    try:
        db.commit()
    except Exception:
        db.rollback()
        raise

    db.refresh(store)

    log_audit(
        db,
        actor,
        "STORE_CREATE",
        "store",
        store.id,
        {
            "code": store.code,
            "name": store.name,
            "plan": store.plan,
            "bos_username": bos.username,
            "category_count": len(payload.category_names),
        },
        request,
    )
    return store


def update_store(
    db: Session,
    store: Store,
    payload: StoreUpdate,
    actor: User,
    request=None,
) -> Store:
    changes = payload.model_dump(exclude_unset=True)
    if not changes:
        return store

    for field in ("name", "owner_name"):
        if field in changes and changes[field]:
            changes[field] = changes[field].strip()

    if "plan" in changes and changes["plan"] == Plan.UNLIMITED:
        # Paket tak terbatas tidak punya tanggal habis. Meninggalkan tanggal
        # lama membuat hari_to_expiry() masih melaporkan sisa hari yang salah.
        changes["plan_expires_at"] = None

    if "plan" in changes and changes["plan"] != Plan.UNLIMITED:
        # Beralih dari unlimited ke paket berbayar tanpa tanggal berarti
        # langganan langsung dianggap kedaluwarsa.
        if store.plan == Plan.UNLIMITED and changes.get("plan_expires_at") is None:
            changes.setdefault("plan_expires_at", date.today())

    before = {
        "plan": store.plan,
        "plan_expires_at": store.plan_expires_at.isoformat() if store.plan_expires_at else None,
        "status": store.status,
        "is_active": store.is_active,
    }

    for field, value in changes.items():
        setattr(store, field, value)

    try:
        db.commit()
    except Exception:
        db.rollback()
        raise
    db.refresh(store)

    after = {
        "plan": store.plan,
        "plan_expires_at": store.plan_expires_at.isoformat() if store.plan_expires_at else None,
        "status": store.status,
        "is_active": store.is_active,
    }

    # Menonaktifkan toko harus decided lewat status, bukan is_active saja:
    # POS membaca status, jadi is_active=False dengan status ACTIVE membuat
    # aplikasi tetap bisa dipakai. Selaraskan keduanya.
    if after["is_active"] is False and after["status"] == StoreStatus.ACTIVE:
        store.status = StoreStatus.SUSPENDED
        db.commit()
        after["status"] = store.status
    elif after["is_active"] is True and after["status"] == StoreStatus.SUSPENDED:
        store.status = StoreStatus.ACTIVE
        db.commit()
        after["status"] = store.status

    log_audit(
        db,
        actor,
        "STORE_UPDATE",
        "store",
        store.id,
        {"before": before, "after": after},
        request,
    )
    return store


def create_store_user(
    db: Session,
    store: Store,
    username: str,
    password: str,
    full_name: str,
    role: str,
    actor: User,
    request=None,
) -> User:
    username = username.strip()
    if _username_taken(db, username):
        raise OnboardingError(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Username '{username}' sudah dipakai",
        )
    if not store.is_active or store.status != StoreStatus.ACTIVE:
        raise OnboardingError(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Toko sedang tidak aktif, user baru tidak bisa dibuat",
        )

    user = User(
        username=username,
        password_hash=hash_password(password),
        full_name=full_name.strip(),
        role=role,
        is_active=True,
        store_id=store.id,
    )
    db.add(user)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise
    db.refresh(user)

    log_audit(
        db,
        actor,
        "USER_CREATE",
        "user",
        user.id,
        {"username": user.username, "role": role, "store_id": str(store.id)},
        request,
    )
    return user


def update_store_user(
    db: Session,
    user: User,
    changes: dict,
    actor: User,
    request=None,
) -> User:
    """Ubah profil user toko. Perubahan role/password/aktif memaksa logout."""
    if "username" in changes:
        raise OnboardingError(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username tidak bisa diubah",
        )

    if changes.get("role") == UserRole.OWNER.value:
        raise OnboardingError(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Peran OWNER hanya bisa dibuat oleh sistem, bukan dari toko",
        )

    new_role = changes.get("role", user.role)
    is_active = changes.get("is_active", user.is_active)

    if user.role == UserRole.BOS.value and new_role != UserRole.BOS.value:
        # Bos terakhir tidak boleh mengunci semua akses ke tokonya sendiri.
        if not _store_has_other_bos(db, user.store_id, exclude_id=user.id):
            raise OnboardingError(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Toko harus punya minimal satu BOS aktif",
            )

    if is_active is False and user.role == UserRole.BOS.value:
        if not _store_has_other_bos(db, user.store_id, exclude_id=user.id):
            raise OnboardingError(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="BOS terakhir tidak bisa dinonaktifkan",
            )

    sensitive = any(
        changes.get(field) is not None
        for field in ("password", "role", "is_active")
    )
    if "password" in changes and changes["password"]:
        changes["password_hash"] = hash_password(changes.pop("password"))

    before = {"role": user.role, "is_active": user.is_active}

    for field, value in changes.items():
        setattr(user, field, value)

    if sensitive:
        revoke_all_tokens(db, user)

    try:
        db.commit()
    except Exception:
        db.rollback()
        raise
    db.refresh(user)

    log_audit(
        db,
        actor,
        "USER_UPDATE",
        "user",
        user.id,
        {
            "username": user.username,
            "before": before,
            "after": {"role": user.role, "is_active": user.is_active},
            "tokens_revoked": sensitive,
        },
        request,
    )
    return user


def _store_has_other_bos(db: Session, store_id: Optional[UUID], exclude_id: UUID) -> bool:
    if store_id is None:
        return False
    return (
        db.query(User.id)
        .filter(
            User.store_id == store_id,
            User.role == UserRole.BOS.value,
            User.is_active.is_(True),
            User.id != exclude_id,
        )
        .first()
        is not None
    )


def delete_store(db: Session, store: Store, actor: User, request=None) -> None:
    """Nonaktifkan toko. Sengaja tidak menghapus baris.

    Penjualan, laporan, dan audit milik toko harus tetap bisa dibaca untuk
    pembukuan, jadi penghapusan fisik tidak pernah dipakai dari dashboard.
    """
    if store.is_active:
        store.is_active = False
        store.status = StoreStatus.SUSPENDED
        db.commit()

    log_audit(
        db,
        actor,
        "STORE_SUSPEND",
        "store",
        store.id,
        {"code": store.code, "reason": "dihapus dari dashboard"},
        request,
    )


def lifetime_sales(db: Session, store_id: UUID):
    row = (
        db.query(
            func.count(Sale.id).label("count"),
            func.coalesce(func.sum(Sale.total_amount), 0).label("revenue"),
        )
        .filter(Sale.store_id == store_id, Sale.status == "COMPLETED")
        .first()
    )
    return int(row.count or 0), float(row.revenue or 0)
