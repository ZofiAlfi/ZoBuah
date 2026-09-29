import uuid
from datetime import datetime, date
from sqlalchemy import Boolean, Column, Date, DateTime, String, Text, func, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from ..database import Base

from ..utilities.helpers import iso_utc


class StoreStatus:
    ACTIVE = "ACTIVE"
    SUSPENDED = "SUSPENDED"
    EXPIRED = "EXPIRED"

    ALL = (ACTIVE, SUSPENDED, EXPIRED)


class Plan:
    TRIAL = "TRIAL"
    BASIC = "BASIC"
    PRO = "PRO"
    UNLIMITED = "UNLIMITED"

    ALL = (TRIAL, BASIC, PRO, UNLIMITED)


class Store(Base):
    __tablename__ = "stores"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=func.gen_random_uuid())
    code = Column(String(20), nullable=False, unique=True, index=True)
    name = Column(String(100), nullable=False)
    owner_name = Column(String(100), nullable=False)
    phone = Column(String(20), nullable=True)
    address = Column(Text, nullable=True)
    # Kolom NOT NULL di bawah memakai default sisi-Python DAN sisi-DB.
    # Default sisi-Python saja tidak cukup: create_all() tidak pernah menulis
    # DEFAULT ke database, sehingga INSERT SQL mentah (dipakai migrasi 003)
    # akan gagal "null value in column ...".
    plan = Column(String(20), nullable=False, default=Plan.TRIAL, server_default=Plan.TRIAL)
    plan_expires_at = Column(Date, nullable=True)
    status = Column(String(20), nullable=False, default=StoreStatus.ACTIVE,
                    server_default=StoreStatus.ACTIVE, index=True)
    is_active = Column(Boolean, nullable=False, default=True, server_default=text("true"))
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow,
                        server_default=func.now())
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow,
                        server_default=func.now(), onupdate=datetime.utcnow)

    users = relationship("User", back_populates="store")
    categories = relationship("Category", back_populates="store")
    products = relationship("Product", back_populates="store")
    sales = relationship("Sale", back_populates="store")
    stock_movements = relationship("StockMovement", back_populates="store")
    damage_reports = relationship("DamageReport", back_populates="store")
    audit_logs = relationship("AuditLog", back_populates="store")
    devices = relationship("Device", back_populates="store")
    sync_events = relationship("SyncEvent", back_populates="store")
    broadcasts = relationship("Broadcast", back_populates="store")

    def days_to_expiry(self):
        """Sisa hari sampai langganan habis. None bila langganan tak terbatas."""
        if self.plan_expires_at is None:
            return None
        return (self.plan_expires_at - date.today()).days

    def health(self, last_sync_at=None, stale_hours=24):
        """OK / STALE / DEAD berdasarkan sync terakhir dari perangkat.

        last_sync_at diisi pemanggil (service admin_metrics) lewat Devices.
        Sengaja tidak become relationship agar model ini bebas dependency
        ke Device dan tidak memicu lazy-load.
        """
        if self.status != StoreStatus.ACTIVE or not self.is_active:
            return "DEAD"
        if last_sync_at is None:
            return "STALE"
        hours = (datetime.utcnow() - last_sync_at).total_seconds() / 3600
        return "DEAD" if hours > stale_hours * 7 else ("STALE" if hours > stale_hours else "OK")

    def to_dict(self):
        return {
            "id": str(self.id),
            "code": self.code,
            "name": self.name,
            "owner_name": self.owner_name,
            "phone": self.phone,
            "address": self.address,
            "plan": self.plan,
            "plan_expires_at": self.plan_expires_at.isoformat() if self.plan_expires_at else None,
            "days_to_expiry": self.days_to_expiry(),
            "status": self.status,
            "is_active": self.is_active,
            "created_at": iso_utc(self.created_at),
            "updated_at": iso_utc(self.updated_at),
        }
