from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
import uuid


class DamageReportCreate(BaseModel):
    id: Optional[uuid.UUID] = None
    product_id: uuid.UUID
    quantity: float = Field(..., gt=0)
    unit: str = Field(..., max_length=20)
    reason: str = Field(..., max_length=50)
    description: Optional[str] = None
    employee_id: Optional[uuid.UUID] = None
    photos: List[str] = Field(default_factory=list)
    device_id: Optional[str] = None
    created_at: Optional[datetime] = None


class DamageReportApprove(BaseModel):
    reason: Optional[str] = None


class DamageReportReject(BaseModel):
    reason: str = Field(..., min_length=3, max_length=500)


class DamageReportResponse(BaseModel):
    id: uuid.UUID
    product_id: uuid.UUID
    product_name: Optional[str]
    quantity: float
    unit: str
    reason: str
    description: Optional[str]
    status: str
    employee_id: uuid.UUID
    employee_name: Optional[str]
    approved_by: Optional[uuid.UUID]
    approved_at: Optional[datetime] = None
    rejected_by: Optional[uuid.UUID]
    rejected_at: Optional[datetime] = None
    rejection_reason: Optional[str]
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None