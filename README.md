# Fruit POS

Aplikasi Point of Sale (POS) untuk toko buah dengan arsitektur **online/offline-first**:
- **Mobile app**: Flutter (Android) — bisa beroperasi offline (SQLite) lalu sinkron saat online.
- **Backend**: FastAPI (Python 3.11) + PostgreSQL.
- **Deploy**: Docker Compose + Nginx (termasuk HTTPS via let's encrypt / Certbot), cocok untuk VPS / Oracle Cloud.

---

## Fitur Utama

- **Role & kontrol akses** (dipaksa di backend, bukan sekadar sembunyi tombol):
  - `BOS` — akses penuh: kelola produk, karyawan, stok, laporan, audit log, approve/reject laporan kerusakan.
  - `KARYAWAN` — hanya penjualan, produk, transaksi sendiri, laporan kerusakan.
- **Produk** dengan unit desimal (kg, gram, buah, sisir, ikat, dus, paket, …), stok minimum, dan peringatan stok menipis.
- **Stok berbasis `stock_movements`**: `STOCK_IN`, `SALE`, `DAMAGE`, `ADJUSTMENT`, `RETURN`.
- **Laporan kerusakan (damage)**: status `PENDING` → `APPROVED`/`REJECTED` oleh BOS; `APPROVED` menambah movement `DAMAGE` dan mengurangi stok.
- **Offline-first**: SQLite + outbox (`PENDING`/`SYNCING`/`SYNCED`/`FAILED`), UUID idempotency, push/pull lewat `/api/v1/sync/push` & `/api/v1/sync/pull`.
- **Laporan**: harian/mingguan/bulanan, stok, laba (gross & bersih setelah waste), produk terlaris, penjualan per karyawan, audit log.

---

## Struktur Folder

```
PROJECTBUAH/
├── backend/                 # FastAPI backend
│   ├── app/                # kode aplikasi (routes, models, schemas, services)
│   ├── migrations/
│   │   ├── init.sql       # skema PostgreSQL lengkap + seed
│   │   └── init_db.sh     # menerapkan init.sql ke DB via docker exec
│   └── Dockerfile
├── fruit_pos/               # Flutter app (Android)
│   └── lib/
│       ├── api/            # ApiService (call backend)
│       ├── auth/           # AuthState, auth info
│       ├── core/           # constants, formatters, theme
│       ├── features/       # halaman: dashboard, sales, products, stock, damage,
│       │                   # reports, employees, audit, transactions, settings, login
│       ├── models/         # model + SQLite local DB
│       ├── shared/         # widget umum
│       └── sync/           # SyncManager, ConnectivityService (offline-first)
├── deploy/                  # nginx.conf, setup_server.sh, backup.sh, .env.example
├── scripts/                 # script bantuan
└── docker-compose.yml       # db + api + nginx + backup scheduler
```

---

## Akun Default

Dibuat otomatis saat backend pertama kali start (startup seed):

| Role | Username | Password |
|------|----------|----------|
| BOS  | `bos`    | `bos12345` |

> **PENTING**: ganti password akun BOS segera setelah deploy produksi.

---

## Menjalankan Backend (Docker Compose)

1. Siapkan environment:
   ```bash
   cp deploy/.env.example .env
   # lalu isi SECRET_KEY & DB_PASSWORD dengan nilai acak yang kuat
   ```
2. Jalankan:
   ```bash
   docker compose up -d --build
   ```
3. Skema + seed diterapkan otomatis saat container DB pertama kali dibuat via `backend/migrations/init.sql`.

Server API tersedia di `http://<host>:80/api/v1` (lihat `deploy/nginx.conf`).

### Seed manual (jika DB sudah ada dan ingin reset skema)
```bash
bash backend/migrations/init_db.sh
```

---

## Menjalankan Backend (Development / tanpa Docker)

```bash
cd backend
python -m venv venv
venv\Scripts\activate          # Windows  |  source venv/bin/activate  (Linux/macOS)
pip install -r requirements.txt
# buat DB PostgreSQL lalu set DATABASE_URL di environment (lihat .env.example)
uvicorn app.main:app --reload
```

Dokumentasi OpenAPI (Swagger) otomatis tersedia di `http://localhost:8000/docs`.

---

## Menjalankan Flutter App

```bash
cd fruit_pos
flutter pub get
flutter run
```

Sebelum run pastikan `AppConstants.baseUrl` di `fruit_pos/lib/core/constants.dart` menunjuk ke server yang benar
(misal `https://pos.domain.com`), bukan placeholder `https://your-server.example.com`.

### Build APK release
```bash
flutter build apk --release
# hasil: fruit_pos/build/app/outputs/flutter-apk/app-release.apk
```

---

## Deploy ke Server (Oracle Cloud / VPS)

```bash
# 1. Jalankan setup satu kali di server baru
bash deploy/setup_server.sh

# 2. Salin project ke server, buat .env, lalu:
docker compose up -d --build

# 3. HTTPS (Let's Encrypt) via nginx + certbot
#    - Pasang cert di deploy/nginx.conf (server_name + ssl_certificate)
#    - Jalankan certbot certonly untuk domain Anda
```

### Backup
- Scheduler bawaan (`backup` service di docker-compose.yml) mengambil `pg_dump` setiap 02:30 dan menyimpannya di `deploy/backup/` (retensi 7 hari).
- Backup manual: `bash deploy/backup.sh`.

---

## API Ringkas (prefix `/api/v1`)

- **Auth**: `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`, `GET /auth/me`
- **Users (BOS)**: `GET/POST /auth/users`, `PUT /auth/users/{id}`
- **Products**: `GET/POST /products`, `GET/PUT/DELETE /products/{id}`, `GET/POST /products/categories`, `PUT/DELETE /products/categories/{id}`
- **Stock**: `GET /stock`, `POST /stock/in`, `POST /stock/adjustment`, `GET /stock/movements`
- **Sales**: `POST /sales`, `GET /sales`, `GET /sales/{id}`, `POST /sales/{id}/cancel`
- **Damage**: `POST /damage-reports`, `GET /damage-reports`, `GET/DELETE /damage-reports/{id}`, `POST .../approve|reject`
- **Reports**: `/reports/daily`, `/reports/weekly`, `/reports/monthly`, `/reports/top-products`, `/reports/by-employee`, `/reports/damage`, `/reports/dashboard`, `/reports/stock`, `/reports/profit`
- **Audit**: `GET /audit/logs`
- **Sync**: `POST /sync/push`, `POST /sync/pull`

---

## Teknologi

- **Frontend**: Flutter `^3.7.2`, provider, http, sqflite, connectivity_plus, uuid, flutter_secure_storage, image_picker.
- **Backend**: Python 3.11, FastAPI, SQLAlchemy, psycopg2, PostgreSQL 16, JWT auth.
- **Infra**: Docker Compose, Nginx, Let's Encrypt/Certbot, cron backup.
