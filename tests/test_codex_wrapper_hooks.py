#!/usr/bin/env python3
"""
Regression tests for Resources/bin/codex wrapper exit reporting.
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_WRAPPER = ROOT / "Resources" / "bin" / "codex"


def make_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    return [line.rstrip("\n") for line in path.read_text(encoding="utf-8").splitlines()]


def run_wrapper(*, socket_state: str, argv: list[str], exit_code: int) -> tuple[int, list[str], list[str], dict | None, str]:
    with tempfile.TemporaryDirectory(prefix="cmux-codex-wrapper-test-") as td:
        tmp = Path(td)
        wrapper_dir = tmp / "wrapper-bin"
        real_dir = tmp / "real-bin"
        wrapper_dir.mkdir(parents=True, exist_ok=True)
        real_dir.mkdir(parents=True, exist_ok=True)

        wrapper = wrapper_dir / "codex"
        shutil.copy2(SOURCE_WRAPPER, wrapper)
        wrapper.chmod(0o755)

        real_args_log = tmp / "real-args.log"
        cmux_log = tmp / "cmux.log"
        cmux_stdin_log = tmp / "cmux-stdin.log"
        socket_path = str(tmp / "cmux.sock")

        make_executable(
            real_dir / "codex",
            """#!/usr/bin/env bash
set -euo pipefail
: > "$FAKE_REAL_ARGS_LOG"
for arg in "$@"; do
  printf '%s\\n' "$arg" >> "$FAKE_REAL_ARGS_LOG"
done
exit "${FAKE_REAL_EXIT_CODE:-0}"
""",
        )

        make_executable(
            wrapper_dir / "cmux",
            """#!/usr/bin/env bash
set -euo pipefail
stdin_payload=""
if [ ! -t 0 ]; then
  stdin_payload="$(cat)"
fi
printf '%s timeout=%s\\n' "$*" "${CMUXTERM_CLI_RESPONSE_TIMEOUT_SEC-__UNSET__}" >> "$FAKE_CMUX_LOG"
printf '%s\\n' "$stdin_payload" >> "$FAKE_CMUX_STDIN_LOG"
if [[ "${1:-}" == "--socket" ]]; then
  shift 2
fi
if [[ "${1:-}" == "ping" ]]; then
  if [[ "${FAKE_CMUX_PING_OK:-0}" == "1" ]]; then
    exit 0
  fi
  exit 1
fi
exit 0
""",
        )

        test_socket: socket.socket | None = None
        if socket_state in {"live", "stale"}:
            test_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            test_socket.bind(socket_path)

        env = os.environ.copy()
        env["PATH"] = f"{wrapper_dir}:{real_dir}:{env.get('PATH', '/usr/bin:/bin')}"
        env["CMUX_SURFACE_ID"] = "surface:test"
        env["CMUX_WORKSPACE_ID"] = "workspace:test"
        env["CMUX_SOCKET_PATH"] = socket_path
        env["FAKE_REAL_ARGS_LOG"] = str(real_args_log)
        env["FAKE_REAL_EXIT_CODE"] = str(exit_code)
        env["FAKE_CMUX_LOG"] = str(cmux_log)
        env["FAKE_CMUX_STDIN_LOG"] = str(cmux_stdin_log)
        env["FAKE_CMUX_PING_OK"] = "1" if socket_state == "live" else "0"

        try:
            proc = subprocess.run(
                ["codex", *argv],
                cwd=tmp,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
        finally:
            if test_socket is not None:
                test_socket.close()

        stdin_payload = None
        stdin_lines = [line for line in read_lines(cmux_stdin_log) if line]
        if stdin_lines:
            try:
                stdin_payload = json.loads(stdin_lines[-1])
            except json.JSONDecodeError:
                stdin_payload = None

        return (
            proc.returncode,
            read_lines(real_args_log),
            read_lines(cmux_log),
            stdin_payload,
            proc.stderr.strip(),
        )


def expect(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def test_live_socket_reports_clean_exit(failures: list[str]) -> None:
    code, real_argv, cmux_log, stdin_payload, stderr = run_wrapper(
        socket_state="live",
        argv=["--help"],
        exit_code=0,
    )
    expect(code == 0, f"clean exit: wrapper exited {code}: {stderr}", failures)
    expect(real_argv == ["--help"], f"clean exit: expected passthrough args, got {real_argv}", failures)
    expect(any(" ping" in line for line in cmux_log), f"clean exit: expected cmux ping, got {cmux_log}", failures)
    expect(
        any("codex-hook session-end" in line for line in cmux_log),
        f"clean exit: expected wrapper to report session-end, got {cmux_log}",
        failures,
    )
    expect(stdin_payload is not None, "clean exit: expected JSON payload on stdin", failures)
    if stdin_payload is not None:
        expect(stdin_payload.get("exit_status") == "0", f"clean exit: expected exit_status 0 payload, got {stdin_payload}", failures)
        expect(bool(stdin_payload.get("cwd")), f"clean exit: expected cwd in payload, got {stdin_payload}", failures)


def test_live_socket_reports_interrupt_exit(failures: list[str]) -> None:
    code, real_argv, cmux_log, stdin_payload, stderr = run_wrapper(
        socket_state="live",
        argv=["chat"],
        exit_code=130,
    )
    expect(code == 130, f"interrupt exit: wrapper exited {code}: {stderr}", failures)
    expect(real_argv == ["chat"], f"interrupt exit: expected passthrough args, got {real_argv}", failures)
    expect(
        any("codex-hook session-end" in line for line in cmux_log),
        f"interrupt exit: expected wrapper to report session-end, got {cmux_log}",
        failures,
    )
    expect(stdin_payload is not None, "interrupt exit: expected JSON payload on stdin", failures)
    if stdin_payload is not None:
        expect(stdin_payload.get("exit_status") == "130", f"interrupt exit: expected exit_status 130, got {stdin_payload}", failures)
        expect(stdin_payload.get("signal") == "INT", f"interrupt exit: expected signal INT, got {stdin_payload}", failures)


def test_missing_socket_skips_reporting(failures: list[str]) -> None:
    code, real_argv, cmux_log, stdin_payload, stderr = run_wrapper(
        socket_state="missing",
        argv=["chat"],
        exit_code=1,
    )
    expect(code == 1, f"missing socket: wrapper exited {code}: {stderr}", failures)
    expect(real_argv == ["chat"], f"missing socket: expected passthrough args, got {real_argv}", failures)
    expect(cmux_log == [], f"missing socket: expected no cmux calls, got {cmux_log}", failures)
    expect(stdin_payload is None, f"missing socket: expected no stdin payload, got {stdin_payload}", failures)


def test_stale_socket_skips_reporting(failures: list[str]) -> None:
    code, real_argv, cmux_log, stdin_payload, stderr = run_wrapper(
        socket_state="stale",
        argv=["chat"],
        exit_code=1,
    )
    expect(code == 1, f"stale socket: wrapper exited {code}: {stderr}", failures)
    expect(real_argv == ["chat"], f"stale socket: expected passthrough args, got {real_argv}", failures)
    expect(any(" ping" in line for line in cmux_log), f"stale socket: expected ping probe, got {cmux_log}", failures)
    expect(
        not any("codex-hook session-end" in line for line in cmux_log),
        f"stale socket: expected no session-end report, got {cmux_log}",
        failures,
    )
    expect(stdin_payload is None, f"stale socket: expected no stdin payload, got {stdin_payload}", failures)


def main() -> int:
    failures: list[str] = []
    test_live_socket_reports_clean_exit(failures)
    test_live_socket_reports_interrupt_exit(failures)
    test_missing_socket_skips_reporting(failures)
    test_stale_socket_skips_reporting(failures)

    if failures:
        print("FAIL: codex wrapper regression checks failed")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("PASS: codex wrapper reports clean exits and interrupts to cmux")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
