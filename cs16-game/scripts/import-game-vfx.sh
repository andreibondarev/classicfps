#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

venv/bin/python scripts/import-game-vfx.py \
  ../cs16-demo-player/public/sprites/classic \
  ../cs16-demo-player/public/wads/decals.wad \
  game/assets/vfx

cargo build --quiet --manifest-path ../shared/goldsrc-crate/Cargo.toml --bin godot_mdl
exporter="$repo_root/../shared/goldsrc-crate/target/debug/godot_mdl"
"$exporter" ../cs16-demo-player/public/models/effects/rshell.mdl game/generated/effects/rshell
"$exporter" ../cs16-demo-player/public/models/effects/pshell.mdl game/generated/effects/pshell
