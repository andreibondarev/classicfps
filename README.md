# Classic FPS

A playable CS 1.6 remake built in Godot 4, with offline bot matches, a
dedicated server, and a browser build. The original GoldSrc maps, models and
sounds are converted into Godot content by a Rust crate that lives in this
repository.

Production runs at `classicfps.app`; see [deploy/README.md](deploy/README.md).

## Quick start

```bash
npm run game:run
```

This opens the Godot client. Click **Deploy** to play an offline 5v5 against
bots on Dust2. The converted maps, models and sounds are committed under
`game/generated/` and `game/assets/`, so there is no import step before the
first run.

```bash
npm run game:run -- -- --map=cs_assault   # hostage map
godot --path game -- --join=127.0.0.1     # join a server running locally
```

Controls, game rules and the multiplayer menus are described in
[game/README.md](game/README.md). The client log is written to
`/tmp/protocol47-game.log`.

## Requirements

| Tool | Needed for | Notes |
| --- | --- | --- |
| Godot 4.7.1 | Everything | `godot` must be on your `PATH` |
| Node.js | `npm run` scripts and the test runners | No npm dependencies to install |
| Rust (cargo) | Re-importing maps and models, crate tests | Not needed just to play |
| Python 3 venv at `venv/` | Asset regression scripts, HUD/UI importers, web voice test | Only third-party package is `playwright` |
| Godot export templates | `game:build:*` | macOS, Linux Server and Web presets |

Create the Python environment once:

```bash
python3 -m venv venv
venv/bin/pip install playwright
venv/bin/playwright install chromium
```

## Layout

| Path | What it is |
| --- | --- |
| `game/` | The Godot project: `scripts/` (GDScript), `scenes/`, `tests/`, `assets/`, `generated/` |
| `game/generated/` | Converter output: maps (`de_dust2`, `de_inferno`, `cs_assault`), players, weapons, effects. Committed; do not edit by hand |
| `scripts/` | Importers (`import-game-*`), test runners (`run-game-*.mjs`) and regression checks |
| `deploy/` | Dedicated server, Caddy, admin dashboard and systemd units |
| `docs/` | Parity spec, readiness checklist and audits; start at [docs/README.md](docs/README.md) |
| `shared/goldsrc-crate/` | Rust crate: BSP/WAD/MDL converters and the `.dem` parser. See its [README](shared/goldsrc-crate/README.md) |
| `shared/goldsrc-assets/` | Original GoldSrc files the importers read. See [shared/README.md](shared/README.md) |
| `shared/demos/` | Recorded demos replayed by the parser tests |

Every `npm run` command is run from the repository root.

## Common commands

### Check and test

```bash
npm run game:check            # load the project in the editor and quit; catches script errors
npm run game:test             # runner unit tests, then every headless suite
npm run game:test:movement    # one suite; see package.json for the full list
node scripts/run-game-tests.mjs game:test:ballistics   # one suite through the strict runner
```

The strict runner fails on script or resource errors even when Godot exits
zero, requires pass markers, and times out stuck suites. It writes
`game/artifacts/headless-test-report.json`. The full run takes a long time;
run the suites that cover what you changed while iterating.

`npm run game:test:rendered` and the `game:capture:*` scripts open a window and
need a GPU. `game:perf*` scripts measure frame times; their options are
documented in [game/README.md](game/README.md).

### Re-import original assets

Run these after changing a converter or adding source assets. Each one
rewrites part of `game/generated/` or `game/assets/`; commit the result.

```bash
npm run game:import:dust2       # also :inferno, :assault
npm run game:import:players
npm run game:import:weapons
npm run game:import:hostages
npm run game:import:gibs
npm run game:import:sounds
npm run game:import:hud         # also :hud:death
```

A clean import should leave `git status` empty. A diff means either the
converter changed or the source assets did.

### Build

```bash
npm run game:build:mac       # game/builds/, unsigned
npm run game:build:server    # Linux dedicated server
npm run game:build:web       # browser build with .br/.gz copies
```

Installing the server and web builds on the droplet is covered in
[deploy/README.md](deploy/README.md).

### Rust crate

```bash
cd shared/goldsrc-crate
cargo test --release            # about four minutes; replays every demo in shared/demos
```

## Related repository

The browser demo player (Three.js replay viewer for `.dem` files) moved to its
own repository, `classicfps-demo-player`, in November 2026. It carries its own
copy of the crate; the copy here is the one future replay work in the game
builds on.

## Licensing of bundled content

There is no licence file yet. `shared/goldsrc-assets/`, `game/assets/` and
`game/generated/` contain or are derived from Valve's Counter-Strike and
Half-Life content, and `shared/demos/` holds third-party recordings. Keep the
repository private while they are tracked. Details are in
[shared/README.md](shared/README.md).
