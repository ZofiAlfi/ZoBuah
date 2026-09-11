import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Text
from sqlalchemy.dialects.postgresql import UUID

from ..database import Base


class Device(Base):
    __tablename__ = "devices"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    device_id = Column(String(100), unique=True, nullable=False)
    device_name = Column(String(100), nullable=True)
    platform = Column(String(50), nullable=True)
    last_sync_at = Column(DateTime, nullable=True)
    registered_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)

    def to_dict(self):
        return {
            "id": str(self.id),
            "device_id": self.device_id,
            "device_name": self.device_name,
            "platform": self.platform,
            "last_sync_at": self.last_sync_at.isoformat() if self.last_sync_at else None,
            "registered_at": self.registered_at.isoformat() if self.registered_at else None,
            "is_active": self.is_active,
        }