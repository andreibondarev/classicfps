# Classic FPS

Classic FPS is the playable native game built alongside the CS 1.6 replay
viewer. Godot owns the client, classic 100 Hz simulation, UI, audio, and rendering. The
shared Rust crate (`../shared/goldsrc-crate`) converts GoldSrc BSP, WAD and MDL
data into portable game content, reading the source assets from
`../shared/goldsrc-assets`. Run the `npm run game:*` commands from the
`cs16-game/` folder.

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
- Knife: left mouse slashes; right mouse stabs. M4A1/USP: right mouse attaches or removes the silencer.
- `1` / `2` / `3` / `4` — primary / pistol / knife / grenades
- `5` — equip carried C4; hold fire in a bomb site to plant
- `E` — use nearby objectives, hostages, doors, and buttons
- `B` — buy menu (while eligible, in a buy zone)
- `G` — drop the active weapon or C4
- `Tab` — scoreboard
- `R` — reload
- `T` — spray the bundled `@rushing_andrei` graffiti on a nearby flat static surface (10-second cooldown)
- `Esc` — open the menu and release the mouse (pauses offline play; online matches keep running)

During freeze time, `F1` buys an AK-47, `F2` buys a Desert Eagle,
`F3` buys armor and a helmet, and `F4` buys an HE grenade, subject to buy rules.

Spraypaint works offline and through the host-authoritative multiplayer path.
Stand within 1.28 world units of a flat wall/floor; doors, breakable brushes,
sky and unsupported edges are excluded. Up to 32 sprays persist until the next
round, with snapshot replication for late joiners. The current lean build has
one bundled spray, not an arbitrary-image upload system. Artwork and generation
prompt: [`assets/sprays/README.md`](assets/sprays/README.md).

The top-right kill feed uses the original weapon silhouettes and a separate
headshot icon. It records the damage weapon, so an HE kill still shows a grenade
after the thrower switches weapons. Rebuild those sprites with
`npm run game:import:hud:death`. Muted knife, silencer, and kill-feed regressions
are included in `npm run game:test:viewmodels`.

The game supports offline 5v5 matches on Dust2 (bomb scenario) and Assault
(hostage scenario), with team selection, buying, round economy, match endings,
and rematches. Launch Assault with `npm run game:run -- -- --map=cs_assault`.
It includes GoldSrc-inspired
acceleration, friction and air control; 100 Hz fixed-step physics; the original
CS weapon models and sounds; rifle, pistol, knife and grenade combat; navigating
teammates and opponents; headshots and recoil; freeze/live/bomb/post phases; persistent score
and economy; planting at the original map sites; and a native HUD.

Physics uses Jolt with unrounded collision hulls and ray face indices enabled
for material-dependent bullet/footstep behavior. Navigation shortcut checks
reject initial hull overlaps before sweeping, so contact with a floor cannot
cause the same world's later walls to be ignored. Adjacent navigation portals
still use the movement kernel's step/jump handling. The kernel retains a
separate GoldSrc 1/32-HU contact separation; it is not a complete BSP clip-hull
oracle, and the broader fidelity/release gates remain in
[`docs/production-readiness.md`](../docs/production-readiness.md).

All bots use the original four Terrorist and four Counter-Terrorist player
skins with baked idle, run, crouch, fire, and death animation frames. Their
third-person weapons are bone-merged to the same GoldSrc player pose.

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

The test suite runs headlessly and separates deterministic combat checks from the real-map check.
It verifies the ten-combatant team roster, human/bot controller assignment,
friendly-fire rules, team elimination, camera, HUD, fixed tick rate, firing ray,
damage, weapon slots, grenade and bomb state, network input validation, all
Dust2 surfaces, solid-only collision, navigation mesh/pathing, and both teams'
map spawns.

The strict runner rejects script/resource errors even if Godot exits with code
zero, requires pass markers, and times out stuck suites. It writes an audit
report to `game/artifacts/headless-test-report.json`. Run one suite through the
same guard with `node scripts/run-game-tests.mjs game:test:ballistics`; selected
suites write `headless-test-selected-report.json` without replacing the full report.

The full gate also includes `game:test:assault-traversal`: silent, from-spawn
hostage-rescue runs for both player-team selections, each capped at 18,000 ticks,
with normal movement and door collision.
Perception is blinded to isolate traversal from combat deaths; actors and
hostages are not moved into place. It requires all four physical rescues and
the resulting round end. Both selections now pass the focused checks; this
does not establish combat-enabled full-match or performance readiness. Run it alone
with `node scripts/run-game-tests.mjs game:test:assault-traversal`.
The hostage integration fixture also verifies that periodic route refreshes
and moving leaders cannot reset an in-progress authored navigation-link
crossing. It checks both directions, endpoint release, and ordinary/disabled/
one-way link exclusions. Traversal reports retain hostage route points and
requested/actual velocities to distinguish blocked movement from route pacing.

`game:test:bots` also checks bounded waits for auto-closing rotating doors and
a 10,000-tick normal-combat Assault entrance regression. This run keeps the
normal T spawn, Glock/knife inventory, freeze, door collision and bot combat.
It requires CT_Bot_05 to physically enter the warehouse, checks displacement,
and rejects door waits longer than six seconds. It is entrance-progress
coverage, not proof of full-match rescue completion or GPU smoothness.

The gate also checks the live benchmark's human-input driver with
`game:test:match-driver`. It follows the production hull-clear navigation route
from the normal CT spawn and jumps through the Assault warehouse entrance via
ordinary player commands. The test waits the normal freeze, disables attacks,
and checks jump impulses and per-tick displacement; it is navigation coverage,
not evidence of combat performance. The benchmark itself keeps combat enabled
and reports `local_combat_covered`, local shots, and driver jump/CPU counts.
Use `--live-match --ticks=12000 --require-local-combat` for combat benchmarks:
the final gate then fails if no local shots were recorded. Short navigation
probes may omit the requirement, but must not be reported as shooting coverage.
The same group also runs 24,000 normal-combat CT ticks. It requires local shots
and real sidestep/backoff inputs, rejects a continuous local blockage over
1,000 ticks, and checks intra-round displacement without counting normal spawns
as movement. It also rejects more than 1,000 idle ticks on an unfinished local
route, excluding freeze/death and active fire, reload or use. This catches both
an automated player pinning the warehouse queue and one silently issuing no input;
it does not require a CT victory or claim full-match rescue/GPU coverage.
The driver gives its normal jump attempt priority before recovering from a
sustained jam. The deliberately incomplete MR15 negative control remains required.
The group also kills the four CT teammates through normal damage and requires
the last human-controlled CT to collect and rescue all four Assault hostages
from the normal spawn. Attacks are disabled for this navigation/use test.
The driver emits real edge-triggered use input and maintains a stable rescue
destination; it does not update hostage ownership, positions, or rewards.
Its test-only planner aligns required traversal endpoints more tightly than
bot steering and keeps steering inside the corresponding approach band.
Freeze/death suppression, endpoint height/alignment, four human-credit rescues,
and per-tick displacement are checked. This is not combat or GPU evidence.
Live reports include `test_driver_solo_objective_commands` and
`test_driver_use_commands`; a zero count means that input path was not covered.

The audio suite checks listener position and existing-voice attenuation across
deployment, first-person, alternate-camera, death chase, target cycling,
intentional observation, no-target observation, and respawn on both maps.
Distance gain follows the active viewport camera. These checks are muted and
validate routing/level state, not PCM or stereo-panning fidelity.

`game:test:network` validates packet types, finite values, protocol/counter
bounds, replay rejection, accepted-input burst limits, held-input expiry and
disconnect/reconnect state. It also launches separate silent Godot host/client
processes bound only to loopback, with isolated settings and guarded deadlines.
Combat feedback now uses bounded host-only reliable events for gunshot/reload
animations, owner recoil, catalog audio, muzzle/shell and impact/blood effects,
and kill notices. Clients never run damage or weapon simulation for these events.
The combat fixture rejects duplicate, stale, wrong-life and malformed events;
the Dust2 world pair checks owner reload/cancel and remote firing/reload feedback.
Audio replication reuses existing host schedules (currently explicit player
reload sound stages cover AK/Deagle); it does not add missing per-weapon sounds.
Grenade replication, complete objective feedback and adverse-network/full-match
validation remain open. Both peers must run the same working-tree build.
The first pair exercises production RPC methods, including malformed packets
and fresh connection counters. A second `--human-simulation` pair binds a
validated remote peer to the real `PlayerController`: normal hull/friction
movement, freeze/look rules, pistol edge handling, server bullet damage/ammo,
effects and silent-input expiry are checked. The client observes movement via
production position snapshots. Only the target is staged; received transforms
do not move the pawn. The `--game-roster` pairs additionally load the actual Game
on both maps and verify pending-human joins, reconnects, fresh actor IDs, rematch,
host restart and scene teardown. Sound and objective ownership are explicitly
staged when checking departure cleanup. The staged human-objective fixture also
checks per-human C4 inventory, plant/defuse commands, full action durations,
input-expiry cancellation, movement locks and objective score in the actual host
Game. The world-use fixture adds two-human input/expiry, real Assault hostage
rewards, button/C4 selection, remote brush contacts/IDs and security-camera
ownership/timeout/cleanup. Remote camera state is not yet presented on clients.
The staged inventory fixture checks per-human gun drops/pickups, simultaneous
claims, reconnect identity, death drops/score/headshots and C4 corpse cleanup.
It exercises host pawn actions, not a reliable network drop protocol.
The separate real-map admission fixture calls the production host team/class
methods: one bot is replaced per entrant, class completion controls spawning,
late joins wait, and survivor/death loadouts, halftime, rematch and remote-teammate
spectating are checked on both maps. Separate `--game-admission` pairs now send
real reliable team/class requests from the client, validate owner-only replies,
and verify host spawning, duplicate/malformed rejection and fresh reconnect
identity. Action dispatch and pending client requests are bounded separately
from movement. The mandatory `--world` pairs additionally load the actual client
Game on both maps and check menu admission, replicated actors, movement, one
host-owned shot, HUD health/ammo, deaths, round reset and disconnect. Opponents
are stationary for these checks. The pairs also check weapon slots, grenade
cycling, Q/lastinv, replicated inventory and exact ammo after staged host grants,
plus C4 selection on Dust2. The Dust2 pair also purchases kevlar through the
existing B / Equipment menu, verifies the remote debit and replicated wallet,
and rejects an unaffordable direct request. The separate silent Dust2 buy fixture
checks both teams, ammo/armor/carry limits, replay rejection and per-human
zone/life/timer rules. Other staged inventory grants remain fixture setup.
Full-world replication, prediction, other
discrete actions and adverse-network coverage remain unfinished.

Audio and combat-effect diagnostic histories retain the latest 4,096 events;
they are bounded debugging snapshots, not complete replay recordings. Audio
signals still deliver every event. `total_effect_events` tracks the VFX total
since the last explicit history reset.

Character animation precomputes per-source-pose culling bounds when loading its
finite animation tapes. Interpolating those bounds (and enclosing both body/gait
layers) avoids rescanning every rendered vertex. Player gait follows the source
bone branches, including both legs after the spine in the skeleton's array.
Regenerated player exports provide `lower_body_mask` per vertex so complete
thighs/pelvis follow locomotion, rather than a fixed-height lower-body cutoff.
Legacy exports without this metadata retain the height-based fallback.
Foot grounding uses an exact cached minimum only for an unblended source frame;
interpolated grounding still scans the actual vertices, since the lowest vertex
can change between frames. The animation tests check containment, source-pose
parity, exact grounding, rendered pixels, and off-screen shadows.

For CPU-only firefight measurements without a window:

```bash
npm run game:perf:cpu -- --report=/tmp/firefight-cpu.json
```

These reports explicitly set `gpu_measured: false`; they cannot prove smooth
rendered gameplay. See [production readiness](../docs/production-readiness.md)
for the unresolved release requirements.

For rendered frame-time measurements, run this separately from the test suite
and other heavy workloads:

```bash
npm run game:perf -- --report=/tmp/firefight.json --capture=/tmp/firefight.png
```

This scripted ten-actor fixture reports startup/idle, initial and repeated
volleys, a cold weapon switch, and firing through smoke. It includes weapon
animations, audio, muzzle flashes, shell ejection, impacts, and smoke; movement
and AI decision-making are disabled to isolate combat presentation. The JSON
records frame-time percentiles, maximum frame time, and frames over 33 ms.
The cold-switch phase's `first_frame_ms` includes equipping, firing, and the
following rendered interval; `weapon_switch_cpu_ms` reports equipping alone.
It requires a rendered window and is not a substitute for a full-match playtest.
Both benchmark commands are silent and reject script errors or missing
completion markers. Loading/warmup is reported separately from the combat stages.
The GPU benchmark keeps its window on top and checks rendered-frame counts:
macOS can otherwise skip drawing covered windows while simulation continues,
making apparently fast results invalid. This affects only the benchmark window,
not normal gameplay settings.

Before rendered deployment, the finite weapon catalog also prepares the shaded
CPU geometry for frame zero of every animation (190 unique poses, ~32.8 MB of
packed arrays). Preparation yields between poses and retains no animated nodes
or material instances. Muzzle projection and lighting remain instance-specific;
later animation frames still use the bounded on-demand mesh cache. The viewmodel
suite verifies all prepared attributes against source-built meshes, material
identity, muzzle placement, repeatability, and release. Rendered checks compare
prepared M4/AK/knife poses with unprepared references and wrong-hand controls.

The separate, silent rendered-correctness gate checks presentation warmup and
an animated character fully outside the camera whose shadow falls on a visible receiver:

```bash
npm run game:test:rendered
# Process-local backend comparison; does not alter the game's default:
npm run game:test:rendered -- --renderer=mobile --driver=metal
```

The ten-fixture runner saves process exit codes, timeouts, errors, and completion
markers in `game/artifacts/render-test-<renderer>-<driver>-report.json` (omitted
overrides use `default`). Printing a fixture's pass marker is insufficient: its
process must also exit cleanly. Unknown or incompatible backend flags fail
before launch. Logs are separate for each requested renderer/driver pair.
The decal fixture renders shot, blood and scorch materials under three ambient
light levels with HDR2D both off and on. White-mask controls must leave the destination pixels unchanged;
authored marks must remain visible, and a deliberately double-lit negative
control must fail the pixel comparison. This is a compositing contract, not
an original-engine visual comparison or a performance benchmark.

The match-lifecycle fixture reaches halftime, a 16-win ending, death spectating,
and Enter-to-rematch through authoritative round events and real actor damage.
Its rendered mode checks actual draws at halftime, match end, and rematch;
captures are `/tmp/protocol47-lifecycle-<map>-<renderer>-<boundary>.png`.
The headless `npm run game:test:matches` matrix covers both maps, both starting
teams, and both 16-win and 15–15 endings (eight cases); it is included in the
full twenty-three-group headless gate. The tests check survivor gear in ordinary
rounds, fresh halftime/rematch loadouts, scores/accounts, alive/collision/control
state, camera restoration, old weapon/bomb cleanup, equipment/blindness resets,
and cleared HUD notices/effects. They deliberately shorten freeze/post delays
and disable actor navigation/firing, so they do not replace real full-match
gameplay/performance soaks. The rematch still waits its normal six-second freeze.

`npm run game:test:observers` additionally tests participant death spectating and
intentional Spectator selection on both maps. The observer fixture follows a
scripted 16-win match through halftime/rematch, checks non-participating actor
and roster state, both-team camera cycling, and joining CT during the new freeze.
Its rendered captures are `/tmp/protocol47-observer-<map>-<renderer>-<boundary>.png`.
The existing nine bots remain in their slots when the human observes; automatic
bot backfill and live mid-round team-changing rules are not covered by this test.
Chase observation hides the inactive local slot's combat HUD and viewmodel while
retaining match time, notices, and the watched player's name. With no living
target, the held camera still says `Spectating`. HUD geometry regressions cover
three resolutions, modal pause/resume, and restoration to first-person after
respawn; observer captures include a `no-target` boundary.

`npm run game:test:joins` checks the source-based enrollment/spawn rules and
the actual keyboard team/class path on both maps. During play, M opens team
selection; 0 or Escape cancels the team menu. A permitted selection can kill
the local participant, but must not restart scores/time or reset other actors.
Appearance selection cannot grant a second spawn in the same round. New early
entrants can spawn after choosing appearance; late entrants wait for the next
round. Auto-assignment uses roster counts, scores and capacity, with the HUD
showing the accepted team's classes. These fixtures also cover menu input,
next-round collision/camera restoration, and unchanged bot health/ammo/positions.
The rendered gate includes a draw-verified live-menu capture; this is lifecycle
correctness coverage, not a full-match performance measurement.
Reopening an unfinished join resumes its class choice; a pending appearance
also follows the authoritative team if halftime occurs before submission.

The BSP color fixture compares 26 opaque/masked material cases against independent
CPU color values, including saturated channels and black/near-black/endpoints.
Each capture must draw. On Compatibility, a legacy-shader comparison must remain
unchanged; on Metal, the same legacy shader is a negative control for the former
color-space bug. Reports are `game/artifacts/bsp-color-<renderer>-report.json`.
Both shaders now evaluate the authored WAD/lightmap response in encoded space,
converting only the final result for linear-output renderers. Engine framebuffer
conversion can still differ near black. These checks establish the material
contract, not pixel parity with original CS 1.6 or a backend-wide fidelity claim.

The pose-sampler fixture compares the production mesh builder against the old
scalar calculation for a blended body/gait, attached weapon, and hostage pose.
It checks both initial surfaces and vertex-region updates, with stale-pose
negative controls. The character suite also checks 9.37 million vertex samples,
surface offsets, overlay masks, and the portable scalar-construction fallback.
Fused body/gait composition must also remain bit-identical to the preceding
two-pass vector sampler, independently of the scalar-reference tolerance.

The shadow fixture compares the optimized pose's shadow pixels with unconditional animation,
requires visible shadow motion, and verifies that a frozen-pose negative control
fails the comparison. The report is `game/artifacts/shadow-render-test-report.json`;
before/after captures are `/tmp/protocol47-shadow-{before,after}.png`. Offscreen
pose skipping now accounts for shadow-enabled lights in the same world, their
caster masks, directional shadow paths, and positional-light influence ranges.
It does not disable shadows or pause authoritative animation clocks.
The effects regression also checks that loading preserves the displayed camera,
retires staging viewports, and retains a hidden, inactive planted-C4 shader owner
without gameplay collision or lighting; scene teardown must release that owner.
The viewmodel residency regression compares restored weapons against original
and freshly constructed presentations, including a lighting change and a stale-
tint negative control. Its report is `game/artifacts/viewmodel-residency-render-report.json`.

For a moving match with normal bot AI, health, ammo, objectives, and round
logic (the local player's intent is automated through its normal controller):

```bash
npm run game:perf -- --live-match --report=/tmp/live-match.json --capture=/tmp/live-match.png
```

The default is 1,800 frames. The report verifies actual actor travel and combat
events, and records test-driver cost separately. This is a live-match sample,
not a complete-match or long-soak release gate. `--cpu-only` is also supported.
Select a supported map with `--map=de_dust2|cs_assault` and the local player's
starting team with `--team=T|CT` (live fixture only). For example:

```bash
npm run game:perf -- --live-match --map=cs_assault --team=CT --ticks=12000 --report=/tmp/assault-ct.json
```

Team selection uses the normal team/class-selection path before measurement.
Reports include final actor teams/alive states/positions, round-end events, and
the hostage state and current-round hostage events. Bot name prefixes can differ
from their actual team after selection; use the `team` field. Activity-check
success is not proof of objective completion or passing frame-time budgets.
`bot_navigation_final` reads existing route/obstruction state without issuing
new path queries; it includes the next five route points for diagnosing stalls.

Rendered deployment prepares the finite bot purchase presentations for both
possible sides, plus bomb-carrier poses on bomb maps. Candidate weapons come
from the buy planner and the actual roster's sniper roles. Only source templates
are retained; preparation does not equip weapons or create extra actor meshes.
The live report's `bot_asset_preparation` records loading slices, new templates,
elapsed loading time, and static-memory growth. Headless correctness tests skip
automatic preparation; the character suite tests it explicitly, including
idempotence, unchanged actor state, and cache release.

For comparable simulation duration, use `--ticks=3000` instead of `--frames`:

```bash
npm run game:perf -- --live-match --ticks=3000 --report=/tmp/live-30-seconds.json
```

At the game's 100 Hz physics rate this samples 30 simulated seconds, recording
as many render frames as occur. A sample ends at the next render boundary, so the
report includes actual physics ticks (which can slightly exceed the target).
The normal supported range is 300–12,000 ticks; short runs may fail the activity check
if combat has not started. Inspect effect counts and match state as well as frame
percentiles. Tick count and render-frame count options are mutually exclusive.
Live reports also include `frame_windows`: 100-physics-tick windows with frame
percentiles, effect counts, and living-actor ranges. Frames are assigned by their
ending tick, with no invented samples for empty windows. Inspect these windows
to avoid hiding a slow active opening behind a long, inexpensive idle period.
The performance runner first requires a silent metrics regression to pass.

For a complete live-match attempt, explicitly add `--full-match`:

```bash
npm run game:perf:cpu -- --live-match --full-match --map=cs_assault --team=CT --report=/tmp/full-match-cpu.json
```

This mode starts with the normal team pistol and initial freeze, without the
short benchmark's granted AK. It stops at match completion or a hard tick limit
(default/maximum 1,068,030 ticks: approximately 178 simulated minutes;
override with `--ticks`). This bound covers all 30 rounds at the production
freeze, five-minute round, late-plant C4 and post-round limits, with a
one-tick-per-round allowance. Most matches should finish much earlier.
The wall-clock deadline scales with that limit plus startup/shutdown allowance.
Success requires local shots, one halftime and match-end event, and a consistent
MR15 final score/round count; reaching the tick cap alone is failure. Render
exclusions and frame-count limits are rejected. A full GPU run uses the same
options with `game:perf` instead of `game:perf:cpu`, and must run separately from
other test jobs. Headless completion is not GPU smoothness evidence.
For a timing-enforced full GPU match (still silent), use:

```bash
npm run game:perf:full-match -- --map=cs_assault --team=CT --report=/tmp/full-match-gl.json
```

This adds `--require-smoothness`: only after clean checked process completion,
the wrapper audits its fresh report. Both overall and every nonempty
100-physics-tick window must meet p95 ≤16.7 ms and p99 ≤25 ms at 1280×720.
Any live interval above 50 ms requires review and fails this conservative gate,
even outside combat; no initial/live-transition intervals or isolated hitches
are discarded. Loading is reported separately. Missing/inconsistent metrics,
draw coverage, incomplete matches, instrumented runs and render exclusions fail.
Report paths supplied to the wrapper are resolved relative to the repository
root before Godot starts. Diagnostics can still use `game:perf` without this
flag, whose existing pass marker means measurement/activity coverage only.

An existing artifact can be checked without starting Godot:

```bash
npm run game:perf:audit -- /tmp/full-match-gl.json
```

The artifact-only command does not establish a clean process exit, hardware
identity, workload isolation or freshness. Neither command proves all-map/team,
weapon/grenade, rematch, multiplayer or release coverage from one match.
The normal correctness gate runs only a bounded three-second negative control,
which must reject an incomplete match while preserving the pistol/freeze rules.
Static-memory reports include retained benchmark frame samples, so growth is
not by itself evidence of a game-memory leak. Full-match attempts are not part
of the default correctness gate.
The report also timestamps local shots, deaths/respawns, and bomb-state changes;
each bomb transition includes its frame time and the next three frame times.
The live gate also rejects bots that activate or move during observed freeze
frames; reports include `freeze_observations` and `freeze_control_violations`.
Both performance fixtures record `physics_engine` and `physics_space_class`;
the latter identifies the actual backend when the project setting is `DEFAULT`.
Backend probes must pass collision, material-hit, and movement checks before
their timings can support a production configuration change.

For investigation only, `--diagnostic-hide=world_drops|corpse_models|viewmodel|effect_lights|muzzle_smoke|map`
hides one presentation category while leaving normal simulation active. Use one
value, with `--live-match`. The stationary fixture additionally accepts
`--diagnostic-hide=effect_lights` only, preserving light creation/lifetimes while
excluding them from rendering. These exclusions are explicitly recorded and never
enabled by default; reduced-presentation results do not prove production
smoothness. Mark profiler-attached runs with `--instrumented` and obtain clean
uninstrumented measurements separately.
`--profile-phases` adds bounded CPU timings for actor reset, round buying, phase
application, slow game-tick/round-event handling, and bot decisions taking at
least 2 ms (up to 256 records per bot). Bot records include route time and
full-body sweep time/count; these are nested timings, not additive categories.
`hostage_cpu_totals` records call counts, total microseconds, and maximum cost
for hostage advancement and contract synchronization. Advancement includes
synchronization; these totals are also nested, not additive.
They also include total swept distance and the slowest individual sweep's
duration/distance, to distinguish many cheap checks from one expensive cast.
Exact same-tick repeated sweeps and their measured CPU time are also counted
across bots. Every query still executes; the profiler does not cache answers.
It automatically marks the report instrumented and uses test-only subclasses
that call the production methods. Its `engine_physics_tick` values are absolute; subtract the report's
`physics_tick_origin` to align them with the sampled event timestamps.

Hostage presentation skips only offscreen mesh deformation, not the 100 Hz
animation/action clock. Visibility uses an envelope of all authored poses,
including grounding and affine ancestor transforms, and all active same-world
cameras (including shared-world SubViewports). Enabling hostage shadows fails
open to unconditional updates. Equivalent skin assignments no longer resubmit
poses. The character suite checks clocks, bounds, skin reloads, cameras, and
masks; the rendered suite additionally compares reentry pixels with forced
rendering and a deliberately stale negative control.

Renderer comparisons can explicitly override the benchmark process without
changing the project's default renderer. For example, on a supported Mac:

```bash
npm run game:perf -- --renderer=mobile --driver=metal --report=/tmp/firefight-metal.json
```

Use the stationary fixture for matched volley counts and `--live-match --ticks`
for matched simulation duration. The default fixed-frame live fixture can cover
different simulated durations on faster renderers, so its percentiles alone
are not an equal-workload comparison. Renderer/driver overrides
are validated and rejected for CPU-only runs; rendering and silence guards remain.

For cross-backend collision diagnostics, the navigation fixture can write the
same 1,000-query grid's endpoint fingerprint, clearance bytes, and sweep CPU time:

```bash
godot --headless --audio-driver Dummy --path game --script res://tests/navigation_projection_test.gd -- --map=de_dust2 --clearance-report=/tmp/navigation-clearance.json
```

Use the strict test runner's `runCheckedCommand` when automating this command;
Godot may exit zero after a script error. The default navigation gate requires
both blocked and clear outcomes and compares each result with an initial-overlap
check followed by a full-hull cast on the current backend. Passing it alone does not establish parity with another
backend; compare the optional reports with identical endpoint fingerprints.

Before deployment, rendered games prepare the finite 29-weapon catalog and
bot navigation graphs, and draw the player's starting view into an offscreen
viewport without changing the visible deployment camera. Effect and planted-C4
shader variants are drawn during loading too. Warmup viewports are retired
before gameplay is enabled; one hidden, process-disabled C4 visual retains its
shader resources without adding a gameplay bomb. This trades bounded resident asset memory and loading
time for eliminating cold animation-file reads and texture conversion on pickups
and weapon switches. Headless correctness fixtures skip presentation preparation;
the catalog preparation contract is tested separately.
Each viewmodel additionally retains up to three inactive, hidden weapon models
in least-recently-used order, plus the active model. Each retains at most 256
cached animation-frame meshes. This avoids destroying/rebuilding recent guns
on switches or respawns; eviction and scene teardown release their nodes.
Materials stay instance-local, and restoration resets action and lighting state.

Navigation endpoint projection uses a bounding-volume hierarchy over the same
eligible polygon triangles. It retains exact triangle distance and lowest-ID tie
behavior; it does not approximate endpoints using polygon centers or change hull
clearance checks. Both imported maps have exhaustive-reference parity regressions.

## Remaining work

- Profile full moving 5v5 matches, cold loads, weapon switches, and sustained
  effects on target hardware. Animation caching and persistent GPU vertex
  buffers reduce allocation, but do not establish that all stutters are gone.
- Finish anatomical hitboxes and remaining weapon special cases. Per-weapon
  recoil/spread and crouched hit-group classification have been improved; see
  [the Dust2 combat audit](../docs/dust2-combat-audit.md) for tested behavior and
  limits. Movement colliders are still not the original animated hitboxes.
- Soak-test remote multiplayer and prediction/reconciliation under real network
  latency. Remote-human spawning and host/client gameplay are implemented;
  successful local transport tests do not establish remote-match reliability.
- Keep scope on Dust2; verify distributable builds, signing, and asset
  redistribution rights before release.

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

The current release effort is **Dust2 only**. Assault remains available in the
repository, but its development and benchmarks are deferred. Historical
multi-map checks below do not make other maps release requirements.

The game defaults to offline play. Its ENet layer uses input sequence numbers,
server-side command sanitization, three channels, and 20 Hz authoritative
snapshots. To connect from the game, press Escape (also available before
deployment), choose **New Game** to host Dust2, or **Find Servers** to enter a
host address and UDP port. This is a direct-connect form, not a server browser.
The default port is 27447. Both players need the same build and a reachable
host address; there is no matchmaking, relay or automatic port forwarding.
After hosting, go Back / Resume and select your team/class. A joining player
gets team selection after the first authoritative world arrives.

Connection failures retain the form for retry. **Return Offline** in the form
or **Disconnect** in the game menu closes the session and reloads a fresh
offline game, including AI and collision ownership. It abandons the current
match; settings are retained. Host/join cannot replace an active session
without that explicit disconnect. Connection and initial-world waits are
bounded to 10 and 15 seconds respectively.
Hostname resolution runs in the background within the connection deadline;
canceling or returning offline discards the pending lookup.

### Browser play

`npm run game:build:web` exports `game/builds/web` (Godot Web, single-threaded,
WebGL 2). A browser build joins the server that served the page at
`wss://<host>/ws`; `?server=<ws or wss URL>` joins another server, `?offline`
plays locally against bots, and `?perf` logs the frame rate to the browser
console. The dedicated server accepts browser clients over WebSocket on its UDP
port + 1 (`--ws-port=`, `--ws-bind=`) alongside desktop ENet clients, through
one combined multiplayer peer (`scripts/network_multi_peer.gd`).
`npm run game:test:dedicated` includes a probe that joins one UDP and one
WebSocket client to the same match. Deployment is in
[`../deploy/README.md`](../deploy/README.md).

Animated models ship as rigid bone tapes (manifest version 4): every GoldSrc
vertex follows one bone, so each pose stores one 3x4 transform per bone and
`scripts/mdl_rigid_skin.gd` rebuilds the vertex frames when a model loads. The
exporter (`godot_mdl`) refuses to write a model unless rebuilding reproduces
its baked frames within 2e-4 units (observed 6e-8). This cut the converted
assets from 1.8 GB to 315 MB.

The command-line hooks also remain available:

```bash
godot --path game -- --host
godot --path game -- --join=127.0.0.1
```

Transport validation and a server-side human input adapter are implemented.
The adapter requires explicit peer ownership binding and uses human movement
and weapon code, not bot simulation. Base input yaw/pitch are separated from
rendered recoil, so the server does not add punch a second time. The human
pawn now supports a pre-tree remote role with its own network controller,
third-person model and per-slot audio identity, without claiming the local camera
or using its keyboard/mouse or display settings. Ownership tests cover coexisting
local/remote pawns; the loopback fixture verifies remote movement/shooting while
the host pawn remains unchanged. The actual host Game now allocates unique slots
and durable actor IDs for connections, registers them as UNASSIGNED spectators,
and removes them on departure. Pending humans are hidden, non-solid and cannot
move or fire; connection alone does not bypass team/class admission. Reconnects
get fresh actor IDs, and rematches preserve connected identities.
Host team/class methods now admit humans into reserved 5v5 slots by replacing
bots, with real spawning and round/halftime/rematch lifecycle. Reliable client
team/class requests now connect the existing client menus to these methods and
return owner-only outcomes. A connected client stops offline round/AI/combat
simulation and displays host actor snapshots, health/ammo and round scores using
the existing map, models and HUD. Remote actors interpolate; owner movement now
uses the same movement/collision step as the host, with consumed-input
acknowledgments and bounded replay (25 commands / 250ms). It predicts map-solid
collisions only, never weapons, damage or objectives. Life changes, teleports,
death and stale updates clear or stop prediction. Dynamic-player collision
agreement, correction presentation and adverse-network match testing remain open.
Both peers must currently load the same map and use world schema version 7.
Owner-only inventory snapshots now carry weapons, ammunition, previous weapon,
equipment and mode flags. Normal slot keys, grenade cycling, Q/lastinv and C4's
slot 5 send reliable selections; the host checks ownership and switches through
the existing weapon code. Selection requests cannot grant weapons or ammo on the host.
Right-click and G also use reliable host-owned actions, with cooldown and held-
weapon checks. Host burst/zoom/silencer modes update the client HUD and camera;
gun/C4 drops and planted C4 now have source-model replicas on clients, without
client pickup/collision simulation. Stable IDs retain models across updates,
and host snapshots drive flight, planted countdowns and removal. Larger world
snapshots use bounded chunks and apply only when complete. Scope accuracy and
movement depend on weapon zoom state, not display FOV.
The existing B buy menu now submits reliable item-only requests. The host uses
the buyer's money, team, life, position, buy timer and normal grant/carry rules;
snapshots update that client's wallet, inventory and buy-zone availability.
Menu digits are isolated from weapon controls, and the displayed account and
disabled rows refresh when the authoritative wallet changes.
Online pause/options menus block only that user's gameplay input. The host's
round and remote pawns keep advancing, and client snapshots keep updating.
Offline pause suspends the gameplay subtree; the always-active HUD routes
resume/Quit input. Starting a host with the menu already open releases the
offline simulation pause without dismissing the menu.
The working tree now replicates firing/reload feedback, exact existing host
audio, impacts and kill notices. Grenade flight, HE/flash effects and aged smoke
are host-driven; clients display owner flash duration, planting/defusing
progress, and bomb/round results. Smoke reconstructs from a current snapshot
and clears on round reset. Reload presses use reliable actions. This is world
schema 7: restart both peers on the same updated source with `npm run game:run`.
Dust2 breakable visibility/collision now follows complete host snapshots, including
round reset. Grenade pin/throw actions use reliable presentation events; the
importer now includes the original grenade animation strips. Flash/smoke use
their own shipped detonation sounds. macOS Ctrl-crouch firing preserves physical
left/right mouse intent, and presentation loading no longer waits indefinitely
for an automatic draw in an occluded native window. See
`docs/production-readiness.md` for verified archive and test status.

Remote reassignment/backfill remains deliberately restricted. Player-collision
prediction, exact grenade timing parity, missing weapon-specific sounds,
adverse-network/full-match testing, smoothness
and shipping checks remain unfinished. Returning offline rebuilds the scene
instead of changing authority in place. These features are not release clearance.

Scope stays limited to Dust2, basic direct host/join, smoothness and
essential shipping checks—not accounts, matchmaking, rankings or extra modes.

## Build for macOS

Latest validated internal archive: `game/builds/Protocol47-validation-20260910.zip`.
It includes the September 10 crouch-fire, preparation, grenade and Dust2 brush
fixes. Its muted packaged-startup check passed; it is unsigned and not a public
release. Both multiplayer peers need the same updated schema-7 build/source.

Install Godot 4.7.1 and its official macOS export template, then run:

```bash
npm run game:build:mac
```

### Dedicated Dust2 server

Build the headless Linux server with:

```bash
npm run game:test:dedicated
npm run game:build:server
```

The resulting `game/builds/protocol47-server.x86_64` accepts ten remote
players and listens on UDP 27447. It starts a fresh 5v5 Dust2 match when the
first player connects, then restores the full bot roster after the last player
leaves.
Run it on Linux with:

```bash
./protocol47-server.x86_64 --headless --audio-driver Dummy -- --dedicated --port=27447
```

The production systemd unit lives at `deploy/protocol47.service`. The client
joins the server's public IPv4 address through **Play Online → Join**. The
host firewall must allow inbound UDP 27447; TCP 27447 is not used.

The universal Apple Silicon/Intel release is written to
`game/builds/ClassicFPS.zip`. The build command also extracts that archive,
launches the packaged main scene headlessly with the Dummy audio driver, and
rejects missing release-only resources, script/load errors, generic engine
errors, failure markers and leak warnings. Six offline checks for this guard
run before export; they can also be run with
`venv/bin/python scripts/test-export-package-regression.py`.
The packaged check requires a fresh-settings startup confirmation at an explicit
temporary `PROTOCOL47_SETTINGS_PATH`. The settings suite verifies fresh defaults,
cross-process persistence, invalid-path rejection and preservation of the
installed macOS profile. This isolates application settings, not all engine
caches. The packaged check still covers startup only, not playable matches.
It is intentionally unsigned; public
distribution requires a Developer ID signature, notarization, and the
appropriate rights to redistribute the original game assets.
