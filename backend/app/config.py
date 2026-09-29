import os
from datetime import timedelta
from dotenv import load_dotenv

load_dotenv()


class Settings:
    APP_NAME: str = "Fruit POS API"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = os.getenv("DEBUG", "False").lower() == "true"

    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql+psycopg2://fruitpos:fruitpos@localhost:5432/fruitpos",
    )

    SECRET_KEY: str = os.getenv("SECRET_KEY", "change-me-in-production")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "480"))
    REFRESH_TOKEN_EXPIRE_DAYS: int = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "30"))

    # Token impersonate OWNER ke toko sengaja berumur pendek. Owner sering
    # membuka banyak toko untuk keperluan dukungan, dan token yang terlalu
    # lama menjadi jalur sampingan untuk mengubah data pelanggan.
    IMPERSONATION_EXPIRE_MINUTES: int = int(os.getenv("IMPERSONATION_EXPIRE_MINUTES", "15"))

    # Jendela waktu untuk data yang sudah dibuang: laporan rusak dan sync gagal.
    # Alert hanya menghitung yang masih berada di dalam jendela ini.
    ALERT_WINDOW_DAYS: int = int(os.getenv("ALERT_WINDOW_DAYS", "7"))

    ALLOWED_ORIGINS: list = os.getenv(
        "ALLOWED_ORIGINS", "http://localhost,http://localhost:8080"
    ).split(",")

    # Origin untuk ZoBuah Owner Console (web dashboard).
    # Dev: Vite di 5173 memakai proxy sehingga CORS tidak perlu, tapi tetap
    # didaftarkan agar mode tanpa proxy (mis. test langsung ke API) jalan.
    ADMIN_ORIGINS: list = os.getenv(
        "ADMIN_ORIGINS", "http://localhost:5173,http://localhost:4173"
    ).split(",")

    # Akun OWNER awal. Dipakai seed_initial_data() hanya bila belum ada
    # owner sama sekali, dan passwordnya wajib diganti setelah login pertama.
    OWNER_USERNAME: str = os.getenv("OWNER_USERNAME", "owner")
    OWNER_PASSWORD: str = os.getenv("OWNER_PASSWORD", "")
    OWNER_FULL_NAME: str = os.getenv("OWNER_FULL_NAME", "Pemilik Layanan")

    # Gerbang safety untuk perubahan skema.
    #
    # create_all() dan migration runner HANYA boleh mengubah skema kalau
    # DATABASE_URL menunjuk ke database lokal, atau ALLOW_REMOTE_DDL=1
    # disetel eksplisit. Tanpa gerbang ini, satu salah import urut di
    # script UAT/otomasi cukup untuk menjalankan DDL ke produksi.
    # Produksi tidak akan ikut ter-migrasi diam-diam; harus ada keputusan
    # sadar setiap kali memang mau menerapkan migrasi ke sana.
    ALLOW_REMOTE_DDL: str = os.getenv("ALLOW_REMOTE_DDL", "0")

    MAX_UPLOAD_SIZE_MB: int = int(os.getenv("MAX_UPLOAD_SIZE_MB", "5"))
    UPLOAD_DIR: str = os.getenv("UPLOAD_DIR", "/data/uploads")

    # Storage foto: "local" (disk, dev) atau "s3" (Backblaze B2 / S3-compatible, prod)
    STORAGE: str = os.getenv("STORAGE", "local")
    S3_ENDPOINT_URL: str = os.getenv("S3_ENDPOINT_URL", "")
    S3_ACCESS_KEY_ID: str = os.getenv("S3_ACCESS_KEY_ID", "")
    S3_SECRET_ACCESS_KEY: str = os.getenv("S3_SECRET_ACCESS_KEY", "")
    S3_BUCKET: str = os.getenv("S3_BUCKET", "")


settings = Settings()