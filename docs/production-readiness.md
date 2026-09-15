# Production readiness

Status: not release-ready. This is an evidence checklist, not a feature-complete claim.

September 14 ammo-purchase audio (source only): every successful local or
host-authoritative remote ammo-box purchase now emits the original
`items/9mmclip1.wav` cue once on `CHAN_ITEM`, from the buyer's spatial audio
identity. Primary/secondary aliases and direct caliber purchases share the same
path. Rejected, full-ammo and replayed purchases remain silent; clients present
the host event instead of predicting a duplicate. This follows ReGameDLL CS
`BuyGunAmmo`, which emits the cue only after `GiveAmmo` succeeds. Muted catalog,
buy integration, remote buy, combat-event, live-audio and network-feedback
fixtures passed. No archive was rebuilt.

September 13 defuse progress HUD (source only): the CT actively defusing now sees
a square-edged 200x12 classic progress track near the lower middle of the view.
Its green fill uses authoritative elapsed/duration ticks, including the 5-second
kit and 10-second no-kit timings. Only the owning defuser sees it; abort, death,
completion, disconnect and mismatched-map cleanup clear it, while Pause/buy menus
temporarily hide it. Multiplayer clients derive it from validated owner feedback
instead of predicting objective authority. Muted HUD, layout, world-state, human
objective and full C4 objective regressions passed. A muted native GPU capture was
visually inspected at `/tmp/protocol47-defuse-kit-hud.png`. No ZIP/video rebuilt.

September 13 bot shooting tune (source only): offline bots now use a medium 0.58
combat skill instead of the previous hard-coded 0.88. Their acquisition delay is
about 240 ms after a scheduled vision scan, aim turns at roughly 210 degrees per
second rather than snapping, movement lead is partial, and seeded angular error
persists and drifts instead of rerolling a nearly perfect offset every 10 ms.
Tracked enemies must remain inside the vision cone, removing the prior LOS-only
360-degree lock. Weapon cadence, recoil/spread, walls, smoke, flash and deterministic
100 Hz replay remain in the existing paths. Tactics, perception, combat, procedural
smoke, doors, Dust2 objectives, round integration, mobility and hostage determinism
fixtures passed muted. The 30/240 fps mobility signatures are exactly equal. This
is a playability tune, not a claim of original CS bot-difficulty parity. No ZIP or
social video rebuilt.

September 13 buy-menu completion/helmet HUD (source only): successful local mouse
and numeric purchases close the buy menu and restore gameplay input. A purchased
primary replaces a held pistol; newly purchased firearms also equip from utility
or knife, while ammo/equipment and a pistol bought under a held primary do not
switch weapons. Rejections leave the menu open. Remote clients wait for accepted
host replies to close the matching menu session and use owner snapshots for the
equipped weapon; late replies cannot close a reopened menu or dismiss Pause.
All health/armor HUD refresh paths now include authoritative helmet ownership,
selecting the existing combined `suithelmet_full` sprite after buying a helmet.
Purchase, damage, fresh/surviving spawn and owner snapshot regressions passed.
Six muted headless fixtures, the real Dust2 host/client world transport and a
muted native equipment HUD capture passed; the combined armor/helmet icon was
visually inspected in `/tmp/protocol47-defuse-kit-hud.png`. No ZIP/video rebuilt.

September 13 equipment HUD/defaults (source only): the original `defuser` mask
from `640hud7.spr` is now part of the reproducible HUD extraction (36 sprites).
A green left-side kit indicator follows living CT ownership, stacks above the
buy-zone cart, and hides for menus/spectating, death, kit loss and disconnect.
Local purchases refresh it immediately; clients use authoritative owner inventory
snapshots, including late joins. Fresh USP/M4A1 human grants and the starting CT
USP now default to silenced as requested; already-owned/surviving weapons retain
their selected mode. This default is a project behavior choice, not a new claim
of original-engine parity. First-shot audio, model state and remote inventory
are covered by muted regressions. Native capture inspected:
`/tmp/protocol47-defuse-kit-hud.png`. The new kit fixture is in `game:test:hud`;
sprite, layout, menu, knife/silencer and network inventory checks passed.
No download ZIP or social video rebuilt.

September 13 Dust2 shadow readability (source only): a bounded 0.14 encoded-light
lift now fades out between luminance 0.18 and 0.65 in the baked-world shader and
player/viewmodel tints. Bright surfaces and texlights are unchanged; other maps
default to zero adjustment. This is an artistic readability adjustment, not an
original-engine lighting parity claim, and adds no dynamic lights. Muted native
before/after captures cover CT spawn, upper/lower tunnels and a sunlit wall;
pixel checks confirm shadow lift and unchanged bright pixels. Captures are at
`/tmp/protocol47-{ct-spawn,upper-tunnel,lower-tunnel,sunlight}-{before,after}.png`.
The headless regression is `npm run game:test:lighting`; BSP material, character,
viewmodel and target-presentation regressions also passed. No ZIP rebuilt.

September 13 Dust2 combat follow-up (source only): dropped/planted C4 radar
contacts now respect living-Terrorist visibility and snapshot-based cleanup.
Per-weapon accuracy/recoil, scoped spread, burst behavior and posture-aware
hit-group classification were corrected. Muted regression tests, a native radar
capture and a real Dust2 host/client transport passed. Clean stationary GPU
firefights measured 15.6 ms repeated-fire p95, but earlier live samples contained
spikes up to 89.3 ms. Neither full smoothness nor original bone-attached hitboxes
is complete. See [the combat audit](dust2-combat-audit.md) for exact changes,
reference variants, measurements and remaining limitations. No ZIP rebuilt.

September 13 spraypaint (source only): the advertised T key now places the bundled
transparent `@rushing_andrei` graffiti on nearby flat static geometry, with the
existing `player/sprayer.wav` sound. Placement uses the authoritative eye ray,
1.28-unit reach, supported-footprint probes, and a 10-second per-human cooldown.
Dead/spectating players, menus, moving/breakable brush models, sky and unsupported
edges are excluded. The 32-entry history clears each round. Clients submit only
an empty spray action, never positions, image paths or another actor's identity.
Validated optional spray records travel with full world snapshots, supporting
late joins, deduplication, eviction and round cleanup without replaying old audio.
Updated host and client source are required; no old ZIP rebuilt.

Eight muted headless fixtures passed: spray placement/integration, world state,
action validation, grenade/feedback, audio catalog, classic UI, combat effects and
world chunks. The spray fixture covers original sound, cooldown/echo/menu/death
gates, remote ownership/replay, actual alpha, bounded retention and removal.
Real Dust2 host/client transport passed with the T action and late-join spray
state. Native Compatibility capture passed and was visually inspected at
`/tmp/protocol47-dust2-spray.png`; logs: `/tmp/protocol47-spray-*.log`.
The image was created with the built-in image generator and preserved in
`game/assets/sprays/rushing_andrei.png`; its exact prompt is in the adjacent
README. GPU import is mipmapped and limited to 1024 pixels. There is one bundled
spray, not an arbitrary-image upload system. The prior Twitter video is unchanged.

September 13 player-name wiring (source only): Options → Multiplayer → Name now
loads the saved display name. Apply/OK normalizes, persists and updates the live
actor; Cancel discards only uncommitted edits. Names are limited to 32 characters,
trimmed, stripped of control/direction-override characters, and default to Player
when empty. Unicode and clan tags are supported; kill notices escape name markup.
Local spawn, team/spectator selection, scoreboard, radio and kill-name lookup
use the configured name. Scoreboard row identities and highlights remain keyed
to actor IDs, including duplicate display names.

Clients send their own saved name over a bounded, rate-limited reliable RPC.
The host binds it to the registered sender, caches it for Game/roster creation,
and publishes it through existing actor snapshots. Disconnect clears the cache;
reconnect sends the current saved name again. No account, authentication or
unique-name system was added. Both host and client should run this updated source;
the old ZIP has not been rebuilt.

Verified using isolated settings: cross-process persistence, local Apply/OK/Cancel,
live scoreboard/highlight, markup safety, malformed/spoofed/rate-limited names,
and real muted Dust2 host/client transports covering live rename, world snapshot
propagation, a peer joining before Game exists and reconnect. Seven additional
muted headless fixtures passed: classic UI, HUD layout, action validation, packet
validation, network pause, network menu and network grenade/feedback. Logs:
`/tmp/protocol47-name-*.log`. The installed player's settings were not modified.

September 13 player gait fix (source only): the MDL exporter now follows Valve's
`StudioSetupBones` gait branch switches, resuming gait at the leg branches after
the spine rather than treating the spine's array index as a permanent cutoff.
Both feet retain the authored run/crouchrun poses. Body exports include a
per-vertex bone-ownership mask; the runtime uses it instead of splitting thighs
at a fixed height. Legacy assets retain the old fallback. All eight base skins,
76 weapon-family body variants and 29 attached weapons were regenerated; all
113 models / 972 animation tapes passed metadata/byte-length checks.
Movement physics, gait speed scaling and network protocol were not changed.
Reference: [Valve StudioModelRenderer.cpp](https://github.com/ValveSoftware/halflife/blob/master/cl_dll/StudioModelRenderer.cpp).

The new rendered-vertex stride regression failed on all eight old skins and
passes with the regenerated assets. Rust checks both feet against every authored
run/crouchrun frame and verifies alternating leading feet across all eight skins.
All 17 Rust library tests and six muted headless fixtures passed: character
animation, pose sampler, grounding, target presentation, bot preparation and
network grenade/feedback. Native Compatibility gait capture and shadow regression
passed (zero optimized/reference shadow pixel mismatches). Inspected gait image:
`game/artifacts/protocol47-character-gait-grid.png`; logs:
`/tmp/protocol47-walk-*.log`. Restart `npm run game:run` for these assets.
The ZIP and previously recorded social video are unchanged.

September 13 money-change HUD feedback (source only): the original bundled
plus/minus, dollar and digit sprites now display above the account balance.
Gains are green and expenses red, held for one second then faded over 1.5 seconds
(classic-style timing, not a verified frame-exact original-client timing claim).
Same-sign changes combine while visible; a change of sign replaces the amount.
Only actual balance differences animate, including capped rewards. Host money
updates no longer wait for the next displayed clock second. Client snapshots use
the existing owner balance, with no new protocol or economy changes. Initial
accounts, match resets and side changes establish a quiet baseline; duplicate
snapshots do not replay the effect. Modal and spectator visibility follow the
existing money HUD.

Seven muted headless fixtures passed: HUD layout, classic UI, round integration,
buy integration, match lifecycle, world state and network grenade/feedback. Checks
include actual kill/round credits, client reward/purchase snapshots, repeat/reset
handling, fades, rapid rewards, account cap and 640/1024/1280 layout bounds.
Native Compatibility feedback capture passed and was inspected at
`/tmp/protocol47-money-reward.png`; logs: `/tmp/protocol47-money-*.log`.
The ZIP and previously recorded social video are unchanged. Restart
`npm run game:run` to use the updated source.

September 13 direct ammo-buy menu fix (source only): primary/secondary ammo
entries now emit `primammo`/`secammo` directly, as in the bundled MainBuyMenu
reference. Mouse clicks and keys 6/7 retain the main menu; no empty ammo detail
page. Existing authoritative caliber, price, reserve and purchase restrictions
remain unchanged. Weapon-row prices use the same font metrics and vertical
alignment as their labels. Removed obsolete ammo-submenu capture states.
Muted classic UI and buy-integration headless fixtures passed; the latter also
passed in native Compatibility rendering. Tests cover T/CT mouse and keyboard
ammo purchases, one pack/charge per action, account refresh, full reserves,
insufficient money, missing weapons and name/price baselines. Inspected native
weapon-menu capture: `/tmp/protocol47-direct-ammo-prices.png`; logs:
`/tmp/protocol47-direct-ammo-*.log`. No ZIP rebuilt; restart `npm run game:run`.

September 13 thrown-grenade visuals (source only): HE, flashbang and smoke
projectiles now use their existing textured world models instead of the dark
sphere placeholder. Host selects the model at launch, after the kind is known;
clients select it from the existing item weapon field. Throw physics, collision,
fuses and the network schema are unchanged. The grenade/feedback fixture checks
all three source meshes/skins, launch state, client replication, repeated
snapshots, removal and detonation visibility. Five muted headless fixtures passed:
network grenade/feedback, live audio, weapon timing, world state and network
weapon actions. The native fixture now waits for asynchronous presentation startup
before testing/teardown, avoiding the premature shutdown resource warning seen
in initial captures. Native Compatibility captures passed with muted audio. Logs:
`/tmp/protocol47-grenade-model-*.log`. Inspected capture:
`/tmp/protocol47-grenade-models.png` (staged stationary projectiles, not a full-match
flight/performance benchmark). No ZIP rebuilt; restart `npm run game:run`.

September 13 death-drop and post-round movement fixes (source only):
`MdlCharacterModel.play_death()` now hides the held weapon without spawning a
decorative ground copy. Game owns the single pickup; clients render only that
replicated item beside the empty-handed corpse. Standalone `force_pose` capture
tosses remain available. Tests cover bot and remote-human deaths, carried ammo,
dead-actor arrival, repeated snapshots, pickup removal and corpse weapon refresh.

Surviving human players may move during PHASE_POST, independently of attack
permission. The existing snapshot motion-enabled bit carries this permission to
client prediction; no schema change. Freeze, intermission, dead and pending
players remain locked. This change permits movement, not post-result combat;
bot post-round decisions remain unchanged. Ten muted headless fixtures passed:
character animation, human inventory, network grenade/feedback, movement
prediction, human objective, weapon-drop motion, round integration, world state,
network actions and human admission. Logs: `/tmp/protocol47-death-post-*.log`.
No new rendered/full-match claim or rebuilt ZIP. Restart `npm run game:run`.

September 13 reference-scoreboard update (source only; older ZIP unchanged):
the user's supplied image now guides the Tab panel, superseding the earlier
compact, darker layout. Near-full-height 4:3 panel, translucent background,
thin amber frame, inline column headings, Terrorists first, colored team rules,
score/death sorting, and separate status / HP / Money / Score / Deaths / Latency
columns. Local-row highlighting remains ID-based. HP, money and Bomb status are
team-only; dead status is public and no longer replaces latency. Host uses live
actor health; clients use existing snapshot data. Client Bomb labels are limited
to known equipped C4 or the owner's inventory (no new carrier field/protocol).
No fabricated avatars/accounts or new networking system. Host refreshes visible
stats at 5 Hz and immediately on Tab; rebuilding preserves scroll position.

Six muted gates passed: classic UI flow, HUD layout, round-game integration,
network grenade/feedback, remote-human objective, and world-state validation.
Tests cover private-stat masking, team totals/order, owner highlighting, live
HP refresh, and 32-player scroll retention/header alignment. Native Compatibility
capture passed at 640x480, 1024x768 and 1280x720, with 17- and 32-player fixtures.
Screenshots inspected in `/tmp/protocol47-scoreboard-reference/`; capture log
`/tmp/protocol47-scoreboard-reference-capture.log`. This is UI/source validation,
not a rebuilt archive or full-match performance clearance. Restart `npm run game:run`.

September 13 defuse/reload audio and local scoreboard highlight (source only):

- Defuse start now emits `weapons/c4_disarm.wav` once on CHAN_ITEM; success
  emits `weapons/c4_disarmed.wav` on CHAN_WEAPON. Normal spatial attenuation,
  existing reliable world-audio replication, no loop or protocol change.
  Holding use does not retrigger; abort never plays success; restarting plays
  a new start cue. Channels/samples checked against ReGameDLL_CS
  `regamedll/dlls/ggrenade.cpp`, `DefuseBombStart` / `DefuseBombEnd`.
- Reload audio now includes all 22 magazine-fed firearms (69 original MDL
  event-5004 markers, rounded to 100 Hz), shared by humans and bots. Both human
  shotguns emit shell insertion cues and M3 emits its finishing pump; the bot
  shotgun's existing simplified reload clock is unchanged. No ammo or reload
  deadlines changed. Switching weapons, interrupting shotgun reload, or firing
  over a late reload-animation tail cancels pending human reload sounds.
- Tab highlights the local player's full row, preserving columns/team colors.
  Offline/host uses the local actor ID; joining clients use snapshot owner ID,
  so duplicate names and death do not move the highlight to another player.

Muted Godot fixtures passed: catalog, live audio (every magazine timeline and
both human shotguns), weapon timing, Glock mouse input, bot combat, event router,
playback adapter, network combat events, remote-human objectives, network
grenade/audio feedback, classic UI flow and HUD layout. Client tests cover exact
defuse/reload samples, duplicate rejection and presentation without ammo mutation;
these are staged integration checks, not a new two-process defuse-match run.
A read-only binary MDL comparison confirmed all 69 magazine markers/samples;
the pinned 808-WAV asset regression also passed. No audible listening test.
Native Compatibility UI test passed with Dummy audio; the clean capture
`/tmp/protocol47-scoreboard-highlight.png` was inspected. Logs include
`/tmp/protocol47-final-audio_live_integration_test.log`,
`/tmp/protocol47-final-network_human_objective_test.log`,
`/tmp/protocol47-final-network_grenade_feedback_test.log`, and
`/tmp/protocol47-scoreboard-highlight-rendered.log`.
Restart `npm run game:run`; both peers need this source for the new audio catalog.
No archive rebuilt, new map, matchmaking, or full-match performance claim.

September 13 buy-menu callback fix (source only; September 10 ZIP unchanged):
the live game log showed `Attempted to free a locked object (calling or emitting)`
when clicking a category or purchasing. Both menu rebuild paths now detach old
controls immediately and queue their deletion until callbacks finish. Deferred
focus resolves the current visible row rather than retaining retired buttons.
No layout, price, inventory, or network protocol change.

The existing mandatory buy-integration fixture now sends viewport mouse motion
and press/release events through all eight category buttons and Back, purchases
a Deagle through the real Game handler (one grant / $650 debit), refreshes account
and affordability, and checks Cancel/reopen and old-node disposal. It reproduced
the original locked-object error before the patch and passed afterward, both
headlessly and in native Compatibility rendering with Dummy audio. Classic UI,
network buying and network menu fixtures also passed muted; all checks rejected
engine/script errors. Post-refresh image `/tmp/protocol47-buy-click-fixed.png`
was inspected. Logs: `/tmp/protocol47-buy-click-before.log`,
`/tmp/protocol47-buy-click-after.log`, `/tmp/protocol47-buy-click-rendered.log`.
Restart `npm run game:run` to use the fix. No archive was rebuilt in this pass.

Latest internal Mac archive: `game/builds/Protocol47-validation-20260910.zip`
(484 MiB as displayed by `ls -lh`, unsigned universal build). Export and the
fresh-settings, muted packaged-startup regression passed; six offline guard
tests passed. Export log `/tmp/protocol47-export-20260910.log` confirms all three
grenade pullpin/throw strips are packed. Packaged startup is not packaged match
or GPU clearance. Older ZIPs are preserved and do not contain this follow-up.
SHA-256: `e5623680a5c2b44e05d415d13c0850bce15652cd14e6f678ccc232c1f558f6ac`.
Restart source with `npm run game:run`; both multiplayer peers must use this
same schema-7 source/build. For silent play: `npm run game:run -- --audio-driver Dummy`.

September 10 lean Dust2 follow-up (supersedes corresponding open items below):

- macOS Ctrl-crouch firing normalizes Godot's translated Control-left event
  using its physical button mask; genuine right-click remains secondary.
  The fixture covers both-button ordering, releasing Ctrl first, menu reset,
  and sustained crouched firing. The rendered pair uses synthetic native-shaped
  input through the real controller, not physical hardware injection.
- Presentation warmup explicitly draws its preparation frames instead of
  waiting indefinitely for automatic drawing in an occluded native window.
  A muted native test with the render loop disabled passed in 10.848 seconds.
  Forced draws are confined to loading, not measured gameplay frames.
- Flash and smoke now use their own shipped detonation samples/channels;
  only HE emits HE explosion/debris. Muted routing assertions are not listening
  tests. The rejected Glock menu-selection cue remains pending user preference.
- The MDL importer previously classified grenade viewmodels as characters and
  exported only idle. It now preserves all four original sequences for HE,
  flash and smoke. Generated assets include pullpin/throw/deploy. Reliable
  host grenade-action events animate owner/remote presentation without local
  ammunition, projectile or damage simulation; stale throws cannot replace
  a newly selected gun. This is not an exact animation-timing parity claim.
- World schema **7** carries a validated full list of broken brush model IDs.
  Clients apply only locally authored breakables to visibility/collision before
  owner movement replay; reset snapshots restore them without running local
  damage rules. Dust2's ten breakable brushes are covered; moving doors and
  predicted player-to-player collision remain outside this change.

Nineteen focused muted Godot fixtures passed after the fixes: crouch input,
world state/chunks, combat events, weapon actions, prediction, Quit, gun toss,
audio catalog/live routing, human objectives, C4 explosion, round disconnect
(72 cases), round integration, Glock input, network menu/pause, grenade feedback
and viewmodel animation. The new Rust regression passes all three original
grenade models. All 72 Node runner/auditor/triangle diagnostic tests passed.
The initial grenade animation assertions failed on the idle-only exports and
passed after the importer correction; those failed attempts are not clearance.
Final muted Compatibility Dust2 pair `YcmLC4` passed (peak chunk/snapshot
1,016/1,391 bytes), including crouched owner fire, distinct grenade detonation
audio and client crate destruction/reset. Both processes exited cleanly.
The pair's grenade flight is staged; original pin/throw frames and presentation
are verified by the focused fixtures, not actual mouse-driven throwing in that
pair. Earlier headless `Z8i93W` passed before the animation export correction.

Short native Compatibility stationary 10-actor GPU report:
`/tmp/protocol47-lean-firefight.json`. All stages had zero frames over 33ms;
firefight max 20.462ms, repeat 27.395ms, cold switch/fire 28.410ms, smoke 17.048ms.
Repeat/cold p95 exceeded 16.67ms. This has no moving AI and is not a full-match
smoothness pass or proof that every reported hitch is fixed.

Moving-combat T-side check `/tmp/protocol47-lean-live-T.json` passed its coverage
checks: 6,000 physics ticks, 11,903/11,903 rendered frames, local firing/death,
dropped/picked-up C4 and planting. p95 9.300ms, p99 11.322ms, max 35.586ms;
the sole frame over 33ms was the first measured frame, retained in the report.
No pauses or missing authoritative ticks. This short fixture grants an AK and
skips the initial freeze, uses nine production bots plus automated local intent,
and did not finish a round. It is not a full or two-player match benchmark.
The CT-side 12,000-tick run `/tmp/protocol47-lean-live-CT.json` also passed its
coverage checks: 23,695 sampled / 23,694 rendered frames, two completed rounds,
local firing/death/respawn and planting. p95 9.422ms, p99 11.165ms, max 31.582ms
(round reset), no frames over 33ms, no pauses or missing authoritative ticks.
Both rounds ended by elimination; neither explosion nor defuse was exercised.
It uses the same short-fixture equipment/freeze allowances as the T run, not
normal full-match start conditions. These two samples do not clear a full match.

Primary implementation references: [Godot 4.7.1 native Control-left translation](https://github.com/godotengine/godot/blob/4.7.1-stable/platform/macos/godot_content_view.mm#L402-L414),
[physical macOS mouse mask](https://github.com/godotengine/godot/blob/4.7.1-stable/platform/macos/display_server_macos.mm),
and [ReGameDLL grenade detonation routing](https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/ggrenade.cpp)
(community reimplementation, not Valve's original source).

Still open: authored reload stages, the Glock cue decision, player collision
prediction, full two-player T/CT matches including explosion/defuse and genuine
late joining, loss/latency soak, full-match GPU clearance, and public distribution
rights/signing/notarization. Direct host/join and Dust2 remain the only target;
do not add team reassignment/backfill, maps, accounts or matchmaking to close
this list. Internal packaging is not public-release clearance.

September 10 weapon-drop motion fix (working tree): manual/death gun drops no
longer teleport to a floor-snapped position. The original world model now starts
above the floor, travels forward and falls under gravity. Host-side point sweeps
stop at map walls and settle on floor support; a launch-path check prevents the
forward spawn offset from placing it through a nearby wall. Existing snapshots
carry the motion to visual-only client replicas. The next weapon's existing draw
animation, inventory/ammo transfer and pickup ownership rules are unchanged;
this adds world toss motion, not a newly authored hand-release animation or an
exact original-engine physics parity claim.

Six muted Godot fixtures passed: drop motion, drop/pickup, remote inventory,
reliable weapon actions, world state and round integration. The new mandatory
weapon-gate fixture checks flight, landing and a fast thin-wall collision.
All 37 test-runner Node checks passed. The expanded headless Dust2 pair passed
(`ftwrP4`, peak chunk/snapshot bytes 1,016/1,367), including movement across
successive host snapshots with a stable, non-physical client weapon replica.
The first rendered attempt (`yTZYKJ`) reached and captured gun flight but failed
the pre-existing immediate reload assertion. The fixture now waits for both
the host reloading flag and the requested viewmodel animation, rather than
assuming the reliable event and owner snapshot arrive in the same frame.
That attempt is not counted as an overall pass.
Its gun-in-flight capture was inspected. Rerun `vm7Fun` stalled in native
presentation warmup; the host timed out waiting for admission, then the client
exited on its own fixture deadline. Neither rendered attempt
is full-suite clearance, and no performance claim is made.
Restart `npm run game:run` to load this source; archived ZIPs remain unchanged.

September 9 grenade/objective follow-up (working tree, after all archives):
world schema 6 adds stable-ID grenade flight, persistent smoke with host-owned
age, and owner-only flash duration and planting/defusing progress. The client
reconstructs smoke at its current age without replaying physics or fuse ticks,
uses the existing HUD/C4 planting animations, and displays bomb/round results.
Host and client smoke clear on round reset; flash expires locally from the last
host duration even if snapshots stop. Existing host grenade/C4/round audio and
HE/flash/C4 explosion effects use the bounded presentation stream. Grenades from
the same thrower have distinct sound identities. Reload presses now use the
existing reliable action channel, with host cooldown, ownership and replay checks.

Sixteen focused Godot fixtures passed with Dummy audio: grenade/feedback,
weapon actions, combat events, world state/chunks, actions, human objectives,
prediction, effects, C4 explosion, Glock mouse input, live audio, menu, pause,
human controller and round integration. All 70 Node runner/auditor tests passed.
The new grenade/feedback fixture is mandatory in `game:test:network` and covers
malformed feedback/events, visual-only aged smoke, repeated snapshots, expiry,
host/client reset cleanup, defuse HUD and flash expiry without new snapshots.
The actual Dust2 pair additionally checks all three flying grenade types, HE
motion, HE/flash effects, host flash duration, smoke reconstruction, planting
progress/banner, bomb beeps and three independently routed detonation sounds.
Its final headless pass is `5cyH3e` (peak chunk/snapshot bytes 1,016/1,366).
The final muted Compatibility rendered pair `NhQR9B` passed (1,016/1,376)
after the separate-camera correction. Its smoke and planted-C4 captures were
inspected: the cloud is visible at its replicated position and the C4 model,
planted banner and defend prompt are present. The camera is test-only and does
not establish first-person visual parity. Both processes exited cleanly.

Test limits: grenade origins are staged; close flash/smoke bodies are frozen
but retain the normal fuse. Smoke reconstruction removes/rebuilds a replica
from a live snapshot, not a third joining process. Defuse is covered through
the real host objective fixture and client presentation fixture, not a second
full two-process CT match. C4 blast uses existing host integration plus the
presentation codec; the loopback pair plants but does not wait for detonation.
These are functional checks, not listening tests, full-match coverage or new
GPU performance clearance. Generic HE audio for flash/smoke, missing authored
weapon reload stages, grenade throw-animation parity, dynamic brushes,
adverse-network checks, smoothness and shipping remain open. The rejected Glock
mode-switch cue is unchanged. Both peers must restart on this source; existing
ZIPs do not include it.

Failed/limited attempts remain recorded: `v7KjqG` lost a one-frame unreliable
reload input, leading to the reliable-action change. `DX8xIC` cleared a fixture
handshake before the host observed it; the fixture now holds acknowledgement
until the next stage appears. Initial native passes `kDNgeZ`, `82HPk4` and
`j1cRA3` are valid assertion runs, but their smoke images are not visual evidence:
one was flash-white and later captures had aim overwritten by gameplay. Capture
now waits for flash expiry and uses a separate camera. `pxRjeY` was a parse-failed
capture-fixture launch (untyped ray result), corrected before rerun.

September 9 multiplayer combat-presentation follow-up (working tree, after the
archives below): host-only reliable packets now carry gunshot and reload
actions, owner camera punch, exact catalog audio sample choices, world/blood
impacts and headshot-aware kill notices. Human and bot paths share the existing
models/effects/router; clients do not fire bullets, advance weapon clocks,
debit ammunition or apply damage when presenting these events. Audio uses
separate per-actor channels and the active client camera as listener. Death,
new life, departure, world change and disconnect clean up relevant voices.

The contract is versioned and bounded (4 KiB per validated event, at most 128
pending presentation events), with host epoch/sequence deduplication, snapshot
ordering and actor-life/round guards. It permits only known catalog/sample
combinations, not arbitrary paths. Transient effects expire after one second;
kill notices have a separate five-second useful lifetime and cannot cross a
round. This is not pre-decode flood protection or an adverse-network soak.
It uses the existing reliable ENet channel; both peers must run the same source.

The mandatory event fixture covers malformed fields/vectors/sample paths,
duplicates, ordering, bounded queues, reconnect, old epochs/lives/rounds and
delayed kill notices. Fifteen focused Godot fixtures passed with Dummy audio,
covering this contract, snapshots/chunks, prediction, ownership/weapon actions,
Glock input/timing, audio and model/effect regressions. All 63 Node runner tests
passed. The expanded actual Dust2 world fixture checks one owner shot, owner
reload/cancel, one remote host shot/reload, exact single-shot/reload audio,
camera punch without local weapon simulation, impacts/blood and five headshot
kill notices, then retains its buying/drop/C4/round/disconnect checks.
The final headless pair passed (`vq5TTM`, peak chunk/snapshot bytes 1,016/1,296),
including a delayed-notice case. The final Compatibility rendered pair passed
(`hnCnsE`, 1,016/1,301); its client capture was inspected and shows the replicated
headshot kill feed. Both used Dummy audio and exited cleanly. These are functional
checks, not listening tests or new GPU timing/full-match performance clearance.

Failed attempts are retained: two initial reload waits (`ebkdPT`, `v0oCGi`)
used a staged rifle with zero reserve; a client reload attempt (`z5FigA`) was
issued inside the shot cooldown. The fixture now grants explicit reserve and
waits the existing cooldown. A native assertion (`T9fwQc`) read rendered
animation state inside the action callback before the model's next process
step; the fixture now checks the requested action immediately and waits for
rendered state. Two short parse-failed launches (`Sol17b`, `1a2zZW`) exposed a
missing continuation in that test predicate and were corrected. Headless
`JybOsp`/`fWvTrV` reached post-round state without presented kill notices under
the old one-second expiry; diagnostics and a deterministic two-second-delay
fixture led to the separate notice lifetime. These failures are not passes.

This is the initial combat-feedback pass, not complete multiplayer or release
clearance. The newer entry above records grenade/objective work. Dynamic brush
state, adverse-network/full-match checks, smoothness and packaging remain open. Replication
only forwards existing host reload sound schedules (explicit player stages are
currently AK/Deagle); missing weapon-specific sound authoring is not solved.
The user also rejected the selected Glock mode-switch menu cue; its replacement
is unresolved and unchanged here. Relaunching `npm run game:run` loads this
work; neither existing ZIP includes it.

Working-tree Glock audio follow-up (September 9, after the input fix): the
semi-auto catalog randomly selected the single-shot or three-shot recording,
and burst fire restarted the entire burst recording for each bullet. The
single-shot event now selects only `glock18-2.wav`; a full burst plays
`glock18-1.wav` once. This mapping matches the
[CS16Client Glock event implementation](https://raw.githubusercontent.com/Velaron/cs16-client/main/cl_dll/events/event_glock18.cpp).
Bursts with only one or two rounds left use one single-shot event per actual
bullet. Successful burst-mode changes now play a quiet, local-only existing
selection click (intentional usability feedback, not an original-game parity
claim). A connected owner hears it when the host-confirmed mode changes;
unchanged snapshots, admission and remote pawns on the host do not cue it.
The client now advances the presentation audio clock so these voices expire.
The extended mouse fixture reproduced the old audio failures before the fix.
Seven focused Godot tests passed with Dummy audio: Glock mouse input, catalog,
router, playback adapter, live audio integration, weapon timing and remote
weapon actions. The headless Dust2 world pair passed (`jseraV`, peak
chunk/snapshot bytes 1,016/1,304), including owner cue counts and expiry.
All 808 source and 808 game WAV assets retain their pinned bundle hash.
This verifies event routing and lifecycle, not a listening test or complete
multiplayer combat audio replication. Restart `npm run game:run` to load it;
neither existing archive includes this follow-up.

Working-tree Glock input fix (September 9, after the archives below): reproduced
a quick right-click → left-click failing to fire because mode switching wrote
the primary attack deadline. The weapon clock now separates the secondary
deadline; burst toggles do not block primary fire, and a successful secondary
action has priority for simultaneous buttons. This follows the
[Glock secondary-attack implementation](https://raw.githubusercontent.com/rehlds/ReGameDLL_CS/master/regamedll/dlls/wpn_shared/wpn_glock18.cpp).
Glock semi-auto now consumes a held press only when it fires (or dry-fires),
so a press started during cooldown can fire once when ready. Burst mode repeats
at its existing cycle while held, and release only finishes the active burst.
A press/release between ticks now produces a one-tick held-fire pulse so it
is not discarded before multiplayer serialization; this does not guarantee
delivery over packet loss. A dedicated mouse-input fixture reproduced the
old failures and now passes; timer boundary and remote-action tests cover
separate cooldowns. The final headless Dust2 world pair passed (`NRz741`, peak
chunk/snapshot bytes 1,016/1,298), and all 62 Node runner/auditor tests passed.
The user runs `npm run game:run`, which loads this working tree after relaunch.
Neither existing ZIP contains this follow-up; no new export was needed for
that source-based workflow. No new GPU or OS-mouse-event validation is claimed.

Latest local validation archive:
`game/builds/Protocol47-validation-20260909-prediction.zip`
(505,872,234 bytes; SHA-256
`b03265e0d7622c308ad0caefacd77bec076a3cd69a8c722f78b010b53f9e8de5`).
This includes owner movement prediction and world schema 5. Export completed
cleanly in 38.336 seconds; the fresh-profile, Dummy-audio packaged main-scene
startup check passed in 22.419 seconds. The six export-guard unit tests passed.
This remains an unsigned universal 0.2.0 validation build, not a release candidate
or clearance of the open gameplay, native startup, GPU, Intel and distribution gates.

Previous local validation archive: `game/builds/Protocol47-validation-20260909.zip`
(505,866,249 bytes; SHA-256
`c4a7bd4efca2b9171bb1fd29662c67d5aa5431bbcc6645920e2b42b24717d677`).
The export completed cleanly in 40.580 seconds. Its isolated, silent packaged
main-scene startup check passed in 22.492 seconds, after the six export-guard
unit checks passed. This is an unsigned 0.2.0 universal validation build, not
public distribution approval, Intel runtime clearance or a completed gameplay
and performance release gate. Prior archives were preserved.

Previous archive's exported-app Quit verification (September 9, 12:52 local): Computer Use clicked
Escape and the visible Quit button in the extracted archive, running with Dummy
audio and a fresh isolated settings path. The process exited with code 0, no
signal, no timeout and no guarded errors after 22.816 seconds total runtime
(`/tmp/protocol47-packaged-final.xKNkbd/native-quit-final.log`). Two earlier
interactive checks reached their 180/120-second harness deadlines before a Quit
click could be delivered; those are failed test attempts, not Quit failures.
The first interactive run did show invalid-port feedback, Return Offline and
Dust2 deployment. An earlier external `--script` fixture attempt also timed out:
the release template does not support that editor-only script override and ran
the normal main scene. It is not packaged regression evidence.

Current release scope: **Dust2 only**, per the user's September 8 direction.
Assault remains in the repository, but its fixes, feature work and benchmarks
are deferred, not shipping requirements. Historical multi-map evidence below
does not expand the current scope. Focus new validation and performance work
on Dust2 with both teams; no new map support or map-transition work is required
for this release.

Scope constraint: finish the existing Dust2 game, basic direct host/join multiplayer,
smooth gameplay and essential release checks. Reuse the current menus and
systems. Accounts, matchmaking, rankings, extra modes and new service
infrastructure are out of scope. Entries below are chronological evidence;
older gaps may be superseded by later checks, not additional feature requests.

September 9 owner movement prediction: the client now reuses PlayerController's
movement-only step, including the existing GoldSrc map collision solver. The
normal gameplay tick remains disabled: prediction cannot fire/reload, advance
weapon clocks, damage players, trigger pickups or decide objectives. World
schema 5 carries owner crouch/jump state, controls/objective locks and speed
overrides. Consumed-input acknowledgments remove old commands; remaining input
is replayed from host position/velocity without rewinding current aim. Replay
is bounded to 25 commands / 250ms, expires old input, stops on stale snapshots
and clears on life/epoch changes, death, teleport or disconnect.

The new mandatory silent fixture compares prediction against normal host
physics through turning, jumping, crouching, walking and solid-wall contact
with staged 50ms-delayed snapshots (peak position difference 0.00000006 world
units). It also checks combat isolation, acknowledgment/history bounds, stale
updates, objective movement caps, freeze, death, teleport and cleanup. This is
deterministic fixture evidence, not a WAN performance result. The real Dust2
headless pair passed (`RH4xrL`): with presentation snapshots withheld for twelve
physics-frame signals, the owner moved 0.065756 world units while its applied
snapshot tick stayed unchanged. Buying, one host-owned shot, damage, drops and
C4 through round 3 still passed; peak chunk/snapshot sizes were 1,016/1,303 bytes.
The first delivery-gap assertion expected 5cm after only nine executed movement
steps; diagnostics measured 4.54cm at normal acceleration. The fixture now
allows eleven executed steps, retaining the 5cm requirement and normal physics.
Initial fixture compile/type/setup failures were corrected before these passes.
Dynamic player/brush collision agreement, correction presentation under jitter,
combat/grenade feedback and full multiplayer match/soak checks remain open.
The previous validation ZIP predates this prediction change; the latest
`-prediction.zip` archive above includes it.

The filtered Dust2 regression finished at `2026-09-09T17:00:22.656Z`: 54
commands / 62 markers, including network, HUD/Quit, movement/collision, weapons,
rounds, joins, both-team win/tie/halftime/rematch lifecycles and observers. The
real world pair ran separately. All 61 Node runner/auditor tests also passed.
The final silent native world pair passed (`P5cF6Q`), including the staged
snapshot gap (0.065756 units of local movement, unchanged applied snapshot tick),
with 1,016/1,312-byte peak chunks/snapshots. Its client gameplay capture was
inspected. These are functional checks, not new GPU timing or WAN soak clearance.

The preceding native attempt (`DK3qi3`) failed: the host timed out waiting for
admission at 22.646 seconds, while the client stayed alive without reaching Join.
The exact owned client process was sampled, then terminated at 89.159 seconds
after its host had failed. Sampling did not identify the script wait. The world
fixture now logs loading/capture stages and has a 60-second internal deadline;
the diagnostic rerun above passed without a production startup change. That
later pass does not explain or close the intermittent native startup wait.

September 9 direct connection menu: New Game / Find Servers now open the
existing-style Dust2 host/join form, with address/port validation, status,
bounded connection/world waits and retry. Return Offline / Disconnect closes
ENet and rebuilds a fresh offline Game with bots, collision and authority; it
does not partially convert the client pawn. Settings remain untouched. Escape
works before deployment, and Resume restores the team/class keyboard contract.
The menu fixture checks malformed inputs, exact staged timeout boundaries,
retry, real ENet hosting, duplicate-start rejection and two offline reloads.
Those staged timeouts are not adverse-network gameplay clearance.

The two-process Dust2 world test now uses viewport clicks on the actual
Host/Join controls before its existing team/class, buying, shooting, drop and
C4 sequence. Headless (`0DpI9u`) and silent native (`9bGkac`) pairs passed and
exited cleanly; the native connect-menu capture was inspected. Native peak
chunk/snapshot bytes were 1,016/1,223. All 60 Node runner/auditor tests passed.
Remaining client prediction, replicated combat/grenades/objective feedback,
network-condition tests and full-match GPU/release checks are still open.

The broader Dust2 run first stopped at the initial team Cancel fixture: it
assumed Cancel was inert and sent team digits behind the newly opened game
menu. The fixture now asserts that Cancel cannot start play, that it opens the
menu, and that Escape/Resume restores team input before normal selection.
The fresh rerun completed 52 commands / 62 markers at
`2026-09-09T15:12:36.063Z`, covering network, HUD/Quit, weapons, rounds, movement,
joins, both-team win/tie/halftime/rematch lifecycles and observers. It is a
filtered strict command run, not the full headless report or a played-match soak.
The connection panel is now opaque after capture inspection showed background
team text bleeding through it.

The final DNS follow-up was made after that run's network checks. ENet's direct
hostname connection can invoke blocking resolution (see the
[engine connection implementation](https://raw.githubusercontent.com/godotengine/godot/4.6/modules/enet/enet_connection.cpp));
the game now uses the [queued IP resolver](https://docs.godotengine.org/en/stable/classes/class_ip.html)
and passes only a resolved numeric address to ENet. Resolution shares the
10-second connection deadline and is discarded on timeout/disconnect/Quit.
Pending DNS disables duplicate starts and remains an inert client role.
The final silent menu fixture passes queued-lookup timeout/retry/cancel checks;
the real world pair now connects through `localhost` to exercise resolution.
That final silent native pair passed (`q6Kno1`), with an inspected opaque
connection-menu capture and 1,016/1,230-byte peak chunks/snapshots. The native
menu test passed in 16.180 seconds, including two offline scene rebuilds.
Actual Quit clicks while DNS was queued passed headlessly (2.578 seconds) and
natively (11.346 seconds), with clean process exits and cleared resolver/session
state. The pending-lookup Quit case is now mandatory in the HUD suite. All 60
Node runner/auditor tests passed again. These are functional checks, not new GPU
timing evidence; the renderer default remains Compatibility.

The repaired optional Metal profiling run completed 9,000 aligned ticks with
24,439 draws, p95 7.664 ms, p99 9.951 ms, max 56.721 ms and five frames above
33.333 ms (`/tmp/protocol47-dust2-metal-profile-20260909.json`). Its longest
recorded bot command was 2.359 ms; round reset Game physics was 18.165 ms,
including 7.709 ms resetting combatants and 4.494 ms bot buying with no new
templates. None of its slow-frame boundaries had a recorded >15 ms Game update
or >2 ms bot command. This narrows the sampled script paths, not the entire
CPU/render/OS cause. Instrumented timing is not release smoothness evidence.

September 9 continuation: the interrupted native check actually completed at
`2026-09-08T16:40:40.792Z`. Polling its original handle confirmed native hosted
Quit and the rendered Dust2 pair passed (`6PjzFn`), including open host/client
menus, buying, shooting and C4 progression; peak chunk/snapshot bytes 1,016/1,231.
The earlier unexplained native wait is still not closed by these later passes.

Fresh 9,000-tick Dust2 T live probes on September 9 (muted 1280x720, normal AI/
movement/damage, diagnostic starting AK and skipped initial freeze; not full
matches) both rendered every sampled frame. Compatibility produced p95 9.456 ms,
p99 11.819 ms, max 263.132 ms, 19 frames above 33.333 ms and 13 failing one-second
windows (`/tmp/protocol47-dust2-live-20260909.json`). Metal/Mobile produced
p95 8.128 ms, p99 11.268 ms, max 128.284 ms, three frames above 33.333 ms and one
failing window (`/tmp/protocol47-dust2-metal-20260909.json`, inspected capture).
Both recorded 30 local shots. Neither clears smoothness. No renderer default
changed. The largest stalls had unchanged effect counters; that excludes a new
effect emission at those sample boundaries, not all rendering or OS causes.

The Metal run's second-round reset appeared later in engine ticks despite the
same first-round result tick. The fixture did not record pauses and accepted
desktop input, so interruption cannot be excluded from that comparison. Live
probes now disable scene/player/spectator desktop input and GUI input, release
the cursor, record pause/time-scale observations plus kernel/engine clock gaps,
and fail on interruptions or lost active-match ticks. The full-match auditor
requires those fields. New negative metadata checks pass; a 9,000-tick silent
CPU-only run verifies zero pause observations, zero clock gap and 9,000 kernel
ticks (`/tmp/protocol47-dust2-clock-20260909.json`). It is not GPU evidence.

Earlier pause evidence:

The input-isolated Metal T rerun completed cleanly: 24,340 draws for 24,340
sampled frames, 9,000 kernel/engine ticks, zero pause observations/clock gap,
p95 7.545 ms, p99 10.060 ms, max 92.258 ms, twelve frames above 33.333 ms and
four failing one-second windows (`/tmp/protocol47-dust2-metal-isolated-20260909.json`).
This removes pause interference from this run but does not clear smoothness.
A concurrent read-only system sample showed other desktop apps consuming CPU;
that is not causal attribution, and no other apps were stopped or changed.
Thermal/power warnings were absent. The first subsequent profiling attempt
failed before gameplay because its override had not followed the production
round-reset signature; the failed process was terminated and recorded as a
failed gate. The adapter now forwards the survivor-loadout argument, and a bad
adapter load terminates the fixture immediately rather than leaving an inert
window until the outer deadline.

Dust2 pause isolation (September 8): opening an online pause/options menu now
blocks that player's input without pausing the authoritative world or client
presentation. Host menu state is separate from SceneTree pause; Escape closes
the menu, and entering options cannot accidentally restart a concluded match.
The raw local objective-input path now observes modal input blocking too.
Starting a host/join with an offline menu open releases the world pause without
dismissing the menu. Disconnecting an open host menu restores offline pause.

Inspection also found the Game root was ALWAYS, inherited by gameplay children
even while the round clock's explicit pause check stopped. The root is now
PAUSABLE. HUD/networking remain ALWAYS; paused unhandled keys are forwarded to
the existing Game handler so offline Escape and Quit still work. The pause test
uses viewport-dispatched Escape, verifies the offline pawn/weapon clock stop,
then starts a real loopback host with the menu open and verifies remote admission,
movement, one shot and advancing round ticks alongside neutral host input.

Fresh Dust2-focused headless regression passed 51 commands / 61 markers at
`2026-09-08T16:36:23.441Z`: network, HUD, weapons, rounds, movement, joins,
both-team match endings/rematches and observers, excluding Assault-specific
commands and hostage fixtures. This is not a full played-match/render timing
gate. The world pair (`PXGicH`) verifies host-menu-open buying, movement/shooting,
and continuing client snapshots with neutral input behind its own pause menu.
All 57 Node runner/auditor checks passed. The selected-suite JSON was separately
updated by the earlier HUD-only run (`2026-09-08T16:32:57.375Z` start); it is not
the 51-command run's report.

The first native pause fixture exceeded its 150-second outer deadline and was
terminated (`/tmp/protocol47-native-pause.log`); no other native checks in that
sequence ran. Its live process was retained/polled and sampled before timeout,
not treated as complete or restarted on an observation timeout. Sampling showed
an active event loop but did not locate the GDScript wait. The fixture now logs
stages and has its own 30-second failure deadline. A subsequent native run
passed in 12.034 seconds (`/tmp/protocol47-native-pause-stage.log`), including
viewport-dispatched offline Escape and host menu isolation. The original
intermittent native wait remains unexplained; a later pass does not close it.

Earlier buying evidence:

Dust2 multiplayer buying (September 8): the existing B menu now sends reliable
item-only requests, with host-selected prices and per-human wallet, team, life,
buy-zone and timer checks. The existing grant/carry rules are shared with local
buying; full/unavailable grants do not charge, and request replays cannot debit
twice. A CT kit updates that buyer's objective flag, not the host's. Live active
ammo is stored before grants so equipment buying cannot restore stale rounds.
World schema version 4 adds owner buy eligibility. Client snapshots refresh
inventory, wallet, menu account and disabled rows without resetting the current
page. Buy-menu digits cannot also select weapons; native cursor capture is
checked separately from headless input contracts.

Fresh silent checks: 25 HUD/weapon/round commands passed at
`2026-09-08T16:28:30.261Z`, including existing local buying and Quit. The
Dust2-filtered network group passed 16 commands / 26 markers at
`2026-09-08T16:29:07.462Z`; 56 Node runner/auditor checks also passed. These
selected commands do not replace the older selected-suite JSON or establish a
full release gate. The world pair (`0X2ZkM`) bought kevlar via B / Equipment,
checked the client's $800-to-$150 debit, unchanged host account, updated menu
and unaffordable-request rejection. Host fixtures cover both teams, zone/time/
life limits, ammo boxes, armor, grenade caps and duplicate requests.

The initial two buy pairs (`z7Eb7N`, `WDlfEa`) failed fixture expectations:
bought armor correctly changed the scripted 25-point hit from 75 HP to 89 HP,
and headless DisplayServer ignored an explicit captured-cursor request (2),
reporting visible (0). The test now expects actual armored damage on Dust2,
tests the menu input contract headlessly and retains the real cursor assertion
for native runs. No production damage or cursor thresholds were weakened.

The silent native Dust2 pair then passed (`Vdmfhh`): inspected
`client-buy-menu.png` shows ACCOUNT: $150 and disabled equipment rows after
the purchase. macOS accepted cursor mode 2 both in the control and after menu
close. The pair continued through gun/C4 drops, plant, round-three cleanup and
clean disconnect; chunk payload peak stayed 1,016 bytes, compressed snapshot
peak 1,223 bytes. This is functional rendering evidence, not a GPU timing run.
No current smoothness or release clearance is implied.

Earlier world-item evidence:

Dust2 world-item view (September 8): world schema version 3 adds stable IDs,
positions, rotations and C4 countdowns for dropped guns, airborne/landed backpacks
and planted C4. The client reuses existing source models with no collision,
pickup or bomb simulation nodes. Repeated updates retain the same model; flight
transforms interpolate, and complete snapshots remove picked-up/reset items.
Epoch changes, disconnect and late switching from offline clear replicas and
old local items. The codec bounds 32 actors and 512 world items together, with
strict kind/weapon/identity/rotation/countdown validation and no network-supplied
asset paths.

The expanded live scene reached a 1,212-byte compressed snapshot, exceeding the
unchanged 1,200-byte payload target. Snapshots now use 960-byte chunks on the
existing unreliable channel, applied only after complete validated reassembly.
Serialized chunk payloads peak at 1,016 bytes (before transport headers). Two
in-flight snapshots are retained, each at most 32 KiB encoded / 35 chunks;
incomplete buffers expire after one second and decoded size is bounded at
256 KiB. This preserves the last complete world under missing chunks instead
of applying partial item removals. Unit checks cover reorder, duplication,
missing parts, expiry, bounded buffering, mismatched counters, invalid envelopes
and combined maximum actor/item counts. These are not adverse-network soak or
worst-case rendering/performance clearance.

Dust2-focused regression completed at `2026-09-08T16:14:59.684Z`: 36 commands,
46 pass markers, no detected errors/leaks; all 55 Node runner/auditor tests also
passed. Same selected package groups/filter as the prior Dust2 run; the older
selected-suite JSON is not this run's report. World-pair artifact `o768N6`
passed model identity reuse, collision-free gun replicas, death/manual drops,
backpack flight/pickup, client-selected C4 and normal-duration held-fire plant,
planted countdown and round-three cleanup. The toss starts above spawn and
travel to the bombsite is staged; this is not a from-spawn objective route test.
The first native item capture (`tVHw1L`) stalled in an unbounded post-draw wait
and failed its deadlines; it is not passing evidence. The fixture now uses the
existing debris-capture pattern: two process frames and an explicit capture
draw, not a timing sample. The subsequent silent native pair passed (`LDopyz`)
with 1,016-byte chunk payloads / 1,216-byte peak compressed snapshot. Inspected
`client-dropped-gun.png` and `client-planted-c4.png` show the actual client models
in Dust2. Both processes exited cleanly. No new GPU timing clearance.

Still open: grenades/brush-state replication, audiovisual events and
objective feedback, prediction/reconciliation, broader Dust2 network/performance
coverage and release packaging. Visible world items do not establish production
readiness or a fully synchronized match.

Earlier secondary/drop evidence:

Dust2 secondary/drop actions (September 8): right-click and G now send reliable
`secondary` / `drop_weapon` requests through the existing action channel, with
the expected held weapon. The host checks sender ownership, life/control state,
weapon identity and existing cooldowns, then invokes the normal secondary/gun/
C4-drop paths. A delayed action cannot silently target a different weapon;
replays cannot toggle modes or duplicate a drop. Read-only client pawns cannot
run local secondary/drop simulation. Owner mode snapshots now update HUD labels,
zoom FOV and the existing silencer-transition animation.

This exposed a scope-state bug: movement speed and shot spread previously inferred
zoom from camera FOV below 89 degrees, including an unzoomed remote camera's
74-degree default. They now use the weapon's actual zoom mode; returning to a
sniper resets zoom. `network_weapon_action_test.gd` passes host-side burst,
cooldown/replay, freeze/death, mismatched-weapon, zoom levels/accuracy/movement,
silencer, knife-secondary and exact-ammo gun-drop checks on Dust2. It is required
by the network suite. All 55 Node runner/auditor tests passed.

The Dust2 Game pair passed real mouse/key input for burst toggling, gun drops and
C4 drop/pickup (`9CVukQ`). The C4 check initially assumed the backpack would stay
dropped, but traces show a valid pickup near spawn geometry two ticks after the
accepted drop. The corrected fixture checks exactly one remote manual-drop event,
one corresponding world spawn and consistent subsequent ownership. Its staged
initial transfer explicitly consumes its round events. Normal pickup physics
and network acceptance thresholds were not relaxed. The expanded pair also
checks client zoom/restored FOV. The Dust2-focused regression completed at
`2026-09-08T16:01:35.218Z`: 35 commands, 45 pass markers, no detected errors/leaks.
It reused `runCheckedCommand` over the network/weapons/HUD/movement/ballistics/
timing/joins/matches/observers package commands, excluding `cs_assault` commands
and the Assault-specific `network_human_world_use_test.gd`. This was a selected
run, not the older JSON report or a full release gate. Current headless world-pair
artifact: `tyrFvW` (1,069-byte peak). A subsequent silent native Dust2 client
also passed the full input/zoom/drop sequence (`WFeYXQ`, 1,076-byte peak);
captures show the existing map, HUD and remote actors. Both processes exited
cleanly. These are functional checks, not GPU timing or smoothness clearance.

Still open: buying, client rendering of dropped/objective/dynamic entities,
firing/reload presentation, prediction/reconciliation and Dust2 network/performance
coverage. Gun/C4 drops currently exist on the host and update client inventory;
this is not yet shared world-item rendering or a complete playable release.

Earlier inventory/selection evidence:

Owner inventory and weapon selection (September 8): world schema version 2
adds the recipient's carried weapons, exact active/inactive ammunition, previous
weapon, equipment and mode flags. Inventory is owner-specific, bounded by the
registry, type-checked and detached; duplicates, unknown weapons and conflicting
active-ammo values are rejected. Clients use that inventory for the existing
slot/lastinv input. Reliable `select_weapon` actions share the existing bounded
action channel; the host resolves the sender's pawn, rejects inactive/dead or
unowned requests and invokes the normal weapon switch without granting items.
Read-only client pawns cannot run `switch_weapon` to change authoritative ammo.

Dust2's real Game pair passed slot 1/2/3, grenade cycling, Q/lastinv and slot-5
C4 selection, host-only grants, exact ammo preservation and unowned-rifle rejection
(`9Pi94s`, peak 1,065-byte world payload). Grants are staged in this test, not
proof of network buying. The first expanded test pressed a semi-auto pistol
during deploy and timed out; the fixture now waits the existing deploy duration
before its single shot. Production weapon timing was not changed. Unit checks
cover all registry weapon identifiers/ammo, strict inventory shapes, equipment
flags and selection replay; host admission checks also cover freeze-style
selection, reload cancellation, same-weapon deploy stability and dead players.
The seven-suite regression completed at `2026-09-08T15:51:22.320Z` with 76 pass
markers and no detected errors/leaks: network/weapons/HUD/joins/rounds/observers/
matches. Report: `game/artifacts/headless-test-selected-report.json`. It was
already running when scope narrowed to Dust2 and finished normally. Current
Dust2 world-pair artifact: `V9gBtQ`, peak 1,065 bytes. All 54 Node runner/auditor
tests also passed. No new rendered timing or full-gate clearance.

Still open for client weapons: buying, drop requests, secondary actions,
presentation of firing/reload/mode changes and prediction/reconciliation. World
objectives/dynamic entities, broader network tests and release validation also
remain open. Inventory and selection alone do not establish shared playable
multiplayer or production readiness.

Earlier shared-actor evidence:

Shared actor view (September 8): connected clients now reuse the existing map,
team/class menu, first-person view, character models, HUD and spectator camera.
Their local round/AI/combat simulation is stopped; 20 Hz host snapshots supply
actor identities, positions, health, active-weapon ammunition and round scores.
Remote actors interpolate between updates; owner movement still snaps to host
updates, so prediction/reconciliation and network smoothness remain unfinished.
Snapshot validation rejects malformed fields and stale epochs/ticks. A bounded
Zstd envelope checks its declared decoded size before decompression. Normal
ten-actor fixtures measured 867–884 bytes; this is not a worst-case MTU guarantee.

Actual Game host/client pairs passed on Dust2 (`bkZMye`, 876-byte peak) and
Assault (`uu8HKy`, 875-byte peak): menu admission, held-input movement, one
host-owned pistol shot, replicated damage/ammo, elimination/score, death models,
round reset/revival and disconnect cleanup. Client attempts to simulate combat
or restart the round leave host-derived state unchanged. Opponents are stationary
in these controlled fixtures; these are not full-AI matches or network soaks.
A silent native Dust2 client also passed (`iAgsGu`); inspected captures show
remote character models and HUD health 75 / ammunition 19. This is functional
rendering evidence, not GPU timing or smoothness clearance. The network gate
now requires the world-state unit and both map pairs; 54 Node runner/auditor
tests passed. A subsequent selected gate caught an RPC to the Quit fixture's
registered-but-unconnected peer; sending now requires a live transport peer,
with a dedicated negative assertion. The corrected six-suite regression passed
at `2026-09-08T15:43:51.137Z`: network/HUD/joins/rounds/observers/matches,
74 pass markers, no detected errors/leaks and all child processes terminal.
Report: `game/artifacts/headless-test-selected-report.json`. Current world-pair
artifacts are `AyT9lZ` (Dust2, 869 bytes) and `YwcJZ2` (Assault, 884 bytes).
All 54 Node runner/auditor tests also passed again. This is selected regression
coverage, not a fresh full gate or GPU clearance.

Still unfinished: objective/dynamic-entity replication, full inventory and other
discrete actions, firing presentation, owner prediction/reconciliation, map
transitions and broader network/performance coverage. Both peers currently need
the same map through the development CLI. A disconnected client stays stopped;
in-place client-to-host/offline switching is not implemented. This is a shared
actor view, not a complete shared playable match or a release-ready build.

Earlier admission-only evidence:

Reliable multiplayer admission (September 8): client team/class API requests
now use strict versioned envelopes on reliable ENet channel 2. Host dispatch
uses the actual registered RPC sender, monotonically consumes request counters,
rejects malformed/spoofed/replayed requests and independently limits accepted
gameplay actions to an eight-command burst and eight per second per peer.
Valid gameplay/rate-limit failures receive explicit results; client results
must match a pending action/sequence/selection. Pending client work is bounded
to sixteen requests and expires after five seconds with an unknown-outcome
timeout, not an authoritative rollback. Disconnect clears action state and
Game teardown releases its handler. Movement remains on its existing channel.

The new unit fixture passes malformed request/result, ownership, replay,
rate/boundary/isolation, unbound-handler, reconnect, result correlation and
timeout/departure cases. Real two-process ENet fixtures passed on Dust2
(`kQdiKE`) and Assault (`Zg9lxb`), including actual host team/class spawn,
duplicate/wrong-order rejection, host identity/camera isolation, ordinary input,
departure cleanup and reconnect with a fresh actor identity and reset request
sequence. Client-side pending-capacity/local-invalid selection checks were added
before the Assault pass. Both pairs and the action unit fixture are mandatory
in the network gate; all 53 Node runner/auditor tests pass. These clients are
transport fixtures, not rendered shared matches. Menu integration, other
reliable actions, replication/prediction, pre-decode/flood protection and
adverse-network tests remain open. No new GPU/smoothness clearance is claimed.

Fresh reliable-admission regression completed at `2026-09-08T15:20:57.244Z`:
six suites (network/HUD/joins/rounds/observers/matches), 67 pass markers, no
errors/leaks, all child processes terminal. The selected report is
`game/artifacts/headless-test-selected-report.json`. Current real admission
pair artifacts are `ldyxYp` (Dust2) and `abeKqQ` (Assault); both include the
client invalid-selection and pending-capacity assertions. Roster pairs are
`G9Ci9n` and `iXsOYP`; flat human simulation `Hiapv4` passed at 22 ms release
delay / 1.163 m total travel. This does not close the earlier unexplained
1.713 m fixture overrun, substitute for a fresh full gate, or establish shared
client rendering and network-condition coverage.

Quit menu repair (September 8): the real pause-menu button emitted
`quit_requested`, but Game had no listener. The new viewport-input test
reproduced the bug: the click did not exit within two seconds. Game now connects
that request, releases mouse capture, disconnects the network session and asks
the scene tree to quit. Offline and host-session headless tests terminate
cleanly; the host case also checks pending-peer cleanup. A muted native
Compatibility-window run exited with code 0, no errors/leaks, one teardown
marker and no timeout (`/tmp/protocol47-menu-quit-native.log`, 11.059 seconds
including Game loading). Both headless cases are mandatory in the HUD gate.
This verifies actual GUI event dispatch and process termination, not just a
button signal. It does not validate the separate Disconnect/server-browser
menu workflows or packaged application shutdown.

Initial remote-human admission (September 8): host Game now validates
team/class selection, reserves map spawn slots and replaces exactly one
server-selected bot when a side is full. It preserves remaining bot positions
and durable brush activators. Class completion controls appearance and spawning;
late entrants wait for the next round, while duplicate class requests cannot
heal/rearm. Round resets preserve survivor equipment, give dead humans fresh
loadouts and retain unfinished appearance choices. Halftime and rematch update
remote team/skin/spawn state without allocating new connection identities.
The host body becomes hittable by human bullet masks while admitted peers exist.
Radar contacts and local death-camera candidates now include remote teammates.

The real-map admission fixture passed on Dust2 and Assault and is now mandatory
in the network gate. Its additional spectating assertion initially checked
after one second despite the production two-second activation delay; it now
tests both sides of that unchanged delay, cycling and respawn camera return.
Projected replacement unit tests reject unknown/self/opposite-side targets
without mutation, retain capacity/balance limits, and cover the inclusive
two-player imbalance boundary. The initial unit failure expected that legal
boundary to reject; the corrected case also checks a three-player imbalance
does reject. Kernel-first team-selection death now uses per-life spawn serials
for physical cleanup idempotence, so an already-recorded round death still
drops the human's weapon once. Client team/class RPCs, shared-world replication,
remote team changes/spectator selection, bot backfill and last-alive bot
replacement edge coverage remain open. All 52 Node runner/auditor tests pass.
No gameplay GPU benchmark or smoothness clearance was produced by these fixes.

The admission/Quit revision's fresh six-suite selection completed at
`2026-09-08T15:12:48.853Z`: 60 markers across HUD, network, joins, rounds,
observers and matches, no errors/leaks. This preceded the reliable action work
above. The selected report is replaced by subsequent selected runs; the older
full report is not fresh full-revision clearance.

Remote-human inventory/death (September 8): dropped guns now carry a durable
dropper ID. Only that manual dropper is suppressed until it leaves the pickup
radius; other living humans can collect immediately. Stable human ordering
allows exactly one simultaneous claimant, empty-slot checks prevent involuntary
replacement, and clip/reserve transfer intact. Pending/dead humans are excluded;
a disconnected dropper cannot strand an item or restrict a reused peer slot.
Remote gun-drop and combatant-elimination signals now drive actor-specific Game
handlers for physical item creation, round death/kill accounts, kill notices,
C4 release and control cleanup. Only local death schedules the host spectator
camera. Death callback duplicates are inert. Kill notices use remote human
weapon identity and actual headshot status. Manual C4 drop/pickup routing also
uses the owning human instead of the host row.

The staged host inventory fixture passed these cases, then a new corpse-pose
assertion exposed C4 inventory cleanup resetting a dead remote's model to idle.
Production now reapplies death presentation after a dead human's weapon-model
refresh; the expanded fixture passes. It is mandatory in `game:test:network`.
The existing local G-drop/bot-death/empty-slot pickup fixture passes and is now
mandatory in `game:test:weapons`. All 50 Node runner/auditor tests pass. The fresh
network/weapon/round/observer/join selection passed at `2026-09-08T14:50:27.766Z`:
five suites, 44 markers, no errors/leaks. The report is
`game/artifacts/headless-test-selected-report.json`; current loopback roster
artifacts are `6j7QaY` (Dust2) and `qxulnz` (Assault). The flat human simulation
`jI2CPd` passed with 28 ms release delay / 1.188 m total travel, without closing
the earlier unexplained movement-bound failure. A final standalone inventory
rerun also verifies the host spectator is neither active nor scheduled after a
remote death. These processes are terminal; no GPU run was made for this revision.
Admission is explicitly staged and drop actions call the host pawn seam: this
does not establish reliable client action transport, weaponbox flight/landing,
full remote respawn/halftime, client rendering or current GPU/smoothness clearance.

Remote-human world use (September 8): host Game now tracks each human's Use edge
and brush identity separately, includes remote hulls in touch/breakable processing,
and clears departed peers' edge/contact/position state without reusing their brush
IDs. Doors, hostages and C4 use the same candidate set and tick selection; world
use remains enabled while C4 is planted. The new staged host-Game fixture passes
independent local/two-remote input, expiry, actual Assault hostage first-use rewards,
real button/C4 competition, selection retention after target movement, two-human
door touches and reconnect cleanup. It stages team/alive state, not admission.

The fixture initially exposed host camera takeover through remote activation of
button 51's cam4 output. Production now stores remote camera transform/FOV/deadline
and input lock per activating human; normal timeout, phase reset and departure
clear only that state. Late IO from an old remote activator cannot target the host
or a replacement peer. This is server camera ownership, not client presentation
or complete Source camera-flag parity. The existing local camera origin/aim/return
fixture is now mandatory in `game:test:map`. All 48 Node runner/auditor tests pass.
The network/map/round/observer selection passed at `2026-09-08T14:42:55.362Z`:
four suites, 47 markers, no errors/leaks. The full gate started at
`2026-09-08T14:33:46.613Z` and finished at `2026-09-08T14:43:12.662Z` with
24 suites and 114 markers, no errors/leaks. It began before these world-use
edits and before the two new mandatory fixtures were wired, so it is not fresh
full coverage of this revision; no current GPU/smoothness pass is claimed.
Both runs are terminal. Their reports are the full and selected JSON files
under `game/artifacts/`. The current selected run includes loopback roster
artifacts `I2sCMx` (Dust2) and `4dhkrD` (Assault), and human simulation `Fk1QO4`
(42 ms release / 1.213 m total travel); this pass does not close the earlier
unexplained 1.713 m fixture overrun.

Remote-human objectives (September 8): Game's C4 path now recognizes remote
human bodies without a bot cast, uses their own validated held fire/use commands,
weapon clocks, hulls, ground contact and camera rays, and resolves active defusers
by durable roster ID. C4 inventory, movement locks and phase control/look flags
are per human. Pending peers remain inactive. The new staged host-Game objective
test passes normal-duration planting/defusing, release/retry, input expiry with
the existing use grace, objective credit, freeze and host-camera/input isolation.
It also rejects airborne and wrong-aim remote defuse requests. The test is now
mandatory in `game:test:network`; all 46 Node runner/auditor tests pass.
Team/alive state is explicitly staged: this does not establish combat admission,
shared client-world simulation, reliable weapon selection, remote objective
animation/UI, or C4 world pickup/drop. The fresh network/round/join/observer gate
passed at `2026-09-08T14:33:35.804Z`: four suites, 40 markers, no errors/leaks
(`game/artifacts/headless-test-selected-report.json`, since replaced by the newer
selected run above). A full gate subsequently started on the objective revision;
the world-use edits above began during that run, so no fresh full/GPU pass is claimed.

Pending-human Game roster (September 8): the actual Game now owns a
`remote_human_roster.gd` node bound to NetworkSession's registered host peers.
It handles connections established before Game load as well as later joins.
Each gets a unique reusable slot and monotonically increasing actor ID, separate
from the transport ID and scene-node name. IDs survive round resets/rematches
and are not recycled when the host restarts its transport within the same Game.
Client-side rosters cannot allocate authoritative humans. A connection creates
only an UNASSIGNED, hidden, non-solid, inactive pawn: no team, life, money,
device input or first-person model, and no character meshes until team admission.
The scoreboard now correctly places UNASSIGNED rows in the existing spectator
section, including the local observer case.

Departure unbinds input, disables the pawn, consumes round/C4 events while its
identity and transform are still available, removes round/knowledge/scoreboard
entries, stops that actor's voice channels, releases hostage leadership and
navigation state, then detaches and queues the node for deletion. A slot becomes
reusable only after that state/audio cleanup, not before the departure callback.
Whole-scene teardown disconnects callbacks and frees owned pawns without closing
the separately owned transport. Game actor-ID and position lookups include the
remote roster, and rematch registration preserves its connected identities.

Real two-process `--game-roster` checks pass on both imported maps, including
preconnected Game load, duplicate/unknown/local peer rejection, ignored movement
and fire while pending, node renaming, reset/rematch, reconnect, host restart and
teardown while still connected. Three connections produce `remote_human_1`,
`remote_human_2`, then `remote_human_3`, reusing audio slot 268435458 only after
cleanup. C4 and hostage ownership and audio events are explicitly staged for
departure checks: these do not prove combat admission, normal objective use or
two independently presented clients. Latest standalone artifacts are
`protocol47-network-F6aB5w` (Dust2) and `aJxjhl` (Assault); combined-gate cases
are `ABjSWK` and `L82UBj`, under the existing OS temporary directory. The network
group now requires both map cases. All 45 Node runner/auditor tests pass, and the
network/smoke/observer/join selection passes at `2026-09-08T14:19:46.870Z` with
22 markers and no errors/leaks.

A fresh full 24-suite headless gate started at `2026-09-08T14:22:18.179Z` for
the Game-roster revision and finished at `2026-09-08T14:31:29.104Z`: all 24 suites,
113 markers, no errors/leaks. Objective integration edits began after its
network/round suites had completed, so it cannot establish a fresh full pass
for those edits. The selected gate above rechecks the affected suites on the
objective revision. `game/artifacts/headless-test-report.json` is now being
replaced by the new full objective-revision run, not retained as the old result.

The first expanded objective gate failed its exact host-position assertion:
the camera was unchanged, but a staged ungrounded host holding its own +use
invoked ground categorization and snapped down 0.000112 m. The fixture now
explicitly stages the host as grounded for the defuse contrast (remote airborne
must still fail), while retaining the inverse grounding contrast for planting.
The exact host-position/camera assertion is unchanged. This is a fixture setup
correction, not a production movement or tolerance change.

One earlier combined run failed the unchanged human-simulation total movement
bound: 1.713 m exceeded 1.5 m (`protocol47-network-lKd2f4`). That isolated flat
fixture does not instantiate the new Game roster. Release-request/receipt timing
diagnostics were added without relaxing the limit. Eight bounded serial repeats
then passed: observed release delays 20–42 ms, post-observation friction travel
approximately 0.510 m and total travel 1.163–1.213 m. The combined rerun also
passed (29 ms / 1.188 m). These reruns do not establish a cause or a fix for the
original overrun. Keep this timing-sensitive failure open alongside the existing
GPU/frame-pacing failures; there is no new smoothness clearance.

Combat-team/class admission (including bot quota/capacity), active-human phase,
spawn, inventory, death, C4/use/drop and brush participation remain open. Pending
connection rows are not playable participants. IDs still need wire/epoch
replication, clients still simulate an offline world, and world authority,
prediction/interpolation and host/join menus remain unfinished. No new rendered
or full-duration multiplayer performance claim is made from these headless tests.

Round departure prerequisite (September 8): the Game integration audit identifies
singleton-only actor lookup, spawn/reset/phase, C4/defuse input, world use and
weapon pickup paths; the concrete integration map is recorded in
`multiplayer-implementation-plan.md`. Before admitting remote humans, round state
now exposes `disconnect_player(id, authoritative_position)`: it cancels an active
plant/defuse, drops carried C4 once, clears retry/roster state, emits a departure
record and reevaluates elimination without a synthetic death or kill reward.
A planted bomb retains its fuse and historical planter ID after departure.
That ID must never be reassigned to a different peer while old events survive.

The same audit found an existing elimination bug: `_check_elimination` awarded
an elimination against an empty team or appearance-pending-only opponents.
It now requires both sides to contain spawnable participants; alive/spawnable
counts share one roster pass. This follows
[ReGameDLL's ClientDisconnected and TeamExterminationCheck](https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/multiplay_gamerules.cpp).
The new `round_disconnect_test.gd` first fails on the missing operation and
elimination guards. Its first fixture used unsupported scenario aliases; these
were corrected to the exported scenario constants before the passing C4/defuse
checks. Current coverage includes both supported scenario kernels, neutral
disconnect accounting, duplicate/invalid departures, bomb/defuse lifecycle and
a 72-case elimination matrix (including mutual wipe and planted C4). The test
is mandatory in `game:test:rounds`. All 44 Node runner/auditor tests pass.
The selected rounds/matches/observers/joins regression passes at
`2026-09-08T13:59:55.404Z`: four suites, 32 markers, clean exits and no detected
errors/leaks. The eight match cases cover both maps, both starting teams,
first-to-16 and 15–15 endings, halftime and rematch; they are lifecycle fixtures,
not full-duration gameplay soaks. Those test processes have ended.
There is no fresh full-gate or GPU timing clearance for the round-departure revision.

The pending-roster integration above now connects part of this cleanup to the
world/transport lifecycle. Active participants still need use/touch/drop history
cleanup and physical defuser items. The full empty-server/game-commencing and scoring lifecycle is
still open; an elimination guard does not establish those separate behaviors.

Remote-human ownership/presentation (September 8): `PlayerController` now has
an explicit pre-tree `configure_remote_human(slot)` role, separate from peer
binding. Remote pawns start with the network controller, never subscribe to
device input or claim the viewport, allocate no first-person model/light, and
use the existing third-person character/weapon renderer. Their audio channels
use `0x10000000 + slot`, separate from local ID 1, bot IDs, map entities and
grenade fallback IDs. The future host roster must allocate unique slots; this
API is not itself a roster or a client-authorized ownership operation.
Remote hulls use actor collision layer 2. Model aim, locomotion, firearm/knife/
grenade/reload actions, death, respawn and side-switch appearance are connected
to human simulation. Remote eye bob/FOV do not read the host's accessibility
or display preferences. Local offline behavior is retained.

`network_human_ownership_test.gd` passes with one local and two remote pawns,
including remote-first camera initialization, immutable live ownership,
independent concurrent audio channels, no host mouse/settings leakage, weapon
handling without a viewmodel, and mesh reuse on same-loadout respawn. The real
two-process fixture now also includes a local host pawn, and verifies its
camera, transform and shot count remain unchanged while the remote moves and
fires. The first run exposed a one-shot unreliable final acknowledgement and
a fixture comparison against the requested rather than floor-adjusted spawn;
the acknowledgement now repeats until host departure and the comparison uses
the actual spawn. The corrected strict network/movement/smoke run passes at
`2026-09-08T13:45:45.454Z` (11 markers). The RPC case `protocol47-network-crO9lq`
records 1.213 m movement, one shot, clip 19 and target health 79. All 43 Node
runner/auditor tests pass. A muted native Compatibility run of the ownership
test also passes with clean exit/errors/leak checks; the inspected 1280x720
capture `/tmp/protocol47-network-ownership-pair.png` shows both remote team
models through the retained local camera. This is rendered correctness, not
a timing benchmark or original-game visual parity proof.

A fresh full headless gate for this ownership revision started at
`2026-09-08T13:47:31.000Z` and passed at `2026-09-08T13:56:49.045Z`: 24 suites,
106 markers, clean exits and no detected errors/leaks. Its network group passed again (RPC artifacts
`protocol47-network-XQdcDs`, movement 1.163 m, one shot, clip 19, target 79).
The authoritative result remains `game/artifacts/headless-test-report.json`.
It predates the round-departure change above; do not treat it as that revision's
full regression or as GPU timing evidence.

Combat-team admission/spawning, local-host network collision participation,
shared world authority, third-person muzzle anchoring refinement, client-side
presentation/prediction and connected menus remain open. The remote shot effect
currently uses the existing world-shot anchor, like bots, not a verified
per-weapon third-person barrel attachment. Neither this fixture nor remote
pawn initialization makes the command-line host/join mode a shared match.

Remote-human simulation seam (September 8): a new controller test first fails
on the absent remote adapter and base-angle command API. The production
`network_human_controller.gd` now consumes detached, validated peer input into
the existing human command seam, with explicit registered-peer binding,
held-versus-pressed fire handling, per-command reload consumption, neutral input
after expiry, and ownership clearing on departure/disconnect. Reusing a peer
ID requires explicit rebinding. It does not use bot movement or aim logic.
`PlayerController` accepts finite absolute base yaw/pitch separately from local
mouse sensitivity/inversion, and Game sends those base angles rather than the
rendered recoil-added body/camera angles. Recoil is therefore not applied
twice to a received command. Local mouse behavior remains covered.

The real two-process loopback `--human-simulation` fixture passes repeatedly.
Remote input moves a normal human hull on a floor by approximately 1.14–1.16 m,
then stops through production friction. One held Glock press fires one shot,
uses one round (20 to 19), damages a staged opposing target (100 to 79), and
emits production effects. Freeze blocks movement/fire while preserving look;
silence expires held input; the client observes the server-generated position
via production snapshots. No received transform or test teleport moves the
human. The initial fixture had one server human and a staged target; the newer
ownership revision above adds the local host pawn. Neither is a complete
Game, roster or two independently presented human clients. They do not prove
damage/ammo replication, full-world authority, UI, prediction, reliable actions,
packet-loss behavior or a playable multiplayer match.

The strict network + movement + existing game smoke selection passes at
`2026-09-08T13:31:15.729Z`: three groups, ten markers, clean exits and no detected
errors/leaks. All 43 Node runner/auditor tests pass. Human-pair artifacts include
`protocol47-network-xbu5py`, `xtgfnn`, `zhGFZG` and the new full-run case
`6rOpZW` under the existing OS temporary directory. The expanded network group
is mandatory in the full 24-group headless gate. That full rerun finished at
`2026-09-08T13:41:56.301Z`: 24 groups, 105 markers, clean exits and no errors.
It predates the ownership/presentation changes above; do not use it as full
coverage of that newer revision. All GPU timing/profiler capture ended before
these checks. Current gameplay smoothness remains unproven.

Render-pacing controls (September 8): serial 95-second standalone Compatibility
runs at 1280x720 confirm the periodic hitch with both VSync disabled and enabled
(the latter is the game's normal settings default). Audio is Dummy, no game is
loaded, and every measured interval has a draw. The uncapped report
`/tmp/protocol47-render-baseline-pacing-off.json` has 97,678 intervals, p95
2.165 ms, p99 3.708 ms, and three intervals above 25 ms, spaced 30.111932 and
30.127535 seconds; maximum is 35.450 ms. The VSync-on report at the matching
`pacing-on.json` path has 11,045 intervals, p95 15.134 ms, p99 17.486 ms and
maximum 33.382 ms. Its periodic trio is spaced 30.109450 and 30.142960 seconds,
with three additional intervals above 25 ms. The first on-mode periodic hitch
is approximately 60.244 seconds after the last off-mode one, continuing across restart.
This rules out disabled VSync as necessary for this recurrence, not an OS/driver
owner or the cause of every game stall. Invalid/duplicate mode arguments and
headless timing are rejected. No default game setting changes.

An Instruments-launched System Trace reports target exit zero but produces no
probe-completion artifact, so it is not usable as a completed control. A second
trace attaches to the confirmed ready standalone process: the 120-second probe
finishes, with `instrumented: true` in `/tmp/protocol47-render-system-attach.json`.
The 40-second trace is retained at `/tmp/protocol47-render-system-attach.trace`
(approximately 1.8 GiB), with a 45-second recording window. The thread-state
export contains 1,618,274 rows and 468,613 main-thread rows; its long main-thread
intervals include a 62.726 ms Blocked span. This does not identify the blocking
resource. Wall-clock-to-event-clock alignment is not independently validated,
so provisional per-frame overlaps must not be used for attribution. Tracing and
trace processing substantially disturb the minimal scene (86 intervals above
25 ms, maximum 155.258 ms), so none of those timings are clean evidence. The
recurring clean-control hitch and transient game cluster remain unresolved.

Full-match timing acceptance follow-up (September 8): the
existing performance wrapper only enforces measurement/activity and clean
process completion. New `scripts/audit-game-smoothness.mjs` separately evaluates
recorded full-match timing. It requires actual draw coverage, intact effects,
normal full-match metadata, complete/non-overlapping frame-window totals, and
finite, ordered metrics. Overall and every nonempty 100-physics-tick window
must meet p95 <=16.7 ms and p99 <=25 ms. Any interval above 50 ms fails pending
review, including non-combat intervals; this is a conservative implementation
of the existing provisional smoothness target, not a source-engine standard.
No slow intervals are excluded based on attribution. The detail list is capped
by the fixture, so acceptance uses complete aggregate/window maxima and counts,
not only `slow_frames`. Loading remains separate.

`game:perf:full-match` enables `--require-smoothness` after the native checked
process succeeds and requires a report written during that run. Diagnostic,
headless, short-match and unknown fixture options are rejected in this mode.
`game:perf:audit` checks an existing report without starting Godot; it explicitly
does not verify process exit, freshness, target hardware or workload isolation.
Neither is release clearance from a single scenario. All 42 Node runner/auditor
tests pass after the GPU process finishes. They cover slow-window masking,
isolated hitches, exact threshold boundaries, malformed/missing metrics,
window totals and bounds, CLI failure exits, report freshness, clean-process
prerequisites and package/argument bindings. The artifact-only command rejects
the completed GPU report below with exit 1 and only timing-limit failures,
not missing-metadata failures. The new integrated full-match flag has not yet
been exercised by a fresh native full match; its helper/bindings are tested.
No production game or active native fixture was changed during this timing run.

A lightweight mid-run host observation shows a MacBookPro18,2 with 64 GiB RAM,
zero swap allocation/use and no recorded thermal/performance warning in
`pmset -g therm`. Chrome, WindowServer and the Datadog agent are among active
background processes. These observations do not correlate any process with a
specific slow frame or establish that the whole host is idle. No unrelated
application or service has been stopped. "No overlapping tests/builds" must
not be read as "no background workload."

Transport-validation foundation (September 8): the initial native packet test
reproduces non-finite local look/snapshot time and session counters surviving
disconnect. `NetworkSession` now distinguishes tolerant local normalization
from strict version-1 wire validation. Wrong types, missing/extra fields,
non-finite/out-of-range values, stale input/snapshot counters and unknown peer
IDs are rejected before entering retained session state. Accepted remote input
is limited to a 16-command burst with 120 commands/second refill. Held input
expires after 250 ms of silence without resetting its replay history. These
are explicit current transport defaults, not a source-engine timing-parity
claim. Departure/disconnect clears peer state; reconnect resets local counters
and snapshot history. Offline input no longer advances transport counters.

Two actual Godot processes exercise the production RPC methods on loopback,
including malformed top-level/value/owner packets, valid normalized input,
snapshot ordering, automatic physics-loop input expiry, disconnect and a fresh
connection with counters restarting at one. Four serial paired runs pass,
with clean exits and no detected errors/leaks. The native packet suite also
tests peer capacity, wrong scalar/vector types, burst refill, dictionary
ownership, expiry boundaries, missing fields and restart state. The strict
network + existing game smoke selection passes at `2026-09-08T12:38:22.978Z`
(five markers), and all 29 Node runner tests pass. Diagnostics are retained in
`/var/folders/9y/b4wfvjjj7c30rs6464rcxtvm0000gn/T/protocol47-network-*`.
The new mandatory network group brings the full headless suite to 24 groups;
its fresh full rerun passes at `2026-09-08T12:49:25.541Z`: 24 groups, 101 pass
markers, all child exits zero and no detected errors/leaks. Report:
`game/artifacts/headless-test-report.json`. No GPU timing overlapped it.
A further paired check at `protocol47-network-c89H1n` also verifies 40 immediate
host-local commands are retained under host ownership without the remote rate
limit, and claimed-owner remote input cannot overwrite that state. This extra
fixture assertion passes separately after the full run's network group loaded;
the production transport code is unchanged by that test-only extension.
The packet fixture also separately passes added checks for uninterrupted
100-Hz input and independent per-peer allowances
(`/tmp/protocol47-network-packet-rate-final.log`). Those assertions likewise
follow the full run's packet group without changing production code.

A fresh muted, default-Compatibility full-match GPU run completes cleanly at
`2026-09-08T13:09:09.796Z`:
`/tmp/protocol47-assault-ct-solo-objective-full-match-gl.json` and matching
`.png`. It starts only after all headless/network checks finish, with no
overlapping test/build/game processes. The checked wrapper exits zero; 162,056
intervals / 162,055 draws cover 108,364 sampled physics ticks and 17 rounds,
with 112 local shots, 6,686 effects, maximum blockage 152 ticks and zero freeze
violations. Round-end, halftime, match-end, final actor and final hostage state
exactly match the corresponding CPU report. The ending is T 16 / CT 1 at kernel
tick 108,365, with halftime at 95,295. The inspected capture shows the match-over
score, rematch prompt and retained weapon/actors; it is not original-engine
visual-parity evidence.

Smoothness still fails: overall p95 11.633 ms, p99 14.784 ms, maximum 108.576 ms,
and 70 intervals above 33.333 ms. Of 1,084 nonempty one-second windows, 20 exceed
p95 16.7 ms, 36 exceed p99 25 ms, and 12 contain an interval above 50 ms. The
worst cluster is around ticks 61,100–61,599: window 61,100 has p95 70.535 ms,
while window 61,400 has the 108.576 ms maximum with zero new effects and five
living actors. This does not establish a combat trigger or an external cause.
The diagnostic slow-frame list stops at 64 entries although 70 slow intervals
are counted; the new acceptance gate uses the complete windows/aggregates and
correctly rejects this report. Earlier driver workloads differ, so the reduced
maximum versus the older run is not proof of a performance fix. Periodic-hitch
and transient-cluster attribution remain open. Both benchmark processes are
confirmed terminal before the 42 Node checks start.

The tests bind the host to `127.0.0.1` using Godot's
[ENet interface binding](https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html#class-enetmultiplayerpeer-method-set-bind-ip),
use fresh per-process settings paths, and bound both child processes with the
strict timeout/error/leak guard. Normal hosting retains its existing wildcard
binding. Peer IDs identify an established transport sender, not an authenticated
user account. This work does not add remote gameplay consumers, human roster
ownership, prediction, weapon/discrete-action input, authentication/encryption,
or pre-decode packet-size/flood protection. Accepted-command rate limits are
not proof against transport-level denial of service. Full multiplayer remains
open; see `multiplayer-implementation-plan.md`.

Sole-survivor benchmark-driver follow-up (September 8): the new
`match_driver_solo_test.gd` first fails because the last CT emits no movement
without an alive ally. The test-only driver now gathers unrescued Assault
hostages with normal edge-triggered use input, then follows a stable rescue
destination. It does not set hostage ownership, awards, positions or clock
values. Combat still takes priority, and human death/freeze disables intent.
This closes the identified Assault last-CT input gap, not every bomb-map
solo-human action or full multiplayer input ownership.

The stronger from-spawn test exposes a second test-driver limitation: a loose
12-cm required-waypoint radius lets the human approach cut into a door jamb.
Smaller collision margins and lower jump-arc probes do not fix it; those
experiments are not retained. A test-only planner instead centers required
traversal endpoints within 2 cm horizontally, retaining the actual floor-height
check and existing physical jump query. A new 3-cm boundary assertion then
catches the inherited bot steering code's 5-cm zero-velocity band. The planner
now keeps steering inside that band until its tighter endpoint is reached.
No production bot, player, hull, collision margin, door or navigation asset changes.

The final solo fixture passes twice with four player-credit use/follow events,
four player-credit rescues at hostage tick 8,730 / test tick 8,129, four use
commands, no shots and maximum per-tick displacement 0.070330 m. It tests
alignment/height, the approach band, freeze and death suppression, and actual
human world-use ownership. Attacks are blinded to isolate traversal; this is
not combat/GPU evidence. Logs include `/tmp/protocol47-driver-solo-final.log`
and `/tmp/protocol47-match-driver-solo.log`. The final ally-following traversal
also passes at tick 3,819 with the normal jump and maximum displacement
0.103178 m. The new solo fixture is mandatory in `game:test:match-driver`;
all 28 Node runner tests pass. The last full 23-suite gate below predates this
fixture/driver change. The expanded strict focused group passes at
`2026-09-08T12:28:10.394Z`: four markers, clean exit, no detected errors/leaks
(`game/artifacts/headless-test-selected-report.json`). Its normal-combat
24,000-tick run reaches round four with 24 local shots, maximum blockage
123 ticks, maximum unfinished-route idle streak 371 ticks, and maximum local
intra-round displacement 0.085346 m. Solo/use counts are zero in that short
combat sample; the separate solo fixture proves that path, not this sample.

The old normal-combat progress guard could accept an idle route because its
blocked counter advanced only when movement was requested. A pre-boundary-fix
snapshot demonstrates this at 24,000 ticks: zero movement and blocked ticks
while stopped 4.7 cm from the required endpoint. The probe now additionally
rejects more than 1,000 consecutive idle ticks with an unfinished local route,
excluding freeze/death and active fire, reload or use. It reports
`driver_max_idle_route_ticks`, plus solo-objective/use command counts. A fresh
silent full-match headless replay completes cleanly at
`2026-09-08T12:33:25.033Z` in
`/tmp/protocol47-assault-ct-solo-objective-full-match-cpu.json`: 17 rounds,
108,364 sampled ticks / kernel end 108,365, one halftime, T 16 / CT 1,
112 local shots, 6,686 effects, maximum local blockage 152 ticks, zero freeze
violations and no hostage-timeout round. Solo-objective/use counters are zero:
normal combat never needed that fallback in this replay; its coverage remains
the explicit four-rescue fixture. This process loaded before the transport
change above and overlaps correctness checks, so its timings do not establish
GPU or isolated CPU performance. Benchmark input changed; earlier full-match
timings are not a like-for-like performance comparison with this driver.

Full-match budget/settings follow-up (September 8): full-match probes now derive
their default/max tick budget from the running MR15 rules: 30 rounds times
freeze + round + full late-plant C4 + post-round + one transition tick. With
production defaults this is 1,068,030 ticks. No game rule or completion check
is weakened. The Node runner matches that bound and scales its wall deadline;
ten runner tests and the native incomplete-match negative control pass, including
a cross-check against the actual runtime configuration. A new normal-combat
Assault CT headless full match with the recovered driver passes at
`/tmp/protocol47-assault-ct-recovered-full-match-cpu.json` (report written
`2026-09-08T11:28:23.991Z`): 18 rounds, one halftime, a T 16 / CT 2 ending,
145,520 sampled physics ticks / kernel end tick 145,521, 100 local shots,
6,714 effects, zero freeze-control violations and maximum local blockage
184 ticks. It finishes inside the old 180,000-tick cap; the larger legal bound
is not what makes this attempt pass. Round 9 alone times out at tick 81,883;
the follow-up below identifies an idle benchmark-driver limitation. This process loaded
before the settings-path change and overlapped correctness/export work, so
its timing samples are not clean performance evidence. The full headless
gate started on the then-current 22-suite revision and passes at
`2026-09-08T11:27:34.055Z`: 93 markers and no detected errors/leaks. It includes
the new combat-driver regression and updated full-match negative control, but
started before the settings changes below. Neither is GPU timing.

The packaged-startup guard's GODOT_USER_DATA_DIR environment variable did not
isolate the macOS profile. The application now accepts an explicit absolute
`PROTOCOL47_SETTINGS_PATH` with an existing parent directory, rejects relative,
resource/user URI, directory, and missing-parent targets without falling back
to the installed profile, and keeps the default path unchanged when unset.
Fresh defaults and all input/video/audio/accessibility settings survive a
two-process save/reload test; the installed macOS profile remains byte-identical.
The invalid-path test initially replaced the autoload's exit 2 with its own
exit 1; the fixture now preserves the already-requested rejection.
The export guard requests and validates a fresh-storage startup confirmation,
so an old build ignoring the environment variable cannot pass. Six offline
guard tests and all 28 Node runner tests pass. The fresh validation export at
`game/builds/Protocol47-validation-20260908.zip` passes the packaged startup
guard with confirmed fresh settings and no detected startup errors/leaks.
It is 505,791,242 bytes, SHA-256
`fa979cef108834efd6e584fbdb4321c9c1a59aa7eb1bf0f84a5326965e910e97`.
The old `Protocol47.zip` remains unchanged. The export log at
`/tmp/protocol47-settings-export.log` contains no matched script/parse/engine
errors, warnings or leak markers.
Settings isolation is not isolation of every engine cache or packaged gameplay
completion. The new mandatory settings group brings future full gates to 23
suites; the completed 22-suite process started before these settings
changes, which pass their separate focused suite. Fresh full-suite coverage
of the settings/gameplay revision subsequently passes at
`2026-09-08T12:12:21.386Z`: all 23 suites, 96 pass markers, zero detected errors
or shutdown leaks, and all child exits zero. The 28 Node runner tests also
pass. Authoritative report: `game/artifacts/headless-test-report.json`. This
run overlaps only headless diagnostic work after the GPU controls finish;
its timings are not GPU or isolated CPU performance evidence. Both ten-fixture rendered correctness
gates pass again on the final settings revision (Compatibility and Metal/Mobile,
reports in `game/artifacts/render-test-*`), with no detected errors/leaks.
These are not timing runs.
The fresh muted, default-Compatibility Assault CT full-match GPU run completed
at `2026-09-08T11:54:29.826Z`, with no overlapping CPU-heavy checks:
`/tmp/protocol47-assault-ct-recovered-full-match-gl.json` and matching `.png`.
It exits cleanly with 255,422 intervals / 255,421 draws at 1280×720, 18 rounds,
100 local shots, and 6,714 effects. Round-end, halftime, match-end events and
all final actor positions exactly match the headless report. Median is 4.861 ms,
p95 10.604 ms, p99 13.312 ms, but maximum is 225.333 ms, with 48 frames over
33.333 ms and 11 over 50 ms. Four one-second windows exceed p95 16.7 ms;
16 exceed p99 25 ms. Many slow frames recur at roughly 3,011 physics ticks
(30.11 seconds), including quiet periods. Cause is not established. This
functional full-match pass does not clear smoothness; the periodic stalls and
the isolated 225 ms stall require investigation. The inspected capture shows
the completed match with the weapon and effects retained, not visual parity.

The standalone `scripts/render-baseline` control reproduces the periodic stall
without loading any game code, assets, autoloads, networking, or player settings.
The silent 95-second Compatibility run at
`/tmp/protocol47-render-baseline.json` collects 98,783 actual draws / intervals,
p95 2.102 ms and p99 3.649 ms. Its only three intervals above 25 ms occur at
22.495525, 52.606104, and 82.710954 seconds (37.514, 28.850, 25.354 ms), separated
by 30.110579 and 30.104850 seconds. No detected log errors/leaks. Game callbacks
are therefore not a necessary cause of this periodic hitch. This does not
identify engine versus driver/OS/other host activity, excuse the stalls, or
explain the separate 225 ms full-match outlier. No production behavior is
changed to hide the symptom.

The subsequent silent Metal/Mobile control also reproduces the cadence:
`/tmp/protocol47-render-baseline-metal.json`, 34,882 draws / intervals over
95 seconds, p95 8.026 ms, p99 10.073 ms, maximum 32.676 ms. Three slow intervals
land at 6.951665, 37.080862, and 67.193517 elapsed seconds, with one additional
25.660 ms interval at 72.542763 seconds. The first periodic Metal spike is
120.45849 wall-clock seconds after the first Compatibility spike—approximately
four periods—despite restarting the process and changing the backend. This
points toward a host-wide periodic disturbance, but does not identify its
owner. A two-second macOS `sample` capture spanning the next predicted spike
is saved at `/tmp/protocol47-render-hitch-sample.txt`. Its aggregated stacks
include presentation/WindowServer IPC waits, but are not per-frame timestamps
and cannot prove which stack caused the hitch. The associated `-traced.json`
control is instrumented diagnostic evidence, not a clean timing baseline.

The normal-combat Assault CT replay through tick 83,000 also completes cleanly:
`/tmp/protocol47-assault-round9-diagnostic.json`, 297.752 seconds wall time
overlapping headless correctness checks (not performance evidence). Round-nine
snapshots from tick 58,000 through 81,000 show the only remaining CT is the
local Player, alive at approximately (-6.6031, 3.3604, -25.5995), with zero
movement/use/fire commands, zero velocity and zero blocked ticks. The remaining
T, CT_Bot_02, holds its hostage guard position without sight of the player.
All four hostages remain alive; hostage_153 previously followed T_Bot_03 (a CT
actor despite its name) until that leader died. No follower remains stuck on
an active rescue route. Source inspection of `live_match_driver.gd` explains
the idle command: it moves only toward an alive ally's objective and has no
sole-survivor objective intent when no enemy is visible. This timeout is not
evidence of another production navigation deadlock. The benchmark driver still
needs independent objective/use intent and a sole-survivor regression before
full-match automation can claim that coverage; normal human input is unchanged.

Team-selection implementation (September 8): the reproduced reset path now
preserves the running match and unrelated actors. Kernel rules distinguish
enrollment, an unfinished appearance choice, and eligibility for a first spawn
in the current round. They enforce map spawn capacity, the default two-player
imbalance limit, dead-player repeat-change rejection, and the normal 20-second
live-round join window. Auto-assignment uses counts, then the losing score,
then a tie break; full-side fallback can return no available team. Accepted
normal team selection uses a local suicide/death/drop and frag penalty, including
same-team appearance changes. A last survivor's selection can legitimately end
the round; the tests do not mask that outcome. Observer entry retains its
separate alive/freeze rules and frag restoration.

HUD auto-assignment now reaches authority, accepts the resolved class family,
and keeps the team menu on rejection. M opens the live menu; 0/Escape cancels.
Menu input is local to the human controller, not a world pause. Deployment is
separate from starting a match, and repeated start requests are idempotent.
Live selection never invokes bot-side/reset logic. Spawn allocation and halftime
now follow each actor's authoritative side, retaining distinct slots after a
cross-team choice. A waiting participant regains body/collision/camera only at
an eligible spawn. An unfinished appearance menu still blocks a round-boundary
spawn. Initial lobby roster setup and explicit rematch remain separate paths.

The original diagnostic now exits cleanly with round 2 / T 1–0 / tick 3 retained,
one local death, the same dead opponent, and all eight surviving bots still
active (`/tmp/protocol47-team-selection-probe.json`; this file now holds the
after-change result). New rule checks and full menu fixtures pass headlessly on
both maps. The 17-marker rounds group passes; the observer and eight-case MR15
lifecycle/rematch groups pass after the observer fixture is corrected to finish
appearance before expecting a spawn. All 27 Node runner checks pass. The new
three-fixture `game:test:joins` group is mandatory, bringing the full headless
gate to 22 groups. The rendered gate now includes the menu fixture (ten total).
Both ten-fixture rendered gates pass before the final pending-appearance
follow-up (Compatibility `2026-09-08T10:53:25.333Z`, Metal/Mobile
`2026-09-08T10:54:03.096Z`); the live Compatibility menu capture was inspected.
A new reopen regression then catches returning an unfinished join to team
selection. M now resumes that pending class choice, and halftime refreshes its
authoritative class family. The extended fixture also holds appearance open
across the real halftime transition; its first draft set rounds_played but
omitted round_number, so never triggered halftime and correctly failed. After
correcting that setup, the full joins group passes on both maps. The initial
full headless attempt reaches this newly extended fixture and fails on the
same setup issue; no full-headless success is claimed for that attempt.
The corrected revision passes the complete 22-group headless gate at
`2026-09-08T11:02:35.695Z`, and both ten-fixture rendered gates at
`2026-09-08T11:03:31.418Z` (Compatibility) and
`2026-09-08T11:04:09.013Z` (Metal/Mobile), with no detected errors/leaks.
A subsequent actual-button regression exposes the mouse Cancel callback as
a no-op (it reopens the same menu). `/tmp/protocol47-cancel-before.log` fails
only that assertion. The callback now requests cancellation through game
authority, which closes a running menu but never bypasses initial deployment.
HUD keyboard cancellation uses the same request. The extended joins group
passes on both maps, and both maps' menu fixtures pass natively on both
backends. The six-marker HUD and three-marker observer groups also pass.
These focused passes follow the full gates above; those full gates
precede the small Cancel change. These changes do not implement remote-human
multiplayer or close the full-match,
visual/audio fidelity, packaging, signing and distribution requirements below.

Decal follow-up (September 8): the earlier full-match capture shows rectangular
dark backgrounds around persistent shot/blood marks. A new rendered fixture
reproduces a compositing error in the unchanged production material: replacing
its source texture with white still changes all 12,100 interior pixels at
ambient energy 0 and 0.25, for shot, blood and scorch. The completed baseline
run (`/tmp/protocol47-decal-before-gl.log`, exit 1) reports only these six
expected assertion failures; initial fixture enum/viewport-bound errors were
corrected before collecting that baseline. The inspected blood capture shows
the dark rectangle. Godot's [multiply blending and shading documentation](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)
explains why independently lighting a multiplicative mask can darken its white
surround before blending with an already-lit destination. The candidate is an
unshaded modulation material, not removal of the destination's lighting.
The navigation revision first passes the complete headless gate at
`2026-09-08T10:23:42.687Z`: 21 suites, 89 markers, no detected errors/leaks.
Both from-spawn rescue runs repeat four rescues at T 9,410 / CT 8,030 ticks,
and the local driver crosses at tick 2,730 with no teleport assertion failure.

After that completed gate, production decals switch to unshaded modulation.
Compatibility passes immediately, but Mobile still halves the mask's linear
RGB. This matches Godot 4.7's
[non-HDR Mobile buffer normalization](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp#L861).
The material now compensates that factor only for Mobile viewports without
HDR2D, expressing the linear factor through the material's sRGB color input.
No source pixels, stamp counts, geometry, filters or default renderer change.
The final fixture passes 18 cases on each backend (three families, three light
levels, HDR2D off/on): zero changed white-mask pixels, authored marks still
visible, and double-lit negative controls detected. Both non-HDR blood captures
were inspected; the rectangular dark background is gone. Logs:
`/tmp/protocol47-decal-final-{gl,metal}.log`. The focused headless VFX group
also passes after this change. The nine-fixture rendered gate now includes
this pixel contract. The first complete Compatibility attempt reaches the
observer fixture's pass marker but is correctly rejected for 14 leaked objects
and four resources at shutdown. Verbose repeats identify ten
AudioStreamPlaybackWAV objects and four death WAVs, not decal materials; one
unchanged repeat exits cleanly, so a clean retry alone is not a fix. A trial
Game pre-delete stop hook also produces three clean repeats but then fails
the larger rerun and new weak-reference checks; it has been removed. Trace
evidence confirms stop calls happen, while the supposed 200 ms teardown timer
actually waits only 5.895/5.958 ms after the long cleanup frame. This is not
evidence that the existing adapter cleanup needs replacing. The observer
fixture now waits for actual playback ownership release using a monotonic
two-second deadline and retains strict leak/error rejection. Its nominal
SceneTreeTimer no longer determines whether the mixer has drained. The
unchanged production audio cleanup passes three focused Compatibility repeats:
all ten playback objects release, taking 1.995, 1.857 and 25.374 ms respectively.
The complete nine-fixture rendered gates then pass with no detected errors/leaks:
Compatibility at `2026-09-08T10:37:43.889Z`, Metal/Mobile at
`2026-09-08T10:38:14.238Z`. Reports are under `game/artifacts/render-test-*`.
Pixel correctness is not original-engine visual parity.

Two muted, uninstrumented Compatibility GPU volley runs now pass with all
1,500 draws, 6,593 effect events, no render exclusions and the 1280x720 viewport:
`/tmp/protocol47-volley-decal-fix-gl.json` and
`/tmp/protocol47-volley-decal-fix-repeat-gl.json`. Repeated-fire p95 is
14.102 / 14.116 ms, p99 15.321 / 15.028 ms, versus the preceding source-bounds
runs' p95 17.458 / 17.156 ms. Cold-fire p95 is 13.647 / 13.469 ms; the complete
switch-and-fire first interval is 18.786 / 16.995 ms. No sampled interval
exceeds 33.333 ms. The first smoke capture was inspected: smoke and weapon
presentation remain visible. This establishes repeatable improvement in the
stationary synchronized-volley scenario, not full-match clearance. The fixture
disables AI/movement; the full smoothness and release requirements remain open.
A fresh normal-combat Assault CT full headless match is running after the
navigation/decal changes; it is not a GPU timing run. That attempt subsequently
exits 1 after reaching the unchanged 180,000-tick limit, in round 14 with 13
completed rounds and CT 9 / T 4. It has 36 local USP shots, 4,322 effect events,
652.636 m of local travel and zero freeze-control violations, but no halftime
or match-end event. Four rounds end in hostage-rescue timeouts. The strict
runner reports only the expected missing-completion failure and fail marker,
not runtime/leak errors. Report:
`/tmp/protocol47-assault-ct-nav-decal-full-match-cpu.json` (721.966 s).
It loaded before the team-menu changes and is not current-revision or GPU
clearance. A 30-minute simulation cap cannot cover every legal 30-round match
with five-minute rounds; longer bounded completion coverage and the actual
normal-combat rescue timeouts still require investigation. Do not relabel this
incomplete attempt as a passing full match.

A current-revision normal-combat CT diagnostic reproduces round 1/2 wins at
the same ticks (6,827 / 13,484), then captures the third round through tick
44,000: `/tmp/protocol47-ct-round3-rescue-probe.json`, strict clean exit in
188.454 s. All four hostages remain alive; hostage 153 starts following at
hostage tick 4,144 and stops at 4,198 because its leader dies. This is not a
hostage-following stall. The remaining three CT bots repeatedly collide at
the warehouse entrance: T_Bot_02 stays at (6.2407, 0.0024, -21.7999), with
the local Player blocking its forward motion and world geometry behind it.
The test driver uses routing and jump attempts but omitted the production
controller's physical sidestep/backoff recovery. It now also translates that
recovery into normal local movement input; player positions, physics, health,
weapons and bot behavior are unchanged. Diagnostic snapshots now include local
movement/route/shot state and blocked duration. The first recovery candidate
finishes three normal-combat CT rounds by tick 22,526 and limits its longest
blocked streak to 92 ticks (`/tmp/protocol47-ct-driver-avoidance-probe.json`),
but fails the existing isolated warehouse-jump fixture: its 20-tick sidestep
threshold preempts the local 25-tick jump attempt. This candidate is rejected.
Recovery now waits for a sustained 75-tick local jam before using the bot's
bounded recovery, while already-running backoff/door waits finish normally.
The unchanged traversal fixture passes at tick 4,130, with 14 jump frames and
maximum physical displacement 0.1032 m; the full-match negative control still
rejects incomplete matches. The adjusted driver completes three normal-combat
rounds by tick 20,183 (CT wins at 5,779 / 12,896, T wins at 20,183), reaches
30 local shots and has a maximum blocked streak of 184 ticks during 24,000
ticks (`/tmp/protocol47-ct-driver-recovery-probe.json`, clean 106.558 s).
The complete bot group also passes; its normal T-side door regression retains
entry tick 4,681, maximum wait 456 ticks and maximum displacement 0.1680 m.
The match-driver group now adds a 24,000-tick normal-combat CT regression:
it requires actual recovery commands and local shots, rejects continuous
local blockage over 1,000 ticks, and verifies physical moves below 0.25 m
excluding normal round spawns. The expanded three-marker match-driver group
passes the strict runner at `2026-09-08T11:17:50.502Z`, in 128.354 s with no
detected errors/leaks. The combat regression repeats the same three round
end ticks, 30 local shots and maximum 184-tick blockage, records 840 recovery
input ticks, and limits intra-round displacement to 0.0676 m. Evidence:
`/tmp/protocol47-driver-progress-regression.json` and
`game/artifacts/headless-test-selected-report.json`. All 27 Node runner checks
also pass. The earlier full 22-group gate precedes these driver changes;
full-suite and full-match/GPU revalidation remain required. These are
local-driver progress checks, not a completed
MR15 match, hostage-rescue guarantee, or GPU performance result.

Team-menu lifecycle audit (September 8): a fresh headless diagnostic exercises
the actual HUD team/class signal path during round 2, with a 1–0 T lead and
one dead CT. Selecting the current T team immediately revives the dead bot
and deactivates all nine bots; choosing class 3 then resets the kernel to tick
0, round 1, score 0–0 and freeze. The local player incurs no death. Evidence:
`/tmp/protocol47-team-selection-probe.gd` and matching `.json`, strict exit 0
in 2.419 s after correcting an invalid cleanup call in the first probe attempt.
The pass marker means diagnostic collection, not correct team behavior.
This confirms `_on_team_selected`'s unconditional actor resets and the
`deploy_requested -> start_match` wiring as separate live-join defects.
The inspected [ReGameDLL team/appearance handlers](https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/client.cpp#L1568)
do not restart the match on appearance selection; an accepted team selection
uses the local player's death path, even for same-team appearance changes.
Capacity/balance checks, once-per-round changes, initial/observer joining and
normal respawn eligibility must be preserved when fixing this path. No
production menu behavior was changed in this diagnostic turn.

Latest packaging guard work (September 8): the existing macOS preset/template
and export command are present; release packaging does not need scaffolding
from scratch. The smoke runner now explicitly uses Dummy audio and rejects
generic engine errors, failure markers and ObjectDB leak warnings in addition
to its prior narrow resource/script checks. Four offline regression checks
pass and run before `game:build:mac`; the exporter is explicitly muted too.
No new export or packaged game was launched during the GPU benchmark. The
existing `game/builds/Protocol47.zip` is dated July 26 and is not evidence for
the current revision. This remains a startup-only probe without a gameplay
completion handshake; clean-install user-data isolation, packaged matches,
fresh export verification and distribution approval remain unverified.
User-data isolation audit: the installed `godot --help` exposes no
`--user-data-dir` option. The inspected upstream
[OS user-data resolution](https://github.com/godotengine/godot/blob/master/core/os/os.cpp)
uses project configuration, and
[macOS data paths](https://github.com/godotengine/godot/blob/master/platform/macos/os_macos.mm)
derive from the home directory; neither inspected path honors the smoke
runner's `GODOT_USER_DATA_DIR`. GameSettings still loads/saves
`user://protocol47.cfg` unconditionally. An installed-engine probe now confirms
the environment assignment is ignored: a minimal project with the same
application name resolves the normal Protocol 47 user-data directory instead
of `/tmp/protocol47-userdata-probe.Um2VmU/userdata`. Evidence:
`/tmp/protocol47-userdata-probe.Um2VmU/run.log` (exit 0). The probe has no
autoloads and does not read/write game settings. Packaged-runtime isolation
remains unverified; do not claim isolation from the temporary directory or
environment assignment, and do not repurpose HOME as a workaround.

Latest live-match coverage work (September 8): `--live-match --full-match` removes
the short probe's granted AK and initial-freeze bypass, allows a bounded
300–180,000 physics-tick budget (default 180,000), and exits when the real match
concludes. The runner's wall deadline scales to the requested duration rather
than terminating every run after three minutes. A passing full attempt requires
local firing, exactly one halftime/end event and an MR15 score consistent with
the completed-round trace. Reaching the tick limit without that evidence fails;
render exclusions and render-frame limits are rejected. Reports record actual
starting inventory/phase and whether completion was verified. Process static
memory includes retained fixture samples, so it is not an isolated game-memory
measurement.

The new bounded negative control is included in `game:test:match-driver`. Its
real three-second headless run confirms the normal USP/freeze, zero freeze-control
violations, intact effects configuration, explicit GPU-false metadata, and the
expected missing-match/missing-combat failure. Its wrapper accepts only those
expected errors and fails on unrelated runtime errors. All 25 Node runner tests
pass. The first full Assault CT headless attempt now exits cleanly with the
strict completion marker: `/tmp/protocol47-assault-ct-full-match-cpu.json`.
It completes 18 rounds in 158,292 physics ticks (26.382 simulated minutes),
with exactly one halftime and one match-end event, final side scores CT 2 / T 16,
and a verified MR15 trace. The local player starts CT with only knife/USP and
normal freeze, switches sides at halftime, and records 75 USP/Glock shots and
941.965 m of non-teleport travel. All ten actors travel, 6,048 effects occur,
and 6,479 freeze observations contain zero control violations. The runner exits
0 with no detected runtime/leak errors. Round endings comprise 15 CT elimination
wins, one T elimination win and two hostage timeouts; this is not successful
rescue coverage. Static memory rises from 383,304,292 to 488,324,408 bytes,
including 94,976 retained frame samples and other fixture data; this is not
isolated game-memory or GPU smoothness evidence.

Rescue-timeout follow-up: the final headless round's retained hostage trace
records CT_Bot_04 recruiting hostage_154 at round tick 3,770, then damaging it
at 3,977 and 3,985 and killing it at 3,993. Three other hostages finish alive,
unrescued and never used. This is evidence of escort collateral damage, not
proof of why all other rescue tasks stopped progressing. The assignment
refresh explicitly removes dead/rescued hostages from eligibility, and the
reported CT_Bot_01/03 route targets still point toward surviving hostages;
simply clearing a dead-hostage assignment is not an established fix. Final
bot idle/zero-velocity readings are taken in intermission, where the game
intentionally disables actors, so they cannot diagnose a live navigation
stall. Follow up with a pre-timeout snapshot/reproduction including live
commands, enemy perception, ammo, hull blockers and objective assignments,
without turning off combat or bypassing the actual movement path.

The new muted `hostage_combat_probe.gd` captures pre-timeout bot commands,
ammo, perception, assignments, route points, motion-probe blockers and brush
states without disabling combat or granting equipment. Its normal T start
(knife/Glock, real freeze) reproduces a live-round stall in 12,000 ticks:
`/tmp/protocol47-hostage-combat-probe.json` (46.523 s, strict clean exit).
A detailed 10,000-tick repeat also exits cleanly:
`/tmp/protocol47-hostage-combat-detail.json` (39.940 s). These markers mean
diagnostic collection completed, not that gameplay or performance passed.
From ticks 5,999 through 11,999, surviving CT_Bot_05 remains near the Assault
entrance with USP clip 12 / reserve 100, no visible enemy and a live hostage_154
assignment. It repeatedly attempts the route while oscillating around
x 6.45–6.95 / z -22.14–-21.90. Detailed snapshots identify rotating-door entity
11 as the blocker while its state is open. The next required route point is
(6.44, 0.36, -23.00), beyond that rotated leaf. World collision also blocks
some escape directions. This rejects ammo exhaustion and a dead assignment
as explanations for this reproduction. It is a new normal-T-start reproduction,
not yet an exact replay of the full match's late-round state.

Bounded door-wait follow-up: after sustained world obstruction, bots now probe
their actual hull for a rotating leaf with a scheduled return. They may pause
movement until its normal closing cycle finishes, capped at 600 fixed ticks;
firing, aiming and reload commands remain intact. Permanent, start-open and
overlong-return doors retain the existing escape path. Tactics reset cancels
the wait. Door solidity, the normal jump impulse, combat and spawn paths are
unchanged. The focused unit fixture verifies duration calculation, exclusions,
deadline expiry, reset and preserved combat commands.

The normal-T-start 10,000-tick entrance assertion fails on the baseline
(`/tmp/protocol47-door-progress-before.json`, no crossing) and passes after
the change (`/tmp/protocol47-door-progress-after.json`, CT_Bot_05 crosses at
tick 4,681). Maximum round-one per-tick displacement is unchanged at
0.168033 m. The integrated repeat adds all-bot wait counters and passes:
`/tmp/protocol47-door-progress-regression.json`, maximum consecutive wait
456 ticks. CT_Bot_01–04 wait; CT_Bot_05 itself does not, so altered doorway
traffic is part of this result. This proves the reproduced entrance progress,
not a rescue or resolution of the original late-round timeout. Both fixtures
are now required in `game:test:bots`; all 26 Node runner checks pass. The full
headless gate rejects this revision at `game:test:assault-traversal`: the T
selection rescues all four in 11,190 ticks, but CT reaches only one rescue
within the unchanged 18,000-tick deadline. Two following hostages remain at
the warehouse entrance while their leaders are near rescue; a third has
stopped following elsewhere. Earlier bot/hostage frame-rate determinism checks
pass, but that is not sufficient. The door-wait change is provisional until
this regression is resolved; rendered/performance revalidation is on hold.

The detailed replay (`/tmp/protocol47-door-wait-ct-rescue-detail.log`, expected
exit 1) identifies route-refresh oscillation for hostages 153/154: while partway
through the authored entrance link, each 25-tick re-query points them back to
its entry. Per-tick motion prevents the existing stuck-release timer from
recognizing the lack of net progress. The route code now consumes reached
points before considering a refresh and retains an active, enabled authored
link's exit until arrival; ordinary segments still refresh normally. It does
not move actors, bypass hull collision, or alter follow speed/door state.
The focused integration test first fails in both directions for timer and
moved-leader refreshes, then passes with the change. An additional negative
control catches failure to resume refresh when the link is the final segment;
that endpoint case is now fixed too. Tests also cover disabled/one-way links
and ordinary segments.

The initial physical rerun passes all four rescues for both selections:
T at 9,410 ticks, CT at 8,030, maximum per-tick displacements 0.168033 m and
0.167549 m respectively. These two processes loaded before the final-endpoint
guard was added; the final revision still needs the full gate. The selected
three-suite run now exits 0 (18 markers): physical traversal, hostage
determinism and all bot tests. On the final endpoint-guard revision, the
combat-enabled entrance repeats tick 4,681 / maximum wait 456 and hostage
determinism remains exact at 30/240 frame rates. The complete focused hostage
integration fixture passes cleanly in 2.678 s, including endpoint and
disabled/one-way/ordinary-segment cases. All 26 Node checks pass. The subsequent
full navigation-revision gate passes at 10:23:42 UTC (21 suites / 89 markers);
see the latest decal follow-up above for later material changes. Full-match
rescue, broader rendered correctness and GPU frame-time revalidation remain open.
Standalone command:
`godot --headless --fixed-fps 60 --audio-driver Dummy --path game --script res://tests/hostage_combat_probe.gd`.
Optional `-- --team=CT --ticks=140000 --report=/tmp/protocol47-hostage-history.json`
retains the longer normal match history for the separate late-round investigation.

The matching muted native Compatibility full match now exits 0 with the strict
completion marker and no detected runtime/leak errors. Report:
`/tmp/protocol47-assault-ct-full-match-gl.json`; inspected capture: matching `.png`.
At 1280x720 it records 337,987 measured intervals / 337,986 actual draws,
158,291 measured physics ticks, 18 completed rounds and verified MR15 completion.
The kernel's round, halftime and match-end traces exactly match the headless
run, ending at kernel tick 158,292 with CT 2 / T 16. It preserves normal
knife/USP starting equipment/freeze, records 75 USP/Glock shots and 6,048 effects,
and has zero control violations across 13,886 freeze observations. Effects are
intact and instrumentation is off. No other running game or CPU-heavy test
overlapped; four offline packaging-guard checks and an engine help query ran
during measurement. This was not an otherwise controlled idle-host run.

Overall p95 is 9.799 ms / p99 11.148 ms, but six intervals exceed 33.333 ms
and five exceed 50 ms; maximum is 73.980 ms. The slow intervals occur at
measured ticks 8,293 (59.764 ms), 34,123 (65.200), 34,201 (60.485), 64,220
(60.606), 94,207 (39.996) and 134,618 (73.980). Of 1,583 one-second windows,
two exceed p95 16.7 ms and six exceed p99 25 ms. Worst window p95 is 24.544 ms
at ticks 64,100–64,199, immediately before another 60.606 ms interval. Some
slow windows contain new effects, others do not; this correlation does not
establish a combat or external-process cause. The long quiet tail must not
hide these outliers behind the overall percentiles. Smoothness remains open.
Loading is 9,048.777 ms, separate from live samples. Static memory rises from
874,369,341 to 948,865,765 bytes including retained fixture data, not an isolated
game-memory measurement. The capture confirms the match-end/rematch prompt and
spectator view, but also shows conspicuous rectangular impact-decal backgrounds
that need visual fidelity review. Both maps, both initial team selections,
rematches and the remaining release gates still need coverage; this one full
match does not satisfy the overall release checklist.

Latest camera-audio fix (September 8): the game's distance-attenuation listener
now follows the viewport's active camera rather than always using PlayerCamera.
A silent before-change integration probe reproduced 140.795 HU error during
deployment, 208.758/304.032 HU in death/cycled chase, and 509.902 HU with a
deliberately separated alternate camera. Existing-voice distance and gain were
also wrong; first-person and respawn were correct. The new fixture covers eight
view states, including intentional/no-target observation, and is included for
both maps in the existing audio group. After the fix all listener errors are
zero and an existing sound 50 HU from the view receives the expected gain.
The focused audio/observer rerun passes all nine markers; 24 Node runner checks
pass. This is attenuation-state evidence, not PCM/panning fidelity or a GPU
benchmark. The prior full animation-revision gate passed all 21 groups and 84
markers at 09:09:58 UTC, before this subsequent audio change.
The camera-audio fixture also exits cleanly for both maps on native Compatibility
and Metal/Mobile: all eight viewpoint checks per case report zero listener error
and correct existing-voice gain. Logs are
`/tmp/protocol47-camera-audio-{gl_compatibility,mobile}-{de_dust2,cs_assault}.log`.
All four launches use the Dummy driver and disabled device playback; they are
native integration checks, not frame-time measurements or audible comparisons.

Latest animation optimization (September 8): character templates now retain
finite per-source-pose bounds, computed during template loading. Normal character
animation derives conservative bounds from the same frame/pitch weights and
encloses both body/gait layers, removing the full-vertex culling-bound scan from
each rendered pose. Geometry, animation clocks and interpolation are unchanged.
The boxes may be larger than the exact pose bounds; they cannot intentionally
exclude animated vertices. A 0.00001 m margin covers extrema rounding. Direct
custom renderer callers retain exact scanned bounds. Grounding uses cached
minimum Y only for an unblended source frame; interpolation still uses the exact
vertex-wise minimum, not interpolation of endpoint minima.

The six-fixture character group passes after the grounding fast path, including
2,431 exact grounding comparisons. Extended sampler checks exercise 14,295
samples / 9,371,926 vertices / 38 templates and check enclosure across frame,
pitch and body/gait combinations. Source-position error remains at most
0.000000111511 m. The isolated 200-query culling calculation is 84 us versus
9,793 us for the previous vertex scan (another run: 86 / 10,121 us). These are
component timings, not GPU results. All 23 Node runner checks pass.

All eight rendered checks pass on both backends with the final production code:
Compatibility finished 09:02:23 UTC and Metal/Mobile 09:02:51 UTC. Optimized
body, weapon, hostage, shadow and reload pixel comparisons retain zero reference
mismatches, with functioning stale-pose negative controls. The first muted,
uninstrumented Compatibility volley run (`/tmp/protocol47-volley-source-bounds-gl.json`
and inspected `.png`) draws all 1,500 intervals with 6,593 effects. Repeated-fire
p95 is 17.458 ms / p99 19.793 ms, versus the recent baseline 18.680 / 19.857 ms;
initial p95 is 17.495 ms and cold-phase p95 18.116 ms. The complete switch interval
is 23.018 ms, smoke p95 9.275 ms, and no frame exceeds 33 ms. Loading is
8,734.090 ms versus baseline 7,355.971 ms; static memory is 931,022,162 bytes
versus 928,818,399 bytes. The finite bounds cache trades some loading work and
memory for cheaper pose updates. This does not yet pass sustained-volley p95
or the overall release gate.

A separate repeat (`/tmp/protocol47-volley-source-bounds-repeat-gl.json`, matching
capture) records repeated p95 17.156 ms / p99 19.130 ms, initial p95 16.762 ms,
cold p95 16.929 ms, complete switch interval 22.055 ms, and smoke p95 9.201 ms.
Again all 1,500 draws and 6,593 effects are present, with no interval above 33 ms.
Loading is 8,679.025 ms and static memory 931,021,066 bytes. The repeated-volley
reduction appears in both new runs, but neither satisfies the p95 target. The
full twenty-one-group regression rerun after these GPU runs passed with 84
markers at 09:09:58 UTC, before the subsequent camera-audio change above.

Latest sustained-volley audit (September 8): a new silent, draw-verified default
Compatibility baseline still misses the target: repeated p95 18.680 ms,
p99 19.857 ms, shot CPU p95 4.794 ms, cold-phase p95 18.107 ms, complete
switch interval 23.947 ms. Artifact: `/tmp/protocol47-volley-light-audit-before.json`.
A bounded muzzle-light reuse experiment preserved independent simultaneous
lights, exact fixed-tick decay, illumination settings, expiration visibility,
overflow cleanup and scene teardown; its focused headless and native-rendered
checks passed. However, `/tmp/protocol47-volley-light-pool-after.json` records
repeated p95 18.213 ms / p99 20.241 ms / shot CPU p95 4.795 ms and cold p95
18.219 ms. Both runs drew all 1,500 samples with 6,593 effects and zero frames
above 33 ms. The small percentile difference is within previously observed
run-to-run variation and does not prove a useful improvement. The experimental
pool and its pool-specific test were removed; production light behavior is
unchanged. Do not repeat light-node pooling as an established fix or treat the
benchmark completion marker as proof that frame-time targets pass.

Latest benchmark-coverage work (September 8): the live local-input driver now
uses the production hull-clear route and ordinary mouse/movement/jump commands.
It shares a living teammate's objective instead of stopping beside that teammate
at the warehouse doorway. No production movement or combat rules were changed.
The new `game:test:match-driver` is included in the twenty-one-group headless gate;
its focused run passes from the normal Assault CT spawn after normal freeze,
entering at tick 4,217 with 14 jump-impulse frames and maximum per-tick displacement
0.051511 m. Attacks/perception are disabled only in that traversal regression.
The expanded full gate has not yet been rerun. All 23 Node runner checks pass.

The combat-enabled 12,000-tick headless probe records local shots, two CT round
wins, two driver jump commands, and no freeze-control violations. Its artifact
is `/tmp/protocol47-assault-ct-objective-driver-cpu.json`; these CPU-only results
do not establish GPU smoothness. An earlier driver revision passed traversal but
still produced zero local shots when its surviving teammate blocked the doorway;
that result is not accepted as shooting coverage. Combat benchmarks can now use
`--require-local-combat`, which fails explicitly when no local shots are recorded.
A 300-tick negative-control run confirmed exit 1 and the expected missing-combat
error (`/tmp/protocol47-driver-no-combat-negative.json`).

The corresponding silent Metal/Mobile 1280×720 GPU sample exits cleanly with
41,199 measured intervals / 41,198 actual draws, 25 local AK shots, 899 effect
events, two CT elimination wins, and 12,000 physics ticks. Frame times are
p95 7.025 ms, p99 8.337 ms, maximum 27.062 ms, with zero frames above 33 ms;
the worst one-second window has p95 9.540 ms. Loading is 4,368.440 ms and static
memory grows from 888,968,490 to 910,975,409 bytes. Report/capture:
`/tmp/protocol47-assault-ct-objective-driver-metal.json` / `.png`; the final image
was inspected. Effects are intact and no other test jobs overlapped the GPU run.
macOS indexing/media-analysis and user-app activity were observed, so this is
not a controlled idle-host benchmark or a like-for-like improvement claim.
It proves sampled moving-combat coverage, not a full match, physical rescues,
all weapons, or release readiness. Compatibility remains the project default.

The default Compatibility run of the same scenario also exits cleanly:
22,282 intervals / 22,281 actual draws, the same 25 local shots, 899 effects,
two round wins and final actor positions. Its p95 is 10.056 ms, p99 11.174 ms,
maximum 27.470 ms, with zero frames above 33 ms. The worst one-second p95 is
14.121 ms (ticks 7,000–7,099, ten to nine living actors). Loading is 7,616.575 ms;
static memory grows from 872,362,710 to 886,908,590 bytes. Report/capture:
`/tmp/protocol47-assault-ct-objective-driver-gl.json` / `.png`; final capture
inspected. The same environmental/coverage limitations apply. These moving
samples meet the provisional percentile targets but do not resolve the prior
Compatibility synchronized-volley p95 failure or establish a full-match soak.

Latest lifecycle verification: the nineteen-group gate passed on September 8 at
08:21:49 UTC after the halftime/rematch equipment, actor, HUD, radio-input, and
blindness fixes. Both seven-fixture rendered gates also exited cleanly, finishing
at 08:17:27 UTC (Compatibility) and 08:17:45 UTC (Metal/Mobile).
Subsequent observer work expands the gate to twenty groups and eight rendered
fixtures. Both expanded rendered gates passed at 08:26:41 UTC (Compatibility)
and 08:27:06 UTC (Metal/Mobile); the twenty-group headless run passed with 83
markers at 08:31:19 UTC. A subsequent source-rule correction restricts spectator
entry while alive and fixes freeze-time death/account semantics. Its twenty-group
rerun passed with 83 markers at 08:37:17 UTC. That run overlapped subsequent HUD
work and is not a final-code full-gate claim. The final spectator-HUD changes
pass the dedicated HUD/observer/match rerun (17 markers, 08:37:15 UTC) and all
eight rendered checks on both backends (Compatibility 08:37:12 UTC, Metal/Mobile
08:37:37 UTC). Inspected captures confirm on-screen, non-overlapping spectator
identity and no inactive local combat widgets. No new GPU timing was measured.

Current verification note: the default headless gate includes an eighteenth
group for physical Assault rescue from normal spawns, with both player-team
selections. Both selections now complete all four rescues. The complete
eighteen-group rerun passed with 72 completion markers and no detected errors
or leaks on September 8 at 07:38:32 UTC, including the hostage pose-submission,
exact grounding, fused vector pose sampler and initial weapon-pose preparation.
The vector pose sampler also passes
focused correctness, determinism and five rendered fixtures. Its clean Assault
CT GPU result is p95 10.740 ms / p99 13.075 ms, with no frames above 33 ms;
the synchronized-volley stress scene still misses p95. A subsequent fused-layer
sampler passes focused correctness and all five rendered checks, but its clean
volley p95 remains above target. First-pose weapon preparation subsequently
reduces the measured cold-switch interval from 33.456 to 23.331/23.269 ms in
two clean runs, while heavy volleys still measure p95 18.558/19.085 ms. The
post-fusion/preparation full regression rerun passed. These are not
full release-readiness proofs.
An updated native Metal/Mobile probe meets stationary frame-time targets
(repeated-volley p95 14.058 ms). Its BSP material color-space mismatch is now
corrected without changing the tested Compatibility output. Both backends pass
six rendered fixtures, including 26 color cases. One prior effects-fixture
shutdown timeout remains unexplained; a newly isolated Godot-cache run exits
cleanly, but does not prove the intermittent issue fixed. Post-change stationary
Metal still meets its target (repeated-volley p95 14.439 ms); Compatibility is
18.789 ms. The post-change Metal Dust2 CT run covers 12,000 ticks, one completed
round and part of the next, with all one-second windows below target and no
frames above 33 ms. Broader backend fidelity and full-match coverage remain
required. Compatibility remains the default.

## Release requirements

- [ ] Smooth gameplay: rendered 5v5 firefights, movement, cold weapon switches,
  grenades, smoke, and full-match soaks on target hardware. Provisional target:
  60 FPS at 1280×720, p95 frame time ≤16.7 ms, p99 ≤25 ms, no recurrent
  combat-triggered frames above 50 ms. Loading must be separated from live play.
  Headless CPU tests alone do not satisfy this gate.
- [ ] Combat fidelity: correct per-weapon timing, spread/recoil, hitboxes,
  armor, penetration, mode changes, and consistent human/bot behavior.
  Off-screen animation skipping must also preserve any shadows visible to the
  player; camera-frustum checks alone do not establish shadow correctness.
- [ ] Complete matches: both teams on Dust2; buying, objectives,
  deaths, spectating, round transitions, match ending, rematch, and settings.
- [ ] Multiplayer: authoritative remote-human actors, input ownership,
  prediction/reconciliation, joining/leaving, loss/latency behavior, and abuse
  bounds. Existing ENet transport is not a completed multiplayer game.
- [ ] Stable operation: bounded presentation/debug memory, deterministic
  simulation, no script/resource errors, repeatable headless CI, and long soaks.
- [ ] Release artifact: reproducible macOS export, packaged smoke tests,
  clean-install validation, versioning, crash diagnostics, and release notes.
- [ ] Distribution: approved asset redistribution route and, for public Mac
  distribution, signing/notarization credentials. Neither rights nor credentials
  may be assumed from the presence of local assets.

## Evidence and open findings

- The complete 17-group strict headless gate passed again on September 8 after
  weapon/bot-template preparation, viewmodel residency, indexed navigation,
  shadow-aware animation, entry-view/C4 warmup, actor-model reuse/reload, and
  round-freeze fixes, the Jolt/initial-overlap/contact-separation changes, and
  camera-aware hostage pose submission/skin reuse:
  67 completion
  markers, zero detected errors or leaks. This includes the 12,305-event diagnostic-history regression,
  1,000 collision-query comparisons per map, objectives, and exact 30/240 FPS
  bot determinism. Report: `game/artifacts/headless-test-report.json` (finished
  `2026-09-08T05:47:58.917Z`). This is correctness evidence, not GPU evidence.
- Historical windowed measurements on M1 Max / Compatibility / 1280×720 reproduced
  repeated-volley p95 at 279 ms and cold-switch volley p95 at 396 ms.
- The interrupted updated rendered run still had repeated-volley p95 at 254 ms.
  Texture and mesh-allocation changes alone did **not** resolve the stall.
- Native sampling then identified repeated OpenGL shader compilation. Retaining
  one effect material per render-state variant removed the recurring compile
  spikes. Matching warmup to the live environment and retaining decal source
  textures further reduced measured overhead. **These historical timings are
  not accepted GPU evidence:** the new draw-count guard proved macOS can stop
  rendering a covered window while simulation and the benchmark continue.
  Reruns must keep the benchmark visible and verify every sampled render frame.
  These are also stationary diagnostic scenes, not full moving-match evidence.
- The first draw-count-verified run (`/tmp/protocol47-visible-gpu.json`) rendered
  every sampled frame: repeated-firefight p95 22.5 ms, p99 24.3 ms, max 31.8 ms;
  first volley 47.2 ms; cold weapon switch CPU 60.5 ms. This still fails the
  smoothness target. Its screenshot confirmed the live M4 and changed camera
  view. The subsequent ground-smoke run (`/tmp/protocol47-ground-smoke.json`)
  again verified every draw: repeated-firefight p95 23.3 ms, max 26.2 ms,
  weapon-switch CPU 57.3 ms. The screenshot shows visible ground-level smoke;
  smoke opacity/source fidelity still needs validation. All phases shut down
  cleanly, and retained VFX events plateaued at 4,096 while total reached 6,593.
- Restored three missing manifest entries (wall puffs, smoke grenade puffs,
  C4 smoke), made missing sprites fail loudly, and added reproducible VFX export
  validation. Older smoke-stage measurements did not prove visible smoke load.
- Added strict zero-exit script-error/leak detection, assertion-marker checks,
  and timeouts for correctness and performance commands. Selected-suite reports
  no longer overwrite full-suite reports.
- Audio/VFX diagnostic histories now use fixed-capacity 4,096-entry rings with
  constant-time recording. Live audio signals and voice lifecycle are unaffected;
  VFX also exposes the total emitted count separately from retained history.
- Weapon-load phase profiling identified cold animation I/O and texgamma work.
  Preparing all 29 first-/third-person weapon assets before deployment reduced
  the draw-verified M4 switch from 57.3 ms to 17.6 ms in
  `/tmp/protocol47-resident-weapons.json`. Loading was 5.55 s and static memory
  655 MB. Sustained-fire p95 was still 22.6 ms; this does not satisfy smoothness.
- Added a live-match fixture with normal physics, bot AI, damage, ammo, and round
  logic, plus an automated local controller. The first draw-verified 1,800-frame
  run (`/tmp/protocol47-live-gpu.json`) found a 2.72 s first-live pause and later
  330 ms pauses. All ten actors traveled at least 20 m, with 257 effect events.
  The driver's own maximum CPU cost was below 1 ms in a separate CPU probe.
- Profiling traced the pauses to quadratic fallback-route compaction: one bot
  performed 938 long hull sweeps in one tick. Forward route simplification now
  uses a linear number of full hull sweeps; the first-live CPU pause fell to
  228 ms and later 300 ms pauses disappeared in the probe. Routes can change;
  objective/determinism checks passed. A proposed ray
  rejection optimization was removed after a sloped-geometry parity failure.
  No ray approximation remains in navigation clearance.
- The updated draw-verified live run (`/tmp/protocol47-live-linear-gpu.json`)
  rendered all 1,800 frames with ten moving actors and 217 combat effects.
  p95 was 19.7 ms, p99 22.3 ms; only three frames exceeded 33 ms (103/162 ms
  on entry to live play, then one 60 ms frame). The earlier 2.7 s and recurring
  330 ms route stalls were absent. Static memory was ~688 MB at start and end.
  Loading was 5.61 s. The 16.7 ms p95 target and hitch-free live entry remain unmet;
  this is not a full match, repeated-run distribution, or long-soak proof.
- Verbose shutdown diagnostics identified WAV playbacks awaiting the audio mixing
  thread, not leaked effect shaders. Allowing that thread to drain after scene
  teardown produced clean benchmark shutdowns. Other teardown paths still need
  release verification.
- Offscreen pose skipping is now shadow-aware: directional swept-sphere/frustum
  checks, conservative positional-light ranges, same-world filtering, and shadow
  caster masks. A scene-tree light registry tracks additions/removals without
  per-frame BSP hierarchy scans. Headless checks cover clocks, visible/hidden and
  removed lights, masks, attached shadow-only weapons, and staging worlds.
- The separate silent `npm run game:test:rendered` gate verifies actual shadow
  pixels from an offscreen animated actor against unconditional pose rendering.
  On M1 Max / Compatibility the fixed scene had 453 shadow pixels, 279 animated
  pixels, zero reference mismatches, and 19 rendered capture frames. Its frozen
  pose negative control differed in 279 pixels, proving sensitivity to the bug.
  This covers the targeted shadow regression, not every map/light/renderer.
- The shadow-aware draw-verified live rerun
  (`/tmp/protocol47-live-shadow-aware.json`) rendered 1,800 frames, with ten moving
  actors and 217 effects: p95 20.3 ms, p99 24.3 ms, max 149.0 ms. Only the first
  two frames exceeded 33 ms (100.8/149.0 ms). Compared with the preceding silent
  run's p95 19.5 ms, sustained frame cost is slightly higher; no broad performance
  improvement is claimed for the correctness fix. Match-entry pauses and the
  16.7 ms p95 target remain open. Sampled Godot performance monitors retained
  earlier loading values at entry, so they were removed from the fixture rather
  than used to attribute these pauses.
- Added validated process-local `--renderer=... --driver=...` benchmark overrides
  and renderer-option regressions. Native Metal / Mobile
  completed a draw-verified live probe at p95 17.7 ms, p99 20.1 ms, max 98.8 ms
  (`/tmp/protocol47-live-metal-probe.json`). Its fixed 1,800 frames covered fewer
  physics ticks and combat events, so this alone is not an equal-workload win.
  Matched stationary volley probes emitted the same 6,593 effects and rendered
  every sampled frame: repeated-fire p95 19.4 ms on Metal versus 22.3 ms on
  Compatibility; max 21.2 versus 24.4 ms. Reports are
  `/tmp/protocol47-firefight-metal-probe.json` and
  `/tmp/protocol47-firefight-shadow-gl.json`. Both captures show the same open
  view, weapon, and visible ground smoke, but wall lighting/shadow appearance
  differs; this needs a source-fidelity comparison before choosing a backend.
  Metal still misses the 16.7 ms target;
  repeated distributions and broader rendering fidelity checks remain necessary.
  The production renderer is unchanged.
- The user subsequently approved GPU benchmarks. Final GPU verification
  remains outstanding; headless correctness checks remain the default suite.
- Navigation endpoint projection now uses a bounding-volume hierarchy over the
  existing component-filtered polygon triangles. Distance calculation, lowest-ID
  ties, and full hull clearance remain unchanged. Direct tests matched the old
  exhaustive scan at 7,622 Dust2 and 6,424 Assault points, plus synthetic exact-tie,
  stacked-floor, component-exclusion, empty-index, and non-finite cases. The same
  100-query grid took 2.6 ms on Dust2 (exhaustive reference 181.7 ms) and 1.7 ms on
  Assault (reference 79.9 ms). Index construction adds loading work and memory.
- The first post-index live GPU sample (`/tmp/protocol47-live-bvh.json`) rendered
  all 1,800 frames with 217 effects. The first live frame fell from 100.8 to
  63.6 ms; the next was still 154.6 ms. p95 20.6 ms and two later 33.5/59.8 ms
  frames leave the smoothness gate unmet. Loading was 6.19 s, static memory about
  701 MB. A microbenchmark improvement is not a claim that gameplay is now smooth.
- Added `--live-match --ticks=N` for approximately matched simulation-duration
  comparisons (actual physics ticks and render-frame counts are reported).
  The Node runner rejects invalid/ambiguous tick budgets, mixed frame/tick modes,
  and use outside the live fixture; default fixed-frame sampling remains available.
- Fixed-duration runs reached a later hitch missed by the 1,800-frame sample:
  about 244–253 ms near physics tick 2,716, shortly after `T_Bot_04` dies holding
  a Glock at tick 2,698. The fixture now records death/respawn events and effect
  counts beside slow-frame timestamps; temporal proximity alone does not prove
  which new render resource causes the stall.
- Warmup now also renders the player's starting world/camera projection into an
  undisplayed viewport, without switching the deployment camera or altering
  simulation. Deferred warmup teardown completes before the ready signal.
  A matched 3,000-tick run (`/tmp/protocol47-live-entry-camera-warm.json`) reduced
  the second entry frame from 154.3 to 39.2 ms; the first remains 61.8 ms.
  All 2,627 frames rendered, with 256 effects over exactly 3,000 physics ticks;
  p95 19.5 ms, p99 23.6 ms, max 244.1 ms, loading 5.84 s. The late hitch and
  smoothness target remain open. The rendered effects regression verifies
  camera preservation, no live warmup effects, and retired staging viewports.
- A six-second native sample around the late hitch captured OpenGL shader
  compilation/linking on the main thread (`/tmp/protocol47-death-native.sample.txt`).
  This identifies a remaining render-side stall but not its specific material.
  The profiler itself caused a 1.17 s attachment pause, so its run
  (`/tmp/protocol47-live-death-profiled.json`, `instrumented: true`) must not be
  used as a clean performance result. The specific resource was subsequently
  isolated to planted C4, as detailed below.
- The post-index bot and hostage trajectory artifact hashes matched the
  pre-index artifacts byte-for-byte, in addition to 30/240 FPS determinism.
- Subsequent warmup code exposed a hostage **fixture** ordering bug: its untyped
  dictionary keys included engine-interned `StringName` values. Harmless script
  changes reordered the first assignment snapshot and the fixture's initial
  staging angles. A per-tick `--logical-trace` showed all 300 logical states were
  identical after sorting assignments by their name text. The fixture now
  converts keys to `String` before sorting and tests the exact ordering contract.
  Its corrected 30/240 FPS gate passed with zero physical drift, logical hash
  `ecc29a576e318bb0bf7a4db368faa7e7c580b887e94bf8987522460ab468e05e`.
  Selected report finished `2026-09-08T03:28:21.348Z`; this correction was verified
  after the full-suite run above. The Node runner gate now has 13 passing tests.
- Diagnostic exclusions of world drops, corpse models, effect lights, muzzle
  smoke, the viewmodel, and BSP geometry each left the late ~240–266 ms hitch
  intact. These reduced-presentation runs are diagnosis only, not accepted
  performance improvements. The runner validates and explicitly reports
  `--diagnostic-hide`; no exclusion is enabled by default. Hiding geometry alone
  does not establish that creating its material cannot trigger compilation.
- A temporary macOS OpenGL compile hook captured the actual GLSL programs at
  the hitch (`/tmp/protocol47-shader-trace.alGKL1/30308-494.glsl` through
  `30308-522.glsl`). They include the planted C4's per-pixel studio material and
  Sprite3D LED variant, absent from the temp-entity warmup. The instrumented run
  is `/tmp/protocol47-live-shader-traced.json`; its timings are not a clean
  benchmark. Bomb-state timestamps now confirm planting completes at tick 2,700,
  independently of the nearby death and the player's shot at tick 2,618.
- Loading now renders the actual planted-C4 presentation and retains one hidden,
  process-disabled visual to keep those shader owners alive. No live bomb,
  collision, countdown, or illumination is added. A rendered regression passed
  with no detected errors/leaks, checking camera preservation, frozen countdown,
  hidden lights, both retained LEDs, idempotence, and teardown release.
- Two clean muted 3,000-tick runs with all production visuals restored no longer
  showed the recurring ~242 ms planting stall. The repeat
  (`/tmp/protocol47-live-c4-warm-repeat.json`) rendered all 2,633 frames, 256 effects,
  exactly 3,000 ticks: planting-frame window 34.4 / 19.2 / 11.5 / 9.8 ms;
  p95 19.9 ms, p99 22.6 ms, max 60.7 ms on entry; loading 6.34 s. The first run
  (`/tmp/protocol47-live-c4-warm.json`) had unrelated later 59/79 ms frames, so
  this is a specific hitch fix, not a hitch-free or production-ready claim.
  The entry pause, sustained p95 target, and full-match soak remain open.
- After the C4 warmup change, the selected strict headless gate passed VFX,
  rounds/objectives, bot determinism, and hostage determinism: 25 completion
  markers across four groups, zero detected errors/leaks. The selected report
  finished `2026-09-08T03:44:51.219Z`. The bot trajectory artifact still matches
  the prior SHA-256 `f4385966f94816ac3650c4d2879d44c1ee20997e89042ab9f18e5eeb5da55081`;
  hostage logical hash remains `ecc29a576e318bb0bf7a4db368faa7e7c580b887e94bf8987522460ab468e05e`.
  All 13 Node runner checks also passed. This selected verification does not
  replace the earlier complete 17-group report.
- A subsequent clean 12,000-tick / two-minute sample reached C4 explosion and
  round 2 (`/tmp/protocol47-live-c4-warm-120s.json`): all 13,897 frames rendered,
  640 effects, p95 18.0 ms, p99 22.3 ms. Planting remained 34.5 ms followed by
  19.7 ms; explosion was 36.9 ms. The longer run exposed a different 192.0 ms
  round-reset frame at tick 7,700, a 72.2 ms live-entry frame at tick 8,300, and
  several later 34–56 ms frames. These remain unresolved. Static memory grew
  from ~698 MB to ~756 MB as later-round weapon assets/instances were exercised;
  repeated-round plateau and full-match stability are not yet proven. This is
  a two-round sample, not a completed match or long soak.
- `npm run game:test:rendered` now runs both the shadow-image regression and the
  rendered effects/warmup regression, each muted and strictly error-checked.
  Both passed after the two-minute sample. The shadow report finished
  `2026-09-08T03:47:19Z`: 453 shadow pixels, 279 moving pixels, zero reference
  mismatches, and 279 stale-pose negative-control mismatches over 19 draws.
- Fixture-only `--profile-phases` timings identified substantial synchronous
  reset work: in `/tmp/protocol47-live-round-profile.json`, actor reset cost
  42.8 ms and bot round-buy application 66.5 ms, within a 171.0 ms reset frame.
  This run is instrumented, not a clean performance result. That first profile's
  phase `physics_tick` values are absolute engine ticks (sample origin 219);
  subsequent reports explicitly use `engine_physics_tick` plus
  `physics_tick_origin`, and phase records use the authoritative round number.
- Bot round buying now applies the same inventory/tactic/economy operations
  synchronously, but finalizes presentation once after all purchases. Re-equipping
  the same skin and weapon resets its pose/death/action state while retaining the
  existing character, body, and attached weapon instances. Real weapon-family
  and skin changes still construct the requested source model; equipped C4 remains
  authoritative. A new character-suite regression checks exact fresh-construction
  pose/UV/foot-alignment parity, inventory reset, batching, and C4 transitions.
- The instrumented follow-up (`/tmp/protocol47-live-round-reuse-profile.json`)
  measured actor reset at 35.7 ms and bot buying at 55.6 ms, versus 42.8/66.5 ms
  before; the complete reset frame was still 151.6 ms. The optimization removes
  redundant work but does not resolve the transition hitch or its deferred work.
- Selected correctness verification after model reuse passed five strict groups
  (characters, bots/navigation, rounds, and both determinism gates): 34 completion
  markers, zero detected errors/leaks; report finished `2026-09-08T03:57:10.164Z`.
  All 14 Node runner tests passed. Both rendered regressions passed again, with
  the shadow-image result unchanged (`2026-09-08T03:57:32Z`). Bot artifact SHA and
  hostage logical hash still match the values above, with zero 30/240 FPS drift.
- The clean 9,000-tick follow-up (`/tmp/protocol47-live-round-reuse-clean.json`)
  rendered all 11,002 frames with 298 effects. The reset frame was 157.1 ms
  (earlier clean two-minute run: 192.0 ms at the same transition), followed by
  50.4 ms; live entry remained 75.4 ms. p95 18.1 ms, p99 21.9 ms, loading 5.99 s.
  These samples support a reduction, not completion of the reset fix or a
  controlled repeated-run distribution. Remaining actor/viewmodel preparation,
  deferred render work, and live-start route/AI work still need isolation.
- A second resource trace (`/tmp/protocol47-live-round-resource-profile.json`)
  captured all 352 GLSL shader sources during the initial 6.7 s only; there was
  no new shader compilation through the round-two reset. The files are
  `/tmp/protocol47-shader-trace.alGKL1/16171-*.glsl`. Actor reset included 32.5 ms
  reconstructing the previously used Glock viewmodel (21.4 ms instance setup,
  10.1 ms trigger-frame preparation). Bot buying also loaded three previously
  unused MP5-family character templates (gsg9/sas/gign). This is instrumented
  diagnosis, not a clean timing result.
- Viewmodels now retain up to three inactive weapon presentations in LRU order,
  in addition to the active weapon. They retain the existing 256-frame cap per
  weapon, keep mutable material tint instance-local, hide inactive roots, reset
  action/lighting on restoration, and retire nodes on eviction or scene teardown.
  Catalog-wide lifecycle tests check actual node bounds, eviction, teardown,
  cached mesh identity, and legacy geometry/UV/normal/color/muzzle parity.
- The instrumented follow-up (`/tmp/protocol47-live-viewmodel-residency-profile.json`)
  restored the Glock in ~0.18 ms across the measured load phases. Actor reset
  fell from 45.8 to 20.0 ms in these profiles; full reset was still 140.6 ms,
  bot buying 59.5 ms, and live restart 83.1 ms. Asset loading and other transition
  work remain open; these instrumented samples do not replace clean GPU evidence.
- All three rendered-correctness fixtures passed with viewmodel residency enabled.
  The new image report finished `2026-09-08T04:09:15Z`: 27 rendered frames,
  23,245 visible weapon pixels, 36,901 changed pixels on weapon switch, zero
  restoration mismatches and zero relighting mismatches. The deliberately stale-
  tint negative control differed at 22,858 pixels. This proves the tested AK
  restoration/lighting case, not every weapon/renderer combination.
- The complete headless gate above and all 14 Node runner checks passed with
  viewmodel residency. Bot trajectory SHA and hostage logical hash remain
  unchanged. An additional viewmodel-only run after extending the frame-cap
  boundary test passed at `2026-09-08T04:12:54.288Z`; it inserts more than 256
  distinct frames, proves eviction, and parks/restores a full cache without
  exceeding the bound. Full and selected reports remain separate.
- The clean two-minute residency run
  (`/tmp/protocol47-live-viewmodel-residency-clean.json`) rendered all 13,934
  frames over exactly 12,000 ticks with 640 effects. Reset was 128.3 ms followed
  by 39.1 ms (previous clean reset 157.1 ms; original two-minute sample 192.0 ms).
  Live restart still took 76.3 ms; p95 17.9 ms, p99 21.9 ms, and a later 60.0 ms
  frame leave the smoothness gate unmet. Loading was 6.02 s. Static memory was
  ~698 MB at start / ~757 MB at end; the final viewmodel held 103 active frame
  meshes and two parked weapons totaling 191 frame meshes. This confirms the
  sampled cache bounds, not a repeated-round memory plateau or total GPU memory
  budget. The preserved actor fingerprints and rendered parity checks above are
  correctness evidence; broader match and performance requirements remain open.

- Added bounded fixture-only bot CPU profiling under `--profile-phases`.
  A 1,000-tick comparison of normal and profiled controllers passed exact logical
  signatures and zero physical drift (`/tmp/protocol47-bot-profiler-false.json`
  versus `...-true.json`). The diagnostic 9,000-tick rendered sample
  `/tmp/protocol47-live-bot-route-profile.json` attributed 45.7 ms of one bot's
  46.7 ms live-restart decision to 208 full-body collision sweeps. The full
  live-restart frame was 78.9 ms. These are instrumented timings; other outliers
  in that run remain unattributed.
- That profile also exposed incorrect round-two behavior: `phase:freeze` was
  consumed before `round_start`, whose actor reset reactivated every bot. They
  patrolled throughout the six-second buy phase. The consumer now reapplies
  freeze controls after reset/buy, using event order rather than the potentially
  newer authoritative phase of a batched trace. The regression failed 27 bot
  inactivity/movement/AI checks before the fix and passes afterward. It also
  covers a respawned human's look/control locks and reactivation at the live
  deadline. New live-match reports count observed freeze frames and fail on
  active or moving bots during freeze.
- Selected strict verification after the freeze fix passed rounds plus both
  determinism groups: 23 completion markers, no detected errors/leaks, report
  finished `2026-09-08T04:23:52.438Z`. All 14 Node runner tests passed. These
  deterministic fixtures cover their existing early-round intervals, not a
  claim that corrected round-two trajectories match the buggy earlier runs.
  The latest complete-suite report above predates this fix.
- The clean muted post-fix sample
  `/tmp/protocol47-live-freeze-lock-clean.json` rendered all 12,604 frames over
  exactly 12,000 physics ticks, with 413 effects and zero bot freeze violations
  across 470 observed freeze frames. Round reset measured 86.0 ms (next frames
  18.5/12.1/13.8 ms), but live restart still measured 90.8 ms. p95 was 19.1 ms,
  p99 23.5 ms, loading 6.05 s, and static memory ~698→767 MB. Both planted-C4
  events rendered without the earlier shader hitch (29.6 ms in round one,
  24.3 ms in round two). Correcting the six seconds of premature bot movement
  intentionally changes round-two routes, encounters, and visible workload, so
  this is the new correctness baseline, not a controlled percentile comparison
  against the buggy sample. The smoothness gate remains unmet; initial live
  routing and cold round-buy preparation still need work.

- A trial 8 m limit on optional navigation shortcuts was removed. It changed
  the original Dust2 mobility route enough to fail the existing floor-contact
  gate (including an airborne T bot); restricting the limit to initial route
  compaction still failed. The ground-contact acceptance criteria were not
  loosened, and no shortcut-distance cap remains. Diagnostic bot records now
  include total swept distance and the slowest individual sweep's time/distance
  for further investigation of the unresolved live-start cost.
- Character reloads used by team/class changes previously added new body/weapon
  children without retiring the old ones. `load_character` now validates the
  replacement body first, detaches and retires old body/gun/drop nodes, resets
  lighting for the new materials, and preserves the last usable model/identity
  if the replacement body fails. The lifecycle regression failed before the
  fix and now checks six repeated reloads, immediate two-child bounds, old-node
  weak-reference release, corpse reset, and failed-load preservation. The actual
  halftime event consumer also checks mesh count and the new skin.
- All three muted rendered-correctness fixtures passed after the reload fix.
  The expanded shadow report finished `2026-09-08T04:32:52Z`, with 27 draws,
  727 changed pixels for the replacement corpse, and zero pixels differing
  after restoring the original character versus its fresh-render reference.
  Existing moving-shadow/negative-control results remain 279 pixels, with zero
  optimized-versus-reference mismatch. This verifies the exercised replacement
  lifecycle and shadow case, not full-match memory or GPU smoothness.
- Post-reload selected correctness gates passed five groups (characters, rounds,
  bots/navigation, and both determinism gates), 34 markers, no detected errors
  or leaks; report finished `2026-09-08T04:34:12.025Z`. The later explicit
  halftime mesh-count assertions also passed in a standalone strict round
  integration run. The expanded profiler matched the normal 1,000-tick logical
  trace exactly with zero physical drift, and all 14 Node runner tests passed.
  No new clean GPU timing sample was taken for this lifecycle-only fix; the
  prior 90.8 ms live-start result remains unresolved.

- Rendered deployment now prepares the bot buy planner's finite presentation
  matrix for the actual roster on both possible sides, including only assigned
  sniper skins and (on bomb maps) the T-side C4 poses. Dust2 has 38 unique
  skin/weapon requests; Assault has 34. Source templates are shared through the
  same lookup as normal character loading. Preparation is incremental before
  readiness, idempotent, and does not purchase/equip items, create actor meshes,
  move bots, or advance their AI clocks. The new character-suite fixture checks
  those invariants, exact cache membership, prepared MP5 construction, and cache
  release; explicit checks also passed on Assault and after the final scenario
  assertions on Dust2. Headless simulation does not automatically preload.
- The clean muted `/tmp/protocol47-live-bot-assets-clean.json` rendered all
  16,933 frames over 12,000 ticks, with 413 effects and no freeze violations
  across 548 observations. Round reset measured 34.1 ms followed by
  14.0/10.8/10.1 ms (previous corrected-freeze sample: 86.0 ms). Live restart
  remains 86.2 ms, with a later 62.2 ms outlier. p95 16.5 ms and p99 19.5 ms meet
  those percentile thresholds in this one sample, but the recurring live-start
  spike still fails the smoothness requirement. Broader scenarios and repeated
  runs remain necessary. All objective transition ticks matched the previous
  sample; three render-sampled death timestamps differed by one physics tick.
- The cache tradeoff is explicit: 14 new templates took 14 loading slices and
  ~210 ms in that run, with ~164 MB observed static-memory growth. Total loading
  was 6.46 s (previous 6.05 s); observed static memory was ~862 MB at start and
  ~873 MB at end, not peak or total GPU memory. A read-only SHA-256 survey of the
  selected animation tapes found only ~25 MB of whole-file duplication across
  these body families, so whole-tape deduplication alone would not recover most
  of this cost. No tape-deduplication change was made.
- The full 17-group/65-marker gate above passed with these production changes;
  both 30/240 FPS deterministic traces remain unchanged, including bot SHA
  `f4385966f94816ac3650c4d2879d44c1ee20997e89042ab9f18e5eeb5da55081`.
  All 14 Node runner checks and all three muted rendered regressions passed
  again; shadow reload mismatch remains zero (report `2026-09-08T04:40:44Z`).
  The release-use choice (private/local versus public distribution) has been
  requested and remains pending; neither asset rights nor signing authority
  is inferred from the local project.

- Further instrumented live-route sampling (`/tmp/protocol47-live-route-repeat-profile.json`)
  rendered all 14,246 frames over 9,000 ticks with no freeze violations. The
  live-start frame remained 92.0 ms. Exact same-tick repeated hull sweeps cost
  only ~1.4 ms at that restart, so a shared result cache was not implemented.
  A conservative triangle AABB/plane index also preserved sampled results but
  increased query CPU time; it remains an experimental test-only helper, not a
  production path. Initially overlapping the world does not justify excluding
  the entire world from a sweep: both maps contain counterexamples.
- The navigation gate now requires both blocked and clear native casts, guarding
  against vacuous parity in an empty physics world. Default-backend results are
  523 blocked/477 clear on Dust2 and 440/560 on Assault. The selected bots plus
  deterministic-mobility gate passed 12 markers with no detected errors/leaks
  (`headless-test-selected-report.json`, finished `2026-09-08T04:59:51.650Z`).
- An isolated temporary project (`/tmp/protocol47-jolt-probe.9UqjfK`) now probes
  Jolt; the production project still uses Godot Physics. With ray face indices
  enabled and collision margin fraction zero, identical 1,000-query endpoint
  grids took 20.6 ms versus 984.8 ms on Dust2, and 18.3 ms versus 421.6 ms on
  Assault. However, five Dust2 and three Assault clearance booleans changed.
  Reports are `/tmp/protocol47-{godot,jolt-sharp}-nav-{de_dust2,cs_assault}.json`.
  Optional `--clearance-report=...` records endpoint fingerprints and exact
  result bytes, while performance reports now identify their actual backend.
- This is not an approved backend migration. Default Jolt failed the angled
  14-HU step regression; zero collision margin fraction made that test pass.
  The ceiling test still fails (feet y=0.079872, existing maximum 0.079000);
  its assertion was not relaxed and now reports the actual endpoint. Default
  Jolt did pass the 1,000-tick mobility test and both 30/240 FPS determinism
  comparisons, but those checks must be repeated for any adjusted configuration.
  Ray face indices matter to material-dependent penetration and footsteps;
  [Godot's Jolt documentation](https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html)
  explains that they are disabled by default and that Jolt rounds convex shape
  edges according to its collision margins. Neither faster sweeps nor these
  narrow passes establish source-accurate movement or complete-match fidelity.
- The silent, uninstrumented Jolt sharp-hull rendered probe
  `/tmp/protocol47-jolt-sharp-live.json` rendered all 17,662 frames over 12,000
  ticks at Compatibility/1280×720. It recorded 576 effects, no freeze violations
  across 544 observations, p95 13.2 ms, p99 15.7 ms, and max 37.1 ms. Only the
  C4 explosion (35.9 ms) and round reset (37.1 ms) exceeded 33.3 ms; no live-start
  frame crossed that threshold. Loading was 6.65 s and observed static memory
  ~894→906 MB. The encounters and objective timings differ from the production
  baseline (413 effects), so this is promising diagnostic evidence, not a
  controlled equal-workload improvement or production-readiness approval.
  The process exited with its activity/draw guard passing and no detected errors
  or leaks. Normal-backend ceiling regression and all 14 Node runner tests also
  passed after the diagnostic/reporting edits; no production physics setting
  has changed.
- With the adjusted Jolt configuration, the eight map fixtures, ballistics,
  seventeen round/objective fixtures, and both 30/240 FPS determinism comparisons
  passed (32 completion markers, no detected errors/leaks). The existing
  ceiling failure and eight cross-backend clearance differences remain open.
  These runs do not replace the normal-backend complete-suite report.
- Ballistics now also checks 24 real ray hits across six distinct triangle
  materials, a static world body with inherited texture metadata, and a moving,
  rotated brush with its own reversed texture table. Both normal Godot Physics
  and adjusted Jolt pass. Disabling Jolt face indices in the isolated negative
  control produced 48 face/material assertion failures, confirming the new
  regression catches the otherwise silent concrete-material fallback. The
  fixture waits for a completed physics step after moving the brush; querying
  before backend synchronization had produced stale-geometry misses in the
  first diagnostic version. No production collision or material policy changed.
- The expanded repeat-counting profiler also passed the original 1,000-tick
  mobility gate and matched the uninstrumented logical trace exactly with zero
  physical drift (`/tmp/protocol47-repeat-profiler-signature.json`). Both
  benchmark report formats executed successfully with the new backend fields;
  the stationary report-format check was CPU-only, not fresh GPU evidence.

- Follow-up diagnosis exported the exact hulls and world/submodel triangles for
  all eight changed queries (`tests/collision_backend_probe.gd`). An independent
  double-precision translated-box/triangle separating-axis diagnostic, with six
  analytic unit tests, distinguished initial contacts, front/back faces, and
  late grazing contacts. This is a triangle-geometry check, not a GoldSrc BSP
  oracle. Jolt's source confirms that an initial overlap can cause an entire
  body to be skipped by `cast_motion`, hiding later walls of a concave world.
  [Engine implementation](https://github.com/godotengine/godot/blob/4.7.1-stable/modules/jolt_physics/spaces/jolt_physics_direct_space_state_3d.cpp)
- Navigation now rejects initial hull overlaps before doing the full sweep.
  The synthetic contract test failed three cases before this change (including
  a floor overlap hiding a later wall); it now also checks stationary hulls,
  shoulder clearance, finite edges, and collision masks. It is part of the bots
  suite. The 1,000-query parity reference now includes the overlap check rather
  than treating the old ignored-overlap behavior as correct. The same guard
  under Godot Physics changed a route enough to fail the original floor-contact
  gate; its acceptance criteria were not loosened. The combined Jolt trial
  passed mobility, angled steps, jumpable ledges, and Dust2 objectives.
- The ceiling comparison exposed an invalid one-sided test maximum. For the
  fixture's 80-HU ceiling and 72-HU hull,
  [ReHLDS's 1/32-HU separation](https://github.com/rehlds/ReHLDS/blob/0124d56c3d888d922eb045775f71c6682ad1226f/rehlds/engine/pmovetst.cpp#L625)
  gives feet y=0.07968747. Godot stopped at 0.07635948 (0.333 HU short); initial
  Jolt stopped at 0.079872 (about 0.018 HU too far). A separate source-valued
  contact separation now produces 0.07965948 (0.0028 HU short). The ceiling
  assertion is replaced by a two-sided source-derived endpoint check within
  1/64 HU, which rejects both prior results. Supporting-floor recovery keeps
  its distinct engine margin. This proves the exercised plane case, not every
  swept collision or the absent full BSP clip-hull oracle.
- The project now explicitly selects Jolt, zero convex collision margin
  fraction, and enabled ray face indices, together with the overlap guard and
  source-valued contact separation. The earlier isolated unguarded GPU sample
  is not performance evidence for this combined change. All three muted
  rendered-correctness fixtures passed after the combined change: shadow and
  character reload mismatch zero (`2026-09-08T05:18:22Z`), viewmodel restore and
  relight mismatch zero (`2026-09-08T05:18:27Z`). Full-suite and fresh smoothness
  results are recorded separately when complete.
- The combined production change passed the complete 17-group, 66-marker
  strict gate with no detected script errors or leaks (report finished
  `2026-09-08T05:20:11.545Z`). All 14 runner checks and six independent geometry
  diagnostic tests passed. The stronger navigation reference observes 947
  blocked/53 clear queries on Dust2 and 956/44 on Assault; this intentionally
  rejects shortcuts whose starting hull touches/overlaps the world instead of
  accepting an ignored-body cast. More adjacent fallback portals are retained,
  but original floor-contact, no-penetration, travel, angled-step, and jump gates
  pass without relaxing their criteria. Determinism remains exact at 30/240 FPS
  with zero physical drift. The new bot logical SHA is
  `ff200c7bddc678ffed987063e4e836e96c8dcf67128828a4d419fcc47ccf0edc`;
  the hostage logical SHA is unchanged. This is a new trajectory baseline,
  not an assertion that the old backend's gameplay trace was preserved.
- Fresh production GPU sample `/tmp/protocol47-jolt-safe-live.json` was muted,
  uninstrumented, with no render exclusions: 19,368/19,368 frames drawn over
  12,000 ticks, 847 effects, and zero freeze violations across 553 observations.
  At Compatibility/1280×720, median was 5.43 ms, p95 12.39 ms, p99 15.70 ms.
  The old ~86 ms live-start spike did not recur. However, max was 58.24 ms at
  tick 6496, shortly after round reset at tick 6467 (35.27 ms, then
  15.87/11.51/11.02 ms). That post-reset outlier remains unattributed and needs
  repeat/profile checks. Loading was 6.56 s and observed static memory
  ~894→908 MB. This route/encounter baseline differs from both earlier samples;
  round one ended by elimination before its planted C4 exploded, so this run
  does not renew explosion-frame coverage. Broader maps, repeats, full matches,
  and soaks remain open; passing percentiles alone does not satisfy smoothness.
- The source-ceiling assertion's isolated negative control restored the old
  0.01-HU contact separation and failed at y=0.07987198, as intended. The
  diagnostic project was restored afterward; production stayed at 1/32 HU.
  The diagnostic bot profiler also matched the new 1,000-tick production trace
  exactly with zero physical drift (`/tmp/protocol47-jolt-safe-profiler-signature.json`).

- The post-reset Dust2 profile repeat did not reproduce the isolated 58 ms
  hitch: `/tmp/protocol47-jolt-safe-reset-profile.json` rendered all 19,377
  frames over 12,000 ticks, max 33.00 ms, 847 effects, and zero freeze violations
  across 557 observations. Reset was 28.25 ms of game CPU; bot buying loaded no
  new templates, and no individual bot decision exceeded the 2 ms reporting
  threshold. This instrumented repeat does not attribute or fix the outlier.
- Broader clean testing found Assault still over budget:
  `/tmp/protocol47-jolt-assault-live.json`, T side, 12,000 ticks, 8,864/8,864
  frames drawn, p95 19.01 ms, p99 23.55 ms, max 42.13 ms (early entry), 252
  effects. A quiet stretch followed the early firefight. It never restarted
  the round, so zero observed freeze violations there are not freeze coverage.
- The live runner now validates supported map and local-team selections and
  reports final actor/hostage states and round-end events. Its CT selection
  uses normal team/class selection. A CPU-only 3,000-tick Assault CT check
  passed and confirmed the requested roster, but all four hostages remained
  unused. Existing short hostage-bot determinism includes a staged rescue
  teleport; it does not establish traversal from normal CT spawn or full-match
  hostage objectives. These remain requirements, not passing claims.
- A muted 3,000-tick Assault timing profile isolated hostage presentation:
  `/tmp/protocol47-assault-hostage-profile-before.json` spent 8,751 ms total in
  3,000 hostage advances (~2.92 ms/tick), including 404 ms of contract sync.
  Hostages now skip mesh deformation outside every active same-world camera,
  using a cached conservative envelope of all source poses plus grounding.
  Nonuniform/affine ancestor transforms and shared-world SubViewports are
  included; enabling shadows fails open. Animation/action clocks continue at
  100 Hz, render-frame reentry submits the current pose without waiting for a
  physics tick, and explicit pose staging remains synchronous. Equivalent
  skin updates no longer defeat culling; reloads reset that binding cache and
  immediately detach the retired mesh. Lighting policy is unchanged.
- The new hostage presentation regression checks 1,292 authored/interpolated
  poses, per-tick logical parity with unconditional deformation, action expiry,
  reentry, hidden/shadow states, camera masks/addition/removal/shared worlds,
  and same-skin reloads. The muted rendered check passed at
  `2026-09-08T05:39:01`: 19 capture frames, 1,301 hostage pixels, zero optimized
  versus forced-render mismatches; a deliberately stale pose differs in 1,336
  pixels. The GPU bounds check uses the submitted `custom_aabb`, since region
  writes leave `ArrayMesh.get_aabb()` at its creation-time value. Report:
  `game/artifacts/hostage-render-test-report.json`. The fixture is now included
  in the headless character suite and the separate rendered suite.
- The matched instrumented Assault repeat
  `/tmp/protocol47-assault-hostage-profile-after.json` reduced total hostage
  advance CPU to 453 ms (~0.151 ms/tick); contract sync was 254 ms. It rendered
  all 2,984 frames, emitted the same 252 effects, and reached identical final
  actor positions/alive states and hostage state over 3,000 ticks. Its p95 was
  14.63 ms, max 31.52 ms. These timings support attribution, not clean release
  performance; clean longer runs and broader objectives remain necessary.

- The clean two-minute Assault T rerun after hostage pose culling
  (`/tmp/protocol47-assault-hostage-cull-live.json`) drew all 13,594 frames over
  12,000 ticks with 252 effects: median 8.67 ms, p95 11.51 ms, p99 14.93 ms,
  versus prior clean p95 19.01 ms. Loading was 6.53 s, static memory ~831→835 MB.
  One 54.62 ms outlier at tick 7538, long after combat stopped, remains
  unattributed. No hostages were used/rescued and no round ended. The improved
  frame distribution does not resolve objective traversal or complete-match
  coverage, and is not a hitch-free/production-ready claim.

- The clean muted Assault CT run (`/tmp/protocol47-assault-ct-cull-live.json`)
  sampled 20,849 frames / 20,848 draws over 12,000 ticks, with 170 effects:
  median 5.99 ms, p95 9.17 ms, p99 20.18 ms, max 42.95 ms on entry. Loading
  was 6.74 s, static memory ~832→836 MB. This view is a different workload,
  not an A/B comparison with the T camera. All four hostages again remained
  unused and the round never ended. The final capture shows CTs stopped on the
  outside walkway, not inside the hostage room.
- The CT route snapshot reveals a concrete objective failure: living CTs in
  `rescue_hostage` state have zero velocity/obstruction counters near the
  projected destination (-14.56, 2.60, -25.92), while the first hostage is at
  (-10.56, 3.36, -25.92). The read-only navigation probe
  `/tmp/protocol47-assault-hostage-nav-probe.json` found 35 graph components;
  the largest has 1,003 polygons, but every hostage lies over another 438-polygon
  component. Restricting nearest-point projection to the largest component
  moves the four destinations 4.07–6.11 m away. Searching all components finds
  points directly above them, only 0.039 m from the actor origins. The closest
  main/hostage-component vertices are 0.48 m apart with a 0.32 m rise; that is
  a candidate traversal boundary, **not** proof a hull can cross it. Correct
  objective routing needs verified inter-component traversal and arrival/use
  checks against the real objective. Simply allowing an unreachable raw target
  or accepting the distant projection is not a fix. Existing parity checks
  preserve the largest-component policy and therefore do not cover this bug.
- All four muted rendered-correctness fixtures passed after the hostage change
  (`2026-09-08T05:45:18`–`05:45:24`): character shadows/reloads, combat effects,
  viewmodel residency/relighting, and hostage reentry. Hostage optimized/reference
  pixels still match exactly and the stale negative control differs in 1,336
  pixels.
- The complete strict headless rerun finished at `2026-09-08T05:47:58.917Z`:
  all 17 groups and 67 completion markers passed, with no detected script
  errors/leaks. All 15 Node runner tests passed too. Both 30/240 FPS determinism
  comparisons remain exact with zero physical drift; bot SHA remains
  `ff200c7bddc678ffed987063e4e836e96c8dcf67128828a4d419fcc47ccf0edc`,
  hostage SHA remains
  `ecc29a576e318bb0bf7a4db368faa7e7c580b887e94bf8987522460ab468e05e`.
  These existing checks do not invalidate the newly observed Assault
  inter-component objective failure, which still needs a production fix and
  a from-spawn traversal regression.

- The Assault traversal investigation added an authored entrance jump link
  outside generated BSP assets (`game/assets/navigation/cs_assault.tscn`).
  Its grounded endpoints bind within 8 cm to clear standing-hull polygons;
  traversal approach/landing points cannot be smoothed away. The original
  main and hostage components now connect, and hostage arrival uses the real
  hostage position rather than the formerly distant projection. This is not a
  general proof that every authored link or route is physically traversable.
- Physical entrance probes exposed two independent collision failures. Bot
  lookahead clipping stopped short of touch-operated doors, and an
  `AnimatableBody3D` under a moving model root retained its old physics pose
  while the visual rotated. The latter is explained by the engine's
  [local-transform synchronization implementation](https://raw.githubusercontent.com/godotengine/godot/4.7-stable/scene/3d/physics/animatable_body_3d.cpp).
  Source-clock-driven brush children now use ordinary transform propagation.
  Bots let the body solver reach movable brushes and forward real movement
  contacts once, including all contacts in each slide result. Reset clears
  contacts; mathematical AABB overlap is no longer required for an actual
  solver-reported touch. The existing small AABB touch tolerance is unchanged.
- The strengthened brush integration regression passes: closed-door ray,
  nearby non-contact negative control, actual pawn-triggered opening, full
  standing-hull passage without teleport, no invisible closed-position
  collider, solid rotated leaf, consumed/reset contacts, and restored closed
  collision. Dynamic-BSP tests now inspect physics-server poses after frame
  synchronization for transform/position/rotation/reset, not just node-local
  identity. The map and player-movement groups passed after these changes.
- Ordinary route waypoints no longer cut a corner merely because the actor
  enters a 40 cm steering radius: the outgoing full-hull sweep must be clear.
  The tight arrival test shares the planar steering deadzone and tolerates
  the navmesh's small height offset, avoiding a zero-velocity arrival deadlock.
  Synthetic regressions cover shoulder obstruction, real arrival, passed
  corners, and required jump approaches.
- New routes made Dust2's crowd fixture perform a real jump at tick 694.
  Its old unconditional 2 HU floor-gap assertion incorrectly counted 54
  airborne ticks as floor errors. The updated audit requires a grounded
  source impulse, gravity, per-tick integrated displacement, bounded apex and
  flight duration before exempting a positive airborne gap. Hovering and
  vertical-warp negative controls are rejected; penetration, world-hull,
  pair-overlap and grounded 2 HU checks remain active. The run records one
  verified jump / 55 audited airborne ticks, a 28.86 HU airborne floor gap,
  and maximum grounded error 1.996 HU with zero violations. Both 30/240 FPS
  determinism comparisons passed with exact logical state and zero physical
  drift; the changed Dust2 path SHA is
  `a8d0e790e7298bc6be37d672792edcaa6bc92d9654d46d96a090d83e2ea7bff5`.
  The hostage staged-determinism SHA remains unchanged. All 16 Node runner
  tests passed, including default inclusion of the new rescue gate.
- The earlier muted 18,000-tick from-spawn Assault run
  (`/tmp/protocol47-assault-hostage-traversal.json`, engine log
  `/tmp/protocol47-assault-traversal-door-sync.log`) opens the entrance at tick
  1,027; three CTs physically jump the transition. First hostage use occurs
  at tick 2,924, rescues at 6,280 and 6,390, and maximum per-tick pawn/hostage
  displacement is 0.182 m. This is a concrete improvement from zero hostage
  uses/rescues, but **the gate still fails**: CT_Bot_01 stalls near
  (5.15, 0.0015, -4.23), leaving hostage_151 unused; hostage_153 follows but
  remains near the entrance while its leader waits at rescue. The round does
  not end. Do not replace the all-four-rescue requirement with a partial-pass
  marker. The next investigation must cover the blocked bot route and actual
  hostage/door contact (the current Game touch loop includes combatants only).
  [Source DoorTouch](https://raw.githubusercontent.com/rehlds/ReGameDLL_CS/master/regamedll/dlls/doors.cpp)
  does not generally exclude living non-player entities; do not assume a
  player-only touch workaround is source-faithful.
- A further muted corridor probe (`/tmp/protocol47-assault-stalled-route.log`)
  finds both the stalled CT's position and its next waypoint on one polygon,
  with clear stationary full hulls and clear center rays. The shoulder grid is
  narrow: the route at z=-4.24 is clear but z=-4.20 intersects world geometry.
  A fixed-direction actor aligned at z=-4.24 physically reaches x=4.716 without
  obstruction (`/tmp/protocol47-assault-stalled-movement.log`), so the next
  investigation should retain the normal controller's approach/unstick state;
  the straight corridor itself is not proven impassable.
- All four muted rendered-correctness fixtures passed again after the door and
  navigation changes (`2026-09-08T06:20:59`–`06:21:05`): shadow/reload, combat
  effects, viewmodel residency/relighting, and hostage presentation. Reference
  pixel mismatches remain zero; stale-shadow/hostage negative controls differ
  in 279/1,336 pixels. GPU **timings** above still predate the navigation and
  moving-collision changes. These narrow pixel checks do not establish live
  smoothness or release readiness.
- The full strict rerun starting `2026-09-08T06:19:52.119Z` completed all
  eighteen groups: the existing seventeen passed with 67 completion markers,
  and `game:test:assault-traversal` failed only its all-four-rescue and round-end
  assertions. `game/artifacts/headless-test-report.json` correctly records
  `ok: false`; the new default gate is not green. Its repeated rescue timings
  match the earlier run (2,924 first use; 6,280/6,390 rescues), while late
  obstructed-actor positions differ slightly. Only the dedicated short
  30/240 FPS fixtures, not the full rescue run, have exact replay proof.
- A clean muted rendered Assault CT run with these changes completed 12,000
  ticks / 17,279 sampled frames / 17,278 draws and 386 effects
  (`/tmp/protocol47-assault-door-nav-live.json`, matching `.png`). On M1 Max /
  Compatibility / 1280×720: median 5.854 ms, p95 15.298 ms, p99 29.552 ms,
  max 47.504 ms, with 49 frames over 33 ms. Many slow frames occur in the
  opening four seconds before the first effect; others occur during combat.
  Loading was 6.931 s, static memory ~835→842 MB. This misses the p99 target.
  Compared with the earlier CT run, routes, camera and combat workload changed
  (386 versus 170 effects), so percentile differences are not an isolated A/B
  measurement. No local shots or hostage uses occurred in this combat-enabled
  run; the round did not end, and the final screenshot shows the local player
  stopped in the entrance vestibule. The benchmark completion marker means
  the measurement/draw/activity checks passed, not production smoothness.
- The separate muted 3,000-tick opening profile
  (`/tmp/protocol47-assault-door-nav-profile.json`) reproduces the slow section:
  1,883 frames / 1,882 draws, 295 effects, p95 30.765 ms, p99 38.318 ms,
  max 45.501 ms (instrumented, not a clean release measurement). No individual
  bot decision reaches the profiler's 2 ms reporting threshold. Hostage
  advance/sync totals 3.318 s over 3,001 calls (~1.106 ms/tick), with a 3.293 ms
  maximum; nested contract sync is 0.239 s. The only reported slow Game phase
  is initial round consumption (19.022 ms, including a 15.413 ms prepared buy
  with no new templates). Thus the recurring early 35–45 ms frames are
  reproduced, but **not yet attributed**; these probes do not justify blaming
  the new corner sweeps or claiming another loading-only hitch. Native/full
  frame CPU/GPU profiling of the active opening view remains necessary.

- Living, unrescued hostage actors now forward their actual movement contacts
  to touch-enabled doors, using their BSP entity IDs and smaller source hull.
  Contacts survive movement retries and are consumed once; reposition/death/
  rescue clears them. Buttons remain combatant-only, and the existing door
  capability/target restrictions and AABB tolerance are unchanged. The brush
  integration fixture now exercises real hostage-driven opening and passage,
  plus dead/rescued and reset/contact-consumption negative controls.
- The stalled corridor approach was caused by the body's 15-degree minimum
  wall-slide guard discarding a small but necessary lateral correction. Bot
  and hostage bodies now retain tangential wall movement, consistent with the
  local GoldSrc velocity-clipping implementation. A normal-controller fixture
  reaches x=4.706 with the change; restoring only the old guard stalls at
  x=5.000 on the identical approach. Maximum tick displacement is 0.0253 m.
- Focused from-spawn Assault runs now rescue all four hostages and finish the
  round with either player-team selection: T at tick 9,240, CT at tick 15,130.
  Both use physical movement and the normal objective clock; only perception
  is blinded. Door opening occurs at tick 1,027, all four assigned CT bots
  jump the entrance transition, and maximum pawn/hostage tick displacement is
  0.182 m. One hostage in each run needs normal stuck/re-use recovery, with no
  duplicate first-use reward. Reports are
  `/tmp/protocol47-assault-hostage-traversal.json` and the `-ct.json` variant.
  These are traversal checks, not combat-enabled full-match proof.
- The selected map/bots/bot-determinism/hostage-bot-determinism gate finished
  `2026-09-08T06:37:12.891Z`: all four groups passed, 25 completion markers,
  zero detected errors/leaks. Both 30/240 FPS comparisons remain exact after
  the hostage-contact and wall-slide changes.
- The complete strict rerun finished `2026-09-08T06:45:22.107Z`: all eighteen
  groups passed, 70 completion markers, no detected errors/leaks. The two
  from-spawn rescue runs repeat the 9,240/15,130-tick round ends. Current report:
  `game/artifacts/headless-test-report.json`. All sixteen Node runner tests
  passed too. Four muted rendered-correctness fixtures passed at 06:41:22–29
  UTC, with zero reference pixel mismatches and working negative controls.
  The new metrics preflight and CPU live integration passed separately; the
  latter accounted for all 1,801 frames and 246 effects across 31 windows.
  These results supersede the historical red rescue report above, but do not
  satisfy performance, full-match, multiplayer, or distribution requirements.
- Live performance reports now include 100-physics-tick frame-time windows,
  with effect counts and minimum/maximum living actors. Each sampled frame
  belongs to its ending-tick window; stalls spanning a boundary are not split,
  empty windows are not invented, and partial final windows remain visible.
  Summaries are computed after measurement. A muted metrics preflight covers
  boundaries, sparse/empty/single-frame data, counter reset, and a slow opening
  followed by cheap idle frames; the performance runner requires it to pass.
  Overall percentiles remain present but cannot alone establish smoothness.

- The clean post-rescue-fix Assault CT GPU run
  (`/tmp/protocol47-assault-rescue-fixes-live.json`, matching `.png`) measured
  12,001 ticks / 6,947 frames / 6,946 draws and 961 effects across a round end
  and restart. M1 Max / Compatibility / 1280×720: median 17.925 ms,
  p95 29.044 ms, p99 36.508 ms, max 103.919 ms, 99 frames above 33 ms.
  Loading was 7.132 s; static memory ~835→848 MB. All 608 observed freeze
  frames kept bots inactive/stationary. No local shots or hostage uses occur;
  the final screenshot still shows the local driver facing the entrance wall.
  This is not adequate full-map traversal or full-match coverage. Windowed
  p95 is 43.72 ms at ticks 100–199, and 69.839/68.317 ms at ticks 5,600–5,799
  after the round transition, with no new effects in those windows. All window
  frame/effect/slow-frame totals match the full report. Smoothness fails.
- An eight-second native sample of the opening
  (`/tmp/protocol47-assault-opening-native.sample.txt`, instrumented report
  `/tmp/protocol47-assault-opening-native.json`) did not name most engine
  functions in this stripped build. The Compatibility GPU profiler reported
  empty zero-time results, not credible evidence of zero GPU cost.
  A separate `--debug --profiling` run produced useful script timings in
  `/tmp/protocol47-assault-opening-script-profile.log`: one 47.273 ms frame
  spends 42.199 ms in scripts, including 14.504 ms in twenty hostage tick
  animation calls across five physics steps. Character interpolation and
  minimum-height calculations are additional major costs. These are nested
  profiler timings, not additive totals or clean release measurements.
- Hostage animation clocks still advance every 100 Hz tick, but ordinary
  mesh submission now occurs in the render callback. Intermediate catch-up
  physics poses no longer rebuild meshes that cannot be displayed. Explicit
  setup/actions/forced captures remain synchronous. A counted-submission
  regression proves seven ticks advance the exact clock with zero intermediate
  submissions, then one render matches the per-tick reference; another render
  without a tick does not rebuild. Source-frame actor assertions now explicitly
  observe a render after each tick and retain all their exact expected keys.
  Actor, presentation, and game-integration headless checks passed. The
  30/240 FPS hostage replay remains logically exact with zero physical drift,
  and all four muted rendered fixtures passed at 06:51:04–10 UTC (zero hostage
  reference mismatches, 1,336-pixel stale-pose negative control).
- The clean muted post-batching GPU run
  (`/tmp/protocol47-assault-batched-hostage-live.json`, matching `.png`) completes
  12,000 ticks / 7,975 frames / 7,974 draws with the same 961 effects and one
  CT round win. Median is 15.506 ms, p95 21.268 ms, p99 25.135 ms, max
  40.398 ms; only four frames exceed 33 ms (previously 99). Opening ticks
  100–199 improve from p95 43.720 to 33.056 ms. The two worst post-transition
  windows improve from 69.839/68.317 to 25.821/26.206 ms. Loading is 6.631 s,
  static memory ~835→848 MB, with zero freeze-control violations. Rendered
  capture inspection confirms the same final entrance-wall view; it does not
  solve the automated local driver's traversal limitations. This is one
  before/after pair, not a repeated-run distribution. Both the overall p95
  and p99 targets remain unmet, and active windows are slower still.
  The full post-optimization headless rerun completed at
  `2026-09-08T07:00:01.193Z`: eighteen groups, 70 completion markers, no detected
  errors/leaks. Both full rescue outcomes remain at ticks 9,240/15,130.
- The next profile-backed optimization specializes the foot-grounding scan
  for identical pitch samples and identical frames. It still takes the
  minimum over every interpolated vertex, never interpolates cached endpoint
  minima, and leaves general pitch blending unchanged. A new character-suite
  regression compares against the original four-source-sample calculation
  over 2,431 cases from all eight player models, the hostage model, and a
  synthetic crossing-minimum negative control. The pre-implementation
  candidate matched exactly and took 23.519 ms for 200 queries versus
  51.842 ms for production; this is an isolated CPU check, not a GPU result.
  The production fast path passes all 2,431 exact comparisons (22.816 ms for
  200 queries versus 39.368 ms for the independently written reference), the
  full character group, and 30/240 FPS hostage determinism with zero drift.
  All four muted rendered fixtures pass at 07:00:49–55 UTC, with unchanged
  shadow/hostage negative controls and zero reference mismatches. Clean live
  GPU measurement and the full expanded 71-marker headless rerun subsequently
  completed, as recorded below.
- The clean grounding-fast-path GPU run
  (`/tmp/protocol47-assault-grounding-fast-live.json`, matching `.png`) measures
  12,000 ticks / 8,789 frames / 8,788 draws, again 961 effects and the same
  authoritative CT round win at tick 4,413. Median is 13.923 ms, p95 19.604 ms,
  p99 22.616 ms, max 36.150 ms, with two frames over 33 ms (live entry and
  round reset). The opening 100–199 tick window remains p95 27.033 ms; the
  two prior slow post-transition windows are now 22.774/23.358 ms. Loading is
  6.589 s, static memory ~835→849 MB, with zero freeze-control violations.
  The screenshot confirms the same limited entrance-wall camera coverage.
  The full strict suite completes `2026-09-08T07:09:35.906Z`: eighteen groups,
  71 markers, no detected errors/leaks, both rescue outcomes unchanged.
- A separate vector-interpolation prototype performs native Vector3 operations
  on small source-frame slices. Its 300-query check, including allocations,
  takes 22.203 ms versus 116.658 ms for scalar interpolation; this is not a GPU
  result. The integrated sampler retains no new frame cache, preserves surface
  ordering/UVs/materials, and leaves actual animated-bound accumulation intact.
  It uses engine-width-aware decoding with a scalar-construction fallback.
  Source clocks, pitch selection, gait masks and exact grounding are unchanged.
- The new sampler regression covers 38 templates, 10,970 surface samples and
  7,315,702 vertices, including fractional frame/pitch blends, wraparound,
  offsets, empty surfaces, overlays, fallback construction and independent
  output storage. Maximum difference from the old double-scalar calculation
  is 0.000000060184 m, below the test's one-micrometre ceiling and the existing
  source-quantization tolerance. The vector path is not claimed bit-identical.
  Actual production surface creation and GPU region updates match reference
  pixels for body/gait, AK and hostage cases: zero mismatches, with negative
  controls differing in 4,418/1,620/3,642 pixels. All five rendered fixtures
  pass at 07:10:49–59 UTC, as do the character group and exact 30/240 FPS
  hostage determinism. The full 72-marker rerun subsequently passed at
  07:19:29 UTC (`game/artifacts/headless-test-report.json`).
- The clean muted vector-sampler Assault CT run
  (`/tmp/protocol47-assault-vector-sampler-live.json`, matching `.png`) measures
  12,000 ticks / 15,077 frames / 15,076 draws with the same 961 effects and CT
  round win at tick 4,413. Median is 8.309 ms, p95 10.740 ms, p99 13.075 ms,
  max 29.953 ms, and no frame exceeds 33 ms. Static memory is ~835→849 MB,
  loading 6.953 s, with zero freeze-control violations. Overall percentiles
  now meet the provisional target in this run, but opening windows 100–199
  and 200–299 still have p95 19.553/17.365 ms. The final capture retains the
  entrance-wall view, with no local shots or rescues. Broader camera, map,
  team, full-match and repeated-run coverage remains required.
- A clean muted stationary ten-actor volley run on Dust2
  (`/tmp/protocol47-firefight-vector-sampler.json`, matching `.png`) verifies
  all 1,500 sampled draws and 6,593 effects. Repeated-fire p95 is 18.414 ms,
  p99 20.822 ms, max 21.012 ms; the cold-M4 firing phase is p95 19.325 ms,
  max 22.679 ms. The separately measured weapon-switch CPU cost is 11.003 ms
  (7.276 ms preparing fire frames); it is not a complete switch-frame measurement.
  Visible ground-smoke firing is p95 9.229 ms, p99 11.382 ms, max 16.808 ms.
  No sampled phase has a frame above 33 ms. Capture inspection confirms the
  M4 and visible smoke in the open vista. Repeated/cold volleys still miss the
  p95 target; moving play with local firing, combined switch-frame latency,
  repeated distributions and long soaks remain open.

- A muted `--debug --profiling` stationary run
  (`/tmp/protocol47-volley-script-profile.log`, matching `.json`) attributes
  ~4.2 ms to nine character pose updates in sampled shooting frames and a
  further ~4.0 ms to a cold viewmodel-frame cache miss. Timings are nested,
  instrumented diagnostics, not clean GPU evidence. The new benchmark report
  explicitly labels instrumentation. Its cold-weapon first interval now begins
  before equipping, so it includes switch CPU, firing and the following render;
  the old phase timer started after equipping and missed the combined hitch.
- Fused body/gait sampling selects each vertex's source layer before blending,
  eliminating the two complete intermediate poses and discarded interpolation.
  It keeps the same masks, clocks, source frames and temporary-memory bound.
  Expanded tests cover 14,295 samples / 9,371,926 vertices / 38 templates,
  including all eight player skins' action/gait combinations and synthetic
  empty, all-upper, all-lower, mixed, coincident-frame and subrange cases.
  Composited results are bit-identical to the preceding two-pass **vector**
  sampler; maximum error against the independent double-scalar source reference
  is 0.000000111511 m (expanded coverage, still below one micrometre).
  The isolated 200-query comparison is 38.168 ms versus 70.994 ms; no noisy
  CPU timing threshold is added to the correctness gate. The six-fixture
  character group, subsequent expanded sampler check, 16 Node runner checks,
  and all five rendered fixtures pass. Body/gait, weapon, hostage and shadow
  pixel comparisons retain zero mismatches and working negative controls.
- The clean muted fused-composition volley rerun
  (`/tmp/protocol47-firefight-fused-composition.json`, matching inspected `.png`)
  renders all 1,500 samples and retains the same 6,593 emitted effects / 4,096
  retained events. First/repeated volleys are p95 17.363/18.677 ms, repeated
  p99 20.493 ms / max 20.962 ms. This does **not** establish a sustained-volley
  p95 improvement or satisfy the target. Cold-M4 firing is p95 19.508 ms;
  the newly included switch frame is 33.456 ms, versus 9.796 ms switch CPU.
  This is the only interval above 33 ms. Ground-smoke p95 is 9.311 ms,
  p99 10.809 ms, max 11.814 ms. Loading is 6.137 s, static memory ~894 MB.
  The inspected capture shows the M4 and visible smoke in the open Dust2 vista.
- Broader clean moving-combat evidence now includes Dust2 with local CT
  (`/tmp/protocol47-dust2-ct-fused-live.json`, matching inspected `.png`):
  12,000 ticks / 44,896 sampled frames / 44,895 draws, 558 effects, 16 local
  shots (AK and USP), 133.261 m of player travel and 31.174–149.118 m per bot.
  Bomb pickup/drop, planting, explosion and a round transition are observed;
  T wins by `target_bombed` at authoritative round tick 8,132. Overall median
  is 2.379 ms, p95 4.948 ms, p99 6.537 ms, max 29.068 ms (bomb explosion),
  with no frames above 33 ms or freeze-control violations. Every one-second
  window meets the p95 target; the worst is ticks 100–199 at 12.902 ms.
  Window counts sum to all 44,896 samples and 558 effects. Loading is 6.017 s,
  static memory ~895→912 MB. The final capture shows the local USP at an open
  site rather than the Assault entrance-wall view. This exercises a moving
  local player and one completed round, not a full match, all routes, both
  sides, all combat situations, or a long stability soak.

- Weapon loading now prepares immutable, shaded CPU geometry for frame zero
  of every unique source animation: 190 poses across 29 weapons, exactly
  32,777,424 bytes of packed geometry plus small container overhead. Work yields
  between poses before deployment. No additional animated nodes or tinted
  materials are retained, and later frames keep the existing bounded per-model
  cache. Prepared uploads bind the current instance's materials; muzzle
  projection is calculated for that instance, not shared across handedness/FOV.
  The first implementation incorrectly shared the muzzle projection; the
  all-weapon comparison exposed the knife's mirrored muzzle and this was fixed.
- The expanded weapon-load fixture checks all 190 prepared poses against
  independent source mesh construction: exact vertex/UV/normal/color arrays,
  material identity, muzzle parity, immutable cached colors, on-demand later
  frames, preparation without an equipped model, idempotence, and cache release.
  Both viewmodel fixtures and all 16 Node runner checks pass. All five rendered
  fixtures pass, including 106 drawn frames in the expanded viewmodel fixture
  at 07:31:50 UTC: zero prepared/unprepared mismatch for M4/knife/AK, with
  25,946/25,206/23,222 visible pixels and wrong-handed negative controls
  differing in 51,906/37,575/46,445 pixels. Each capture now checks draw progress.
- The clean muted initial-pose-preparation GPU run
  (`/tmp/protocol47-firefight-prepared-initial-poses.json`, matching inspected
  `.png`) renders all 1,500 samples with the same 6,593 effects / 4,096 retained
  events. Cold-switch CPU falls from 9.796 to 3.080 ms; fire-frame preparation
  is 0.604 ms rather than 7.463 ms. The complete switch-and-fire interval falls
  from 33.456 to 23.331 ms. Repeated-fire p95 is 18.558 ms, p99 20.245 ms,
  max 21.469 ms; cold-M4 firing p95 is 18.150 ms, p99 22.119 ms. Smoke firing
  is p95 9.081 ms / max 10.816 ms. No sample exceeds 33 ms. Loading increases
  from 6.137 to 7.368 s and static memory from ~894 to ~929 MB. The inspected
  capture retains the M4 and visible ground smoke. This improves the cold
  switch but does not satisfy heavy-volley p95 or the full smoothness gate.
- A second independent clean muted launch
  (`/tmp/protocol47-firefight-prepared-initial-poses-repeat.json`, matching `.png`)
  confirms the switch interval at 23.269 ms / CPU 2.912 ms. All 1,500 samples
  draw; effects remain 6,593; no interval exceeds 33 ms. Repeated-fire p95 is
  19.085 ms, p99 20.211 ms, max 21.191 ms, and cold-fire p95 is 19.137 ms.
  Loading is 7.363 s, static memory ~929 MB. Thus the switch improvement
  repeats, but heavy-volley p95 remains an unresolved gate. The full eighteen-
  group regression subsequently passed at 07:38:32 UTC with 72 completion
  markers and no detected errors/leaks, including the fused body/gait sampler
  and initial-pose preparation. Both from-spawn rescue selections repeat their
  four-rescue completions at ticks 9,240 (T) and 15,130 (CT).
- A test-only stationary `--diagnostic-hide=effect_lights` option now isolates
  light rendering while preserving creation, fixed-tick lifetimes, shot CPU,
  and other effects. It is off by default, explicitly recorded in the report,
  rejects other stationary exclusions, and passes the eight runner argument
  tests. With no concurrent CPU tests, `/tmp/protocol47-volley-no-lights-diagnostic.json`
  records all 1,500 draws and 6,593 effects: repeated-volley p95 16.429 ms,
  p99 18.897 ms versus normal p95 18.558/19.085 ms. Shot CPU p95 remains
  5.071 ms. Cold-volley p95 remains 17.213 ms. This suggests a rendering/light
  overhead contribution; it is **not** a production optimization or a passing
  smoothness result. Normal lights and rendering remain unchanged.
- With all lights/effects enabled, updated native Metal/Mobile
  (`/tmp/protocol47-volley-prepared-metal.json`, matching inspected `.png`)
  renders every one of 1,500 samples and emits the same 6,593 effects. Initial,
  repeated and cold volleys are p95 12.618/14.058/13.333 ms. Repeated p99 is
  15.950 ms / max 17.312 ms; the complete cold-switch interval is 18.195 ms.
  Smoke p95 is 9.343 ms / max 10.419 ms. No sample exceeds 33 ms. Loading is
  5.614 s, static memory ~944 MB. This is a process-local renderer override,
  not a production configuration change. The capture shows visibly brighter
  world lighting than Compatibility, so its speed does not establish acceptable
  visual fidelity or release readiness.
- The native Metal pose-sampler and offscreen-shadow fixtures pass (zero
  optimized/reference pixel mismatches; shadow 430 visible / 243 moving pixels).
  The following combat-effects fixture prints its pass marker but fails to exit:
  the strict runner terminates it after 90 seconds (`/tmp/protocol47-combat_effects_test-metal.log`).
  This is a **failed** check despite the printed marker. The remaining viewmodel
  and hostage fixtures were not reached in that run. Backend switching remains
  gated on shutdown stability as well as broader fidelity/performance checks.
- A new diagnostic `bsp_color_pipeline_probe.gd` isolates three constant
  albedo/lightmap inputs through the production BSP shader and a numerical
  constant-output reference shader. Both backends draw the swatches and match
  their respective numerical references exactly, but differ strongly from each
  other: the middle swatch is RGB ~116/83/28 on Compatibility versus 150/114/56
  on Metal. Reports: `/tmp/protocol47-bsp-color-gl_compatibility.json` and
  `/tmp/protocol47-bsp-color-mobile.json`. This local evidence attributes the
  difference to color-pipeline handling, not scene timing or changed textures.
  Godot documents different `OUTPUT_IS_SRGB` behavior for these backends in its
  [spatial shader reference](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html).
  The probe is not a GoldSrc-source-fidelity proof; a consistent intended display
  response and the Metal shutdown failure still need resolution before choosing
  a new production backend. No production shader or renderer setting changed.

- The previous effects shutdown timeout did not recur in 13 standalone warm
  reruns or a subsequent five-fixture Metal sequence. The first isolated-cache
  attempt's log contains a pass marker, but its runner result was not retained;
  its process is now absent, which does not establish a successful exit. A new
  isolated Godot user-data/cache run completed at 08:00:19 UTC with exit 0,
  no errors, no timeout, and 1,429 ms elapsed. Its durable result is
  `/tmp/protocol47-effects-metal-cold-verified-runner.json`, log
  `/tmp/protocol47-effects-metal-cold-verified.log`, and unique project/user-data
  name `protocol47-cold-metal-verified.VGNkc9`. Existing settings/caches were not
  deleted or changed. Shared import caches and Apple driver caches were not
  purged. No speculative shutdown fix or timeout relaxation was applied.
- BSP opaque and cutout materials now deliberately sample encoded WAD data,
  perform the existing authored lightmap/texture response in that same space,
  and decode only the final product when the backend expects linear output.
  Previously, `source_color` decoded the input only on linear renderers, while
  the shader applied the same nonlinear formulas and returned incompatible
  output values. Compatibility's response is preserved; this does not assert
  that the existing artistic response is a measured GoldSrc gamma-table match.
  In the original three swatches, Compatibility RGB remains 11/13/0,
  116/83/28, 216/208/185; updated Metal is 18/18/6, 115/84/31, 216/208/185,
  down from 46/44/22, 150/114/56, 230/221/200. Remaining low-end differences
  are not claimed as bit-identical cross-backend output. Godot's Compatibility
  [transfer-function approximations](https://github.com/godotengine/godot/blob/4.7-stable/drivers/gles3/shaders/tonemap_inc.glsl)
  help explain why a CPU exact-sRGB prediction differs from its final pixels.
- Expanded the color probe into a rendered contract regression: 13 inputs
  across opaque and half-masked materials, 312 actual draws per backend,
  independent CPU reference colors, per-capture draw guards, and legacy-shader
  controls. All 26 cases have zero reference mismatch pixels at the existing
  2/255 tolerance. Compatibility also has zero legacy mismatch pixels; Metal's
  old shader differs in 216,000 aggregate pixels. Both representative masked
  captures were inspected. This covers constant RGB samples and alpha-mask
  rendering, not all spatial filtering, map views, skies, or source fidelity.
- The rendered runner now accepts validated renderer/driver overrides and
  persists strict per-process results in separate backend reports. Unknown,
  repeated, and incompatible options fail before launch; all runs remain
  muted and always-on-top. All 19 Node runner checks pass. The full six-fixture
  Metal gate passes at 07:59:35 UTC, including normal effects shutdown in
  946 ms; the default Compatibility six-fixture gate also passes. Reports:
  `game/artifacts/render-test-mobile-metal-report.json` and
  `game/artifacts/render-test-default-default-report.json`. The post-shader
  map group passes all eight completion markers with no detected errors/leaks
  at 07:59:48 UTC (`game/artifacts/headless-test-selected-report.json`). The
  full 18-group report remains the pre-shader 07:38:32 result, not a fresh full
  regression claim.

- The corrected shader retains native Metal's stationary performance advantage
  in a clean, muted, draw-verified run with all lights/effects enabled:
  `/tmp/protocol47-volley-explicit-color-metal.json` and inspected `.png`.
  All 1,500 samples draw and the unchanged workload emits 6,593 effects with
  4,096 retained. Initial/repeated/cold volleys are p95 13.643/14.439/13.654 ms;
  repeated p99 is 15.493 ms / max 16.848 ms. The integrated switch-and-fire
  frame is 19.995 ms (switch CPU 4.917 ms). Smoke p95 is 9.593 ms, p99
  10.855 ms, max 12.165 ms. No sampled interval exceeds 33 ms. Loading is
  4.785 s; static memory ~944 MB. The real map capture now closely resembles
  the Compatibility world brightness, with visible smoke and muzzle flash;
  this is inspection, not a quantitative original-engine or all-view comparison.
- A separate clean post-change Compatibility run
  (`/tmp/protocol47-volley-explicit-color-gl.json`, inspected `.png`) renders
  the same 1,500 samples and emits 6,593 effects. Initial/repeated/cold p95 is
  18.474/18.789/18.942 ms; repeated p99 20.875 ms / max 24.641 ms. The
  integrated switch-and-fire interval is 27.437 ms (CPU 5.436 ms), smoke p95
  9.140 ms / max 12.858 ms, and no sample exceeds 33 ms. Loading is 7.673 s,
  static memory ~929 MB. The default-backend heavy-volley p95 gate therefore
  remains unmet; the passing Metal probe is not substituted for it. Both
  benchmark processes finish their capture and exit normally.

- A clean muted post-change Metal moving-match run
  (`/tmp/protocol47-dust2-ct-explicit-color-metal.json`, inspected `.png`)
  completes 12,000 physics ticks, 91,769 sampled frames and 91,768 draws.
  Normal bots, movement, damage, ammo, and objectives remain enabled: 558
  effects, 16 local shots (AK/USP), 133.262 m local travel, and 31.174–149.118 m
  per bot. T wins by bomb explosion at authoritative tick 8,132, then round two
  starts. Overall p95 is 3.291 ms, p99 4.480 ms, max 29.064 ms (the explosion);
  the reset interval is 25.929 ms. Every one-second window meets p95 16.7 ms;
  the worst is ticks 100–199 at 9.464 ms. Window totals account for all frames
  and 558 effects, with no intervals above 33 ms or freeze-control violations.
  Loading is 4.424 s, static memory ~944→968 MB. The final capture shows the
  USP at an open bombsite, not a stuck/wall-only view. The process exits cleanly.
  This is a completed round plus a partial second round on one map/team, not
  full-match ending/rematch, all-map coverage, multiplayer, or a long soak.

- Match-lifecycle integration previously stopped at injected halftime and
  match-end events. A new `match_lifecycle_test.gd` instead lets the MR15 kernel
  generate all transitions from actual actor eliminations, then sends Enter
  through the existing rematch input handler. It reproduced retained surviving
  rifles/armor at halftime, missing actor respawns on round-one rematch, retained
  dropped gear, and an unplayable dead local player in the new match. The first
  test had an incorrect spectator-camera-null assumption; this was corrected to
  check the persistent spectator service is disengaged and the player camera is
  current, rather than claimed as another production defect.
- Halftime/new-match boundaries now mark a fresh-loadout reset for the next
  `round_start`; ordinary rounds still preserve survivors' equipment. The
  rematch's round one now resets actors and drops too. Starting inventories clear
  equipment flags and the previous-weapon slot; halftime clears authoritative
  defuse kits. Eight cases passed at 08:09:40 UTC on both maps and starting
  teams, covering 16-win/dead-player and 15–15/surviving-player rematches
  (`/tmp/protocol47-match-lifecycle-matrix.json`). They verify the normal
  six-second freeze in the new match but accelerate previous freeze/post delays
  and disable actor AI/locomotion. These are lifecycle tests, not full-match
  navigation, objective, human-input, or smoothness soaks.
- Actual rendered lifecycle captures then exposed a stale MATCH OVER banner
  and kill feed still visible after rematch despite the new scores/health.
  A HUD reset now invalidates pending fades, kills active feedback tweens, and
  clears old announcements, objective text, radio, kill feed, damage and flash
  overlays. Actor respawns clear logical blindness too. The fixture checks these
  states and that an old active fade cannot hide a new announcement. The UI
  skill's referenced `uidotsh://ui` resource was unavailable; this targeted fix
  used the existing HUD code and native rendered captures, without changing
  layout or styling.
- Intentional Spectator selection was separately reproduced as broken: it did
  not start a match, left the local actor alive/solid, never acquired the chase
  camera, and skipped bot-side synchronization at halftime. The new observer
  fixture reproduced these through the menu signal and real kernel transitions
  (`/tmp/protocol47-observer-before.log`, nonzero exit). Selection now starts the
  match without class selection, disables local participation/collision/weapon
  rendering, and watches either team's living bots. Round/rematch boundaries
  preserve observer status; halftime mirrors the authoritative switched roster
  and spawn sides even without a participating local player. Joining CT restores
  the body and first-person camera. Bomb knowledge no longer labels an observer
  as T, and entering observation does not reset other bots' knowledge.
- The first observer implementation allowed alive live-round entry without a
  death. That assumption was rejected after checking the reference below, not
  accepted as source fidelity merely because the new regression passed.
  Focused round-state, Dust2 observer MR15, and existing death-camera
  tests pass with clean process exit. The spawn assertion was corrected to
  allow the existing floor-drop behavior, not counted as a production bug.
  The expanded full gate includes death spectating and both-map observer cases;
  the rendered gate now includes observer boundary captures. All are silent.
  These fixtures disable AI navigation/firing and accelerate phase delays: they
  do not prove full AI matches or smoothness. Nine bots remain when the human
  observes (no automatic bot backfill). Joining is tested during rematch freeze;
  live mid-round team-changing rules and roster preservation still need work.
- Inspected both backends' observer entry/rematch captures: chase-camera views
  draw the current target and the rematch clears old result/kill-feed text. The
  HUD still presents the local slot's health/ammo/radar while spectating, rather
  than a deliberate observer presentation. This is an open visual/interaction
  issue, not covered by the current observer-state assertions. Separately,
  `_on_team_selected` resets all bot actors and the class-menu deploy signal
  calls `start_match` unconditionally; live team changes need a regression that
  verifies round/roster continuity, not just the existing freeze-time direct
  handler test. No claim of complete spectator UI or live team switching yet.
- Follow-up source audit during the first full GPU run: HUD `_select_team(5)`
  converts Auto-assign to `1` before emitting `team_selected`, so the game's
  auto-assignment branch never receives that menu choice. The standalone
  `classic_ui_flow_test.gd` tests explicit CT selection but not Auto-assign.
  The round integration test directly emits team/class signals and expects all
  bots to respawn; it never calls HUD `_select_class`, which additionally emits
  `deploy_requested` into `start_match`. The observer join test also bypasses
  that deploy signal. Those passing tests therefore cannot establish live menu
  continuity. A follow-up regression must use the actual menu path, prohibit
  synthetic match/roster resets, and retain unrelated actors' identities,
  health, positions and equipment. Account for a legitimate local selection
  death and any resulting normal round outcome instead of requiring every
  state field to remain unchanged. Auto-assignment must reach game authority and
  show the class family of the accepted team. Source inspection also finds no
  live change-team key branch in `game._unhandled_input`, so live menu opening
  itself needs implementation/coverage. No production edits or additional
  runtime tests were made during the GPU timing run for this audit.
- Reference follow-up (September 8):
  [HandleMenu_ChooseTeam / HandleMenu_ChooseAppearance](https://raw.githubusercontent.com/rehlds/ReGameDLL_CS/master/regamedll/dlls/client.cpp)
  does not simply reject every living participant's team change. In the normal
  menu branch, an accepted selection invokes the player's death path before
  changing team, including same-team appearance selection. Dead players with a
  recorded team change are rejected from another change. Team capacity/stacking
  checks precede acceptance. Appearance selection updates the model and joining
  state or checks win conditions; it does not restart the match. This corrects
  any proposed test expecting an alive participant to survive all menu choices.
  Observer entry remains a separate freeze/dead restriction. Initial joining,
  post-death joining and the permitted spawn timing still need a complete
  reference trace before implementation; no new gameplay behavior is claimed.
  [SelectDefaultTeam](https://raw.githubusercontent.com/rehlds/ReGameDLL_CS/master/regamedll/dlls/multiplay_gamerules.cpp)
  chooses the smaller roster, then the losing side when counts tie, and only
  randomizes a remaining tie; it checks capacity and can return no available
  team. The non-ADD branch uses scores, while REGAMEDLL_ADD uses consecutive
  losses. The current game's unconditional coin flip does not cover this
  contract even after fixing HUD forwarding. Do not substitute that shortcut
  for source-faithful auto-assignment.
- The subsequent joining trace also distinguishes enrollment from spawning:
  [GetIntoGame](https://raw.githubusercontent.com/rehlds/ReGameDLL_CS/master/regamedll/dlls/player.cpp)
  marks the player joined, asks the game rules whether spawning is allowed,
  and otherwise enters observation while retaining the selected team.
  [FPlayerCanRespawn](https://raw.githubusercontent.com/rehlds/ReGameDLL_CS/master/regamedll/dlls/multiplay_gamerules.cpp)
  normally rejects a second spawn in the same round, a late join after the
  respawn window when both teams are populated, and an open appearance menu.
  Forced-respawn configuration changes those rules. This requires separate
  regressions for a new early join, a late join and a previously spawned dead
  participant; blindly calling `reset_player` for all three is not equivalent.
- Additional silent rendered observer runs on Assault also exited cleanly:
  Compatibility 11.533 s and Metal/Mobile 7.758 s (these overlap the headless
  gate and are correctness timings, not performance comparisons). Logs are
  `/tmp/protocol47-observer-assault-gl.log` and
  `/tmp/protocol47-observer-assault-metal.log`. Inspected Assault entry/rematch
  captures show the indoor T and outdoor CT spawn views across halftime; the
  same observer-HUD limitation remains visible.
- [ReGameDLL's HandleMenu_ChooseTeam](https://raw.githubusercontent.com/rehlds/ReGameDLL_CS/master/regamedll/dlls/client.cpp)
  only permits joined players to enter Spectator while frozen or dead. Alive
  freeze-time entry uses suicide but compensates the frag penalty, removes
  inventory, and resets money. The correction now rejects alive live/bomb-phase
  selection without changing C4/plant/defuse state. Initial deployment does not
  invent a death; freeze-time entry uses the existing actor death/drop path and
  counts one death without awarding another player a kill. Entering after death
  does not count another death. Observer accounts are zero, including rematch.
  Updated pure-state and Dust2 integration tests pass. Effective local viewmodel
  visibility is also checked, beyond the parent actor's visibility flag.
  Complete inventory-removal/HUD fidelity and live team-join rules remain open;
  inactive local inventory is currently discarded on rejoin/reset, not stripped
  completely by a dedicated observer inventory transition.
- Chase-camera presentation now has an explicit HUD state independent of target
  availability. It hides the inactive local vitals, ammo, money, radar/hostage
  indicators, crosshair, buy-zone icon, and damage vignette while retaining the
  match timer and notices. The spectator camera hides the local weapon anchor
  for death spectating too, and restores it on stop. Missing targets retain a
  generic `Spectating` label rather than restoring combat UI. Entry clears old
  flash/damage/nightvision presentation. The reference's
  [StartObserver](https://raw.githubusercontent.com/rehlds/ReGameDLL_CS/master/regamedll/dlls/player.cpp)
  hides health/weapons and holsters the local weapon; this does not claim a full
  reproduction of the original spectator VGUI, in-eye, map, or roaming modes.
- The observer HUD regression first failed on stale combat widgets. Expanded
  geometry checks and captured frames then caught this change's off-screen
  spectator label (absolute position had been used instead of bottom-anchor
  offsets). The offsets are corrected; tests cover logical viewport scaling,
  label/timer/objective separation at 640×480, 1024×768, and 1280×720, live HUD
  refreshes, pause/resume, no-target observation, and normal respawn restoration.
  The initial buy-zone test was corrected to use freeze eligibility, since live
  match updates intentionally clear it. The UI skill's referenced resource was
  unavailable; existing components and native captures were used instead.
  These are presentation/correctness checks, not new GPU timing evidence.
- Final current-code HUD/observer/match selected report is
  `game/artifacts/headless-test-selected-report.json` (17 markers; clean exits,
  no detected script errors or leaks). Both backend render reports contain
  eight successful fixtures, including the strengthened on-screen identity
  assertion. Inspected Compatibility entry/no-target and Metal rematch images
  show the corrected label/timer separation. The older off-screen captures
  were overwritten by the successful rerun, not accepted as visual evidence.
- Further observer integration still needs inventory-removal fidelity and
  team/class joining without restarting a running match or resetting all bots.
  Also, `game.gd` currently feeds the custom audio adapter from `player.camera`
  even when the chase camera owns the view; listener placement needs an actual
  camera-switch regression. Muting test playback does not verify spatial-audio
  correctness. These remaining issues are not hidden by the HUD fix.

Keep unresolved requirements intact. Passing a narrow regression or improving
one benchmark must not silently lower the release gate.
