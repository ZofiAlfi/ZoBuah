"""Health check API ZoBuah -- uptime monitor buatan sendiri (tanpa UptimeRobot).

Dijalankan tiap 10 menit lewat Windows Task Scheduler
(lihat install_uptime_cron.ps1). Juga bisa dipakai di GitHub Actions
(cron */10 * * * *) atau manual.

Pemakaian:
    python deploy/health_check.py [url] [--log path]

Exit code: 0 = sehat, 1 = bermasalah.
Setiap hasil di-append ke file log (~/.zobuah_uptime.log default).
"""

import os
import sys
import time
import urllib.request

DEFAULT_URL = "https://zobuah.onrender.com/health"
DEFAULT_LOG = os.path.join(os.path.expanduser("~"), ".zobuah_uptime.log")


def check(url: str, timeout: int = 30) -> tuple[int, str]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            status = resp.status
            body = resp.read().decode("utf-8", "replace")
        healthy = status == 200 and '"ok"' in body
        return (0 if healthy else 1, f"HTTP {status} {body[:80]}")
    except Exception as e:
        return (1, f"ERROR {e}")


def main(argv: list[str]) -> int:
    log_path = DEFAULT_LOG
    if "--log" in argv:
        idx = argv.index("--log")
        if idx + 1 < len(argv):
            log_path = argv[idx + 1]
    url_args = [a for a in argv if not a.startswith("--") and a != log_path]
    url = url_args[0] if url_args else DEFAULT_URL

    code, detail = check(url)
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"{stamp} [{'FAIL' if code else 'OK  '}] {url} {detail}"
    print(line)

    try:
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))