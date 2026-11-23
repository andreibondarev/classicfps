# Documentation index

These documents are working records, written while the game was being built.
Most are dated and describe the state at the time; check the date at the top
of each before relying on a status line.

| Document | What it is | Use it when |
| --- | --- | --- |
| [cs16-parity.md](cs16-parity.md) | The specification: what "faithful to CS 1.6" means system by system, with a gap matrix and links to the reference engine sources | Deciding how a mechanic should behave, or finding what is still missing |
| [production-readiness.md](production-readiness.md) | Evidence checklist for release, with a long dated log of fixes and their validation | Checking whether something was already fixed and how it was verified |
| [multiplayer-implementation-plan.md](multiplayer-implementation-plan.md) | Requirements and status for networked play: transport, snapshots, authority | Working on `network_session.gd` or anything replicated |
| [visual-rejection-report.md](visual-rejection-report.md) | Where rendering, HUD and audio still differ from the original, with the checks used | Working on visuals, HUD or sound fidelity |
| [dust2-combat-audit.md](dust2-combat-audit.md) | A September 2026 audit of combat on Dust2 | Background on combat fixes from that pass |

Elsewhere in the repository:

| Document | What it covers |
| --- | --- |
| [../README.md](../README.md) | Setup, layout and everyday commands |
| [../game/README.md](../game/README.md) | Controls, game rules, test and performance tooling, multiplayer menus, builds |
| [../deploy/README.md](../deploy/README.md) | Dedicated server, browser hosting, admin dashboard and moderation |
| [../shared/README.md](../shared/README.md) | Original assets, their provenance and licensing, demo fixtures |
| [../shared/goldsrc-crate/README.md](../shared/goldsrc-crate/README.md) | The Rust converters and demo parser |
| [../scripts/render-baseline/README.md](../scripts/render-baseline/README.md) | Rendered-test baselines |
