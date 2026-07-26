# CS 1.6 visual and sensory rejection report

Status: **rejected for CS 1.6 parity**. The HUD tranche described below passes
its limited gate; the complete game does not.

## 2026-07-26 baked-map and AK revalidation

### Map lighting — accepted

Imported BSP materials now render the exported baked vertex light directly
through an unshaded material with anisotropic filtered mipmaps. The synthetic
Godot sun/ambient pass no longer lights these surfaces a second time.

Fresh evidence: `game/artifacts/protocol47-hud-parity.png`.

- Near-white capture fraction: **0.0228%**, down from **3.95%** in
  `protocol47-hud-before-user.png`.
- Gate: less than 0.5% of pixels with all three color channels above 250.
- The surface retains the warm de_dust2 color and light variation visible in
  Valve's official Counter-Strike store capture without the prior white
  clipping.

Verdict: **accepted for the current baked-light presentation gate**. A future
pixel-identical pass should still validate raw per-surface lightmap sampling,
but the prior overexposure rejection is closed.

### Animated AK-47 viewmodel framing — accepted

The authentic animated `v_ak47.mdl` is mirrored and calibrated to
`base_position = (0.16, -0.075, -0.36)` and
`scale = (-0.63, 1.0, -1.0)`.

Fresh neutral-background evidence:
`game/artifacts/protocol47-viewmodel-ak.png`.

- Normalized silhouette bounds at 1280×720:
  `x=0.4766..0.8039`, `y=0.7708..1.0000`.
- Gate: left 45–50%, right 78–82%, top 75–80%, bottom at or below 98%.
- The model retains its authored vertical proportions while horizontal
  compression and camera-space placement keep the receiver, magazine, hands,
  and forearm in the classic lower-right safe region.

Verdict: **accepted for AK idle framing and animated-transform integrity**.
Other weapons and action-frame silhouette comparisons remain separate work.

## Reference baseline

- Valve HLDS App 90 assets documented in
  `public/models/ASSET-SOURCE.md` and
  `public/sprites/weapons/ASSET-SOURCE.md`.
- Original Valve Half-Life SDK HUD implementation:
  `/tmp/valve-halflife-src/halflife-master/cl_dll/hud_redraw.cpp`,
  `health.cpp`, `battery.cpp`, and `ammo.cpp`.
- App 90 audio mirror and metadata:
  `public/sounds/ASSET-SOURCE.md`, `materials.txt`, and `sentences.txt`.
- Original Valve sound/channel and footstep behavior:
  [`common/const.h`](https://github.com/ValveSoftware/halflife/blob/master/common/const.h#L614-L636)
  and
  [`pm_shared/pm_shared.c`](https://github.com/ValveSoftware/halflife/blob/master/pm_shared/pm_shared.c#L292-L631).
- Current deterministic captures in `game/artifacts/`.

The original HUD source is explicit about the visual grammar: additive,
yellowish sprite digits; health and armor at the lower left; clip, a narrow
separator, reserve ammunition, and an ammo icon at the lower right. It does not
define a persistent top-center match card or a hit-confirm marker.

## Ranked rejections

### Closed — Map lighting and material response

**Accepted in the 2026-07-26 revalidation.** BSP surfaces now render their
exported baked light directly. The capture harness continuously rejects any
regression above 0.5% clipped pixels.

Acceptance:

1. In a fixed de_dust2 reference camera, fewer than 0.5% of map pixels may have
   all RGB channels above 250.
2. Rendered texture color at five fixed UV/world probes must be within 10% luma
   and 8 delta-E of a software render from the BSP texture plus lightmap data.
3. Turning the synthetic `Sunlight` node on and off must not change imported
   BSP surface luma by more than 2%.
4. Fog must be off unless the BSP/entities explicitly request it.

### R1 — Player scale, hull relationship, and pose

**Accepted for the corrected deterministic R1 gate.** The source-model
scale/pose sub-gate remains accepted. Fresh captures are
`/tmp/protocol47-character-pose-grid.png` and
`/tmp/protocol47-character-scale-grid.png`.

- All **eight**, not nine, original playable MDLs are present. Their idle
  silhouettes are about **203–217 px** tall beside the approximately **249 px**
  72-HU bars. That difference is not a reason to enlarge them: the renderer
  now uses `MODEL_SCALE=1.0`, and the shorter visible mesh is the authored MDL
  inside the 72-HU collision hull.
- The pose grid shows seven distinct grounded source poses. At 1280×720 their
  visible heights are approximately **158–216 px** for upright/crouched poses;
  the final death silhouette is horizontal and floor-aligned. Hands and the
  attached AK have no obvious capture-scale separation.
- `character_model_animation_test.gd` passes all eight skins, exact
  32×32×72-HU hull scale, source sequence metadata, four sampled fractions,
  authored aim blends, and feet within 2 HU.

The prior crowd-gate correction is now implemented in
`bot_mobility_test.gd`. It runs all ten combatants at 100 Hz for 1,000 ticks
from de_dust2's original BSP spawn entities. Every tick measures pairwise
32-HU box separation, five-point walkable floor support, and a
32×72×32-HU BSP intersection probe. The regenerated
`/tmp/protocol47-bot-crowd-1000-ticks.json` records:

- minimum pairwise axis separation: **0.087 HU**;
- maximum floor error: **0.605 HU**;
- pair overlaps, missing floor traces, floor errors over 2 HU, and BSP hull
  intersections: **0 each**;
- all nine bots travelled **783–1,911 HU**.

This closes the exact deterministic evidence gap identified in the previous
review. A post-integration rerun printed
`GAME_BOT_MOBILITY_TEST_PASS`, exited zero, and its log contained no script,
parse, compile, or failed-resource-load errors. The visual model remains at
source scale 1.0; no mesh stretching was used to obtain the physical result.

### R2 — Camera and remaining first-person weapons

**Partially rejected.** AK idle framing is now accepted, but the camera FOV
remains configurable with modern semantics and no capture set yet proves every
weapon/action against the GoldSrc 90-degree baseline and widescreen rule.

Acceptance:

1. At 4:3, a default-FOV calibration scene must measure 90 degrees horizontally
   within 0.25 degrees. The chosen 16:9 rule must be documented and locked by
   the same test.
2. For every `v_*.mdl`, idle/deploy/fire/reload screenshots at fixed animation
   fractions must remain within a 2% silhouette-difference mask of an original
   GoldSrc render.
3. Camera eye is 17 units above the standing hull origin and 12 units above the
   crouched hull origin, with no one-frame pop during duck transitions.
4. Bob phase/amplitude at 250 units/s must match a recorded 100 Hz reference
   trace within 1 pixel at 720p.

### R3 — Animation playback

**Temporal playback accepted; independent GoldSrc transition parity still
rejected.**

Accepted code/test evidence:

1. `_set_frame()` now selects current and adjacent source frames and carries
   the fractional `time × fps` remainder through every vertex. Looping
   sequences wrap to frame zero; non-looping sequences clamp to their final
   frame and alpha zero.
2. `_render_interpolated_frame()` performs the full four-pose interpolation:
   authored XR aim blend within the current and next temporal frames, followed
   by temporal interpolation between those results. Body and attached weapon
   are sampled from the same authoritative animation clock.
3. The focused character test passed cleanly. At phases **0.25, 0.50, and
   0.75**, it independently reconstructs the four source offsets and checks
   every rendered body and weapon vertex within one source quantization step.
   This directly closes the prior frame-stepping rejection.
4. `/tmp/protocol47-character-100hz-transition-tape.json` contains 160
   consecutive 100-Hz ticks spanning idle, run, crouch, shoot, reload, and
   death. It records body/weapon clock equality at every tick, preserves the
   locomotion clock across idle→run→crouch, resets shoot/reload, starts death
   at frame zero, and holds `die:35:35:0` through the final sample.

Rejected oracle sub-gate:

- The tape declares its source as **“deterministic production sampler.”** It
  is generated from the same implementation that the assertions exercise.
  There is no independently recorded GoldSrc transition tape and no
  comparison of gait phase, reset/continuation semantics, or death timing
  against such a tape. The deterministic regression is accepted, but it
  cannot establish reference parity with itself.

Required remaining correction: record the identical input/tick schedule in a
real GoldSrc client, store that oracle independently, and compare every
transition field with explicit tolerances. Until then, the mechanical
smoothness defect is closed but the claim of GoldSrc-exact transition behavior
is not.

### R4 — VFX and combat feedback

**Corrected mechanics mostly accepted; flicker behavior and the independent
GoldSrc composite oracle remain rejected.** The focused
`game:test:vfx` command passed cleanly. Refreshed evidence is
`protocol47-combat-vfx-impacts.png`,
`protocol47-combat-vfx-smoke.png`, and
`protocol47-combat-vfx-explosion.png`.

Exact correction verdicts:

1. **ACCEPT — 8 HU/s explosion motion.** Each `fexplo` and `eexplo` sprite
   owns an upward velocity of 0.08 m/s at the locked 100-HU-per-meter scale.
   The fixed-tick test advances 25 ticks and measures exactly 0.02 m, or 2 HU.
2. **ACCEPT — four lights for two independent `TE_EXPLOSION`s.** Each
   fireball owns one dlight and one elight represented by independent fading
   light nodes, for two of each and four total. They follow their respective
   rising sprite and expire with that sprite's distinct 84- or 100-tick
   lifetime. The prior shared-light implementation is gone.
3. **REJECT — source flicker behavior.** Two batches and 16 nodes per
   fireball now exist, but `_spawn_flicker_particles()` creates fixed-color
   additive line tracers. `_update_motions()` changes only position and
   velocity; it never changes brightness, palette/ramp, alpha, or visibility.
   The test asserts batch and declared particle count only. Naming these nodes
   “flicker” does not implement or prove the source's time-varying flicker
   particles.
4. **ACCEPT — `steam1` orientation 4.** The importer retains orientation 4,
   runtime maps it to a view-plane billboard while preserving source roll, and
   the focused test exercises a nonzero 37-degree roll. The smoke capture shows
   the imported frame rather than the former generic-orientation path.
   Broader “every orientation mode is distinct” parity should not be claimed:
   modes 0 and 1 still collapse to the same Godot fixed-Y mode.
5. **ACCEPT implementation / REJECT the full rendered-probe gate — WAD RGB
   multiplicative decals.** The importer now writes original palette RGB
   instead of white-alpha silhouettes, runtime uses white tint plus
   multiplicative blending, and no family tint table remains. The test verifies
   `shot1`'s center RGB `(140,140,140)` and its material mode. It still does
   not measure bullet, blood, and scorch output at fixed lit-surface pixels as
   the prior correction required, so the implementation is accepted but the
   complete color/compositing evidence gate is not.
6. **ACCEPT — eight gravity tracers plus `richo1` per `TE_SPARKS`.** Cube
   particles are gone. The runtime creates eight additive tracer line nodes
   with gravity and a fixed lifetime for each shower, plus one original App 90
   `richo1` sprite; the two-shower test observes 16 tracer nodes and two
   ricochet events. The event tape records gravity and lifetime, although a
   future source-oracle comparison must still validate the chosen deterministic
   velocity, color, and decay distribution.

Independent reference gate:

- **REJECT — paired real-GoldSrc 5% composite oracle is still missing.** The
  three refreshed captures are clear Godot-only fixtures. There are no
  same-camera, same-event-tick GoldSrc frames, no alpha-silhouette difference,
  and no RGB/composite error report. The very bright overlapping explosion
  capture especially cannot establish optical parity by inspection alone.

Required remaining correction: implement an actual time-varying source flicker
ramp, add fixed lit-surface bullet/blood/scorch probes, then capture paired
GoldSrc and Godot impact, muzzle, shell, HE, and delayed-smoke frames and enforce
the stated **5%** silhouette gate with RGB/composite error reported separately.

### R5 — Audio direction and event system

**Reject the live mix; accept the mirrored bytes, isolated event router, and
tested attenuation-adapter mechanics.** The repository now owns a strong source
library, a deterministic GoldSrc-compatible event plane, and a pooled Godot
renderer with explicit unit conversion. Live gameplay still bypasses them, and
the adapter has not been measured against a real CS 1.6 PCM reference.

#### Asset and provenance audit

- `public/sounds` and `game/assets/sounds/classic` each contain exactly **808
  WAVs**. Every relative path is present in both trees and every pair is
  byte-identical.
- The sorted path-plus-file-hash bundle is pinned to SHA-256
  `97fa9110932cf4b21f93f2498e2650712d73e551b59917ffe0ba0f538cff5363`.
  `materials.txt`, `sentences.txt`, and `ASSET-SOURCE.md` are independently
  pinned to `0d35d708...ab6c`, `09d57cf3...453a`, and
  `78639c62...c4c` respectively.
- `sound-assets-regression.py` now checks those pins, RIFF/WAVE headers,
  per-file mirror equality, missing paths, and unexpected Godot-only WAVs.
  `audio_catalog_test.gd` passes with 18 catalog event families and 662 parsed
  material tags.
- The provenance notes in both trees are byte-identical and identify official
  HLDS App 90 via SteamCMD plus the Counter-Strike-over-Half-Life search order.
  This proves what the checked-in mirror claims and the hash pins make later
  mutation visible. It is not fully reproducible provenance yet: the note does
  not record a Steam depot manifest/build ID, download transcript, or a Valve
  manifest hash.

#### Runtime audit

| Area | App 90 / Valve evidence | Current live behavior | Verdict |
|---|---|---|---|
| Event mapping | The mirror includes weapon actions, impacts, player states, C4, radio, doors, buttons, trains, ambience, and more. `sentences.txt` also maps radio groups to samples. | `CS16AudioEventRouter.emit_catalog_event()` resolves catalog samples and records their checked SHA-256, but live `PlayerController` and `HEGrenade` still bypass it through flat legacy paths; `TargetActor` has no weapon, step, pain, or death emitter. The live Deagle reload uses `res://assets/sounds/deagle_reload.wav`, which is absent from the App 90 mirror. Knife hit/wall/stab, empty-fire, staged reload actions, C4, and most impact events are not mapped. | **Infrastructure accepted; live mapping rejected** |
| Channel and concurrency | Valve defines `CHAN_WEAPON`, `CHAN_VOICE`, `CHAN_ITEM`, `CHAN_BODY`, `CHAN_STREAM`, and `CHAN_STATIC`; the channel is part of every sound emission. | The isolated router now implements same-entity/same-fixed-channel replacement, cross-channel and cross-entity overlap, independent `CHAN_AUTO` allocation, explicit stop, natural expiration, and deterministic stop ordering. Live nodes do not use it: local shot/reload remain two 2D streams, grenade bounce suppresses contacts while its sample plays, explosion sounds allocate one-shot nodes, and bots are silent. | **Router accepted; live concurrency rejected** |
| Attenuation and spatialization | Valve exposes `ATTN_NONE=0`, `ATTN_NORM=0.8`, `ATTN_STATIC=1.25`, and `ATTN_IDLE=2` as event parameters. ReHLDS preserves origin, volume, attenuation, flags, and pitch in `S_StartDynamicSound`/`S_StartStaticSound`; the Quake-lineage mixer uses `dist_mult = attenuation / 1000` and linear gain. | The isolated adapter now locks `100 HU = 1 m`, uses 2D playback for `ATTN_NONE`, uses 3D playback otherwise, disables Godot's built-in distance attenuation, and applies `gain = clamp(1 - distance_hu × attenuation / 1000, 0, 1)` once. Existing gameplay nodes still use arbitrary 18/45 m cutoffs or Godot defaults. No GoldSrc PCM capture yet proves the proxy curve, stereo pan, PVS/occlusion, or mixer quantization. | **Adapter mechanics accepted; live/reference parity rejected** |
| Pitch and volume | Valve emissions carry explicit volume and pitch; `PITCH_NORM=100`. Its footstep implementation uses normal pitch and material/state-dependent volumes rather than per-step pitch jitter. | Shots randomize `pitch_scale` from 0.97–1.025, footsteps from 0.96–1.04, and grenade bounces from 0.92–1.08 without a cited CS event rule. The grenade uses the global RNG, so its pitch is not deterministic. Fixed `-5/-8/-10/-7 dB` gains are project choices, not conversions of source volume fields. | **Reject** |
| Footsteps and materials | Valve reads only the first 12 texture characters, falls back to concrete, alternates left/right foot sample pairs, uses a special 1-in-5 tile variant, and emits running ground steps every 300 ms. In multiplayer, ordinary ground steps are silent at speeds at or below 220 units/s. The App 90 `materials.txt` adds the CS texture table. | The catalog correctly parses the 12-character table and concrete fallback, but the player never calls it. Live steps are always `pl_step1..4`, in linear order, with no BSP texture lookup, water/wade/ladder/landing states, or bot steps. At AK speed, the 1.65 m distance threshold is about 746 ms per step rather than the source 300 ms. Shift-walk/crouch silence is directionally correct at current speeds, but the rest of the state machine is absent. | **Reject except for walk-silence intent** |
| HE variants | The App 90 tree contains the CS-specific `he_bounce-1.wav` as well as inherited Half-Life `g_bounce1..5.wav`. | Live HE uses `he_bounce-1.wav`, while catalog event `he.bounce` selects inherited `g_bounce1..5.wav`. Without staged event metadata resolving that conflict, the catalog cannot be accepted as authoritative. Explosion audio always selects `explode3` plus one debris sample. | **Reject / unresolved source conflict** |
| Radio and announcer | The mirror contains all **45** radio WAVs. `sentences.txt` lines 667–713 explicitly bind groups including `MRAD_CTWIN`, `MRAD_TERWIN`, `MRAD_ROUNDDRAW`, `MRAD_BOMBPL`, and `MRAD_BOMBDEF`. | No gameplay script references any radio sample or sentence group. Round win/draw, bomb plant/defuse, commands, acknowledgements, and bot chatter are silent; HUD banners are not an audio substitute. | **Reject** |
| Deterministic evidence | GoldSrc events carry entity, channel, sample, origin, volume, attenuation, flags, and pitch. Those fields provide a reproducible event trace. | `audio_event_router_test.gd` proves a byte-identical seeded 100 Hz event trace. `audio_playback_adapter_test.gd` additionally proves deterministic HU/metre and attenuation probes, 2D/3D pool selection, fixed-channel stop-before-start replacement, pool-slot reuse, listener gain refresh, and adapter traces. `game:capture` still captures no PCM or GoldSrc comparison. | **Event/adapter traces accepted; PCM parity rejected** |

#### Completed infrastructure slice — 100 Hz event router

`CS16AudioEventRouter` is accepted for the following isolated boundary:

1. Its public constants reproduce Valve's channel numbers, attenuation
   descriptors, normal/low/high pitch, normal volume, and sound flags.
2. `emit_catalog_event()` and `emit_descriptor()` reject missing/non-classic
   samples, invalid channels, volume outside 0–1, negative attenuation, invalid
   pitch ranges, and non-positive explicit duration.
3. Deterministic seeded selection owns both sample variant and source pitch.
   Resetting seed and event order produces byte-identical JSON traces; no global
   RNG participates.
4. Voice duration is quantized to the authoritative 100 Hz clock after pitch
   scaling. Replacement, explicit stop, and natural completion all produce
   ordered trace events.
5. Every start trace records event name, tick, entity, source channel, App 90
   relative sample and SHA-256, variant, volume, raw attenuation descriptor,
   pitch, flags, origin, and expected end tick.
6. Headless tests cover all source constants, hash/path resolution,
   same-channel replacement, permitted overlaps, `CHAN_AUTO`, explicit stop,
   exact pitched expiration, all four attenuation descriptors, seeded replay,
   and invalid input.

The router emits `event_started`/`event_stopped` to
`CS16AudioPlaybackAdapter`. The adapter's accepted isolated boundary is:

1. `HU_PER_METER=100` and `METERS_PER_HU=0.01`; router origins are explicitly
   Hammer/GoldSrc units and every 3D player position crosses that boundary once.
2. `ATTN_NONE` acquires a pooled `AudioStreamPlayer`; attenuated events acquire
   pooled `AudioStreamPlayer3D` nodes with Godot attenuation disabled.
3. Source volume and pitch configure the player. The linear attenuation proxy
   is evaluated in HU and converted to dB exactly once, then refreshed whenever
   the listener origin changes.
4. Router stop arrives before replacement start, returns the old player to its
   typed pool, and the replacement reuses that stable pool slot. Cross-channel
   overlap acquires a second slot.
5. Adapter traces avoid engine instance IDs and record stable pool slot, source
   hash, HU/metre origin, listener, distance, attenuation, gain, source volume,
   dB output, pitch, stop reason, and replacement link.

This accepts deterministic adapter state, **not GoldSrc PCM parity**. Exact
residuals remain:

- Valve's public SDK and ReHLDS header expose the mixer inputs but not the
  original closed client mix implementation. The 1000-HU linear curve follows
  the inherited Quake mixer and must still be measured against CS 1.6.
- Godot stereo panning/HRTF, `ATTN_NONE` presentation, PVS/occlusion,
  underwater filtering, and listener/entity update timing are not matched.
- GoldSrc's mixer sample quantization, same-frame duplicate-sound phase offset,
  clipping, 8-bit source conversion, output-rate resampling, and device buffer
  timing are not emulated.
- No gameplay emitter is bound to the router/adapter yet, and no captured PCM
  is compared with a real GoldSrc reference.

#### Required deterministic audio gate

1. Drive a fixed 100 Hz event script containing two players firing
   simultaneously, same-entity same-channel replacement, different-channel
   overlap, reload stages, dry fire, knife miss/body/wall, HE bounce/explosion,
   four surface footsteps, C4 plant/defuse, and each round result.
2. Record an event trace containing tick, entity, channel, original relative
   sample path and SHA-256, variant seed/index, volume, attenuation, pitch,
   origin, and listener origin. Repeating the test must produce byte-identical
   traces.
3. Capture PCM at a fixed mix rate. Assert onset within one 100 Hz tick, source
   duration within one source sample after declared pitch conversion, and a
   concurrency matrix that proves same-channel replacement and cross-channel /
   cross-entity overlap.
4. Probe `ATTN_NONE`, `ATTN_NORM`, `ATTN_STATIC`, and `ATTN_IDLE` at fixed
   0/128/512/1024-unit distances, locking the GoldSrc-to-Godot curve before any
   aesthetic gain adjustment.
5. Run the full material step state machine at fixed velocities and seeds,
   including left/right pairing, the tile fifth sample, ladder, wade, slosh,
   landing, duck volume/cadence, and multiplayer walk silence.
6. Compare a 30-second fixed combat/round mix with a GoldSrc reference:
   identical event counts and ordering, no missing radio/announcer events, and
   peak/RMS envelopes within 1 dB after a documented output-rate conversion.

**Highest-impact remaining tranche:** bind one scene-owned router/adapter,
migrate Player, bots, grenade, C4/round, and material footsteps, and delete the
replaced direct `AudioStreamPlayer*` paths. In parallel, capture a real GoldSrc
distance/pan reference to accept or correct the linear proxy before claiming
PCM parity.

### R6 — Deployment, buy, scoreboard, menus, and text

**Partially accepted.** This is now a substantial source-backed CS 1.6 UI
implementation, not the previous branded clean-room card. The source archive,
parser, portraits, team-filtered buy art, ESC suppression, deterministic
scaling, and broad capture coverage pass. Exact parity still fails on
accelerator rendering, briefing clipping, several live input/action paths, the
handwritten options pages, complete scoreboard evidence, and the missing
GoldSrc pixel oracle.

The independent rerun passed `game:test:hud`, including all four Godot HUD
tests, and the stable whole-project `game:check` log contains no script, parse,
compile, or failed-load errors.

#### R6.1 — Source integrity, capture coverage, and scaling: ACCEPT

- `public/ui/classic` contains a pinned **126-file** Steam App 90 archive.
  `ui-source-regression.py` verifies every source/runtime byte, size, App ID,
  and aggregate SHA-256
  `3ccf1215d4d1852789741d1bfee08637d189dcd6db5ee947ad0ca6743070b7d7`.
  The required team, class, buy, scoreboard, GameMenu, scheme, briefing, TGA,
  and platform-options resources are present.
- `CS16VGuiSource` successfully parses the staged UTF-8/UTF-16 KeyValues,
  center/right coordinates, localization, scheme colors, y-resolution font
  sizes, menu entries, and map briefing. The source-focused test passes.
- The fresh run contains exactly **87 captures: 29 states × 3 resolutions**.
  All 29 states exist at 640×480, 1024×768, and 1280×720. Nine older generic
  `buy`/`class`/`options` captures remain in the directory, explaining the raw
  total of 96; they are not part of the current gate.
- The deterministic reference scale remains 1.0, 1.6, and 1.5, with the
  expected 160-pixel horizontal safe area at 1280×720. Contact-sheet review
  found no outer-canvas overflow.

This accepts source integrity and deterministic coverage, not a pixel-identical
GoldSrc claim.

#### R6.2 — Team and class selection: implementation ACCEPT, exact flow REJECT

Accepted:

- `Teammenu`, `Classmenu_CT`, and `Classmenu_TER` geometry is read from the
  pinned resources. The menus expose four real T and four real CT families
  plus source auto-select; the unsupported militia/Spetsnaz rows are gone.
- All eight staged player portraits load, and focus/hover updates the portrait.
  The CT/T captures visibly show distinct original artwork.
- de_dust2's title, scenario, and body now come from the pinned 452-byte App 90
  briefing rather than project-authored copy.

Rejected:

1. **Accelerators are not rendered.** The source localization contains strings
   such as `&1 TERRORIST FORCES` and defines `DefaultUnderline`; the runtime
   hard-codes `1  TERRORIST FORCES`, strips the accelerator contract, and uses
   a normal Godot `Button` with no underline span/font. A numeric prefix is not
   source accelerator rendering, and no test asserts it.
2. **The briefing is visibly clipped at every resolution.** The 640×480 team
   capture ends after “weapon stashes.” while the source continues with
   “Other Notes: There are 2 chemical weapon stashes in the mission.” The
   description is fixed to 210 pixels inside a clipping parent. The geometry
   test encloses the label control, not all rendered source lines.
3. `handle_menu_key()` implements numeric selection internally, but
   `game.gd` never calls it. `team_selected` and `class_selected` are not
   connected to authoritative player state; only `deploy_requested` starts the
   match. Number/cancel and replicated-selection acceptance is therefore still
   missing in the live game.

#### R6.3 — Buy menu: visual/source catalog ACCEPT, live inventory flow REJECT

Accepted:

- All **16 team/category combinations** are freshly captured at all three
  resolutions. CT/T category files are parsed independently and sorted by
  source `ypos`; the focused test proves CT rifles include M4A1 and exclude
  AK-47 while T rifles do the inverse.
- Original weapon/equipment TGAs render in the detail pane and track focus.
  Source control metadata, costs, disabled unaffordable state, and the full
  visual catalog are exercised without the former mixed-team list.
- `B`, buy-zone geometry, buy time, team restrictions, account balance, and
  the authoritative round-state purchase ledger now exist in live code.

Rejected:

1. Live input is incomplete: `game.gd` opens the menu on `B` but never forwards
   number/escape navigation to `hud.handle_menu_key()`.
2. The menu exposes the full source catalog and deducts its prices, but
   `_on_buy_item_requested()` grants inventory only for armor, AK-47, Deagle,
   HE grenade, and defuser. Most pistols, shotguns, SMGs, rifles, grenades,
   ammo, night vision, shield, and equipment can charge the account without
   granting the item.
3. All 48 fresh buy captures use `$10000`; the test checks a disabled Deagle
   in memory, but no requested unaffordable-state capture exists.

The exact gameplay transaction correction is therefore rejected despite the
accepted source catalog and eligibility infrastructure.

#### R6.4 — Scoreboard: structure/snapshot ACCEPT, complete live gate REJECT

Accepted:

- The 520×340 frame comes from `ScoreBoard.res`; source-style team sections,
  columns, scroll behavior, and staged `smallskull`, `smallvip`, and `smallc4`
  states replace the former `*DEAD*` suffix.
- Live rows now come from `round_state.scoreboard_snapshot()` rather than only
  a capture fixture. Round score, alive/dead, kills, deaths, and bomb-carrier
  state are propagated.
- A deterministic 32-player fixture is captured at all three resolutions.
  The 640×480 image shows 14 CT rows fitting the source-height scroll viewport
  with an active scrollbar rather than overflowing the 520×340 frame.

Rejected:

1. `set_scoreboard_held()` exists but no live `KEY_TAB` press/release binding
   calls it. The scoreboard is not reachable through the required held-TAB
   contract.
2. The exact requested 1-, 10-, and 20-player captures are absent; only the
   six-player and 32-player states are captured. The 32-player test fixture is
   not asserted to contain every generated row after scrolling.
3. Voice/mute/status state remains absent, and live latency is hard-coded to
   zero. No paired GoldSrc full-server comparison exists.

#### R6.5 — ESC game menu: visual and HUD-suppression ACCEPT, actions REJECT

Accepted:

- Exact `game_menu.tga` and mouseover artwork is staged, hashed, loaded, and
  visible in all three fresh captures. The seven entries come from
  `GameMenu.res`, use source localization, and emit menu focus/activation sound
  requests.
- The gameplay radar, money, vitals, timer, ammo, crosshair, announcement, and
  damage controls are all suppressed while the ESC overlay is active. The
  captures visibly contain no residual gameplay HUD.

Rejected:

1. Source `OnlyInGame`/`notsingle` visibility rules are parsed but ignored;
   `menu_entries()` always returns all seven entries.
2. New Game and Find Servers only emit a generic signal. Disconnect and Quit
   stop at unconnected HUD signals. Player List substitutes the current
   scoreboard. The requested real dialogs/actions are not implemented.
3. `ui_sound_requested` is not connected by `game.gd`, so the source-named
   focus/activation samples are requests, not live sounds. Live Escape also
   toggles pause directly instead of routing nested cancel behavior through
   `handle_menu_key()`.

#### R6.6 — Options and accessibility: coverage/isolation ACCEPT, parity REJECT

Accepted:

- Multiplayer, Keyboard, Mouse, Audio, Video, and Voice each have a distinct
  visible page and three fresh resolution captures. Accessibility is a seventh
  separately branded extension overlay; it does not appear inside the six
  claimed parity tabs.

Rejected:

1. The options pages are handwritten in `_build_options_page()` rather than
   built from the staged platform resources. The panel metadata even points to
   nonexistent `OptionsDialog.kv`; the pinned source is
   `DialogOptionsIngame.kv`.
2. Source control rectangles, labels, `tabPosition`, defaults, and command
   contracts in `OptionsSub*.res` are not parsed into the controls. The
   keyboard page is a six-line static list rather than the source key-binding
   list/control set.
3. Apply/Defaults merely emit unconnected generic signals; Cancel/OK do not
   implement staged-value rollback/commit. Original focus order and control
   sounds are unproven.

#### R6.7 — Typography, color, opacity, focus, and visual oracle: REJECT

The previous default-font rejection is partially corrected: `ClientScheme`
colors and y-resolution sizes are parsed, and the runtime requests Verdana at
weight 600 with Arial/Tahoma fallback. That matches the source `Default` rule
on this machine.

The complete gate still fails. Font face/weight/underline are not returned by
the parser; one global weight-600 system font is applied even to source rules
such as `DefaultSmall` weight 0 and `DefaultUnderline` Tahoma weight 500.
Fixed text-baseline and composited-RGBA probes do not exist. Focus order is not
derived from source `tabPosition`, accelerators are not drawn, and the fresh
captures have no paired GoldSrc images or pixel-difference report.

Required remaining tranche: render source accelerators, make the full briefing
fit, wire the HUD input contract and team/class state, grant every purchased
catalog item, bind held TAB, complete GameMenu dialogs/sounds, build options
from `DialogOptionsIngame`/`OptionsSub*`, and add same-state GoldSrc golden
captures with baseline/RGBA and pixel-difference gates.

### R7 UI corrective audit — 2026-07-26

**Overall verdict: REJECT exact CS 1.6 UI parity.** The corrective tranche
closes several concrete R6 failures: source accelerators now render on the team
menu, the complete briefing is reachable through a real scroll container,
numeric/cancel input and held TAB are wired in `game.gd`, and the requested
scoreboard/unaffordable fixtures exist. It also exposes new pixel-level
failures that the structural tests do not catch, most visibly duplicated buy
accelerators, a raw `&1` in the selected-item description, an empty keyboard
binding list, incomplete voice controls, and non-source voice-status glyphs.

Independent evidence for this audit:

- `npm run game:test:hud` passed
  `APP90_UI_SOURCE_REGRESSION_PASS files=126
  aggregate_sha256=3ccf1215d4d1852789741d1bfee08637d189dcd6db5ee947ad0ca6743070b7d7`,
  `CLASSIC_UI_SOURCE_TEST_PASS`, `HUD_SPRITE_ASSET_TEST_PASS`,
  `HUD_LAYOUT_TEST_PASS`, and `CLASSIC_UI_FLOW_TEST_PASS`.
- A fresh `--residual` GUI run passed and rendered eleven current 640×480
  states: team, briefing end, unaffordable T pistols, scoreboard
  1/10/20/32/voice, and keyboard/mouse/voice options.
- The older 87-state, three-resolution matrix predates the R7 HUD changes.
  Geometry tests still pass at 640×480, 1024×768, and 1280×720, but current
  post-correction pixels at the latter two resolutions are not evidence-backed.
- The HUD sprite/layout/flow tests and the fresh capture still exit with
  CanvasItem RID, ObjectDB, and `FontAdvanced` resource leaks.

| Surface | Verdict | Evidence accepted | Exact residuals |
| --- | --- | --- | --- |
| App 90 source archive and parser | **ACCEPT, source integrity only** | The 126-file public/runtime mirror and aggregate hash pass. KeyValues, UTF-16 localization, coordinates, colors, menu conditions, font rules, briefing text, portraits, and TGA lookup are exercised. | Parsing source data is not proof that every runtime control implements its semantics or pixels. |
| Team accelerators | **ACCEPT, narrow** | The fresh team capture contains no raw `&`; `1`, `2`, `5`, `6`, and `0` have visible underline strokes. The test identifies `DefaultUnderline`, accelerator metadata, and a measured ascent. | No fresh R7 class capture or paired GoldSrc pixels exist. The default team viewport does not show `Other Notes`; only the endpoint fixture proves it is reachable, so exact source scroll position/viewport remains unverified. |
| Briefing completeness | **ACCEPT, functional** | The endpoint capture visibly includes `Other Notes: There are 2 chemical weapon stashes in the mission.` and the scrollbar reaches its lower limit. The full source string remains in the label. | This accepts “not irretrievably clipped,” not an exact GoldSrc line-wrap or initial viewport match. |
| Team/class live input | **PARTIAL ACCEPT** | `game.gd` now forwards non-echo keys to `hud.handle_menu_key()`; numeric team/class selection, zero/back, and Escape are tested through the typed API. | `team_selected` and `class_selected` are still not connected by `game.gd` to authoritative player/team/model state. Selecting a T family only reaches `deploy_requested`/`start_match`; replicated selection acceptance remains a HUD-only API. |
| Buy catalog and unaffordable state | **REJECT visual parity** | The fresh `$600` pistol fixture visibly disables the unaffordable rows while leaving the `$400` Glock selectable; team/category source catalogs and art remain staged. | The pixel result is broken: rows read `1 1 9X19MM SIDEARM`, `2 2 KM .45 TACTICAL`, etc. because a generated numeric prefix is combined with the localized source accelerator. The detail pane exposes raw `&1 9X19MM SIDEARM`. Disabled rows also retain duplicated ghost text. A green structural test missed all three failures. |
| Scoreboard fixture coverage | **ACCEPT, fixture structure** | Fresh 1-, 10-, 20-, and 32-player captures exist. The 32-player viewport shows 14 CT rows with an active scrollbar; the automated test finds all 32 player row nodes. Skull, VIP, and C4 sprites render. | The 20- and 32-player images show only the top of the scroll range, so T/spectator rows are not visually exercised at the bottom. No GoldSrc full-server pair exists. |
| Held-TAB and live scoreboard data | **PARTIAL ACCEPT** | `game.gd` now opens on TAB press and closes on release; the HUD action API has the same held contract. | Live `game.gd` still assigns every latency `0` and does not populate live `voice_active`/`voice_muted`. Voice evidence is fixture-only. The fresh voice capture uses project-authored green dots and `×` characters rather than a demonstrated CS 1.6 speaker/mute rendering. |
| ESC GameMenu | **PARTIAL ACCEPT** | Source artwork, localization, seven in-game entries, hover art, nested options, and gameplay-HUD suppression remain implemented and visually plausible in the existing captures. | The runtime always calls `menu_entries()` with default in-game/multiplayer arguments rather than an actual context. New Game and Find Servers only emit generic commands; disconnect/quit and UI sound requests remain unconnected in `game.gd`; Player List is substituted with the scoreboard. No fresh R7 ESC capture or source-paired oracle exists. |
| Options source geometry | **ACCEPT, metadata only** | The shell points at the real `DialogOptionsIngame.kv`; all six pages are generated from the corresponding `OptionsSub*.kv`, preserve source rectangles and `tabPosition`, and build focus-neighbor metadata. | The tabs and outer property-sheet shell are still project-authored. `DialogOptionsIngame` itself contains only frame/build controls and does not justify the handwritten tab bar or scaled 520×412 shell. |
| Keyboard options | **REJECT** | Defaults/Edit/Clear buttons use the source positions and labels. | The fresh keyboard capture is an empty black list area. The capture scene has no player-created InputMap actions, so `_build_source_key_list()` produces no binding rows. Change/Clear only emit command strings and do not capture, replace, or clear a binding. |
| Mouse/audio/video/voice options | **REJECT complete behavior and pixels** | Reverse mouse, sensitivity, SFX volume, and VSync have staged bindings; mouse Cancel rollback is tested. Source labels/rectangles render on the inspected pages. | Most source controls are inert generic widgets. The fresh voice page omits the transmit-volume slider and both mic-meter images; receive volume is the only visible slider. Test Microphone, mic boost, mouse-look/filter/joystick/raw input, and most multiplayer/video/audio settings do not change game state. Unknown source panels render as blank dark rectangles. |
| Apply/OK/Cancel/Defaults | **PARTIAL ACCEPT, narrow** | One sensitivity change is proven staged; Cancel restores its snapshot. Apply updates the six project settings, OK applies then closes, and Defaults resets those same six values. | The tests do not exercise Apply, OK, default focus activation, keyboard traversal, or rollback across every tab. The majority of displayed source controls never enter `_options_pending`, so the commit contract is incomplete even where buttons exist. |
| Typography, color, and focus | **PARTIAL ACCEPT** | Runtime `SystemFont` objects request source family and weight per rule; team accelerators use the underline rule; source colors, alpha parsing, ascent metadata, and tab ordering have deterministic tests. | Source antialias, drop shadow, outline, text alignment, disabled/focus colors, and exact baseline/rasterization are not generally applied. Buy text proves accelerator composition is not globally correct. No 640×480 GoldSrc pixel pair, font-raster diff, or RGBA composite render probe exists. |
| Runtime/test hygiene | **REJECT** | All functional assertions exit zero. | HUD sprite/layout/flow tests and the fresh GUI capture report 8 leaked CanvasItem RIDs, 20 leaked ObjectDB instances, and one leaked `FontAdvanced` allocation. A parity gate should not normalize persistent shutdown leaks. |

#### R7 UI false-green tests

1. The accelerator test inspects the team button only. It does not exercise a
   source string that already contains both `&` and its numeric label after the
   buy list prepends another number, nor the plain selected-item description.
2. The briefing test proves the complete string exists and the control is
   scrollable; it does not compare the initial scroll position, line wrapping,
   scrollbar skin, or viewport height with GoldSrc.
3. The capture-fixture test searches the capture script source for state names.
   It does not assert that current captures exist, were produced after the
   implementation changed, or contain correct pixels.
4. The 32-player test counts hidden row nodes. It does not scroll and render
   every section, validate row spacing at the bottom, or compare live latency
   and voice state.
5. The options test validates one mouse slider and Cancel. It cannot catch the
   empty key list, missing mic meter/transmit control, inert source widgets,
   Apply/OK/default-focus behavior, or control rendering.

Required next UI gate: remove buy-number synthesis and treat the localized
accelerator as the sole label source; strip/render accelerators consistently
in descriptions; capture the current full matrix at all three resolutions;
connect team/class choice to authoritative state; feed real latency and voice
state; implement source-equivalent voice/key/options controls and commit
semantics; eliminate shutdown leaks; and pair every accepted surface with the
same GoldSrc 640×480 state plus a documented pixel/typography diff.

## Completed tranche — in-game HUD

Before: `game/artifacts/protocol47-hud-before-user.png` shows a rounded
top-center match card, boxed health and ammo panels, a weapon/fire-mode caption,
and a pale modern crosshair. The prior deterministic
`protocol47-gameplay.png` additionally showed cyan center announcements; the
code also rendered a hit-confirm X after impacts.

After: `game/artifacts/protocol47-hud-parity.png` shows the sparse classic
composition: upper-left radar; green money; yellow/orange health, armor,
clock/timer, clip separator/reserve, and ammo glyphs; lower-center timer;
green four-arm crosshair; no persistent match card; no weapon-mode caption; no
hit marker.

HUD tranche acceptance:

1. `HUDRoot/MatchBar` is absent.
2. `ClassicRadar`, `ClassicVitals`, `ClassicTimer`, and `ClassicAmmo` exist in
   the classic screen regions.
3. Hitmarker exists only as a compatibility API node and has zero visual
   children.
4. Clip/reserve use the original `clip | reserve` ordering and low health/ammo
   switches to classic red.
5. Health, armor, money, timer, clip, reserve, and radar now render the original
   640px App 90 HUD atlas regions. The extraction manifest pins
   `hud.txt` to SHA-256
   `0c85c594323d9a19cbb53907fe0a6f6aab3070583dc9e99cd64ae343a095141e`
   and pins every source `.spr` sheet independently.
6. `hud_sprite_asset_test.gd` verifies all 35 manifest regions, source hashes,
   dimensions, non-empty alpha geometry, original numeral textures, viewport
   containment, and pairwise non-overlap at 640×480, 1024×768, and 1280×720.
7. `hud_layout_test.gd` and `npm run game:capture` pass. The capture gate
   asserts exact image dimensions and produces `protocol47-hud-640x480.png`,
   `protocol47-hud-1024x768.png`, and `protocol47-hud-1280x720.png`.

This core HUD sprite tranche is **accepted**: the temporary font/vector
numerals and core icons are gone, and the validated captures use Valve's
original glyph geometry at native pixel scale without overlap. Remaining HUD
work is limited to flows and symbols outside this core tranche, such as
scoreboard/buy menus and context-specific scenario icons.

## R7 gameplay/physics rejection — 2026-07-26

This is an independent adversarial review of the new round state, original
de_dust2 objective volumes, purchases, stale-dead reset, bot tactics, and
ten-player crowd behavior. No implementation was changed during this review.

Fresh evidence:

- `npm run game:test:rounds`: `GAME_ROUND_STATE_TEST_PASS` and
  `GAME_ROUND_INTEGRATION_TEST_PASS`.
- `npm run game:test:bots`: `GAME_BOT_TACTICS_TEST_PASS` and
  `GAME_BOT_MOBILITY_TEST_PASS`.
- `npm run game:check`: script parsing passes. Godot still reports leaked
  objects/RIDs in the integration tests and cannot save its editor settings in
  the sandbox.
- `/tmp/protocol47-bot-crowd-1000-ticks.json`: ten actors, 1000 physics ticks,
  zero reported pair overlaps/BSP intersections/floor errors, minimum reported
  pairwise axis separation `0.048 HU`.
- `game/generated/de_dust2/map.json`: source submodel bounds exist for bomb
  models `*16`/`*42` and buy models `*29`/`*30`; team properties survive as
  `1` and `2`.
- Primary comparison source:
  `/tmp/regamedll-src/ReGameDLL_CS-master/regamedll`, especially
  `dlls/triggers.cpp`, `dlls/player.cpp`, `dlls/wpn_shared/wpn_c4.cpp`,
  `dlls/ggrenade.cpp`, `dlls/combat.cpp`, and
  `dlls/multiplay_gamerules.cpp`.

### R7.1 — Accept/reject matrix

| Surface | Verdict | Severity | Reason |
| --- | --- | --- | --- |
| 100 Hz phase/deadline ownership | **ACCEPT, narrow** | — | Freeze/live/post deadlines and 30/60/144 render-schedule equivalence are deterministic in the isolated state model. |
| New-round stale-dead HUD reset | **ACCEPT** | — | A real post-to-freeze transition revives all ten combatants, rebuilds the live scoreboard, removes skull states, and restores player health. This directly covers the reported stale-dead regression. |
| de_dust2 BSP objective extraction | **ACCEPT, extraction only** | — | The four original brush submodels and buy-team properties are present with non-empty transformed source bounds; debug site cylinders are absent. |
| Runtime bomb/buy region membership | **REJECT** | **High** | Runtime uses `AABB.has_point(feet)`. GoldSrc buy zones are trigger touches (player hull overlap), while ReGameDLL's fixed bomb target additionally requires the player's full X/Y body bounds to be contained after touch. A feet point in all three axes matches neither contract. |
| C4 plant/defuse clock | **ACCEPT, model only** | — | 3 s planting, 5/10 s defuse, interruption, 45 s C4, and the ReGameDLL same-tick defuse-before-explosion fix are represented deterministically. |
| Live C4 gameplay | **REJECT** | **Critical** | C4 is only a boolean HUD state: key 5 does not equip the C4 weapon/viewmodel, the gun can remain active during the initial plant input, dropped C4 has no world entity/pickup path, bot carriers cannot plant, and human CT defuse is absent. Auto-defuse uses 100 HU with no facing/selection contract; GoldSrc searches usable entities within 64 HU and requires a forward candidate. |
| C4 economy | **REJECT** | **Critical** | The model immediately gives the planter `$800`. CS 1.6/ReGameDLL gives the `$800` bomb-planted amount to the Terrorist team when the bomb is defused; `wpn_c4.cpp` does not award an individual planter `$800`. The losing team therefore receives the wrong balances. |
| General economy/loss streak | **REJECT** | **High** | Five consecutive same-team losses happen to match. Streak handoff does not: ReGameDLL uses a shared loser-bonus value and resets it to `$1500` when a team breaks a streak longer than one; the implementation uses independent arrays and restarts the other team at `$1400`. Round money is also applied at round end instead of the restart/account-distribution point. |
| Purchase eligibility | **PARTIAL ACCEPT** | **Medium** | Alive/time/team checks and source IDs exist. VIP/map restrictions, `mp_buytime` minimum/disabled modes, buy-status restrictions, current equipment state, grenade limits, and shield incompatibilities are absent. |
| Purchase transaction/inventory | **REJECT** | **Critical** | The integration test buys Elites and checks only the money delta. `Player.refill_weapon()` returns immediately because a starting Glock/knife loadout has no `ammunition.elite`; `owns_weapon("elite")` remains false. The same no-op affects essentially every newly bought weapon and grenade. Kevlar, ammunition, NVGs, and shield are deliberately declared unavailable. |
| Starting/death-reset loadout | **REJECT** | **High** | Starting T/CT pistols receive registry maximum reserves (`120` 9 mm / `100` .45 ACP), not the CS 1.6 defaults (`40` Glock reserve / `24` USP reserve). Dead-player equipment such as defuse state is not fully reconciled between round state and player inventory. |
| Ten-player collision regression | **ACCEPT, narrow** | — | The exact 32×72×32 HU living hull set shows no measured pair/BSP/floor penetration for ten seconds on the original spawn set. This is good evidence against the original spawn-overlap screenshot. |
| Crowd-play quality | **REJECT** | **High** | The test gives everyone one million health, records only endpoint travel and overlap/floor counters, and does not gate jitter, repeated contacts, corridor deadlocks, route completion, spawn reuse, objective traffic, or long matches. A bot can oscillate for ten seconds and still pass the travel threshold. |
| Bot 100 Hz tactics unit | **ACCEPT, isolated only** | — | Seeded reaction, memory, burst, and reload traces are deterministic inside `CS16BotTactics`. |
| Live bot fire cadence | **REJECT** | **Critical** | `CS16BotTactics` emits AK shots about every 0.10 s, but `TargetActor` independently rejects them behind `_next_shot = 0.72..1.18 s`. The tested source-like cadence is therefore not the cadence that reaches gameplay. The tactics clip/reload is likewise disconnected from an authoritative actor inventory. |
| Live bot aim/damage | **REJECT** | **Critical** | The tactics aim target updates only on acquisition, while the rendered bot can keep looking at a stale point. Firing then ignores that aim/error and raycasts directly to the enemy's current `aim_point()`, applying random 6–10 generic damage. Bots do not use the human AK spread, recoil, hit groups, armor, penetration, or damage path. |
| Bot movement physics | **REJECT** | **Critical** | Bots set horizontal Godot velocity directly to 221 HU/s and call `move_and_slide()`. They do not use the accepted GoldSrc movement kernel, ground acceleration/friction, air movement, step-slide, duck, jump, ladder, fall, or weapon-speed behavior. |
| Bot CS objective behavior | **REJECT** | **Critical** | Bots select the nearest enemy only. Terrorist carriers cannot route to a site or plant; nobody can recover a dropped bomb; CTs are not routed to the planted bomb; the nearest CT merely auto-defuses if chance puts it within 100 HU. Round two can assign C4 to a bot and make the objective unwinnable except by elimination. |
| Bot/scoreboard round reset | **REJECT** | **High** | Combatant bodies reset, but `CS16BotTactics` is not reset; its tick, ammunition, reload deadline, burst, and visual memory persist into the next round. Bot kills/rewards are also not propagated accurately: ally deaths and player deaths do not credit the actual bot killer. |

Overall R7 verdict: **REJECT CS 1.6 gameplay/physics parity**. The stale-dead
bug and the original ten-player spawn-overlap failure are accepted as fixed,
and the deterministic round-state skeleton is a useful foundation. The live
objective, transaction, bot combat, and bot movement systems are not yet close
to source parity.

### R7.2 — False-green tests

1. `round_game_integration_test.gd` proves that Elites reduce money but never
   asserts `player.owns_weapon("elite")`, the replaced pistol, clip/reserve,
   current weapon selection, or a dropped replaced weapon. Its green purchase
   result masks a complete inventory no-op.
2. The region test asserts only region count, positive dimensions, team
   properties, and that one T spawn point is inside one AABB. It does not probe
   any boundary against GoldSrc trigger-touch/player-hull semantics or pin the
   four expected source model bounds.
3. `bot_tactics_test.gd` never drives `TargetActor`; it cannot see the second
   0.72–1.18 s cooldown, exact-target ray, random 6–10 damage, or disconnected
   actor ammo.
4. `bot_mobility_test.gd` makes death impossible and does not assert route
   goals, objective completion, contact/jitter budgets, velocity/acceleration
   traces, or shared GoldSrc movement. “Travelled hundreds of HU” is not
   evidence of competent CS bot movement.
5. The isolated stale-dead snapshot test is valid but insufficient on its own;
   the live integration test is the meaningful gate and should remain.
6. `cargo test ... bsp` currently selects zero tests. The exported bounds are
   exercised only indirectly by the Godot integration test, not by a parser
   fixture that compares model lump values and coordinate transforms.

### R7.3 — Precise next fixes required

1. Make purchases atomic: validate capacity/state first, debit only after a
   successful `grant_item`, assert ownership and exact clip/backpack ammo, drop
   replaced weapons, and implement source armor, ammo, NVG, shield, defuser,
   and grenade-limit behavior. Add rollback tests for every rejection path.
2. Replace point-in-AABB checks with source trigger contracts. For buy zones,
   detect the standing/ducking hull touching the brush. For bomb targets,
   reproduce trigger touch plus ReGameDLL full horizontal hull containment.
   Pin `*16`, `*29`, `*30`, and `*42` bounds numerically from the BSP fixture
   and test inside/outside edge cases in both hull states.
3. Materialize authoritative C4 inventory and world entities: random eligible
   carrier, actual equip/viewmodel/max speed, source planting freeze while
   preserving view control, drop model/owner/icon, hull pickup, bot pickup and
   plant, 64 HU forward-use defuse selection, interruption, glow/beep state,
   and exact target activation.
4. Correct economy from ReGameDLL event order: no individual `$800` plant
   award, `$800` T team award on defuse, shared loss-bonus handoff/reset,
   correct restart-time account distribution, teamkill/suicide penalties, and
   exact killer credit. Add alternating-streak and plant/defuse ledger oracles.
5. Remove the duplicate bot cooldown and route bot shots through the same
   weapon clock, inventory, spread, recoil, ballistics, hit-group, armor,
   penetration, animation, audio, and VFX path as the player. Gate accepted
   gameplay fire ticks, not only isolated tactic pulses.
6. Continuously update bot perception/aim subject to reaction and skill error;
   bullets must follow the resulting aim direction. Add moving-target miss/hit
   distributions and visibility-loss/reacquisition traces against source bot
   behavior.
7. Drive bots through the GoldSrc movement kernel and weapon max speeds. Add
   source-oracle traces for acceleration, stopping, steps, doors, crouch,
   jumping, ladders, falls, narrow corridors, and player-player contacts.
8. Add a real objective planner and round lifecycle: T carrier/site choice,
   escort/cover, dropped-C4 recovery, CT rotate/guard/retake/defuse, and full
   tactic reset on spawn. Run deterministic full 5v5 matches across many
   rounds with plant/defuse/elimination outcome coverage.
9. Extend the crowd gate to at least several full rounds and record per-tick
   displacement, desired/actual velocity, collision contacts, path progress,
   time stationary, pair proximity, route completion, and objective outcome.
   Include harsh rendered captures/video at choke points and bomb sites, not
   only a JSON endpoint summary.
