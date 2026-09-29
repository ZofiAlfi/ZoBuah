import uuid
from datetime import datetime
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from ..database import Base

from ..utilities.helpers import iso_utc


class BroadcastLevel:
    INFO = "INFO"
    WARNING = "WARNING"
    MAINTENANCE = "MAINTENANCE"

    ALL = (INFO, WARNING, MAINTENANCE)


class BroadcastTarget:
    ALL = "ALL"
    STORE = "STORE"

    ALL_TARGETS = (ALL, STORE)


class Broadcast(Base):
    __tablename__ = "broadcasts"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=func.gen_random_uuid())
    title = Column(String(120), nullable=False)
    body = Column(Text, nullable=False)
    level = Column(String(20), nullable=False, default=BroadcastLevel.INFO)
    target = Column(String(20), nullable=False, default=BroadcastTarget.ALL)
    store_id = Column(UUID(as_uuid=True), ForeignKey("stores.id"), nullable=True)
    starts_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=True)
    is_active = Column(Boolean, nullable=False, default=True, index=True)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    store = relationship("Store", back_populates="broadcasts")
    creator = relationship("User")

    def is_live(self, now=None):
        """Aktif bila is_active, sudah mulai, dan belum kedaluwarsa."""
        now = now or datetime.utcnow()
        if not self.is_active:
            return False
        if self.starts_at and self.starts_at > now:
            return False
        if self.expires_at and self.expires_at < now:
            return False
        return True

    def to_dict(self):
        return {
            "id": str(self.id),
            "title": self.title,
            "body": self.body,
            "level": self.level,
            "target": self.target,
            "store_id": str(self.store_id) if self.store_id else None,
            "store_name": self.store.name if self.store else None,
            "starts_at": iso_utc(self.starts_at),
            "expires_at": iso_utc(self.expires_at),
            "is_active": self.is_active,
            "is_live": self.is_live(),
            "created_by": str(self.created_by) if self.created_by else None,
            "created_by_name": self.creator.full_name if self.creator else None,
            "created_at": iso_utc(self.created_at)
        }
