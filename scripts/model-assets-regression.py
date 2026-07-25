#!/usr/bin/env python3
"""Validate the complete stock Counter-Strike studio-model bundle."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "public" / "models"
EXPECTED_COUNTS = {
    "player": 9,
    "weapons": 103,
    "weapons/shield": 18,
    "classic": 56,
}
EXPECTED_WORLD_MODELS = {
    "w_9mmclip.mdl", "w_ak47.mdl", "w_antidote.mdl", "w_assault.mdl",
    "w_aug.mdl", "w_awp.mdl", "w_backpack.mdl", "w_battery.mdl",
    "w_c4.mdl", "w_deagle.mdl", "w_elite.mdl",
    "w_famas.mdl", "w_fiveseven.mdl", "w_flashbang.mdl", "w_g3sg1.mdl",
    "w_galil.mdl", "w_glock18.mdl", "w_hegrenade.mdl", "w_kevlar.mdl",
    "w_knife.mdl", "w_longjump.mdl", "w_m249.mdl", "w_m3.mdl", "w_m4a1.mdl",
    "w_mac10.mdl", "w_mp5.mdl", "w_p228.mdl", "w_p90.mdl",
    "w_scout.mdl", "w_security.mdl", "w_sg550.mdl", "w_sg552.mdl",
    "w_shield.mdl", "w_shotbox.mdl", "w_smokegrenade.mdl", "w_thighpack.mdl",
    "w_tmp.mdl", "w_ump45.mdl", "w_usp.mdl", "w_weaponbox.mdl",
    "w_xm1014.mdl",
}


def files_below(path: Path) -> list[Path]:
    return sorted(path.rglob("*.mdl"))


def main() -> int:
    players = files_below(MODELS / "player")
    shield = files_below(MODELS / "weapons" / "shield")
    weapon_root = sorted((MODELS / "weapons").glob("*.mdl"))
    classic = files_below(MODELS / "classic")
    groups = {
        "player": players,
        "weapons": weapon_root,
        "weapons/shield": shield,
        "classic": classic,
    }
    errors: list[str] = []
    for name, expected in EXPECTED_COUNTS.items():
        actual = len(groups[name])
        if actual != expected:
            errors.append(f"{name}: expected {expected}, found {actual}")

    world = {path.name for path in weapon_root if path.name.startswith("w_")}
    missing_world = sorted(EXPECTED_WORLD_MODELS - world)
    if missing_world:
        errors.append(f"missing world models: {', '.join(missing_world)}")

    all_models = players + weapon_root + shield + classic
    for path in all_models:
        with path.open("rb") as model:
            if model.read(4) not in {b"IDST", b"IDSQ"}:
                errors.append(f"invalid GoldSrc studio header: {path.relative_to(ROOT)}")

    print(
        f"Models: {len(all_models)} total; {len(players)} player; "
        f"{len(weapon_root)} weapon; {len(shield)} shield; {len(classic)} classic"
    )
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return 1
    print("Model asset regression: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
