# Classic Counter-Strike sprite source

These files are the original Counter-Strike sprite definitions and binary
`.spr` assets staged from Valve's Steam application **90** on 2026-07-26:

```text
steamcmd
+@sSteamCmdForcePlatformType linux
+login anonymous
+app_update 90 validate
```

Source directories inside the validated depot:

```text
cstrike/sprites
valve/sprites
```

They are retained as the fidelity oracle and source for deterministic
conversion into Godot-ready images. Do not substitute redrawn approximations
when an original sprite exists.

The `valve/sprites` subset is limited to the combat temp-entity sources used
by Counter-Strike: `fexplo`, `eexplo`, `steam1`, `blood`, and `bloodspray`.
Their SHA-256 values are recorded by `scripts/import-game-vfx.sh`'s generated
manifest and can be rechecked against the validated depot.
