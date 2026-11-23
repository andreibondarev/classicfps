#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

cargo build --quiet --manifest-path shared/goldsrc-crate/Cargo.toml --bin godot_mdl
exporter="$repo_root/shared/goldsrc-crate/target/debug/godot_mdl"

# The canonical CS 1.6 weapon surface. The same identifier is used by the
# gameplay catalog, v_ first-person model, p_ third-person model and generated
# Godot directory wherever Valve ships that model.
weapons=(
  p228
  glock18
  scout
  hegrenade
  xm1014
  c4
  mac10
  aug
  smokegrenade
  elite
  fiveseven
  ump45
  sg550
  galil
  famas
  usp
  awp
  mp5
  m249
  m3
  m4a1
  tmp
  g3sg1
  flashbang
  deagle
  sg552
  ak47
  p90
  knife
)

for weapon in "${weapons[@]}"; do
  view_model="shared/goldsrc-assets/models/weapons/v_${weapon}.mdl"
  player_model="shared/goldsrc-assets/models/weapons/p_${weapon}.mdl"

  if [[ ! -f "$view_model" ]]; then
    printf 'Missing required first-person model: %s\n' "$view_model" >&2
    exit 1
  fi

  # Viewmodels need their original sequence frames; a static first frame makes
  # firing, drawing and reloading look like a placeholder no matter how good
  # the surrounding renderer is.
  "$exporter" --animated "$view_model" "game/generated/weapons/$weapon"

  if [[ -f "$player_model" ]]; then
    "$exporter" \
      --attached \
      shared/goldsrc-assets/models/player/terror/terror.mdl \
      "$player_model" \
      "game/generated/player_weapons/$weapon"
  else
    printf 'No third-person model for %s; leaving it out of attached coverage\n' "$weapon"
  fi
done
