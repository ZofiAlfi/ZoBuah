import secrets
import string
import time
import uuid
from threading import Lock
from typing import Dict, Tuple, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ..database import get_db
from ..models.user import User
from ..models.app_setting import AppSetting
from ..security import get_current_user, require_bos, log_audit

router = APIRouter(prefix="/auth", tags=["auth"])

DEFAULT_EXIT_PIN = "123456"
EXIT_PIN_KEY = "EXIT_PIN"
OTP_TTL_SECONDS = 5 * 60

# In-memory one-time PIN store: {otp_request_id: {pin, expires_at, used, user_id}}
_OTP_LOCK = Lock()
_ACTIVE_OTPS: Dict[str, Dict] = {}


def _get_setting(db: Session, key: str) -> Optional[str]:
    row = db.query(AppSetting).filter(AppSetting.key == key).first()
    return row.value if row else None


def _set_setting(db: Session, key: str, value: str) -> None:
    row = db.query(AppSetting).filter(AppSetting.key == key).first()
    if row:
        row.value = value
    else:
        db.add(AppSetting(key=key, value=value))
    db.commit()


def seed_exit_pin(db: Session) -> None:
    if _get_setting(db, EXIT_PIN_KEY) is None:
        _set_setting(db, EXIT_PIN_KEY, DEFAULT_EXIT_PIN)


class ExitPinRequest(BaseModel):
    pin: str = Field(..., min_length=4, max_length=8)


class OtpRequestResponse(BaseModel):
    otp_id: str
    expires_in: int
    message: str


class ExitVerifyResponse(BaseModel):
    success: bool
    message: str


class ExitApprovalItem(BaseModel):
    otp_id: str
    requester: str
    requester_id: str
    pin: str
    requested_at: float
    expires_at: float


class ExitApprovalListResponse(BaseModel):
    items: list[ExitApprovalItem]


@router.post("/exit/request", response_model=OtpRequestResponse)
def request_exit_otp(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Buat PIN sekali pakai untuk izin keluar (karyawan).
    PIN TIDAK dikirimkan kembali ke karyawan — PIN hanya bisa dilihat BOS
    lewat /auth/exit/pending untuk diteruskan ke karyawan."""
    pin = "".join(secrets.choice(string.digits) for _ in range(6))
    otp_id = str(uuid.uuid4())
    now = time.time()
    with _OTP_LOCK:
        # clean expired
        expired = [k for k, v in _ACTIVE_OTPS.items() if v["expires_at"] < now]
        for k in expired:
            _ACTIVE_OTPS.pop(k, None)
        _ACTIVE_OTPS[otp_id] = {
            "pin": pin,
            "expires_at": now + OTP_TTL_SECONDS,
            "used": False,
            "user_id": str(current_user.id),
            "requester": current_user.full_name or current_user.username,
            "requested_at": now,
        }
    log_audit(db, current_user, "EXIT_OTP_REQUEST", "auth", current_user.id,
              {"otp_id": otp_id, "expires_in": OTP_TTL_SECONDS,
               "note": "PIN hanya tampil di akun BOS"}, None)
    return OtpRequestResponse(
        otp_id=otp_id,
        expires_in=OTP_TTL_SECONDS,
        message="PIN sekali pakai dibuat dan dikirim ke BOS untuk disetujui",
    )


@router.get("/exit/pending", response_model=ExitApprovalListResponse)
def pending_exit_otps(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_bos()),
):
    """Daftar permintaan keluar yang menunggu (untuk BOS).
    BOS melihat PIN di sini lalu meneruskannya ke karyawan."""
    now = time.time()
    with _OTP_LOCK:
        items = [
            {
                "otp_id": k,
                "requester": v["requester"],
                "requester_id": v["user_id"],
                "pin": v["pin"],
                "requested_at": v.get("requested_at", now),
                "expires_at": v["expires_at"],
            }
            for k, v in list(_ACTIVE_OTPS.items())
            if not v["used"] and v["expires_at"] >= now
        ]
    items.sort(key=lambda x: x["requested_at"], reverse=True)
    log_audit(db, current_user, "EXIT_OTP_PENDING_VIEW", "auth",
              current_user.id, {"count": len(items)}, None)
    return ExitApprovalListResponse(items=items)


@router.post("/exit/verify", response_model=ExitVerifyResponse)
def verify_exit(body: ExitPinRequest, db: Session = Depends(get_db)):
    """Verifikasi PIN keluar. Cocokkan dengan PIN tetap atau PIN sekali pakai aktif."""
    now = time.time()
    with _OTP_LOCK:
        for otp_id, entry in list(_ACTIVE_OTPS.items()):
            if entry["used"] or entry["expires_at"] < now:
                continue
            if entry["pin"] == body.pin:
                entry["used"] = True
                _ACTIVE_OTPS.pop(otp_id, None)
                return ExitVerifyResponse(success=True, message="PIN sekali pakai valid")

    fixed_pin = _get_setting(db, EXIT_PIN_KEY) or DEFAULT_EXIT_PIN
    if body.pin == fixed_pin:
        return ExitVerifyResponse(success=True, message="PIN valid")

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="PIN tidak valid atau sudah kedaluwarsa",
    )


class SettingsUpdate(BaseModel):
    exit_pin: Optional[str] = Field(None, min_length=4, max_length=8)


@router.get("/settings")
def get_settings(db: Session = Depends(get_db), current_user: User = Depends(require_bos())):
    return {EXIT_PIN_KEY: _get_setting(db, EXIT_PIN_KEY) or DEFAULT_EXIT_PIN}


@router.put("/settings")
def update_settings(
    body: SettingsUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_bos()),
):
    if body.exit_pin is not None and len(body.exit_pin) >= 4:
        _set_setting(db, EXIT_PIN_KEY, body.exit_pin)
        log_audit(db, current_user, "SETTINGS_UPDATE", "app", None,
                  {"exit_pin": "***"}, None)
    return {EXIT_PIN_KEY: _get_setting(db, EXIT_PIN_KEY) or DEFAULT_EXIT_PIN}