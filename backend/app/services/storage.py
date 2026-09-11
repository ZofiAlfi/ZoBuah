"""Abstraksi penyimpanan file foto.

Mode "local": simpan di UPLOAD_DIR (dipakai saat development).
Mode "s3": simpan ke Backblaze B2 (atau S3-compatible) lewat boto3.

Kunci (key) selalu relatif, contoh "product/<id>.png" / "damage/<id>_0.jpg".
Url() menghasilkan URL absolut untuk ditampilkan app:
  - local -> "/uploads/<key>" (di-mount StaticFiles di main.py)
  - s3    -> S3_PUBLIC_BASE_URL + "/" + key
"""

from pathlib import Path

from ..config import settings


class BaseStorage:
    def save_bytes(self, key: str, data: bytes, content_type: str) -> None:
        raise NotImplementedError

    def delete(self, key: str) -> None:
        raise NotImplementedError

    def url(self, key: str) -> str:
        raise NotImplementedError


class LocalStorage(BaseStorage):
    def _path(self, key: str) -> Path:
        # amankan path traversal
        base = Path(settings.UPLOAD_DIR).resolve()
        target = (base / key).resolve()
        if not target.is_relative_to(base):
            raise ValueError("invalid key")
        return target

    def save_bytes(self, key: str, data: bytes, content_type: str) -> None:
        target = self._path(key)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

    def delete(self, key: str) -> None:
        target = self._path(key)
        if target.is_file():
            target.unlink(missing_ok=True)

    def url(self, key: str) -> str:
        return f"/uploads/{key}"


class S3Storage(BaseStorage):
    def __init__(self) -> None:
        import boto3
        session = boto3.session.Session(
            aws_access_key_id=settings.S3_ACCESS_KEY_ID,
            aws_secret_access_key=settings.S3_SECRET_ACCESS_KEY,
        )
        self._client = session.client(
            "s3",
            endpoint_url=settings.S3_ENDPOINT_URL or None,
            region_name="",
        )

    def save_bytes(self, key: str, data: bytes, content_type: str) -> None:
        self._client.put_object(
            Bucket=settings.S3_BUCKET,
            Key=key,
            Body=data,
            ContentType=content_type,
        )

    def delete(self, key: str) -> None:
        self._client.delete_object(Bucket=settings.S3_BUCKET, Key=key)

    def url(self, key: str) -> str:
        return f"{settings.S3_PUBLIC_BASE_URL.rstrip('/')}/{key}"


def get_storage() -> BaseStorage:
    if settings.STORAGE == "s3":
        return S3Storage()
    return LocalStorage()


storage = get_storage()