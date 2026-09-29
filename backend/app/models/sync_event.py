import uuid
from datetime import datetime
from sqlalchemy import Column, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from ..database import Base

from ..utilities.helpers import iso_utc


class SyncEvent(Base):
    __tablename__ = "sync_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=func.gen_random_uuid())
    event_type = Column(String(50), nullable=False)
    entity_type = Column(String(50), nullable=False)
    entity_id = Column(String(100), nullable=False, index=True)
    device_id = Column(String(100), nullable=True)
    server_reference = Column(String(100), nullable=True)
    payload = Column(Text, nullable=True)
    status = Column(String(20), nullable=False, default="PROCESSED")
    error_message = Column(Text, nullable=True)
    # Scope tenant. Ditambahkan di migrasi 003_multi_tenant.sql.
    # Nullable dengan sengaja: user OWNER tidak punya toko.
    store_id = Column(UUID(as_uuid=True), ForeignKey("stores.id"), nullable=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    store = relationship("Store", back_populates="sync_events")

    def to_dict(self):
        return {
            "id": str(self.id),
            "event_type": self.event_type,
            "entity_type": self.entity_type,
            "entity_id": self.entity_id,
            "device_id": self.device_id,
            "store_id": str(self.store_id) if self.store_id else None,
            "server_reference": self.server_reference,
            "payload": self.payload,
            "status": self.status,
            "error_message": self.error_message,
            "created_at": iso_utc(self.created_at)
        }