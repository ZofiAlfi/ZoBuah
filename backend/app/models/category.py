import uuid
from datetime import datetime
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from ..database import Base

from ..utilities.helpers import iso_utc


class Category(Base):
    __tablename__ = "categories"
    # Migrasi 003_multi_tenant.sql: nama kategori unik PER TOKO, bukan global.
    # Kalau tetap unik global, toko kedua tidak bisa punya kategori "Apel".
    __table_args__ = (UniqueConstraint("store_id", "name", name="ux_categories_store_name"),)

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=func.gen_random_uuid())
    name = Column(String(100), nullable=False)
    description = Column(Text, nullable=True)
    # Migrasi 006: kategori juga bisa dinonaktifkan, bukan dihapus. Tanpa ini
    # kategori yang dihapus di server tidak pernah hilang dari perangkat
    # kasir karena tidak ada sinyal penghapusan di payload sync.
    is_active = Column(Boolean, nullable=False, default=True)
    # Scope tenant. Ditambahkan di migrasi 003_multi_tenant.sql.
    # Nullable dengan sengaja: user OWNER tidak punya toko.
    store_id = Column(UUID(as_uuid=True), ForeignKey("stores.id"), nullable=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    products = relationship("Product", back_populates="category")
    store = relationship("Store", back_populates="categories")

    def to_dict(self):
        return {
            "id": str(self.id),
            "name": self.name,
            "description": self.description,
            # bool() wajib, bukan nilai mentah: kolomnya sudah NOT NULL tapi
            # data lama bisa masih null sebelum migrasi 006 jalan, dan null di
            # JSON terbaca sebagai "aktif" di sisi klien.
            "is_active": bool(self.is_active),
            "store_id": str(self.store_id) if self.store_id else None,
            "created_at": iso_utc(self.created_at),
            "updated_at": iso_utc(self.updated_at),
        }
