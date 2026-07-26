#!/usr/bin/env python3
"""Stage the App 90 VGUI resources required by the native game UI.

The source directory is a SteamCMD App 90 install. Every copied byte is
recorded in a deterministic manifest so tests can prove that the runtime parser
and renderer are consuming Valve's source resources rather than handwritten
lookalikes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path


CSTRIKE_RESOURCE_FILES = (
    "ClientScheme.res",
    "GameMenu.res",
    "OptionsSubMultiplayer.res",
    "cstrike_english.txt",
    "game_menu.tga",
    "game_menu_mouseover.tga",
    "logo_game.tga",
    "menu_hl_no_icon.tga",
)

VALVE_RESOURCE_FILES = (
    "ClientScheme.res",
    "DialogOptionsIngame.res",
    "OptionsSubAdvanced.res",
    "OptionsSubAudio.res",
    "OptionsSubKeyboard.res",
    "OptionsSubMouse.res",
    "OptionsSubMultiplayer.res",
    "OptionsSubVideo.res",
    "OptionsSubVoice.res",
    "MultiplayerAdvancedPage.res",
    "gameui_english.txt",
    "valve_english.txt",
    "mic_meter_dead.tga",
    "mic_meter_live.tga",
    "marlett.ttf",
)

VALVE_VOICE_ART = (
    "640_speaker1.tga",
    "640_speaker2.tga",
    "640_speaker3.tga",
    "640_speaker4.tga",
    "640_voiceblocked.tga",
    "speaker4.tga",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy_file(source: Path, destination: Path, depot_path: str, files: list[dict]) -> None:
    if not source.is_file():
        raise FileNotFoundError(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    files.append(
        {
            "file": destination.as_posix(),
            "source": depot_path,
            "size": destination.stat().st_size,
            "sha256": sha256(destination),
        }
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "app90_root",
        nargs="?",
        type=Path,
        default=Path("/tmp/protocol47-app90"),
    )
    parser.add_argument(
        "archive_destination",
        nargs="?",
        type=Path,
        default=Path("public/ui/classic"),
    )
    parser.add_argument(
        "runtime_destination",
        nargs="?",
        type=Path,
        default=Path("game/assets/ui/classic"),
    )
    args = parser.parse_args()

    app90 = args.app90_root.resolve()
    archive_destination = args.archive_destination.resolve()
    runtime_destination = args.runtime_destination.resolve()
    if not (app90 / "cstrike").is_dir() or not (app90 / "valve").is_dir():
        raise SystemExit(f"not an App 90 install: {app90}")

    source_inventory: list[tuple[Path, str]] = []
    for source in sorted((app90 / "cstrike/resource/UI").glob("*.res")):
        source_inventory.append((source, f"cstrike/resource/UI/{source.name}"))
    for name in CSTRIKE_RESOURCE_FILES:
        source_inventory.append(
            (app90 / "cstrike/resource" / name, f"cstrike/resource/{name}")
        )
    for name in VALVE_RESOURCE_FILES:
        source_inventory.append(
            (app90 / "valve/resource" / name, f"valve/resource/{name}")
        )
    for source in sorted((app90 / "cstrike/gfx/vgui").glob("*.tga")):
        source_inventory.append((source, f"cstrike/gfx/vgui/{source.name}"))
    source_inventory.append(
        (
            app90 / "cstrike/gfx/shell/kb_act.lst",
            "cstrike/gfx/shell/kb_act.lst",
        )
    )
    for name in VALVE_VOICE_ART:
        source_inventory.append(
            (app90 / "valve/gfx/vgui" / name, f"valve/gfx/vgui/{name}")
        )
    for source in sorted((app90 / "cstrike/maps").glob("*.txt")):
        source_inventory.append((source, f"cstrike/maps/{source.name}"))

    archive_files: list[dict] = []
    runtime_files: list[dict] = []
    # Remove only importer-owned text resources from the runtime tree. Godot
    # reserves `.res` for binary resources, so runtime byte mirrors use `.kv`.
    for suffix in ("*.res", "*.txt"):
        for stale in runtime_destination.rglob(suffix):
            stale.unlink()

    for source, depot_path in sorted(source_inventory, key=lambda item: item[1]):
        archive_target = archive_destination / depot_path
        copy_file(source, archive_target, depot_path, archive_files)

        relative = Path(depot_path)
        if relative.parts[:3] == ("cstrike", "gfx", "vgui"):
            runtime_relative = Path("vgui") / relative.name
        elif relative.parts[:3] == ("cstrike", "gfx", "shell"):
            runtime_relative = Path("bindings") / relative.name
        elif relative.parts[:3] == ("valve", "gfx", "vgui"):
            runtime_relative = Path("voice") / relative.name
        elif relative.parts[:2] == ("cstrike", "maps"):
            runtime_relative = Path("briefings") / relative.name
        elif relative.parts[:2] == ("cstrike", "resource"):
            runtime_relative = Path("resources/cstrike").joinpath(*relative.parts[2:])
        elif relative.parts[:2] == ("valve", "resource"):
            runtime_relative = Path("resources/valve").joinpath(*relative.parts[2:])
        else:
            raise AssertionError(depot_path)
        if (
            runtime_relative.suffix.lower() in {".res", ".txt"}
            and runtime_relative.parts[0] != "briefings"
        ):
            runtime_relative = runtime_relative.with_suffix(".kv")
        copy_file(
            source,
            runtime_destination / runtime_relative,
            depot_path,
            runtime_files,
        )

    # Manifest paths are relative so the checkout can move.
    for item in archive_files:
        item["file"] = Path(item["file"]).relative_to(archive_destination).as_posix()
    archive_files.sort(key=lambda item: item["file"])
    aggregate_input = "".join(
        f"{item['file']}\0{item['sha256']}\0{item['size']}\n"
        for item in archive_files
    ).encode()
    aggregate_sha256 = hashlib.sha256(aggregate_input).hexdigest()
    manifest = {
        "format": "protocol47-app90-vgui",
        "version": 1,
        "steam_app_id": 90,
        "depot_family": "Half-Life Dedicated Server / Counter-Strike 1.6",
        "file_count": len(archive_files),
        "aggregate_sha256": aggregate_sha256,
        "files": archive_files,
    }
    archive_destination.mkdir(parents=True, exist_ok=True)
    (archive_destination / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (archive_destination / "ASSET-SOURCE.md").write_text(
        "# App 90 classic VGUI resources\n\n"
        "These files were copied byte-for-byte from a SteamCMD App 90 install.\n"
        "They contain Valve Counter-Strike 1.6 VGUI layouts, scheme data, menu\n"
        "art, class and weapon portraits, localization, and platform option\n"
        "resources. `manifest.json` records the original depot-relative path,\n"
        "size, and SHA-256 of every staged file.\n\n"
        f"Aggregate inventory SHA-256: `{aggregate_sha256}`\n",
        encoding="utf-8",
    )

    for item in runtime_files:
        item["file"] = Path(item["file"]).relative_to(runtime_destination).as_posix()
    runtime_files.sort(key=lambda item: item["file"])
    runtime_destination.mkdir(parents=True, exist_ok=True)
    (runtime_destination / "manifest.json").write_text(
        json.dumps(
            {
                "format": "protocol47-app90-vgui-runtime",
                "version": 1,
                "source_aggregate_sha256": aggregate_sha256,
                "file_count": len(runtime_files),
                "files": runtime_files,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    (runtime_destination / "ASSET-SOURCE.md").write_text(
        "# App 90 classic VGUI runtime mirror\n\n"
        "Binary art/font files are byte-identical to `public/ui/classic`.\n"
        "Valve KeyValues `.res`/`.txt` files use a `.kv` extension here because\n"
        "Godot reserves `.res`; their bytes and SHA-256 remain unchanged.\n\n"
        f"Source aggregate SHA-256: `{aggregate_sha256}`\n",
        encoding="utf-8",
    )
    print(
        f"APP90_VGUI_IMPORT_PASS files={len(archive_files)} "
        f"aggregate_sha256={aggregate_sha256}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
