# Multiplayer implementation requirements

Status: multiplayer gameplay remains open. The initial review was performed
while the September 8 full-match GPU benchmark ran. Subsequent transport
validation below was implemented and tested after GPU timing finished.

Current release target: **Dust2 only** (user direction, September 8). Defer
Assault-specific work and benchmarks, other maps and map switching. Existing
multi-map tests/evidence remain available but are not additional release scope.
Apply the remaining shared-game and smoothness requirements to Dust2, both teams.

Keep the scope lean: existing Dust2 game plus basic direct host/join and essential
correctness, smoothness and release checks. Reuse existing UI and gameplay.
No accounts, matchmaking, rankings, additional modes or service infrastructure.

## Current evidence

- September 10 lean follow-up: world schema 7 adds a complete, validated broken
  brush list; client Dust2 crate visibility/collision follows the host and resets
  without local damage rules. Grenade pullpin/throw events now drive existing
  presentation, and the importer preserves previously missing grenade animation
  strips. Flash/smoke have their own detonation routing. macOS Ctrl-crouch input
  and occluded-window preparation are fixed. Nineteen focused muted Godot checks,
  one three-model Rust regression and 72 Node checks pass. Final rendered pair
  `YcmLC4` passes (peak chunk/snapshot 1,016/1,391 bytes). This is a staged loopback
  scenario, not full-match, genuine late-join or adverse-network clearance.
  Player collision prediction, missing authored reload sounds, Glock cue choice,
  full-match performance and public shipping clearance remain open.

- September 9 grenade/objective follow-up: world schema 6 carries stable-ID
  grenade flight and persistent smoke with host-owned age, plus owner-only
  planting/defusing progress and flash duration. Clients reconstruct smoke
  from snapshots and display bomb/round results through the existing HUD;
  they do not simulate grenade physics, fuse, damage or objective rules.
  Existing host grenade/C4/round audio and HE/flash/C4 explosion effects use
  the bounded presentation stream. Concurrent grenades have separate audio
  identities. Reliable reload actions replace the lossy one-frame input pulse.
  See production readiness for exact checks, including staged grenade positions
  and the reconstruction test's limits. Brush state, throw-animation parity,
  missing authored sounds, network-condition/full-match and performance work
  remain open. Both peers require the same updated source.

- September 9 combat feedback: host-only reliable presentation events now
  drive owner/remote firing and reload actions, owner camera punch, existing
  catalog audio, muzzle/shell and impact/blood effects, and kill notices.
  Epoch/sequence, snapshot-order and actor-life/round checks prevent duplicate
  or stale presentation without enabling client weapon/damage simulation.
  The new event codec/queue fixture is mandatory in `game:test:network`;
  the actual Dust2 pair also exercises these paths. See the current readiness
  entry for exact verification and limits. This supersedes the missing combat
  event-stream statements in older entries. The newer entry above records
  grenade/objective progress; network-condition, full-match and performance
  requirements remain open.

- September 9: the existing New Game / Find Servers entries now open a lean
  Dust2 host/direct-address form, with validated address/port, status, retry,
  connection/world deadlines and explicit Return Offline. Disconnect rebuilds
  the offline scene rather than partially re-enabling a read-only client.
  Escape reaches the menu before deployment; Resume restores team/class input.
  The silent menu fixture passes malformed endpoints, staged timeout/retry,
  actual ENet hosting, duplicate-start prevention and offline reconstruction.
  The actual two-process Dust2 world pair now clicks Host/Join through viewport
  GUI dispatch before its existing admission, buying, combat and C4 checks.
  Remaining gameplay/latency/presentation requirements below are still open;
  this adds no server discovery, matchmaking or map switching.

- `game/scripts/network_session.gd` opens ENet peers, sanitizes small input and
  snapshot dictionaries, and stores `latest_inputs` / `latest_snapshot`.
  `network_human_controller.gd` now reads validated input through a detached
  `input_for_peer()` accessor and clears ownership on peer/session departure.
  The actual Game now binds the adapter through `remote_human_roster.gd` for
  connected, UNASSIGNED humans. These remain non-solid/inactive until Game's
  authoritative team/class admission methods complete. Reliable client team/class
  requests now invoke those methods and receive owner-only results. Connected
  clients consume host actor snapshots through `network_client_view.gd`.
- `PlayerController.configure_remote_human(slot)` now separates initialization:
  no keyboard controller, viewport takeover, host settings subscription or
  first-person mesh/light for a remote pawn. Existing third-person models follow
  its human simulation. Reserved per-slot audio IDs keep concurrent human voices
  separate. The ownership test covers three pawns and a native rendered pair;
  the loopback fixture also verifies an unchanged local host pawn. The Game roster
  now assigns unique slots and monotonically increasing actor IDs, independent
  of peer IDs and node names, across rematches and host restarts. Actor IDs and
  epochs are replicated; existing client team/class menus send reliable actions.
- `game/scripts/game.gd` now sends all human/bot actor state at 20 Hz with
  per-peer owner identity and consumed-input acknowledgement. Connected clients
  stop offline round/AI/combat simulation and render host actors and public round
  state. Snapshots are strictly validated, ordered and size-bounded/compressed.
  Remote actors interpolate; owner movement now reuses the host movement step
  with consumed-input acknowledgment and bounded unacknowledged replay. Schema
  version 5 added owner movement locks, crouch/jump state and speed overrides;
  version 6 added grenade/objective feedback; current version 7 adds broken
  brush state as described above.
  The client queries map solids but never enables its gameplay tick or collision
  layer. Its history is capped at 25 commands / 250ms; stale updates, new lives,
  teleports, death and disconnect stop or reset prediction. This is initial
  prediction, not adverse-network smoothness clearance or dynamic actor/brush
  collision agreement. World state also includes owner-only inventory/buy eligibility and stable-ID dropped
  guns/backpacks/planted C4, with model-only client replicas and host countdowns.
  Larger snapshots are chunked into bounded packets and applied atomically
  after reassembly; loss retains the last complete state. Brush state and
  full-match validation remain open. This is not yet a release-cleared match.
- Online pause/options menus now isolate local input without pausing the host
  or client presentation. Host round time, remote movement/firing and snapshots
  keep advancing. Offline gameplay inherits PAUSABLE; the HUD remains ALWAYS
  and forwards paused keys to the existing menu handler. Host/join transitions
  with an open menu release the offline world pause, and Quit still closes the
  session. Modal menus also suppress the local raw objective-use input path.
- Buying now shares per-human host checks and grants with the local player.
  The existing B menu sends an item identifier only; authoritative snapshots
  update wallet, equipment and buy eligibility. Host rules own prices, team,
  life, zone, deadline, carry limits and the debit. Replay protection prevents
  duplicate charges. Buying syncs live ammo before a grant so equipment cannot
  restore stale magazine/reserve values. Some other HUD event routing still
  assumes the single `"player"` row. Remote combat/objectives, world use, inventory and initial
  team/class admission now have host-owned paths described below. `_all_bots()`
  returns bot arrays; human-aware consumers use the separate human roster.
- The held-input contract still omits client simulation tick.
  Team/class, buying, weapon selection, secondary and drop requests use the separate reliable
  action contract. Existing slot/grenade-cycle/lastinv inputs read replicated
  inventory; slot 5 requests an owned C4. The host uses normal switch/deploy/ammo
  rules and rejects requests for unowned weapons or unavailable pawns.
  Secondary/drop commands specify the expected held weapon and respect host
  cooldown/life/control checks. Mode snapshots update the client HUD, scope FOV
  and existing silencer animation. Scope-dependent movement/spread now derives
  from weapon mode, not the player's display FOV. World drops and planted C4 now
  have client models without client physics or pickup authority.
  Version-1 input/action validation now rejects
  malformed fields, non-finite values and stale counters. Registered transport
  senders have a bounded accepted-command token bucket and held-input expiry.
  Session/departure cleanup and reconnect counter resets are implemented.
- New `network_packet_test.gd` and two-process `network_transport_test.gd` checks
  pass under `game:test:network`. They exercise real loopback RPC delivery,
  malformed input/snapshots, expiry without disconnect, and reconnection.
  The additional `--human-simulation` pair drives the production human pawn
  through floor collision/friction and pistol firing, verifies server damage,
  ammunition/effects, freeze/look and expiry, and checks client-observed
  position snapshots. It stages one target, not a complete Game/round roster.
  This proves the human input/simulation seam, not a shared playable match.
  The September 9 menu workflow supersedes the original command-line-only gap.
- The two-process `--game-roster` fixture loads the actual Game on both maps.
  It covers a connection established before Game load, duplicate/unknown/local
  peer rejection, pending spectator rows, ignored movement/fire, round reset,
  rematch, reconnect, host restart, fresh IDs, safe slot reuse and scene teardown
  while still connected. Staged sound/C4/hostage ownership checks exercise real
  departure cleanup, not normal team admission or objective gameplay. The client
  is a transport fixture, not a fully presented multiplayer Game.
- Host-Game C4 consumers now recognize every `PlayerController`, resolve remote
  objective identity through the roster, sample the remote's own validated held
  command, and use its weapon clock, hull, grounded state and camera ray. C4
  inventory and objective locks are per human; phase changes preserve pending
  inactivity and clear completed remote objective locks. The staged
  `network_human_objective_test.gd` passes planting/release/retry, full-duration
  planting and defusing, expiry/use grace, remote objective scoring, freeze,
  airborne/aim rejection and host input/camera isolation. It directly stages
  team/alive state: this is not team admission, real-client objective presentation,
  reliable weapon selection or normal C4 world pickup/drop coverage.
- Host world interaction now tracks Use edges per human, includes remote hulls
  in brush/breakable contacts, and assigns remote brush activators monotonically
  from a separate host-local 64-bit namespace. Departure clears that human's
  edge/contact/position state; delayed IO cannot inherit a reconnect's identity.
  Doors, source-use nodes and C4 share candidate selection, including the selected
  object across the Game tick, so a moving target cannot cause two activations
  from one press. World use is available in live and planted-bomb phases.
  `network_human_world_use_test.gd` stages two humans and verifies independent
  inputs/expiry, actual Assault hostage use/reward, real button/C4 competition,
  door contacts, reconnect attribution and host camera isolation.
- That test exposed a real remote-to-host camera takeover through Assault button
  51's cam4 output. Remote camera state/control locks now belong to the activating
  human and expire/reset/clean up independently. The transform and deadline are
  host-authoritative state only: owner snapshot serialization and client camera
  presentation remain unfinished. Local camera origin/aim/return coverage is now
  mandatory in the map gate. These fixtures still stage admission, not shared play.
- Gun drops now retain the durable dropper ID. Touch pickup considers all living
  humans in stable order, fills only empty slots, preserves live clip/reserve,
  suppresses only the overlapping manual dropper, and cannot duplicate a gun on
  simultaneous touches. Remote drop signals and combatant elimination signals
  bind to actor-specific Game handlers. Death updates the correct round row,
  drops the carried/best gun, releases C4, preserves headshot/weapon kill notices,
  and does not schedule the host spectator camera. Duplicate death handling is
  inert. Manual C4 drop/pickup routing is also human-specific. C4 cleanup after
  death now preserves the remote corpse pose when weapon presentation changes.
  `network_human_inventory_test.gd` covers these staged host paths and reconnect
  pickup identity; it does not send reliable drop actions over the wire or prove
  weaponbox flight/landing, normal remote admission, or shared client rendering.

- Initial host team/class admission now reserves map spawn slots, replaces one
  server-selected same-side bot, preserves surviving bots' positions and brush
  activator IDs, and validates projected capacity/balance before removal. Class
  completion owns appearance and spawning; duplicate requests cannot heal or
  rearm, and late entrants wait for the next round. Human slots survive round
  resets, halftime and rematch, with survivor loadout preservation, fresh death
  equipment and pending class choices retained. The host body participates in
  human bullet hit masks while admitted peers exist. Radar and death spectating
  include remote teammates. `network_human_admission_test.gd` exercises the real
  host methods on Dust2 and Assault and is mandatory in the network gate.
  Peer registration is staged in this fixture; the two-process fixture below
  separately verifies reliable team/class RPCs. The newer `--world` pair below
  checks the actual client menu and actor view. Remote team changes,
  spectator selection, bot backfill and last-alive replacement edge coverage
  remain open.

- `NetworkSession` now sends strict versioned team/class actions and owner-only
  results on reliable ENet channel 2. The host derives identity from the RPC
  sender, checks registered ownership and monotonic request counters, and limits
  gameplay dispatch to an eight-action burst/refill rate of eight per second per
  peer independently of movement input. Invalid packets/replays do not dispatch;
  valid gameplay/rate-limit rejections receive explicit results. Client pending
  requests are bounded to sixteen, correlated by action/sequence/selection, and
  expire after five seconds with an unknown-outcome timeout (not host rollback).
  Disconnect clears counters/results/pending state; Game teardown unbinds the
  handler. No account authentication, packet pre-decode/flood protection, session
  version handshake or adverse-network clearance is established by these checks.
  The unit fixture and real `--game-admission` host/client pairs are mandatory
  in the network gate. Both map pairs passed first selection, actual host pawn
  spawn, duplicate/wrong-order rejection, spoofed-owner/malformed packet rejection,
  normal input coexistence, departure cleanup and reconnect with fresh actor ID.
  This admission client is a transport fixture, not a rendering test.
- The mandatory `--world` pairs load actual Game scenes on both maps. They check
  existing menu admission, host-owned movement/firing, HUD health/ammunition,
  actor death/revival, round scores/reset and disconnect without independent
  client round/combat simulation. A muted native Dust2 client capture also shows
  remote actor models. Stationary opponents and loopback transport make these
  functional checks, not full-match, adverse-network or smoothness proof. Both
  peers must load the same map; map transition and in-place role switching remain
  unfinished. The codec unit also covers every registry weapon's ammo semantics.
  Expanded world pairs also check slot selection, grenade cycling, lastinv,
  inventory/ammo/equipment after staged host grants and unowned-rifle rejection;
  Dust2 includes C4 pickup/selection. These grants do not test buying, nor does
  selecting C4 establish client objective-entity presentation. Host admission
  checks cover freeze selection, same-weapon no-op, reload cancellation and
  dead/unowned/unknown request rejection. Weapon actions use existing replay and
  rate limits, not a separate networking subsystem.

## Implementation order and proof required

1. Finish the versioned wire contract: identity from the established transport
   sender (not account authentication); input sequence and simulation tick; movement/look/buttons;
   reliable discrete actions; authoritative entity snapshots and event IDs.
   Reject wrong types, non-finite values, unknown actions, stale sequences and
   unowned actors. Expire held input after silence and clear session state on
   disconnect. Unit tests must include malformed/replayed packets, reconnects,
   burst limits and packet loss—not just valid input clamping.
   The current packet/loopback tests cover shapes, counters, accepted-command
   rate limits, silent-input expiry, reliable initial team/class actions and
   reconnects. Other discrete actions, full-world snapshots, pre-decode size/flood
   bounds and adverse-network tests remain open.
2. Add stable human actor IDs and roster ownership. Local UI should resolve the
   owned actor instead of assuming every command targets `"player"`. Server
   joins, team/class selection, capacity/balance rules, appearance, death/drop,
   observer state, halftime and departure must all reach the same round rules.
   A remote human must use human movement and weapon simulation, not silently
   substitute the bot's different movement/aiming controller.
   The new adapter and two-process human fixture establish that simulation
   seam. Explicit binding prevents another peer, a departed/reused transport ID
   or local mouse events from steering it. Local/remote pawn initialization and
   per-slot audio/world presentation now coexist in tests. Pending Game binding,
   unique slot allocation, durable host IDs, replicated actor IDs/epochs,
   local-host collision participation and initial combat team/class admission
   are implemented. Remote reassignment and remaining participant lifecycle
   edges still need coverage. Remote world muzzle effects
   still use the existing approximate world-shot anchor. The adapter consumes only version-one held buttons;
   it does not solve reliable discrete actions or client prediction.
3. Make the host authoritative for actors, health/ammo, economy, damage,
   objectives, doors, grenades and round/match transitions. A client must not
   independently decide hits, rewards, rescue or round wins. Prove this with
   separate local processes: one peer moves/fires, the other observes the same
   actor, damage, ammunition and round event exactly once.
4. Add owner prediction and acknowledgement/reconciliation, remote snapshot
   interpolation and deduplicated audiovisual events. Test latency, loss,
   jitter, out-of-order packets, joins in progress and reconnects. Any hit
   rewind must be bounded by server history and must not trust client hits.
5. Connect the actual host/join UI, connection failure/retry, disconnect and
   return-to-offline flows. Verify Dust2 and both starting sides through
   a complete match, halftime and rematch with multiple human-owned peers.
6. Re-run performance/soak coverage on multiplayer workloads. A successful
   offline 5v5 benchmark cannot establish remote prediction smoothness, input
   fairness, network abuse bounds or shared-match correctness.

The full production-readiness checklist remains in `production-readiness.md`.
Transport availability alone is not a completed multiplayer feature.

## Actual Game integration audit (September 8)

Remote pawn construction alone is not sufficient for admission to this Game.
The following existing consumers must move together when binding the roster:

- `_round_id_for_actor`, `_actor_for_round_id` and `_round_actor_positions` now
  include the pending remote roster's durable host IDs. `_live_combatants_stable`
  and `_brush_activator_id` now include live remote humans, with distinct stable
  remote activators. Bot activators still depend on sorted roster indices and
  must become stable before bot replacement can mutate that roster. Replicated
  IDs need a world/session epoch before old events can cross scene reloads.
- `_refresh_roster_spawns`, `_reset_combatants_for_round`
  and `_apply_halftime_side_switch` must include every admitted human while
  preserving team capacity, late-join waiting and survivor loadout rules.
  `_apply_round_phase` now handles remote control/look/objective locks without
  activating pending humans; admission/reset integration remains necessary.
- `_round_tick_command` now distinguishes human bodies by type, not host identity.
  Human C4 ownership, plant/defuse input, eye/hull/grounding and objective locks
  are generalized and covered by the staged objective fixture above. Remote
  plant world animations and replicated objective UI/events still remain open.
- `_process_player_world_use` now processes per-human commands/edges and camera
  rays. `_process_weapon_pickups` now uses durable dropper IDs and stable human
  ordering; pending/dead humans cannot claim items. Weaponbox collision/flight,
  shared ammo policy and world-item replication remain separate fidelity work.
- Human death/drop and C4 ownership/drop routing now have actor-specific handlers.
  Remote reliable equipping/drop requests, buying, full scoreboard replication
  and remote spectator selection/presentation remain open.
  Hostage use/damage/rescue banners still target the local HUD; per-owner/team
  presentation events must replace those broadcasts during client integration.
- Departure is not a synthetic kill. Round state now provides `disconnect_player`
  for objective/roster cleanup without death/kill rewards. The new
  `round_disconnect_test.gd` first exposes, then verifies the correction to,
  missing spawnable-team guards in `_check_elimination`. Source reference: ReGameDLL's
  [ClientDisconnected and TeamExterminationCheck](https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/multiplay_gamerules.cpp).
  Pending roster removal now unbinds input, disables collision/physics, consumes
  round events before freeing the actor, stops its voice channels, retargets an
  existing spectator target and clears knowledge/hostage references. Admitted
  humans now have per-actor use/touch/death/drop handling but still need full
  participant lifecycle, respawn/halftime inventory and replicated state cleanup.
  Defuser item dropping and the full empty-server/game-commencing lifecycle are
  not established by the round-removal test alone.
