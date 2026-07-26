#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

source_root="public/sounds"
destination_root="game/assets/sounds/classic"

if [[ ! -d "$source_root" ]]; then
  printf 'Missing required classic sound library: %s\n' "$source_root" >&2
  exit 1
fi

mkdir -p "$destination_root"
cp -R "$source_root/." "$destination_root/"

source_count="$(find "$source_root" -type f -name '*.wav' | wc -l | tr -d ' ')"
destination_count="$(find "$destination_root" -type f -name '*.wav' | wc -l | tr -d ' ')"
if [[ "$source_count" != "$destination_count" ]]; then
  printf 'Sound import incomplete: expected %s WAV files, found %s\n' \
    "$source_count" \
    "$destination_count" >&2
  exit 1
fi

printf 'Imported %s classic sound assets\n' "$destination_count"
