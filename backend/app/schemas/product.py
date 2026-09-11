from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
import uuid


class CategoryCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None


class CategoryUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = None


class CategoryResponse(BaseModel):
    id: uuid.UUID
    name: str
    description: Optional[str]
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class ProductCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    category_id: Optional[uuid.UUID] = None
    unit: str = Field(default="kg", max_length=20)
    modal_price: float = Field(default=0, ge=0)
    selling_price: float = Field(default=0, ge=0)
    stock: float = Field(default=0, ge=0)
    min_stock: float = Field(default=0, ge=0)
    is_active: bool = True
    description: Optional[str] = None


class ProductUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    category_id: Optional[uuid.UUID] = None
    unit: Optional[str] = Field(None, max_length=20)
    modal_price: Optional[float] = Field(None, ge=0)
    selling_price: Optional[float] = Field(None, ge=0)
    min_stock: Optional[float] = Field(None, ge=0)
    is_active: Optional[bool] = None
    description: Optional[str] = None


class ProductResponse(BaseModel):
    id: uuid.UUID
    name: str
    category_id: Optional[uuid.UUID]
    category_name: Optional[str]
    unit: str
    modal_price: float
    selling_price: float
    stock: float
    min_stock: float
    is_active: bool
    description: Optional[str]
    photo_url: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class StockInRequest(BaseModel):
    product_id: uuid.UUID
    quantity: float = Field(..., gt=0)
    notes: Optional[str] = None