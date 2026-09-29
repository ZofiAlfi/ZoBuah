"""Audit to_dict(): tangkap dict entry yang key-nya bukan string literal.

Kelas bug: "created_at": iso_utc(self.created_at) yang kutipnya hilang
menjadi created_at: iso_utc(...). Itu NAMPAK valid bagi py_compile dan
ast.parse karena `name: value` memang sintaks dict yang sah -- tapi
saat to_dict() dipanggil, Python mencari variabel bernama `created_at`
dan melempar NameError. Uji kompilasi tidak akan pernah menangkapnya.
"""
import ast
import pathlib
import sys

MODELS = pathlib.Path("app/models")
SCAN_ROOTS = (MODELS, pathlib.Path("app/routes"), pathlib.Path("app/schemas"))


def audit(path: pathlib.Path):
    problems = []
    tree = ast.parse(path.read_text(encoding="utf-8"), str(path))

    for node in ast.walk(tree):
        if not isinstance(node, ast.Dict):
            continue
        for key in node.keys:
            if key is None:
                continue  # **spread
            if isinstance(key, ast.Constant) and isinstance(key.value, str):
                continue  # key string literal, benar
            if isinstance(key, (ast.Constant, ast.Str)):
                continue
            problems.append((key.lineno, ast.dump(key)[:70]))

    return problems


def main() -> int:
    total = 0
    scanned = 0
    for root in SCAN_ROOTS:
        if not root.is_dir():
            continue
        for path in sorted(root.glob("*.py")):
            scanned += 1
            for lineno, dumped in audit(path):
                total += 1
                print("  %s:%d  key bukan string -> %s" % (path, lineno, dumped))
    print("file dipindai:", scanned)
    if total:
        print("TOTAL key rusak:", total)
        return 1
    print("Audit bersih: semua key dict adalah string literal.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
