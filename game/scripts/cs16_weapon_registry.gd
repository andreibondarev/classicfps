class_name CS16WeaponRegistry
extends RefCounted

## Authoritative Counter-Strike 1.6 weapon/equipment definitions.
##
## Values are transcribed from ReGameDLL_CS `weapons.h`, `weapontype.cpp`,
## `player.cpp`, and the individual `wpn_*.cpp` implementations. Distances
## remain in GoldSrc units here; consumers convert them at their boundary.

const TEAM_BOTH := ["T", "CT"]
const TEAM_T := ["T"]
const TEAM_CT := ["CT"]

const ROSTER := [
	"p228", "scout", "hegrenade", "xm1014", "c4", "mac10", "aug",
	"smokegrenade", "elite", "fiveseven", "ump45", "sg550", "galil",
	"famas", "usp", "glock18", "awp", "mp5", "m249", "m3", "m4a1",
	"tmp", "g3sg1", "flashbang", "deagle", "sg552", "ak47", "knife", "p90",
]

const AMMO := {
	"buckshot": {"reserve_max": 32, "box": 8, "price": 65},
	"9mm": {"reserve_max": 120, "box": 30, "price": 20},
	"556nato": {"reserve_max": 90, "box": 30, "price": 60},
	"556natobox": {"reserve_max": 200, "box": 30, "price": 60},
	"762nato": {"reserve_max": 90, "box": 30, "price": 80},
	"45acp": {"reserve_max": 100, "box": 12, "price": 25},
	"50ae": {"reserve_max": 35, "box": 7, "price": 40},
	"338mag": {"reserve_max": 30, "box": 10, "price": 125},
	"57mm": {"reserve_max": 100, "box": 50, "price": 50},
	"357sig": {"reserve_max": 52, "box": 13, "price": 50},
}

# Common fields:
# id/name/category/slot/team/price/ammo/magazine/reserve/max_speed/automatic
# primary/reload/damage/range_modifier/range_units/penetrations/bullet/armor
# pellets/secondary/zoom_speed. `mode` is the classic HUD-facing label.
const WEAPONS := {
	"p228": {"id": 1, "name": "228 COMPACT", "category": "pistol", "slot": 2, "team": TEAM_BOTH, "price": 600, "ammo": "357sig", "magazine": 13, "reserve": 52, "max_speed": 250.0, "automatic": false, "primary": 0.15, "reload": 2.7, "damage": 32, "range_modifier": 0.8, "range_units": 4096.0, "penetrations": 1, "bullet": "357sig", "armor": 1.25, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "SEMI AUTO"},
	"scout": {"id": 3, "name": "SCHMIDT SCOUT", "category": "sniper", "slot": 1, "team": TEAM_BOTH, "price": 2750, "ammo": "762nato", "magazine": 10, "reserve": 90, "max_speed": 260.0, "automatic": false, "primary": 1.25, "reload": 2.0, "damage": 75, "range_modifier": 0.98, "range_units": 8192.0, "penetrations": 3, "bullet": "762mm", "armor": 1.7, "pellets": 1, "secondary": "zoom", "zoom_levels": [90, 40, 15], "zoom_speed": 220.0, "mode": "BOLT ACTION"},
	"hegrenade": {"id": 4, "name": "HE GRENADE", "category": "grenade", "slot": 4, "team": TEAM_BOTH, "price": 300, "ammo": "hegrenade", "magazine": 1, "reserve": 0, "reserve_max": 1, "max_speed": 250.0, "automatic": false, "primary": 1.0, "reload": 0.0, "damage": 100, "range_modifier": 1.0, "range_units": 350.0, "penetrations": 0, "bullet": "", "armor": 1.0, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "THROW"},
	"xm1014": {"id": 5, "name": "LEONE YG1265 AUTO SHOTGUN", "category": "shotgun", "slot": 1, "team": TEAM_BOTH, "price": 3000, "ammo": "buckshot", "magazine": 7, "reserve": 32, "max_speed": 240.0, "automatic": true, "primary": 0.25, "reload": 0.55, "reload_insert": 0.3, "damage": 20, "range_modifier": 1.0, "range_units": 3048.0, "penetrations": 0, "bullet": "buckshot", "armor": 1.0, "pellets": 6, "cone": 0.0725, "secondary": "none", "zoom_speed": 240.0, "mode": "AUTO SHOTGUN"},
	"c4": {"id": 6, "name": "C4 EXPLOSIVE", "category": "objective", "slot": 5, "team": TEAM_T, "price": 0, "ammo": "c4", "magazine": 1, "reserve": 0, "reserve_max": 1, "max_speed": 250.0, "automatic": false, "primary": 0.3, "arming": 3.0, "deploy": 0.75, "reload": 0.0, "damage": 500, "range_modifier": 1.0, "range_units": 1750.0, "penetrations": 0, "bullet": "", "armor": 1.0, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "PLANT"},
	"mac10": {"id": 7, "name": "INGRAM MAC-10", "category": "smg", "slot": 1, "team": TEAM_T, "price": 1400, "ammo": "45acp", "magazine": 30, "reserve": 100, "max_speed": 250.0, "automatic": true, "primary": 0.07, "reload": 3.15, "damage": 29, "range_modifier": 0.82, "range_units": 8192.0, "penetrations": 1, "bullet": "45acp", "armor": 0.95, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "FULL AUTO"},
	"aug": {"id": 8, "name": "BULLPUP", "category": "rifle", "slot": 1, "team": TEAM_CT, "price": 3500, "ammo": "556nato", "magazine": 30, "reserve": 90, "max_speed": 240.0, "automatic": true, "primary": 0.0825, "zoom_primary": 0.135, "reload": 3.3, "damage": 32, "range_modifier": 0.96, "range_units": 8192.0, "penetrations": 2, "bullet": "556mm", "armor": 1.4, "pellets": 1, "secondary": "zoom", "zoom_levels": [90, 55], "zoom_speed": 240.0, "mode": "FULL AUTO"},
	"smokegrenade": {"id": 9, "name": "SMOKE GRENADE", "category": "grenade", "slot": 4, "team": TEAM_BOTH, "price": 300, "ammo": "smokegrenade", "magazine": 1, "reserve": 0, "reserve_max": 1, "max_speed": 250.0, "automatic": false, "primary": 1.0, "reload": 0.0, "damage": 0, "range_modifier": 1.0, "range_units": 0.0, "penetrations": 0, "bullet": "", "armor": 1.0, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "THROW"},
	"elite": {"id": 10, "name": "ELITE", "category": "pistol", "slot": 2, "team": TEAM_T, "price": 800, "ammo": "9mm", "magazine": 30, "reserve": 120, "max_speed": 250.0, "automatic": false, "primary": 0.122, "reload": 4.5, "damage": 36, "range_modifier": 0.75, "range_units": 8192.0, "penetrations": 1, "bullet": "9mm", "armor": 1.05, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "SEMI AUTO"},
	"fiveseven": {"id": 11, "name": "ES FIVE-SEVEN", "category": "pistol", "slot": 2, "team": TEAM_CT, "price": 750, "ammo": "57mm", "magazine": 20, "reserve": 100, "max_speed": 250.0, "automatic": false, "primary": 0.15, "reload": 2.7, "damage": 20, "range_modifier": 0.885, "range_units": 4096.0, "penetrations": 1, "bullet": "57mm", "armor": 1.5, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "SEMI AUTO"},
	"ump45": {"id": 12, "name": "KM UMP45", "category": "smg", "slot": 1, "team": TEAM_BOTH, "price": 1700, "ammo": "45acp", "magazine": 25, "reserve": 100, "max_speed": 250.0, "automatic": true, "primary": 0.1, "reload": 3.5, "damage": 30, "range_modifier": 0.82, "range_units": 8192.0, "penetrations": 1, "bullet": "45acp", "armor": 1.0, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "FULL AUTO"},
	"sg550": {"id": 13, "name": "KRIEG 550 COMMANDO", "category": "sniper", "slot": 1, "team": TEAM_CT, "price": 4200, "ammo": "556nato", "magazine": 30, "reserve": 90, "max_speed": 210.0, "automatic": true, "primary": 0.25, "reload": 3.35, "damage": 70, "range_modifier": 0.98, "range_units": 8192.0, "penetrations": 2, "bullet": "556mm", "armor": 1.45, "pellets": 1, "secondary": "zoom", "zoom_levels": [90, 40, 15], "zoom_speed": 150.0, "mode": "SEMI AUTO"},
	"galil": {"id": 14, "name": "IDF DEFENDER", "category": "rifle", "slot": 1, "team": TEAM_T, "price": 2000, "ammo": "556nato", "magazine": 35, "reserve": 90, "max_speed": 240.0, "automatic": true, "primary": 0.0875, "reload": 2.45, "damage": 30, "range_modifier": 0.98, "range_units": 8192.0, "penetrations": 2, "bullet": "556mm", "armor": 1.55, "pellets": 1, "secondary": "none", "zoom_speed": 240.0, "mode": "FULL AUTO"},
	"famas": {"id": 15, "name": "CLARION 5.56", "category": "rifle", "slot": 1, "team": TEAM_CT, "price": 2250, "ammo": "556nato", "magazine": 25, "reserve": 90, "max_speed": 240.0, "automatic": true, "primary": 0.0825, "burst_primary": 0.55, "burst_interval": 0.1, "reload": 3.3, "damage": 30, "burst_damage": 34, "range_modifier": 0.96, "range_units": 8192.0, "penetrations": 2, "bullet": "556mm", "armor": 1.4, "pellets": 1, "secondary": "burst", "zoom_speed": 240.0, "mode": "FULL AUTO"},
	"usp": {"id": 16, "name": "KM .45 TACTICAL", "category": "pistol", "slot": 2, "team": TEAM_BOTH, "price": 500, "ammo": "45acp", "magazine": 12, "reserve": 100, "max_speed": 250.0, "automatic": false, "primary": 0.15, "reload": 2.7, "damage": 34, "silenced_damage": 30, "range_modifier": 0.79, "silenced_range_modifier": 0.79, "range_units": 4096.0, "penetrations": 1, "bullet": "45acp", "armor": 1.0, "pellets": 1, "secondary": "silencer", "secondary_seconds": 3.0, "zoom_speed": 250.0, "mode": "SEMI AUTO"},
	"glock18": {"id": 17, "name": "9X19MM SIDEARM", "category": "pistol", "slot": 2, "team": TEAM_BOTH, "price": 400, "ammo": "9mm", "magazine": 20, "reserve": 120, "max_speed": 250.0, "automatic": false, "primary": 0.15, "burst_primary": 0.5, "burst_interval": 0.1, "reload": 2.2, "damage": 25, "range_modifier": 0.75, "range_units": 8192.0, "penetrations": 1, "bullet": "9mm", "armor": 1.05, "pellets": 1, "secondary": "burst", "zoom_speed": 250.0, "mode": "SEMI AUTO"},
	"awp": {"id": 18, "name": "MAGNUM SNIPER RIFLE", "category": "sniper", "slot": 1, "team": TEAM_BOTH, "price": 4750, "ammo": "338mag", "magazine": 10, "reserve": 30, "max_speed": 210.0, "automatic": false, "primary": 1.45, "reload": 2.5, "damage": 115, "range_modifier": 0.99, "range_units": 8192.0, "penetrations": 3, "bullet": "338mag", "armor": 1.95, "pellets": 1, "secondary": "zoom", "zoom_levels": [90, 40, 10], "zoom_speed": 150.0, "mode": "BOLT ACTION"},
	"mp5": {"id": 19, "name": "KM SUB-MACHINE GUN", "category": "smg", "slot": 1, "team": TEAM_BOTH, "price": 1500, "ammo": "9mm", "magazine": 30, "reserve": 120, "max_speed": 250.0, "automatic": true, "primary": 0.075, "reload": 2.63, "damage": 26, "range_modifier": 0.84, "range_units": 8192.0, "penetrations": 1, "bullet": "9mm", "armor": 1.0, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "FULL AUTO"},
	"m249": {"id": 20, "name": "ES M249 PARA", "category": "machinegun", "slot": 1, "team": TEAM_BOTH, "price": 5750, "ammo": "556natobox", "magazine": 100, "reserve": 200, "max_speed": 220.0, "automatic": true, "primary": 0.1, "reload": 4.7, "damage": 32, "range_modifier": 0.97, "range_units": 8192.0, "penetrations": 2, "bullet": "556mm", "armor": 1.5, "pellets": 1, "secondary": "none", "zoom_speed": 220.0, "mode": "FULL AUTO"},
	"m3": {"id": 21, "name": "LEONE 12 GAUGE SUPER", "category": "shotgun", "slot": 1, "team": TEAM_BOTH, "price": 1700, "ammo": "buckshot", "magazine": 8, "reserve": 32, "max_speed": 230.0, "automatic": false, "primary": 0.875, "reload": 0.55, "reload_insert": 0.45, "damage": 20, "range_modifier": 1.0, "range_units": 3000.0, "penetrations": 0, "bullet": "buckshot", "armor": 1.0, "pellets": 9, "cone": 0.0675, "secondary": "none", "zoom_speed": 230.0, "mode": "PUMP ACTION"},
	"m4a1": {"id": 22, "name": "MAVERICK M4A1 CARBINE", "category": "rifle", "slot": 1, "team": TEAM_CT, "price": 3100, "ammo": "556nato", "magazine": 30, "reserve": 90, "max_speed": 230.0, "automatic": true, "primary": 0.0875, "reload": 3.05, "damage": 32, "silenced_damage": 33, "range_modifier": 0.97, "silenced_range_modifier": 0.95, "range_units": 8192.0, "penetrations": 2, "bullet": "556mm", "armor": 1.4, "pellets": 1, "secondary": "silencer", "secondary_seconds": 2.0, "zoom_speed": 230.0, "mode": "FULL AUTO"},
	"tmp": {"id": 23, "name": "SCHMIDT MACHINE PISTOL", "category": "smg", "slot": 1, "team": TEAM_CT, "price": 1250, "ammo": "9mm", "magazine": 30, "reserve": 120, "max_speed": 250.0, "automatic": true, "primary": 0.07, "reload": 2.12, "damage": 20, "range_modifier": 0.85, "range_units": 8192.0, "penetrations": 1, "bullet": "9mm", "armor": 1.0, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "FULL AUTO"},
	"g3sg1": {"id": 24, "name": "D3/AU-1", "category": "sniper", "slot": 1, "team": TEAM_T, "price": 5000, "ammo": "762nato", "magazine": 20, "reserve": 90, "max_speed": 210.0, "automatic": true, "primary": 0.25, "reload": 3.5, "damage": 80, "range_modifier": 0.98, "range_units": 8192.0, "penetrations": 3, "bullet": "762mm", "armor": 1.65, "pellets": 1, "secondary": "zoom", "zoom_levels": [90, 40, 15], "zoom_speed": 150.0, "mode": "SEMI AUTO"},
	"flashbang": {"id": 25, "name": "FLASHBANG", "category": "grenade", "slot": 4, "team": TEAM_BOTH, "price": 200, "ammo": "flashbang", "magazine": 1, "reserve": 1, "reserve_max": 2, "max_speed": 250.0, "automatic": false, "primary": 1.0, "reload": 0.0, "damage": 0, "range_modifier": 1.0, "range_units": 0.0, "penetrations": 0, "bullet": "", "armor": 1.0, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "THROW"},
	"deagle": {"id": 26, "name": "DESERT EAGLE", "category": "pistol", "slot": 2, "team": TEAM_BOTH, "price": 650, "ammo": "50ae", "magazine": 7, "reserve": 35, "max_speed": 250.0, "automatic": false, "primary": 0.225, "reload": 2.2, "damage": 54, "range_modifier": 0.81, "range_units": 4096.0, "penetrations": 2, "bullet": "50ae", "armor": 1.5, "pellets": 1, "secondary": "none", "zoom_speed": 250.0, "mode": "SEMI AUTO"},
	"sg552": {"id": 27, "name": "KRIEG 552", "category": "rifle", "slot": 1, "team": TEAM_T, "price": 3500, "ammo": "556nato", "magazine": 30, "reserve": 90, "max_speed": 235.0, "automatic": true, "primary": 0.0825, "zoom_primary": 0.135, "reload": 3.0, "damage": 33, "range_modifier": 0.955, "range_units": 8192.0, "penetrations": 2, "bullet": "556mm", "armor": 1.4, "pellets": 1, "secondary": "zoom", "zoom_levels": [90, 55], "zoom_speed": 200.0, "mode": "FULL AUTO"},
	"ak47": {"id": 28, "name": "AK-47", "category": "rifle", "slot": 1, "team": TEAM_T, "price": 2500, "ammo": "762nato", "magazine": 30, "reserve": 90, "max_speed": 221.0, "automatic": true, "primary": 0.0955, "reload": 2.45, "damage": 36, "range_modifier": 0.98, "range_units": 8192.0, "penetrations": 2, "bullet": "762mm", "armor": 1.55, "pellets": 1, "secondary": "none", "zoom_speed": 221.0, "mode": "FULL AUTO"},
	"knife": {"id": 29, "name": "KNIFE", "category": "melee", "slot": 3, "team": TEAM_BOTH, "price": 0, "ammo": "", "magazine": -1, "reserve": -1, "max_speed": 250.0, "automatic": false, "primary": 0.35, "reload": 0.0, "damage": 15, "stab_damage": 65, "range_modifier": 1.0, "range_units": 48.0, "penetrations": 0, "bullet": "", "armor": 1.7, "pellets": 1, "secondary": "stab", "secondary_seconds": 1.1, "zoom_speed": 250.0, "mode": "MELEE"},
	"p90": {"id": 30, "name": "ES C90", "category": "smg", "slot": 1, "team": TEAM_BOTH, "price": 2350, "ammo": "57mm", "magazine": 50, "reserve": 100, "max_speed": 245.0, "automatic": true, "primary": 0.066, "reload": 3.4, "damage": 21, "range_modifier": 0.885, "range_units": 8192.0, "penetrations": 1, "bullet": "57mm", "armor": 1.5, "pellets": 1, "secondary": "none", "zoom_speed": 245.0, "mode": "FULL AUTO"},
}

const EQUIPMENT := {
	"kevlar": {"name": "KEVLAR VEST", "price": 650, "team": TEAM_BOTH},
	"helmet": {"name": "HELMET", "price": 350, "team": TEAM_BOTH},
	"assaultsuit": {"name": "KEVLAR + HELMET", "price": 1000, "team": TEAM_BOTH},
	"flashbang": {"name": "FLASHBANG", "price": 200, "team": TEAM_BOTH, "carry_max": 2},
	"hegrenade": {"name": "HE GRENADE", "price": 300, "team": TEAM_BOTH, "carry_max": 1},
	"smokegrenade": {"name": "SMOKE GRENADE", "price": 300, "team": TEAM_BOTH, "carry_max": 1},
	"defuser": {"name": "DEFUSAL KIT", "price": 200, "team": TEAM_CT},
	"nvgs": {"name": "NIGHTVISION", "price": 1250, "team": TEAM_BOTH},
	"shield": {"name": "TACTICAL SHIELD", "price": 2200, "team": TEAM_CT},
}


static func definition(weapon_name: String) -> Dictionary:
	var normalized := weapon_name.to_lower()
	if not WEAPONS.has(normalized):
		return {}
	var result := (WEAPONS[normalized] as Dictionary).duplicate(true)
	result.weapon = normalized
	result.primary_seconds = float(result.primary)
	result.reload_seconds = float(result.reload)
	result.base_damage = int(result.damage)
	result.bullet_type = str(result.bullet)
	result.armor_ratio_multiplier = float(result.armor)
	result.range_meters = float(result.range_units) * 0.01
	result.reserve_max = int(result.get("reserve_max", result.reserve))
	result.viewmodel = "res://generated/weapons/%s/model.json" % normalized
	result.player_model = "res://generated/player_weapons/%s/model.json" % normalized
	result.worldmodel = "models/w_%s.mdl" % normalized
	result.fire_event = "%s.fire" % normalized
	return result


static func can_buy(weapon_name: String, team_name: String) -> bool:
	var item := definition(weapon_name)
	return not item.is_empty() and team_name.to_upper() in item.team


static func initial_ammunition(full_reserve := true) -> Dictionary:
	var result := {}
	for weapon_name: String in ROSTER:
		var item: Dictionary = WEAPONS[weapon_name]
		if int(item.magazine) < 0:
			continue
		result[weapon_name] = {
			"clip": int(item.magazine),
			"reserve": int(item.reserve) if full_reserve else 0,
		}
	return result


static func timing(weapon_name: String) -> Dictionary:
	var item := definition(weapon_name)
	if item.is_empty():
		return {}
	var result := {
		"primary_seconds": float(item.primary),
		"reload_seconds": float(item.reload),
		"fire_idle_seconds": 2.0,
		"idle_repeat_seconds": 20.0,
	}
	if weapon_name == "deagle":
		result.fire_idle_seconds = 1.8
		result.idle_repeat_seconds = 3.0625
	elif weapon_name == "ak47":
		result.fire_idle_seconds = 1.9
	elif weapon_name == "knife":
		result.primary_miss_seconds = 0.35
		result.primary_hit_seconds = 0.4
	elif item.category == "grenade":
		result.pin_seconds = 0.5
		result.post_throw_attack_seconds = 0.5
		result.post_throw_idle_seconds = 0.75
		result.retire_seconds = 0.5
		result.idle_repeat_seconds = 10.0
	return result


static func validation_errors(check_assets := false) -> Array[String]:
	var errors: Array[String] = []
	if WEAPONS.size() != 29 or ROSTER.size() != 29:
		errors.append("CS 1.6 roster must contain exactly 29 weapon IDs")
	var ids := {}
	for weapon_name: String in ROSTER:
		if not WEAPONS.has(weapon_name):
			errors.append("missing definition: %s" % weapon_name)
			continue
		var item := definition(weapon_name)
		if ids.has(item.id):
			errors.append("duplicate weapon id: %s" % item.id)
		ids[item.id] = weapon_name
		for field in ["category", "slot", "team", "price", "magazine", "reserve", "max_speed", "primary", "reload", "damage", "range_modifier", "range_units", "penetrations", "armor", "secondary"]:
			if not item.has(field):
				errors.append("%s missing %s" % [weapon_name, field])
		if check_assets:
			if not FileAccess.file_exists(str(item.viewmodel)):
				errors.append("%s missing viewmodel" % weapon_name)
			if not FileAccess.file_exists(str(item.player_model)):
				errors.append("%s missing player weapon model" % weapon_name)
	return errors
