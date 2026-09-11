from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
import uuid


class SaleItemCreate(BaseModel):
    product_id: uuid.UUID
    quantity: float = Field(..., gt=0)
    unit_price: float = Field(..., ge=0)


class PaymentCreate(BaseModel):
    method: str = Field(..., pattern="^(CASH|TRANSFER|QRIS)$")
    amount: float = Field(..., ge=0)
    cash_received: Optional[float] = Field(None, ge=0)
    change_amount: Optional[float] = Field(None, ge=0)
    reference: Optional[str] = None


class SaleCreate(BaseModel):
    id: Optional[uuid.UUID] = None
    transaction_number: Optional[str] = None
    employee_id: Optional[uuid.UUID] = None
    items: List[SaleItemCreate] = Field(..., min_length=1)
    payment: Optional[PaymentCreate] = None
    discount: float = Field(default=0, ge=0)
    device_id: Optional[str] = None
    created_at: Optional[datetime] = None


class SaleCancelRequest(BaseModel):
    reason: str = Field(..., min_length=3, max_length=500)


class SaleResponse(BaseModel):
    id: uuid.UUID
    transaction_number: str
    employee_id: uuid.UUID
    employee_name: Optional[str]
    total_amount: float
    total_modal: float
    total_profit: float
    discount: float
    status: str
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class PurchaseRequest(BaseModel):
    product_id: uuid.UUID
    quantity: float = Field(..., gt=0)
    notes: Optional[str] = None