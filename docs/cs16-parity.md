# Counter-Strike 1.6 parity specification

This document is an implementation contract for turning the Godot game into a
mechanically and perceptually faithful Counter-Strike 1.6 compatibility layer.
Its gap matrix records the baseline tree at `59ac009`; the implementation
status immediately below records the first parity tranche built from that
audit. The behavior references are:

- Valve HLSDK commit [`b1b5cf5`][valve] for the public client/engine contract.
- ReHLDS commit [`0124d56`][rehlds] for GoldSrc server timing and movevars.
- ReGameDLL_CS commit [`6799732`][regame] for Counter-Strike gameplay.

ReGameDLL and ReHLDS are behavior references, not automatic permission to copy
their implementation. Before porting source directly, confirm that this
project's distribution model is compatible with every upstream license.
Otherwise implement from the behavior and conformance tests below.

## Executive finding

The baseline game is a good playable prototype, but it is not yet a CS 1.6
simulation. Its largest discrepancy was not an individual movement constant:
the BSP and converted MDL data used `0.01 world units/HU`, while the runtime
player model, hull and movement were approximately 2.5 times larger. Relative
to the player, the map was 2.5 times too small. The oversized player-to-map
ratio was a primary cause of crowded spawns and navigation failures.

Exact parity is practical in Godot, but not by tuning `CharacterBody3D`.
GoldSrc player movement uses a swept, axis-aligned box against BSP clip hulls,
explicit multi-plane clipping, step-up/step-down trials, contents queries and
integer-millisecond user commands. Godot's capsule plus `move_and_slide()` has
different contact, slope, stair and corner behavior. Keep Godot for rendering,
audio, UI and platform support; put authoritative movement, traces, weapon
timers and RNG in a deterministic GoldSrc compatibility simulation.

## First parity tranche implemented

The runtime now uses one `0.01 world units/HU` boundary for BSPs, MDLs, player
and bot hulls, movement, navigation, weapon ranges and projectiles. Standing
and crouched player hulls are CS-sized AABBs; the gameplay clock is 100 Hz; the
live player path uses CS acceleration, friction, air acceleration, gravity,
jump, duck and weapon speed constants; AK/Deagle/HE constants, deterministic
shared spread, range loss, basic continuation, hitgroup/armor math and recoil
recovery are wired into play. Deterministic movement and ballistics tests cover
those formulas.

This is a foundation, not a claim of finished parity. The largest remaining
blockers are still E2 (the custom swept-AABB/BSP PM kernel), E3 (removing
wall-clock and scene-timer gameplay), E4 (runtime BSP entities), complete
studio hitboxes/material traces, and the full weapon/objective/client surface.

## Parity decisions

### Canonical units

Keep authoritative state in GoldSrc units and use one conversion constant at
every Godot boundary:

```text
HU_TO_WORLD = 0.01
WORLD_TO_HU = 100
```

The choice of Godot world-unit magnitude is arbitrary; relative scale and
consistent conversion are what determine GoldSrc behavior. `0.01` preserves
the existing BSP and MDL artifacts and avoids a needless re-export. Convert
BSP vertices, entity origins, clip hulls, MDL vertices, navigation data,
traces, effect distances and test fixtures from the same constant. Do not
compensate with per-node model scales.

At this scale the CS standing hull is `32 × 32 × 72 HU`
(`0.32 × 0.32 × 0.72` world units) and the crouched hull is
`0.32 × 0.32 × 0.50`.
The authoritative hull is an AABB, not a capsule. In a feet-level Godot
wrapper, the standing eye is `(36 + 17) HU = 0.53` world units above the
floor; the crouched eye is `(18 + 12) HU = 0.30`. See [util.h][hulls].

### Canonical simulation clock

Set the deterministic gameplay clock to **100 Hz** (`dt = 0.010 s`). This
matches ReHLDS defaults `sys_ticrate=100` and `fps_max=100`; see
[host.cpp][host]. GoldSrc movement itself consumes the integer `msec` carried
by each `usercmd`, so preserve that field even when initially emitting one
10 ms command per simulation tick. Rendering must interpolate independently.

The project now runs Godot physics at 100 Hz and sends 20 Hz partial
snapshots. A 20 Hz
snapshot stream is acceptable as a configurable network presentation rate
(ReHLDS defaults permit 10–30 updates/s), but it must not be the gameplay
clock.

Deterministic timing acceptance:

1. Replay the same 10,000-command seeded tape while rendering at 30, 60, 100
   and 144 fps.
2. Hash authoritative position, velocity, flags, weapon state, ammo, health
   and RNG state after every 100 Hz tick.
3. All four hash streams must be identical. Events must occur on the same
   tick. When compared with the GoldSrc oracle, position error must be at most
   `1/32 HU`, velocity error at most `1/100 HU/s`, and timers at most one
   10 ms tick. Collision-side and round-state decisions allow no tolerance.

### Status and priority

- **Partial**: recognizable subset exists but does not follow the source
  algorithm.
- **Missing**: no runtime implementation.
- **Incorrect**: implementation exists but has materially different behavior.
- **P0**: foundation or match-breaking parity.
- **P1**: required for a credible complete bomb-defusal match.
- **P2**: required for broad CS 1.6 feature/perceptual parity.

## Engine-level blockers

| Blocker | Current state | Required implementation | Exit test |
|---|---|---|---|
| E1 — world scale | **Partial after first tranche.** The baseline mixed `0.01` BSP/MDL data with runtime characters roughly 2.5× larger. Runtime BSP, player/bot hulls, MDLs, movement, navigation, ranges and projectiles now consistently use `0.01`; simulation state is not yet stored natively in HU. | Keep authoritative simulation in HU and enforce one conversion boundary in exporters, runtime services and fixtures. | Dust2 world bounds, all 40 spawn origins and two bomb volumes equal source BSP coordinates after round-trip conversion within `1/32 HU`; standing hull fits adjacent 96 HU spawns without overlap. |
| E2 — collision kernel | **Incorrect.** Capsule `CharacterBody3D.move_and_slide()` against rendered triangle soup. | Deterministic swept AABB, BSP clip-hull/content queries, five-plane clipping, `PM_FlyMove`, `PM_WalkMove` up/down step trial, ground categorization, base velocity and stuck recovery from [PM][pm]. A native GDExtension is appropriate; a fully deterministic GDScript port is acceptable if it passes the oracle. | Command-tape corpus covering flat ground, 18 HU stair, ramp, wall seam, acute corner, ceiling duck and moving pusher matches oracle tolerances. |
| E3 — fixed clock and clocks domain | **Partial after first tranche.** Physics now runs at 100 Hz, but gameplay still mixes `_physics_process`, render `_process`, `Time.get_ticks_msec()` and scene timers. | One 100 Hz authoritative tick; tick-indexed movement, weapons, grenades, rounds and entities. Wall time is presentation only. | Timing test above; pausing, rendering stalls and host frame rate do not change simulation hashes. |
| E4 — BSP entity runtime | **Missing.** Brush models are folded into static collision. Entity keyvalues are mostly inert. | Preserve model-local brush geometry and instantiate target/killtarget, use/touch, spawnflags, master, delay, wait, speed, lip, damage and round reset semantics. Implement GoldSrc `MOVETYPE_PUSH`, triggers and contents. | Entity I/O fixture plus every entity in stock Dust2 executes the same state/event trace as HLSDK/ReGameDLL. |
| E5 — deterministic trace/RNG service | **Partial after first tranche.** Exact shared-float/spread helpers and live range/continuation math exist, but rays still use Godot, the seed is not yet carried by `usercmd`, and BSP collision lacks material metadata/GoldSrc hitboxes. | Authoritative line/hull traces with hitgroups, texture material, penetration continuation and a shared usercmd seed. Expose the same service to local prediction, server and bots. | 10,000 seeded shots produce identical spread offsets, hit entities, hitgroups, penetration exits and damage on client and server. |
| E6 — authoritative network simulation | **Missing.** ENet transfers input and a partial local snapshot, but does not simulate remote actors or reconcile clients. | Server owns all entities. Client predicts its own movement/weapons using the shared kernel, buffers commands, reconciles from acked commands, interpolates others, and receives reliable discrete events. Add interest/PVS, lag compensation and reconnect/state baselines. | Two clients at 0/50/100 ms latency and 0/2% loss converge; local correction stays under `1 HU` in ordinary movement; server hit results remain authoritative and deterministic. |
| E7 — CS client oracle | **Blocked on capture harness.** Valve publishes the HLSDK interface but not all CS 1.6 client HUD/crosshair/viewmodel behavior. | Add automated black-box captures from a pinned Steam CS 1.6 build: usercmds, camera/FOV, crosshair, HUD pixels, weapon event timings and audio event logs. Treat those recordings as golden fixtures. | Pinned version/build metadata and golden captures exist for every supported weapon, stance, aspect ratio and round event. |

Do E1–E5 before attempting fine movement or weapon tuning. Otherwise later
constants will be calibrated against the wrong geometry and clock.

## Mechanical gap matrix

The rows below are ordinary gameplay, presentation, content and test work once
their `E*` dependencies are complete. A row that calls for a source algorithm
still belongs in the compatibility layer, but it does not require replacing
Godot itself. The engine-level architectural decisions are isolated above.

### Movement and collision

| ID | Current state | Exact CS 1.6 target and source | Dependency | Pri | Deterministic acceptance test |
|---|---|---|---|---|---|
| M1 hull/origin | **Partial after first tranche.** Human and bot colliders are scaled `32×32×72 HU` AABBs and the standing eye is `53 HU` above the feet. The runtime still uses a feet-level Godot origin rather than GoldSrc's centered origin, and duck-origin shifting is approximate. | AABBs: stand mins/maxs `(-16,-16,-36)/(16,16,36)`, crouch `(-16,-16,-18)/(16,16,32)`; views `17/12 HU` [hulls]. Preserve GoldSrc origin shifts during duck. | E1, E2 | P0 | All six hull extents and eye origins equal source; a 33 HU corridor passes and a 31 HU corridor blocks exactly as oracle. |
| M2 ground acceleration | **Partial.** The first tranche now uses the CS multiplayer values and formula, but lacks the edge trace and custom collision kernel. | `sv_accelerate=5`, `sv_friction=4`, `sv_stopspeed=75 HU/s`; `accelspeed=accel*frametime*wishspeed*player_friction` [rounds], `PM_Accelerate`/`PM_Friction` [pm]. Preserve the source edge-friction trace where configured. | E1–E3 | P0 | From rest and from 250 HU/s, forward/reverse/coast tapes match velocity every tick; ledge case applies edge friction on the same tick. |
| M3 weapon speed / walk | **Partial after first tranche.** AK uses `221 HU/s`; Deagle, knife and HE use `250 HU/s`; Shift scales commands by `0.52` and duck by `0.333`. Inventory/usercmd integration and the pinned client-profile oracle remain. | Active weapon caps: AK `221 HU/s`; Deagle, knife and HE `250 HU/s` [ak], [deagle], [weapons]. `+speed` scales generated forward/side commands using the CS client `cl_movespeedkey` profile; crouch multiplies command components by `0.333` [pmh]. The commonly shipped CS profile is `0.52`, but E7 must pin the actual target build before freezing that default. | E3, E7, inventory | P0 | For each weapon × stand/walk/crouch, 5 s terminal speed differs by no more than `0.01 HU/s`; switching AK→knife changes cap on the next command. |
| M4 air movement | **Partial after first tranche.** `sv_airaccelerate=10` and the `30 HU/s` add-speed cap now match `PM_AirAccelerate`; exact plane clipping and base velocity still require E2. | `sv_airaccelerate=10`; `PM_AirAccelerate` caps `wishspd` used for add-speed to `30 HU/s` while acceleration magnitude uses uncapped wishspeed [pm]. Preserve plane clipping and base velocity. | E2, E3 | P0 | 90° air-strafe and alternating strafe tapes match oracle position/velocity over 300 ticks. |
| M5 gravity/jump/stamina | **Partial after first tranche.** Gravity, jump impulse, release-gated jumping and the `1.2×`/`0.8` mega-bunny crop match source constants. Jump stamina and the custom collision clock remain. | `sv_gravity=800 HU/s²`, jump impulse `sqrt(2*800*45)=268.328157 HU/s`, jump stamina `fuser2=1315.789429`, per-frame stamina speed penalty, no pogo until release, mega-bunny limit `1.2× maxspeed` with `0.8` crop [pm], [svphys]. | E1–E3 | P0 | Single jump apex/time, five repeated jumps and >300 HU/s bunny entry match oracle every tick. |
| M6 duck transition | **Partial after first tranche.** Shooting while ducked works; the collider, `0.4 s` spline eye transition and `0.333` command multiplier are present. Air-duck origin shifting, uncrouch hull traces and stuck correction remain approximate. | `TIME_TO_DUCK=0.4 s`, spline view transition, immediate completion in air, command multiplier `0.333`, origin adjustment, stand-up hull trace and stuck correction [pm], [pmh]. Shooting remains legal while ducking. | E2, E3 | P0 | Duck/unduck at 0, 100 and 250 HU/s; low-ceiling and air-duck tapes match hull, view and flags on every tick. |
| M7 stairs/slopes/grounding | **Incorrect.** Godot floor snap `0.22 m`, max slope `48°`. | `sv_stepsize=18 HU`; GoldSrc tries direct slide versus step-up/slide/step-down and chooses greatest horizontal distance; uses plane normals and `PM_CategorizePosition`, not a generic slope angle [pm], [svphys]. | E2 | P0 | 17.99 HU stair succeeds, 18.01 HU stair blocks; canonical Dust2 stair and ramp trajectories match oracle. |
| M8 falling | **Missing.** No fall damage, landing punch or landing sounds. | Damage-safe fall `500 HU/s`, fatal `1100 HU/s`, damage `100/(1100-500)` per excess HU/s [playerh]. The separate PM step/sound threshold is `580 HU/s`; landing punch begins at `250 HU/s` [pmh]. | E2, damage | P1 | Falls at 499, 500, 800 and 1100 HU/s produce exact health, armor immunity, sound and punch events. |
| M9 ladders | **Missing.** `func_ladder` is inert/static. | Ladder contents detection, `MOVETYPE_FLY`, max climb `200 HU/s`, view-relative projection, crouch multiplier and jump-off velocity `270 HU/s` along ladder normal in `PM_LadderMove` [pm]. | E2, E4 | P1 | Mount, climb, lateral move, crouch and jump-off fixture matches position/velocity/movetype each tick. |
| M10 water/contents | **Missing.** Liquid surfaces are translucent visuals only. | `waterlevel/watertype`, swim speed `0.8×`, water friction/acceleration, idle sink `60 HU/s`, jump vertical `100/80/50` for water/slime/lava, water-jump and splash/wade events [pm]. | E2, E4 | P1 | Enter/exit at three depths, swim, sink and water-jump command tapes match oracle flags and velocity. |
| M11 pushers/conveyors | **Missing.** Doors/trains are static; no base velocity. | GoldSrc `MOVETYPE_PUSH`, blocking/reversal/crush, `basevelocity`, conveyors and moving-ground carry from [doors], [plats], [pm]. | E2, E4 | P1 | Player riding, blocking and being pushed by linear/rotating doors and train matches entity/player transforms and damage ticks. |
| M12 material footsteps | **Partial.** Four generic steps, distance-based cadence, silent walk/crouch. | `PM_UpdateStepSound` timers and volume by speed, ladder/wade states and texture material mapping (concrete, metal, dirt, vent, grate, tile, slosh, snow) [steps]. | E2, texture service | P1 | Material strip at walk/run/crouch emits the same sample class, volume and command tick as oracle. |

### Weapons and inventory

| ID | Current state | Exact CS 1.6 target and source | Dependency | Pri | Deterministic acceptance test |
|---|---|---|---|---|---|
| W1 inventory model | **Incorrect.** Player always owns AK, Deagle, knife and optionally HE; buys refill guns. | Five slots, at most one primary and secondary, shared ammo pools, exhaustible grenade rules, C4/defuser/shield state, pickup/drop/death weapon boxes and auto-switch. Definitions and caps come from [weapontype]. | E3, entity runtime | P0 | Scripted buy/pickup/drop/death/restart tape matches weapon bits, slots, clips and reserve ammo after every event. |
| W2 complete arsenal | **Missing.** 4 of the CS arsenal are playable. Assets exist for most original weapons, but generated runtime data covers only four viewmodels and one attached AK. | Implement P228, Glock18, Scout, HE, XM1014, C4, MAC10, AUG, smoke, Elite, Five-Seven, UMP45, SG550, Galil, Famas, USP, AWP, MP5, M249, M3, M4A1, TMP, G3SG1, flashbang, Deagle, SG552, AK47, P90, knife and tactical shield, using each `wpn_*.cpp`. | W1, E5, asset pipeline | P1 | Data-driven weapon suite verifies item info, team availability, clip/carry, speed, deploy, primary/secondary, reload and empty behavior for every item. |
| W3 weapon clock | **Incorrect.** Fire uses wall-clock milliseconds; reload uses scene timers. | Tick/usercmd weapon time, `m_flNextPrimaryAttack`, `m_flNextSecondaryAttack`, `m_flTimeWeaponIdle`, `m_flNextAttack`; predicted server/client `ItemPostFrame`. Switching/death interrupts reload. See [weaponbase] and Valve `HUD_PostRunCmd` contract [api]. | E3, E6 | P0 | Fire/reload/switch command tape at four render rates has identical shot and ammo event ticks; client/server weapon state hashes agree. |
| W4 AK-47 | **Partial after first tranche.** Base damage, speed, ammo, cycle, reload, range, penetration count, falloff, stance spread and KickBack branches now use source constants. The wall-clock weapon timer and approximate hit traces prevent deterministic parity. | `36` base damage, `221 HU/s`, 30/90 ammo, `0.0955 s`, `2.45 s`, range `8192 HU`, two penetrations, range modifier `0.98`; accuracy `min(shots³/200+0.35,1.25)`, stance/movement spread branches and source `KickBack` branches [ak]. | E3, E5 | P0 | 30-round burst in four stances matches every spread pair, punch angle, shot tick, clip and damage; reload completes at 2.45 s exactly. |
| W5 Desert Eagle | **Partial after first tranche.** Damage, speed, ammo, cycle, reload, range, penetration count, falloff, accuracy recovery and stance spread now use source constants. The weapon clock, hit traces and complete animation events remain. | `54`, `250 HU/s`, 7/35, effective cycle `0.225 s`, reload `2.2 s`, range `4096 HU`, two penetrations, range modifier `0.81`; accuracy clamps `0.55..0.9` from time since shot and stance branches [deagle]. | E3, E5 | P1 | Seven paced and seven fastest shots in four stances match spread, recoil, shot ticks, range damage and ammo. |
| W6 knife | **Incorrect.** One `65`-damage, `2.15 m` ray every `0.48 s`; no secondary or hull trace. | Primary slash `15` damage (`20` fast follow-up), `48 HU`; secondary stab `65`, `32 HU`; backstab `3×`; line then hull trace, distinct hit/miss delays and sounds [knife]. | E2, E3, E5 | P1 | Front/back, line/hull edge, player/world hit and miss cases match damage and next-attack tick for both buttons. |
| W7 reload/deploy/animation | **Partial.** Single reload sound and static timing; no draw lockout, staged sounds, shells or idle events. | Source sequence timing, deploy extensions, empty clicks, magazine transfer completion, bolt/shell events and player third-person animations for every weapon. | W2, MDL event pipeline | P1 | Event trace and rendered sequence frame at every 10 ms tick match golden client capture for one complete lifecycle per weapon. |

### Ballistics, damage and armor

| ID | Current state | Exact CS 1.6 target and source | Dependency | Pri | Deterministic acceptance test |
|---|---|---|---|---|---|
| B1 spread RNG | **Partial after first tranche.** Shared uniform spread consumption is deterministic and source-shaped, but the seed is local shot state rather than an authoritative usercmd shared seed. | Usercmd shared seed; spread offsets are sums of two shared uniform `[-0.5,0.5]` values per axis, consumed in fixed order by `FireBullets3` [ballistics]. | E5 | P0 | First 10,000 offsets for fixed command seeds equal oracle bit-for-bit after chosen float normalization. |
| B2 range falloff | **Implemented for AK/Deagle in first tranche.** The live trace applies source range modifiers by traveled GoldSrc distance; the remaining risk is E5's trace oracle. | Damage is multiplied by `range_modifier^(distance/500 HU)` after each trace segment; AK `0.98`, Deagle `0.81` [ballistics]. | E1, E5 | P0 | Targets every 500 HU produce the same integer damage as source for both guns. |
| B3 penetration/materials | **Partial after first tranche.** AK/Deagle continuation count, caliber power/distance and generic surface continuation are live. BSP texture material metadata and exact entry/exit traces remain. | Penetration counts, power/distance by caliber (7.62: `39/5000 HU`; .50AE: `30/1000 HU`) and texture modifiers for metal, concrete, grate, vent, tile, computer and wood [ballistics]. | E2, E5, BSP textures | P0 | Canonical material/thickness stack produces same exit/no-exit, residual range and damage for AK/Deagle. |
| B4 hitboxes/hitgroups | **Incorrect.** One capsule and a world-height head threshold. | Studio model hitboxes transformed by bones; groups generic/head/chest/stomach/arms/legs/shield. Multipliers: head `4`, chest/arms `1`, stomach `1.25`, legs `0.75` in `CBasePlayer::TraceAttack` [player]. | Animated skeleton, E5 | P0 | Static and animated pose ray corpus hits same hitbox/group and distance as oracle; no visual-pose/collision divergence over sequences. |
| B5 armor/helmet | **Partial after first tranche.** Bullet and HE health/armor depletion, weapon ratios and helmet coverage use source formulas. Inventory acquisition and studio-hitbox hitgroups are still incomplete. | Kevlar covers torso/arms, helmet additionally head, never legs. Base `ARMOR_RATIO=.5`, `ARMOR_BONUS=.5`; weapon ratio modifiers include AK `×1.55`, Deagle `×1.5`; apply source depletion formula [player], [playerh]. | B4, inventory | P0 | 100 armor/helmet target hit in every group by AK/Deagle matches health and armor after each shot; no helmet head case takes full head damage. |
| B6 friendly fire/impulse | **Incorrect.** Teammate damage is rejected unconditionally; no hit impulse or flinch. | `mp_friendlyfire`, classic teammate damage scaling, grenade self/team rules, large-flinch weapon list, damage punch and velocity impulse from `CBasePlayer::TakeDamage` [player]. | Damage service, cvars | P1 | Enemy/team/self matrix across bullet, HE and fall matches health, velocity, flinch and account penalties. |
| B7 impacts/effects | **Partial.** Temporary line tracer and glowing sphere impact. | Correct decals by material, sparks, blood, helmet sparks, shell ejection, muzzle flash, smoke and sound events, with PVS/PAS visibility [ballistics], [player]. | E5, effects/assets | P2 | Seeded shot scene emits the same typed effect-event list; screenshot/audio golden comparison meets perceptual thresholds. |

### Grenades

| ID | Current state | Exact CS 1.6 target and source | Dependency | Pri | Deterministic acceptance test |
|---|---|---|---|---|---|
| G1 HE input/throw | **Partial after first tranche.** Pitch remap, capped velocity, 16 HU start offset, full player velocity and `1.5 s` fuse now match source constants. Pin-pull/release state and tick-owned timing remain. | Press pulls pin; release/idle throws. Pitch remap yields `flVel=(90-angle.x)*6`, capped `750 HU/s`; start `view + forward*16`, add full player velocity; timed fuse `1.5 s` [he]. | E3, E5 | P1 | Nine pitch × movement cases match spawn, velocity and detonation tick; holding pin never cooks/detonates. |
| G2 HE physics/damage | **Partial after first tranche.** Gravity, elasticity/friction approximation, stop threshold, `100` base damage, `350 HU` radius, linear falloff and explosion armor are implemented. Exact GoldSrc toss collision, water handling and trace semantics still require E2/E4. | Toss/bounce semantics, HE gravity `0.55×800`, friction `0.7`; `100` damage and `350 HU` radius with linear falloff (`RadiusDamage`), water boundary rules and classic through-wall behavior [grenade], [radius]. | E2–E5 | P1 | Bounce fixture and targets every 25 HU to 350 HU match transform and integer damage; water and owner/team cases match. |
| G3 flash/smoke | **Missing.** | Flashbang line-of-sight/facing/time and stacking; smoke detonation-on-rest timing, smoke field events and one-smoke carry; max two flashes. Use `wpn_flashbang`, `wpn_smokegrenade`, `ggrenade.cpp`. | E2–E5, assets | P1 | Golden positions/ticks plus visibility/facing flash matrix and smoke-rest fixture match source event state. |

### Buy and economy

| ID | Current state | Exact CS 1.6 target and source | Dependency | Pri | Deterministic acceptance test |
|---|---|---|---|---|---|
| E01 buy eligibility | **Incorrect.** Four F-keys buy anywhere during 4 s freeze only. | `func_buyzone` team volumes, `mp_buytime=1.5` minutes from round start (minimum handling), alive/team/map restrictions and buy-anywhere fallback only when the map has no buyzone; `CanPlayerBuy` [buy]. | E4, round clock | P1 | Inside/outside, CT/T, alive/dead and boundary-time table returns same allow/error result as source. |
| E02 catalog/prices | **Partial.** AK 2500, Deagle 650, full suit 1000 and HE 300 match; no team restrictions, ammo or other items. | Full price/team catalog: Kevlar 650, helmet upgrade 350, suit 1000, kit 200, NVG 1250, ammo bundles and every weapon/grenade from [weapontype]. AK is T-only; CT-equivalent rifle is M4A1. | W1, W2 | P1 | Iterate every team/item/ownership/money combination and compare result, money, inventory and message token. |
| E03 money/rewards | **Partial.** $800 start/$16000 cap/$300 kill; fixed $3250 T win and $1400 CT/loss path. | Scenario rewards and escalating loss bonus: T/CT ordinary win `3000`, bomb target `3500`, defuse/explode/saved `3250`, plant `800`, kill `300`; loss `1400`, then `1500..3000` in `500` steps [economy]. | Round manager | P1 | Ten-round scripted outcome series matches every player's account after kill, plant and round rewards. |
| E04 persistence/default loadout | **Incorrect.** Survivors keep loadout; dead player resets to zero AK plus Deagle; bots do not buy. | Team spawn pistols/knife, surviving inventory persistence, dropped weapon behavior, ammo/armor persistence and round C4/kit assignment as `RestartRound`/player spawn specify. | W1, rounds | P1 | Survivor/death/team-switch/restart fixture matches all inventory/account states. |

### Rounds and objectives

| ID | Current state | Exact CS 1.6 target and source | Dependency | Pri | Deterministic acceptance test |
|---|---|---|---|---|---|
| R1 cvars/state machine | **Partial.** Freeze 4, live 115, C4 35, post 2.6 seconds; one local match. | Compatibility defaults: `mp_freezetime=6`, `mp_roundtime=5` minutes, `mp_c4timer=45`, `mp_round_restart_delay=5`; expose cvars so 1.6 league profiles can choose 1.75/15/35 etc. Phases and scenario checks follow `CHalfLifeMultiplay` [gamecvars], [rounds]. | E3 | P0 | For each outcome and a custom league profile, state transitions, timer messages and restart tick equal source. |
| R2 bomb ownership/plant | **Incorrect.** Human always plants by holding Use near hard-coded points for 3.2 s; no C4. | One T receives C4; equip C4 and hold primary attack while grounded in `func_bomb_target`; arm time `3.0 s`, interrupt on release/zone/ground loss, freeze movement, create dropped/planted C4 and grant plant reward [c4]. | E4, W1, E3 | P0 | Ownership/drop/pickup and all plant interruption cases match source tick/event/account traces. |
| R3 defuse/explosion | **Missing.** No CT defuse or bomb damage; timer directly awards T. | Use planted bomb; freeze defuser; `10 s` without kit, `5 s` with kit, abort conditions, C4 timer from cvar, beep cadence, explosion radius/damage and race handling [defuse], [grenade]. | E3–E5, inventory | P0 | Kit/no-kit, abort/death and final-tick defuse-vs-explode races match source winner and exact event tick. |
| R4 win conditions | **Partial.** Elimination/time/bomb for this hard-coded scenario. | Bomb, hostage, VIP and escape scenario checks, game commence, draw, team population, time expiry (bomb remains live after expiry), max rounds/win limit and intermission [rounds]. | E3, E4 | P1 | Exhaustive scenario truth table returns same winner/reason/reward; planted bomb prevents premature T-elimination/timeout resolution. |
| R5 reset completeness | **Partial.** Players/bots/bomb reset; static map state never changes. | Restart players, hostages, C4, weapons and every resettable breakable, door, button, trigger, water and train class in `RestartRound` [rounds]. | E4 | P1 | Mutate all entity classes, end round, then compare complete state hash with fresh-map round start. |
| R6 other objectives | **Missing.** Only bomb-defusal flow. | Hostages/rescue zones, VIP/escape and assassination maps with exact rewards and bot states. | E4, bots, assets | P2 | One deterministic complete round for each stock scenario matches source event/reward trace. |

### Doors, ladders, water and triggers

| ID | Current state | Exact CS 1.6 target and source | Dependency | Pri | Deterministic acceptance test |
|---|---|---|---|---|---|
| T1 brush models | **Incorrect.** `func_breakable`, door, rotating door, pushable, train and wall geometry is merged into one static body. | Independent brush-local transforms, solid/content type and entity lifetime; world model 0 remains static. | E1, E4 | P0 | Every submodel's world vertices equal BSP source before/after entity movement and never appear in world static collision simultaneously. |
| T2 doors/buttons/trains | **Missing.** | Linear/rotating door spawnflags, linked doors, use/touch, wait/lip/speed, sounds, blocking/crush/reverse; buttons, plats, trains/path corners [doors], [plats], [buttons]. | E2, E4 | P1 | Fixture exercises toggle, locked, linked, blocked and round reset; state and transforms match HLSDK every tick. |
| T3 breakables/pushables | **Missing.** Static collision only. | Health/material, weapon/explosion damage, shards/sounds, target firing, pushable mass/friction and spawnflags from `func_break.cpp`. | E2, E4, damage | P1 | All material/weapon cases produce same break tick, target event, collision removal and effect type. |
| T4 triggers/target graph | **Missing.** Buy/bomb are hard-coded and other triggers inert. | Touch/use target graph plus `trigger_once/multiple/hurt/push/teleport/gravity`, relays, counters, autos, changetarget, ambient/music and round reset [triggers]. | E4 | P1 | Synthetic graph produces identical ordered I/O and damage/velocity effects under simultaneous touches. |
| T5 contents | **Missing.** No ladder/water/slime/lava/sky semantics. | BSP point contents and brush contents feed movement, bullets, audio and effects; `func_ladder` sets `CONTENTS_LADDER` [triggers]. | E2, E4 | P1 | Dense 3D content sampling agrees with BSP oracle; movement selects same movetype/waterlevel. |

### Sound, HUD, view and input

| ID | Current state | Exact CS 1.6 target and source | Dependency | Pri | Deterministic acceptance test |
|---|---|---|---|---|---|
| P1 HUD | **Partial.** Core sprite HUD and 640-reference team/class/buy/scoreboard/ESC shells are implemented; the modern match/deploy/settings cards and hitmarker are removed. Missing authoritative input/session bindings, VGUI portraits/logo/font/sounds, weapon selection, death notices, chat/radio, progress, spectator, and console flows. | Reproduce CS 1.6 sprite/font HUD: health/armor/ammo/money, round timer, weapon selection, radar/overview, scoreboard, death notices, chat/radio, status/progress icons, buy/team/class menus and spectator UI. CS 1.6 has no hit-confirmation marker. | E7, asset/sprite pipeline | P1 | Pixel diff against golden captures at 640×480, 800×600, 1280×720 and 1920×1080; no element exceeds 1 px geometry or defined color tolerance. |
| P2 projection/camera | **Partial.** Godot vertical FOV defaults to 74 and clamps pitch ±89; custom bob. | Match GoldSrc projection/aspect behavior for `default_fov=90`, zoom FOVs, view height, punch angles, stair smoothing, landing and bob. Do not equate a Godot vertical FOV with GoldSrc's cvar without conversion [view], E7. | M1, E7 | P0 | Camera matrices and screen-space coordinates of calibration points match golden capture across aspects/FOVs; bob/punch trace matches per frame. |
| P3 mouse/usercmd input | **Partial.** Raw mouse is accumulated into direct degrees/pixel; fixed binds; no console/bind layer. | GoldSrc button fractions and `CL_CreateMove`, sensitivity × `m_yaw/m_pitch` (defaults `0.022`), optional accel, zoom sensitivity, command msec, binds/aliases and simultaneous-button semantics [input]. | E3, E7 | P0 | Raw delta/button event tape yields identical viewangles, forward/side/up move, buttons, impulse and msec fields. |
| P4 sound propagation | **Partial.** A few local samples; bots do not hear gameplay events. | Original samples/channels, attenuation, pitch, PAS-style audibility, material steps, weapon/reload/impact/ricochet, pain/death, radio/announcer, C4 and ambience. Emit semantic sound events for bot hearing. | E4, assets, bots | P1 | Event log fixture matches sample/channel/volume/attenuation/pitch tick; occluded-distance audio render meets golden loudness tolerance. |
| P5 rendering | **Incorrect for identity.** Filmic tonemap, global sun/fog/shadows and nearest materials overlay converted light colors. | GoldSrc lightmaps/lightstyles, overbright/gamma, fullbright, skybox, animated/turbulent/scrolling textures, transparency modes, decals, sprites, MDL render modes and visibility/PVS. Avoid modern effects in parity preset. | BSP/MDL renderer | P2 | Reference viewpoints on each map meet SSIM/color thresholds and animated surfaces match phase/timing. |

### Bots and navigation

| ID | Current state | Exact CS 1.6 target and source | Dependency | Pri | Deterministic acceptance test |
|---|---|---|---|---|---|
| AI1 navigation representation | **Partial.** Runtime Godot navmesh bake, capsule avoidance and nearest-enemy destination. | CS nav areas/connections, ladders, hiding spots, encounter paths and place names; parse/generate compatible `.nav` data and route by area cost [botnav]. | E1, E4 | P1 | Route corpus on each map returns same traversed areas and ladder decisions for fixed costs; no spawn overlap/stuck timeout. |
| AI2 behavior state machine | **Missing.** Hunt nearest, LOS, circular strafe and fire. | Buy, idle, hunt, attack, hide, investigate noise, follow, move-to, fetch/plant/defuse bomb, use entity and escape bomb states with team roles [botstates]. | Mechanical systems, AI1 | P1 | Scripted world/event tapes produce same high-level state transitions and objective completion as reference bot. |
| AI3 perception/aim/fire | **Incorrect.** Perfect ray LOS to aim point, fires random 6–10 damage every 0.12–0.22 s inside range. | Vision/FOV/recognition/reaction, hearing semantic sounds, aim skill/error, friendly-fire checks and the exact shared weapon simulation/inventory [botvision], [botweapon]. | E5, W1–W5, P4 | P1 | Skill-seeded duel fixture matches reaction distribution bounds, shot event legality and uses identical weapon damage/ballistics. |
| AI4 locomotion/avoidance | **Incorrect.** Navigation velocity bypasses player acceleration and uses Godot RVO at `3.4 m/s`. | Bots issue the same usercmds and run the same PM kernel as humans; avoidance is tactical/path intent, never a second motion solver. Include jump, crouch, ladder, door and stuck monitor. | E2, AI1 | P0 | Human and bot receiving the same command tape have identical transform hashes; 10-bot spawn exits without overlap or off-mesh motion. |
| AI5 teamwork/radio | **Missing.** | Squad roles, follow requests, bomb carrier coordination, guarding, retreat, radio/chatter and place knowledge. | AI2, P4 | P2 | Seeded 5v5 scenario meets expected role/state/event trace without duplicate objective ownership. |

### Networking and tickrate

| ID | Current state | Exact CS 1.6 target and source | Dependency | Pri | Deterministic acceptance test |
|---|---|---|---|---|---|
| N1 fixed simulation | **Partial.** Godot physics is now 100 Hz; usercmd msec, authoritative tick ownership and render-rate-invariant state are not complete. Snapshots remain 20 Hz. | 100 Hz compatibility tick; integer-msec usercmd cadence; render interpolation; configurable 10–30+ snapshot rate. ReHLDS defaults `sys_ticrate/fps_max=100`, max update 30 [host], [server]. | E3 | P0 | Timing acceptance suite in “Canonical simulation clock.” |
| N2 server authority | **Missing.** Input is stored but not consumed to drive remote actors; snapshots only include one position/velocity/health/phase/time. | Server-simulated players, weapons, entities, rounds, bots and RNG; command sequence/ack; baseline/delta state and reliable events. | E5, E6 | P0 | Headless 10-player match state hashes are identical with or without connected render clients. |
| N3 prediction/reconciliation | **Missing.** | Share PM and weapon code between local prediction and authority, buffer unacked commands, rewind/replay on snapshot, interpolate remote actors [api]. | E2, E3, E6 | P0 | Under deterministic 100 ms/2% network simulation, client converges after every ack and produces no duplicate weapon/effect events. |
| N4 lag compensation | **Missing.** | Pin CS 1.6 `sv_unlag` behavior from ReHLDS target build; store history, validate command time, rewind eligible player hitboxes for authoritative traces, then restore. | E5, E6, E7 | P1 | Moving-target latency matrix matches pinned server hit/miss results and never rewinds world/unsupported entities. |
| N5 session/product behavior | **Partial.** Host/join ENet, max 10 clients, no teams/chat/spectator/reconnect. | Up to 32 client slots, join/team/class flow, spawn/spectate/HLTV-like observers, scoreboard/chat/radio, disconnect/reconnect and map change. Protocol compatibility with GoldSrc is **not** required unless made a separate goal. | E6, HUD, rounds | P2 | 32-peer soak plus join/leave/team/spectator/map-change scenario completes without divergent authoritative hashes. |

### Maps and assets

| ID | Current state | Exact CS 1.6 target and source | Dependency | Pri | Deterministic acceptance test |
|---|---|---|---|---|---|
| A1 map coverage | **Partial.** Runtime loads only converted `de_dust2`; repository has at least Dust2, Nuke, Inferno, Aztec, Prodigy, Cbble, Train, CPL Mill and CPL Strike BSPs. | Load each BSP generically, using its entities rather than hard-coded Dust2 sites/spawns. Define “stock parity” and “third-party compatibility” corpora separately. | E1, E4 | P1 | Every corpus map loads without hard-coded coordinates; entity/model/texture/content counts match exporter manifest and a full bot round completes. |
| A2 BSP fidelity | **Partial.** Render triangles, UVs/colors and world collision exist; clipnodes, leaves/PVS, light styles and runtime entities do not. | Preserve planes/nodes/clipnodes/leaves/models/visibility/lightmaps/entities/textures and hull queries. | E1, E2, E4, renderer | P0 | Structural manifest matches BSP lump counts; random trace/content/PVS queries agree with oracle. |
| A3 asset coverage | **Partial.** Many original weapon/player/world models and sounds are already under `public`, but the Godot import only packages a subset. | Manifest-driven WAD/MDL/SPR/WAV/sky/decal import with sequence events, bodygroups, skins, animation, palettes, transparency and missing-asset report. | Importers, legal provenance | P1 | Required-asset manifest for every map/weapon resolves 100%; hashes/provenance recorded; no runtime “optional assets unavailable.” |
| A4 map navigation | **Partial.** Runtime navmesh baking loses CS area semantics and changes with geometry settings. | Versioned, offline deterministic nav generation or import of matching CS `.nav` files, including places/hiding/encounters/ladders. | AI1, E4 | P1 | Nav artifact hash is stable across machines and passes route corpus for every map. |
| A5 perceptual assets | **Partial.** Original player skins/AK are present; third-person inventory models and animations are incomplete. | Original view/player/world models for every item, player sequence selection, attachments, death variants, shells, sprites, HUD assets, radio and map ambience. | W2, renderer | P2 | Asset/sequence/event matrix has no fallback meshes; golden multi-angle captures pass. |

## Critical path

### Stage 0 — freeze the oracle and legal boundary

Pin the Steam CS 1.6 build/config, the three source commits above, canonical
cvars and the test maps. Build the E7 capture harness. Decide whether the
compatibility layer is a clean-room implementation or a license-compliant
source port. This prevents “identical” from moving between modern Steam,
`steam_legacy`, ReGameDLL fixes and league configurations.

### Stage 1 — scale, BSP query and 100 Hz simulation

Complete E1–E5. Keep Dust2 and MDLs on the canonical `0.01 world units/HU`
boundary, retain authoritative state in HU, replace `move_and_slide()` with
swept AABB/BSP hull movement, add content and
material queries, shared RNG and the 100 Hz tick. Finish M1–M8 before adding
more gameplay. This stage should produce a movement-only executable whose
command tapes pass the GoldSrc oracle.

### Stage 2 — one exact combat slice

Implement inventory foundations plus AK, Deagle, knife, hitboxes, penetration,
damage, armor and exact input/camera. Use only human-versus-static targets at
first. The exit criterion is deterministic parity for W1, W3–W6 and B1–B6,
not visual plausibility.

### Stage 3 — one exact Dust2 bomb round

Implement brush entities/buy and bomb volumes, C4 ownership/plant/defuse,
economy, round reset, doors/breakables and HE/flash/smoke. Then route bots
through the same command and weapon simulation. Exit only when a seeded 5v5
Dust2 round is reproducible headlessly and every state transition is source
equivalent.

### Stage 4 — perceptual CS client parity

Replace the custom HUD, projection, view bob, viewmodel events, soundscape and
modern lighting preset with the captured CS presentation. Keep accessibility
and modern presentation as an optional non-parity preset, never mixed into
golden comparisons.

### Stage 5 — authoritative multiplayer

Build E6 and N2–N4 around the already deterministic simulation. Do not make
network code authoritative before offline command tapes are stable: prediction
requires the exact same movement, traces, weapon clock and RNG on both sides.

### Stage 6 — full arsenal and map corpus

Finish the data-driven weapon catalog, all objective modes, all BSP entities,
asset manifests and deterministic navigation artifacts. Run movement, entity,
weapon, bot, network, pixel and audio suites on the full corpus in CI.

## Required conformance harnesses

The parity work should add these test layers rather than relying on subjective
playtesting:

1. **C++ source oracle fixtures**: compile or instrument a legally usable
   reference harness for PM, weapon spread/timing, damage and round rules.
2. **Command-tape runner**: JSON/binary usercmd streams with integer msec,
   viewangles, movement, buttons, impulse and seed; outputs per-tick hashes.
3. **BSP query differential**: randomized line/hull traces, point contents,
   texture material and PVS queries against both implementations.
4. **Entity event traces**: ordered `(tick, entity, input, output, state)`
   records for doors, triggers, C4 and round resets.
5. **Network fault simulator**: deterministic latency, jitter, loss,
   duplication and reordering around multi-client prediction/reconciliation.
6. **Steam client goldens**: frame-perfect HUD/viewmodel/camera captures and
   typed audio/event logs for the closed CS-specific presentation behavior.
7. **Corpus CI**: run all of the above at 30/60/100/144 render fps; gameplay
   hashes may never depend on render rate.

## Source index

Local current-state references are:
`crate/src/bsp.rs::export_godot`,
`crate/src/mdl.rs`,
`game/project.godot`,
`game/scripts/{player,combatant,grenade,game,bsp_map,bot_controller,target,network_session,hud,human_controller}.gd`.

[valve]: https://github.com/ValveSoftware/halflife/tree/b1b5cf5892918535619b2937bb927e46cb097ba1
[regame]: https://github.com/rehlds/ReGameDLL_CS/tree/679973265e1ac99a43193119e0da212ee568f5f9
[rehlds]: https://github.com/rehlds/ReHLDS/tree/0124d56c3d888d922eb045775f71c6682ad1226f
[api]: https://github.com/ValveSoftware/halflife/blob/b1b5cf5892918535619b2937bb927e46cb097ba1/engine/APIProxy.h#L28-L68
[input]: https://github.com/ValveSoftware/halflife/blob/b1b5cf5892918535619b2937bb927e46cb097ba1/cl_dll/input.cpp#L653-L716
[view]: https://github.com/ValveSoftware/halflife/blob/b1b5cf5892918535619b2937bb927e46cb097ba1/cl_dll/view.cpp
[host]: https://github.com/rehlds/ReHLDS/blob/0124d56c3d888d922eb045775f71c6682ad1226f/rehlds/engine/host.cpp#L49-L72
[server]: https://github.com/rehlds/ReHLDS/blob/0124d56c3d888d922eb045775f71c6682ad1226f/rehlds/engine/sv_main.cpp#L105-L195
[svphys]: https://github.com/rehlds/ReHLDS/blob/0124d56c3d888d922eb045775f71c6682ad1226f/rehlds/engine/sv_phys.cpp#L45-L55
[svuser]: https://github.com/rehlds/ReHLDS/blob/0124d56c3d888d922eb045775f71c6682ad1226f/rehlds/engine/sv_user.cpp#L47-L54
[pmh]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/pm_shared/pm_shared.h#L54-L74
[pm]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/pm_shared/pm_shared.cpp
[hulls]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/util.h#L74-L88
[playerh]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/player.h#L57-L74
[player]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/player.cpp#L679-L816
[ak]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/wpn_shared/wpn_ak47.cpp#L78-L184
[deagle]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/wpn_shared/wpn_deagle.cpp#L92-L201
[knife]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/wpn_shared/wpn_knife.cpp
[weapons]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/weapons.h
[weaponbase]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/weapons.cpp
[weapontype]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/weapontype.h
[ballistics]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/cbase.cpp#L1264-L1477
[he]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/wpn_shared/wpn_hegrenade.cpp#L92-L238
[grenade]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/ggrenade.cpp
[radius]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/combat.cpp#L243-L329
[c4]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/wpn_shared/wpn_c4.cpp#L103-L270
[defuse]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/ggrenade.cpp#L1023-L1219
[gamecvars]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/game.cpp#L20-L35
[rounds]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/multiplay_gamerules.cpp
[economy]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/gamerules.h#L116-L150
[buy]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/player.cpp#L4624-L4694
[doors]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/doors.cpp
[plats]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/plats.cpp
[buttons]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/buttons.cpp
[triggers]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/triggers.cpp
[steps]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/pm_shared/pm_shared.cpp#L169-L499
[botnav]: https://github.com/rehlds/ReGameDLL_CS/tree/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/game_shared/bot
[botstates]: https://github.com/rehlds/ReGameDLL_CS/tree/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/bot/states
[botvision]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/bot/cs_bot_vision.cpp
[botweapon]: https://github.com/rehlds/ReGameDLL_CS/blob/679973265e1ac99a43193119e0da212ee568f5f9/regamedll/dlls/bot/cs_bot_weapon.cpp
