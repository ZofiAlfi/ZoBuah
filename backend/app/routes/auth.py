from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.user import User, UserRole
from ..schemas.auth import (
    LoginRequest,
    RefreshRequest,
    TokenResponse,
    UserCreate,
    UserResponse,
    UserUpdate,
)
from ..security import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
    get_current_user,
    require_bos,
    log_audit,
    revoke_all_tokens,
)
from ..tenancy import require_store_id

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
def login(request: Request, body: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == body.username).first()
    if not user or not verify_password(body.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Username atau password salah",
        )
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Akun nonaktif")
    if user.role == UserRole.OWNER.value:
        # OWNER tidak punya toko, jadi tidak punya akses ke endpoint POS mana pun.
        # Menolaknya di sini mencegah token lintas-toko bocor ke perangkat toko.
        raise HTTPException(
            status_code=403,
            detail="Akun owner tidak dapat login lewat aplikasi POS",
        )
    if user.store_id is None:
        raise HTTPException(
            status_code=403,
            detail="Akun Anda belum tertaut ke toko. Hubungi pemilik layanan.",
        )

    log_audit(db, user, "LOGIN", "auth", user.id, {"username": user.username}, request)

    return TokenResponse(
        access_token=create_access_token(
            str(user.id), user.role, str(user.store_id), user.token_version or 0
        ),
        refresh_token=create_refresh_token(str(user.id), user.token_version or 0),
        user=user.to_dict(),
    )


@router.post("/refresh", response_model=TokenResponse)
def refresh(body: RefreshRequest, db: Session = Depends(get_db)):
    payload = decode_token(body.refresh_token)
    if payload is None or payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Refresh token tidak valid")
    user = db.query(User).filter(User.id == payload.get("sub"), User.is_active == True).first()
    if not user:
        raise HTTPException(status_code=401, detail="Pengguna tidak ditemukan")

    # Refresh token lama setelah force logout tidak boleh menghidupkan akses lagi.
    if payload.get("tv", 0) != (user.token_version or 0):
        raise HTTPException(status_code=401, detail="Sesi sudah tidak berlaku. Silakan login kembali.")
    if user.store_id is None:
        raise HTTPException(status_code=403, detail="Akun Anda belum tertaut ke toko.")

    return TokenResponse(
        access_token=create_access_token(
            str(user.id), user.role, str(user.store_id), user.token_version or 0
        ),
        refresh_token=create_refresh_token(str(user.id), user.token_version or 0),
        user=user.to_dict(),
    )


@router.post("/logout")
def logout(request: Request, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    log_audit(db, current_user, "LOGOUT", "auth", current_user.id, None, request)
    return {"message": "Logout berhasil"}


@router.get("/me", response_model=UserResponse)
def me(current_user: User = Depends(get_current_user)):
    return current_user


@router.get("/users", response_model=list[UserResponse])
def list_users(
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
):
    """Hanya user milik toko pemanggil.

    Sebelumnya .all() tanpa filter, sehingga satu BOS bisa melihat seluruh
    akun seluruh toko beserta nama lengkapnya.
    """
    return (
        db.query(User)
        .filter(User.store_id == require_store_id(current_user))
        .order_by(User.created_at.desc())
        .all()
    )


@router.post("/users", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def create_user(
    body: UserCreate,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    existing = db.query(User).filter(User.username == body.username).first()
    if existing:
        raise HTTPException(status_code=400, detail="Username sudah digunakan")

    # User baru SELALU milik toko pemanggil. Body tidak boleh menentukannya,
    # jadi tidak ada jalur untuk membuat akun di toko orang lain.
    user = User(
        username=body.username,
        full_name=body.full_name,
        password_hash=hash_password(body.password),
        role=body.role,
        store_id=require_store_id(current_user),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    log_audit(db, current_user, "USER_CREATE", "user", user.id,
              {"username": user.username, "role": user.role,
               "store_id": str(user.store_id)}, request)
    return user


@router.put("/users/{user_id}", response_model=UserResponse)
def update_user(
    user_id: str,
    body: UserUpdate,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    store_id = require_store_id(current_user)
    # WAJIB ter-scope: tanpa ini, BOS toko A bisa mengubah akun toko B hanya
    # dengan menebak UUID.
    user = db.query(User).filter(User.id == user_id, User.store_id == store_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Pengguna tidak ditemukan")

    # Mencegah BOS mengunci dirinya sendiri dengan mencabut role terakhirnya.
    if body.role is not None and user.id == current_user.id and body.role != user.role:
        remaining = (
            db.query(User)
            .filter(
                User.store_id == store_id,
                User.role == UserRole.BOS.value,
                User.is_active == True,
                User.id != user.id,
            )
            .count()
        )
        if remaining == 0:
            raise HTTPException(
                status_code=400,
                detail="Tidak bisa menurunkan role BOS terakhir di toko ini",
            )

    changes = {}
    if body.full_name is not None:
        user.full_name = body.full_name
        changes["full_name"] = body.full_name
    if body.password is not None:
        user.password_hash = hash_password(body.password)
        changes["password"] = "***"
    if body.role is not None:
        user.role = body.role
        changes["role"] = body.role
    if body.is_active is not None:
        user.is_active = body.is_active
        changes["is_active"] = body.is_active

    if changes:
        # Ganti password atau ubah role/is_active harus mematikan sesi lama di
        # perangkat POS, kalau tidak akun yang dicut masih jalan sampai token
        # atau refresh-nya habis.
        revoke_all_tokens(db, user)
        changes["token_version"] = user.token_version
        db.commit()
        db.refresh(user)
        log_audit(db, current_user, "USER_UPDATE", "user", user.id, changes, request)
    return user