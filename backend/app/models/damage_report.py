import uuid
from datetime import datetime
from sqlalchemy import Column, String, Numeric, DateTime, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from ..database import Base


class DamageReport(Base):
    __tablename__ = "damage_reports"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    quantity = Column(Numeric(12, 3), nullable=False)
    unit = Column(String(20), nullable=False)
    # Kuantitas dalam satuan stok produk (hasil konversi unit pada saat lapor).
    qty_in_base_unit = Column(Numeric(12, 3), nullable=True)
    reason = Column(String(50), nullable=False)
    description = Column(Text, nullable=True)
    status = Column(String(20), nullable=False, default="PENDING")
    employee_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    approved_by = Column(UUID(as_uuid=True), nullable=True)
    approved_at = Column(DateTime, nullable=True)
    rejected_by = Column(UUID(as_uuid=True), nullable=True)
    rejected_at = Column(DateTime, nullable=True)
    rejection_reason = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    product = relationship("Product")
    employee = relationship("User", back_populates="damage_reports")
    photos = relationship("DamagePhoto", back_populates="damage_report")

    def to_dict(self):
        return {
            "id": str(self.id),
            "product_id": str(self.product_id),
            "product_name": self.product.name if self.product else None,
            "quantity": float(self.quantity),
            "unit": self.unit,
            "qty_in_base_unit": float(self.qty_in_base_unit) if self.qty_in_base_unit is not None else None,
            "reason": self.reason,
            "description": self.description,
            "status": self.status,
            "employee_id": str(self.employee_id),
            "employee_name": self.employee.full_name if self.employee else None,
            "approved_by": str(self.approved_by) if self.approved_by else None,
            "approved_at": self.approved_at.isoformat() if self.approved_at else None,
            "rejected_by": str(self.rejected_by) if self.rejected_by else None,
            "rejected_at": self.rejected_at.isoformat() if self.rejected_at else None,
            "rejection_reason": self.rejection_reason,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "photos": [photo.file_url for photo in self.photos if photo.file_url],
        }


class DamagePhoto(Base):
    __tablename__ = "damage_photos"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    damage_report_id = Column(UUID(as_uuid=True), ForeignKey("damage_reports.id"), nullable=False)
    file_path = Column(String(255), nullable=False)
    file_url = Column(String(500), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    damage_report = relationship("DamageReport", back_populates="photos")

    def to_dict(self):
        return {
            "id": str(self.id),
            "damage_report_id": str(self.damage_report_id),
            "file_path": self.file_path,
            "file_url": self.file_url,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }