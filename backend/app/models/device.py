import uuid
from datetime import datetime
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from ..database import Base

from ..utilities.helpers import iso_utc


class Device(Base):
    __tablename__ = "devices"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=func.gen_random_uuid())
    # Scope tenant. Ditambahkan di migrasi 003_multi_tenant.sql.
    # Nullable dengan sengaja: user OWNER tidak punya toko.
    store_id = Column(UUID(as_uuid=True), ForeignKey("stores.id"), nullable=True, index=True)

    device_id = Column(String(100), unique=True, nullable=False)
    device_name = Column(String(100), nullable=True)
    platform = Column(String(50), nullable=True)
    last_sync_at = Column(DateTime, nullable=True)
    registered_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)

    store = relationship("Store", back_populates="devices")

    def to_dict(self):
        return {
            "id": str(self.id),
            "device_id": self.device_id,
            "device_name": self.device_name,
            "platform": self.platform,
            "store_id": str(self.store_id) if self.store_id else None,
            "last_sync_at": iso_utc(self.last_sync_at),
            "registered_at": iso_utc(self.registered_at),
            "is_active": self.is_active,
        }