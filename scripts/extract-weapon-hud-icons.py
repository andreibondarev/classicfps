#!/usr/bin/env python3
"""Extract Counter-Strike's original 640px weapon HUD silhouettes as PNG masks."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import struct
import zlib


WEAPONS = (
    "p228", "shield", "scout", "hegrenade", "xm1014", "c4", "mac10", "aug",
    "smokegrenade", "elite", "fiveseven", "ump45", "sg550", "galil", "famas",
    "usp", "glock18", "awp", "mp5navy", "m249", "m3", "m4a1", "tmp", "g3sg1",
    "flashbang", "deagle", "sg552", "ak47", "knife", "p90",
)


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(
        ">I", zlib.crc32(kind + payload) & 0xFFFFFFFF
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
    return width, height, palette, data[pixels_offset : pixels_offset + width * height]


def definition(source: Path, weapon: str) -> tuple[str, int, int, int, int]:
    lines = (source / f"weapon_{weapon}.txt").read_text(errors="replace").splitlines()
    for line in lines:
        parts = re.split(r"\s+", line.strip())
        if len(parts) == 7 and parts[0] == "weapon_s" and parts[1] == "640":
            return parts[2], *(int(value) for value in parts[3:])
    raise ValueError(f"No 640px selected HUD sprite for {weapon}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to cstrike/sprites")
    parser.add_argument("output", type=Path, help="Output directory")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    sheets: dict[str, tuple[int, int, list[tuple[int, int, int]], bytes]] = {}
    for weapon in WEAPONS:
        sheet, x, y, width, height = definition(args.source, weapon)
        if sheet not in sheets:
            sheets[sheet] = read_sprite(args.source / f"{sheet}.spr")
        sheet_width, sheet_height, palette, pixels = sheets[sheet]
        if x + width > sheet_width or y + height > sheet_height:
            raise ValueError(f"Crop outside {sheet}.spr for {weapon}")
        rgba = bytearray()
        for row in range(y, y + height):
            for column in range(x, x + width):
                red, green, blue = palette[pixels[row * sheet_width + column]]
                # GoldSrc renders these sheets additively. Their nominally black
                # background contains low-value dithering rather than an alpha
                # channel, so remove that floor and rescale the remaining edge
                # coverage into a browser-friendly mask.
                brightness = max(red, green, blue)
                alpha = max(0, min(255, round((brightness - 34) * 255 / 221)))
                rgba.extend((255, 255, 255, alpha))
        write_png(args.output / f"{weapon}.png", width, height, bytes(rgba))

    print(f"Extracted {len(WEAPONS)} official HUD silhouettes to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
