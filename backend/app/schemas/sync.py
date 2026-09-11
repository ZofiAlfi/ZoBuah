from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime
import uuid


class SyncPushItem(BaseModel):
    entity_type: str
    entity_id: str
    data: dict
    device_id: Optional[str] = None


class SyncPushRequest(BaseModel):
    device_id: Optional[str] = None
    items: List[SyncPushItem] = []


class SyncPushResponse(BaseModel):
    accepted: int
    rejected: int
    results: List[dict]


class SyncPullRequest(BaseModel):
    device_id: Optional[str] = None
    last_sync_at: Optional[datetime] = None


class SyncPullResponse(BaseModel):
    products: List[dict] = []
    categories: List[dict] = []
    damage_reports: List[dict] = []
    stock_movements: List[dict] = []
    sales: List[dict] = []
    server_time: str