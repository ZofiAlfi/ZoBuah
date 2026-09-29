import uuid
from datetime import datetime
from sqlalchemy import Column, DateTime, ForeignKey, Integer, Numeric, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from ..database import Base

from ..utilities.helpers import iso_utc


class StockMovement(Base):
    __tablename__ = "stock_movements"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=func.gen_random_uuid())
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    movement_type = Column(String(20), nullable=False)
    quantity = Column(Numeric(12, 3), nullable=False)
    stock_before = Column(Numeric(12, 3), nullable=False)
    stock_after = Column(Numeric(12, 3), nullable=False)
    reference_id = Column(UUID(as_uuid=True), nullable=True)
    reference_type = Column(String(50), nullable=True)
    notes = Column(Text, nullable=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    # Scope tenant. Ditambahkan di migrasi 003_multi_tenant.sql.
    # Nullable dengan sengaja: user OWNER tidak punya toko.
    store_id = Column(UUID(as_uuid=True), ForeignKey("stores.id"), nullable=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    product = relationship("Product", back_populates="stock_movements")
    store = relationship("Store", back_populates="stock_movements")
    user = relationship("User")

    def to_dict(self):
        return {
            "id": str(self.id),
            "store_id": str(self.store_id) if self.store_id else None,
            "product_id": str(self.product_id),
            "movement_type": self.movement_type,
            "quantity": float(self.quantity),
            "stock_before": float(self.stock_before),
            "stock_after": float(self.stock_after),
            "reference_id": str(self.reference_id) if self.reference_id else None,
            "reference_type": self.reference_type,
            "notes": self.notes,
            "user_id": str(self.user_id),
            "created_at": iso_utc(self.created_at)
        }
