# Shared GoldSrc inputs

Everything the game is converted from, plus the Rust crate that does the
converting.

| Path | What it is |
| --- | --- |
| `goldsrc-crate/` | Rust crate with the converters and the demo parser. See its [README](goldsrc-crate/README.md) |
| `goldsrc-assets/` | Original GoldSrc files, unmodified |
| `demos/` | `.dem` recordings used as parser regression fixtures |

## goldsrc-assets

| Folder | Contents | Read by |
| --- | --- | --- |
| `maps/` | `.bsp` maps | `game:import:dust2`, `:inferno`, `:assault` |
| `wads/` | Texture WADs referenced by the maps, plus `decals.wad` | Map importers, `scripts/import-game-vfx.sh` |
| `models/` | Player, weapon (`v_`, `p_`, `w_`), hostage, gib and effect `.mdl` files | `game:import:players`, `:weapons`, `:hostages`, `:gibs`, and the crate's tests |
| `sounds/` | The `cstrike/sound` tree and the Half-Life categories it inherits | `game:import:sounds` |
| `sprites/` | HUD and effect `.spr` sheets with their `hud.txt` layouts | `game:import:hud`, `scripts/import-game-vfx.sh` |
| `ui/` | VGUI layouts, schemes, menu text and fonts | `game:import:ui` |

The game never loads these files at runtime. Importers convert them into
`game/generated/` and `game/assets/`, and those outputs are what ship.

### Provenance

Most files were staged from Valve's Counter-Strike dedicated-server
distribution (SteamCMD app 90). Each folder's `ASSET-SOURCE.md` records
exactly what was taken and when, and several folders have a `manifest.json`
with SHA-256 hashes that the regression scripts check:

- `models/ASSET-SOURCE.md`, `models/effects/ASSET-SOURCE.md`
- `sounds/ASSET-SOURCE.md`
- `sprites/classic/ASSET-SOURCE.md`, `sprites/weapons/ASSET-SOURCE.md`
- `ui/classic/ASSET-SOURCE.md`
- `demos/SOURCES.md` (also covers `de_aztec.bsp` and the `de_prodigy` assets)

`ui/classic/` and `sprites/classic/` are byte-exact mirrors: `.gitattributes`
turns off line-ending conversion for them so the hashes keep matching. Do not
reformat those files.

### Licensing

These are Valve's assets and remain Valve content, as do the converted copies
under `game/generated/` and `game/assets/`. The repository's AGPL licence
applies to the code only.

## demos

Tracked demos are fixtures for `goldsrc-crate/tests/parse_native.rs`, which
parses each one and asserts on duration, entry counts, player names and
position bounds. `demos/SOURCES.md` lists where they came from.

`demos/corpus/` is a larger local-only set (over 1 GB) that the same test walks
if it exists. It is ignored by git; the tests pass without it.

The demos are third-party recordings and are not covered by the repository's
licence.
