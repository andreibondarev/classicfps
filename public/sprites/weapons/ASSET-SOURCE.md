# Counter-Strike weapon HUD silhouettes

These transparent masks were extracted from the `weapon_s` regions declared by
the original Counter-Strike 1.6 `cstrike/sprites/weapon_*.txt` files and their
corresponding `640hud*.spr` sheets. The source installation was obtained from
Valve's official HLDS App 90 through SteamCMD.

Regenerate them with:

```sh
venv/bin/python scripts/extract-weapon-hud-icons.py \
  /path/to/cstrike/sprites public/sprites/weapons
```
