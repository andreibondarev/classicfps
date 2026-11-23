#!/usr/bin/env python3
"""Extract Counter-Strike's original 640px ammo-type HUD icons as PNG masks.

Each `weapon_<name>.txt` in cstrike/sprites names the 24x24 region of a HUD
sheet that shows the weapon's ammunition type. The region is written as
`ammo_<name>.png`, white with the same gamma-lifted alpha as the HUD counters.
"""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import re

_core_spec = importlib.util.spec_from_file_location(
    "extract_cs_hud_core", Path(__file__).with_name("extract-cs-hud-core.py")
)
core = importlib.util.module_from_spec(_core_spec)
_core_spec.loader.exec_module(core)


def ammo_region(definition: Path) -> tuple[str, int, int, int, int] | None:
    for line in definition.read_text(errors="replace").splitlines():
        parts = re.split(r"\s+", line.strip())
        if len(parts) == 7 and parts[0] == "ammo" and parts[1] == "640":
            return parts[2], int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6])
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to cstrike/sprites")
    parser.add_argument("output", type=Path, help="Output directory")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    sheets: dict[str, tuple[int, int, list[tuple[int, int, int]], bytes]] = {}
    count = 0
    for definition in sorted(args.source.glob("weapon_*.txt")):
        region = ammo_region(definition)
        if region is None:
            continue
        sheet, x, y, width, height = region
        if sheet not in sheets:
            sheets[sheet] = core.read_sprite(args.source / f"{sheet}.spr")
        sheet_width, sheet_height, palette, pixels = sheets[sheet]
        if x + width > sheet_width or y + height > sheet_height:
            raise ValueError(f"Crop outside {sheet}.spr for {definition.name}")
        rgba = bytearray()
        for row in range(y, y + height):
            for column in range(x, x + width):
                red, green, blue = palette[pixels[row * sheet_width + column]]
                alpha = round(255.0 * (max(red, green, blue) / 255.0) ** (1.0 / 2.2))
                rgba.extend((255, 255, 255, alpha))
        name = definition.stem.removeprefix("weapon_")
        core.write_png(args.output / f"ammo_{name}.png", width, height, bytes(rgba))
        count += 1
    print(f"Extracted {count} ammo HUD icons to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
