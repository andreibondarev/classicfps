#!/usr/bin/env python3
"""Launch the exported macOS build and reject release-only resource failures."""

from __future__ import annotations

import os
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile


REJECTED_OUTPUT = (
    "Missing staged App 90 VGUI resource",
    "SCRIPT ERROR:",
    "Parse Error:",
    "Failed loading resource:",
)


def rejected_output(output: str) -> list[str]:
    """Godot can return zero despite script, resource, or teardown errors."""
    rejected = []
    for raw_line in output.splitlines():
        line = re.sub(r"\x1b\[[0-9;]*m", "", raw_line).strip()
        if (
            any(marker in line for marker in REJECTED_OUTPUT)
            or line.startswith("ERROR:")
            or re.search(r"ObjectDB instances? (?:were |was )?leaked", line)
            or re.search(r"\b[A-Z][A-Z0-9_]*_FAIL\b", line)
        ):
            rejected.append(line)
    return rejected


def launch_args(executable: Path, log_path: Path) -> list[str]:
    return [
        str(executable),
        "--headless",
        "--audio-driver",
        "Dummy",
        "--log-file",
        str(log_path),
        "--quit-after",
        "180",
        "--",
        "--verify-settings-storage",
    ]


def launch_environment(settings_path: Path) -> dict[str, str]:
    environment = os.environ.copy()
    environment["PROTOCOL47_SETTINGS_PATH"] = str(settings_path)
    return environment


def isolated_storage_confirmed(output: str, settings_path: Path) -> bool:
    prefix = "GAME_SETTINGS_STORAGE_READY "
    records = []
    try:
        for line in output.splitlines():
            if line.startswith(prefix):
                records.append(json.loads(line[len(prefix):]))
    except json.JSONDecodeError:
        return False
    expected = {"path": str(settings_path), "fresh": True}
    return bool(records) and all(record == expected for record in records)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: export-package-regression.py PATH_TO_PROTOCOL47_ZIP", file=sys.stderr)
        return 2
    if sys.platform != "darwin":
        print("EXPORT_PACKAGE_REGRESSION_SKIP: macOS bundle requires a macOS host")
        return 0

    archive = Path(sys.argv[1]).resolve()
    if not archive.is_file():
        print(f"missing export archive: {archive}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="protocol47-export-") as temp_name:
        temp_dir = Path(temp_name)
        with zipfile.ZipFile(archive) as package:
            names = set(package.namelist())
            executable_name = "Protocol 47.app/Contents/MacOS/Protocol 47"
            pck_name = "Protocol 47.app/Contents/Resources/Protocol 47.pck"
            missing = sorted({executable_name, pck_name} - names)
            if missing:
                print(f"incomplete export archive; missing: {', '.join(missing)}", file=sys.stderr)
                return 1
            package.extractall(temp_dir)

        executable = temp_dir / executable_name
        executable.chmod(executable.stat().st_mode | 0o100)
        user_data = temp_dir / "userdata"
        user_data.mkdir()
        log_path = temp_dir / "export-run.log"
        settings_path = user_data / "protocol47.cfg"
        result = subprocess.run(
            launch_args(executable, log_path),
            cwd=temp_dir,
            env=launch_environment(settings_path),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
            check=False,
        )
        output = result.stdout
        if log_path.is_file():
            output += "\n" + log_path.read_text(errors="replace")

        rejected = rejected_output(output)
        storage_confirmed = isolated_storage_confirmed(output, settings_path)
        if result.returncode != 0 or rejected or not storage_confirmed:
            print(output, file=sys.stderr)
            print(
                f"export launch rejected: exit={result.returncode}, markers={rejected}, isolated_settings={storage_confirmed}",
                file=sys.stderr,
            )
            return 1

    print("EXPORT_PACKAGE_REGRESSION_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
