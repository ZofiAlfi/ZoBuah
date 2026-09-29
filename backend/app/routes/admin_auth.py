"""Login dashboard OWNER.

Pemisahan dari /api/v1/auth/login bukan sekadar kosmetik. Endpoint POS
sengaja menolak OWNER (lihat routes/auth.py) supaya token lintas-toko tidak
pernah bocor ke perangkat kasir. Karena itu kredensial owner hanya punya satu
pintu masuk, dan token yang dihasilkannya ditolak oleh setiap route POS lewat
require_store_id() di tenancy.py.
"""
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.user import User, UserRole
from ..schemas.admin import (
    AdminLoginRequest,
    AdminRefreshRequest,
    AdminTokenResponse,
    OwnerProfile,
)
from ..security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    log_audit,
    require_owner,
    verify_password,
)

router = APIRouter(prefix="/admin/auth", tags=["admin-auth"])


def _profile(user: User) -> OwnerProfile:
    return OwnerProfile(
        id=user.id,
        username=user.username,
        full_name=user.full_name,
        created_at=user.created_at,
    )


def _owner_or_401(db: Session, user_id: str) -> User:
    user = db.query(User).filter(User.id == user_id, User.is_active.is_(True)).first()
    if user is None or user.role != UserRole.OWNER.value:
        # 401, bukan 403: kredensialnya tidak berlaku untuk dashboard sama
        # sekali, dan membedakan keduanya membuat akun toko bisa menebak
        # perannya lewat pesan error.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Akun tidak diizinkan untuk dashboard owner",
        )
    return user


@router.post("/login", response_model=AdminTokenResponse)
def admin_login(request: Request, body: AdminLoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == body.username).first()
    if not user or not verify_password(body.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Username atau password salah",
        )
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Akun nonaktif")
    if user.role != UserRole.OWNER.value:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Akun ini bukan akun owner. Gunakan aplikasi POS.",
        )

    log_audit(db, user, "ADMIN_LOGIN", "auth", user.id, {"username": user.username}, request)

    return AdminTokenResponse(
        access_token=create_access_token(
            str(user.id), user.role, None, user.token_version or 0
        ),
        refresh_token=create_refresh_token(str(user.id), user.token_version or 0),
        owner=_profile(user),
    )


@router.post("/refresh", response_model=AdminTokenResponse)
def admin_refresh(body: AdminRefreshRequest, db: Session = Depends(get_db)):
    payload = decode_token(body.refresh_token)
    if payload is None or payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token tidak valid",
        )
    user = _owner_or_401(db, payload.get("sub"))
    if payload.get("tv", 0) != (user.token_version or 0):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sesi sudah tidak berlaku. Silakan login kembali.",
        )

    return AdminTokenResponse(
        access_token=create_access_token(
            str(user.id), user.role, None, user.token_version or 0
        ),
        refresh_token=create_refresh_token(str(user.id), user.token_version or 0),
        owner=_profile(user),
    )


@router.get("/me", response_model=OwnerProfile)
def admin_me(owner: User = Depends(require_owner())):
    return _profile(owner)
