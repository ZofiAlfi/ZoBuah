"""Seed UAT ZoBuah: 4 toko sintetis dengan data yang terlihat seperti dunia nyata.

Tujuannya satu: ketika dashboard Owner dibuka, angkanya harus punya cerita.
Tabel yang kosong atau transaksi 3 buah membuat semua KPI, grafik tren, dan
alert jadi tidak bisa diverifikasi secara visual, jadi data sengaja disebar
pada kondisi yang bermasalah juga:

  Toko 1  PRO, sync sehat, 30 hari penuh transaksi
  Toko 2  BASIC, paket habis 4 hari lagi  -> memicu alert PLAN_EXPIRING
  Toko 3  TRIAL, paket sudah lewat 9 hari -> memicu alert PLAN_EXPIRED
  Toko 4  UNLIMITED, tidak pernah sync    -> memicu alert STORE_OFFLINE

Dijalankan dengan:
    python uat/seed_uat.py --reset

--reset menghapus SELURUH schema public dulu. Karena itu skrip ini menolak
berjalan kalau DATABASE_URL bukan host lokal, kecuali --i-am-not-touching-prod
diberikan secara eksplisit.
"""
import argparse
import itertools
import os
import random
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.parse import urlparse

from dotenv import load_dotenv

BACKEND = Path(__file__).resolve().parent.parent / "backend"
sys.path.insert(0, str(BACKEND))

# override=False: env shell menang atas .env, supaya tidak bisa ter stunt ke produksi.
load_dotenv(BACKEND / ".env", override=False)

# Host dicocokkan sebagai hostname utuh, bukan substring. Cek substring pernah
# membiarkan "db-prod.perusahaan.co.id" lewat karena memuat huruf "db", dan
# seed ini menghapus schema lebih dulu.
LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1", "db"}


def guard(force: bool) -> str:
    url = os.environ.get("DATABASE_URL", "")
    host = (urlparse(url).hostname or "").strip()
    if host in LOCAL_HOSTS:
        return url
    if force:
        print("PERINGATAN: --i-am-not-touching-prod diberikan. Lanjut ke", url)
        return url
    print("DITOLAK: DATABASE_URL bukan host lokal.")
    print(f"  host terbaca: {host!r}")
    print(f"  terbaca: {url[:70]}")
    print("  Jalankan ulang dengan --i-am-not-touching-prod bila benar-benar disengaja.")
    sys.exit(2)


FRUITS = [
    ("Alpukat Mentega", 28000, 22000, 32.0, 10.0),
    ("Apel Fuji", 34000, 26000, 18.0, 8.0),
    ("Jeruk Medan", 22000, 17000, 45.0, 15.0),
    ("Pisang Cavendish", 26000, 20000, 24.0, 12.0),
    ("Mangga Harum Manis", 32000, 24000, 27.5, 10.0),
    ("Semangka Merah", 9000, 6000, 60.0, 25.0),
    ("Anggur Shine Muscat", 78000, 62000, 9.5, 4.0),
    ("Buah Naga", 30000, 23000, 15.0, 6.0),
    ("Salak Pongtol", 25000, 19000, 33.0, 12.0),
    ("Nanas Madu", 12000, 8500, 40.0, 20.0),
    ("Melon Rock", 15000, 10500, 22.0, 10.0),
    ("Duku", 35000, 27000, 6.0, 3.0),
    ("Rambutan", 38000, 29000, 11.0, 5.0),
    ("Jambu Kristal", 29000, 22000, 19.0, 8.0),
]

CATEGORIES = ["Buah Tropis", "Buah Impor", "Buah Lokal", "Paket Campuran"]

DAMAGE_REASONS = ["BUSUK", "MEMBENGKAK", "KUTUK", "SERANGAN HAMA", "KEMASARAN RUSAK"]

# T04 berhenti sync 45 hari lalu. Dipakai dua kali: untuk set last_sync_at
# dan untuk menghentikan pembuatan transaksi, supaya angka di tempat lain
# tidak ikut melenceng kalau skenario ini diubah.
#
# OFFLINE_DAYS (bukan 21) dengan --days 60 supaya T04 jatuh di luar jendela
# 30 hari: revenue_30d = 0 tapi lifetime_revenue > 0. Itu kasus yang
# membedakan antara jendela waktu yang salah dan toko yang memang
# sepi, dan hanya bisa terlihat kalau sejarahnya lebih panjang dari 30 hari.
OFFLINE_DAYS = 45


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reset", action="store_true", help="kosongkan schema public dulu")
    parser.add_argument(
        "--days",
        type=int,
        default=60,
        help="berapa hari riwayat transaksi dibuat (default 60, cukup panjang "
        "supaya kasus toko sepi di luar jendela 30 hari ikut teruji)",
    )
    parser.add_argument("--seed", type=int, default=20260927, help="seed random, supaya hasilnya konsisten")
    parser.add_argument("--i-am-not-touching-prod", action="store_true")
    args = parser.parse_args()

    url = guard(args.i_am_not_touching_prod)
    random.seed(args.seed)

    os.environ.setdefault("OWNER_PASSWORD", "owner-secret-123")
    os.environ.setdefault("STORAGE", "local")

    from sqlalchemy import text

    from app.database import Base, SessionLocal, engine
    from app.models.broadcast import Broadcast, BroadcastLevel, BroadcastTarget
    from app.models.category import Category
    from app.models.damage_report import DamageReport
    from app.models.device import Device
    from app.models.product import Product
    from app.models.sale import Payment, Sale, SaleItem
    from app.models.stock_movement import StockMovement
    from app.models.store import Store
    from app.models.sync_event import SyncEvent
    from app.models.user import User, UserRole
    from app.security import hash_password

    import app.models  # noqa: F401  mendaftar semua model ke Base.metadata

    print(f"UAT DB : {url}")

    if args.reset:
        print("Mengosongkan schema public ...")
        with engine.begin() as conn:
            conn.execute(text("DROP SCHEMA public CASCADE"))
            conn.execute(text("CREATE SCHEMA public"))
        Base.metadata.create_all(bind=engine)
        print("Schema dibuat ulang.")
    else:
        Base.metadata.create_all(bind=engine)

    db = SessionLocal()
    now = datetime.utcnow()
    today = date.today()

    try:
        existing = db.query(User).filter(User.username == "owner").first()
        if existing is None:
            db.add(
                User(
                    username="owner",
                    password_hash=hash_password(os.environ["OWNER_PASSWORD"]),
                    full_name="Pemilik Layanan",
                    role=UserRole.OWNER.value,
                    is_active=True,
                    store_id=None,
                )
            )
            db.commit()
            print("Akun OWNER dibuat.")
        else:
            print("Akun OWNER sudah ada, dilewati.")

        owner = db.query(User).filter(User.username == "owner").first()

        plan_specs = [
            ("T01", "Toko Buah Segar", "PRO", 120, "sehat", 0),
            ("T02", "Toko Buah Maju", "BASIC", 4, "sehat", 0),
            ("T03", "Toko Buah Gratis", "TRIAL", -9, "sehat", 0),
            ("T04", "Toko Buah Terisolasi", "UNLIMITED", None, "mati", OFFLINE_DAYS),
        ]

        created_stores = []
        total_sales = 0

        for code, name, plan, expires_in, sync_state, last_sync_days in plan_specs:
            if db.query(Store).filter(Store.code == code).first():
                print(f"  {code} sudah ada, dilewati.")
                continue

            store = Store(
                code=code,
                name=name,
                owner_name=f"Pemilik {name}",
                phone=f"0812{random.randint(10000000, 99999999)}",
                address=f"Jl. Uji Coba No. {random.randint(1, 99)}, Bandung",
                plan=plan,
                plan_expires_at=(today + timedelta(days=expires_in)) if expires_in is not None else None,
                status="ACTIVE",
                is_active=True,
                created_at=now - timedelta(days=random.randint(120, 200)),
            )
            db.add(store)
            db.commit()
            db.refresh(store)

            bos = User(
                username=f"bos{code.lower()}",
                password_hash=hash_password("bos-secret-123"),
                full_name=f"BOS {name}",
                role=UserRole.BOS.value,
                is_active=True,
                store_id=store.id,
            )
            db.add(bos)
            db.commit()
            db.refresh(bos)

            karyawan = []
            for i in range(1, random.randint(2, 3)):
                kar = User(
                    username=f"kar{code.lower()}{i}",
                    password_hash=hash_password("kar-secret-123"),
                    full_name=f"Karyawan {name} {i}",
                    role=UserRole.KARYAWAN.value,
                    is_active=True,
                    store_id=store.id,
                )
                db.add(kar)
                db.commit()
                db.refresh(kar)
                karyawan.append(kar)

            cats = []
            for cname in CATEGORIES:
                cat = Category(name=cname, store_id=store.id)
                db.add(cat)
                db.commit()
                db.refresh(cat)
                cats.append(cat)

            products = []
            for f_name, selling, modal, stock, min_stock in FRUITS:
                clean = f_name.strip()
                prod = Product(
                    name=clean,
                    category_id=random.choice(cats).id,
                    unit="kg",
                    modal_price=modal,
                    selling_price=selling,
                    stock=stock,
                    min_stock=min_stock,
                    is_active=True,
                    store_id=store.id,
                    created_at=now - timedelta(days=random.randint(60, 180)),
                )
                db.add(prod)
                db.commit()
                db.refresh(prod)
                products.append(prod)

            # Tiga produk ini ditandai sebagai sampel LOW_STOCK. Stoknya
            # baru ditetapkan setelah riwayat transaksi selesai, supaya alert
            # dashboard tetap terisi tanpa menghabiskan stok demo.
            low_stock_products = {prod.id for prod in random.sample(products, 3)}

            # Perangkat. Toko yang "mati" sengaja tidak punya last_sync_at.
            device_last_sync = None
            if sync_state == "sehat":
                device_last_sync = now - timedelta(hours=random.randint(1, 18))
            elif last_sync_days:
                device_last_sync = now - timedelta(days=last_sync_days)

            dev = Device(
                device_id=f"AND-{code}-01",
                device_name=f"HP Kasir {code}",
                platform="android",
                last_sync_at=device_last_sync,
                store_id=store.id,
                is_active=True,
            )
            db.add(dev)
            db.commit()

            # Transaksi harian.
            # Nomor transaksi memakai counter, bukan random: unikanya
            # (store_id, transaction_number), jadi angka acak yang kebetulan
            # sama dalam satu toko akan ditolak database. Counter per toko
            # sekaligus menjamin nomor berurutan seperti filter POS asli.
            seq = itertools.count(1)
            for day_offset in range(args.days, -1, -1):
                day = now - timedelta(days=day_offset)
                weekday = day.weekday()
                base = 6 if weekday >= 5 else 4
                if day_offset < 3:
                    base += 3
                if code == "T03":
                    base = max(0, base - 4)
                if code == "T04":
                    # T04 berhenti operate 21 hari lalu lalu tidak pernah sync
                    # lagi, jadi transaksi berhenti di titik itu. Sengaja tidak
                    # dihapus: justru ini yang membedakan revenue_30d (nol)
                    # dari lifetime_revenue (ada), kasus yang tidak terlihat
                    # kalau tokonya benar-benar belum pernah buka.
                    base = 0 if day_offset <= OFFLINE_DAYS else 3

                for _ in range(base):
                    actor = random.choice(karyawan)
                    items = random.sample(products, random.randint(1, 4))
                    detail_rows = []
                    total_amount = 0.0
                    total_modal = 0.0

                    for prod in items:
                        qty = round(random.uniform(0.5, 4.0), 2)
                        unit_price = float(prod.selling_price)
                        modal_price = float(prod.modal_price)
                        subtotal = round(qty * unit_price, 2)
                        total_amount += subtotal
                        total_modal += round(qty * modal_price, 2)
                        detail_rows.append((prod, qty, unit_price, modal_price, subtotal))

                    if not detail_rows:
                        continue

                    total_amount = round(total_amount, 2)
                    total_modal = round(total_modal, 2)
                    discount = round(total_amount * random.choice([0, 0, 0, 0.02, 0.05]), 2)
                    total_profit = round(total_amount - discount - total_modal, 2)

                    # Kasir aktif 08:00-20:00 WIB (UTC+7). Timestamp disimpan
                    # naif-UTC seperti yang dikirim app produksi (misal
                    # 07:18Z untuk 14:18 WIB). Kalau hour produksi dipakai
                    # begitu saja, perangkat membaca jam WIB seolah UTC dan
                    # riwayat tampil salah tanggal.
                    wib = day.replace(
                        hour=random.randint(8, 20),
                        minute=random.randint(0, 59),
                        second=random.randint(0, 59),
                    )
                    created_utc = wib - timedelta(hours=7)
                    sale = Sale(
                        transaction_number=f"TRX-{created_utc.strftime('%Y%m%d')}-{next(seq):04d}",
                        employee_id=actor.id,
                        total_amount=total_amount,
                        total_modal=total_modal,
                        total_profit=total_profit,
                        discount=discount,
                        status="COMPLETED",
                        store_id=store.id,
                        created_at=created_utc,
                    )
                    db.add(sale)
                    db.commit()
                    db.refresh(sale)

                    for prod, qty, unit_price, modal_price, subtotal in detail_rows:
                        db.add(
                            SaleItem(
                                sale_id=sale.id,
                                product_id=prod.id,
                                product_name=prod.name,
                                unit="kg",
                                unit_price=unit_price,
                                modal_price=modal_price,
                                quantity=qty,
                                subtotal=subtotal,
                            )
                        )
                        before = float(prod.stock)
                        after = round(max(0.0, before - qty), 3)
                        prod.stock = after
                        db.add(
                            StockMovement(
                                product_id=prod.id,
                                # Harus "SALE", bukan "OUT". Laporan stok
                                # mengelompokkan per movement_type dan hanya
                                # mengenali SALE/DAMAGE/RETURN/STOCK_IN/
                                # ADJUSTMENT, sehingga tipe "OUT" membuat
                                # seluruh penjualan hilang dari laporan
                                # (sale_out selalu 0) dan kolom stok tidak
                                # pernah rekonsiliasi.
                                movement_type="SALE",
                                quantity=qty,
                                stock_before=before,
                                stock_after=after,
                                reference_id=sale.id,
                                reference_type="SALE",
                                user_id=actor.id,
                                store_id=store.id,
                                created_at=sale.created_at,
                            )
                        )
                    total_sales += 1

                    method = random.choice(["CASH", "QRIS", "TRANSFER"])
                    db.add(
                        Payment(
                            sale_id=sale.id,
                            method=method,
                            amount=total_amount,
                            cash_received=round(total_amount + random.choice([0, 5000, 10000]), 2) if method == "CASH" else total_amount,
                            change_amount=0,
                        )
                    )
                    db.commit()

            # Stok akhir ditetapkan setelah riwayat transaksi selesai.
            # Kalau tidak, 120 hari penjualan fiktif menguras seluruh stok
            # T01/T02 sampai nol (stok di-clamp max(0.0, ...)), lalu setiap
            # penjualan baru dari POS ditolak server dengan insufficient_stock
            # sehingga transaksi offline tidak pernah bisa masuk ke server.
            # Selisihnya dicatat sebagai movement STOCK_IN supaya ledger
            # stok tetap rekonsiliasi dengan stok produk.
            for prod in products:
                before = round(float(prod.stock or 0), 3)
                if prod.id in low_stock_products:
                    ceiling = max(0.5, float(prod.min_stock) * 0.6)
                    target = round(random.uniform(0.3, ceiling), 3)
                else:
                    target = round(float(prod.min_stock) + random.uniform(2.0, 8.0), 3)
                if target == before:
                    continue
                prod.stock = target
                # Arah gerakan mengikuti konvensi app: record_stock_movement()
                # menentukan arah dari movement_type, dan quantity selalu
                # positif. Menulis STOCK_IN dengan selisih negatif membuat
                # kolom stock_in di laporan bernilai minus dan menutupi
                # artifact, bukan menjelaskan sebagai penyesuaian.
                if target > before:
                    tipe = "STOCK_IN"
                    selisih = round(target - before, 3)
                else:
                    tipe = "ADJUSTMENT_NEGATIVE"
                    selisih = round(before - target, 3)
                db.add(
                    StockMovement(
                        product_id=prod.id,
                        movement_type=tipe,
                        quantity=selisih,
                        stock_before=before,
                        stock_after=target,
                        reference_type="seed_restock",
                        notes="Penyesuaian stok akhir seed UAT",
                        user_id=bos.id,
                        store_id=store.id,
                        created_at=now - timedelta(hours=random.randint(2, 20)),
                    )
                )
            db.commit()

            # Laporan rusak: sebagian lama dan menggantung supaya alert
            # DAMAGE_PENDING nyala.
            for i in range(random.randint(2, 4)):
                prod = random.choice(products)
                age = random.choice([1, 4, 6, 9])
                created = now - timedelta(days=age)
                status = "PENDING" if age >= 3 else random.choice(["APPROVED", "REJECTED"])
                db.add(
                    DamageReport(
                        product_id=prod.id,
                        quantity=round(random.uniform(0.5, 3.0), 2),
                        unit="kg",
                        qty_in_base_unit=round(random.uniform(0.5, 3.0) * 1000, 0),
                        reason=random.choice(DAMAGE_REASONS),
                        description="Kerusakan saat handling di gudang.",
                        status=status,
                        employee_id=random.choice(karyawan).id,
                        approved_by=bos.id if status == "APPROVED" else None,
                        approved_at=created if status == "APPROVED" else None,
                        rejected_by=bos.id if status == "REJECTED" else None,
                        rejected_at=created if status == "REJECTED" else None,
                        store_id=store.id,
                        created_at=created,
                    )
                )
            db.commit()

            # Sync event: beberapa gagal di toko besar supaya terhitung.
            for i in range(random.randint(0, 3)):
                db.add(
                    SyncEvent(
                        event_type="PUSH",
                        entity_type="SALE",
                        entity_id=f"TRX-{code}-{i}",
                        device_id=f"AND-{code}-01",
                        status=random.choice(["PROCESSED", "FAILED"]),
                        error_message="Kolom tidak dikenal" if i == 0 else None,
                        store_id=store.id,
                        created_at=now - timedelta(hours=random.randint(1, 72)),
                    )
                )
            db.commit()

            created_stores.append((store, bos, karyawan, products))
            print(f"  {code} {name:24} plan={plan:10} sync={sync_state:6} produk={len(products)}")

        # Broadcast untuk semua app, plus satu khusus per toko.
        db.add(
            Broadcast(
                title="Pemeliharaan terjadwal",
                body="Server akan dijadwalkan dinonaktifkan hari Minggu pukul 01:00 WIB. Simpan transaksi sebelum pukul tersebut.",
                level=BroadcastLevel.MAINTENANCE,
                target=BroadcastTarget.ALL,
                store_id=None,
                starts_at=now - timedelta(hours=2),
                expires_at=now + timedelta(days=5),
                is_active=True,
                created_by=owner.id,
            )
        )
        db.add(
            Broadcast(
                title="Fitur baru: catatan pembelian",
                body="Sekarang bisa mencatat pembelian dari pemasok di menu Stok. Datanya tersinkron otomatis ke perangkat.",
                level=BroadcastLevel.INFO,
                target=BroadcastTarget.ALL,
                store_id=None,
                starts_at=now - timedelta(days=1),
                expires_at=now + timedelta(days=20),
                is_active=True,
                created_by=owner.id,
            )
        )
        if created_stores:
            target_store = created_stores[0][0]
            db.add(
                Broadcast(
                    title="Diskon akhir pekan",
                    body="Diskon 10% untuk akhir pekan ini. Jangan lupa update banner di kasir.",
                    level=BroadcastLevel.INFO,
                    target=BroadcastTarget.STORE,
                    store_id=target_store.id,
                    starts_at=now,
                    expires_at=now + timedelta(days=2),
                    is_active=True,
                    created_by=owner.id,
                )
            )
        db.commit()

        print("-" * 60)
        print(f"Toko dibuat     : {len(created_stores)}")
        print(f"Transaksi       : {total_sales}")
        print(f"Periode         : {args.days} hari ke belakang")
        print("-" * 60)
        print("AKUN UAT")
        print(f"  OWNER     owner          / {os.environ['OWNER_PASSWORD']}")
        print("  BOS       bost01..t04    / bos-secret-123")
        print("  KARYAWAN  kart011..t043  / kar-secret-123")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
