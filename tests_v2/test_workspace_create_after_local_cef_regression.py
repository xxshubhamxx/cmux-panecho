#!/usr/bin/env python3
"""Regression: warming a local CEF browser must not hang workspace.create."""

from __future__ import annotations

import base64
import glob
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError


SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def _must(cond: bool, msg: str) -> None:
    if not cond:
        raise cmuxError(msg)


def _run(cmd: list[str], *, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env, check=False)
    if check and proc.returncode != 0:
        merged = f"{proc.stdout}\n{proc.stderr}".strip()
        raise cmuxError(f"Command failed ({' '.join(cmd)}): {merged}")
    return proc


def _find_cli_binary() -> str:
    env_cli = os.environ.get("CMUXTERM_CLI")
    if env_cli and os.path.isfile(env_cli) and os.access(env_cli, os.X_OK):
        return env_cli

    candidates = glob.glob(os.path.expanduser("~/Library/Developer/Xcode/DerivedData/**/Build/Products/Debug/cmux"), recursive=True)
    candidates += glob.glob("/tmp/cmux-*/Build/Products/Debug/cmux")
    candidates = [p for p in candidates if os.path.isfile(p) and os.access(p, os.X_OK)]
    if not candidates:
        raise cmuxError("Could not locate cmux CLI binary; set CMUXTERM_CLI")
    candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return candidates[0]


def _run_cli(cli: str, args: list[str]) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    env.pop("CMUX_WORKSPACE_ID", None)
    env.pop("CMUX_SURFACE_ID", None)
    env.pop("CMUX_TAB_ID", None)
    return _run([cli, "--socket", SOCKET_PATH, "--json", *args], env=env)


def _wait_browser_eval_contains(client: cmux, surface_id: str, token: str, timeout_s: float = 20.0) -> None:
    deadline = time.time() + timeout_s
    last = {}
    while time.time() < deadline:
        try:
            last = client._call(
                "browser.eval",
                {"surface_id": surface_id, "script": "document.body ? (document.body.innerText || '') : ''"},
            ) or {}
        except cmuxError as exc:
            if "CEF browser is not ready" not in str(exc):
                raise
            last = {"error": str(exc)}
        if token in str(last.get("value") or ""):
            return
        time.sleep(0.2)
    raise cmuxError(f"Timed out waiting for local browser token {token!r}: {last}")


def main() -> int:
    cli = _find_cli_binary()
    token = f"CMUX_CEF_WORKSPACE_CREATE_{int(time.time() * 1000)}"
    title = f"CEF Warmup {token}"
    html = (
        "<!doctype html><html><head>"
        f"<title>{title}</title>"
        "</head><body>"
        f"<h1>{title}</h1><p id='token'>{token}</p>"
        "</body></html>"
    )
    data_url = "data:text/html;base64," + base64.b64encode(html.encode("utf-8")).decode("ascii")

    with cmux(SOCKET_PATH) as client:
        before_workspace_ids = {wid for _index, wid, _title, _focused in client.list_workspaces()}
        opened = client._call("browser.open_split", {"url": data_url}) or {}
        browser_surface_id = str(opened.get("surface_id") or "")
        _must(bool(browser_surface_id), f"browser.open_split returned no surface_id: {opened}")
        _wait_browser_eval_contains(client, browser_surface_id, token, timeout_s=20.0)

        started_at = time.monotonic()
        created = _run_cli(cli, ["new-workspace", "--cwd", "/tmp"])
        elapsed_s = time.monotonic() - started_at

        _must(elapsed_s < 12.0, f"new-workspace took too long after CEF warmup: {elapsed_s:.2f}s")

        after_workspace_ids = {wid for _index, wid, _title, _focused in client.list_workspaces()}
        new_workspace_ids = sorted(after_workspace_ids - before_workspace_ids)
        _must(len(new_workspace_ids) == 1, f"expected exactly one new workspace after CLI create: stdout={created.stdout!r} list={sorted(after_workspace_ids)}")
        _workspace_id = new_workspace_ids[0]

    print(f"PASS: local CEF warmup did not block new-workspace ({elapsed_s:.2f}s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
