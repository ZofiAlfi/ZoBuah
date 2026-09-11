import uuid
from datetime import datetime
from sqlalchemy import Column, String, Numeric, DateTime, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from ..database import Base


class Sale(Base):
    __tablename__ = "sales"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    transaction_number = Column(String(40), unique=True, nullable=False, index=True)
    employee_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    total_amount = Column(Numeric(12, 2), nullable=False, default=0)
    total_modal = Column(Numeric(12, 2), nullable=False, default=0)
    total_profit = Column(Numeric(12, 2), nullable=False, default=0)
    discount = Column(Numeric(12, 2), nullable=False, default=0)
    status = Column(String(20), nullable=False, default="COMPLETED")
    canceled_at = Column(DateTime, nullable=True)
    canceled_by = Column(UUID(as_uuid=True), nullable=True)
    canceled_reason = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    employee = relationship("User", back_populates="sales")
    sale_items = relationship("SaleItem", back_populates="sale")
    payment = relationship("Payment", back_populates="sale", uselist=False)

    def to_dict(self):
        return {
            "id": str(self.id),
            "transaction_number": self.transaction_number,
            "employee_id": str(self.employee_id),
            "employee_name": self.employee.full_name if self.employee else None,
            "total_amount": float(self.total_amount),
            "total_modal": float(self.total_modal),
            "total_profit": float(self.total_profit),
            "discount": float(self.discount),
            "status": self.status,
            "canceled_at": self.canceled_at.isoformat() if self.canceled_at else None,
            "canceled_by": str(self.canceled_by) if self.canceled_by else None,
            "canceled_reason": self.canceled_reason,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "items": [item.to_dict() for item in self.sale_items],
            "payment": self.payment.to_dict() if self.payment else None,
        }


class SaleItem(Base):
    __tablename__ = "sale_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sale_id = Column(UUID(as_uuid=True), ForeignKey("sales.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    product_name = Column(String(200), nullable=False)
    unit = Column(String(20), nullable=False)
    unit_price = Column(Numeric(12, 2), nullable=False)
    modal_price = Column(Numeric(12, 2), nullable=False, default=0)
    quantity = Column(Numeric(12, 3), nullable=False)
    subtotal = Column(Numeric(12, 2), nullable=False)

    sale = relationship("Sale", back_populates="sale_items")
    product = relationship("Product", back_populates="sale_items")

    def to_dict(self):
        return {
            "id": str(self.id),
            "sale_id": str(self.sale_id),
            "product_id": str(self.product_id),
            "product_name": self.product_name,
            "unit": self.unit,
            "unit_price": float(self.unit_price),
            "modal_price": float(self.modal_price),
            "quantity": float(self.quantity),
            "subtotal": float(self.subtotal),
        }


class Payment(Base):
    __tablename__ = "payments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sale_id = Column(UUID(as_uuid=True), ForeignKey("sales.id"), nullable=False)
    method = Column(String(20), nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    cash_received = Column(Numeric(12, 2), nullable=True)
    change_amount = Column(Numeric(12, 2), nullable=True)
    reference = Column(String(100), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    sale = relationship("Sale", back_populates="payment")

    def to_dict(self):
        return {
            "id": str(self.id),
            "sale_id": str(self.sale_id),
            "method": self.method,
            "amount": float(self.amount),
            "cash_received": float(self.cash_received) if self.cash_received else None,
            "change_amount": float(self.change_amount) if self.change_amount else None,
            "reference": self.reference,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }