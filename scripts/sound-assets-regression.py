#!/usr/bin/env python3
"""Validate the checked-in classic Counter-Strike playback sound bundle."""

from __future__ import annotations

import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "shared" / "goldsrc-assets"
SOURCE_SOUNDS = ASSETS / "sounds"
GAME_SOUNDS = ROOT / "game" / "assets" / "sounds" / "classic"
EXPECTED_WAVS = 808
EXPECTED_WAV_BUNDLE_SHA256 = (
    "97fa9110932cf4b21f93f2498e2650712d73e551b59917ffe0ba0f538cff5363"
)
EXPECTED_METADATA_SHA256 = {
    "materials.txt": "0d35d708cb3737fc99caf50e41ae32680e197218d2a51488489ecb7561b3ab6c",
    "sentences.txt": "09d57cf3205db2203e23f08f46dcc25e032eb2fa47a05e48e2c257c4d261453a",
    "ASSET-SOURCE.md": "78639c6263c2cbd12ca49c3bdb965cd6636808919a08f5064accf8a9c23b4c4c",
}
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


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bundle_sha256(root: Path, wavs: list[Path]) -> str:
    """Pin both the relative names and the bytes of the complete WAV library."""
    digest = hashlib.sha256()
    for path in wavs:
        digest.update(sha256(path).encode())
        digest.update(b" ")
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(b"\n")
    return digest.hexdigest()


def main() -> int:
    issues: list[str] = []
    libraries = (("source", SOURCE_SOUNDS), ("Godot", GAME_SOUNDS))
    for label, sounds in libraries:
        wavs = sorted(sounds.rglob("*.wav"))
        if len(wavs) != EXPECTED_WAVS:
            issues.append(
                f"{label}: expected {EXPECTED_WAVS} WAV files, found {len(wavs)}"
            )
        for relative in REQUIRED:
            if not (sounds / relative).is_file():
                issues.append(f"{label}: missing required sound: {relative}")
        for path in wavs:
            header = path.read_bytes()[:12]
            if (
                len(header) < 12
                or header[:4] != b"RIFF"
                or header[8:12] != b"WAVE"
            ):
                issues.append(
                    f"{label}: invalid WAV header: {path.relative_to(sounds)}"
                )
        actual_bundle_hash = bundle_sha256(sounds, wavs)
        if actual_bundle_hash != EXPECTED_WAV_BUNDLE_SHA256:
            issues.append(
                f"{label}: WAV bundle SHA-256 {actual_bundle_hash} does not match "
                f"pinned App 90 bundle {EXPECTED_WAV_BUNDLE_SHA256}"
            )
        for relative, expected_hash in EXPECTED_METADATA_SHA256.items():
            metadata = sounds / relative
            if not metadata.is_file():
                issues.append(f"{label}: missing pinned metadata: {relative}")
                continue
            actual_hash = sha256(metadata)
            if actual_hash != expected_hash:
                issues.append(
                    f"{label}: {relative} SHA-256 {actual_hash} does not match "
                    f"pinned value {expected_hash}"
                )

    source_wavs = {
        path.relative_to(SOURCE_SOUNDS): path
        for path in SOURCE_SOUNDS.rglob("*.wav")
    }
    game_wavs = {
        path.relative_to(GAME_SOUNDS): path
        for path in GAME_SOUNDS.rglob("*.wav")
    }
    for relative in sorted(source_wavs.keys() | game_wavs.keys()):
        if relative not in source_wavs:
            issues.append(f"Godot-only WAV absent from App 90 mirror: {relative}")
        elif relative not in game_wavs:
            issues.append(f"App 90 WAV missing from Godot mirror: {relative}")
        elif sha256(source_wavs[relative]) != sha256(game_wavs[relative]):
            issues.append(f"Godot WAV differs from App 90 mirror: {relative}")

    if issues:
        print("Sound asset regression: FAIL")
        for issue in issues[:25]:
            print(f"- {issue}")
        return 1
    print(
        "Sound asset regression: PASS "
        f"({EXPECTED_WAVS} source + {EXPECTED_WAVS} Godot WAV files, "
        f"bundle SHA-256 {EXPECTED_WAV_BUNDLE_SHA256})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
