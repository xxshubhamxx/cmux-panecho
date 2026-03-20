#!/usr/bin/env python3
"""Integration test: paper-canvas pane motion keeps Ghostty portals aligned."""

from __future__ import annotations

import glob
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path


def resolve_cmux_app() -> Path:
    explicit_bundle = os.environ.get("CMUX_APP_BUNDLE")
    if explicit_bundle:
        bundle = Path(explicit_bundle).expanduser()
        if bundle.exists():
            return bundle
        raise RuntimeError(f"CMUX_APP_BUNDLE does not exist: {bundle}")

    candidates: list[str] = []
    candidates.extend(
        glob.glob(
            os.path.expanduser(
                "~/Library/Developer/Xcode/DerivedData/cmux-*/Build/Products/Debug/cmux DEV *.app"
            )
        )
    )
    candidates = [p for p in candidates if os.path.exists(p)]
    if not candidates:
        raise RuntimeError("Unable to find a tagged cmux DEV.app. Set CMUX_APP_BUNDLE.")

    candidates.sort(key=os.path.getmtime, reverse=True)
    return Path(candidates[0])


def resolve_cmux_binary() -> Path:
    explicit_bin = os.environ.get("CMUX_APP_BIN")
    if explicit_bin:
        binary = Path(explicit_bin).expanduser()
        if binary.exists() and os.access(binary, os.X_OK):
            return binary
        raise RuntimeError(f"CMUX_APP_BIN is not executable: {binary}")

    bundle = resolve_cmux_app()
    macos_dir = bundle / "Contents" / "MacOS"
    if macos_dir.exists():
        for candidate in sorted(macos_dir.iterdir()):
            if (
                candidate.is_file()
                and os.access(candidate, os.X_OK)
                and candidate.suffix == ""
                and "__preview" not in candidate.name
            ):
                return candidate
    raise RuntimeError(f"Unable to resolve app binary inside {bundle}")


def resolve_cmux_bundle_for_binary(binary: Path) -> Path:
    current = binary.resolve()
    for parent in current.parents:
        if parent.suffix == ".app":
            return parent
    return resolve_cmux_app()


def load_json(path: Path) -> dict[str, str] | None:
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def output_path_for(scenario: str) -> Path | None:
    output_dir = os.environ.get("CMUX_PANE_STRIP_MOTION_OUTPUT_DIR")
    if not output_dir:
        return None

    path = Path(output_dir).expanduser()
    path.mkdir(parents=True, exist_ok=True)
    return path / f"{scenario}.json"


def kill_existing_binary_processes(binary: Path) -> None:
    subprocess.run(
        ["/usr/bin/pkill", "-f", str(binary)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        text=True,
    )
    time.sleep(0.2)


def terminate_process(proc: subprocess.Popen[str]) -> None:
    if proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=5)
        return
    except subprocess.TimeoutExpired:
        pass

    proc.kill()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass


def activate_app_bundle(bundle: Path) -> None:
    subprocess.run(
        ["/usr/bin/open", "-a", str(bundle)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        text=True,
    )


def run_scenario(binary: Path, scenario: str, frame_count: int) -> tuple[bool, str]:
    persisted_output = output_path_for(scenario)
    bundle = resolve_cmux_bundle_for_binary(binary)
    launch_mode = os.environ.get("CMUX_PANE_STRIP_LAUNCH_MODE")
    if not launch_mode:
        launch_mode = (
            "background_then_activate"
            if scenario == "initial_terminal_recovers_after_late_activation"
            else "direct"
        )
    kill_existing_binary_processes(binary)
    with tempfile.TemporaryDirectory(prefix="cmux-pane-strip-motion-") as temp_dir:
        data_path = Path(temp_dir) / f"{scenario}.json"
        env = os.environ.copy()
        env["CMUX_PANE_STRIP_MOTION_SETUP"] = "1"
        env["CMUX_PANE_STRIP_MOTION_PATH"] = str(data_path)
        env["CMUX_PANE_STRIP_MOTION_SCENARIO"] = scenario
        env["CMUX_PANE_STRIP_MOTION_FRAME_COUNT"] = str(frame_count)
        env["CMUX_PANE_STRIP_MOTION_QUIT_WHEN_DONE"] = "1"
        env["CMUX_PANE_STRIP_LAUNCH_MODE"] = launch_mode
        env["CMUX_CLI_SENTRY_DISABLED"] = "1"
        env["CMUX_CLAUDE_HOOK_SENTRY_DISABLED"] = "1"

        proc = subprocess.Popen(
            [str(binary)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
            start_new_session=True,
            text=True,
        )

        deadline = time.time() + 35.0
        activation_delay = 1.5 if launch_mode == "background_then_activate" else 0.0
        next_activation_at = time.time() + activation_delay
        payload: dict[str, str] | None = None
        try:
            while time.time() < deadline:
                now = time.time()
                if now >= next_activation_at:
                    activate_app_bundle(bundle)
                    next_activation_at = now + 0.5
                payload = load_json(data_path)
                if payload and payload.get("done") == "1":
                    break
                if proc.poll() is not None and not data_path.exists():
                    break
                time.sleep(0.1)
        finally:
            terminate_process(proc)

        payload = load_json(data_path)
        if not payload:
            return False, f"{scenario}: no output written to {data_path}"

        if persisted_output:
            persisted_output.write_text(json.dumps(payload, indent=2, sort_keys=True))

        if payload.get("setupError"):
            return False, f"{scenario}: setupError={payload['setupError']}"

        if payload.get("status") != "ok":
            return False, f"{scenario}: status={payload.get('status', 'missing')} payload={payload}"

        output_suffix = f" output={persisted_output}" if persisted_output else ""

        if payload.get("occlusionFailureSeen") == "1":
            return False, (
                f"{scenario}: occlusion at {payload.get('occlusionObservedAt', '')} "
                f"max_wrong_hits={payload.get('maxWrongHitCount', '?')} "
                f"trace={payload.get('timelineTrace', '')}{output_suffix}"
            )

        if payload.get("visibilityFailureSeen") == "1":
            return False, (
                f"{scenario}: visibility failure at {payload.get('visibilityObservedAt', '')} "
                f"trace={payload.get('timelineTrace', '')}{output_suffix}"
            )

        if payload.get("hostedOverlapFailureSeen") == "1":
            return False, (
                f"{scenario}: hosted overlap at {payload.get('hostedOverlapObservedAt', '')} "
                f"max_hosted_overlap={payload.get('maxHostedOverlapPx', '?')} "
                f"trace={payload.get('timelineTrace', '')}{output_suffix}"
            )

        if payload.get("alignmentFailureSeen") == "1":
            return False, (
                f"{scenario}: alignment failure at {payload.get('alignmentObservedAt', '')} "
                f"trace={payload.get('timelineTrace', '')}{output_suffix}"
            )

        if payload.get("blankFrameSeen") == "1":
            return False, (
                f"{scenario}: blank frame at {payload.get('blankObservedAt', '')} "
                f"trace={payload.get('timelineTrace', '')}{output_suffix}"
            )

        if payload.get("sizeMismatchSeen") == "1":
            return False, (
                f"{scenario}: iosurface size mismatch at {payload.get('sizeMismatchObservedAt', '')} "
                f"trace={payload.get('timelineTrace', '')}{output_suffix}"
            )

        return True, (
            f"{scenario}: PASS frames={payload.get('timelineFrameCount', '?')} "
            f"max_position_error={payload.get('maxPositionErrorPx', '?')} "
            f"max_size_error={payload.get('maxSizeErrorPx', '?')} "
            f"max_wrong_hits={payload.get('maxWrongHitCount', '?')} "
            f"max_hosted_overlap={payload.get('maxHostedOverlapPx', '?')}{output_suffix}"
        )


def main() -> int:
    try:
        binary = resolve_cmux_binary()
    except Exception as exc:
        print(f"FAIL: {exc}")
        return 1

    frame_count = int(os.environ.get("CMUX_PANE_STRIP_MOTION_FRAMES", "36"))
    scenarios = os.environ.get(
        "CMUX_PANE_STRIP_MOTION_SCENARIOS",
        "initial_terminal_visible,initial_terminal_renders_after_input,initial_terminal_recovers_after_late_activation,focus_reveal_right,pan_viewport_right,open_pane_right,browser_focus_reveal_right",
    ).split(",")
    scenarios = [s.strip() for s in scenarios if s.strip()]

    all_ok = True
    for scenario in scenarios:
        ok, message = run_scenario(binary, scenario, frame_count)
        print(("PASS: " if ok else "FAIL: ") + message)
        all_ok = all_ok and ok

    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
