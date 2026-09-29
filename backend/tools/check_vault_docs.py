"""Periksa dokumen vault untuk teks yang rusak.

Beberapa sesi kerja, teks yang ditulis ke vault sempat rusak: kata Indonesia
menempel kata Inggris (melesetExtent, memakaiketiga), kata Inggris menggantikan
kata Indonesia (actuality), dan karakter hasil encoding rusak. Semuanya lolos
dari pemeriksaan mata kalau tidak dibaca per kata.

Aturan: buang dulu blok kode (```...``` dan `...`) dan frontmatter link, baru
cari camelCase di teks naratif. Kode_identifier yang sah hanya boleh muncul di
dalam backtick.

Jalankan dari folder backend:
    venv/Scripts/python.exe tools/check_vault_docs.py
"""
import pathlib
import re
import sys

VAULT = pathlib.Path(r"C:\Users\user\Documents\ZOAI\Zofi AI")

TARGETS = [
    VAULT / "04-Bugs" / "Bug-Delete-Produk-Tidak-Sampai-Ke-HP" / "README.md",
    VAULT / "04-Bugs" / "Bug-Jam-Salah-Zona-Server-Render" / "README.md",
    VAULT / "04-Bugs" / "Bug-Keranjang-Tidak-Bisa-Hapus-Satu-Item" / "README.md",
    VAULT / "01-Projects" / "ZoBuah" / "08-Troubleshooting.md",
    VAULT / "01-Projects" / "ZoBuah" / "12-Owner-Console.md",
    VAULT / "01-Projects" / "ZoBuah" / "03-Database-Schema.md",
    VAULT / "01-Projects" / "ZoBuah" / "04-API-Endpoints.md",
    VAULT / "01-Projects" / "ZoBuah" / "00-Ringkasan.md",
    VAULT / "04-Bugs" / "README.md",
]

# Simbol non-ASCII yang sah dipakai di dokumen. Termasuk box-drawing untuk
# diagram ASCII-art.
SIMBOL_SAH = set("—–·×→←±°≥≤≠↔•’‘“”…│├└▼▲◄─═🔓🔐✅⚠️❌📌")

# Kata asing yang pernah bocor masuk.
KATA_ASING = [
    "actuality",
    "Toblig",
    "Amplier",
    "Coomees",
    "Extenn",
    "ramping",
    "amplifying",
    "edgeparsing",
    "Nem",
    "Jadineither",
    "IniTrade",
]


def buang_kode(teks: str) -> str:
    teks = re.sub(r"```.*?```", " ", teks, flags=re.S)
    teks = re.sub(r"`[^`]*`", " ", teks)
    return teks


# Nama yang memang camelCase dan sah muncul di narasi.
CAMEL_SAH = {
    "primaryDark", "primaryLight", "textPrimary", "textSecondary",
    "instantToLocalInput", "localInputToIsoUtc", "dateInputToIsoDate",
}


def cek(path: pathlib.Path):
    masalah = []
    if not path.exists():
        return ["file tidak ada: %s" % path]

    mentah = path.read_text(encoding="utf-8-sig")
    for i, ln in enumerate(mentah.splitlines(), 1):
        for ch in ln:
            if ord(ch) > 127 and ch not in SIMBOL_SAH:
                masalah.append("%d: karakter aneh U+%04X (%s)" % (i, ord(ch), ch))
                break

    narasi = buang_kode(mentah)

    for i, ln in enumerate(narasi.splitlines(), 1):
        for kata in KATA_ASING:
            if re.search(r"\b%s\b" % re.escape(kata), ln, flags=re.I):
                masalah.append("%d: kata asing %r" % (i, kata))
        # camelCase di luar blok kode = kata menempel yang rusak
        for m in re.finditer(r"\b[a-z]{2,}[A-Z][A-Za-z]{2,}\b", ln):
            if m.group() not in CAMEL_SAH:
                masalah.append("%d: kata menempel %r" % (i, m.group()))
        # kata Indonesia menempel tanda titik + kata Inggris ("di.edgeparsing")
        for m in re.finditer(r"\bdi\.[a-z]{4,}", ln):
            masalah.append("%d: frasa rusak %r" % (i, m.group()))
        # teks yang belum sempat dirapikan
        if "\ufffd" in ln:
            masalah.append("%d: replacement char" % i)
        if "???" in ln:
            masalah.append("%d: '???'" % i)
    return masalah


def main() -> int:
    total = 0
    for t in TARGETS:
        m = cek(t)
        if m:
            print("== %s" % t.name)
            for x in m:
                print("   " + x)
            total += len(m)
    print()
    print("BERSIH" if total == 0 else "%d MASALAH" % total)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
