#!/usr/bin/env python3
"""Regression: packaged CEF runtime must pass strict codesign verification."""

from __future__ import annotations

import glob
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmuxError


def _must(cond: bool, msg: str) -> None:
    if not cond:
        raise cmuxError(msg)


def _run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        merged = f"{proc.stdout}\n{proc.stderr}".strip()
        raise cmuxError(f"Command failed ({' '.join(cmd)}): {merged}")
    return proc


def _find_app() -> Path:
    env_app = os.environ.get("CMUX_APP_BUNDLE", "").strip()
    if env_app:
        app = Path(env_app)
        if app.is_dir():
            return app
        raise cmuxError(f"CMUX_APP_BUNDLE does not exist: {env_app}")

    candidates = [
        Path(path)
        for path in glob.glob("/tmp/cmux-*/Build/Products/Debug/cmux DEV*.app")
        if Path(path).is_dir()
    ]
    if not candidates:
        raise cmuxError("Could not locate built cmux app bundle; set CMUX_APP_BUNDLE")
    candidates.sort(key=lambda item: item.stat().st_mtime, reverse=True)
    return candidates[0]


def _codesign_identifier(path: Path) -> str:
    proc = _run(["codesign", "-dv", "--verbose=2", str(path)])
    for line in proc.stderr.splitlines():
        if line.startswith("Identifier="):
            return line.split("=", 1)[1].strip()
    raise cmuxError(f"codesign output missing Identifier for {path}")


def main() -> int:
    app = _find_app()
    frameworks_dir = app / "Contents" / "Frameworks"
    cef_framework = frameworks_dir / "Chromium Embedded Framework.framework"
    helpers = sorted(frameworks_dir.glob("*Helper*.app"))

    _must(cef_framework.is_dir(), f"Missing packaged CEF framework: {cef_framework}")
    _must(helpers, f"Missing packaged CEF helpers in {frameworks_dir}")

    _run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])

    cef_identifier = _codesign_identifier(cef_framework)
    _must(cef_identifier == "org.cef.framework", f"Unexpected CEF framework identifier: {cef_identifier}")

    helper_identifiers = {helper.name: _codesign_identifier(helper) for helper in helpers}
    _must(
        helper_identifiers.get("cmux DEV Helper.app") == "com.cmuxterm.app.debug.helper",
        f"Unexpected helper identifier map: {helper_identifiers}",
    )
    _must(
        helper_identifiers.get("cmux DEV Helper (Renderer).app") == "com.cmuxterm.app.debug.helper.renderer",
        f"Unexpected helper identifier map: {helper_identifiers}",
    )
    _must(
        helper_identifiers.get("cmux DEV Helper (Plugin).app") == "com.cmuxterm.app.debug.helper.plugin",
        f"Unexpected helper identifier map: {helper_identifiers}",
    )
    _must(
        helper_identifiers.get("cmux DEV Helper (Alerts).app") == "com.cmuxterm.app.debug.helper.alerts",
        f"Unexpected helper identifier map: {helper_identifiers}",
    )

    print(f"PASS: packaged CEF runtime signs cleanly in {app}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
