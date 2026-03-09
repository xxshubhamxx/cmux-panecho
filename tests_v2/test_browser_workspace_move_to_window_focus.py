#!/usr/bin/env python3
"""Regression test for browser workspace move-to-window focus semantics.

Requires a Debug app socket that allows external clients, typically:

  CMUX_SOCKET=/tmp/cmux-debug-<tag>.sock
  CMUX_SOCKET_MODE=allowAll
"""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError


SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def _must(cond: bool, msg: str) -> None:
    if not cond:
        raise cmuxError(msg)


def _wait_for_browser_visibility(
    client: cmux,
    panel_id: str,
    workspace_id: str,
    timeout_s: float = 8.0,
) -> dict:
    start = time.time()
    last_snapshot: dict | None = None
    while time.time() - start < timeout_s:
        snapshot = client.panel_lifecycle()
        last_snapshot = snapshot
        row = next((row for row in list(snapshot.get("records") or []) if row.get("panelId") == panel_id), None)
        if row and row.get("workspaceId") == workspace_id:
            anchor = dict(row.get("anchor") or {})
            if (
                row.get("selectedWorkspace") is True
                and row.get("activeWindowMembership") is True
                and row.get("residency") == "visibleInActiveWindow"
                and int(anchor.get("windowNumber") or 0) != 0
            ):
                return dict(row)
        time.sleep(0.05)
    raise cmuxError(f"timed out waiting for visible moved browser: {last_snapshot}")


def main() -> int:
    with cmux(SOCKET_PATH) as client:
        workspace_id = client.current_workspace()
        source_window_id = client.current_window()

        browser_panel_id = client.open_browser("https://example.com/browser-workspace-move-to-window")
        destination_window_id = client.new_window()

        _must(source_window_id != destination_window_id, "window.create should return a new window id")
        client.move_workspace_to_window(workspace_id, destination_window_id, focus=True)

        _must(
            client.current_workspace() == workspace_id,
            f"workspace.move_to_window with focus=true should select moved workspace, got {client.current_workspace()} expected {workspace_id}",
        )
        _must(
            client.current_window() == destination_window_id,
            f"workspace.move_to_window with focus=true should focus destination window, got {client.current_window()} expected {destination_window_id}",
        )

        browser = _wait_for_browser_visibility(client, browser_panel_id, workspace_id)
        _must(browser.get("selectedWorkspace") is True, f"browser not selected after move: {browser}")
        _must(browser.get("activeWindowMembership") is True, f"browser not active-window member after move: {browser}")
        _must(browser.get("residency") == "visibleInActiveWindow", f"browser wrong residency after move: {browser}")

    print("PASS: browser workspace move_to_window preserves focus and visible residency")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
