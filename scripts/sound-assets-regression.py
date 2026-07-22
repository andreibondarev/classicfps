#!/usr/bin/env python3
"""Validate the checked-in classic Counter-Strike playback sound bundle."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOUNDS = ROOT / "public" / "sounds"
EXPECTED_WAVS = 808
REQUIRED = (
    "weapons/ak47-1.wav",
    "weapons/c4_plant.wav",
    "radio/bombpl.wav",
    "player/pl_step1.wav",
    "hostage/hos1.wav",
    "doors/doormove1.wav",
    "buttons/button1.wav",
    "ambience/wind1.wav",
    "plats/train_use1.wav",
)


def main() -> int:
    wavs = sorted(SOUNDS.rglob("*.wav"))
    issues: list[str] = []
    if len(wavs) != EXPECTED_WAVS:
        issues.append(f"expected {EXPECTED_WAVS} WAV files, found {len(wavs)}")
    for relative in REQUIRED:
        if not (SOUNDS / relative).is_file():
            issues.append(f"missing required sound: {relative}")
    for path in wavs:
        header = path.read_bytes()[:12]
        if len(header) < 12 or header[:4] != b"RIFF" or header[8:12] != b"WAVE":
            issues.append(f"invalid WAV header: {path.relative_to(SOUNDS)}")

    if issues:
        print("Sound asset regression: FAIL")
        for issue in issues[:25]:
            print(f"- {issue}")
        return 1
    print(f"Sound asset regression: PASS ({len(wavs)}/{EXPECTED_WAVS} WAV files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
