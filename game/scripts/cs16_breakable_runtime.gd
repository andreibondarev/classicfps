class_name CS16BreakableRuntime
extends RefCounted

## Deterministic func_breakable simulation. Rendering and collision ownership
## stay with BspMap; this runtime owns health, damage filtering, break effects,
## target completion, and round restoration.

signal runtime_event(event: Dictionary)

const EntityWorld := preload("res://scripts/cs16_entity_world.gd")
const CollisionProxy := preload("res://scripts/cs16_breakable_collision_proxy.gd")

const TICK_RATE := 100
const GOLD_SRC_TO_GODOT := 0.01

const MAT_GLASS := 0
const MAT_WOOD := 1
const MAT_METAL := 2
const MAT_FLESH := 3
const MAT_CINDER_BLOCK := 4
const MAT_CEILING_TILE := 5
const MAT_COMPUTER := 6
const MAT_UNBREAKABLE_GLASS := 7
const MAT_ROCKS := 8
const MAT_NONE := 9
const MAT_LAST := 10

const MATERIAL_NAMES := [
	"glass",
	"wood",
	"metal",
	"flesh",
	"cinder_block",
	"ceiling_tile",
	"computer",
	"unbreakable_glass",
	"rocks",
	"none",
]

const SF_BREAK_TRIGGER_ONLY := 1 << 0
const SF_BREAK_TOUCH := 1 << 1
const SF_BREAK_PRESSURE := 1 << 2
const SF_BREAK_CROWBAR := 1 << 8

const DMG_GENERIC := 0
const DMG_CRUSH := 1 << 0
const DMG_BULLET := 1 << 1
const DMG_SLASH := 1 << 2
const DMG_BLAST := 1 << 6
const DMG_CLUB := 1 << 7
const DMG_POISON := 1 << 17

const BREAK_GLASS := 0x01
const BREAK_METAL := 0x02
const BREAK_FLESH := 0x04
const BREAK_WOOD := 0x08
const BREAK_CONCRETE := 0x40

const SPAWN_OBJECTS := [
	"",
	"item_battery",
	"item_healthkit",
	"weapon_9mmhandgun",
	"ammo_9mmclip",
	"weapon_9mmAR",
	"ammo_9mmAR",
	"ammo_ARgrenades",
	"weapon_shotgun",
	"ammo_buckshot",
	"weapon_crossbow",
	"ammo_crossbow",
	"weapon_357",
	"ammo_357",
	"weapon_rpg",
	"ammo_rpgclip",
	"ammo_gaussclip",
	"weapon_handgrenade",
	"weapon_tripmine",
	"weapon_satchel",
	"weapon_snark",
	"weapon_hornetgun",
	"weapon_usp",
	"weapon_glock18",
	"weapon_awp",
	"weapon_mp5n",
	"weapon_m249",
	"weapon_m3",
	"weapon_m4a1",
	"weapon_tmp",
	"weapon_g3sg1",
	"weapon_flashbang",
]

const DAMAGE_SOUNDS := {
	MAT_GLASS: ["debris/glass1.wav", "debris/glass2.wav", "debris/glass3.wav"],
	MAT_WOOD: ["debris/wood1.wav", "debris/wood2.wav", "debris/wood3.wav"],
	MAT_METAL: ["debris/metal1.wav", "debris/metal3.wav", "debris/metal2.wav"],
	MAT_FLESH: [
		"debris/flesh1.wav",
		"debris/flesh2.wav",
		"debris/flesh3.wav",
		"debris/flesh5.wav",
		"debris/flesh6.wav",
		"debris/flesh7.wav",
	],
	MAT_CINDER_BLOCK: [
		"debris/concrete1.wav",
		"debris/concrete2.wav",
		"debris/concrete3.wav",
	],
	MAT_COMPUTER: ["debris/glass1.wav", "debris/glass2.wav", "debris/glass3.wav"],
	MAT_UNBREAKABLE_GLASS: [
		"debris/glass1.wav",
		"debris/glass2.wav",
		"debris/glass3.wav",
	],
	MAT_ROCKS: ["debris/concrete1.wav", "debris/concrete2.wav", "debris/concrete3.wav"],
}

const BREAK_SOUNDS := {
	MAT_GLASS: ["debris/bustglass1.wav", "debris/bustglass2.wav"],
	MAT_WOOD: ["debris/bustcrate1.wav", "debris/bustcrate2.wav"],
	MAT_METAL: ["debris/bustmetal1.wav", "debris/bustmetal2.wav"],
	MAT_FLESH: ["debris/bustflesh1.wav", "debris/bustflesh2.wav"],
	MAT_CINDER_BLOCK: ["debris/bustconcrete1.wav", "debris/bustconcrete2.wav"],
	MAT_CEILING_TILE: ["debris/bustceiling.wav"],
	MAT_COMPUTER: ["debris/bustmetal1.wav", "debris/bustmetal2.wav"],
	MAT_ROCKS: ["debris/bustconcrete1.wav", "debris/bustconcrete2.wav"],
}

const GIB_MODELS := {
	MAT_GLASS: "models/glassgibs.mdl",
	MAT_WOOD: "models/woodgibs.mdl",
	MAT_METAL: "models/metalplategibs.mdl",
	MAT_FLESH: "models/fleshgibs.mdl",
	MAT_CINDER_BLOCK: "models/cindergibs.mdl",
	MAT_CEILING_TILE: "models/ceilinggibs.mdl",
	MAT_COMPUTER: "models/computergibs.mdl",
	MAT_UNBREAKABLE_GLASS: "models/glassgibs.mdl",
	MAT_ROCKS: "models/rockgibs.mdl",
}

var events: Array[Dictionary] = []

var _bsp_map: Variant
var _entity_world: Variant
var _breakables: Dictionary = {}
var _round_snapshot: Dictionary = {}
var _event_sequence := 0


func configure(bsp_map: Variant, entity_world: Variant) -> int:
	_bsp_map = bsp_map
	_entity_world = entity_world
	_breakables.clear()
	_round_snapshot.clear()
	events.clear()
	_event_sequence = 0

	var raw_entities: Array = bsp_map.entities
	assert(
		entity_world.entity_count() == raw_entities.size(),
		"CS16BreakableRuntime requires the same BSP entity array in CS16EntityWorld",
	)
	for array_index in range(raw_entities.size()):
		var raw: Dictionary = raw_entities[array_index]
		if str(raw.get("classname", "")) != "func_breakable":
			continue
		var map_entity_index := int(raw.get("entity_index", array_index))
		var model_index := int(bsp_map.model_index_for_entity(map_entity_index))
		if model_index <= 0 or bsp_map.model_root(model_index) == null:
			continue
		var record := _make_record(array_index, map_entity_index, model_index, raw)
		_breakables[array_index] = record
		entity_world.set_capabilities(array_index, 0)
		entity_world.set_entity_state(array_index, true)
		entity_world.bind_handler(
			array_index,
			Callable(self, "_on_entity_use").bind(array_index),
		)
		bsp_map.set_model_runtime_active(model_index, true)

	_round_snapshot = _breakables.duplicate(true)
	entity_world.capture_round_start()
	return _breakables.size()


func breakable_count() -> int:
	return _breakables.size()


func has_entity(entity_id: int) -> bool:
	return _breakables.has(entity_id)


func get_breakable(entity_id: int) -> Dictionary:
	if not _breakables.has(entity_id):
		return {}
	return (_breakables[entity_id] as Dictionary).duplicate(true)


func trigger(entity_id: int, activator_id: int, caller_id := -1) -> bool:
	if not _breakables.has(entity_id):
		return false
	var record: Dictionary = _breakables[entity_id]
	if not bool(record["alive"]) or not bool(record["breakable"]):
		return false
	return _entity_world.use_entity(
		entity_id,
		activator_id,
		activator_id if caller_id < 0 else caller_id,
		EntityWorld.USE_TOGGLE,
		0.0,
		"breakable_trigger",
	)


## Attaches the damage surface expected by existing bullet and knife traces to
## BspMap's real AnimatableBody3D objects. The optional resolver maps gameplay
## actor objects to stable entity ids.
func bind_collision_bodies(actor_id_resolver := Callable()) -> int:
	var bound := 0
	var ids: Array = _breakables.keys()
	ids.sort()
	for raw_id in ids:
		var entity_id := int(raw_id)
		var record: Dictionary = _breakables[entity_id]
		var body: CollisionObject3D = _bsp_map.model_collision_body(
			int(record["model_index"]),
		)
		if body == null or not body is AnimatableBody3D:
			continue
		if body.get_script() != CollisionProxy:
			if body.get_script() != null:
				push_warning(
					"Breakable collision body %d already owns a different script"
					% int(record["model_index"]),
				)
				continue
			body.set_script(CollisionProxy)
		if not body.has_method("bind_breakable"):
			continue
		body.call(
			"bind_breakable",
			self,
			entity_id,
			actor_id_resolver,
		)
		bound += 1
	return bound


## Applies the exact CBreakable damage modifiers. attack_direction is in Godot
## coordinates and is used by directed debris; callers may leave it zero to use
## the brush's authored yaw.
func damage(
	entity_id: int,
	attacker_id: int,
	inflictor_id: int,
	raw_damage: float,
	damage_bits: int,
	attack_direction := Vector3.ZERO,
	attacker_is_client := true,
) -> Dictionary:
	var result := {
		"accepted": false,
		"applied_damage": 0.0,
		"remaining_health": 0.0,
		"broken": false,
	}
	if not _breakables.has(entity_id) or raw_damage <= 0.0:
		return result
	var record: Dictionary = _breakables[entity_id]
	result["remaining_health"] = float(record["health"])
	if (
		not bool(record["alive"])
		or not bool(record["breakable"])
		or bool(record["trigger_only"])
	):
		return result

	var applied := raw_damage
	if (
		attacker_id == inflictor_id
		and attacker_is_client
		and (int(record["spawnflags"]) & SF_BREAK_CROWBAR) != 0
		and (damage_bits & DMG_CLUB) != 0
	):
		applied = float(record["health"])
	if (damage_bits & DMG_CLUB) != 0:
		applied *= 2.0
	if (damage_bits & DMG_POISON) != 0:
		applied *= 0.1

	record["health"] = float(record["health"]) - applied
	record["last_attack_direction"] = (
		attack_direction.normalized()
		if not attack_direction.is_zero_approx()
		else _authored_attack_direction(record)
	)
	result["accepted"] = true
	result["applied_damage"] = applied
	result["remaining_health"] = float(record["health"])
	if float(record["health"]) <= 0.0:
		_break(record, attacker_id, damage_bits, "damage")
		result["broken"] = true
	else:
		_emit_damage_event(record, attacker_id, damage_bits, applied)
	return result


## Source touch tests use GoldSrc velocity units. A crash-through only applies
## damage when speed*0.01 can finish the brush; pressure breaks are scheduled on
## the fixed 100 Hz clock.
func touch(
	entity_id: int,
	player_id: int,
	velocity_hu_per_second: Vector3,
	standing_on_top := false,
	is_player := true,
) -> bool:
	if not _breakables.has(entity_id) or not is_player:
		return false
	var record: Dictionary = _breakables[entity_id]
	if not bool(record["alive"]) or not bool(record["breakable"]):
		return false
	if (int(record["spawnflags"]) & SF_BREAK_TOUCH) != 0:
		var crash_damage := velocity_hu_per_second.length() * 0.01
		if crash_damage >= float(record["health"]):
			record["last_attack_direction"] = _godot_velocity_from_source(
				velocity_hu_per_second,
			).normalized()
			var result := damage(
				entity_id,
				player_id,
				player_id,
				crash_damage,
				DMG_CRUSH,
				record["last_attack_direction"],
			)
			if bool(result["broken"]):
				_emit_event("touch_player_damage", record, {
					"player_id": player_id,
					"damage": crash_damage * 0.25,
					"damage_bits": DMG_SLASH,
				})
				return true
	if (
		standing_on_top
		and (int(record["spawnflags"]) & SF_BREAK_PRESSURE) != 0
		and int(record["pressure_break_tick"]) < 0
	):
		var delay_seconds := float(record["delay_seconds"])
		if is_zero_approx(delay_seconds):
			delay_seconds = 0.1
		record["pressure_break_tick"] = (
			int(_entity_world.tick) + _seconds_to_ticks(delay_seconds)
		)
		record["activator_id"] = player_id
		_emit_event("pressure_armed", record, {
			"player_id": player_id,
			"due_tick": int(record["pressure_break_tick"]),
		})
		return true
	return false


func advance_tick(advance_entity_world := true) -> Array[Dictionary]:
	var start := events.size()
	if advance_entity_world:
		_entity_world.advance_tick()
	var ids: Array = _breakables.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = _breakables[int(raw_id)]
		if (
			bool(record["alive"])
			and int(record["pressure_break_tick"]) >= 0
			and int(record["pressure_break_tick"]) <= int(_entity_world.tick)
		):
			record["pressure_break_tick"] = -1
			_break(
				record,
				int(record["activator_id"]),
				DMG_CRUSH,
				"pressure",
			)
	return events.slice(start)


func advance_ticks(count: int) -> void:
	for _step in range(maxi(0, count)):
		advance_tick()


func drain_events() -> Array[Dictionary]:
	var drained := events.duplicate(true)
	events.clear()
	return drained


func reset_round(reset_entity_world := true) -> void:
	if reset_entity_world:
		_entity_world.reset_round()
	_breakables = _round_snapshot.duplicate(true)
	events.clear()
	_event_sequence = 0
	var ids: Array = _breakables.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = _breakables[int(raw_id)]
		_bsp_map.set_model_runtime_active(int(record["model_index"]), true)


func _make_record(
	entity_id: int,
	map_entity_index: int,
	model_index: int,
	raw: Dictionary,
) -> Dictionary:
	var properties := _properties(raw)
	var material := _int_property(properties, "material", MAT_WOOD)
	if material < 0 or material >= MAT_LAST:
		material = MAT_WOOD
	var health := _float_property(properties, "health", 0.0)
	var spawnflags := _int_property(properties, "spawnflags", 0)
	var spawn_object_index := _int_property(properties, "spawnobject", 0)
	var spawn_object := (
		str(SPAWN_OBJECTS[spawn_object_index])
		if spawn_object_index > 0 and spawn_object_index < SPAWN_OBJECTS.size()
		else ""
	)
	var gib_model := str(properties.get("gibmodel", GIB_MODELS.get(material, "")))
	var initial_transform: Transform3D = _bsp_map.initial_transform_for_model(model_index)
	var bounds: AABB = _bsp_map.model_bounds_for_index(model_index)
	return {
		"entity_id": entity_id,
		"map_entity_index": map_entity_index,
		"model_index": model_index,
		"properties": properties,
		"spawnflags": spawnflags,
		"initial_health": health,
		"health": health,
		"material": material,
		"material_name": str(MATERIAL_NAMES[material]),
		"breakable": material != MAT_UNBREAKABLE_GLASS,
		"trigger_only": (spawnflags & SF_BREAK_TRIGGER_ONLY) != 0,
		"alive": true,
		"solid": true,
		"delay_seconds": _float_property(properties, "delay", 0.0),
		"explosion_magnitude": _int_property(properties, "explodemagnitude", 0),
		"explosion_mode": (
			"directed"
			if str(properties.get("explosion", "")).to_lower() == "directed"
			else "random"
		),
		"spawn_object": spawn_object,
		"gib_model": gib_model,
		"bounds": bounds,
		"center": initial_transform * bounds.get_center(),
		"size": bounds.size,
		"angle": _float_property(properties, "angle", 0.0),
		"last_attack_direction": Vector3.RIGHT,
		"pressure_break_tick": -1,
		"activator_id": -1,
		"rng_state": ((entity_id + 1) * 1103515245 + 12345) & 0x7fffffff,
	}


func _on_entity_use(event: Dictionary, entity_id: int) -> void:
	if not _breakables.has(entity_id):
		return
	var record: Dictionary = _breakables[entity_id]
	if not bool(record["alive"]) or not bool(record["breakable"]):
		return
	record["last_attack_direction"] = _authored_attack_direction(record)
	_break(
		record,
		int(event.get("activator_id", -1)),
		DMG_GENERIC,
		"trigger",
	)


func _break(
	record: Dictionary,
	activator_id: int,
	damage_bits: int,
	reason: String,
) -> void:
	if not bool(record["alive"]) or not bool(record["breakable"]):
		return
	record["alive"] = false
	record["solid"] = false
	record["health"] = minf(0.0, float(record["health"]))
	record["pressure_break_tick"] = -1
	_bsp_map.set_model_runtime_active(int(record["model_index"]), false)
	_entity_world.set_entity_state(int(record["entity_id"]), false)

	var pitch := 95 + _random_int(record, 30)
	if pitch > 97 and pitch < 103:
		pitch = 100
	var break_sounds: Array = BREAK_SOUNDS.get(int(record["material"]), [])
	var sound := (
		str(break_sounds[_random_int(record, break_sounds.size())])
		if not break_sounds.is_empty()
		else ""
	)
	var volume := minf(
		1.0,
		0.85 + _random_float(record) * 0.15
		+ absf(float(record["health"])) / 100.0,
	)
	var debris_velocity := Vector3.ZERO
	if str(record["explosion_mode"]) == "directed":
		debris_velocity = (
			(record["last_attack_direction"] as Vector3).normalized()
			* 200.0
			* GOLD_SRC_TO_GODOT
		)
	var debris_seed := _random_int(record, 0x7fffffff)
	_emit_event("break", record, {
		"activator_id": activator_id,
		"damage_bits": damage_bits,
		"reason": reason,
		"sound": sound,
		"pitch": pitch,
		"volume": volume,
	})
	_emit_event("debris", record, {
		"origin": record["center"],
		"size": record["size"],
		"velocity": debris_velocity,
		"randomization": 10,
		"gib_model": str(record["gib_model"]),
		"shard_count": 0,
		"duration_seconds": 2.5,
		"break_flag": _break_flag(int(record["material"])),
		"break_flag_name": _break_flag_name(int(record["material"])),
		"seed": debris_seed,
	})
	# CBreakable::Die uses a null activator and resolves its CBaseDelay outputs
	# after removing solidity, before spawning an item or explosion.
	var output_delay_override := -1
	if reason == "pressure" and is_zero_approx(float(record["delay_seconds"])):
		# BreakTouch changes a zero delay to 0.1 before both its Die think and
		# the subsequent CBaseDelay output.
		output_delay_override = 10
	_entity_world.emit_outputs(
		int(record["entity_id"]),
		-1,
		EntityWorld.USE_TOGGLE,
		0.0,
		output_delay_override,
	)
	if not str(record["spawn_object"]).is_empty():
		_emit_event("spawn_object", record, {
			"classname": str(record["spawn_object"]),
			"origin": record["center"],
			"owner_entity_id": int(record["entity_id"]),
		})
	if int(record["explosion_magnitude"]) > 0:
		_emit_event("explosion", record, {
			"origin": record["center"],
			"magnitude": int(record["explosion_magnitude"]),
			"mode": str(record["explosion_mode"]),
		})


func _emit_damage_event(
	record: Dictionary,
	attacker_id: int,
	damage_bits: int,
	applied_damage: float,
) -> void:
	var material := int(record["material"])
	var sounds: Array = DAMAGE_SOUNDS.get(material, [])
	var sound := (
		str(sounds[_random_int(record, sounds.size())])
		if not sounds.is_empty()
		else ""
	)
	var pitch := 100
	if _random_int(record, 3) == 0:
		pitch = 95 + _random_int(record, 35)
	_emit_event("damage", record, {
		"attacker_id": attacker_id,
		"damage_bits": damage_bits,
		"applied_damage": applied_damage,
		"remaining_health": float(record["health"]),
		"sound": sound,
		"pitch": pitch,
		"volume": 0.75 + _random_float(record) * 0.25,
	})


func _emit_event(event_name: String, record: Dictionary, fields: Dictionary) -> void:
	var event: Dictionary = {
		"event": event_name,
		"tick": int(_entity_world.tick),
		"sequence": _event_sequence,
		"entity_id": int(record["entity_id"]),
		"model_index": int(record["model_index"]),
		"material": int(record["material"]),
		"material_name": str(record["material_name"]),
	}
	_event_sequence += 1
	event.merge(fields, true)
	events.append(event)
	runtime_event.emit(event.duplicate(true))


func _random_int(record: Dictionary, upper_exclusive: int) -> int:
	record["rng_state"] = (
		(int(record["rng_state"]) * 1103515245 + 12345)
		& 0x7fffffff
	)
	if upper_exclusive <= 1:
		return 0
	return int(record["rng_state"]) % upper_exclusive


func _random_float(record: Dictionary) -> float:
	return float(_random_int(record, 0x7fffffff)) / float(0x7ffffffe)


func _authored_attack_direction(record: Dictionary) -> Vector3:
	var yaw := deg_to_rad(float(record["angle"]))
	return Vector3(cos(yaw), 0.0, -sin(yaw)).normalized()


func _godot_velocity_from_source(source_velocity: Vector3) -> Vector3:
	return Vector3(
		source_velocity.x,
		source_velocity.z,
		-source_velocity.y,
	)


func _break_flag(material: int) -> int:
	match material:
		MAT_GLASS:
			return BREAK_GLASS
		MAT_WOOD:
			return BREAK_WOOD
		MAT_METAL, MAT_COMPUTER:
			return BREAK_METAL
		MAT_FLESH:
			return BREAK_FLESH
		MAT_CINDER_BLOCK, MAT_ROCKS:
			return BREAK_CONCRETE
	return 0


func _break_flag_name(material: int) -> String:
	match _break_flag(material):
		BREAK_GLASS:
			return "glass"
		BREAK_WOOD:
			return "wood"
		BREAK_METAL:
			return "metal"
		BREAK_FLESH:
			return "flesh"
		BREAK_CONCRETE:
			return "concrete"
	return "none"


func _properties(raw: Dictionary) -> Dictionary:
	var result := {}
	for raw_pair: Variant in raw.get("properties", []):
		if raw_pair is Array and raw_pair.size() >= 2:
			result[str(raw_pair[0])] = str(raw_pair[1])
	return result


func _float_property(properties: Dictionary, key: String, default_value: float) -> float:
	if not properties.has(key):
		return default_value
	return str(properties[key]).to_float()


func _int_property(properties: Dictionary, key: String, default_value: int) -> int:
	if not properties.has(key):
		return default_value
	return str(properties[key]).to_int()


func _seconds_to_ticks(seconds: float) -> int:
	return maxi(0, roundi(maxf(0.0, seconds) * float(TICK_RATE)))
