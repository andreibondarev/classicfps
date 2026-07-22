# CS 1.6 Demo Player

A browser-based Counter-Strike 1.6 replay player. A Rust/WebAssembly parser
turns GoldSrc `.dem` recordings into a deterministic timeline; Three.js renders
textured BSP maps, studio models, first-person viewmodels, effects, and replay
UI.

## Current capabilities

- Protocol 47/48-style HLTV and POV demo parsing
- Deterministic interpolation and direct seeking
- Textured BSP v30 maps with external WAD fallback and sampled lightmaps
- GoldSrc player, attached weapon, world-object, and first-person MDL models
- Original model sequences, locomotion, discrete actions, and death poses
- Recorded POV camera, HUD, observer mode, FOV, weapon animations, and fades
- Clearly labeled reconstructed first-person views for HLTV players
- Grenades, dropped equipment, C4, smoke, flashes, impacts, blood, and decals
- Positional recorded audio with GoldSrc entity/channel replacement
- Radar, scoreboard, economy, kill feed, round timer, event navigation, and chat
- Free camera, player follow, kill camera, automatic director, and replay studio
- Bookmarks, timestamp sharing, screenshots, and short WebM capture
- Replay diagnostics, checksums, data-coverage inspection, and missing-asset UI
- Adaptive render quality and authentic/cinematic interpolation modes

## POV fidelity

The UI distinguishes the source of every first-person camera:

- **Recorded POV** uses the full-rate recorder camera and recorder-local HUD
  tracks when the demo contains them.
- **Reconstructed POV** uses server-observed entity origins, angles, stance,
  weapon state, shots, and animation sequences.

HLTV recordings do not contain every player's private client prediction,
mouse input, punch angle, or HUD state. Reconstructed views are therefore
high-fidelity spectator views, not claims of forensically exact client output.

## Architecture

```text
crate/src/
  demo.rs        demo framing and timeline construction
  netmsg.rs      SVC/user-message and entity stream parsing
  events.rs      kills, rounds, HUD, observer, audio, and effects
  bsp.rs         BSP/WAD geometry, textures, and light sampling
  mdl.rs         studio-model geometry, sequences, and weapon bonemerge
  lib.rs         WebAssembly transfer boundary

src/
  index.ts       replay application, renderer, cameras, audio, and UI state
  wasm.ts        typed WASM interface and timeline interpolation
  replayVerifier.ts deterministic replay and seek-equivalence verification

scripts/
  corpus-regression.py   complete demo compatibility suite
  fidelity-regression.py deterministic visual/structural checkpoints
```

The files under `src/parser`, `src/renderer`, `src/bsp`, and `src/state` are
legacy TypeScript implementations retained for reference. The shipped player
uses the Rust/WASM parser and the application in `src/index.ts`.

## Validation

The bundled compatibility corpus currently contains 46 recordings across
`de_dust2`, `de_inferno`, `de_nuke`, `de_train`, and `de_aztec`. The suite also
contains two intentionally invalid recordings whose verification failures are
expected and asserted.

```bash
npm run build
npm run test:fidelity
npm run test:corpus
```

The visual suite checks stable nuke HLTV, professional aztec, and recorded
inferno POV checkpoints. It compares downsampled rendered pixels and asserts:

- finite camera and mesh transforms
- deterministic replay verification
- correct recorded/reconstructed POV provenance
- loaded BSP geometry and stable map identity
- no visible fallback cylinders or direction cones

Update baselines only after visually reviewing generated screenshots:

```bash
venv/bin/python scripts/fidelity-regression.py --update --screenshots
```

The corpus suite supports CI sharding:

```bash
npm run test:corpus -- --shard-index 0 --shard-count 2
npm run test:corpus -- --shard-index 1 --shard-count 2 --port 5218
```

## Rebuilding the parser

```bash
cd crate
wasm-pack build --target web
cd ..
npm run build
```

The frontend imports the generated package from `crate/pkg`.

## Asset layout

Runtime assets are served from:

```text
public/maps/              BSP maps
public/wads/              WAD3 texture archives
public/models/player/     player studio models
public/models/weapons/    complete p_, v_, w_, and shield studio models
public/models/classic/    hostages, equipment effects, and stock map props
public/sounds/            recorded and fallback WAV sounds
```

Missing optional assets do not crash playback. The viewer displays an asset
status badge with the unavailable paths and continues with the best valid
fallback.

## Remaining format limits

- An HLTV demo cannot provide client-private state that was never recorded.
- Some custom mods use user messages, models, or entity classes outside the
  Counter-Strike registry and require additional mappings.
- Fully animated brush entities require their network entity state and BSP
  submodel geometry to both be present.
- Original game assets must be distributed or supplied under appropriate
  licensing terms.

These are input and distribution constraints rather than replay-timeline
correctness issues.
