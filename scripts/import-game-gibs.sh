#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

cargo build --quiet --manifest-path shared/goldsrc-crate/Cargo.toml --bin godot_mdl
exporter="$repo_root/shared/goldsrc-crate/target/debug/godot_mdl"

# Static GoldSrc gib models used by TE_BREAKMODEL and stock Counter-Strike
# maps. Keep source basenames stable so runtime descriptors map directly to a
# generated asset without aliases or placeholder geometry.
gibs=(
  ceilinggibs
  cindergibs
  computergibs
  fleshgibs
  glassgibs
  metalplategibs
  mil_crategibs
  woodgibs
)

for gib in "${gibs[@]}"; do
  source_model="shared/goldsrc-assets/models/classic/${gib}.mdl"
  if [[ ! -f "$source_model" ]]; then
    printf 'Missing required stock gib model: %s\n' "$source_model" >&2
    exit 1
  fi
  "$exporter" \
    --body-variants \
    "$source_model" \
    "game/generated/gibs/$gib"
done
