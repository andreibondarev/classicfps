# Classic FPS

A playable Godot 4 CS 1.6 remake with a dedicated server, plus the GoldSrc
tooling it is built on.

| Folder | What it is | Start here |
| --- | --- | --- |
| [`cs16-game/`](cs16-game/game/README.md) | The game: Godot 4 client and dedicated server | `cd cs16-game && npm run game:run` |
| [`shared/goldsrc-crate/`](shared/goldsrc-crate) | Rust crate: demo parser and BSP/WAD/MDL converters (used by the game's importers) | `cargo test --release` |
| `shared/goldsrc-assets/` | Original GoldSrc maps, models, sounds, sprites, UI files and WADs the importers read | |
| `shared/demos/` | Demos the parser's regression tests replay (sources in `shared/demos/SOURCES.md`) | |

Python tooling uses the repo-root `venv/`.

The browser demo player that used to live here moved to its own repository,
`classicfps-demo-player`, in November 2026, with its own copy of the crate.
