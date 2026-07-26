#!/usr/bin/env python3
"""Extract original GoldSrc combat sprites and decals for the Godot client."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zlib


SPRITES = (
    "muzzleflash1",
    "muzzleflash2",
    "muzzleflash3",
    "muzzleflash4",
    "rifle_smoke1",
    "rifle_smoke2",
    "rifle_smoke3",
    "pistol_smoke1",
    "pistol_smoke2",
    "fexplo",
    "eexplo",
    "steam1",
    "richo1",
    "blood",
    "bloodspray",
)
DECALS = (
    "{shot1",
    "{shot2",
    "{shot3",
    "{shot4",
    "{shot5",
    "{scorch1",
    "{scorch2",
    "{blood1",
    "{blood2",
    "{blood3",
    "{blood4",
    "{blood5",
    "{blood6",
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
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(rows, 9))
        + png_chunk(b"IEND", b"")
    )


def safe_name(name: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9_-]+", "_", name.lstrip("{")).strip("_")
    return cleaned.lower() or "asset"


def sprite_rgba(
    pixels: bytes,
    palette: list[tuple[int, int, int]],
    texture_format: int,
) -> bytes:
    rgba = bytearray()
    key_color = palette[-1] if palette else (255, 255, 255)
    for palette_index in pixels:
        red, green, blue = palette[min(palette_index, len(palette) - 1)]
        if texture_format == 2:  # SPR_INDEXALPHA
            red, green, blue = key_color
            alpha = palette_index
        elif texture_format == 3:  # SPR_ALPHTEST
            alpha = 0 if palette_index == 255 else 255
        else:
            # SPR_NORMAL and SPR_ADDITIVE retain their original palette. The
            # renderer applies additive blending for format 1, where black is
            # naturally transparent.
            alpha = 255
        rgba.extend((red, green, blue, alpha))
    return bytes(rgba)


def parse_single_frame(data: bytes, offset: int) -> tuple[dict, int]:
    origin_x, origin_y, width, height = struct.unpack_from("<iiii", data, offset)
    pixel_offset = offset + 16
    pixel_count = width * height
    pixels = data[pixel_offset : pixel_offset + pixel_count]
    if len(pixels) != pixel_count:
        raise ValueError("sprite frame extends past source file")
    return {
        "origin_x": origin_x,
        "origin_y": origin_y,
        "width": width,
        "height": height,
        "pixels": pixels,
    }, pixel_offset + pixel_count


def extract_sprite(source: Path, output_root: Path) -> dict:
    data = source.read_bytes()
    if len(data) < 42 or data[:4] != b"IDSP":
        raise ValueError(f"Invalid GoldSrc sprite: {source}")
    (
        version,
        orientation,
        texture_format,
        bounding_radius,
        max_width,
        max_height,
        frame_count,
        beam_length,
        sync_type,
    ) = struct.unpack_from("<iiifiiifi", data, 4)
    if version != 2:
        raise ValueError(f"Unsupported sprite version {version}: {source}")
    palette_count = struct.unpack_from("<H", data, 40)[0]
    palette_offset = 42
    palette = [
        tuple(data[palette_offset + index * 3 : palette_offset + index * 3 + 3])
        for index in range(palette_count)
    ]
    offset = palette_offset + palette_count * 3
    frames: list[dict] = []
    intervals: list[float] = []
    while len(frames) < frame_count:
        frame_type = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        if frame_type == 0:
            frame, offset = parse_single_frame(data, offset)
            frames.append(frame)
            intervals.append(0.0)
            continue
        if frame_type != 1:
            raise ValueError(f"Unsupported frame type {frame_type}: {source}")
        grouped_count = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        grouped_intervals = list(
            struct.unpack_from(f"<{grouped_count}f", data, offset)
        )
        offset += grouped_count * 4
        for interval in grouped_intervals:
            frame, offset = parse_single_frame(data, offset)
            frames.append(frame)
            intervals.append(interval)

    sprite_directory = output_root / "sprites" / source.stem
    frame_paths: list[str] = []
    frame_metadata: list[dict] = []
    for index, frame in enumerate(frames):
        filename = f"{index:02}.png"
        write_png(
            sprite_directory / filename,
            frame["width"],
            frame["height"],
            sprite_rgba(frame["pixels"], palette, texture_format),
        )
        relative_path = f"sprites/{source.stem}/{filename}"
        frame_paths.append(relative_path)
        frame_metadata.append(
            {
                "texture": relative_path,
                "origin_x": frame["origin_x"],
                "origin_y": frame["origin_y"],
                "width": frame["width"],
                "height": frame["height"],
            }
        )
    return {
        "name": source.stem,
        "source_sha256": hashlib.sha256(data).hexdigest(),
        "orientation": orientation,
        "texture_format": texture_format,
        "bounding_radius": bounding_radius,
        "max_width": max_width,
        "max_height": max_height,
        "beam_length": beam_length,
        "sync_type": sync_type,
        "intervals": intervals,
        "frames": frame_paths,
        # GoldSrc registers every frame with its authored upper-left origin.
        # Retain this even when a particular sprite happens to be centered.
        "frame_metadata": frame_metadata,
    }


def wad_lumps(data: bytes) -> dict[str, bytes]:
    if len(data) < 12 or data[:4] != b"WAD3":
        raise ValueError("Invalid WAD3 source")
    lump_count, directory_offset = struct.unpack_from("<ii", data, 4)
    result: dict[str, bytes] = {}
    for index in range(lump_count):
        offset = directory_offset + index * 32
        file_position, disk_size, _, entry_type, compression = struct.unpack_from(
            "<iiiBB", data, offset
        )
        name = data[offset + 16 : offset + 32].split(b"\0", 1)[0].decode("latin1")
        if entry_type != 0x43 or compression != 0:
            continue
        result[name.lower()] = data[file_position : file_position + disk_size]
    return result


def extract_decal(name: str, lump: bytes, output_root: Path) -> dict:
    source_name = lump[:16].split(b"\0", 1)[0].decode("latin1")
    width, height, mip0, _, _, mip3 = struct.unpack_from("<iiiiii", lump, 16)
    pixels = lump[mip0 : mip0 + width * height]
    palette_offset = mip3 + max(1, width * height // 64)
    palette_count = struct.unpack_from("<H", lump, palette_offset)[0]
    palette_bytes = lump[palette_offset + 2 : palette_offset + 2 + palette_count * 3]
    palette = [
        tuple(palette_bytes[index * 3 : index * 3 + 3])
        for index in range(palette_count)
    ]
    rgba = bytearray()
    for palette_index in pixels:
        red, green, blue = palette[min(palette_index, len(palette) - 1)]
        # GoldSrc decals retain their WAD palette RGB and modulate the lit
        # surface. White texels are the multiplicative identity; replacing
        # them with white-alpha loses the authored decal color.
        rgba.extend((red, green, blue, 255))
    filename = f"{safe_name(name)}.png"
    write_png(output_root / "decals" / filename, width, height, bytes(rgba))
    return {
        "name": source_name,
        "width": width,
        "height": height,
        "texture": f"decals/{filename}",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("sprite_source", type=Path)
    parser.add_argument("decal_wad", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()

    sprites = [
        extract_sprite(arguments.sprite_source / f"{name}.spr", arguments.output)
        for name in SPRITES
    ]
    lumps = wad_lumps(arguments.decal_wad.read_bytes())
    decals = []
    for name in DECALS:
        lump = lumps.get(name.lower())
        if lump is None:
            raise ValueError(f"Missing required decal {name}")
        decals.append(extract_decal(name, lump, arguments.output))

    manifest = {
        "format": "protocol47-goldsrc-vfx",
        "version": 1,
        "decal_wad_sha256": hashlib.sha256(
            arguments.decal_wad.read_bytes()
        ).hexdigest(),
        "sprites": {sprite["name"]: sprite for sprite in sprites},
        "decals": {safe_name(decal["name"]): decal for decal in decals},
    }
    arguments.output.mkdir(parents=True, exist_ok=True)
    (arguments.output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )
    print(
        f"Extracted {len(sprites)} original sprites and "
        f"{len(decals)} original decals to {arguments.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
