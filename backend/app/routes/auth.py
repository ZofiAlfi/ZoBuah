from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.user import User
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
)

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

    log_audit(db, user, "LOGIN", "auth", user.id, {"username": user.username}, request)

    return TokenResponse(
        access_token=create_access_token(str(user.id), user.role),
        refresh_token=create_refresh_token(str(user.id)),
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
    return TokenResponse(
        access_token=create_access_token(str(user.id), user.role),
        refresh_token=create_refresh_token(str(user.id)),
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
    return db.query(User).order_by(User.created_at.desc()).all()


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

    user = User(
        username=body.username,
        full_name=body.full_name,
        password_hash=hash_password(body.password),
        role=body.role,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    log_audit(db, current_user, "USER_CREATE", "user", user.id,
              {"username": user.username, "role": user.role}, request)
    return user


@router.put("/users/{user_id}", response_model=UserResponse)
def update_user(
    user_id: str,
    body: UserUpdate,
    current_user: User = Depends(require_bos()),
    db: Session = Depends(get_db),
    request: Request = None,
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Pengguna tidak ditemukan")

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
        db.commit()
        db.refresh(user)
        log_audit(db, current_user, "USER_UPDATE", "user", user.id, changes, request)
    return user