extends RefCounted

## Small host-only presentation packets. No client hits, paths or gameplay calls.
const World = preload("res://scripts/network_world_state.gd")
const Catalog = preload("res://scripts/cs16_audio_catalog.gd")
const Settings = preload("res://scripts/settings.gd")
const VERSION := 1
const MAX_BYTES := 4096
const MAX_PENDING := 128
const MAX_AGE_TICKS := 100
const KILL_NOTICE_AGE_TICKS := 500
const FIELDS := ["version", "epoch", "sequence", "tick", "actor", "life", "kind", "data"]


static func validate(packet: Variant) -> Dictionary:
	if not World.keys_match(packet, FIELDS):
		return {}
	for key in ["version", "epoch", "sequence", "tick", "life"]:
		if not World.integer(packet[key], 0, World.MAX_COUNTER):
			return {}
	if packet.version != VERSION or packet.epoch < 1 or packet.sequence < 1:
		return {}
	if typeof(packet.actor) != TYPE_STRING or (packet.actor != "" and not World.identifier(packet.actor)):
		return {}
	if typeof(packet.kind) != TYPE_STRING or not packet.data is Dictionary:
		return {}
	var d: Dictionary = packet.data
	match packet.kind:
		"shot":
			if not World.keys_match(d, ["weapon", "sequence", "origin", "direction", "right", "up", "punch"]):
				return {}
			if not _weapon(d.weapon) or not World.integer(d.sequence, 0, 255) or not World.vector(d.origin, 10000.0):
				return {}
			for key in ["direction", "right", "up"]:
				if not World.vector(d[key], 1.01) or absf(d[key].length() - 1.0) > 0.02:
					return {}
			if typeof(d.punch) != TYPE_VECTOR2 or not d.punch.is_finite() or d.punch.length() > 100.0:
				return {}
		"reload":
			if not World.keys_match(d, ["weapon"]) or not _weapon(d.weapon):
				return {}
		"knife_action":
			if not World.keys_match(d, ["action"]) or typeof(d.action) != TYPE_STRING or d.action not in ["midslash1", "midslash2", "stab", "stab_miss"]:
				return {}
		"grenade_action":
			if not World.keys_match(d, ["weapon", "action"]) or typeof(d.weapon) != TYPE_STRING or d.weapon not in ["hegrenade", "flashbang", "smokegrenade"]:
				return {}
			if typeof(d.action) != TYPE_STRING or d.action not in ["pullpin", "throw"]:
				return {}
		"audio", "world_audio":
			var fields := ["name", "sample", "channel", "volume", "attenuation", "pitch", "origin"]
			if packet.kind == "world_audio":
				fields.append("source")
				if not World.integer(d.get("source"), 0, World.MAX_COUNTER):
					return {}
			if not World.keys_match(d, fields):
				return {}
			if typeof(d.name) != TYPE_STRING or not Catalog.EVENT_SAMPLES.has(d.name) or d.name == "weapon.mode_switch":
				return {}
			if typeof(d.sample) != TYPE_STRING or not d.sample in Catalog.EVENT_SAMPLES[d.name]:
				return {}
			if not World.integer(d.channel, 0, 6) or not World.integer(d.pitch, 1, 255) or not World.vector(d.origin, 10000.0):
				return {}
			if not World.number(d.volume, 0.0, 1.0) or not World.number(d.attenuation, 0.0, 4.0):
				return {}
		"impact", "blood", "blood_decal":
			if not World.keys_match(d, ["position", "normal", "sequence", "surface"]):
				return {}
			if not World.vector(d.position, 10000.0) or not World.vector(d.normal, 1.01) or not World.integer(d.sequence, 0, 255):
				return {}
			if typeof(d.surface) != TYPE_STRING or d.surface.length() > 32:
				return {}
		"kill":
			if not World.keys_match(d, ["killer", "killer_team", "weapon", "victim", "victim_team", "headshot"]):
				return {}
			for key in ["killer", "killer_team", "weapon", "victim", "victim_team"]:
				if typeof(d[key]) != TYPE_STRING or d[key].length() > 64:
					return {}
			if typeof(d.headshot) != TYPE_BOOL or d.killer_team not in ["", "T", "CT", "UNASSIGNED"] or d.victim_team not in ["T", "CT", "UNASSIGNED"]:
				return {}
		"explosion":
			if not World.keys_match(d, ["weapon", "position", "normal", "underwater"]):
				return {}
			if typeof(d.weapon) != TYPE_STRING or d.weapon not in ["hegrenade", "flashbang", "c4"]:
				return {}
			if not World.vector(d.position, 10000.0) or not World.vector(d.normal, 1.01) or typeof(d.underwater) != TYPE_BOOL:
				return {}
		"radio":
			if not World.keys_match(d, ["sample", "sender_name", "team", "text"]):
				return {}
			if typeof(d.sample) != TYPE_STRING or not Catalog.RADIO_MESSAGES.has(d.sample):
				return {}
			if typeof(d.sender_name) != TYPE_STRING or d.sender_name != Settings.sanitize_player_name(d.sender_name):
				return {}
			if typeof(d.team) != TYPE_STRING or d.team not in ["T", "CT"]:
				return {}
			if typeof(d.text) != TYPE_STRING or d.text != str(Catalog.RADIO_MESSAGES[d.sample]):
				return {}
		_:
			return {}
	if packet.kind in ["shot", "reload", "audio", "grenade_action", "knife_action", "radio"] and packet.actor.is_empty():
		return {}
	if packet.kind in ["world_audio", "explosion"] and not packet.actor.is_empty():
		return {}
	if var_to_bytes(packet).size() > MAX_BYTES:
		return {}
	return packet.duplicate(true)


static func _weapon(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and World.Weapons.WEAPONS.has(value)


static func maximum_age_ticks(kind: String) -> int:
	# A scoreboard notification remains useful after a brief presentation stall;
	# a delayed muzzle flash or gunshot does not. Round/epoch checks still apply.
	return KILL_NOTICE_AGE_TICKS if kind == "kill" else MAX_AGE_TICKS
