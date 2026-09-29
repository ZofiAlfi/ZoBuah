import uuid
from datetime import datetime
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Index, Integer, Numeric, String, Text, func, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from ..database import Base

from ..utilities.helpers import iso_utc
from ..services.storage import storage


class Product(Base):
    __tablename__ = "products"

    # Satu produk AKTIF per nama per toko. Ini index parsial, bukan unique
    # penuh: baris nonaktif di luar index, jadi produk lama bisa di-revive
    # tanpa bentrok dan produk baru dengan nama sama tidak akan muncul dua
    # kali di grid kasir.
    #
    # Dideklarasikan di sini, bukan hanya di migrasi 006, karena
    # Base.metadata.create_all() tidak bisa membuat index parsial dari
    # migrasi SQL. Tanpa baris ini, setiap skema yang dibangun lewat
    # create_all (yaitu seed UAT --reset dan instalasi baru) tidak punya
    # index ini sama sekali sampai server start menjalankan migrasi.
    __table_args__ = (
        Index(
            "ux_products_store_name_active",
            "store_id",
            "name",
            unique=True,
            postgresql_where=text("is_active = TRUE"),
            sqlite_where=text("is_active = 1"),
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=func.gen_random_uuid())
    name = Column(String(200), nullable=False)
    category_id = Column(UUID(as_uuid=True), ForeignKey("categories.id"), nullable=True)
    unit = Column(String(20), nullable=False, default="kg")
    modal_price = Column(Numeric(12, 2), nullable=False, default=0)
    selling_price = Column(Numeric(12, 2), nullable=False, default=0)
    stock = Column(Numeric(12, 3), nullable=False, default=0)
    min_stock = Column(Numeric(12, 3), nullable=False, default=0)
    # Migrasi 006: NOT NULL. Kalau NULL, sisi klien membaca json['is_active']
    # dengan fallback true sehingga produk nonaktif tetap dianggap aktif dan
    # masih bisa terjual.
    is_active = Column(Boolean, nullable=False, default=True)
    description = Column(Text, nullable=True)
    photo_path = Column(String(255), nullable=True)
    # Scope tenant. Ditambahkan di migrasi 003_multi_tenant.sql.
    # Nullable dengan sengaja: user OWNER tidak punya toko.
    store_id = Column(UUID(as_uuid=True), ForeignKey("stores.id"), nullable=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    category = relationship("Category", back_populates="products")
    store = relationship("Store", back_populates="products")
    stock_movements = relationship("StockMovement", back_populates="product")
    sale_items = relationship("SaleItem", back_populates="product")

    @property
    def category_name(self):
        return self.category.name if self.category else None

    def to_dict(self):
        return {
            "id": str(self.id),
            "store_id": str(self.store_id) if self.store_id else None,
            "name": self.name,
            "category_id": str(self.category_id) if self.category_id else None,
            "category_name": self.category.name if self.category else None,
            "unit": self.unit,
            "modal_price": float(self.modal_price) if self.modal_price else 0,
            "selling_price": float(self.selling_price) if self.selling_price else 0,
            "stock": float(self.stock) if self.stock else 0,
            "min_stock": float(self.min_stock) if self.min_stock else 0,
            "is_active": bool(self.is_active),
            "description": self.description,
            "photo_url": storage.url(self.photo_path) if self.photo_path else None,
            "created_at": iso_utc(self.created_at),
            "updated_at": iso_utc(self.updated_at),
        }
