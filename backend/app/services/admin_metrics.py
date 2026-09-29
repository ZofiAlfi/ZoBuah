"""Agregasi lintas-toko untuk dashboard OWNER.

Semua fungsi di sini hanya boleh dipanggil setelah require_owner() lolos.
Tidak ada satu pun yang menerima User toko sebagai sumber scope, karena
agregat lintas-toko tidak punya makna untuk pengguna toko.

Tiga sumber "kesegaran toko" dipakai dengan tingkat keyakinan berbeda:
  Device.last_sync_at      - kapan perangkat toko terakhir heartbeat.
  SyncEvent.created_at     - kapan server terakhir memproses perubahan.
  Store.updated_at         - kapan admin terakhir mengubah data toko.
Yang dipakai untuk health adalah Device, karena POS offline selalu heartbeat
walau tidak ada penjualan; kalau hanya melihat SyncEvent, toko yang benar-benar
dipakai tapi tidak ada perubahan data akan terlihat MATI.
"""
from datetime import date, datetime, time, timedelta
from typing import Optional
from uuid import UUID

from sqlalchemy import Float, func
from sqlalchemy.orm import Session

from ..models.category import Category
from ..models.damage_report import DamageReport
from ..models.device import Device
from ..models.product import Product
from ..models.sale import Sale
from ..models.store import Plan, Store, StoreStatus
from ..models.sync_event import SyncEvent
from ..models.user import User, UserRole
from ..schemas.admin import HealthRow, PlanRow, RevenuePoint, StoreUsage, TopStore

SALE_DONE = "COMPLETED"
STALE_HOURS = 24


def _f(value) -> float:
    """Numeric dari PostgreSQL datang sebagai Decimal. Dashboard JSON butuh float."""
    return float(value) if value is not None else 0.0


def _window_start(days: int) -> datetime:
    """Awal jendela agregat, presisi sampai pergantian hari.

    Dulu ini `now - N*24 jam`, itu meleset satu hari dari deret harian di
    revenue_series: jendela mulai 30x24 jam lalu, sementara deret harian
    dimulai dari tanggal (hari ini - N + 1). Transaksi di antara kedua batas
    itu terhitung di KPI tapi tidak muncul di grafik, jadi jumlah omzet di
    kartu dan jumlah titik di kurva tidak pernah sama.

    Dasarnya tanggal UTC, sama dengan func.date(Sale.created_at) yang dipakai
    untuk pengelompokan. Kalau di sini dipakai tanggal lokal, keduanya bisa
    bergeser satu hari di zona waktu bukan UTC.
    """
    days = max(1, days)
    return datetime.combine(datetime.utcnow().date() - timedelta(days=days - 1), time.min)


def last_sync_map(db: Session) -> dict:
    """store_id -> waktu sync terakhir dari perangkat."""
    rows = (
        db.query(Device.store_id, func.max(Device.last_sync_at))
        .filter(Device.store_id.isnot(None))
        .group_by(Device.store_id)
        .all()
    )
    return {row[0]: row[1] for row in rows if row[0] is not None}


def _hours_since(moment: Optional[datetime]) -> Optional[float]:
    if moment is None:
        return None
    return round((datetime.utcnow() - moment).total_seconds() / 3600, 1)


def health_of(store: Store, last_sync: Optional[datetime], stale_hours: int = STALE_HOURS) -> str:
    if store.status != StoreStatus.ACTIVE or not store.is_active:
        return "DEAD"
    if last_sync is None:
        return "STALE"
    hours = (datetime.utcnow() - last_sync).total_seconds() / 3600
    if hours > stale_hours * 7:
        return "DEAD"
    return "STALE" if hours > stale_hours else "OK"


def overview(db: Session) -> dict:
    now = date.today()
    soon = now + timedelta(days=7)

    total_stores = db.query(func.count(Store.id)).scalar() or 0
    active_stores = (
        db.query(func.count(Store.id))
        .filter(Store.is_active.is_(True), Store.status == StoreStatus.ACTIVE)
        .scalar()
        or 0
    )
    suspended = (
        db.query(func.count(Store.id))
        .filter(Store.status == StoreStatus.SUSPENDED)
        .scalar()
        or 0
    )
    expired_stores = (
        db.query(func.count(Store.id))
        .filter(
            Store.plan != Plan.UNLIMITED,
            Store.plan_expires_at.isnot(None),
            Store.plan_expires_at < now,
        )
        .scalar()
        or 0
    )
    trial = (
        db.query(func.count(Store.id)).filter(Store.plan == Plan.TRIAL).scalar() or 0
    )
    expiring_soon = (
        db.query(func.count(Store.id))
        .filter(
            Store.plan != Plan.UNLIMITED,
            Store.plan_expires_at.isnot(None),
            Store.plan_expires_at >= now,
            Store.plan_expires_at <= soon,
        )
        .scalar()
        or 0
    )

    total_users = (
        db.query(func.count(User.id)).filter(User.role != UserRole.OWNER.value).scalar() or 0
    )
    total_products = (
        db.query(func.count(Product.id)).filter(Product.is_active.is_(True)).scalar() or 0
    )
    total_devices = (
        db.query(func.count(Device.id)).filter(Device.is_active.is_(True)).scalar() or 0
    )

    start = _window_start(30)
    row = (
        db.query(
            func.count(Sale.id),
            func.coalesce(func.sum(Sale.total_amount), 0),
            func.coalesce(func.sum(Sale.total_profit), 0),
        )
        .filter(Sale.status == SALE_DONE, Sale.created_at >= start)
        .first()
    )
    sales_30d = int(row[0] or 0)
    revenue_30d = _f(row[1])
    profit_30d = _f(row[2])

    pending_damage = (
        db.query(func.count(DamageReport.id))
        .filter(DamageReport.status == "PENDING")
        .scalar()
        or 0
    )

    health_counts = {"OK": 0, "STALE": 0, "DEAD": 0}
    sync_map = last_sync_map(db)
    for store in db.query(Store).all():
        health_counts[health_of(store, sync_map.get(store.id))] += 1

    return {
        "total_stores": total_stores,
        "active_stores": active_stores,
        "suspended_stores": suspended,
        "expired_stores": expired_stores,
        "trial_stores": trial,
        "total_users": total_users,
        "total_products": total_products,
        "total_devices": total_devices,
        "total_sales_30d": sales_30d,
        "revenue_30d": revenue_30d,
        "profit_30d": profit_30d,
        "avg_revenue_per_store_30d": round(revenue_30d / active_stores, 2) if active_stores else 0.0,
        "healthy_stores": health_counts["OK"],
        "stale_stores": health_counts["STALE"],
        "dead_stores": health_counts["DEAD"],
        "pending_damage_total": pending_damage,
        "expiring_soon": expiring_soon,
        "generated_at": datetime.utcnow(),
    }


def revenue_series(db: Session, days: int = 30, store_id: Optional[UUID] = None) -> list:
    """Deret harian. Hari tanpa transaksi tetap dikembalikan dengan nol supaya
    grafik tidak skipping hari dan penjumlahan tidak tampak salah."""
    days = max(1, min(days, 365))
    start = _window_start(days)

    q = db.query(
        func.date(Sale.created_at).label("d"),
        func.count(Sale.id),
        func.coalesce(func.sum(Sale.total_amount), 0),
        func.coalesce(func.sum(Sale.total_modal), 0),
        func.coalesce(func.sum(Sale.total_profit), 0),
    ).filter(Sale.status == SALE_DONE, Sale.created_at >= start)
    if store_id is not None:
        q = q.filter(Sale.store_id == store_id)

    # Kunci bucket harus string ISO. func.date() di PostgreSQL dikembalikan
    # psycopg2 sebagai objek datetime.date; kalau kunci disimpan apa adanya
    # sementara pencarian memakai .isoformat(), tidak akan pernah cocok dan
    # seluruh grafik berubah jadi nol padahal ada ribuan transaksi.
    buckets = {
        row[0].isoformat(): {
            "revenue": _f(row[2]),
            "modal": _f(row[3]),
            "profit": _f(row[4]),
            "transactions": int(row[1] or 0),
        }
        for row in q.group_by(func.date(Sale.created_at)).all()
    }

    out = []
    # UTC, bukan date.today(): tanggal lokal bisa bergeser satu hari dari
    # func.date(Sale.created_at) di zona waktu bukan UTC.
    today = datetime.utcnow().date()
    for offset in range(days - 1, -1, -1):
        day = (today - timedelta(days=offset)).isoformat()
        data = buckets.get(day, {})
        out.append(
            RevenuePoint(
                date=day,
                revenue=data.get("revenue", 0.0),
                modal=data.get("modal", 0.0),
                profit=data.get("profit", 0.0),
                transactions=data.get("transactions", 0),
            )
        )
    return out


def top_stores(db: Session, days: int = 30, limit: int = 5) -> list:
    days = max(1, min(days, 365))
    start = _window_start(days)

    rows = (
        db.query(
            Store.id,
            Store.code,
            Store.name,
            func.coalesce(func.sum(Sale.total_amount), 0),
            func.coalesce(func.sum(Sale.total_profit), 0),
            func.count(Sale.id),
        )
        .join(Sale, Sale.store_id == Store.id)
        .filter(Sale.status == SALE_DONE, Sale.created_at >= start)
        .group_by(Store.id, Store.code, Store.name)
        .order_by(func.coalesce(func.sum(Sale.total_amount), 0).desc())
        .limit(max(1, min(limit, 50)))
        .all()
    )
    return [
        TopStore(
            store_id=row[0],
            code=row[1],
            store_name=row[2],
            revenue=_f(row[3]),
            profit=_f(row[4]),
            transactions=int(row[5] or 0),
        )
        for row in rows
    ]


def plan_breakdown(db: Session) -> list:
    start = _window_start(30)
    now = date.today()

    sales_by_store = dict(
        db.query(Sale.store_id, func.coalesce(func.sum(Sale.total_amount), 0))
        .filter(Sale.status == SALE_DONE, Sale.created_at >= start)
        .group_by(Sale.store_id)
        .all()
    )

    out = []
    for plan in Plan.ALL:
        stores = db.query(Store).filter(Store.plan == plan).all()
        active = [s for s in stores if s.is_active and s.status == StoreStatus.ACTIVE]
        expired = [
            s
            for s in stores
            if s.plan != Plan.UNLIMITED
            and s.plan_expires_at is not None
            and s.plan_expires_at < now
        ]
        revenue = sum(_f(sales_by_store.get(s.id, 0)) for s in stores)
        out.append(
            PlanRow(
                plan=plan,
                store_count=len(stores),
                active_store_count=len(active),
                expired_count=len(expired),
                revenue_30d=round(revenue, 2),
            )
        )
    return out


def store_usage(db: Session, store_id: Optional[UUID] = None) -> list:
    start = _window_start(30)
    sync_map = last_sync_map(db)

    # store_id -> (jumlah transaksi, total omzet). Baris agregat punya tiga
    # kolom sehingga tidak bisa langsung diempar ke dict().
    sales_by_store = {
        row[0]: (int(row[1] or 0), _f(row[2]))
        for row in db.query(
            Sale.store_id,
            func.count(Sale.id),
            func.coalesce(func.sum(Sale.total_amount), 0),
        )
        .filter(Sale.status == SALE_DONE, Sale.created_at >= start)
        .group_by(Sale.store_id)
        .all()
    }

    def count_for(model, **filters):
        q = db.query(func.count(model.id))
        if store_id is not None:
            q = q.filter(model.store_id == store_id)
        for key, value in filters.items():
            q = q.filter(getattr(model, key) == value)
        return q.scalar() or 0

    users_by_store = dict(
        db.query(User.store_id, func.count(User.id))
        .filter(User.store_id.isnot(None))
        .group_by(User.store_id)
        .all()
    )
    products_by_store = dict(
        db.query(Product.store_id, func.count(Product.id))
        .filter(Product.store_id.isnot(None), Product.is_active.is_(True))
        .group_by(Product.store_id)
        .all()
    )
    categories_by_store = dict(
        db.query(Category.store_id, func.count(Category.id))
        .filter(Category.store_id.isnot(None))
        .group_by(Category.store_id)
        .all()
    )
    devices_by_store = dict(
        db.query(Device.store_id, func.count(Device.id))
        .filter(Device.store_id.isnot(None), Device.is_active.is_(True))
        .group_by(Device.store_id)
        .all()
    )

    q = db.query(Store)
    if store_id is not None:
        q = q.filter(Store.id == store_id)

    out = []
    for store in q.all():
        sales = sales_by_store.get(store.id)
        out.append(
            StoreUsage(
                store_id=store.id,
                code=store.code,
                store_name=store.name,
                plan=store.plan,
                user_count=users_by_store.get(store.id, 0),
                product_count=products_by_store.get(store.id, 0),
                category_count=categories_by_store.get(store.id, 0),
                device_count=devices_by_store.get(store.id, 0),
                sale_count_30d=int(sales[0]) if sales else 0,
                revenue_30d=round(sales[1] if sales else 0, 2),
                last_sync_at=sync_map.get(store.id),
                health=health_of(store, sync_map.get(store.id)),
            )
        )
    return out


def store_health(db: Session, stale_hours: int = STALE_HOURS) -> list:
    sync_map = last_sync_map(db)
    start = _window_start(7)

    failed = dict(
        db.query(SyncEvent.store_id, func.count(SyncEvent.id))
        .filter(
            SyncEvent.store_id.isnot(None),
            SyncEvent.status == "FAILED",
            SyncEvent.created_at >= start,
        )
        .group_by(SyncEvent.store_id)
        .all()
    )
    devices = dict(
        db.query(Device.store_id, func.count(Device.id))
        .filter(Device.store_id.isnot(None), Device.is_active.is_(True))
        .group_by(Device.store_id)
        .all()
    )

    out = []
    for store in db.query(Store).all():
        last_sync = sync_map.get(store.id)
        out.append(
            HealthRow(
                store_id=store.id,
                code=store.code,
                store_name=store.name,
                health=health_of(store, last_sync, stale_hours),
                last_sync_at=last_sync,
                hours_since_sync=_hours_since(last_sync),
                device_count=devices.get(store.id, 0),
                failed_sync_7d=failed.get(store.id, 0),
            )
        )
    return out
