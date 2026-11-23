# goldsrc-crate

Rust readers for GoldSrc file formats. The crate (package name
`cs16_demo_parser`) does two jobs:

1. **Converters for the game.** Two command-line binaries turn `.bsp` maps and
   `.mdl` models into the portable files under `game/generated/`.
2. **Demo parser.** Decodes `.dem` recordings (HLTV and first-person) into a
   timeline of player positions, events and objects. The game does not use
   this yet; it is the planned basis for a replay mode.

## Modules

| File | Purpose |
| --- | --- |
| `src/bsp.rs` | BSP v30 geometry, entities, lightmaps; WAD3 texture lumps |
| `src/mdl.rs` | Studio model v10: bones, meshes, textures, animation sequences, weapon bone-merge |
| `src/demo.rs` | Demo file framing and timeline construction |
| `src/netmsg.rs` | SVC network messages, delta-compressed entity updates |
| `src/delta.rs` | Delta field definitions received at signon |
| `src/entity.rs` | Entity state across updates |
| `src/events.rs` | User messages: kills, rounds, HUD, chat, shots |
| `src/bitreader.rs` | Bit-level reader for packed network data |
| `src/types.rs` | Timeline and event types |
| `src/lib.rs` | WASM entry points and native debug helpers |
| `src/bin/godot_bsp.rs` | Map converter |
| `src/bin/godot_mdl.rs` | Model converter |

## Converters

Normally run through `npm run game:import:*` from the repository root. Direct
use:

```bash
cargo run --release --bin godot_bsp -- <map.bsp> <output-directory> [texture.wad ...]

cargo run --release --bin godot_mdl -- <model.mdl> <output-directory>
cargo run --release --bin godot_mdl -- --animated <player.mdl> <output-directory>
cargo run --release --bin godot_mdl -- --animated-family <family> <player.mdl> <output-directory>
cargo run --release --bin godot_mdl -- --attached <player.mdl> <weapon.mdl> <output-directory>
cargo run --release --bin godot_mdl -- --body-variants <gibs.mdl> <output-directory>
```

`godot_bsp` writes `map.json`, TGA textures, entity metadata and world and
submodel geometry. `godot_mdl` writes meshes, textures and packed animation
streams (`.f32`, `.q16`). `--attached` bakes a third-person weapon through the
player's skeleton, because `p_` weapon models have no usable pose of their own.

## Tests

```bash
cargo test --release
cargo test --release --test parse_native -- --nocapture   # with parser diagnostics
DEMO_PATH=/path/to/file.dem cargo test --release --test parse_native parse_env_demo -- --nocapture
```

The unit tests are instant. `tests/parse_native.rs` takes about four minutes:
it parses every demo in `../demos` (and `../demos/corpus` if present) and every
model in `../goldsrc-assets/models`. `parse_env_demo` is for debugging one
demo by hand and does nothing unless `DEMO_PATH` is set.

Some unit tests in `src/mdl.rs` embed models from `../goldsrc-assets` with
`include_bytes!`, so the crate does not compile its tests without that folder.

## WASM build

`pkg/` holds a committed `wasm-pack` build of the parser. Nothing in this
repository loads it since the demo player moved to `classicfps-demo-player`,
which has its own copy of this crate and its own `pkg/`. To rebuild it here:

```bash
wasm-pack build --target web
```

## Format references

- coldemoplayer's `HalfLifeDemoParser.cs` and `BitBuffer.cs` for demo and
  network message layouts across protocol versions 43 to 48
- ReHLDS `sv_main.cpp` for server-info and delta description encoding

These are used as behaviour references. The code here is written against the
formats, not copied from those projects.
