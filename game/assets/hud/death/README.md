# Original death-notice sprites

Extracted from the local `public/sprites/classic/hud.txt` 640-resolution `d_*`
regions and their original GoldSrc `.spr` sheets; these are death-notice icons,
not the larger buy-menu / weapon-selection silhouettes.

Regenerate: `npm run game:import:hud:death` from the repository root.
`manifest.json` records each source sheet, SHA-256 and native dimensions.
White alpha masks are tinted warm gold by the HUD. Names retain team colors.
Unknown/world deaths use `d_skull`; HE/C4 damage uses `d_grenade`; headshots add
`d_headshot` after the weapon icon. No user-controlled texture paths are loaded.
