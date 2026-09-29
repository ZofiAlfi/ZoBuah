import uuid
from datetime import datetime, timedelta
from typing import Optional, Dict
import json

import jwt
from passlib.context import CryptContext
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from .config import settings
from .database import get_db
from .models.user import User, UserRole
from .models.audit_log import AuditLog
from .models.device import Device

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

TOKEN_BLACKLIST: Dict[str, datetime] = {}


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def create_access_token(user_id: str, role: str, store_id: Optional[str] = None, token_version: int = 0) -> str:
    expires = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": user_id,
        "role": role,
        # store_id ikut dikodekan supaya klaim tidak bisa diedit di sisi
        # klien, tapi TIDAK dipakai sebagai sumber kebenaran. Filter selalu
        # membaca User.store_id langsung dari DB, jadi user yang dipindah
        # toko langsung kehilangan akses ke toko lamanya.
        "store_id": store_id,
        "tv": token_version,
        "type": "access",
        "exp": expires,
        "iat": datetime.utcnow(),
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(user_id: str, token_version: int = 0) -> str:
    expires = datetime.utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    payload = {
        "sub": user_id,
        "tv": token_version,
        "type": "refresh",
        "exp": expires,
        "iat": datetime.utcnow(),
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> Optional[dict]:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        jti = payload.get("jti")
        if jti in TOKEN_BLACKLIST:
            return None
        return payload
    except jwt.ExpiredSignatureError:
        return None
    except jwt.PyJWTError:
        return None


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    payload = decode_token(token)
    if payload is None or payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token tidak valid atau telah kedaluwarsa",
        )
    user_id = payload.get("sub")
    user = db.query(User).filter(User.id == user_id, User.is_active == True).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Pengguna tidak ditemukan",
        )

    # Penolakan token_version: naikkan angka ini untuk memaksa semua token
    # lama mati (logout paksa, ganti password, toko dicut). TOKEN_BLACKLIST
    # di atas hanya in-memory, jadi tidak bisa diandalkan untuk ini.
    if payload.get("tv", 0) != (user.token_version or 0):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sesi sudah tidak berlaku. Silakan login kembali.",
        )

    # Akses silang toko: user yang dipindahkan ke toko lain atau dinonaktifkan
    # tidak boleh tetap memakai token lama yang masih valid secara kriptografi.
    if not user.is_owner and payload.get("store_id") and user.store_id is not None:
        if payload["store_id"] != str(user.store_id):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Akun sudah dipindahkan ke toko lain. Silakan login kembali.",
            )

    return user


async def get_current_active_user(
    current_user: User = Depends(get_current_user),
) -> User:
    if not current_user.is_active:
        raise HTTPException(status_code=403, detail="Akun nonaktif")
    return current_user


def require_role(*roles: str):
    async def role_checker(current_user: User = Depends(get_current_user)):
        if current_user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Anda tidak memiliki izin untuk melakukan aksi ini",
            )
        return current_user

    return role_checker


def require_owner():
    """Hanya OWNER. Dipakai untuk seluruh endpoint /api/v1/admin/*."""
    return require_role(UserRole.OWNER.value)


def require_bos():
    return require_role(UserRole.BOS.value)


def revoke_all_tokens(db: Session, user: User) -> int:
    """Naikkan token_version sehingga seluruh token lama user mati seketika.

    Dipakai saat owner memaksa logout, dan ketika role/toko user berubah.
    Mengembalikan nilai token_version yang baru.
    """
    user.token_version = (user.token_version or 0) + 1
    db.commit()
    db.refresh(user)
    return user.token_version


def create_impersonation_token(
    user_id: str,
    role: str,
    store_id: str,
    token_version: int = 0,
) -> str:
    """Token OWNER untuk melihat satu toko secara read-only.

    Token ini memakai sub milik user toko tersebut, bukan sub milik OWNER,
    jadi seluruh endpoint POS yang sudah ter-scope akan otomatis melihat
    baris toko yang benar tanpa perlu endpoint khusus.

    Yang membuatnya read-only adalah klaim "imp", yang dibaca middleware
    write_guard di main.py: setiap metode selain GET/HEAD/OPTIONS ditolak.
    Menyimpan penolakan di middleware, bukan di tiap endpoint, karena ada
    puluhan route POS dan hanya satu tempat yang bisa dijamin lengkap.
    """
    expires = datetime.utcnow() + timedelta(minutes=settings.IMPERSONATION_EXPIRE_MINUTES)
    payload = {
        "sub": user_id,
        "role": role,
        "store_id": store_id,
        "tv": token_version,
        "imp": True,
        "type": "access",
        "exp": expires,
        "iat": datetime.utcnow(),
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def is_impersonation_token(payload: Optional[dict]) -> bool:
    return bool(payload) and payload.get("imp") is True


def log_audit(
    db: Session,
    user: User,
    action: str,
    entity_type: Optional[str] = None,
    entity_id: Optional[str] = None,
    details: Optional[dict] = None,
    request=None,
):
    ip_address = None
    if request:
        ip_address = request.client.host if request.client else None
    log = AuditLog(
        user_id=user.id,
        action=action,
        entity_type=entity_type,
        entity_id=str(entity_id) if entity_id else None,
        details=json.dumps(details, default=str) if details else None,
        ip_address=ip_address,
        # Milik toko pemicu, bukan toko actor. OWNER selalu NULL karena
        # lintas-toko, dan baris audit milik toko tidak boleh hilang.
        store_id=user.store_id,
    )
    db.add(log)
    db.commit()


def register_device(db: Session, device_id: str, device_name: Optional[str] = None, platform: Optional[str] = None, store_id=None) -> Device:
    device = db.query(Device).filter(Device.device_id == device_id).first()
    if device:
        device.device_name = device_name or device.device_name
        device.platform = platform or device.platform
        device.last_sync_at = datetime.utcnow()
        # Perangkat yang pindah toko harus ikut pindah, kalau tidak tokonya
        # masih bisa mengsinkronkan barang yang bukan miliknya.
        if store_id is not None:
            device.store_id = store_id
    else:
        device = Device(
            device_id=device_id,
            device_name=device_name,
            platform=platform,
            last_sync_at=datetime.utcnow(),
            store_id=store_id,
        )
        db.add(device)
    db.commit()
    db.refresh(device)
    return device