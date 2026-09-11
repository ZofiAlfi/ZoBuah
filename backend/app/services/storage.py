"""Abstraksi penyimpanan file foto.

Mode "local": simpan di UPLOAD_DIR (dipakai saat development).
Mode "s3": simpan ke Backblaze B2 (atau S3-compatible) lewat boto3.

Kunci (key) selalu relatif, contoh "product/<id>.png" / "damage/<id>_0.jpg".
Url() menghasilkan path virtual "/uploads/<key>" untuk kedua mode; saat mode
"s3" endpoint /uploads di-main() mem-proxy dari B2 sehingga bucket tidak perlu
publik dan app selalu memakai baseUrl + /uploads/...
"""

from pathlib import Path

from ..config import settings


class BaseStorage:
    def save_bytes(self, key: str, data: bytes, content_type: str) -> None:
        raise NotImplementedError

    def read_bytes(self, key: str) -> bytes:
        raise NotImplementedError

    def delete(self, key: str) -> None:
        raise NotImplementedError

    def url(self, key: str) -> str:
        return f"/uploads/{key}"


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

    def read_bytes(self, key: str) -> bytes:
        target = self._path(key)
        if not target.is_file():
            raise FileNotFoundError(key)
        return target.read_bytes()

    def delete(self, key: str) -> None:
        target = self._path(key)
        if target.is_file():
            target.unlink(missing_ok=True)


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

    def read_bytes(self, key: str) -> bytes:
        try:
            obj = self._client.get_object(Bucket=settings.S3_BUCKET, Key=key)
        except Exception as e:
            if getattr(e, "response", {}).get("ResponseMetadata", {}).get("HTTPStatusCode") == 404:
                raise FileNotFoundError(key) from e
            raise
        return obj["Body"].read()

    def delete(self, key: str) -> None:
        self._client.delete_object(Bucket=settings.S3_BUCKET, Key=key)


def get_storage() -> BaseStorage:
    if settings.STORAGE == "s3":
        return S3Storage()
    return LocalStorage()


storage = get_storage()