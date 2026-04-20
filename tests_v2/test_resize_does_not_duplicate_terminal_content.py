#!/usr/bin/env python3
"""Regression: terminal output lines are not duplicated by resize churn."""

from __future__ import annotations

import os
import secrets
import sys
import time
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError
from pane_resize_test_support import (
    focused_pane_id as _focused_pane_id,
    pane_extent as _pane_extent,
    pick_resize_direction_for_pane as _pick_resize_direction_for_pane,
    surface_scrollback_lines as _surface_scrollback_lines,
    wait_for as _wait_for,
    wait_for_surface_command_roundtrip as _wait_for_surface_command_roundtrip,
    workspace_panes as _workspace_panes,
    must as _must,
)


DEFAULT_SOCKET_PATHS = ["/tmp/cmux-debug.sock", "/tmp/cmux.sock"]


def _count_exact_lines(
    client: cmux,
    workspace_id: str,
    surface_id: str,
    expected_lines: list[str],
) -> Counter[str]:
    expected = set(expected_lines)
    lines = _surface_scrollback_lines(client, workspace_id, surface_id)
    return Counter(line for line in lines if line in expected)


def _line_counts_ready(
    client: cmux,
    workspace_id: str,
    surface_id: str,
    expected_lines: list[str],
) -> bool:
    counts = _count_exact_lines(client, workspace_id, surface_id, expected_lines)
    return all(counts[line] == 1 for line in expected_lines)


def _run_once(socket_path: str) -> int:
    workspace_id = ""
    try:
        with cmux(socket_path) as client:
            workspace_id = client.new_workspace()
            client.select_workspace(workspace_id)

            surfaces = client.list_surfaces(workspace_id)
            _must(bool(surfaces), f"workspace should have at least one surface: {workspace_id}")
            surface_id = surfaces[0][1]
            _wait_for_surface_command_roundtrip(client, workspace_id, surface_id)

            stamp = secrets.token_hex(4)
            output_lines = [f"CMUX_RESIZE_DUP_CONTENT_{stamp}_{index:02d}" for index in range(1, 25)]
            draw_output = (
                f"stamp={stamp}; "
                "i=1; "
                f"while [ $i -le {len(output_lines)} ]; do "
                "printf 'CMUX_RESIZE_DUP_CONTENT_%s_%02d\\n' \"$stamp\" \"$i\"; "
                "i=$((i + 1)); "
                "done"
            )
            client.send_surface(surface_id, draw_output + "\n")
            _wait_for(
                lambda: _line_counts_ready(client, workspace_id, surface_id, output_lines),
                timeout_s=10.0,
            )
            pre_counts = _count_exact_lines(client, workspace_id, surface_id, output_lines)
            _must(
                all(pre_counts[line] == 1 for line in output_lines),
                f"pre-resize output counts were not exactly once: {pre_counts}",
            )

            split_payload = client._call(
                "surface.split",
                {"workspace_id": workspace_id, "surface_id": surface_id, "direction": "right"},
            ) or {}
            _must(bool(split_payload.get("surface_id")), f"surface.split returned no surface_id: {split_payload}")
            _wait_for(lambda: len(_workspace_panes(client, workspace_id)) >= 2, timeout_s=4.0)

            client.focus_surface(surface_id)
            time.sleep(0.1)
            pane_ids = [pid for pid, _focused, _surface_count in _workspace_panes(client, workspace_id)]
            pane_id = _focused_pane_id(client, workspace_id)
            grow_direction, axis = _pick_resize_direction_for_pane(client, pane_ids, pane_id)
            shrink_direction = {
                "left": "right",
                "right": "left",
                "up": "down",
                "down": "up",
            }[grow_direction]

            directions = [grow_direction, shrink_direction] * 4
            for direction in directions:
                pre_extent = _pane_extent(client, pane_id, axis)
                resize_result = client._call(
                    "pane.resize",
                    {
                        "workspace_id": workspace_id,
                        "pane_id": pane_id,
                        "direction": direction,
                        "amount": 80,
                    },
                ) or {}
                _must(
                    str(resize_result.get("pane_id") or "") == pane_id,
                    f"pane.resize response missing expected pane_id: {resize_result}",
                )
                _wait_for(
                    lambda before=pre_extent, want=direction: (
                        _pane_extent(client, pane_id, axis) > before + 1.0
                        if want == grow_direction
                        else _pane_extent(client, pane_id, axis) < before - 1.0
                    ),
                    timeout_s=5.0,
                )

            post_token = f"CMUX_RESIZE_DUP_POST_{stamp}"
            client.send_surface(surface_id, f"echo {post_token}\n")
            _wait_for(
                lambda: post_token in _surface_scrollback_lines(client, workspace_id, surface_id),
                timeout_s=8.0,
            )

            post_counts = _count_exact_lines(client, workspace_id, surface_id, output_lines)
            duplicated = {line: count for line, count in post_counts.items() if count != 1}
            _must(
                not duplicated,
                f"resize duplicated prior terminal output lines: {duplicated}",
            )

            client.close_workspace(workspace_id)
            workspace_id = ""

        print("PASS: resize churn does not duplicate prior terminal output lines")
        return 0
    finally:
        if workspace_id:
            try:
                with cmux(socket_path) as cleanup_client:
                    cleanup_client.close_workspace(workspace_id)
            except Exception:
                pass


def main() -> int:
    env_socket = os.environ.get("CMUX_SOCKET")
    if env_socket:
        return _run_once(env_socket)

    last_error: Exception | None = None
    for socket_path in DEFAULT_SOCKET_PATHS:
        try:
            return _run_once(socket_path)
        except cmuxError as exc:
            text = str(exc)
            recoverable = (
                "Failed to connect",
                "Socket not found",
            )
            if not any(token in text for token in recoverable):
                raise
            last_error = exc
            continue

    if last_error is not None:
        raise last_error
    raise cmuxError("No socket candidates configured")


if __name__ == "__main__":
    raise SystemExit(main())
