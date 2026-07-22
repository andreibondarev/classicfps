# Counter-Strike sound assets

The WAV files in this directory come from Valve's official HLDS App 90,
downloaded through SteamCMD.

The bundle includes the complete `cstrike/sound` tree. Counter-Strike inherits
environmental and mechanical audio from Half-Life, so the playback-relevant
`valve/sound` categories are included as well: `ambience`, `buttons`, `common`,
`debris`, `doors`, `fans`, `items`, `misc`, `plats`, `player`, and `weapons`.
Counter-Strike files override base files at the same relative path, matching the
GoldSrc search order.

Half-Life-only creature and NPC dialogue is intentionally excluded because it
cannot be referenced by standard Counter-Strike demos or maps in this player.
