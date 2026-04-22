#!/usr/bin/env python3
"""
Regression test: the generated OpenCode session plugin is valid ESM.
"""

from __future__ import annotations

import os
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from claude_teams_test_utils import resolve_cmux_cli


def make_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def main() -> int:
    bun = shutil.which("bun")
    if bun is None:
        print("SKIP: bun not found")
        return 0

    try:
        cli_path = resolve_cmux_cli()
    except Exception as exc:
        print(f"FAIL: {exc}")
        return 1

    with tempfile.TemporaryDirectory(prefix="cmux-opencode-plugin-") as td:
        root = Path(td)
        config_dir = root / "opencode"
        config_dir.mkdir(parents=True, exist_ok=True)
        config_json = config_dir / "opencode.json"
        config_json.write_text(
            json.dumps(
                {
                    "plugin": [
                        "oh-my-opencode",
                        ["existing-plugin", {"enabled": True}],
                    ]
                }
            ),
            encoding="utf-8",
        )
        env = os.environ.copy()
        env["OPENCODE_CONFIG_DIR"] = str(config_dir)

        install = subprocess.run(
            [cli_path, "opencode", "install-hooks", "--yes"],
            capture_output=True,
            text=True,
            check=False,
            env=env,
            timeout=20,
        )
        if install.returncode != 0:
            print("FAIL: opencode plugin install failed")
            print(f"exit={install.returncode}")
            print(f"stdout={install.stdout.strip()}")
            print(f"stderr={install.stderr.strip()}")
            return 1

        plugin_path = config_dir / "plugins" / "cmux-session.js"
        if not plugin_path.exists():
            print(f"FAIL: expected plugin at {plugin_path}")
            return 1

        try:
            config = json.loads(config_json.read_text(encoding="utf-8"))
        except Exception as exc:
            print(f"FAIL: invalid opencode.json after install: {exc}")
            return 1
        plugins = config.get("plugin")
        if not isinstance(plugins, list):
            print(f"FAIL: expected plugin list in opencode.json, got {plugins!r}")
            return 1
        if "cmux-session" not in plugins:
            print(f"FAIL: expected cmux-session registration in opencode.json, got {plugins!r}")
            return 1
        if "oh-my-opencode" not in plugins or ["existing-plugin", {"enabled": True}] not in plugins:
            print(f"FAIL: installer did not preserve existing plugin entries: {plugins!r}")
            return 1

        fake_cmux = root / "fake-cmux"
        fake_args_log = root / "fake-cmux-args.log"
        fake_stdin_log = root / "fake-cmux-stdin.log"
        fake_env_log = root / "fake-cmux-env.log"
        make_executable(
            fake_cmux,
            """#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$FAKE_CMUX_ARGS_LOG"
cat >> "$FAKE_CMUX_STDIN_LOG"
printf '\\n---\\n' >> "$FAKE_CMUX_STDIN_LOG"
{
  printf 'kind=%s\\n' "${CMUX_AGENT_LAUNCH_KIND-}"
  printf 'cwd=%s\\n' "${CMUX_AGENT_LAUNCH_CWD-}"
  printf 'argv=%s\\n' "${CMUX_AGENT_LAUNCH_ARGV_B64-}"
} >> "$FAKE_CMUX_ENV_LOG"
""",
        )

        check_env = env.copy()
        check_env["CMUX_TEST_OPENCODE_PLUGIN_PATH"] = str(plugin_path)
        check_env["CMUX_SURFACE_ID"] = "surface-opencode-test"
        check_env["CMUX_OPENCODE_CMUX_BIN"] = str(fake_cmux)
        check_env["FAKE_CMUX_ARGS_LOG"] = str(fake_args_log)
        check_env["FAKE_CMUX_STDIN_LOG"] = str(fake_stdin_log)
        check_env["FAKE_CMUX_ENV_LOG"] = str(fake_env_log)
        check_source = """
	const pluginPath = process.env.CMUX_TEST_OPENCODE_PLUGIN_PATH;
	const mod = await import(pluginPath);
	if (typeof mod.CMUXSessionRestore !== "function") {
	  throw new Error("missing CMUXSessionRestore export");
	}
	if (typeof mod.default !== "function") {
	  throw new Error("missing default export");
	}
	const hooks = await mod.default({ directory: "/tmp/opencode-project" });
	if (!hooks || typeof hooks.event !== "function") {
	  throw new Error("missing event hook");
	}
	await hooks.event({
	  event: {
	    type: "session.created",
	    properties: {
	      info: {
	        id: "opencode-session-test",
	        directory: "/tmp/opencode-project"
	      }
	    }
	  }
	});
	"""
        check = subprocess.run(
            [bun, "--eval", check_source],
            cwd=root,
            capture_output=True,
            text=True,
            check=False,
            env=check_env,
            timeout=20,
        )
        if check.returncode != 0:
            print("FAIL: generated OpenCode plugin is not importable ESM")
            print(f"exit={check.returncode}")
            print(f"stdout={check.stdout.strip()}")
            print(f"stderr={check.stderr.strip()}")
            return 1

        args_log = fake_args_log.read_text(encoding="utf-8") if fake_args_log.exists() else ""
        stdin_log = fake_stdin_log.read_text(encoding="utf-8") if fake_stdin_log.exists() else ""
        env_log = fake_env_log.read_text(encoding="utf-8") if fake_env_log.exists() else ""
        if "opencode-hook session-start" not in args_log:
            print(f"FAIL: plugin did not invoke opencode-hook session-start, got {args_log!r}")
            return 1
        if '"session_id":"opencode-session-test"' not in stdin_log or '"/tmp/opencode-project"' not in stdin_log:
            print(f"FAIL: plugin did not pass expected session payload, got {stdin_log!r}")
            return 1
        if "kind=opencode" not in env_log or "cwd=/tmp/opencode-project" not in env_log or "argv=" not in env_log:
            print(f"FAIL: plugin did not pass launch metadata environment, got {env_log!r}")
            return 1

    print("PASS: generated OpenCode plugin installs and imports as ESM")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
