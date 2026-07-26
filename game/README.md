# Protocol 47

Protocol 47 is the playable native game built alongside the CS 1.6 replay
viewer. Godot owns the client, classic 100 Hz simulation, UI, audio, and rendering. The
existing Rust crate converts GoldSrc BSP and WAD data into portable game
content.

## Run

```bash
npm run game:run
```

Click **Deploy**, then use:

- `WASD` — movement
- `Shift` — walk silently
- `Space` — jump
- `Ctrl` — crouch
- Mouse — aim
- Left mouse — fire
- `1` / `2` / `3` / `4` — AK-47 / Desert Eagle / knife / HE grenade
- `E` — plant at an A/B site
- `R` — reload
- `Esc` — pause and release the mouse

During freeze time, `F1` buys AK ammunition, `F2` buys Desert Eagle
ammunition, `F3` buys armor, and `F4` buys an HE grenade.

The current release is an offline 5v5 Dust2 bomb scenario: the human player
and four T bots fight five CT bots. It includes GoldSrc-inspired
acceleration, friction and air control; 100 Hz fixed-step physics; the original
CS weapon models and sounds; rifle, pistol, knife and grenade combat; navigating
teammates and opponents; headshots and recoil; freeze/live/bomb/post phases; persistent score
and economy; planting at the original map sites; and a native HUD.

All bots use the original four Terrorist and four Counter-Terrorist player
skins with baked idle, run, crouch, fire, and death animation frames. Their
third-person AK-47 is bone-merged to the same GoldSrc player pose.

Pause exposes sensitivity, inverted aim, field of view, VSync, render quality,
master volume, high-contrast/scalable crosshair, and reduced camera motion.

All human and bot actors share the same `Combatant` health, armor, team, damage,
and elimination rules. A `HumanCombatController` translates local input into
commands while each `BotCombatController` supplies perception, navigation,
targeting, and fire commands to the same pawn boundary. This is also the seam
for future remote-player and replay controllers.

## Validate

```bash
npm run game:check
npm run game:test
npm run game:capture
```

The test suite separates deterministic combat checks from the real-map check.
It verifies the ten-combatant team roster, human/bot controller assignment,
friendly-fire rules, team elimination, camera, HUD, fixed tick rate, firing ray,
damage, weapon slots, grenade and bomb state, network input validation, all
Dust2 surfaces, solid-only collision, navigation mesh/pathing, and both teams'
map spawns.

## Rebuild the map

```bash
npm run game:import:dust2
npm run game:import:players
npm run game:import:weapons
npm run game:import:sounds
```

The Rust converter emits a versioned `map.json`, TGA textures, entity metadata,
and world/submodel geometry under `game/generated/de_dust2`. The companion MDL
converter emits the complete classic first-person weapon set under
`game/generated/weapons`, all stock team models under
`game/generated/players`, and bone-merged third-person weapons under
`game/generated/player_weapons`. Compact binary vertex frames
carry the original animation poses. Godot builds render surfaces, collision,
navigation, animated players, and viewmodels from those portable assets.
The sound importer mirrors the complete classic WAV library under
`game/assets/sounds/classic`, preserving its original ambient, button, debris,
hostage, material, player, radio and weapon channel hierarchy.

## Multiplayer foundation

The game defaults to offline play. Its ENet layer uses input sequence numbers,
server-side command sanitization, three channels, and 20 Hz authoritative
snapshots. Run a host or join a development server with:

```bash
godot --path game -- --host
godot --path game -- --join=127.0.0.1
```

The transport and authority boundary are implemented; spawning and reconciling
multiple human-controlled actors is the next networking milestone.

## Build for macOS

Install Godot 4.7.1 and its official macOS export template, then run:

```bash
npm run game:build:mac
```

The universal Apple Silicon/Intel release is written to
`game/builds/Protocol47.zip`. The build command also extracts that archive,
launches the packaged main scene headlessly, and rejects missing release-only
resources or script/load errors. It is intentionally unsigned; public
distribution requires a Developer ID signature, notarization, and the
appropriate rights to redistribute the original game assets.
