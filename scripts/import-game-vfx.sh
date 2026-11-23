#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

venv/bin/python scripts/import-game-vfx.py \
  shared/goldsrc-assets/sprites/classic \
  shared/goldsrc-assets/wads/decals.wad \
  game/assets/vfx

cargo build --quiet --manifest-path shared/goldsrc-crate/Cargo.toml --bin godot_mdl
exporter="$repo_root/shared/goldsrc-crate/target/debug/godot_mdl"
"$exporter" shared/goldsrc-assets/models/effects/rshell.mdl game/generated/effects/rshell
"$exporter" shared/goldsrc-assets/models/effects/pshell.mdl game/generated/effects/pshell
