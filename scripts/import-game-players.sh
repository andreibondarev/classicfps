#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

cargo build --quiet --manifest-path crate/Cargo.toml --bin godot_mdl
exporter="$repo_root/crate/target/debug/godot_mdl"

skins=(terror leet arctic guerilla urban gsg9 sas gign)
for skin in "${skins[@]}"; do
  "$exporter" \
    --animated \
    "public/models/player/$skin/$skin.mdl" \
    "game/generated/players/$skin"
done

"$exporter" \
  --attached \
  public/models/player/terror/terror.mdl \
  public/models/weapons/p_ak47.mdl \
  game/generated/player_weapons/ak47
