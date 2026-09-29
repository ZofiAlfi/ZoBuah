import io
import uuid as _uuid
from datetime import datetime, timezone
from typing import Optional


def generate_uuid() -> str:
    return str(_uuid.uuid4())


def generate_transaction_number(date: Optional[datetime] = None) -> str:
    dt = date or datetime.now()
    return f"TRX-{dt.strftime('%Y%m%d')}-{str(_uuid.uuid4()).upper()[:6]}"


def parse_iso_date(value: str) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def validate_image_bytes(data: bytes, max_size_mb: int = 5) -> bool:
    max_bytes = max_size_mb * 1024 * 1024
    return len(data) <= max_bytes and len(data) > 0


def iso_utc(value: Optional[datetime]) -> Optional[str]:
    """Serialisasi datetime ke ISO-8601 UTC yang eksplisit (suffix Z).

    Semua kolom waktu di database adalah TIMESTAMP TANPA ZONA dan diisi
    dengan datetime.utcnow(), jadi isinya UTC. Versi lama memanggil
    .isoformat() langsung, yang menghasilkan "2026-09-28T15:51:18.668954"
    TANPA offset. String seperti itu ambigu, dan JavaScript membacanya
    sebagai waktu LOKAL browser. Akibatnya Owner Console menampilkan jam
    server dalam zona browser: 7 jam meleset untuk WIB, dan benar hanya
    kebetulan kalau browser kebetulan di UTC.

    Suffix "Z" membuat maksudnya tidak mungkin salah dibaca: ini instant UTC.
    Klien bebas mengonversi ke zona tampilnya masing-masing.
    """
    if value is None:
        return None
    # Naive berarti UTC, karena itu cara kolomnya diisi. Value yang sudah
    # punya zona dikonversi ke UTC dulu supaya tidak ada dua bentuk keluaran.
    if value.tzinfo is None:
        return value.isoformat() + "Z"
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")