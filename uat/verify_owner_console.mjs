// Skrip verifikasi kontrak Owner Console.
//
// Menembak SETIAP endpoint yang dipanggil frontend, lalu memeriksa bentuk
// respons sesuai apa yang diketik di src/lib/types.ts. Tujuannya bukan
// menguji logika backend (itu sudah ada di UAT admin), tapi memastikan
// tidak ada layar yang dibangun di atas asumsi yang salah.
//
// Jalankan: node uat/verify_owner_console.mjs

const BASE = process.env.API ?? "http://127.0.0.1:8000/api/v1";
const USERNAME = process.env.OWNER_USER ?? "owner";
const PASSWORD = process.env.OWNER_PASS ?? "owner-secret-123";

let pass = 0;
let fail = 0;
const failures = [];

function check(name, condition, detail = "") {
  if (condition) {
    pass += 1;
    console.log(`  LULUS  ${name}`);
  } else {
    fail += 1;
    failures.push(name);
    console.log(`  GAGAL  ${name}  ${detail}`);
  }
}

let token = null;
const created = { store: null, user: null, broadcast: null };

/* extraHeaders dipakai saat pengujian perlu token selain token OWNER, misalnya
 * login POS untuk membuktikan broadcast tidak bocor antar toko. */
async function call(method, path, body, extraHeaders = {}) {
  const headers = { Accept: "application/json", ...extraHeaders };
  if (token && !headers.Authorization) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers["Content-Type"] = "application/json";

  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  const raw = await res.text();
  let parsed = null;
  if (raw) {
    try {
      parsed = JSON.parse(raw);
    } catch {
      parsed = raw;
    }
  }
  return { status: res.status, body: parsed };
}

const isArr = (v) => Array.isArray(v);
const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const hasKeys = (v, keys) =>
  v !== null && typeof v === "object" && !isArr(v) && keys.every((k) => k in v);

async function main() {
  console.log("== LOGIN ==");
  const login = await call("POST", "/admin/auth/login", { username: USERNAME, password: PASSWORD });
  check("POST /admin/auth/login", login.status === 200, `status=${login.status}`);
  check("respons login punya owner", hasKeys(login.body, ["access_token", "refresh_token", "owner"]));
  token = login.body?.access_token ?? null;

  const me = await call("GET", "/admin/auth/me");
  check("GET /admin/auth/me", me.status === 200 && me.body?.username === USERNAME, `status=${me.status}`);

  const refreshed = await call("POST", "/admin/auth/refresh", {
    refresh_token: login.body.refresh_token,
  });
  check("POST /admin/auth/refresh", refreshed.status === 200, `status=${refreshed.status}`);
  check("refresh mengembalikan owner", hasKeys(refreshed.body, ["access_token", "owner"]));

  console.log("\n== DASHBOARD & METRICS ==");
  const dash = await call("GET", "/admin/dashboard");
  check("GET /admin/dashboard", dash.status === 200, `status=${dash.status}`);
  check(
    "dashboard punya 5 blok",
    hasKeys(dash.body, ["overview", "revenue_30d", "top_stores", "plans", "alerts"]),
    Object.keys(dash.body ?? {}).join(","),
  );
  check("tren 30 titik", isArr(dash.body?.revenue_30d) && dash.body.revenue_30d.length === 30, `n=${dash.body?.revenue_30d?.length}`);
  check(
    "titik tren punya 5 field",
    isArr(dash.body?.revenue_30d) && hasKeys(dash.body.revenue_30d[0], ["date", "revenue", "modal", "profit", "transactions"]),
  );
  check("tren bukan semua nol", (dash.body?.revenue_30d ?? []).some((p) => p.transactions > 0));

  /* Jaga agar jendela waktu KPI dan deret harian tidak lagi berbeda. Dulu
   * jendela aggregat mulai 30x24 jam lalu sementara deret harian mulai dari
   * tanggal (hari ini - 29), jadi ada transaksi yang masuk KPI tapi hilang
   * dari grafik. Owner akan melihat dua angka berbeda untuk hal yang sama. */
  const seriesRevenue = (dash.body?.revenue_30d ?? []).reduce((s, p) => s + p.revenue, 0);
  const seriesTx = (dash.body?.revenue_30d ?? []).reduce((s, p) => s + p.transactions, 0);
  check(
    "jumlah tren sama dengan KPI omzet",
    Math.abs(seriesRevenue - dash.body.overview.revenue_30d) < 1,
    `tren=${seriesRevenue} kpi=${dash.body.overview.revenue_30d}`,
  );
  check(
    "jumlah transaksi tren sama dengan KPI",
    seriesTx === dash.body.overview.total_sales_30d,
    `tren=${seriesTx} kpi=${dash.body.overview.total_sales_30d}`,
  );
  check(
    "tanggal tren berurutan tanpa lompatan",
    (() => {
      const dates = (dash.body?.revenue_30d ?? []).map((p) => p.date);
      for (let i = 1; i < dates.length; i += 1) {
        const prev = new Date(`${dates[i - 1]}T00:00:00Z`).getTime();
        const cur = new Date(`${dates[i]}T00:00:00Z`).getTime();
        if (cur - prev !== 86400000) return false;
      }
      return dates.length === 30;
    })(),
    "tanggal tren harus 30 hari berturut-turut",
  );
  check(
    "overview punya field KPI",
    hasKeys(dash.body?.overview, [
      "total_stores",
      "active_stores",
      "revenue_30d",
      "profit_30d",
      "healthy_stores",
      "dead_stores",
      "avg_revenue_per_store_30d",
      "pending_damage_total",
      "expiring_soon",
      "trial_stores",
      "total_users",
      "total_products",
      "total_devices",
    ]),
    Object.keys(dash.body?.overview ?? {}).join(","),
  );

  const overview = await call("GET", "/admin/metrics/overview");
  check("GET /admin/metrics/overview", overview.status === 200, `status=${overview.status}`);

  const revenue = await call("GET", "/admin/metrics/revenue?days=30");
  check("GET /admin/metrics/revenue mengembalikan array", isArr(revenue.body) && revenue.body.length === 30, `status=${revenue.status}`);

  const storeId = dash.body?.top_stores?.[0]?.store_id;
  const revenueOne = await call("GET", `/admin/metrics/revenue?days=30&store_id=${storeId}`);
  check("GET /admin/metrics/revenue?store_id", revenueOne.status === 200 && isArr(revenueOne.body), `status=${revenueOne.status}`);

  const top = await call("GET", "/admin/metrics/top-stores");
  check("GET /admin/metrics/top-stores mengembalikan array", isArr(top.body), `status=${top.status}`);
  check(
    "baris top-stores punya 6 field",
    isArr(top.body) && hasKeys(top.body[0], ["store_id", "code", "store_name", "revenue", "profit", "transactions"]),
  );
  check(
    "total top-stores sama dengan KPI omzet",
    isArr(top.body) &&
      Math.abs(top.body.reduce((s, r) => s + r.revenue, 0) - dash.body.overview.revenue_30d) < 1,
  );

  const plans = await call("GET", "/admin/metrics/plans");
  check("GET /admin/metrics/plans mengembalikan array", isArr(plans.body), `status=${plans.status}`);
  check(
    "baris plans punya 6 field",
    isArr(plans.body) && hasKeys(plans.body[0], ["plan", "store_count", "active_store_count", "expired_count", "revenue_30d"]),
  );

  const usage = await call("GET", "/admin/metrics/usage");
  check("GET /admin/metrics/usage mengembalikan array", isArr(usage.body), `status=${usage.status}`);
  check(
    "baris usage punya 10 field",
    isArr(usage.body) &&
      hasKeys(usage.body[0], [
        "store_id",
        "code",
        "store_name",
        "plan",
        "user_count",
        "product_count",
        "category_count",
        "device_count",
        "sale_count_30d",
        "revenue_30d",
        "last_sync_at",
        "health",
      ]),
    Object.keys(usage.body?.[0] ?? {}).join(","),
  );
  check("usage punya transaksi nyata", isArr(usage.body) && usage.body.filter((u) => u.sale_count_30d > 0).length >= 3, `punya transaksi=${usage.body?.filter((u) => u.sale_count_30d > 0).length}`);
  /* Toko yang belum pernah buka harus melaporkan nol, bukan ikut error.
   * Inilah kasus yang dulu luput karena UAT awal hanya punya 2 toko dan
   * keduanya sudah berisi transaksi. */
  check(
    "toko tanpa transaksi melaporkan nol",
    isArr(usage.body) && usage.body.some((u) => u.sale_count_30d === 0),
  );

  const health = await call("GET", "/admin/stores/health");
  check("GET /admin/stores/health mengembalikan array", isArr(health.body), `status=${health.status}`);
  check(
    "baris health punya 8 field",
    isArr(health.body) &&
      hasKeys(health.body[0], [
        "store_id",
        "code",
        "store_name",
        "health",
        "last_sync_at",
        "hours_since_sync",
        "device_count",
        "failed_sync_7d",
      ]),
    Object.keys(health.body?.[0] ?? {}).join(","),
  );

  const alerts = await call("GET", "/admin/alerts");
  check("GET /admin/alerts", alerts.status === 200, `status=${alerts.status}`);

  console.log("\n== TOKO ==");
  const stores = await call("GET", "/admin/stores?page_size=100");
  check("GET /admin/stores", stores.status === 200 && isArr(stores.body?.items), `status=${stores.status}`);
  check("stores punya meta", hasKeys(stores.body?.meta, ["page", "page_size", "total", "total_pages"]));
  check(
    "baris toko punya 17 field",
    hasKeys(stores.body?.items?.[0], [
      "id", "code", "name", "owner_name", "phone", "address", "plan", "plan_expires_at",
      "days_to_expiry", "status", "is_active", "health", "last_sync_at", "user_count",
      "product_count", "sale_count_30d", "revenue_30d", "created_at",
    ]),
    Object.keys(stores.body?.items?.[0] ?? {}).join(","),
  );
  check("toko melaporkan transaksi", stores.body.items.some((s) => s.sale_count_30d > 0));

  const filtered = await call("GET", "/admin/stores?plan=PRO&status=ACTIVE&page_size=50");
  check("GET /admin/stores?plan&status", filtered.status === 200, `status=${filtered.status}`);
  check(
    "filter benar-benar menyaring",
    isArr(filtered.body?.items) && filtered.body.items.every((s) => s.plan === "PRO" && s.status === "ACTIVE"),
  );

  const detail = await call("GET", `/admin/stores/${storeId}`);
  check("GET /admin/stores/{id}", detail.status === 200, `status=${detail.status}`);
  check(
    "detail punya field tambahan",
    hasKeys(detail.body, [
      "device_count", "category_count", "low_stock_count", "pending_damage_count",
      "failed_sync_count_7d", "total_sales", "lifetime_revenue",
    ]),
    Object.keys(detail.body ?? {}).join(","),
  );

  const storeUsers = await call("GET", `/admin/stores/${storeId}/users`);
  check("GET /admin/stores/{id}/users", storeUsers.status === 200 && isArr(storeUsers.body?.items), `status=${storeUsers.status}`);

  /* Kode toko unik per jalannya. API tidak punya hapus toko, jadi kode tetap
   * yang sama akan bentrok pada run kedua; dengan kode unik tiap run, skrip
   * bisa dijalankan berulang tanpa Prepare ulang. Toko uji yang tertinggal
   * sudah dinonaktifkan di bagian BERSIHKAN. */
  const vtCode = `VT${Date.now().toString(36).slice(-6).toUpperCase()}`.slice(0, 10);

  const newStore = await call("POST", "/admin/stores", {
    code: vtCode,
    name: "Toko Uji Kontrak",
    owner_name: "Verifikasi Kontrak",
    plan: "BASIC",
    bos_username: `bovt${vtCode.slice(2).toLowerCase()}`.slice(0, 20),
    bos_full_name: "BOS Verifikasi",
    bos_password: "bos-secret-123",
  });
  check("POST /admin/stores", newStore.status === 200 || newStore.status === 201, `status=${newStore.status} ${JSON.stringify(newStore.body).slice(0, 160)}`);
  created.store = newStore.body?.store?.id ?? newStore.body?.id ?? null;
  created.storeCode = vtCode;

  const users = await call("GET", "/admin/users?page_size=25");
  check("GET /admin/users", users.status === 200 && isArr(users.body?.items), `status=${users.status}`);

  console.log("\n== PENGGUNA TOKO ==");
  const target = storeUsers.body?.items?.[0];
  const patched = await call("PATCH", `/admin/users/${target.id}`, { full_name: target.full_name });
  check("PATCH /admin/users/{id}", patched.status === 200, `status=${patched.status}`);

  const createdUser = await call("POST", `/admin/stores/${created.store}/users`, {
    username: `kar${created.storeCode.slice(2).toLowerCase()}`,
    full_name: "Karyawan Verifikasi",
    role: "KARYAWAN",
    password: "karyawan-secret-123",
  });
  check(
    "POST /admin/stores/{id}/users",
    createdUser.status === 200 || createdUser.status === 201,
    `status=${createdUser.status} ${JSON.stringify(createdUser.body).slice(0, 160)}`,
  );
  created.user = createdUser.body?.id ?? createdUser.body?.user?.id ?? null;
  check(
    "pengguna uji punya id",
    typeof created.user === "string" && created.user.length > 0,
    JSON.stringify(createdUser.body).slice(0, 120),
  );

  if (created.user) {
    /* Tanpa body. Endpoint ini tidak menerima sandi yang diketik owner: ia
     * membuat sandi sementara acak dan mencabut semua token pengguna. Body
     * berisi new_password tidak akan ditolak, hanya diam-diam diabaikan. */
    const reset = await call("POST", `/admin/users/${created.user}/reset-password`);
    check("POST /admin/users/{id}/reset-password", reset.status === 200, `status=${reset.status} ${JSON.stringify(reset.body).slice(0, 120)}`);
    check(
      "reset-password mengembalikan sandi sementara",
      typeof reset.body?.temporary_password === "string" && reset.body.temporary_password.length >= 6,
      JSON.stringify(reset.body).slice(0, 140),
    );
    check(
      "reset-password melaporkan username yang benar",
      reset.body?.username === `kar${created.storeCode.slice(2).toLowerCase()}`,
      `dapat=${reset.body?.username}`,
    );

    /* Sandi sementara harus benar-benar berlaku. Pengguna ini KARYAWAN, jadi
     * dibuktikan lewat login POS (/auth/login), bukan login admin yang khusus
     * OWNER. */
    const temporary = reset.body?.temporary_password;
    if (typeof temporary === "string" && temporary.length > 0) {
      const reLogin = await call("POST", "/auth/login", {
        username: `kar${created.storeCode.slice(2).toLowerCase()}`,
        password: temporary,
      });
      check(
        "sandi sementara hasil reset bisa dipakai login POS",
        reLogin.status === 200 && typeof reLogin.body?.access_token === "string",
        `status=${reLogin.status}`,
      );

      const stale = await call("POST", "/auth/login", {
        username: `kar${created.storeCode.slice(2).toLowerCase()}`,
        password: "karyawan-secret-123",
      });
      check(
        "sandi lama tidak lagi berlaku setelah reset",
        stale.status === 401 || stale.status === 403,
        `status=${stale.status}`,
      );
    }

    const forced = await call("POST", `/admin/users/${created.user}/force-logout`);
    check("POST /admin/users/{id}/force-logout", forced.status === 200, `status=${forced.status} ${JSON.stringify(forced.body).slice(0, 120)}`);
  } else {
    /* Jangan lanjut dengan id yang kosong: endpoint berikutnya akan 422
     * karena UUID tidak valid, dan itu hanya menambah deretan galat yang
     * tidak berhubungan dengan masalah sebenarnya. */
    check("reset-password dan force-logout diuji", false, "pembuatan pengguna tidak menghasilkan id");
  }

  console.log("\n== IMPERSONASI ==");
  /* store_id di body itu wajib, bukan opsional. Endpoint ini menerima
   * store_id dua kali (path dan body); sengaja memanggil sesuai kontrak
   * yang ada supaya skrip ini menangkap perubahan kontrak nanti. */
  const imp = await call("POST", `/admin/stores/${storeId}/impersonate`, { store_id: storeId });
  check("POST /admin/stores/{id}/impersonate", imp.status === 200, `status=${imp.status} ${JSON.stringify(imp.body).slice(0, 140)}`);
  check("token tinjauan bersifat read-only", imp.body?.read_only === true, JSON.stringify(imp.body).slice(0, 120));
  check("token tinjauan punya masa berlaku", typeof imp.body?.expires_in_minutes === "number");
  check(
    "token tinjauan mengembalikan access_token",
    typeof imp.body?.access_token === "string" && imp.body.access_token.length > 0,
  );

  /* Id T01 dicari eksplisit dari daftar toko, bukan memakai top_stores[0]:
   * toko itu ditentukan oleh omzet dan bisa berganti, sedangkan tes di bawah
   * membandingkan T01 dengan T02 jadi keduanya harus pasti. */
  const storeList = await call("GET", "/admin/stores?page_size=100");
  const t01Id = (storeList.body?.items ?? []).find((s) => s.code === "T01")?.id ?? null;
  const t02Id = (storeList.body?.items ?? []).find((s) => s.code === "T02")?.id ?? null;
  check("toko T01 dan T02 ditemukan untuk uji broadcast", !!t01Id && !!t02Id, `T01=${t01Id} T02=${t02Id}`);

  console.log("\n== BROADCAST ==");
  const bcList = await call("GET", "/admin/broadcasts?page_size=100");
  check("GET /admin/broadcasts", bcList.status === 200 && isArr(bcList.body?.items), `status=${bcList.status}`);

  const bcCreate = await call("POST", "/admin/broadcasts", {
    title: "Verifikasi kontrak",
    body: "Broadcast ini dibuat oleh skrip verifikasi kontrak.",
    level: "INFO",
    target: "ALL",
    starts_at: new Date().toISOString(),
  });
    check("POST /admin/broadcasts", bcCreate.status === 200 || bcCreate.status === 201, `status=${bcCreate.status} ${JSON.stringify(bcCreate.body).slice(0, 160)}`);
    created.broadcast = bcCreate.body?.id ?? null;

    /* Broadcast per-toko khusus T01, sengaja dibuat dengan level yang sama
     * (INFO) supaya ia harus mengalahkan pengumuman global dalam tes urutan
     * "yang terbaru menang". Tidak dinonaktifkan di sini; dibersihkan di
     * bagian BERSIHKAN. */
    const bcTargeted = await call("POST", "/admin/broadcasts", {
      title: "Verifikasi kontrak per-toko",
      body: "Hanya untuk T01.",
      level: "INFO",
      target: "STORE",
      store_id: t01Id,
      starts_at: new Date().toISOString(),
    });
    check(
      "POST /admin/broadcasts target=STORE",
      bcTargeted.status === 200 || bcTargeted.status === 201,
      `status=${bcTargeted.status} ${JSON.stringify(bcTargeted.body).slice(0, 160)}`,
    );
    created.targetedBroadcast = bcTargeted.body?.id ?? null;


  const bcPatch = await call("PATCH", `/admin/broadcasts/${created.broadcast}`, {
    level: "WARNING",
  });
  check("PATCH /admin/broadcasts/{id}", bcPatch.status === 200 && bcPatch.body?.level === "WARNING", `status=${bcPatch.status}`);

  const bcDelete = await call("DELETE", `/admin/broadcasts/${created.broadcast}`);
  check("DELETE /admin/broadcasts/{id} (menonaktifkan)", bcDelete.status === 200, `status=${bcDelete.status}`);

  const afterDeactivate = await call("GET", "/admin/broadcasts?page_size=100");
  const still = afterDeactivate.body?.items?.find((b) => b.id === created.broadcast);
  check("broadcast nonaktif masih ada di daftar", still !== undefined);
  check("broadcast nonaktif ditandai tidak aktif", still?.is_active === false);

  console.log("\n== BROADCAST SAMPAI KE POS ==");

  /* Dua hal yang pernah salah dan keduanya diam-diam saja:
   *  1. Broadcast per-toko tidak boleh bocor ke toko lain.
   *  2. Satu level hanya boleh memuat pengumuman TERBARU. Dulu query sudah
   *     terurut starts_at DESC tapi assignment menimpanya, jadi yang paling
   *     lama yang menang dan pengumuman baru tidak pernah muncul sama sekali.
   */
  const notices = await call("POST", "/auth/login", { username: "bost01", password: "bos-secret-123" });
  check("BOS T01 bisa login POS untuk cek broadcast", notices.status === 200, `status=${notices.status}`);

  if (notices.status === 200) {
    const nh = { Authorization: `Bearer ${notices.body.access_token}` };
    const mine = await call("POST", "/sync/pull", { device_id: "verifikasi-broadcast" }, nh);
    const other = await call("POST", "/auth/login", { username: "bost02", password: "bos-secret-123" });
    const theirSettings = other.status === 200
      ? (await call("POST", "/sync/pull", { device_id: "verifikasi-broadcast" }, {
          Authorization: `Bearer ${other.body.access_token}`,
        })).body?.app_settings
      : undefined;

    check("sync/pull mengembalikan app_settings", isObj(mine.body?.app_settings), JSON.stringify(mine.body?.app_settings ?? null).slice(0, 120));

    const levels = Object.keys(mine.body?.app_settings ?? {});
    check("app_settings memakai kunci level", levels.every((l) => ["info", "warning", "maintenance"].includes(l)), levels.join(","));

    const noticesById = Object.values(mine.body?.app_settings ?? {});
    check("tiap pengumuman punya judul dan isi", noticesById.every((n) => n && typeof n.title === "string" && typeof n.body === "string"));

    /* Yang terbaru harus menang per level. bcTargeted dibuat paling akhir dari
     * semua broadcast INFO, jadi T01 harus melihat judulnya, bukan yang lebih
     * lama. Dulu assignment menimpa urutan DESC sehingga yang paling lama
     * menang dan pengumuman baru tidak pernah muncul. */
    check(
      "per level, pengumuman terbaru yang tampil",
      mine.body?.app_settings?.info?.title === "Verifikasi kontrak per-toko",
      `T01 info=${JSON.stringify(mine.body?.app_settings?.info?.title)}`,
    );
    check(
      "id yang tampil di T01 adalah broadcast milik T01",
      mine.body?.app_settings?.info?.id === created.targetedBroadcast,
      `id=${mine.body?.app_settings?.info?.id} harap=${created.targetedBroadcast}`,
    );

    const mineIds = new Set(noticesById.map((n) => n.id));
    const theirIds = new Set(Object.values(theirSettings ?? {}).map((n) => n.id));
    check(
      "broadcast milik T01 tidak muncul di T02",
      ![...mineIds].some((id) => theirIds.has(id) && id === created.targetedBroadcast),
      `tidak boleh ada yang sama dari broadcast per-toko`,
    );
    check(
      "kedua toko sama-sama melihat pengumuman global",
      [...mineIds].some((id) => theirIds.has(id)),
      "pengumuman target=ALL harus sampai ke semua toko",
    );
  }

  console.log("\n== LOG AUDIT ==");
  const audit = await call("GET", "/admin/audit-logs?page_size=30");
  check("GET /admin/audit-logs", audit.status === 200 && isArr(audit.body?.items), `status=${audit.status}`);
  check(
    "baris audit punya 9 field",
    hasKeys(audit.body?.items?.[0], [
      "id", "user_id", "username", "store_id", "store_name",
      "action", "entity_type", "entity_id", "details", "ip_address", "created_at",
    ]),
    Object.keys(audit.body?.items?.[0] ?? {}).join(","),
  );
  check(
    "aktivitasOwner tercatat di audit",
    (audit.body?.items ?? []).some((l) => l.username === USERNAME),
  );

  console.log("\n== CORS ==");
  const preflight = await fetch(`${BASE}/admin/dashboard`, {
    method: "OPTIONS",
    headers: {
      Origin: "http://localhost:5173",
      "Access-Control-Request-Method": "GET",
    },
  });
  check("CORS mengizinkan origin Owner Console", preflight.headers.get("access-control-allow-origin") === "http://localhost:5173", `status=${preflight.status}`);
  const posOrigin = await fetch(`${BASE}/admin/dashboard`, {
    method: "OPTIONS",
    headers: { Origin: "http://localhost:8080", "Access-Control-Request-Method": "GET" },
  });
  check("CORS tetap mengizinkan origin POS", posOrigin.headers.get("access-control-allow-origin") === "http://localhost:8080");

  console.log("\n== ROL ==");
  const denied = await fetch(`${BASE}/admin/dashboard`);
  check("dashboard menolak tanpa token", denied.status === 401, `status=${denied.status}`);

  /* Tidak ada endpoint hapus toko, jadi toko uji tidak bisa dibuang. Supaya
   * menjalankan skrip berkali-kali tidak menumpuk VT01 yang never-clean,
   * toko uji dinonaktifkan dan diberi nama yang jelas. Kalau jumlah toko
   * sudah menumpuk, seed ulang lebih bersih: seed_uat.py --reset. */
  console.log("\n== BERSIHKAN ==");
  if (created.store) {
    const parked = await call("PATCH", `/admin/stores/${created.store}`, {
      name: "Toko Uji Kontrak (nonaktif)",
      status: "SUSPENDED",
      is_active: false,
    });
    check("menonaktifkan toko uji", parked.status === 200, `status=${parked.status}`);
  }
  if (created.user) {
    const off = await call("PATCH", `/admin/users/${created.user}`, { is_active: false });
    check("menonaktifkan pengguna uji", off.status === 200, `status=${off.status}`);
  }

  console.log(`\n${"=".repeat(66)}`);
  console.log(`LULUS ${pass}   GAGAL ${fail}`);
  if (failures.length) console.log(`Gagal: ${failures.join(", ")}`);
  console.log("=".repeat(66));
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("Gagal menjalankan verifikasi:", e.message);
  process.exit(1);
});
