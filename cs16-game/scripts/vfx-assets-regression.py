#!/usr/bin/env python3
"""Reject stale/incomplete combat exports, including silently omitted sprites."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    checked_in = root / "game/assets/vfx"
    with tempfile.TemporaryDirectory(prefix="protocol47-vfx-regression-") as temporary:
        generated = Path(temporary)
        subprocess.run([
            sys.executable, str(root / "scripts/import-game-vfx.py"),
            str(root.parent / "shared/goldsrc-assets/sprites/classic"),
            str(root.parent / "shared/goldsrc-assets/wads/decals.wad"), str(generated),
        ], check=True, capture_output=True, text=True)
        expected = json.loads((generated / "manifest.json").read_text())
        actual = json.loads((checked_in / "manifest.json").read_text())
        if actual != expected:
            raise AssertionError("Combat manifest is stale; rerun scripts/import-game-vfx.sh")
        files = list(generated.rglob("*.png"))
        for source in files:
            relative = source.relative_to(generated)
            destination = checked_in / relative
            if not destination.is_file() or digest(source) != digest(destination):
                raise AssertionError(f"Missing or stale combat texture: {relative}")
        print(f"GAME_VFX_ASSETS_TEST_PASS sprites={len(actual['sprites'])} textures={len(files)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
