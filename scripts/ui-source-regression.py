#!/usr/bin/env python3
"""Verify the staged App 90 VGUI archive and Godot runtime mirror."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "shared" / "goldsrc-assets"
ARCHIVE = ASSETS / "ui/classic"
RUNTIME = ROOT / "game/assets/ui/classic"
EXPECTED = "1a36e031123dce268f5c3c04141be7c8dd519fae98309f6dcd844f6001c54374"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    archive_manifest = json.loads((ARCHIVE / "manifest.json").read_text())
    runtime_manifest = json.loads((RUNTIME / "manifest.json").read_text())
    assert archive_manifest["steam_app_id"] == 90
    assert archive_manifest["file_count"] == 135
    assert archive_manifest["aggregate_sha256"] == EXPECTED
    assert runtime_manifest["file_count"] == 135
    assert runtime_manifest["source_aggregate_sha256"] == EXPECTED

    inventory = []
    source_hashes = {}
    for item in archive_manifest["files"]:
        path = ARCHIVE / item["file"]
        assert path.is_file(), f"missing source resource: {item['file']}"
        actual = digest(path)
        assert actual == item["sha256"], f"source hash mismatch: {item['file']}"
        assert path.stat().st_size == item["size"]
        inventory.append(f"{item['file']}\0{actual}\0{item['size']}\n")
        source_hashes[item["source"]] = actual
    assert hashlib.sha256("".join(inventory).encode()).hexdigest() == EXPECTED

    for item in runtime_manifest["files"]:
        path = RUNTIME / item["file"]
        assert path.is_file(), f"missing runtime resource: {item['file']}"
        actual = digest(path)
        assert actual == item["sha256"], f"runtime hash mismatch: {item['file']}"
        assert actual == source_hashes[item["source"]]

    required = [
        ARCHIVE / "cstrike/resource/UI/Teammenu.res",
        ARCHIVE / "cstrike/resource/UI/ScoreBoard.res",
        ARCHIVE / "cstrike/resource/UI/BuyRifles_CT.res",
        ARCHIVE / "cstrike/resource/GameMenu.res",
        ARCHIVE / "cstrike/resource/game_menu.tga",
        ARCHIVE / "cstrike/gfx/vgui/urban.tga",
        ARCHIVE / "cstrike/gfx/vgui/ak47.tga",
        ARCHIVE / "cstrike/maps/de_dust2.txt",
        ARCHIVE / "cstrike/gfx/shell/kb_act.lst",
        ARCHIVE / "valve/gfx/vgui/640_speaker4.tga",
        ARCHIVE / "valve/gfx/vgui/640_voiceblocked.tga",
        ARCHIVE / "valve/resource/mic_meter_dead.tga",
        ARCHIVE / "valve/resource/mic_meter_live.tga",
    ]
    assert all(path.is_file() for path in required)
    print(
        "APP90_UI_SOURCE_REGRESSION_PASS "
        f"files={archive_manifest['file_count']} aggregate_sha256={EXPECTED}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
