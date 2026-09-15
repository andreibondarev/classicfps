# Dust2 combat audit — September 13, 2026

Source build only; the download ZIP and social video were not rebuilt.

## Implemented

- Dropped C4 appears as a blinking red radar square; planted C4 uses an X.
  Only living Terrorists see these contacts. Pickup, death, team changes,
  resolution and round resets clear them. Network clients use persistent world
  items plus bomb state, so late joins do not depend on replaying drop events.
- Twelve automatic weapons now use their own accuracy growth, stance-dependent
  spread and seven-parameter recoil tables. Trigger release recovers the stored
  shot count incrementally instead of abruptly resetting the whole burst.
- Six pistols use individual refire/recovery constants and spread coefficients.
  Silenced USP/M4 and burst Glock/FAMAS use their respective spread variants.
  Glock retains viewmodel motion without artificial camera punch.
- AWP/Scout movement and unscoped penalties, G3SG1/SG550 refire accuracy, and
  shotgun recoil ranges follow the source formulas. FAMAS follow-up timing is
  corrected; burst follow-ups no longer add a second primary-shot recoil step.
- Human and bot bullet hit-group classification shares victim-local axes and
  posture-aware head heights. This fixes standing-only crouched headshot
  classification and world-axis-dependent left/right body labels.
- MP5 kill notices map the internal `mp5` ID to the original `mp5navy` sprite.

## Reference and limits

Weapon values were checked against [ReGameDLL_CS weapon implementations](https://github.com/rehlds/ReGameDLL_CS/tree/master/regamedll/dlls/wpn_shared),
[shared weapon logic](https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/weapons.cpp)
and [shared random helpers](https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/util.cpp).
Automatic accuracy uses floating-point divisors from `REGAMEDLL_FIXES`, consistent
with this project's existing AK implementation, not the older integer-division
variant. Radar visibility/markers follow [CS16Client radar](https://github.com/Velaron/cs16-client/blob/master/cl_dll/hud/radar.cpp).

This is **not complete vanilla weapon or anatomical hitbox parity**. Shots still
intersect movement colliders, not the original animated MDL bone-attached boxes.
Bot crouch collision and aim/recoil behavior need further work. Shared RNG seeds,
tick quantization, and some remaining special-case weapon damage/timing behavior
(including FAMAS follow-up damage) are not a frame-exact engine reproduction.

## Verification

Muted headless fixtures passed for combat fidelity, ballistics, bot combat,
Glock input, weapon timing, human network inventory, grenade feedback, weapon
actions, live audio and knife/silencer behavior. The new combat-fidelity fixture
is included in `npm run game:test:ballistics` and covers the production host HUD
and client snapshot application paths, including late-join and cleanup cases.

A real two-process Dust2 host/client test passed, including remote inventory,
combat and C4 drops/pickup. Artifacts:
`/var/folders/9y/b4wfvjjj7c30rs6464rcxtvm0000gn/T/protocol47-network-EsMOrl`.
The muted native fidelity fixture passed and its radar capture was inspected:
`/tmp/protocol47-radar-drop.png`.

## GPU measurements

Apple M1 Max, 1280×720, Compatibility renderer, audio driver Dummy. No rendering
exclusions in the following runs. Times are milliseconds, lower is better.

| Clean final stationary scenario | p95 | p99 | Worst | Frames >33.3 ms |
| --- | ---: | ---: | ---: | ---: |
| Ten-actor firefight | 15.304 | 16.841 | 18.462 | 0 |
| Repeated firefight | 15.605 | 16.774 | 17.800 | 0 |
| Cold M4 switch/firefight | 15.298 | 18.937 | 22.397 | 0 |
| Smoke firefight | 10.934 | 13.373 | 14.385 | 0 |

Report: `/tmp/protocol47-dust2-firefight-final.json`. The stationary fixture
disables AI/movement and uses synchronized volleys; it is not a live-match test.
An earlier run reached 47.596 ms on cold-weapon firing. Run-to-run variation is
not evidence of a performance fix; this pass makes no optimization claim.

The initial 90-second moving 5v5 sample measured p95 9.593 ms, p99 11.895 ms,
worst 89.305 ms, with seven frames above 33.3 ms. It included 30 local shots and
one completed round. Report: `/tmp/protocol47-dust2-moving-audit.json`.
A diagnostic phase-profile repeat did not reproduce those late spikes (one
44.959 ms initial frame); its match trajectory differed and part of loading
overlapped a headless transport test, so it is not a clean before/after comparison.

The clean final moving repeat covered 9,000 physics ticks (90 seconds), 18,993
rendered frames and 20 local shots: p95 **8.300 ms**, p99 **9.955 ms**, worst
**74.307 ms**, with **14 frames above 33.3 ms**. No complete round occurred in this
sample. Report: `/tmp/protocol47-dust2-moving-final.json`. There was no overlapping
game test/benchmark, no instrumentation and no render exclusions in this repeat.
Several spikes occurred without new combat effects; the cause is not established.

Occasional live-match spikes remain unresolved. These checks do not establish a
full-match smoothness pass or release readiness; the performance item remains open.
