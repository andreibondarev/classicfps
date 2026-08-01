#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

cargo build --quiet --release --manifest-path crate/Cargo.toml --bin godot_mdl
exporter="$repo_root/crate/target/release/godot_mdl"

skins=(terror leet arctic guerilla urban gsg9 sas gign)
for skin in "${skins[@]}"; do
  "$exporter" \
    --animated \
    "public/models/player/$skin/$skin.mdl" \
    "game/generated/players/$skin"
done

# Body poses must come from the same weapon activity family the attached p_
# model was baked with, or the gun detaches from the hands (a pistol posed on
# ref_*_onehanded floating beside a body playing ref_*_ak47). Bake the family
# variants bot loadouts actually equip. There is deliberately no ak47 family:
# the stock ref_aim_ak47/ref_shoot_ak47 tapes pose the torso off the gait
# facing, so the AK borrows the carbine family (see attached_weapon_family in
# crate/src/mdl.rs); ak47 stays the base players/ export.
families=(onehanded carbine mp5 rifle shotgun m249 knife grenade dualpistols)
for family in "${families[@]}"; do
  for skin in "${skins[@]}"; do
    "$exporter" \
      --animated-family \
      "$family" \
      "public/models/player/$skin/$skin.mdl" \
      "game/generated/player_action_families/$family/$skin"
  done
done

# Bomb planting has its own long source-authored player activity family. Export
# matching body tapes so the player skin and p_c4 share the exact same poses.
terrorist_skins=(terror leet arctic guerilla)
for skin in "${terrorist_skins[@]}"; do
  "$exporter" \
    --animated-family \
    c4 \
    "public/models/player/$skin/$skin.mdl" \
    "game/generated/player_action_families/c4/$skin"
done

"$exporter" \
  --attached \
  public/models/player/terror/terror.mdl \
  public/models/weapons/p_ak47.mdl \
  game/generated/player_weapons/ak47
