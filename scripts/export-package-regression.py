#!/usr/bin/env python3
"""Launch the exported macOS build and reject release-only resource failures."""

from __future__ import annotations

import os
from pathlib import Path
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
        environment = os.environ.copy()
        environment["GODOT_USER_DATA_DIR"] = str(user_data)
        result = subprocess.run(
            [
                str(executable),
                "--headless",
                "--log-file",
                str(log_path),
                "--quit-after",
                "180",
            ],
            cwd=temp_dir,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
            check=False,
        )
        output = result.stdout
        if log_path.is_file():
            output += "\n" + log_path.read_text(errors="replace")

        rejected = [marker for marker in REJECTED_OUTPUT if marker in output]
        if result.returncode != 0 or rejected:
            print(output, file=sys.stderr)
            print(
                f"export launch rejected: exit={result.returncode}, markers={rejected}",
                file=sys.stderr,
            )
            return 1

    print("EXPORT_PACKAGE_REGRESSION_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
