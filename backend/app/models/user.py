import uuid
from datetime import datetime
from sqlalchemy import Boolean, Column, DateTime, Enum as SAEnum, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import enum

from ..database import Base

from ..utilities.helpers import iso_utc


class UserRole(str, enum.Enum):
    BOS = "BOS"
    KARYAWAN = "KARYAWAN"
    # Akun global pemilik SaaS. Tidak punya store_id (NULL) dan boleh melihat
    # seluruh toko. Satu-satunya role yang boleh melewati filter store.
    OWNER = "OWNER"


# Di luar body Enum: nilai tuple di dalam body akan dianggap sebagai enum member.
STORE_ROLES = (UserRole.BOS, UserRole.KARYAWAN)


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=func.gen_random_uuid())
    username = Column(String(50), unique=True, nullable=False, index=True)
    full_name = Column(String(100), nullable=False)
    password_hash = Column(String(255), nullable=False)
    role = Column(String(20), nullable=False, default=UserRole.KARYAWAN.value)
    is_active = Column(Boolean, default=True)
    # NULL untuk role OWNER (akun global). Wajib terisi untuk BOS/KARYAWAN.
    store_id = Column(UUID(as_uuid=True), ForeignKey("stores.id"), nullable=True, index=True)
    # Dinaikkan saat owner memaksa logout. Token yang dibuat sebelum
    # nomor versi ini otomatis tidak berlaku, dan bertahan setelah restart
    # (berbeda dengan TOKEN_BLACKLIST yang hanya in-memory).
    token_version = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    sales = relationship("Sale", back_populates="employee")
    damage_reports = relationship("DamageReport", back_populates="employee")
    audit_logs = relationship("AuditLog", back_populates="user")
    store = relationship("Store", back_populates="users")

    def is_owner(self):
        return self.role == UserRole.OWNER.value

    @property
    def store_name(self):
        """Nama toko, dibaca dari relationship.

        Wajib sebagai property (bukan hanya isi to_dict) karena
        UserResponse mendeklarasikan field store_name dan FastAPI memvalidasi
        respons langsung dari objek ORM. Tanpa property ini, endpoint
        /auth/users mengembalikan 200 dengan store_name = null -- gagal
        senyap yang tidak terlihat di status respons.
        """
        return self.store.name if self.store else None

    def to_dict(self):
        return {
            "id": str(self.id),
            "username": self.username,
            "full_name": self.full_name,
            "role": self.role,
            "is_active": self.is_active,
            "store_id": str(self.store_id) if self.store_id else None,
            "store_name": self.store_name,
            "created_at": iso_utc(self.created_at),
            "updated_at": iso_utc(self.updated_at),
        }
