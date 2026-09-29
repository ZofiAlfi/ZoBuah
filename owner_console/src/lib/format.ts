const rupiah = new Intl.NumberFormat("id-ID", {
  style: "currency",
  currency: "IDR",
  maximumFractionDigits: 0,
});

const plain = new Intl.NumberFormat("id-ID", { maximumFractionDigits: 0 });

const decimal = new Intl.NumberFormat("id-ID", {
  minimumFractionDigits: 0,
  maximumFractionDigits: 2,
});

export const money = (value: number | null | undefined) => rupiah.format(value ?? 0);

/* Versi ringkas untuk kartu KPI: Rp 1,2 jt. Angka penuh tetap dipakai di
 * dalam tabel supaya tidak ada yang perlu ditebak. */
export function moneyShort(value: number | null | undefined): string {
  const v = value ?? 0;
  const abs = Math.abs(v);
  if (abs >= 1_000_000_000) return `Rp ${decimal.format(v / 1_000_000_000)} M`;
  if (abs >= 1_000_000) return `Rp ${decimal.format(v / 1_000_000) } jt`;
  if (abs >= 10_000) return `Rp ${plain.format(Math.round(v / 1000))} rb`;
  return rupiah.format(v);
}

export const num = (value: number | null | undefined) => plain.format(value ?? 0);

export function qty(value: number | null | undefined): string {
  return `${decimal.format(value ?? 0)} kg`;
}

/* Semua waktu di aplikasi ini ditampilkan dalam zona waktu Indonesia Barat.
 * Zona ditulis eksplisit, bukan mengandalkan zona mesin/browser. Kalau tidak,
 * tanggal yang sama tampil berbeda 7 jam tergantung di mana console dibuka --
 * dan angka jam yang salah pada daftar audit atau jadwal broadcast berarti
 * keputusan yang salah, bukan sekadar tampilan yang beda. */
export const ZONA_TAMPIL = "Asia/Jakarta";

const WIB = "WIB";

/* Tanggal polos "2026-12-31" bukan momen waktu, tapi kalender: artinya "batas
 * akhir paket pada tanggal itu", bukan "tengah malam tanggal itu". Menambah
 * suffix Z akan menggesernya ke tanggal berikutnya atau sebelumnya tergantung
 * zona, jadi tanggal polos dibaca sebagai kalender murni, tanpa konversi. */
function isDateOnly(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

/* Backend mengirim UTC eksplisit (suffix Z). String tanpa offset masih bisa
 * muncul dari data lama atau input lain, dan `new Date("2026-09-28T10:00:00")`
 * dibaca JavaScript sebagai waktu LOKAL browser -- salah satu sumber selisih
 * 7 jam. Diasumsikan UTC agar konsisten dengan isi kolom database. */
function parseInstant(value: string): Date | null {
  const raw = value.trim();
  if (!raw) return null;
  const hasZone = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(raw);
  const d = new Date(hasZone ? raw : `${raw}Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}

export function dateShort(value: string | null | undefined): string {
  if (!value) return "-";
  if (isDateOnly(value)) {
    const [y, m, d] = value.split("-");
    return `${d}/${m}/${y}`;
  }
  const d = parseInstant(value);
  if (!d) return "-";
  return d.toLocaleDateString("id-ID", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    timeZone: ZONA_TAMPIL,
  });
}

export function dateTime(value: string | null | undefined): string {
  if (!value) return "-";
  const d = parseInstant(value);
  if (!d) return "-";
  const teks = d.toLocaleString("id-ID", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: ZONA_TAMPIL,
  });
  return `${teks} ${WIB}`;
}

/* "3 jam lalu". Pesan ini menjawab "kapan", bukan "jam berapa", jadi untuk
 * data lama dipakai tanggal penuh. */
export function relative(value: string | null | undefined): string {
  if (!value) return "belum pernah";
  const d = parseInstant(value);
  if (!d) return "-";

  const diffMs = Date.now() - d.getTime();
  const mins = Math.round(diffMs / 60000);
  if (mins < 1) return "baru saja";
  if (mins < 60) return `${mins} menit lalu`;

  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} jam lalu`;

  const days = Math.round(hours / 24);
  if (days < 30) return `${days} hari lalu`;
  return dateShort(value);
}

/* --- Konversi input datetime-local -------------------------------------- */

/* <input type="datetime-local"> menyimpan "YYYY-MM-DDTHH:mm" TANPA zona, dan
 * browser menafsirkannya sebagai waktu lokal mesin. `new Date(nilai).toISOString()`
 * lalu mengonversi sebagai waktu lokal -- benar hanya kalau zona browser
 * kebetulan Jakarta.
 *
 * Fungsi di bawah memperlakukan angka yang diketik admin sebagai WIB, apa pun
 * zona mesinnya. Ini yang membuat "23:30" selalu berarti 23:30 WIB, sehingga
 * broadcast benar-benar tayang pukul 23:30 WIB. */
const WIB_OFFSET_MIN = 7 * 60;

function partsToUtcIso(localValue: string): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(localValue.trim());
  if (!m) return null;
  const [, y, mo, d, h, mi] = m;
  const asUtc = Date.UTC(+y, +mo - 1, +d, +h, +mi - WIB_OFFSET_MIN, 0);
  const dt = new Date(asUtc);
  if (Number.isNaN(dt.getTime())) return null;
  return dt.toISOString();
}

/* Nilai datetime-local untuk <input>, selalu dalam WIB. */
export function instantToLocalInput(value: string | null | undefined): string {
  if (!value) return "";
  if (isDateOnly(value)) return value;
  const d = parseInstant(value);
  if (!d) return "";
  const parts = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZone: ZONA_TAMPIL,
  }).formatToParts(d);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "00";
  /* en-CA bisa menghasilkan hour "24" untuk tengah malam pada sebagian
   * runtime Intl. 24:00 bukan input yang valid, jadi dibulatkan ke 00. */
  const hour = get("hour") === "24" ? "00" : get("hour");
  return `${get("year")}-${get("month")}-${get("day")}T${hour}:${get("minute")}`;
}

/* Input datetime-local -> ISO UTC untuk dikirim ke backend. */
export function localInputToIsoUtc(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (isDateOnly(trimmed)) return `${trimmed}T00:00:00.000Z`;
  return partsToUtcIso(trimmed);
}

/* Tanggal polos untuk input type="date": kalender, tanpa zona. */
export function dateInputToIsoDate(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return isDateOnly(trimmed) ? trimmed : trimmed.slice(0, 10);
}

export function planLabel(plan: string): string {
  return (
    {
      TRIAL: "Uji coba",
      BASIC: "Dasar",
      PRO: "Pro",
      UNLIMITED: "Tak terbatas",
    }[plan] ?? plan
  );
}

export function healthLabel(health: string): { text: string; tone: string } {
  return (
    {
      OK: { text: "Sehat", tone: "ok" },
      STALE: { text: "Jarang sinkron", tone: "warn" },
      DEAD: { text: "Tidak aktif", tone: "bad" },
    }[health] ?? { text: health, tone: "muted" }
  );
}

export function statusLabel(status: string): { text: string; tone: string } {
  return (
    {
      ACTIVE: { text: "Aktif", tone: "ok" },
      SUSPENDED: { text: "Ditangguhkan", tone: "bad" },
      EXPIRED: { text: "Kedaluwarsa", tone: "bad" },
    }[status] ?? { text: status, tone: "muted" }
  );
}

export function roleLabel(role: string): string {
  return { OWNER: "Owner", BOS: "BOS", KARYAWAN: "Karyawan" }[role] ?? role;
}
