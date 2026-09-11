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


def create_access_token(user_id: str, role: str) -> str:
    expires = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": user_id,
        "role": role,
        "type": "access",
        "exp": expires,
        "iat": datetime.utcnow(),
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(user_id: str) -> str:
    expires = datetime.utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    payload = {
        "sub": user_id,
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


def require_bos():
    return require_role(UserRole.BOS.value)


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
    )
    db.add(log)
    db.commit()


def register_device(db: Session, device_id: str, device_name: Optional[str] = None, platform: Optional[str] = None) -> Device:
    device = db.query(Device).filter(Device.device_id == device_id).first()
    if device:
        device.device_name = device_name or device.device_name
        device.platform = platform or device.platform
        device.last_sync_at = datetime.utcnow()
    else:
        device = Device(
            device_id=device_id,
            device_name=device_name,
            platform=platform,
            last_sync_at=datetime.utcnow(),
        )
        db.add(device)
    db.commit()
    db.refresh(device)
    return device