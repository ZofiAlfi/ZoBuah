import uuid as _uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import and_, or_, text
from sqlalchemy.orm import Session

from ..database import get_db
from ..utilities.helpers import iso_utc
from ..models.user import User, UserRole
from ..models.product import Product
from ..models.category import Category
from ..models.sale import Sale, SaleItem, Payment
from ..models.damage_report import DamageReport, DamagePhoto
from ..models.stock_movement import StockMovement
from ..models.sync_event import SyncEvent
from ..models.broadcast import Broadcast, BroadcastLevel, BroadcastTarget
from ..schemas.sync import SyncPushRequest, SyncPullRequest, SyncPullResponse
from ..security import get_current_user, register_device, log_audit
from ..tenancy import require_store_id

router = APIRouter(prefix="/sync", tags=["sync"])


def _finish_sale(db: Session, data: dict, sale: Sale, entity_id: str, body, store_id):
    """Simpan pembayaran + catat SyncEvent, lalu commit satu kali.

    Dipisah dari loop utama supaya alur "semua item berhasil -> commit"
    hanya ada di satu tempat. Kalau pembayaran gagal disimpan, transaksi
    tetap tercatat karena foto bukti pembayaran bukan hal kritis.
    """
    pay = data.get("payment")
    if pay:
        payment_kwargs = {}
        if pay.get("photo"):
            import base64
            from ..services.storage import storage
            try:
                photo_bytes = base64.b64decode(pay["photo"])
                rel_key = f"payment/{sale.id}_0.jpg"
                storage.save_bytes(rel_key, photo_bytes, "image/jpeg")
                payment_kwargs = {
                    "file_path": rel_key,
                    "file_url": storage.url(rel_key),
                }
            except Exception:
                pass
        db.add(Payment(
            sale_id=sale.id,
            method=pay.get("method", "CASH"),
            amount=pay.get("amount", 0),
            cash_received=pay.get("cash_received"),
            change_amount=pay.get("change_amount"),
            reference=pay.get("reference"),
            **payment_kwargs,
        ))

    db.add(SyncEvent(
        event_type="PUSH",
        entity_type="sale",
        entity_id=entity_id,
        device_id=body.device_id,
        server_reference=str(sale.id),
        status="PROCESSED",
        store_id=store_id,
    ))
    db.commit()


@router.post("/push")
def push_data(
    body: SyncPushRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Push hanya untuk akun toko. OWNER sengaja ditolak: dia tidak punya
    # toko, jadi tidak boleh menulis transaksi ke toko manapun.
    store_id = require_store_id(current_user)

    if body.device_id:
        register_device(
            db, body.device_id, platform="android",
            device_name="android-device", store_id=store_id,
        )

    def scoped(model):
        """Semua lookup entitas WAJIB ter-scope ke store_id."""
        return db.query(model).filter(model.store_id == store_id)

    def resolve_employee(raw_id):
        """employee_id dari klien tidak boleh dipercaya mentah-mentah.

        Kalau tidak divalidasi, satu toko bisa mencatat penjualan atas nama
        karyawan toko lain dan menyedot data karyawannya lewat laporan.
        Mengembalikan None bila tidak ditemukan, supaya pemanggil MENOLAK
        item, bukan diam-diam mengganti ke pemanggil sendiri.
        """
        if not raw_id:
            return current_user.id
        emp = (
            db.query(User)
            .filter(User.id == raw_id, User.store_id == store_id, User.is_active == True)
            .first()
        )
        return emp.id if emp else None

    accepted = 0
    rejected = 0
    results = []

    for item in body.items:
        entity_type = item.entity_type
        entity_id = item.entity_id
        data = item.data or {}

        try:
            # Idempotency check: skip if entity already exists on server
            if entity_type == "sale":
                existing = scoped(Sale).filter(Sale.id == entity_id).first()
                if existing:
                    db.add(SyncEvent(
                        event_type="SKIP_DUPLICATE",
                        entity_type="sale",
                        entity_id=entity_id,
                        device_id=body.device_id,
                        status="PROCESSED",
                        store_id=store_id,
                    ))
                    db.commit()
                    rejected += 1
                    results.append({"entity_id": entity_id, "status": "duplicate"})
                    continue

                employee_id = resolve_employee(data.get("employee_id"))
                if employee_id is None:
                    db.rollback()
                    rejected += 1
                    results.append({"entity_id": entity_id, "status": "employee_not_found"})
                    continue
                transaction_number = data.get("transaction_number") or _uuid.uuid4().__str__()[:8].upper()

                # products = pasangan (item, produk). Semua HARUS ketemu produk
                # milik toko ini sebelum transaksi dibuat. Kalau ada yang tidak
                # ketemu, tolak seluruh item. Versi sebelumnya memakai
                # `if product:` sehingga produk asing hanya dilewati dan
                # transaksi tetap tersimpan tanpa item sama sekali.
                line_items = []
                missing_product = False
                inactive_product = None
                for si in data.get("items", []):
                    # Produk WAJIB milik toko ini. Tanpa filter ini, satu toko
                    # bisa menjual produk toko lain dan menguras stoknya.
                    product = scoped(Product).filter(Product.id == si["product_id"]).first()
                    if not product:
                        missing_product = True
                        break
                    # Produk nonaktif tidak boleh terjual. Penjualan online
                    # sudah memeriksanya di sale.py, jadi tanpa cek yang sama
                    # di sini, kasir yang masih offline bisa menjual produk
                    # yang baru saja dinonaktifkan BOS dan server tetap
                    # menerima, termasuk menguras stoknya.
                    if not product.is_active:
                        inactive_product = product.name
                        break
                    line_items.append((si, product))

                if missing_product:
                    db.rollback()
                    rejected += 1
                    results.append({"entity_id": entity_id, "status": "product_not_found"})
                    continue

                if inactive_product:
                    db.rollback()
                    rejected += 1
                    results.append({
                        "entity_id": entity_id,
                        "status": "product_inactive",
                        "detail": f"{inactive_product} sudah dinonaktifkan",
                    })
                    continue

                sale = Sale(
                    id=entity_id,
                    transaction_number=transaction_number,
                    employee_id=employee_id,
                    store_id=store_id,
                    total_amount=data.get("total_amount", 0),
                    total_modal=data.get("total_modal", 0),
                    total_profit=data.get("total_profit", 0),
                    discount=data.get("discount", 0),
                    status=data.get("status", "COMPLETED"),
                    created_at=_as_stored_utc(data.get("created_at")),
                )
                db.add(sale)
                db.flush()

                for si, product in line_items:
                    db.add(SaleItem(
                        sale_id=sale.id,
                        product_id=si["product_id"],
                        product_name=si.get("product_name", product.name),
                        unit=si.get("unit", product.unit),
                        unit_price=si.get("unit_price", 0),
                        modal_price=si.get("modal_price", 0),
                        quantity=si.get("quantity", 0),
                        subtotal=si.get("subtotal", 0),
                    ))
                    # Potong stok di server karena penjualan dibuat offline di HP.
                    from ..services.stock_service import record_sale_quantity
                    try:
                        record_sale_quantity(db, product, sale.id, si.get("quantity", 0), current_user)
                    except Exception:
                        db.rollback()
                        rejected += 1
                        results.append({"entity_id": entity_id, "status": "insufficient_stock"})
                        break
                else:
                    # Semua item berhasil diproses: simpan transaksi.
                    _finish_sale(db, data, sale, entity_id, body, store_id)
                    accepted += 1
                    results.append({"entity_id": entity_id, "status": "ok"})
                continue

            elif entity_type == "damage_report":
                existing = scoped(DamageReport).filter(DamageReport.id == entity_id).first()
                if existing:
                    db.add(SyncEvent(
                        event_type="SKIP_DUPLICATE",
                        entity_type="damage_report",
                        entity_id=entity_id,
                        device_id=body.device_id,
                        status="PROCESSED",
                        store_id=store_id,
                    ))
                    db.commit()
                    rejected += 1
                    results.append({"entity_id": entity_id, "status": "duplicate"})
                    continue

                product = scoped(Product).filter(Product.id == data.get("product_id")).first()
                if not product:
                    rejected += 1
                    results.append({"entity_id": entity_id, "status": "product_not_found"})
                    continue

                emp_id = resolve_employee(data.get("employee_id"))

                report = DamageReport(
                    id=entity_id,
                    product_id=data["product_id"],
                    quantity=data["quantity"],
                    unit=data.get("unit", product.unit),
                    reason=data.get("reason", "OTHER"),
                    description=data.get("description"),
                    status="PENDING",
                    employee_id=emp_id,
                    store_id=store_id,
                    created_at=_as_stored_utc(data.get("created_at")),
                )
                db.add(report)

                for i, photo in enumerate(data.get("photos", [])):
                    try:
                        import base64
                        from ..services.storage import storage
                        photo_bytes = base64.b64decode(photo)
                        fname = f"{entity_id}_{i}.jpg"
                        rel_key = f"damage/{fname}"
                        storage.save_bytes(rel_key, photo_bytes, "image/jpeg")
                        db.add(DamagePhoto(
                            damage_report_id=report.id,
                            file_path=rel_key,
                            file_url=storage.url(rel_key),
                        ))
                    except Exception:
                        pass

                db.add(SyncEvent(
                    event_type="PUSH",
                    entity_type="damage_report",
                    entity_id=entity_id,
                    device_id=body.device_id,
                    status="PROCESSED",
                    store_id=store_id,
                ))
                db.commit()
                accepted += 1
                results.append({"entity_id": entity_id, "status": "ok"})

            else:
                rejected += 1
                results.append({"entity_id": entity_id, "status": f"unsupported_type:{entity_type}"})

        except Exception as e:
            db.rollback()
            db.add(SyncEvent(
                event_type="PUSH_FAILED",
                entity_type=entity_type,
                entity_id=entity_id,
                device_id=body.device_id,
                status="FAILED",
                error_message=str(e),
                store_id=store_id,
            ))
            db.commit()
            rejected += 1
            results.append({"entity_id": entity_id, "status": "error", "message": str(e)})

    return {"accepted": accepted, "rejected": rejected, "results": results}


@router.post("/pull", response_model=SyncPullResponse)
def pull_data(
    body: SyncPullRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # POS hanya boleh menarik data tokonya sendiri. Gagal keras kalau akun
    # belum tertaut ke toko, jangan sampai tanpa filter dan melihat semua.
    store_id = require_store_id(current_user)

    if body.device_id:
        register_device(
            db, body.device_id, platform="android",
            device_name="android-device", store_id=store_id,
        )

    # Semua query WAJIB ter-scope. Sebelumnya .all() tanpa filter, sehingga
    # satu toko bisa menarik produk, kategori, dan movements toko lain.
    products = db.query(Product).filter(Product.store_id == store_id).all()
    categories = db.query(Category).filter(Category.store_id == store_id).all()

    damage_query = db.query(DamageReport).filter(DamageReport.store_id == store_id)
    sales_query = db.query(Sale).filter(Sale.store_id == store_id)

    if current_user.role == UserRole.KARYAWAN.value:
        # Karyawan hanya mendapat laporan & transaksi miliknya, dan status approval terbaru
        damage_query = damage_query.filter(DamageReport.employee_id == current_user.id)
        sales_query = sales_query.filter(Sale.employee_id == current_user.id)

    if body.last_sync_at:
        since = _as_naive_utc(body.last_sync_at)
        damage_query = damage_query.filter(DamageReport.updated_at >= since)
        sales_query = sales_query.filter(Sale.updated_at >= since)

    # Dicapture SEBELUM query, bukan saat response dirakit.
    #
    # Perangkat memakai nilai ini sebagai `last_sync_at` untuk pull berikutnya
    # dan menyaring dengan `updated_at >= last_sync_at`. Kalau timestamp diambil
    # setelah query, perubahan yang masuk di antara query dan response bisa punya
    # `updated_at` lebih kecil dari watermark padahal tidak pernah dikirim --
    # jadi terlewat selamanya. Dengan diambil lebih dulu, semua perubahan
    # setelah titik ini pasti lebih besar dari watermark dan akan diambil pada
    # pull berikutnya.
    sync_started_at = datetime.utcnow()

    damage_reports = damage_query.order_by(DamageReport.created_at.desc()).all()
    sales_complete = True
    sales = sales_query.order_by(Sale.created_at.desc()).limit(500).all()
    if body.last_sync_at is None:
        # Full pull (first sync / startup): payload sales adalah daftar kanonik
        # scope akun ini SELAMA tidak terpotong. Kalau pas 500, tidak bisa
        # dijadiakan dasar menghapus riwayat lokal yang tidak ikut terkirim.
        sales_complete = len(sales) < 500
    movements = (
        db.query(StockMovement)
        .filter(StockMovement.store_id == store_id)
        .order_by(StockMovement.created_at.desc())
        .all()
    )

    return SyncPullResponse(
        products=[p.to_dict() for p in products],
        categories=[c.to_dict() for c in categories],
        damage_reports=[r.to_dict() for r in damage_reports],
        stock_movements=[m.to_dict() for m in movements],
        sales=[s.to_dict() for s in sales],
        sales_complete=sales_complete,
        app_settings=_build_app_settings(db, store_id),
        server_time=iso_utc(sync_started_at),
    )


def _as_naive_utc(value: datetime) -> datetime:
    """Samakan `last_sync_at` dari perangkat dengan kolom `updated_at` di DB.

    Kolom `updated_at` dibuat `TIMESTAMP WITHOUT TIME ZONE` (lihat model) dan
    diisi `datetime.utcnow()`, jadi isinya UTC TANPA penanda timezone. Perangkat
    meanwhile mengirim watermark sebagai ISO ber-timezone (`...Z`).

    PostgreSQL tidak bisa membandingkan keduanya langsung: kolom naive dibaca
    sebagai waktu pada TimeZone sesi, dan pada DB ini TimeZone = Asia/Bangkok
    (+07). Akibatnya setiap baris terlihat 7 jam lebih tua dari aslinya dan
    `updated_at >= since` tidak pernah benar -- incremental pull selalu
    mengembalikan 0 transaksi, sehingga koreksi dari Owner Console baru muncul
    setelah aplikasi dijalankan ulang (full pull). Itu terlihat sebagai
    "riwayat di HP tidak live".

    Ubah watermark menjadi UTC naive supaya perbandingannya terjadi di ruang
    waktu yang sama dengan penyimpanan.
    """
    if value.tzinfo is not None:
        return value.astimezone(timezone.utc).replace(tzinfo=None)
    return value


def _as_stored_utc(value) -> datetime:
    """Samakan `created_at` dari perangkat dengan kolom penyimpanan (UTC naive).

    Perangkat mengirim `created_at` ber-timezone (`...Z`). Kolomnya
    `TIMESTAMP WITHOUT TIME ZONE` berisi UTC, jadi penanda zona harus
    dikonversi lalu dilepas, bukan dibuang begitu saja -- kalau tidak, jam
    aslinya bergeser 7 jam di semua tampilan yang menghormati `Z` (Owner
    Console, laporan harian), dan transaksi dibuat lewat malam bisa
    tercatat di tanggal yang salah.
    """
    if not value:
        return datetime.utcnow()
    parsed = value if isinstance(value, datetime) else datetime.fromisoformat(value)
    return _as_naive_utc(parsed)


def _build_app_settings(db: Session, store_id):
    """Payload broadcast yang aktif untuk toko ini.

    app_settings sebelumnya tidak pernah diisi backend maupun dibaca Flutter,
    jadi pengumuman owner tidak pernah sampai ke POS. Sekarang dikirim lewat
    sync pull. Field baru opsional supaya Flutter versi lama tidak error.
    """
    now = datetime.utcnow()
    rows = (
        db.query(Broadcast)
        .filter(
            Broadcast.is_active == True,
            Broadcast.starts_at <= now,
            or_(
                Broadcast.target == BroadcastTarget.ALL,
                and_(
                    Broadcast.target == BroadcastTarget.STORE,
                    Broadcast.store_id == store_id,
                ),
            ),
        )
        .order_by(Broadcast.starts_at.desc())
        .all()
    )
    settings = {}
    for b in rows:
        if b.expires_at and b.expires_at < now:
            continue
        # Satu pengumuman per level, yang terbaru menang. Query di atas sudah
        # terurut starts_at DESC, jadi baris PERTAMA per level adalah yang
        # terbaru. Assignment biasa akan menimpanya dengan baris berikutnya
        # dan justru membuat yang paling lama menang, jadi level yang sudah
        # terisi dilewati.
        level = b.level.lower()
        if level in settings:
            continue
        settings[level] = {
            "id": str(b.id),
            "title": b.title,
            "body": b.body,
            "starts_at": iso_utc(b.starts_at),
            "expires_at": iso_utc(b.expires_at),
        }
    return settings