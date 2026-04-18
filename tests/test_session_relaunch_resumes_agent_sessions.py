#!/usr/bin/env python3
"""
Regression: normal relaunch should resume saved Claude/Codex sessions.

Repro for issue #2923:
1) Launch cmux and seed workspaces with tracked Claude/Codex sessions.
2) Quit the app normally so the session snapshot is saved.
3) Relaunch cmux the next day.
4) Verify the restored panels automatically run the saved resume commands.
"""

from __future__ import annotations

import json
import os
import plistlib
import re
import socket
import subprocess
import tempfile
import time
from pathlib import Path

from cmux import cmux


def _bundle_id(app_path: Path) -> str:
    info_path = app_path / "Contents" / "Info.plist"
    if not info_path.exists():
        raise RuntimeError(f"Missing Info.plist at {info_path}")
    with info_path.open("rb") as f:
        info = plistlib.load(f)
    bundle_id = str(info.get("CFBundleIdentifier", "")).strip()
    if not bundle_id:
        raise RuntimeError("Missing CFBundleIdentifier")
    return bundle_id


def _snapshot_path(bundle_id: str, suffix: str = "") -> Path:
    safe_bundle = re.sub(r"[^A-Za-z0-9._-]", "_", bundle_id)
    return Path.home() / "Library/Application Support/cmux" / f"session-{safe_bundle}{suffix}.json"


def _socket_reachable(socket_path: Path) -> bool:
    if not socket_path.exists():
        return False
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.settimeout(0.3)
        sock.connect(str(socket_path))
        sock.sendall(b"ping\n")
        data = sock.recv(1024)
        return b"PONG" in data
    except OSError:
        return False
    finally:
        sock.close()


def _wait_for_socket(socket_path: Path, timeout: float = 20.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if _socket_reachable(socket_path):
            return
        time.sleep(0.2)
    raise RuntimeError(f"Socket did not become reachable: {socket_path}")


def _wait_for_socket_closed(socket_path: Path, timeout: float = 20.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not _socket_reachable(socket_path):
            return
        time.sleep(0.2)
    raise RuntimeError(f"Socket still reachable after quit: {socket_path}")


def _kill_existing(app_path: Path) -> None:
    exe = app_path / "Contents" / "MacOS" / "cmux DEV"
    subprocess.run(["pkill", "-f", str(exe)], capture_output=True, text=True)
    time.sleep(1.0)


def _launch(app_path: Path, socket_path: Path, env_overrides: dict[str, str] | None = None) -> None:
    try:
        socket_path.unlink()
    except FileNotFoundError:
        pass

    command = ["open", "-na", str(app_path)]
    full_env = dict(env_overrides or {})
    full_env["CMUX_SOCKET_PATH"] = str(socket_path)
    full_env["CMUX_ALLOW_SOCKET_OVERRIDE"] = "1"
    for key, value in full_env.items():
        command.extend(["--env", f"{key}={value}"])
    subprocess.run(command, check=True)
    _wait_for_socket(socket_path)
    time.sleep(1.5)


def _quit(bundle_id: str, socket_path: Path) -> None:
    subprocess.run(
        ["osascript", "-e", f'tell application id "{bundle_id}" to quit'],
        capture_output=True,
        text=True,
        check=True,
    )
    _wait_for_socket_closed(socket_path)
    try:
        socket_path.unlink()
    except FileNotFoundError:
        pass
    time.sleep(0.8)


def _connect(socket_path: Path) -> cmux:
    client = cmux(socket_path=str(socket_path))
    client.connect()
    if not client.ping():
        raise RuntimeError("ping failed")
    return client


def _read_scrollback(client: cmux) -> str:
    return client._send_command("read_screen --scrollback")


def _wait_for_condition(timeout: float, predicate) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.25)
    return False


def _write_fake_agent(fake_bin_dir: Path, binary_name: str, prefix: str) -> None:
    fake_bin_dir.mkdir(parents=True, exist_ok=True)
    fake_binary = fake_bin_dir / binary_name
    fake_binary.write_text(
        "#!/bin/sh\n"
        f"printf '{prefix}:%s\\n' \"$*\"\n",
        encoding="utf-8",
    )
    fake_binary.chmod(0o755)


def _write_hook_state(path: Path, session_id: str, workspace_id: str, surface_id: str, cwd: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": 1,
        "sessions": {
            session_id: {
                "sessionId": session_id,
                "workspaceId": workspace_id,
                "surfaceId": surface_id,
                "cwd": cwd,
                "updatedAt": time.time(),
            }
        },
    }
    path.write_text(json.dumps(payload), encoding="utf-8")


def main() -> int:
    app_path_str = os.environ.get("CMUX_APP_PATH", "").strip()
    if not app_path_str:
        print("SKIP: set CMUX_APP_PATH to a built cmux DEV .app path")
        return 0
    app_path = Path(app_path_str)
    if not app_path.exists():
        print(f"SKIP: CMUX_APP_PATH does not exist: {app_path}")
        return 0

    bundle_id = _bundle_id(app_path)
    socket_path = Path(f"/tmp/cmux-session-relaunch-agents-{bundle_id.replace('.', '-')}.sock")
    snapshot = _snapshot_path(bundle_id)
    previous_snapshot = _snapshot_path(bundle_id, suffix="-previous")
    codex_hook_state = Path.home() / ".cmuxterm" / "codex-hook-sessions.json"
    claude_hook_state = Path.home() / ".cmuxterm" / "claude-hook-sessions.json"

    codex_expected = "CMUX_FAKE_CODEX_RESUME:resume codex-session-relaunch-2923"
    claude_expected = "CMUX_FAKE_CLAUDE_RESUME:--resume claude-session-relaunch-2923"

    failures: list[str] = []

    with tempfile.TemporaryDirectory(prefix="cmux-session-relaunch-agents-") as td:
        fake_bin_dir = Path(td) / "bin"
        _write_fake_agent(fake_bin_dir, "codex", "CMUX_FAKE_CODEX_RESUME")
        _write_fake_agent(fake_bin_dir, "claude", "CMUX_FAKE_CLAUDE_RESUME")
        launch_path = f"{fake_bin_dir}:{os.environ.get('PATH', '')}"

        _kill_existing(app_path)
        snapshot.unlink(missing_ok=True)
        previous_snapshot.unlink(missing_ok=True)
        codex_hook_state.unlink(missing_ok=True)
        claude_hook_state.unlink(missing_ok=True)

        try:
            _launch(app_path, socket_path, env_overrides={"PATH": launch_path})
            client = _connect(socket_path)
            try:
                codex_workspace_id = client.current_workspace()
                codex_surfaces = client.list_surfaces()
                if not codex_surfaces:
                    failures.append("expected a Codex workspace surface during setup")
                else:
                    _write_hook_state(
                        codex_hook_state,
                        session_id="codex-session-relaunch-2923",
                        workspace_id=codex_workspace_id,
                        surface_id=codex_surfaces[0][1],
                        cwd=os.getcwd(),
                    )

                claude_workspace_id = client.new_workspace()
                time.sleep(0.4)
                client.select_workspace(claude_workspace_id)
                time.sleep(0.4)
                claude_surfaces = client.list_surfaces()
                if not claude_surfaces:
                    failures.append("expected a Claude workspace surface during setup")
                else:
                    _write_hook_state(
                        claude_hook_state,
                        session_id="claude-session-relaunch-2923",
                        workspace_id=claude_workspace_id,
                        surface_id=claude_surfaces[0][1],
                        cwd=os.getcwd(),
                    )

                client.select_workspace(codex_workspace_id)
                time.sleep(0.4)
            finally:
                client.close()
            _quit(bundle_id, socket_path)

            # Prove the relaunch uses the persisted cmux snapshot, not the live hook files.
            codex_hook_state.unlink(missing_ok=True)
            claude_hook_state.unlink(missing_ok=True)

            _launch(app_path, socket_path, env_overrides={"PATH": launch_path})
            client = _connect(socket_path)
            try:
                workspaces = client.list_workspaces()
                if len(workspaces) < 2:
                    failures.append(f"expected >=2 restored workspaces after relaunch, got {len(workspaces)}")

                def workspace_contains(index: int, expected: str) -> bool:
                    if len(client.list_workspaces()) <= index:
                        return False
                    client.select_workspace(index)
                    return expected in _read_scrollback(client)

                if not _wait_for_condition(12.0, lambda: workspace_contains(0, codex_expected)):
                    client.select_workspace(0)
                    scrollback_tail = "\n".join(_read_scrollback(client).splitlines()[-20:])
                    failures.append(
                        "normal relaunch did not resume the saved Codex session; "
                        f"tail:\n{scrollback_tail}"
                    )

                if not _wait_for_condition(12.0, lambda: workspace_contains(1, claude_expected)):
                    client.select_workspace(1)
                    scrollback_tail = "\n".join(_read_scrollback(client).splitlines()[-20:])
                    failures.append(
                        "normal relaunch did not resume the saved Claude session; "
                        f"tail:\n{scrollback_tail}"
                    )
            finally:
                client.close()
            _quit(bundle_id, socket_path)
        finally:
            _kill_existing(app_path)
            socket_path.unlink(missing_ok=True)
            snapshot.unlink(missing_ok=True)
            previous_snapshot.unlink(missing_ok=True)
            codex_hook_state.unlink(missing_ok=True)
            claude_hook_state.unlink(missing_ok=True)

    if failures:
        print("FAIL:")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("PASS: normal relaunch resumes saved Claude and Codex sessions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
