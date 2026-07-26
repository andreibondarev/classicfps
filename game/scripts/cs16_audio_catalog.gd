class_name CS16AudioCatalog
extends RefCounted

const MATERIALS_PATH := "res://assets/sounds/classic/materials.txt"
const SOUND_ROOT := "res://assets/sounds/classic"

const CONCRETE := "C"
const METAL := "M"
const VENT := "V"
const DIRT := "D"
const SLOSH := "S"
const TILE := "T"
const GRATE := "G"
const WOOD := "W"
const COMPUTER := "P"
const GLASS := "Y"
const SNOW := "N"
const GRASS := "X"

const FOOTSTEP_FAMILIES := {
	CONCRETE: {"prefix": "pl_step", "count": 4},
	METAL: {"prefix": "pl_metal", "count": 4},
	VENT: {"prefix": "pl_duct", "count": 4},
	DIRT: {"prefix": "pl_dirt", "count": 4},
	SLOSH: {"prefix": "pl_slosh", "count": 4},
	TILE: {"prefix": "pl_tile", "count": 5},
	GRATE: {"prefix": "pl_grate", "count": 4},
	# GoldSrc falls these less common classes back to one of its stock step
	# families; CS does not ship a separate pl_wood/pl_glass/pl_computer set.
	WOOD: {"prefix": "pl_step", "count": 4},
	COMPUTER: {"prefix": "pl_metal", "count": 4},
	GLASS: {"prefix": "pl_tile", "count": 5},
	SNOW: {"prefix": "pl_snow", "count": 6},
	GRASS: {"prefix": "pl_dirt", "count": 4},
}

const EVENT_SAMPLES := {
	"p228.fire": ["weapons/p228-1.wav"],
	"scout.fire": ["weapons/scout_fire-1.wav"],
	"xm1014.fire": ["weapons/xm1014-1.wav"],
	"mac10.fire": ["weapons/mac10-1.wav"],
	"aug.fire": ["weapons/aug-1.wav"],
	"elite.fire": ["weapons/elite_fire.wav"],
	"fiveseven.fire": ["weapons/fiveseven-1.wav"],
	"ump45.fire": ["weapons/ump45-1.wav"],
	"sg550.fire": ["weapons/sg550-1.wav"],
	"galil.fire": ["weapons/galil-1.wav", "weapons/galil-2.wav"],
	"famas.fire": ["weapons/famas-1.wav", "weapons/famas-2.wav"],
	"famas.fire_burst": ["weapons/famas-burst.wav"],
	"glock18.fire": ["weapons/glock18-1.wav", "weapons/glock18-2.wav"],
	"glock18.fire_burst": ["weapons/glock18-1.wav"],
	"usp.fire": ["weapons/usp_unsil-1.wav"],
	"usp.fire_silenced": ["weapons/usp1.wav", "weapons/usp2.wav"],
	"usp.silencer_on": ["weapons/usp_silencer_on.wav"],
	"usp.silencer_off": ["weapons/usp_silencer_off.wav"],
	"awp.fire": ["weapons/awp1.wav"],
	"mp5.fire": ["weapons/mp5-1.wav", "weapons/mp5-2.wav"],
	"m249.fire": ["weapons/m249-1.wav", "weapons/m249-2.wav"],
	"m3.fire": ["weapons/m3-1.wav"],
	"m4a1.fire": ["weapons/m4a1_unsil-1.wav", "weapons/m4a1_unsil-2.wav"],
	"m4a1.fire_silenced": ["weapons/m4a1-1.wav"],
	"m4a1.silencer_on": ["weapons/m4a1_silencer_on.wav"],
	"m4a1.silencer_off": ["weapons/m4a1_silencer_off.wav"],
	"tmp.fire": ["weapons/tmp-1.wav", "weapons/tmp-2.wav"],
	"g3sg1.fire": ["weapons/g3sg1-1.wav"],
	"sg552.fire": ["weapons/sg552-1.wav", "weapons/sg552-2.wav"],
	"p90.fire": ["weapons/p90-1.wav"],
	"ak47.fire": ["weapons/ak47-1.wav", "weapons/ak47-2.wav"],
	"ak47.clip_out": ["weapons/ak47_clipout.wav"],
	"ak47.clip_in": ["weapons/ak47_clipin.wav"],
	"ak47.bolt": ["weapons/ak47_boltpull.wav"],
	"deagle.fire": ["weapons/deagle-1.wav", "weapons/deagle-2.wav"],
	"deagle.clip_out": ["weapons/de_clipout.wav"],
	"deagle.clip_in": ["weapons/de_clipin.wav"],
	"deagle.deploy": ["weapons/de_deploy.wav"],
	"knife.slash": ["weapons/knife_slash1.wav", "weapons/knife_slash2.wav"],
	"knife.hit": [
		"weapons/knife_hit1.wav",
		"weapons/knife_hit2.wav",
		"weapons/knife_hit3.wav",
		"weapons/knife_hit4.wav",
	],
	"knife.hit_wall": ["weapons/knife_hitwall1.wav"],
	"knife.stab": ["weapons/knife_stab.wav"],
	# v_hegrenade.mdl sequence event 5004, frame 27 at 41 fps.
	"he.pull_pin": ["weapons/pinpull.wav"],
	# CGrenade::BounceSound selects the CS-specific sample for HE damage > 50.
	"he.bounce": ["weapons/he_bounce-1.wav"],
	"he.explode": [
		"weapons/explode3.wav",
		"weapons/explode4.wav",
		"weapons/explode5.wav",
	],
	"he.debris": [
		"weapons/debris1.wav",
		"weapons/debris2.wav",
		"weapons/debris3.wav",
	],
	"weapon.empty_pistol": ["weapons/dryfire_pistol.wav"],
	"weapon.empty_rifle": ["weapons/dryfire_rifle.wav"],
	"weapon.zoom": ["weapons/zoom.wav"],
	"player.pain": [
		"player/pl_pain2.wav",
		"player/pl_pain4.wav",
		"player/pl_pain5.wav",
		"player/pl_pain6.wav",
		"player/pl_pain7.wav",
	],
	"player.death": [
		"player/die1.wav",
		"player/die2.wav",
		"player/die3.wav",
		"player/death6.wav",
	],
	"player.headshot_death": [
		"player/headshot1.wav",
		"player/headshot2.wav",
		"player/headshot3.wav",
	],
	"c4.plant": ["weapons/c4_plant.wav"],
	"c4.beep1": ["weapons/c4_beep1.wav"],
	"c4.beep2": ["weapons/c4_beep2.wav"],
	"c4.beep3": ["weapons/c4_beep3.wav"],
	"c4.beep4": ["weapons/c4_beep4.wav"],
	"c4.beep5": ["weapons/c4_beep5.wav"],
	"c4.explode": ["weapons/c4_explode1.wav"],
	"radio.bomb_planted": ["radio/bombpl.wav"],
	"round.ct_win": ["radio/ctwin.wav"],
	"round.t_win": ["radio/terwin.wav"],
	"round.draw": ["radio/rounddraw.wav"],
}

static var _material_types: Dictionary = {}


static func material_code(texture_name: String) -> String:
	_ensure_material_types()
	var normalized := texture_name.strip_edges().to_lower().substr(0, 12)
	match normalized:
		"concrete":
			return CONCRETE
		"metal":
			return METAL
		"vent":
			return VENT
		"dirt":
			return DIRT
		"slosh":
			return SLOSH
		"tile":
			return TILE
		"grate":
			return GRATE
		"wood":
			return WOOD
		"computer":
			return COMPUTER
		"glass":
			return GLASS
		"snow":
			return SNOW
		"grass":
			return GRASS
	var literal_code := normalized.to_upper()
	if normalized.length() == 1 and FOOTSTEP_FAMILIES.has(literal_code):
		return literal_code
	return str(_material_types.get(normalized, CONCRETE))


static func footstep_sample(texture_name: String, step_index: int) -> String:
	var family: Dictionary = FOOTSTEP_FAMILIES.get(
		material_code(texture_name),
		FOOTSTEP_FAMILIES[CONCRETE],
	)
	var count := int(family.count)
	var sample_index := posmod(step_index, count) + 1
	return "%s/player/%s%d.wav" % [SOUND_ROOT, str(family.prefix), sample_index]


static func event_sample(event_name: String, variant_index := 0) -> String:
	var variants: Array = EVENT_SAMPLES.get(event_name, [])
	if variants.is_empty():
		return ""
	return "%s/%s" % [SOUND_ROOT, str(variants[posmod(variant_index, variants.size())])]


static func footstep_descriptor(
	texture_name: String,
	left_foot: bool,
	volume: float,
) -> Dictionary:
	var code := material_code(texture_name)
	var family: Dictionary = FOOTSTEP_FAMILIES.get(
		code,
		FOOTSTEP_FAMILIES[CONCRETE],
	)
	var prefix := str(family.prefix)
	var count := int(family.count)
	var indices := [2, 4] if left_foot else [1, 3]
	var samples: Array[String] = []
	for index in indices:
		if index <= count:
			samples.append("player/%s%d.wav" % [prefix, index])
	# Tile's fifth variant is selected one time in five by PM_PlayStepSound.
	# Keep it in the descriptor so the original sample is addressable; exact
	# one-in-five scheduling remains owned by the live footstep state machine.
	if code == TILE and count >= 5:
		samples.append("player/%s5.wav" % prefix)
	return {
		"samples": samples,
		"channel": 4, # CHAN_BODY; kept numeric to avoid a catalog/router cycle.
		"volume": clampf(volume, 0.0, 1.0),
		"attenuation": 0.8,
		"pitch_min": 100,
		"pitch_max": 100,
		"flags": 0,
	}


static func footstep_volume(texture_name: String) -> float:
	match material_code(texture_name):
		DIRT:
			return 0.55
		VENT:
			return 0.7
	return 0.5


static func _ensure_material_types() -> void:
	if not _material_types.is_empty():
		return
	var file := FileAccess.open(MATERIALS_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing CS material sound table: %s" % MATERIALS_PATH)
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		var separator := line.find(" ")
		if separator <= 0:
			continue
		var code := line.substr(0, separator).strip_edges().to_upper()
		var texture := line.substr(separator + 1).strip_edges().to_lower().substr(0, 12)
		if code.length() == 1 and not texture.is_empty():
			_material_types[texture] = code
