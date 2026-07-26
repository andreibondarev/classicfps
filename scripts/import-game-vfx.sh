#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

venv/bin/python scripts/import-game-vfx.py \
  public/sprites/classic \
  public/wads/decals.wad \
  game/assets/vfx

cargo build --quiet --manifest-path crate/Cargo.toml --bin godot_mdl
exporter="$repo_root/crate/target/debug/godot_mdl"
"$exporter" public/models/effects/rshell.mdl game/generated/effects/rshell
"$exporter" public/models/effects/pshell.mdl game/generated/effects/pshell
