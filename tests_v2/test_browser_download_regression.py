#!/usr/bin/env python3
"""Regression: real browser downloads save files on the active engine path."""

import os
import shutil
import sys
import tempfile
import time
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError


SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")
DOWNLOAD_DIR = os.environ.get("CMUX_UI_TEST_BROWSER_DOWNLOAD_DIR", "").strip()
EXPECTED_FILENAME = "cmux-browser-download.txt"
EXPECTED_BODY = "downloaded-via-browser"


def _must(cond: bool, msg: str) -> None:
    if not cond:
        raise cmuxError(msg)


def main() -> int:
    _must(bool(DOWNLOAD_DIR), "CMUX_UI_TEST_BROWSER_DOWNLOAD_DIR must be set")

    download_dir = Path(DOWNLOAD_DIR)
    if download_dir.exists():
        shutil.rmtree(download_dir)
    download_dir.mkdir(parents=True, exist_ok=True)

    expected_path = download_dir / EXPECTED_FILENAME

    html = f"""
<!doctype html>
<html>
  <head><title>cmux-browser-download</title></head>
  <body>
    <a id="download"
       href="data:text/plain;charset=utf-8,{urllib.parse.quote(EXPECTED_BODY)}"
       download="{EXPECTED_FILENAME}">Download</a>
  </body>
</html>
""".strip()
    data_url = "data:text/html," + urllib.parse.quote(html)

    with cmux(SOCKET_PATH) as c:
        opened = c._call("browser.open_split", {"url": data_url}) or {}
        sid = str(opened.get("surface_id") or "")
        _must(bool(sid), f"browser.open_split returned no surface_id: {opened}")

        c._call("browser.wait", {"surface_id": sid, "selector": "#download", "timeout_ms": 5000})
        c._call("browser.click", {"surface_id": sid, "selector": "#download"})

        waited = c._call(
            "browser.download.wait",
            {"surface_id": sid, "path": str(expected_path), "timeout_ms": 15000},
        ) or {}
        _must(bool(waited.get("downloaded")) is True, f"browser.download.wait failed: {waited}")

        deadline = time.time() + 3.0
        while time.time() < deadline:
            if expected_path.exists() and expected_path.read_text(encoding="utf-8") == EXPECTED_BODY:
                break
            time.sleep(0.05)
        else:
            body = expected_path.read_text(encoding="utf-8") if expected_path.exists() else "<missing>"
            raise cmuxError(f"downloaded file mismatch at {expected_path}: {body!r}")

    print(f"PASS: browser download saved {expected_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
