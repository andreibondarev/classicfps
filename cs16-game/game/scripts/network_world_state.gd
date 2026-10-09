extends RefCounted

## Bounded full actor snapshots. This is not yet the complete dynamic-world
## contract: brush state, visibility filtering and deltas remain separate work.
## Transient combat events have their own codec. Reject before client mutation.
const Weapons = preload("res://scripts/cs16_weapon_registry.gd")
const Spray = preload("res://scripts/cs16_spray.gd")
const VERSION := 8
const MAX_ACTORS := 32
const MAX_WORLD_ITEMS := 512
const MAX_COUNTER := 0x7fffffff
const MAX_DECODED_BYTES := 262144
const MAX_ENCODED_BYTES := 32768
const SKINS := ["terror", "leet", "arctic", "guerilla", "urban", "gsg9", "sas", "gign"]
const FIELDS := ["version", "epoch", "tick", "map", "owner_id", "input_ack", "started", "concluded", "round", "actors", "inventory", "items", "can_buy", "motion", "feedback", "broken_brushes"]
const FEEDBACK_FIELDS := ["action", "total", "remaining", "flash_total", "flash_remaining", "can_plant", "bomb_state", "result"]
const RESULTS := ["", "bomb_planted", "bomb_defused", "bomb_exploded", "t_win", "ct_win", "draw"]
const MOTION_FIELDS := ["enabled", "standing", "duck_elapsed", "jump_down", "objective_locked", "objective_crouch", "max_speed"]
const EQUIPMENT := ["kevlar", "helmet", "defuser", "nvgs", "shield"]
const ROUND_FIELDS := ["number", "phase", "seconds", "t_score", "ct_score"]
const ACTOR_FIELDS := ["id", "kind", "name", "team", "position", "velocity", "angles", "alive", "visible",
	"health", "armor", "helmet", "weapon", "clip", "reserve", "reloading", "skin", "life", "crouched", "kills", "deaths", "money", "class_id", "ping"]


static func keys_match(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for key: String in fields:
		if not value.has(key):
			return false
	return true


static func integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) == TYPE_INT and value >= low and value <= high


static func number(value: Variant, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= low and value <= high


static func identifier(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 32:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return false
	return true


static func vector(value: Variant, limit: float) -> bool:
	return typeof(value) == TYPE_VECTOR3 and value.is_finite() and maxf(absf(value.x), maxf(absf(value.y), absf(value.z))) <= limit


static func inventory_for(human: PlayerController) -> Dictionary:
	var items: Array[Dictionary] = []
	for weapon: String in human.owned_weapons:
		if not human.owns_weapon(weapon):
			continue
		var ammo: Dictionary = human.ammunition.get(weapon, {"clip": -1, "reserve": -1})
		var mode: Variant = human.weapon_modes.get(weapon, 0 if str(Weapons.WEAPONS[weapon].secondary) == "zoom" else false)
		items.append({"weapon": weapon,
			"clip": human.clip if weapon == human.active_weapon else int(ammo.clip),
			"reserve": human.reserve if weapon == human.active_weapon else int(ammo.reserve), "mode": mode})
	return {"weapons": items, "previous": human.previous_weapon, "equipment": human.equipment.duplicate()}


static func motion_for(human: PlayerController) -> Dictionary:
	return {"enabled": human.can_simulate_movement(), "standing": human._standing,
		"duck_elapsed": human._duck_elapsed, "jump_down": human._jump_was_down,
		"objective_locked": human.objective_movement_locked, "objective_crouch": human.objective_crouch_locked,
		"max_speed": human._max_speed_override_ups}


static func valid_motion(value: Variant) -> bool:
	if not keys_match(value, MOTION_FIELDS):
		return false
	for key in ["enabled", "standing", "jump_down", "objective_locked", "objective_crouch"]:
		if typeof(value[key]) != TYPE_BOOL:
			return false
	return number(value.duck_elapsed, 0.0, PlayerController.DUCK_TIME) \
		and number(value.max_speed, 0.0, 10000.0) \
		and (not value.objective_crouch or value.objective_locked)


static func valid_inventory(value: Variant) -> bool:
	if not keys_match(value, ["weapons", "previous", "equipment"]):
		return false
	if typeof(value.previous) != TYPE_STRING or (not value.previous.is_empty() and not Weapons.WEAPONS.has(value.previous)):
		return false
	if not keys_match(value.equipment, EQUIPMENT):
		return false
	for item: String in EQUIPMENT:
		if typeof(value.equipment[item]) != TYPE_BOOL:
			return false
	if not value.weapons is Array or value.weapons.size() > Weapons.WEAPONS.size():
		return false
	var seen := {}
	for item: Variant in value.weapons:
		if not keys_match(item, ["weapon", "clip", "reserve", "mode"]) or typeof(item.weapon) != TYPE_STRING or not Weapons.WEAPONS.has(item.weapon) or seen.has(item.weapon):
			return false
		seen[item.weapon] = true
		var definition: Dictionary = Weapons.WEAPONS[item.weapon]
		if not integer(item.clip, mini(0, int(definition.magazine)), 100) or not integer(item.reserve, mini(0, int(definition.reserve)), 1000):
			return false
		if str(definition.secondary) == "zoom":
			if not integer(item.mode, 0, definition.zoom_levels.size() - 1):
				return false
		elif typeof(item.mode) != TYPE_BOOL or (str(definition.secondary) not in ["burst", "silencer"] and item.mode):
			return false
	return true


static func valid_broken_brushes(value: Variant) -> bool:
	if not value is Array or value.size() > 512:
		return false
	var seen := {}
	for model: Variant in value:
		if not integer(model, 1, 4096) or seen.has(model):
			return false
		seen[model] = true
	return true


static func valid_world_items(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_WORLD_ITEMS:
		return false
	var seen := {}
	var c4_kinds := {}
	for item: Variant in value:
		if not keys_match(item, ["id", "kind", "weapon", "position", "rotation", "total", "remaining"]):
			return false
		if not integer(item.id, 1, MAX_COUNTER) or seen.has(item.id):
			return false
		seen[item.id] = true
		if typeof(item.kind) != TYPE_STRING or item.kind not in ["gun", "dropped_c4", "planted_c4", "grenade", "smoke"]:
			return false
		if typeof(item.weapon) != TYPE_STRING or not Weapons.WEAPONS.has(item.weapon):
			return false
		if item.kind == "gun":
			if str(Weapons.WEAPONS[item.weapon].category) in ["melee", "grenade", "objective"]:
				return false
		elif item.kind in ["grenade", "smoke"]:
			if item.weapon not in ["hegrenade", "flashbang", "smokegrenade"] or (item.kind == "smoke" and item.weapon != "smokegrenade"):
				return false
		else:
			if item.weapon != "c4" or c4_kinds.has(item.kind):
				return false
			c4_kinds[item.kind] = true
		if not vector(item.position, 10000.0) or typeof(item.rotation) != TYPE_QUATERNION or not item.rotation.is_finite():
			return false
		if absf(item.rotation.length_squared() - 1.0) > 0.00001:
			return false
		if not number(item.total, 0.0, 3600.0) or not number(item.remaining, 0.0, 3600.0) or item.remaining > item.total:
			return false
		if item.kind in ["planted_c4", "smoke"]:
			if item.total <= 0.0:
				return false
			if item.kind == "smoke" and item.total > 16.0:
				return false
		elif item.total != 0.0 or item.remaining != 0.0:
			return false
	return not (c4_kinds.has("dropped_c4") and c4_kinds.has("planted_c4"))


static func empty_feedback() -> Dictionary:
	return {"action": "", "total": 0.0, "remaining": 0.0, "flash_total": 0.0,
		"flash_remaining": 0.0, "can_plant": false, "bomb_state": "none", "result": ""}


static func valid_feedback(value: Variant) -> bool:
	if not keys_match(value, FEEDBACK_FIELDS):
		return false
	if typeof(value.action) != TYPE_STRING or value.action not in ["", "plant", "defuse"] or typeof(value.can_plant) != TYPE_BOOL:
		return false
	if typeof(value.bomb_state) != TYPE_STRING or value.bomb_state not in ["none", "carried", "dropped", "planting", "planted", "defused", "exploded"]:
		return false
	if typeof(value.result) != TYPE_STRING or value.result not in RESULTS:
		return false
	for key in ["total", "remaining", "flash_total", "flash_remaining"]:
		if not number(value[key], 0.0, 60.0):
			return false
	return value.remaining <= value.total and value.flash_remaining <= value.flash_total \
		and ((value.action == "" and value.total == 0.0 and value.remaining == 0.0) or (value.action != "" and value.total > 0.0))


static func encode(snapshot: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes(snapshot)
	if raw.size() > MAX_DECODED_BYTES:
		return PackedByteArray()
	var result := PackedByteArray()
	result.resize(4)
	result.encode_u32(0, raw.size())
	result.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return result if result.size() <= MAX_ENCODED_BYTES else PackedByteArray()


static func decode(packet: Variant) -> Dictionary:
	if typeof(packet) != TYPE_PACKED_BYTE_ARRAY or packet.size() < 5 or packet.size() > MAX_ENCODED_BYTES:
		return {}
	var size: int = packet.decode_u32(0)
	if size < 1 or size > MAX_DECODED_BYTES:
		return {}
	var raw: PackedByteArray = packet.slice(4).decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size:
		return {}
	# bytes_to_var does not deserialize objects; full schema validation precedes
	# application. The declared byte count bounds decompression allocation.
	return validate(bytes_to_var(raw))


static func validate(packet: Variant) -> Dictionary:
	var fields := FIELDS + ["sprays"] if packet is Dictionary and packet.has("sprays") else FIELDS
	if not keys_match(packet, fields) or not integer(packet.version, VERSION, VERSION):
		return {}
	if not Spray.valid_records(packet.get("sprays", [])):
		return {}
	if not integer(packet.epoch, 1, MAX_COUNTER) or not integer(packet.tick, 0, MAX_COUNTER) or not integer(packet.input_ack, 0, MAX_COUNTER):
		return {}
	if typeof(packet.map) != TYPE_STRING or packet.map not in ["de_dust2", "cs_assault"] or not identifier(packet.owner_id):
		return {}
	if typeof(packet.can_buy) != TYPE_BOOL or typeof(packet.started) != TYPE_BOOL or typeof(packet.concluded) != TYPE_BOOL or not keys_match(packet.round, ROUND_FIELDS):
		return {}
	var round: Dictionary = packet.round
	if not integer(round.number, 1, MAX_COUNTER) or not integer(round.t_score, 0, MAX_COUNTER) or not integer(round.ct_score, 0, MAX_COUNTER):
		return {}
	if typeof(round.phase) != TYPE_STRING or round.phase not in ["deploy", "freeze", "live", "bomb", "post", "intermission"] or not number(round.seconds, 0.0, 3600.0):
		return {}
	if not packet.actors is Array or packet.actors.is_empty() or packet.actors.size() > MAX_ACTORS:
		return {}
	if not valid_inventory(packet.inventory) or not valid_world_items(packet.items) or not valid_motion(packet.motion) or not valid_feedback(packet.feedback):
		return {}
	if not valid_broken_brushes(packet.broken_brushes):
		return {}
	var seen := {}
	var owner_found := false
	for row: Variant in packet.actors:
		if not keys_match(row, ACTOR_FIELDS) or not identifier(row.id) or seen.has(row.id):
			return {}
		seen[row.id] = true
		if typeof(row.kind) != TYPE_STRING or row.kind not in ["human", "bot"]:
			return {}
		if typeof(row.name) != TYPE_STRING or row.name.length() > 64 or typeof(row.team) != TYPE_STRING or row.team not in ["T", "CT", "UNASSIGNED"]:
			return {}
		if not vector(row.position, 10000.0) or not vector(row.velocity, 100.0) or typeof(row.angles) != TYPE_VECTOR2 or not row.angles.is_finite():
			return {}
		if absf(row.angles.x) > PI + 0.000001 or absf(row.angles.y) > PI * 0.5:
			return {}
		for key in ["alive", "visible", "helmet", "reloading", "crouched"]:
			if typeof(row[key]) != TYPE_BOOL:
				return {}
		if not integer(row.health, 0, 100) or not integer(row.armor, 0, 100) or (row.alive and (row.health == 0 or row.team == "UNASSIGNED")):
			return {}
		if typeof(row.weapon) != TYPE_STRING or not Weapons.WEAPONS.has(row.weapon):
			return {}
		var definition: Dictionary = Weapons.WEAPONS[row.weapon]
		if not integer(row.clip, mini(0, int(definition.magazine)), 100) or not integer(row.reserve, mini(0, int(definition.reserve)), 1000):
			return {}
		if typeof(row.skin) != TYPE_STRING or row.skin not in SKINS or not integer(row.life, 0, MAX_COUNTER):
			return {}
		if not integer(row.kills, -MAX_COUNTER, MAX_COUNTER) or not integer(row.deaths, 0, MAX_COUNTER) or not integer(row.money, 0, 16000) or not integer(row.class_id, 0, 4):
			return {}
		# Round-trip milliseconds the host measured; -1 = not measured (bots, fresh joins).
		if not integer(row.ping, -1, 9999):
			return {}
		if row.id == packet.owner_id:
			if row.kind != "human":
				return {}
			if row.crouched == packet.motion.standing or (packet.motion.enabled and not row.alive):
				return {}
			var active_found := false
			for item: Dictionary in packet.inventory.weapons:
				if item.weapon == row.weapon:
					active_found = true
					if item.clip != row.clip or item.reserve != row.reserve:
						return {}
			if row.alive and not active_found:
				return {}
			owner_found = true
	return packet.duplicate(true) if owner_found else {}
