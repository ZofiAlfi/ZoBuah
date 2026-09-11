import uuid
from datetime import datetime
from sqlalchemy import Column, String, Numeric, Integer, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from ..database import Base
from ..services.storage import storage


class Product(Base):
    __tablename__ = "products"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(200), nullable=False)
    category_id = Column(UUID(as_uuid=True), ForeignKey("categories.id"), nullable=True)
    unit = Column(String(20), nullable=False, default="kg")
    modal_price = Column(Numeric(12, 2), nullable=False, default=0)
    selling_price = Column(Numeric(12, 2), nullable=False, default=0)
    stock = Column(Numeric(12, 3), nullable=False, default=0)
    min_stock = Column(Numeric(12, 3), nullable=False, default=0)
    is_active = Column(Boolean, default=True)
    description = Column(Text, nullable=True)
    photo_path = Column(String(255), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    category = relationship("Category", back_populates="products")
    stock_movements = relationship("StockMovement", back_populates="product")
    sale_items = relationship("SaleItem", back_populates="product")

    @property
    def category_name(self):
        return self.category.name if self.category else None

    def to_dict(self):
        return {
            "id": str(self.id),
            "name": self.name,
            "category_id": str(self.category_id) if self.category_id else None,
            "category_name": self.category.name if self.category else None,
            "unit": self.unit,
            "modal_price": float(self.modal_price) if self.modal_price else 0,
            "selling_price": float(self.selling_price) if self.selling_price else 0,
            "stock": float(self.stock) if self.stock else 0,
            "min_stock": float(self.min_stock) if self.min_stock else 0,
            "is_active": self.is_active,
            "description": self.description,
            "photo_url": storage.url(self.photo_path) if self.photo_path else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }
