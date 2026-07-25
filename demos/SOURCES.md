# Demo sources

## `csdm-2607120107-de_aztec.dem`

- Source: KICK.LV CSDM HLTV demo archive
- Recording date: 2026-07-12
- Source page: https://www.kick.lv/demo_csdm
- SHA-256: `4bf7707cd6702f62f82041bf0f2fc790bb5d01d47c613cd934f3c50a5292ca44`

The matching `public/maps/de_aztec.bsp` was downloaded from the MODS.vg
`de_aztec` map entry:

- Source page: https://mods.vg/download/de-aztec
- SHA-256: `6a9c1c472ad01283098760314cb8744552e5f3a6493108ab5e19075216a3f9ed`

## `de_prodigy` map assets

The original map and its textures were imported from Valve's Counter-Strike
dedicated-server distribution using SteamCMD app 90.

- `public/maps/de_prodigy.bsp`
  - SHA-256: `b345bd3f97babab19e026ebb8ae46c9d1be2b7a7da0acc12dbf1816c8a4ced7e`
- `public/wads/prodigy_map.wad`
  - SHA-256: `0e68198578bfefda100c906f2273535a5dde442d50727f5de8fb278a265a9d85`

`prodigy_map.wad` is a lossless subset containing the 214 textures referenced
by `de_prodigy.bsp`, selected from Valve's `halflife.wad`, `cstrike.wad`, and
`prodigy.wad`. Unreferenced texture lumps were omitted to keep the web payload
small; the selected texture data was not modified.

The same Valve distribution supplied seven stock Half-Life world models
precached by the historical EXE HLTV recordings:

- `w_9mmclip.mdl`
- `w_antidote.mdl`
- `w_battery.mdl`
- `w_longjump.mdl`
- `w_security.mdl`
- `w_shotbox.mdl`
- `w_weaponbox.mdl`

They are served from `public/models/weapons/`, alongside the other `w_` studio
models expected by the player.

## Historical professional `de_aztec` demos

The following demos came from Nicolas Scheidler's CS 1.6 Demo Library. The
published archive contains 6,599 files plus a separate 4Players collection and
uses the access password `rejoined`.

- Archive page: https://icedrive.net/s/ZttVfR65akBNfif1gZzYa9fCRXQC
- Archive description: https://community.rejoined.de/t/cs-1-6/443

### NiP vs 4Kings — CPL Winter 2002

Original package: `HeatoN vs. 4Kings de_aztec - CPL Winter 2002.zip`

- `pro-2002-cpl-nip-vs-4kings-de_aztec-part1.dem`
  - SHA-256: `b7af1539e4e1a40941f9cc6d2a3a0093be8f5cfaff785c891c5deeb0fc49508b`
- `pro-2002-cpl-nip-vs-4kings-de_aztec-part2.dem`
  - SHA-256: `72d601de01b0e7beb7fe150347da050c2baed0eb9e174d5226ffe24698efc38d`

### 4Kings vs Forsaken — 2003

Original package: `4kingsvsforsaken-aztec-hltv.zip`

- `pro-2003-4kings-vs-forsaken-de_aztec-part1.dem`
  - SHA-256: `f547ba7a3ce3c99f04e0592a2f52921a6ce7c44fabf52944abfd1060d036ede0`

The package's other half was rejected because it contains only three usable
positional samples.

### eoLithic vs Ocrana.fi — ClanBase EuroCup VI, 2003

Original package: `eoLithic-Ocrana.fi cbble-aztec.zip`

- `pro-2003-eurocup6-eolithic-vs-ocrana-de_aztec.dem`
  - SHA-256: `8796c0cb2a93c0443bf5f6e8a33145c6ae2143a2ca46fa60ce19238d060f2c08`

### mousesports vs a-Losers — 2003

Original package: `mousesports-aLoser aztec.zip`

- `pro-2003-mousesports-vs-alosers-de_aztec-part1.dem`
  - SHA-256: `2269beae42c51883826c5aff8058899aae4a9d934df8f2db83a71ea7d93ee6cf`
- `pro-2003-mousesports-vs-alosers-de_aztec-part2.dem`
  - SHA-256: `3d9f09b357f9ea26fc1b808e5be4b8619761e1220227d882ca87f3172ec1ac17`

### M19 vs Virtus.pro — 2004

Original package: `m19-vs-virtus-aztec-0402072336-de_aztec (1).zip`

- `pro-2004-m19-vs-virtuspro-de_aztec.dem`
  - SHA-256: `7554ffc6a21ff2bc14fc6d17cb706035aea18471eed69ff0d8880ca3c7f898b1`
