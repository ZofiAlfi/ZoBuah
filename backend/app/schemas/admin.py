from datetime import date, datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from ..models.broadcast import BroadcastLevel, BroadcastTarget
from ..models.store import Plan, StoreStatus


class AdminLoginRequest(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=4, max_length=128)


class AdminRefreshRequest(BaseModel):
    refresh_token: str


class OwnerProfile(BaseModel):
    id: UUID
    username: str
    full_name: str
    created_at: Optional[datetime] = None


class AdminTokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    owner: OwnerProfile


class StoreCreate(BaseModel):
    code: str = Field(..., min_length=2, max_length=20)
    name: str = Field(..., min_length=2, max_length=100)
    owner_name: str = Field(..., min_length=2, max_length=100)
    phone: Optional[str] = Field(None, max_length=20)
    address: Optional[str] = None
    plan: str = Plan.TRIAL
    plan_expires_at: Optional[date] = None
    status: str = StoreStatus.ACTIVE
    bos_username: str = Field(..., min_length=3, max_length=50)
    bos_password: str = Field(..., min_length=8, max_length=128)
    bos_full_name: str = Field(..., min_length=1, max_length=100)
    category_names: list[str] = Field(default_factory=list, max_length=50)

    @field_validator("code")
    @classmethod
    def _normalise_code(cls, v: str) -> str:
        # Kode dipakai sebagai username perangkat dan label di laporan, jadi
        # dikunci ke huruf besar agar "zb-01" dan "ZB-01" tidak jadi dua toko.
        v = v.strip().upper()
        if not all(c.isalnum() or c in "-_" for c in v):
            raise ValueError("Kode toko hanya boleh huruf, angka, tanda hubung, dan garis bawah")
        return v

    @field_validator("plan")
    @classmethod
    def _check_plan(cls, v: str) -> str:
        if v not in Plan.ALL:
            raise ValueError(f"Paket harus salah satu dari: {', '.join(Plan.ALL)}")
        return v

    @field_validator("status")
    @classmethod
    def _check_status(cls, v: str) -> str:
        if v not in StoreStatus.ALL:
            raise ValueError(f"Status harus salah satu dari: {', '.join(StoreStatus.ALL)}")
        return v

    @field_validator("category_names")
    @classmethod
    def _dedupe_categories(cls, v: list[str]) -> list[str]:
        seen: set[str] = set()
        out: list[str] = []
        for name in v:
            clean = name.strip()
            if not clean:
                continue
            key = clean.casefold()
            if key in seen:
                continue
            seen.add(key)
            out.append(clean[:100])
        return out


class StoreUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=2, max_length=100)
    owner_name: Optional[str] = Field(None, min_length=2, max_length=100)
    phone: Optional[str] = Field(None, max_length=20)
    address: Optional[str] = None
    plan: Optional[str] = None
    plan_expires_at: Optional[date] = None
    status: Optional[str] = None
    is_active: Optional[bool] = None

    @field_validator("plan")
    @classmethod
    def _check_plan(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in Plan.ALL:
            raise ValueError(f"Paket harus salah satu dari: {', '.join(Plan.ALL)}")
        return v

    @field_validator("status")
    @classmethod
    def _check_status(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in StoreStatus.ALL:
            raise ValueError(f"Status harus salah satu dari: {', '.join(StoreStatus.ALL)}")
        return v


class StoreListItem(BaseModel):
    id: UUID
    code: str
    name: str
    owner_name: str
    phone: Optional[str] = None
    address: Optional[str] = None
    plan: str
    plan_expires_at: Optional[date] = None
    days_to_expiry: Optional[int] = None
    status: str
    is_active: bool
    health: str
    last_sync_at: Optional[datetime] = None
    user_count: int = 0
    product_count: int = 0
    sale_count_30d: int = 0
    revenue_30d: float = 0
    created_at: Optional[datetime] = None


class StoreDetail(StoreListItem):
    device_count: int = 0
    category_count: int = 0
    product_count: int = 0
    low_stock_count: int = 0
    pending_damage_count: int = 0
    failed_sync_count_7d: int = 0
    total_sales: int = 0
    lifetime_revenue: float = 0


class AdminUserItem(BaseModel):
    id: UUID
    username: str
    full_name: str
    role: str
    is_active: bool
    store_id: Optional[UUID] = None
    store_name: Optional[str] = None
    created_at: Optional[datetime] = None


class AdminUserCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=8, max_length=128)
    full_name: str = Field(..., min_length=1, max_length=100)
    role: str = "KARYAWAN"

    @field_validator("role")
    @classmethod
    def _check_role(cls, v: str) -> str:
        if v not in {"BOS", "KARYAWAN"}:
            raise ValueError("Role harus BOS atau KARYAWAN")
        return v


class AdminUserUpdate(BaseModel):
    full_name: Optional[str] = Field(None, min_length=1, max_length=100)
    password: Optional[str] = Field(None, min_length=8, max_length=128)
    role: Optional[str] = None
    is_active: Optional[bool] = None

    @field_validator("role")
    @classmethod
    def _check_role(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in {"BOS", "KARYAWAN"}:
            raise ValueError("Role harus BOS atau KARYAWAN")
        return v


class PasswordResetResult(BaseModel):
    user_id: UUID
    username: str
    temporary_password: str
    message: str


class ForceLogoutResult(BaseModel):
    user_id: UUID
    username: str
    token_version: int
    message: str


class ImpersonateRequest(BaseModel):
    store_id: UUID


class ImpersonateResult(BaseModel):
    access_token: str
    token_type: str = "bearer"
    read_only: bool = True
    expires_in_minutes: int
    store: dict


class BroadcastCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=120)
    body: str = Field(..., min_length=1, max_length=4000)
    level: str = BroadcastLevel.INFO
    target: str = BroadcastTarget.ALL
    store_id: Optional[UUID] = None
    starts_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    is_active: bool = True

    @field_validator("level")
    @classmethod
    def _check_level(cls, v: str) -> str:
        if v not in BroadcastLevel.ALL:
            raise ValueError(f"Level harus salah satu dari: {', '.join(BroadcastLevel.ALL)}")
        return v

    @field_validator("target")
    @classmethod
    def _check_target(cls, v: str) -> str:
        if v not in BroadcastTarget.ALL_TARGETS:
            raise ValueError(
                f"Target harus salah satu dari: {', '.join(BroadcastTarget.ALL_TARGETS)}"
            )
        return v

    @field_validator("expires_at")
    @classmethod
    def _check_window(cls, v: Optional[datetime], info) -> Optional[datetime]:
        starts = info.data.get("starts_at")
        if v is not None and starts is not None and v <= starts:
            raise ValueError("Waktu berakhir harus setelah waktu mulai")
        return v


class BroadcastUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=120)
    body: Optional[str] = Field(None, min_length=1, max_length=4000)
    level: Optional[str] = None
    target: Optional[str] = None
    store_id: Optional[UUID] = None
    starts_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    is_active: Optional[bool] = None

    @field_validator("level")
    @classmethod
    def _check_level(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in BroadcastLevel.ALL:
            raise ValueError(f"Level harus salah satu dari: {', '.join(BroadcastLevel.ALL)}")
        return v

    @field_validator("target")
    @classmethod
    def _check_target(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in BroadcastTarget.ALL_TARGETS:
            raise ValueError(
                f"Target harus salah satu dari: {', '.join(BroadcastTarget.ALL_TARGETS)}"
            )
        return v


class BroadcastItem(BaseModel):
    id: UUID
    title: str
    body: str
    level: str
    target: str
    store_id: Optional[UUID] = None
    store_name: Optional[str] = None
    starts_at: datetime
    expires_at: Optional[datetime] = None
    is_active: bool
    created_by: Optional[UUID] = None
    created_at: datetime


class RevenuePoint(BaseModel):
    date: date
    revenue: float = 0
    modal: float = 0
    profit: float = 0
    transactions: int = 0


class TopStore(BaseModel):
    store_id: UUID
    code: str
    store_name: str
    revenue: float = 0
    profit: float = 0
    transactions: int = 0


class PlanRow(BaseModel):
    plan: str
    store_count: int = 0
    active_store_count: int = 0
    expired_count: int = 0
    revenue_30d: float = 0


class StoreUsage(BaseModel):
    store_id: UUID
    code: str
    store_name: str
    plan: str
    user_count: int = 0
    product_count: int = 0
    category_count: int = 0
    device_count: int = 0
    sale_count_30d: int = 0
    revenue_30d: float = 0
    last_sync_at: Optional[datetime] = None
    health: str


class HealthRow(BaseModel):
    store_id: UUID
    code: str
    store_name: str
    health: str
    last_sync_at: Optional[datetime] = None
    hours_since_sync: Optional[float] = None
    device_count: int = 0
    failed_sync_7d: int = 0


class AlertItem(BaseModel):
    code: str
    severity: str
    title: str
    message: str
    store_id: Optional[UUID] = None
    store_name: Optional[str] = None
    created_at: Optional[datetime] = None


class AuditLogItem(BaseModel):
    id: UUID
    user_id: Optional[UUID] = None
    username: Optional[str] = None
    store_id: Optional[UUID] = None
    store_name: Optional[str] = None
    action: str
    entity_type: Optional[str] = None
    entity_id: Optional[str] = None
    details: Optional[str] = None
    ip_address: Optional[str] = None
    created_at: Optional[datetime] = None


class PageMeta(BaseModel):
    page: int
    page_size: int
    total: int
    total_pages: int


class StoreListResponse(BaseModel):
    items: list[StoreListItem]
    meta: PageMeta


class AdminUserListResponse(BaseModel):
    items: list[AdminUserItem]
    meta: PageMeta


class BroadcastListResponse(BaseModel):
    items: list[BroadcastItem]
    meta: PageMeta


class AuditLogListResponse(BaseModel):
    items: list[AuditLogItem]
    meta: PageMeta


class OverviewResponse(BaseModel):
    total_stores: int = 0
    active_stores: int = 0
    suspended_stores: int = 0
    expired_stores: int = 0
    trial_stores: int = 0
    total_users: int = 0
    total_products: int = 0
    total_devices: int = 0
    total_sales_30d: int = 0
    revenue_30d: float = 0
    profit_30d: float = 0
    avg_revenue_per_store_30d: float = 0
    healthy_stores: int = 0
    stale_stores: int = 0
    dead_stores: int = 0
    pending_damage_total: int = 0
    expiring_soon: int = 0
    open_alerts: int = 0
    generated_at: datetime


# --- Produk satu toko (pemilih produk saat edit transaksi) ---
class StoreProductItem(BaseModel):
    id: UUID
    store_id: Optional[UUID] = None
    name: str
    category_name: Optional[str] = None
    unit: str
    modal_price: float = 0
    selling_price: float = 0
    stock: float = 0
    is_active: bool


class StoreProductListResponse(BaseModel):
    items: list[StoreProductItem]
    meta: PageMeta


# --- Edit transaksi oleh OWNER (koreksi data salah input karyawan) ---
class SaleEditItem(BaseModel):
    product_id: UUID
    quantity: float = Field(..., gt=0)
    unit_price: float = Field(..., ge=0)


class SaleEditPayment(BaseModel):
    method: str = Field(..., pattern="^(CASH|TRANSFER|QRIS)$")
    amount: float = Field(..., ge=0)
    cash_received: Optional[float] = Field(None, ge=0)
    change_amount: Optional[float] = Field(None, ge=0)
    reference: Optional[str] = None


class SaleEditRequest(BaseModel):
    reason: Optional[str] = Field(None, max_length=500)
    items: list[SaleEditItem] = Field(..., min_length=1)
    discount: float = Field(default=0, ge=0)
    payment: Optional[SaleEditPayment] = None


class SaleDeleteRequest(BaseModel):
    reason: Optional[str] = Field(None, max_length=500)


class SaleItemSnapshot(BaseModel):
    id: UUID
    sale_id: UUID
    product_id: UUID
    product_name: str
    unit: str
    unit_price: float
    modal_price: float
    quantity: float
    subtotal: float


class PaymentSnapshot(BaseModel):
    id: UUID
    sale_id: UUID
    method: str
    amount: float
    cash_received: Optional[float] = None
    change_amount: Optional[float] = None
    reference: Optional[str] = None
    file_url: Optional[str] = None


class AdminSaleData(BaseModel):
    id: UUID
    store_id: Optional[UUID] = None
    transaction_number: str
    employee_id: UUID
    employee_name: Optional[str] = None
    total_amount: float
    total_modal: float
    total_profit: float
    discount: float
    status: str
    canceled_at: Optional[str] = None
    canceled_by: Optional[UUID] = None
    canceled_reason: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


class AdminSaleListItem(AdminSaleData):
    item_count: int


class AdminSaleListResponse(BaseModel):
    items: list[AdminSaleListItem]
    meta: PageMeta


class AdminSaleDetail(AdminSaleData):
    items: list[SaleItemSnapshot]
    payment: Optional[PaymentSnapshot] = None
    edit_history: list[AuditLogItem] = []

class DamageReportItem(BaseModel):
    id: UUID
    store_id: Optional[UUID] = None
    product_id: Optional[UUID] = None
    product_name: Optional[str] = None
    quantity: float
    unit: str
    qty_in_base_unit: Optional[float] = None
    reason: str
    description: Optional[str] = None
    status: str
    employee_id: Optional[UUID] = None
    employee_name: Optional[str] = None
    approved_by_name: Optional[str] = None
    approved_at: Optional[datetime] = None
    rejected_by_name: Optional[str] = None
    rejected_at: Optional[datetime] = None
    rejection_reason: Optional[str] = None
    photos: list[str] = []
    created_at: Optional[datetime] = None


class DamageReportListResponse(BaseModel):
    items: list[DamageReportItem]
    meta: PageMeta
    summary: dict = {}


class StockMovementItem(BaseModel):
    id: UUID
    product_id: Optional[UUID] = None
    product_name: Optional[str] = None
    movement_type: str
    quantity: float
    stock_before: float
    stock_after: float
    reference_type: Optional[str] = None
    notes: Optional[str] = None
    user_name: Optional[str] = None
    created_at: Optional[datetime] = None


class StockMovementListResponse(BaseModel):
    items: list[StockMovementItem]
    meta: PageMeta
    summary: dict = {}


class PaymentItem(BaseModel):
    id: UUID
    sale_id: Optional[UUID] = None
    transaction_number: Optional[str] = None
    method: str
    amount: float
    cash_received: Optional[float] = None
    change_amount: Optional[float] = None
    reference: Optional[str] = None
    file_url: Optional[str] = None
    employee_name: Optional[str] = None
    sale_status: Optional[str] = None
    created_at: Optional[datetime] = None


class PaymentListResponse(BaseModel):
    items: list[PaymentItem]
    meta: PageMeta
    summary: dict = {}


class ProductHistoryItem(BaseModel):
    id: UUID
    action: str
    product_id: Optional[str] = None
    product_name: Optional[str] = None
    details: Optional[dict] = None
    user_name: Optional[str] = None
    ip_address: Optional[str] = None
    created_at: Optional[datetime] = None


class ProductHistoryResponse(BaseModel):
    items: list[ProductHistoryItem]
    meta: PageMeta


class CategoryItem(BaseModel):
    id: UUID
    name: str
    description: Optional[str] = None
    is_active: bool
    product_count: int = 0
    created_at: Optional[datetime] = None


class CategoryListResponse(BaseModel):
    items: list[CategoryItem]
    meta: PageMeta
