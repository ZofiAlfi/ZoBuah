"""Uji iso_utc() dan panggil to_dict() model tanpa database.

Dua hal yang diuji:

1. iso_utc() selalu keluar dengan suffix Z. Nilai di database adalah
   TIMESTAMP TANPA ZONA yang diisi datetime.utcnow(), jadi naive = UTC.

2. to_dict() dipanggil sungguhan. damaged_by: value adalah sintaks dict
   yang sah, jadi py_compile lolos padahal runtime akan NameError. Uji
   runtime seperti inilah yang menangkapnya.
"""
import datetime as dt
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from app.utilities.helpers import iso_utc  # noqa: E402


def check_iso_utc() -> list:
    fails = []

    naive = dt.datetime(2026, 9, 28, 15, 51, 18, 668954)
    out = iso_utc(naive)
    if out != "2026-09-28T15:51:18.668954Z":
        fails.append("naive UTC -> %r" % out)
    if not out.endswith("Z"):
        fails.append("suffix Z hilang: %r" % out)

    wib = dt.datetime(
        2026, 9, 28, 22, 51, 18, tzinfo=dt.timezone(dt.timedelta(hours=7))
    )
    out = iso_utc(wib)
    if out != "2026-09-28T15:51:18Z":
        fails.append("aware WIB harus jadi UTC 15:51, dapat %r" % out)
    if "+07:00" in out or "22:51" in out:
        fails.append("waktu lokal bocor ke keluaran: %r" % out)

    if iso_utc(None) is not None:
        fails.append("None harus jadi None")

    midnight = dt.datetime(2026, 1, 1, 0, 0, 0)
    if iso_utc(midnight) != "2026-01-01T00:00:00Z":
        fails.append("tepat tengah malam: %r" % iso_utc(midnight))

    return fails


class FakeRel:
    """Relationship yang tidak disentuh database."""

    def __init__(self, **kw):
        for k, v in kw.items():
            setattr(self, k, v)


def make(cls, scalars, rels):
    """Bangun objek ORM tanpa menyentuh database.

    Relasi ditulis langsung ke __dict__ untuk melewati instrumentation
    SQLAlchemy, yang akan menolak objek biasa karena tidak punya
    _sa_instance_state. to_dict() hanya membaca atributnya, jadi ini
    cukup untuk menguji isi dict yang dihasilkan.
    """
    obj = cls(**scalars)
    for name, value in rels.items():
        obj.__dict__[name] = value
    return obj


def check_to_dict_runs() -> list:
    """Panggil to_dict() dengan stub agar semua key ikut tervalidasi."""
    fails = []
    stamp = dt.datetime(2026, 9, 28, 15, 51, 18)

    from app.models.sale import Sale
    from app.models.damage_report import DamageReport
    from app.models.broadcast import Broadcast

    product = FakeRel(name="Melon Rock")
    employee = FakeRel(full_name="Budi")
    photo = FakeRel(file_url="/uploads/a.jpg")

    sale = make(
        Sale,
        {
            "id": "s1",
            "store_id": "t1",
            "employee_id": "u1",
            "transaction_number": "TRX-1",
            "total_amount": 20000,
            "total_modal": 15000,
            "total_profit": 5000,
            "discount": 0,
            "status": "COMPLETED",
            "canceled_at": None,
            "canceled_by": None,
            "canceled_reason": None,
            "created_at": stamp,
            "updated_at": stamp,
        },
        {"employee": employee, "sale_items": []},
    )
    try:
        d = sale.to_dict()
    except Exception as exc:  # noqa: BLE001
        fails.append("Sale.to_dict() gagal: %s: %s" % (type(exc).__name__, exc))
    else:
        for key in ("canceled_at", "canceled_by", "canceled_reason"):
            if key not in d:
                fails.append("Sale.to_dict() tidak punya key %r" % key)
        if d.get("created_at") != "2026-09-28T15:51:18Z":
            fails.append("Sale.created_at = %r" % d.get("created_at"))

    dr = make(
        DamageReport,
        {
            "id": "d1",
            "quantity": 1,
            "unit": "kg",
            "qty_in_base_unit": 1,
            "reason": "bocor",
            "status": "PENDING",
            "approved_by": None,
            "rejected_by": None,
            "rejection_reason": None,
            "created_at": stamp,
            "updated_at": stamp,
        },
        {"product": product, "employee": employee, "photos": [photo]},
    )
    try:
        d = dr.to_dict()
    except Exception as exc:  # noqa: BLE001
        fails.append("DamageReport.to_dict() gagal: %s: %s" % (type(exc).__name__, exc))
    else:
        for key in ("rejected_by", "rejected_at", "rejection_reason"):
            if key not in d:
                fails.append("DamageReport.to_dict() tidak punya key %r" % key)

    bc = make(
        Broadcast,
        {
            "id": "b1",
            "title": "Uji",
            "body": "Uji",
            "level": "INFO",
            "target": "ALL",
            "is_active": True,
            "starts_at": stamp,
            "expires_at": stamp,
            "created_at": stamp,
        },
        {},
    )
    try:
        d = bc.to_dict()
    except Exception as exc:  # noqa: BLE001
        fails.append("Broadcast.to_dict() gagal: %s: %s" % (type(exc).__name__, exc))
    else:
        for key in ("starts_at", "expires_at", "created_at"):
            if key not in d:
                fails.append("Broadcast.to_dict() tidak punya key %r" % key)
            elif not str(d[key]).endswith("Z"):
                fails.append("Broadcast.%s = %r, tidak berakhiran Z" % (key, d[key]))

    return fails


def main() -> int:
    fails = check_iso_utc() + check_to_dict_runs()
    if fails:
        print("GAGAL:")
        for f in fails:
            print("  -", f)
        return 1
    print("LULUS: iso_utc() benar dan to_dict() berjalan tanpa NameError.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
