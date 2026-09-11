import io
import uuid as _uuid
from datetime import datetime
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