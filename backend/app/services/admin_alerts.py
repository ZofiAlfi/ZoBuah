"""Alert untuk OWNER.

Semua alert dihitung on-read, tidak disimpan di tabel. Alasannya: kondisi yang
dipantau (paket hampir habis, perangkat diam, laporan rusak menggantung) berubah
karena waktu atau karena admin sendiri yang mengubahnya. Tabel alert butuh
pekerjaan untuk mendeteksi perubahan dan mudah basi, sementara calculer ulang
di setiap dashboard visit selalu benar dan belum pernah lewat.

Urutan severity dipakai dashboard: CRITICAL di atas, lalu WARNING, lalu INFO.
"""
from datetime import date, datetime, timedelta
from typing import Optional
from uuid import UUID

from sqlalchemy import func
from sqlalchemy.orm import Session

from ..models.damage_report import DamageReport
from ..utilities.helpers import iso_utc
from ..models.product import Product
from ..models.store import Plan, Store, StoreStatus
from ..models.sync_event import SyncEvent
from ..config import settings
from ..schemas.admin import AlertItem
from .admin_metrics import STALE_HOURS, health_of, last_sync_map

SEVERITY_ORDER = {"CRITICAL": 0, "WARNING": 1, "INFO": 2}
EXPIRY_WARNING_DAYS = 7
PENDING_DAMAGE_DAYS = 3


def _window_start(days: int) -> datetime:
    return datetime.utcnow() - timedelta(days=days)


def _store_label(store: Optional[Store]) -> tuple:
    if store is None:
        return None, None
    return store.id, store.name


def collect_alerts(db: Session, stale_hours: int = STALE_HOURS) -> list:
    now = datetime.utcnow()
    today = date.today()
    horizon = today + timedelta(days=EXPIRY_WARNING_DAYS)
    alerts: list = []

    sync_map = last_sync_map(db)
    stores = db.query(Store).all()
    by_id = {s.id: s for s in stores}

    for store in stores:
        sid, sname = _store_label(store)

        if store.status == StoreStatus.SUSPENDED or not store.is_active:
            alerts.append(
                AlertItem(
                    code="STORE_SUSPENDED",
                    severity="INFO",
                    title=f"{store.name} sedang ditangguhkan",
                    message="Toko tidak bisa login POS sampai diaktifkan kembali.",
                    store_id=sid,
                    store_name=sname,
                )
            )
            continue

        if store.plan != Plan.UNLIMITED and store.plan_expires_at is not None:
            if store.plan_expires_at < today:
                alerts.append(
                    AlertItem(
                        code="PLAN_EXPIRED",
                        severity="CRITICAL",
                        title=f"{store.name} — paket {store.plan} sudah habis",
                        message=f"Habis pada {store.plan_expires_at.isoformat()}. Perpanjang atau.downgrade paket.",
                        store_id=sid,
                        store_name=sname,
                    )
                )
            elif store.plan_expires_at <= horizon:
                left = (store.plan_expires_at - today).days
                alerts.append(
                    AlertItem(
                        code="PLAN_EXPIRING",
                        severity="WARNING",
                        title=f"{store.name} — paket habis {left} hari lagi",
                        message=f"Berakhir {store.plan_expires_at.isoformat()}. Ingatkan pelanggan sebelum akses terputus.",
                        store_id=sid,
                        store_name=sname,
                    )
                )

        health = health_of(store, sync_map.get(store.id), stale_hours)
        if health == "DEAD":
            last_sync = sync_map.get(store.id)
            detail = (
                f"Sync terakhir {iso_utc(last_sync)}." if last_sync else "Belum pernah sync."
            )
            alerts.append(
                AlertItem(
                    code="STORE_OFFLINE",
                    severity="CRITICAL",
                    title=f"{store.name} tidak terlihat online",
                    message=f"{detail} Periksa perangkat dan koneksi toko.",
                    store_id=sid,
                    store_name=sname,
                )
            )
        elif health == "STALE":
            alerts.append(
                AlertItem(
                    code="STORE_STALE",
                    severity="WARNING",
                    title=f"{store.name} jarang sync",
                    message=f"Tidak ada heartbeat perangkat dalam {stale_hours} jam.",
                    store_id=sid,
                    store_name=sname,
                )
            )

    cutoff = _window_start(settings.ALERT_WINDOW_DAYS)
    failed = (
        db.query(SyncEvent.store_id, func.count(SyncEvent.id))
        .filter(
            SyncEvent.status == "FAILED",
            SyncEvent.created_at >= cutoff,
        )
        .group_by(SyncEvent.store_id)
        .all()
    )
    for store_id, count in failed:
        if count:
            store = by_id.get(store_id)
            sid, sname = _store_label(store)
            alerts.append(
                AlertItem(
                    code="SYNC_FAILURES",
                    severity="WARNING",
                    title=f"{sname or 'Toko tanpa nama'} — {count} sync gagal",
                    message="Periksa antrean sinkronisasi dan pesan error di log sync.",
                    store_id=sid,
                    store_name=sname,
                )
            )

    pending_cutoff = now - timedelta(days=PENDING_DAMAGE_DAYS)
    stale_pending = (
        db.query(DamageReport.store_id, func.count(DamageReport.id))
        .filter(DamageReport.status == "PENDING", DamageReport.created_at < pending_cutoff)
        .group_by(DamageReport.store_id)
        .all()
    )
    for store_id, count in stale_pending:
        if count:
            store = by_id.get(store_id)
            sid, sname = _store_label(store)
            alerts.append(
                AlertItem(
                    code="DAMAGE_PENDING",
                    severity="WARNING",
                    title=f"{sname or 'Toko tanpa nama'} — {count} laporan rusak belum diputuskan",
                    message=f"Sudah menunggu lebih dari {PENDING_DAMAGE_DAYS} hari. Laporan menggantung membuat stok terus berkurang tanpa persetujuan.",
                    store_id=sid,
                    store_name=sname,
                )
            )

    low_stock = (
        db.query(Product.store_id, func.count(Product.id))
        .filter(
            Product.is_active.is_(True),
            Product.stock <= Product.min_stock,
            Product.min_stock > 0,
        )
        .group_by(Product.store_id)
        .all()
    )
    for store_id, count in low_stock:
        if count:
            store = by_id.get(store_id)
            sid, sname = _store_label(store)
            alerts.append(
                AlertItem(
                    code="LOW_STOCK",
                    severity="INFO",
                    title=f"{sname or 'Toko tanpa nama'} — {count} produk di bawah stok minimum",
                    message="Produk menyentuh batas minimum. Segera cek untuk tetap bisa berjualan.",
                    store_id=sid,
                    store_name=sname,
                )
            )

    alerts.sort(
        key=lambda a: (SEVERITY_ORDER.get(a.severity, 9), a.store_name or "", a.code)
    )
    return alerts
