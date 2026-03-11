#!/usr/bin/env python3
"""Regression: SSH remote browser automation must unwrap CEF JS results correctly."""

from __future__ import annotations

import base64
import glob
import json
import os
import secrets
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError


SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")
SSH_HOST = os.environ.get("CMUX_SSH_TEST_HOST", "").strip()
SSH_PORT = os.environ.get("CMUX_SSH_TEST_PORT", "").strip()
SSH_IDENTITY = os.environ.get("CMUX_SSH_TEST_IDENTITY", "").strip()
SSH_OPTIONS_RAW = os.environ.get("CMUX_SSH_TEST_OPTIONS", "").strip()


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

    fixed = os.path.expanduser("~/Library/Developer/Xcode/DerivedData/cmux-tests-v2/Build/Products/Debug/cmux")
    if os.path.isfile(fixed) and os.access(fixed, os.X_OK):
        return fixed

    candidates = glob.glob(os.path.expanduser("~/Library/Developer/Xcode/DerivedData/**/Build/Products/Debug/cmux"), recursive=True)
    candidates += glob.glob("/tmp/cmux-*/Build/Products/Debug/cmux")
    candidates = [p for p in candidates if os.path.isfile(p) and os.access(p, os.X_OK)]
    if not candidates:
        raise cmuxError("Could not locate cmux CLI binary; set CMUXTERM_CLI")
    candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return candidates[0]


def _run_cli_json(cli: str, args: list[str]) -> dict:
    env = dict(os.environ)
    env.pop("CMUX_WORKSPACE_ID", None)
    env.pop("CMUX_SURFACE_ID", None)
    env.pop("CMUX_TAB_ID", None)
    proc = _run([cli, "--socket", SOCKET_PATH, "--json", *args], env=env)
    try:
        return json.loads(proc.stdout or "{}")
    except Exception as exc:  # noqa: BLE001
        raise cmuxError(f"Invalid JSON output for {' '.join(args)}: {proc.stdout!r} ({exc})")


def _resolve_workspace_id(client: cmux, payload: dict, *, before_workspace_ids: set[str]) -> str:
    workspace_id = str(payload.get("workspace_id") or "")
    if workspace_id:
        return workspace_id

    workspace_ref = str(payload.get("workspace_ref") or "")
    deadline = time.time() + 30.0
    last_error = ""
    while time.time() < deadline:
        try:
            if workspace_ref.startswith("workspace:"):
                listed = client._call("workspace.list", {}, timeout_s=30.0) or {}
                for row in listed.get("workspaces") or []:
                    if str(row.get("ref") or "") == workspace_ref:
                        resolved = str(row.get("id") or "")
                        if resolved:
                            return resolved

            current = {wid for _index, wid, _title, _focused in client.list_workspaces()}
            new_ids = sorted(current - before_workspace_ids)
            if len(new_ids) == 1:
                return new_ids[0]
        except cmuxError as exc:
            last_error = str(exc)
        time.sleep(0.25)

    if last_error:
        raise cmuxError(f"Unable to resolve workspace_id from payload: {payload} ({last_error})")
    raise cmuxError(f"Unable to resolve workspace_id from payload: {payload}")


def _wait_remote_ready(client: cmux, workspace_id: str, timeout_s: float = 65.0) -> dict:
    deadline = time.time() + timeout_s
    last = {}
    while time.time() < deadline:
        last = client._call("workspace.remote.status", {"workspace_id": workspace_id}) or {}
        remote = last.get("remote") or {}
        daemon = remote.get("daemon") or {}
        proxy = remote.get("proxy") or {}
        if (
            str(remote.get("state") or "") == "connected"
            and str(daemon.get("state") or "") == "ready"
            and str(proxy.get("state") or "") == "ready"
        ):
            return last
        time.sleep(0.25)
    raise cmuxError(f"Remote did not reach ready state: {last}")


def _assert_workspace_socket_health(client: cmux, expected_workspace_id: str) -> None:
    current = client._call("workspace.current", {}, timeout_s=10.0) or {}
    current_id = str(current.get("workspace_id") or "")
    _must(current_id == expected_workspace_id, f"workspace.current mismatch after ssh handoff: {current}")

    listed = client._call("workspace.list", {}, timeout_s=10.0) or {}
    rows = listed.get("workspaces") or []
    row = next((item for item in rows if str(item.get("id") or "") == expected_workspace_id), None)
    _must(row is not None, f"workspace.list missing remote workspace after ssh handoff: {listed}")


def _surface_scrollback_text(client: cmux, workspace_id: str, surface_id: str) -> str:
    payload = client._call(
        "surface.read_text",
        {"workspace_id": workspace_id, "surface_id": surface_id, "scrollback": True},
    ) or {}
    return str(payload.get("text") or "")


def _wait_surface_contains(client: cmux, workspace_id: str, surface_id: str, token: str, timeout_s: float = 15.0) -> None:
    deadline = time.time() + timeout_s
    last = ""
    while time.time() < deadline:
        last = _surface_scrollback_text(client, workspace_id, surface_id)
        if token in last:
            return
        time.sleep(0.2)
    raise cmuxError(f"Timed out waiting for remote terminal token {token!r}: {last[-400:]!r}")


def _wait_browser_eval_contains(client: cmux, surface_id: str, token: str, timeout_s: float = 20.0) -> dict:
    deadline = time.time() + timeout_s
    last = {}
    while time.time() < deadline:
        last = client._call(
            "browser.eval",
            {
                "surface_id": surface_id,
                "script": "document.body ? (document.body.innerText || '') : ''",
            },
        ) or {}
        value = str(last.get("value") or "")
        if token in value:
            return last
        time.sleep(0.2)
    raise cmuxError(f"Timed out waiting for browser.eval body token {token!r}: {last}")


def _wait_browser_title(client: cmux, surface_id: str, expected: str, timeout_s: float = 20.0) -> dict:
    deadline = time.time() + timeout_s
    last = {}
    while time.time() < deadline:
        last = client._call("browser.get.title", {"surface_id": surface_id}) or {}
        if str(last.get("title") or "") == expected:
            return last
        time.sleep(0.2)
    raise cmuxError(f"Timed out waiting for browser title {expected!r}: {last}")


def _warm_local_browser(client: cmux, stamp: str) -> None:
    local_title = f"Local Browser Warmup {stamp}"
    local_token = f"CMUX_LOCAL_BROWSER_WARMUP_{stamp}"
    html = (
        "<!doctype html><html><head>"
        f"<title>{local_title}</title>"
        "</head><body>"
        f"<h1>{local_title}</h1><p id='token'>{local_token}</p>"
        "</body></html>"
    )
    data_url = "data:text/html;base64," + base64.b64encode(html.encode("utf-8")).decode("ascii")
    opened = client._call("browser.open_split", {"url": data_url}) or {}
    local_surface_id = str(opened.get("surface_id") or "")
    _must(bool(local_surface_id), f"local browser.open_split returned no surface_id: {opened}")

    title_payload = _wait_browser_title(client, local_surface_id, local_title, timeout_s=20.0)
    _must(str(title_payload.get("title") or "") == local_title, f"local browser title mismatch: {title_payload}")

    eval_payload = _wait_browser_eval_contains(client, local_surface_id, local_token, timeout_s=20.0)
    _must(local_token in str(eval_payload.get("value") or ""), f"local browser.eval body mismatch: {eval_payload}")

    screenshot = client._call("browser.screenshot", {"surface_id": local_surface_id}) or {}
    png_base64 = str(screenshot.get("png_base64") or "")
    _must(len(png_base64) > 100, f"local browser.screenshot missing image payload: {screenshot}")


def main() -> int:
    if not SSH_HOST:
        print("SKIP: set CMUX_SSH_TEST_HOST to run SSH remote browser eval/snapshot regression")
        return 0

    cli = _find_cli_binary()
    stamp = secrets.token_hex(4)
    remote_workspace_id = ""
    remote_surface_id = ""
    browser_surface_id = ""
    ready_token = f"CMUX_REMOTE_HTTP_READY_{stamp}"
    body_token = f"CMUX_REMOTE_BROWSER_BODY_{stamp}"
    page_title = f"Remote Browser {stamp}"
    web_port = int(os.environ.get("CMUX_SSH_TEST_WEB_PORT", str(21000 + (os.getpid() % 2000))))
    screenshot_out = Path(f"/tmp/cmux-ssh-remote-browser-{stamp}.png")

    try:
        with cmux(SOCKET_PATH) as client:
            _warm_local_browser(client, stamp)

            before_workspace_ids = {wid for _index, wid, _title, _focused in client.list_workspaces()}

            ssh_args = ["ssh", SSH_HOST, "--name", f"ssh-browser-eval-{stamp}"]
            if SSH_PORT:
                ssh_args.extend(["--port", SSH_PORT])
            if SSH_IDENTITY:
                ssh_args.extend(["--identity", SSH_IDENTITY])
            if SSH_OPTIONS_RAW:
                for option in SSH_OPTIONS_RAW.split(","):
                    trimmed = option.strip()
                    if trimmed:
                        ssh_args.extend(["--ssh-option", trimmed])

            payload = _run_cli_json(cli, ssh_args)
            remote_workspace_id = _resolve_workspace_id(client, payload, before_workspace_ids=before_workspace_ids)
            _wait_remote_ready(client, remote_workspace_id, timeout_s=70.0)
            _assert_workspace_socket_health(client, remote_workspace_id)

            surfaces = client.list_surfaces(remote_workspace_id)
            _must(bool(surfaces), f"remote workspace should expose a terminal surface: {remote_workspace_id}")
            remote_surface_id = str(surfaces[0][1])

            server_script = (
                "cat >/tmp/cmux-remote-browser-eval.html <<'EOF'\n"
                "<!doctype html><html><head>"
                f"<title>{page_title}</title>"
                "</head><body>"
                f"<h1>{page_title}</h1><p id='token'>{body_token}</p>"
                "</body></html>\n"
                "EOF\n"
                f"python3 -m http.server {web_port} --directory /tmp >/tmp/cmux-remote-browser-eval-{stamp}.log 2>&1 &\n"
                "for _ in $(seq 1 50); do "
                f"  if curl -fsS http://localhost:{web_port}/cmux-remote-browser-eval.html | grep -q {body_token}; then "
                f"    echo {ready_token}; "
                "    break; "
                "  fi; "
                "  sleep 0.2; "
                "done\n"
            )
            client._call(
                "surface.send_text",
                {"workspace_id": remote_workspace_id, "surface_id": remote_surface_id, "text": server_script},
            )
            client._call(
                "surface.send_key",
                {"workspace_id": remote_workspace_id, "surface_id": remote_surface_id, "key": "enter"},
            )
            _wait_surface_contains(client, remote_workspace_id, remote_surface_id, ready_token, timeout_s=14.0)

            opened = client._call(
                "browser.open_split",
                {
                    "workspace_id": remote_workspace_id,
                    "url": f"http://localhost:{web_port}/cmux-remote-browser-eval.html",
                },
            ) or {}
            browser_surface_id = str(opened.get("surface_id") or "")
            _must(bool(browser_surface_id), f"browser.open_split returned no surface_id: {opened}")

            title_payload = _wait_browser_title(client, browser_surface_id, page_title, timeout_s=20.0)
            _must(str(title_payload.get("title") or "") == page_title, f"browser title mismatch: {title_payload}")

            eval_payload = _wait_browser_eval_contains(client, browser_surface_id, body_token, timeout_s=20.0)
            _must(body_token in str(eval_payload.get("value") or ""), f"browser.eval body mismatch: {eval_payload}")

            get_text = client._call(
                "browser.get.text",
                {"surface_id": browser_surface_id, "selector": "#token"},
            ) or {}
            _must(str(get_text.get("value") or "") == body_token, f"browser.get.text token mismatch: {get_text}")

            snapshot = client._call(
                "browser.snapshot",
                {"surface_id": browser_surface_id, "interactive": False, "compact": True},
            ) or {}
            _must(str(snapshot.get("title") or "") == page_title, f"browser.snapshot title mismatch: {snapshot}")
            _must(body_token in str(((snapshot.get("page") or {}).get("text") or "")), f"browser.snapshot text missing token: {snapshot}")
            _must("ref=" in str(snapshot.get("snapshot") or ""), f"browser.snapshot should include element refs: {snapshot}")
            _must(str(snapshot.get("ready_state") or "") == "complete", f"browser.snapshot ready_state mismatch: {snapshot}")

            screenshot = client._call("browser.screenshot", {"surface_id": browser_surface_id}) or {}
            png_base64 = str(screenshot.get("png_base64") or "")
            _must(len(png_base64) > 100, f"browser.screenshot missing image payload: {screenshot}")
            screenshot_out.write_bytes(base64.b64decode(png_base64))
            _must(screenshot_out.stat().st_size > 1024, f"browser.screenshot wrote tiny image: {screenshot_out}")
            _assert_workspace_socket_health(client, remote_workspace_id)

            print(f"PASS: ssh remote browser eval/snapshot works for {SSH_HOST}")
            print(f"SCREENSHOT: {screenshot_out}")
            return 0
    finally:
        if remote_workspace_id and remote_surface_id:
            try:
                client = cmux(SOCKET_PATH)
                client.connect()
                client._call(
                    "surface.send_text",
                    {
                        "workspace_id": remote_workspace_id,
                        "surface_id": remote_surface_id,
                        "text": f"pkill -f 'http.server {web_port}' || true\n",
                    },
                )
                client._call(
                    "surface.send_key",
                    {"workspace_id": remote_workspace_id, "surface_id": remote_surface_id, "key": "enter"},
                )
                client.close()
            except Exception:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
