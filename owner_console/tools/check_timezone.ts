/* Uji zona waktu Owner Console dengan sengaja dijalankan di zona mesin yang
 * SALAH (mis. UTC-5 dan UTC+9), supaya ketergantungan pada zona browser
 * langsung terlihat. Kalau helper ini benar, hasilnya harus sama persis
 * di semua zona. */
import {
  dateShort,
  dateTime,
  instantToLocalInput,
  localInputToIsoUtc,
  dateInputToIsoDate,
} from "../src/lib/format.ts";

type Case = { nama: string; dapat: unknown; harap: string };

const fails: Case[] = [];

function cek(nama: string, dapat: unknown, harap: string) {
  if (dapat !== harap) {
    fails.push({ nama, dapat, harap });
  }
}

/* --- instantToLocalInput: UTC -> input datetime-local dalam WIB --- */
cek(
  "instantToLocalInput 16:51Z -> 23:51 WIB",
  instantToLocalInput("2026-09-28T16:51:18Z"),
  "2026-09-28T23:51",
);
cek(
  "instantToLocalInput tengah malam UTC -> 07:00 WIB",
  instantToLocalInput("2026-09-28T00:00:00Z"),
  "2026-09-28T07:00",
);
cek(
  "instantToLocalInput 17:00Z -> lewat tengah malam WIB (nasional)",
  instantToLocalInput("2026-09-28T17:00:00Z"),
  "2026-09-29T00:00",
);

/* --- localInputToIsoUtc: input WIB -> instant UTC (inti perbaikan) --- */
cek(
  "localInputToIsoUtc 23:30 WIB -> 16:30Z",
  localInputToIsoUtc("2026-09-28T23:30"),
  "2026-09-28T16:30:00.000Z",
);
cek(
  "localInputToIsoUtc 07:00 WIB -> 00:00Z",
  localInputToIsoUtc("2026-09-28T07:00"),
  "2026-09-28T00:00:00.000Z",
);
cek("localInputToIsoUtc kosong -> null", localInputToIsoUtc(""), null);
cek("localInputToIsoUtc null -> null", localInputToIsoUtc(null), null);

/* Putaran balik: WIB -> UTC -> WIB harus kembali ke nilai semula. */
for (const asli of [
  "2026-09-28T23:30",
  "2026-01-01T00:05",
  "2026-12-31T23:59",
  "2026-06-15T12:00",
]) {
  const iso = localInputToIsoUtc(asli)!;
  cek(`putaran balik ${asli}`, instantToLocalInput(iso), asli);
}

/* --- dateTime: selalu WIB, berapa pun zona mesin --- */
const waktu = dateTime("2026-09-28T16:51:18Z");
cek("dateTime 16:51Z tampil 23:51 WIB", waktu, "28 Sep 2026, 23.51 WIB");

/* --- dateShort --- */
cek("dateShort instant 16:51Z -> 28 Sep", dateShort("2026-09-28T16:51:18Z"), "28 Sep 2026");
/* Tanggal polos harus tetap tanggal itu, tidak bergeser sehari. */
cek("dateShort tanggal polos 31 Des", dateShort("2026-12-31"), "31/12/2026");
cek("dateShort tanggal polos 01 Jan", dateShort("2026-01-01"), "01/01/2026");
cek("dateShort kosong -> -", dateShort(""), "-");
cek("dateTime null -> -", dateTime(null), "-");

/* --- dateInputToIsoDate: kalender, tanpa konversi zona --- */
cek("dateInputToIsoDate polos", dateInputToIsoDate("2026-12-31"), "2026-12-31");
cek("dateInputToIsoDate kosong", dateInputToIsoDate(""), null);

const zonaMesin = Intl.DateTimeFormat().resolvedOptions().timeZone;
console.log(`zona mesin pengujian: ${zonaMesin}`);
console.log(`dateTime(16:51Z) = ${waktu}`);

if (fails.length) {
  console.log(`\nGAGAL ${fails.length}:`);
  for (const f of fails) {
    console.log(`  - ${f.nama}`);
    console.log(`      dapat: ${JSON.stringify(f.dapat)}`);
    console.log(`      harap: ${JSON.stringify(f.harap)}`);
  }
  process.exit(1);
}
console.log("LULUS: seluruh nilai waktu benar dan tidak bergantung zona mesin.");
