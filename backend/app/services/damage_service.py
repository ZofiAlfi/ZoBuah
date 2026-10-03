"""Logika bisnis laporan barang rusak, dipakai oleh dua pintu masuk.

Laporan barang rusak bisa disetujui atau ditolak dari dua tempat: aplikasi POS
oleh BOS toko (`routes/damage_report.py`), dan Owner Console oleh owner platform
(`routes/admin.py`). Keduanya memanggil service di file ini, bukan punya
salinan logikanya sendiri.

Alasannya sederhana: persetujuan memotong stok. Kalau dua salinan logika ada,
mereka pasti berbeda di satu titik, dan titik itu akan jadi bug yang sulit
dilacak karena tidak ada error yang dilempar - stoknya hanya diam-diam beda.

Status hanya bergerak maju satu kali:

    PENDING --setujui--> APPROVED   (stok dipotong, tidak bisa dibatalkan)
    PENDING --tolak----> REJECTED   (stok tidak berubah, butuh alasan)
"""

from datetime import datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..models.damage_report import DamageReport
from ..models.product import Product
from ..models.user import User
from ..security import log_audit
from .stock_service import convert_quantity, record_damage


def resolve_reported_quantity(quantity, from_unit, product_unit):
    """Jumlah laporan dalam satuan stok produk, atau None kalau tak bisa.

    Laporan bisa dibuat dalam satuan kemasan ("2 pcs") sementara stok disimpan
    per satuan dasar ("kg"). Kalau angkanya tidak diubah ke satuan produk, dan
    kolom `qty_in_base_unit` kosong, approve akan memotong 2 kg dari laporan
    yang maksudnya 2 pcs. Itu galat yang tidak pernah melempar error, jadi
    nilainya harus benar sejak laporan disimpan.

    None berarti satuannya tidak dikenal (mis. "box" ke "kg"). Laporan seperti
    ini sebaiknya ditolak, bukan disimpan dengan tebakan.
    """
    f = (from_unit or "").strip().lower()
    t = (product_unit or "").strip().lower()
    if f == t:
        return quantity
    return convert_quantity(quantity, from_unit, product_unit)


def _get_product(db: Session, report: DamageReport) -> Product:
    """Produk laporan, dibatasi store_id laporan itu sendiri.

    Filter store_id bukan Frankenstein: laporan selalu punya store_id, dan
    produk harus dari toko yang sama. Kalau tidak, laporan yang rusak akan
    mengurangi stok produk toko lain.
    """
    product = db.query(Product).filter(
        Product.id == report.product_id,
        Product.store_id == report.store_id,
    ).first()
    if not product:
        raise HTTPException(status_code=404, detail="Produk tidak ditemukan")
    return product


def _deductable_quantity(report: DamageReport) -> float:
    """Jumlah yang benar-benar dipotong dari stok.

   _qty_in_base_unit_ dipakai kalau ada karena laporan bisa dibuat dalam satuan
    kemasan ("2 pcs") sementara stok disimpan per satuan dasar ("kg"). Kalau
    tidak ada, jumlah yang diketik karyawan dipakai apa adanya.
    """
    try:
        qty = float(report.qty_in_base_unit)
    except (TypeError, ValueError):
        qty = 0.0
    if qty <= 0:
        try:
            qty = float(report.quantity)
        except (TypeError, ValueError):
            qty = 0.0
    if qty <= 0:
        raise HTTPException(
            status_code=400, detail="Jumlah barang rusak tidak valid."
        )
    return qty


def approve_core(
    db: Session,
    report: DamageReport,
    actor: User,
    *,
    audit_action: str,
    request,
) -> DamageReport:
    """Setujui satu laporan: potong stok, lalu tandai APPROVED.

    `actor` boleh User biasa (BOS toko) maupun owner platform yang
    `store_id`-nya None --porosity kode tidak bergantung pada siapa aktornya,
    hanya pada `audit_action` yang menandai jalannya.
    """
    # Diperiksa di sini, bukan cuma di handler pemanggil. Dua pintu masuk
    # berarti pemeriksaan di handler bisa dilewati salah satu.
    if report.status != "PENDING":
        raise HTTPException(
            status_code=400, detail="Hanya laporan PENDING yang dapat disetujui"
        )

    product = _get_product(db, report)
    qty = _deductable_quantity(report)

    # Potong stok DULUAN. Kalau record_damage gagal, db.rollback() di
    # pemanggil mengembalikan seluruh transaksi, jadi status tidak pernah
    # berubah tanpa stok yang benar-benar berkurang.
    record_damage(db, product, report.id, qty, actor)

    report.status = "APPROVED"
    report.approved_by = actor.id
    report.approved_at = datetime.utcnow()
    db.commit()
    db.refresh(report)

    log_audit(
        db,
        actor,
        audit_action,
        "damage_report",
        report.id,
        {
            "product": product.name,
            "quantity": float(report.quantity),
            "deducted": qty,
            "unit": product.unit,
        },
        request,
    )
    return report


def reject_core(
    db: Session,
    report: DamageReport,
    actor: User,
    *,
    reason: str,
    audit_action: str,
    request,
) -> DamageReport:
    """Tolak satu laporan: status jadi REJECTED, stok tidak diubah.

    Menolak tidak menyentuh stok karena barangnya dianggap masih layak jual.
    Karena itu alasan wajib diisi - kalau tidak, karyawan yang membuat laporan
    tidak punya cara tahu kenapa laporannya ditolak.
    """
    if report.status != "PENDING":
        raise HTTPException(
            status_code=400, detail="Hanya laporan PENDING yang dapat ditolak"
        )

    cleaned = (reason or "").strip()
    if len(cleaned) < 10:
        raise HTTPException(
            status_code=422,
            detail="Alasan penolakan wajib diisi minimal 10 karakter.",
        )

    report.status = "REJECTED"
    report.rejected_by = actor.id
    report.rejected_at = datetime.utcnow()
    report.rejection_reason = cleaned
    db.commit()
    db.refresh(report)

    log_audit(
        db,
        actor,
        audit_action,
        "damage_report",
        report.id,
        {"reason": cleaned},
        request,
    )
    return report
