#!/usr/bin/env python3
"""Extract Valve's original 640px CS HUD atlas regions as tintable PNG masks."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zlib


CORE_NAMES = (
    *(f"number_{digit}" for digit in range(10)),
    "divider",
    "cross",
    "dollar",
    "minus",
    "plus",
    "stopwatch",
    "suit_full",
    "suit_empty",
    "suithelmet_full",
    "suithelmet_empty",
    "flash_full",
    "flash_empty",
    "flash_beam",
    "smallskull",
    "smallc4",
    "smallvip",
    "buyzone",
    "defuser",
    "rescue",
    "escape",
    "vipsafety",
    "hostage",
    "bombticking",
    "bombticking1",
    "radar",
    "radaropaque",
)


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    rows = b"".join(
        b"\x00" + rgba[y * width * 4 : (y + 1) * width * 4]
        for y in range(height)
    )
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(rows, 9))
        + png_chunk(b"IEND", b"")
    )


def read_sprite(path: Path) -> tuple[int, int, list[tuple[int, int, int]], bytes]:
    data = path.read_bytes()
    if data[:4] != b"IDSP" or struct.unpack_from("<I", data, 4)[0] != 2:
        raise ValueError(f"Unsupported GoldSrc sprite: {path}")
    palette_count = struct.unpack_from("<H", data, 40)[0]
    palette_offset = 42
    palette = [
        tuple(data[palette_offset + index * 3 : palette_offset + index * 3 + 3])
        for index in range(palette_count)
    ]
    frame_offset = palette_offset + palette_count * 3
    frame_type = struct.unpack_from("<I", data, frame_offset)[0]
    if frame_type != 0:
        raise ValueError(f"Grouped sprites are not supported: {path}")
    _, _, width, height = struct.unpack_from("<iiii", data, frame_offset + 4)
    pixels_offset = frame_offset + 20
    pixels = data[pixels_offset : pixels_offset + width * height]
    if len(pixels) != width * height:
        raise ValueError(f"Truncated sprite frame: {path}")
    return width, height, palette, pixels


def definitions(source: Path) -> dict[str, tuple[str, int, int, int, int]]:
    output: dict[str, tuple[str, int, int, int, int]] = {}
    for line in (source / "hud.txt").read_text(errors="replace").splitlines():
        parts = re.split(r"\s+", line.strip())
        if len(parts) != 7 or parts[1] != "640":
            continue
        output[parts[0]] = (
            parts[2],
            int(parts[3]),
            int(parts[4]),
            int(parts[5]),
            int(parts[6]),
        )
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Validated cstrike/sprites directory")
    parser.add_argument("output", type=Path, help="Godot-ready output directory")
    parser.add_argument("--death-notices", action="store_true", help="Extract the original d_* kill-feed sprites instead of HUD counters")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    atlas_definitions = definitions(args.source)
    sheets: dict[str, tuple[int, int, list[tuple[int, int, int]], bytes]] = {}
    manifest: dict[str, object] = {
        "format": "protocol47-cs16-hud",
        "resolution": 640,
        "source_hud_sha256": hashlib.sha256(
            (args.source / "hud.txt").read_bytes()
        ).hexdigest(),
        "sprites": {},
    }

    names = sorted(name for name in atlas_definitions if name.startswith("d_")) if args.death_notices else CORE_NAMES
    for name in names:
        if name not in atlas_definitions:
            raise ValueError(f"Missing 640px HUD definition: {name}")
        sheet, x, y, width, height = atlas_definitions[name]
        source_path = args.source / f"{sheet}.spr"
        if sheet not in sheets:
            sheets[sheet] = read_sprite(source_path)
        sheet_width, sheet_height, palette, pixels = sheets[sheet]
        if x + width > sheet_width or y + height > sheet_height:
            raise ValueError(f"Crop outside {sheet}.spr for {name}")

        rgba = bytearray()
        for row in range(y, y + height):
            for column in range(x, x + width):
                red, green, blue = palette[pixels[row * sheet_width + column]]
                # GoldSrc pushes these additive sprites through its hardware
                # gamma ramp (texgamma 2.2), which lifts the dim glyph fills
                # well above their raw palette values. Bake that response into
                # the mask so digits read solid like the in-game HUD instead of
                # hollow outlines.
                alpha = round(255.0 * (max(red, green, blue) / 255.0) ** (1.0 / 2.2))
                rgba.extend((255, 255, 255, alpha))
        output_path = args.output / f"{name}.png"
        write_png(output_path, width, height, bytes(rgba))
        manifest["sprites"][name] = {
            "file": output_path.name,
            "width": width,
            "height": height,
            "sheet": f"{sheet}.spr",
            "source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
        }

    (args.output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )
    print(f"Extracted {len(names)} official HUD sprites to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
