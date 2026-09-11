from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
import uuid


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: dict


class LoginRequest(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=6, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str


class UserCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=6, max_length=128)
    full_name: str = Field(..., min_length=1, max_length=100)
    role: str = Field(default="KARYAWAN", pattern="^(BOS|KARYAWAN)$")


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    password: Optional[str] = Field(None, min_length=6, max_length=128)
    role: Optional[str] = Field(None, pattern="^(BOS|KARYAWAN)$")
    is_active: Optional[bool] = None


class UserResponse(BaseModel):
    id: uuid.UUID
    username: str
    full_name: str
    role: str
    is_active: bool
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None