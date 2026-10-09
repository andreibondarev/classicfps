# CS 1.6 projects

Two projects that share one GoldSrc parsing crate:

| Folder | What it is | Start here |
| --- | --- | --- |
| [`cs16-demo-player/`](cs16-demo-player/DEVELOPMENT.md) | Browser replay viewer for CS 1.6 `.dem` recordings (Rust/WASM + Three.js) | `cd cs16-demo-player && npm install && npm run dev` |
| [`cs16-game/`](cs16-game/game/README.md) | Classic FPS, a playable Godot 4 CS 1.6 remake with a dedicated server | `cd cs16-game && npm run game:run` |
| [`shared/goldsrc-crate/`](shared/goldsrc-crate) | Rust crate: demo parser (built to WASM for the player) and BSP/WAD/MDL converters (used by the game's importers) | `cargo test --release` |

The game's asset importers read the original GoldSrc files from
`cs16-demo-player/public/`. Python tooling for both projects uses the
repo-root `venv/`.
