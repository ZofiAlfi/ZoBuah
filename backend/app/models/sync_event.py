import uuid
from datetime import datetime
from sqlalchemy import Column, String, DateTime, Text
from sqlalchemy.dialects.postgresql import UUID

from ..database import Base


class SyncEvent(Base):
    __tablename__ = "sync_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_type = Column(String(50), nullable=False)
    entity_type = Column(String(50), nullable=False)
    entity_id = Column(String(100), nullable=False, index=True)
    device_id = Column(String(100), nullable=True)
    server_reference = Column(String(100), nullable=True)
    payload = Column(Text, nullable=True)
    status = Column(String(20), nullable=False, default="PROCESSED")
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id": str(self.id),
            "event_type": self.event_type,
            "entity_type": self.entity_type,
            "entity_id": self.entity_id,
            "device_id": self.device_id,
            "server_reference": self.server_reference,
            "payload": self.payload,
            "status": self.status,
            "error_message": self.error_message,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }