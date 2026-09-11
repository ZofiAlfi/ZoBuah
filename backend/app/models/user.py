import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, Enum as SAEnum, DateTime, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import enum

from ..database import Base


class UserRole(str, enum.Enum):
    BOS = "BOS"
    KARYAWAN = "KARYAWAN"


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username = Column(String(50), unique=True, nullable=False, index=True)
    full_name = Column(String(100), nullable=False)
    password_hash = Column(String(255), nullable=False)
    role = Column(String(20), nullable=False, default=UserRole.KARYAWAN.value)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    sales = relationship("Sale", back_populates="employee")
    damage_reports = relationship("DamageReport", back_populates="employee")
    audit_logs = relationship("AuditLog", back_populates="user")

    def to_dict(self):
        return {
            "id": str(self.id),
            "username": self.username,
            "full_name": self.full_name,
            "role": self.role,
            "is_active": self.is_active,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
