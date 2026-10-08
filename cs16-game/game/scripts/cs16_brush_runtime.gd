class_name CS16BrushRuntime
extends RefCounted

## Fixed-step runtime for the classic BSP brush movers. Geometry and collision
## remain children of BspMap's shared model root, so one transform moves both.

signal runtime_event(event: Dictionary)

const EntityWorld := preload("res://scripts/cs16_entity_world.gd")

const TICK_RATE := 100
const GOLD_SRC_TO_GODOT := 0.01

const STATE_CLOSED := "closed"
const STATE_OPEN := "open"
const STATE_OPENING := "opening"
const STATE_CLOSING := "closing"

const KIND_LINEAR_DOOR := "func_door"
const KIND_ROTATING_DOOR := "func_door_rotating"
const KIND_BUTTON := "func_button"

const SF_DOOR_START_OPEN := 1 << 0
const SF_DOOR_ROTATE_BACKWARDS := 1 << 1
const SF_DOOR_PASSABLE := 1 << 3
const SF_DOOR_ROTATE_ONEWAY := 1 << 4
const SF_DOOR_NO_AUTO_RETURN := 1 << 5
const SF_DOOR_ROTATE_Z := 1 << 6
const SF_DOOR_ROTATE_X := 1 << 7
const SF_DOOR_USE_ONLY := 1 << 8

const SF_BUTTON_DONT_MOVE := 1 << 0
const SF_BUTTON_TOGGLE := 1 << 5
const SF_BUTTON_TOUCH_ONLY := 1 << 8

var events: Array[Dictionary] = []

var _bsp_map: Variant
var _entity_world: Variant
var _brushes: Dictionary = {}
var _round_snapshot: Dictionary = {}
var _activator_positions: Dictionary = {}
var _event_sequence := 0


## The supplied entity world must already contain bsp_map.entities in BSP order.
## Configuration binds handlers, applies source capabilities, positions
## start-open movers, then advances the world's round snapshot to this map-ready
## state.
func configure(bsp_map: Variant, entity_world: Variant) -> int:
	_bsp_map = bsp_map
	_entity_world = entity_world
	_brushes.clear()
	_round_snapshot.clear()
	_activator_positions.clear()
	events.clear()
	_event_sequence = 0

	var raw_entities: Array = bsp_map.entities
	assert(
		entity_world.entity_count() == raw_entities.size(),
		"CS16BrushRuntime requires the same BSP entity array in CS16EntityWorld",
	)
	for array_index in range(raw_entities.size()):
		var raw: Dictionary = raw_entities[array_index]
		var classname := str(raw.get("classname", ""))
		if (
			classname != KIND_LINEAR_DOOR
			and classname != KIND_ROTATING_DOOR
			and classname != KIND_BUTTON
		):
			continue
		var map_entity_index := int(raw.get("entity_index", array_index))
		var model_index := int(bsp_map.model_index_for_entity(map_entity_index))
		if model_index <= 0 or bsp_map.model_root(model_index) == null:
			continue
		var record := _make_record(
			array_index,
			map_entity_index,
			model_index,
			classname,
			raw,
		)
		_brushes[array_index] = record
		entity_world.set_capabilities(array_index, _capabilities_for(record))
		entity_world.set_entity_state(array_index, record["state"] == STATE_OPEN)
		entity_world.bind_handler(
			array_index,
			Callable(self, "_on_entity_use").bind(array_index),
		)
		_apply_transform(record, record["current_transform"])

	_round_snapshot = _brushes.duplicate(true)
	entity_world.capture_round_start()
	return _brushes.size()


func brush_count() -> int:
	return _brushes.size()


func has_entity(entity_id: int) -> bool:
	return _brushes.has(entity_id)


func get_brush(entity_id: int) -> Dictionary:
	if not _brushes.has(entity_id):
		return {}
	return (_brushes[entity_id] as Dictionary).duplicate(true)


func set_activator_position(activator_id: int, position: Vector3) -> void:
	_activator_positions[activator_id] = position


func clear_activator_position(activator_id: int) -> void:
	_activator_positions.erase(activator_id)


## Owns one complete 10 ms simulation quantum: entity inputs and delayed
## outputs resolve first, followed by brush thinks and pusher movement.
func advance_tick(advance_entity_world := true) -> Array[Dictionary]:
	var start := events.size()
	if advance_entity_world:
		_entity_world.advance_tick()
	_process_due_returns()
	_advance_movers()
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
	_brushes = _round_snapshot.duplicate(true)
	events.clear()
	_event_sequence = 0
	_activator_positions.clear()
	var ids: Array = _brushes.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = _brushes[int(raw_id)]
		_apply_transform(record, record["current_transform"])


func _make_record(
	entity_id: int,
	map_entity_index: int,
	model_index: int,
	classname: String,
	raw: Dictionary,
) -> Dictionary:
	var properties := _properties(raw)
	var spawnflags := _int_property(properties, "spawnflags", 0)
	var initial_transform: Transform3D = _bsp_map.initial_transform_for_model(model_index)
	var authored_angles := _vector_property(properties, "angles", Vector3.ZERO)
	if not properties.has("angles") and properties.has("angle"):
		authored_angles.y = _float_property(properties, "angle", 0.0)
	var authored_basis := _basis_from_goldsrc_angles(authored_angles)
	var closed_transform := initial_transform
	# SetMovedir consumes and clears angles on linear doors/buttons; those keys
	# select translation direction and must not rotate the authored BSP brush.
	# Rotating doors retain their explicit starting angles.
	if classname == KIND_ROTATING_DOOR:
		closed_transform.basis = authored_basis * initial_transform.basis

	var speed := _float_property(properties, "speed", 0.0)
	var wait_seconds: float
	var lip: float
	var open_transform := closed_transform
	var distance := 0.0
	var move_axis := Vector3.ZERO
	var open_angle := 0.0
	if classname == KIND_BUTTON:
		if is_zero_approx(speed):
			speed = 40.0
		wait_seconds = _float_property(properties, "wait", 0.0)
		if is_zero_approx(wait_seconds):
			wait_seconds = 1.0
		lip = _float_property(properties, "lip", 0.0)
		if is_zero_approx(lip):
			lip = 4.0
		move_axis = _linear_move_axis(properties)
		distance = _linear_travel(model_index, move_axis, lip)
		if (
			distance < GOLD_SRC_TO_GODOT
			or (spawnflags & SF_BUTTON_DONT_MOVE) != 0
		):
			distance = 0.0
		open_transform.origin += move_axis * distance
	elif classname == KIND_ROTATING_DOOR:
		if is_zero_approx(speed):
			speed = 100.0
		wait_seconds = _float_property(
			properties,
			"wait",
			3.0 if not properties.has("wait") else 0.0,
		)
		lip = _float_property(properties, "lip", 0.0)
		distance = absf(_float_property(
			properties,
			"distance",
			90.0 if not properties.has("distance") else 0.0,
		))
		move_axis = _rotation_axis(spawnflags)
		var direction := -1.0 if (spawnflags & SF_DOOR_ROTATE_BACKWARDS) != 0 else 1.0
		open_angle = distance * direction
		open_transform.basis = (
			Basis(move_axis, deg_to_rad(open_angle))
			* closed_transform.basis
		)
	else:
		if is_zero_approx(speed):
			speed = 100.0
		wait_seconds = _float_property(
			properties,
			"wait",
			3.0 if not properties.has("wait") else 0.0,
		)
		lip = _float_property(
			properties,
			"lip",
			8.0 if not properties.has("lip") else 0.0,
		)
		move_axis = _linear_move_axis(properties)
		distance = _linear_travel(model_index, move_axis, lip)
		open_transform.origin += move_axis * distance

	var start_open := (
		classname != KIND_BUTTON
		and (spawnflags & SF_DOOR_START_OPEN) != 0
	)
	var initial_state := STATE_OPEN if start_open else STATE_CLOSED
	var current_transform := open_transform if start_open else closed_transform
	return {
		"entity_id": entity_id,
		"map_entity_index": map_entity_index,
		"model_index": model_index,
		"classname": classname,
		"properties": properties,
		"spawnflags": spawnflags,
		"speed": speed,
		"wait_seconds": wait_seconds,
		"wait_ticks": _seconds_to_ticks(wait_seconds),
		"lip": lip,
		"distance": distance,
		"move_axis": move_axis,
		"open_angle": open_angle,
		"authored_angles": authored_angles,
		"start_open": start_open,
		"no_auto_return": (
			classname != KIND_BUTTON
			and (spawnflags & SF_DOOR_NO_AUTO_RETURN) != 0
		),
		"use_only": (
			classname != KIND_BUTTON
			and (spawnflags & SF_DOOR_USE_ONLY) != 0
		),
		"toggle": (
			classname == KIND_BUTTON
			and (spawnflags & SF_BUTTON_TOGGLE) != 0
		),
		"dont_move": (
			classname == KIND_BUTTON
			and (spawnflags & SF_BUTTON_DONT_MOVE) != 0
		),
		"touch_only": (
			classname == KIND_BUTTON
			and (spawnflags & SF_BUTTON_TOUCH_ONLY) != 0
		),
		"closed_transform": closed_transform,
		"open_transform": open_transform,
		"current_transform": current_transform,
		"motion_start_transform": current_transform,
		"motion_end_transform": current_transform,
		"motion_progress": 0.0,
		"motion_total": 0.0,
		"motion_per_tick": 0.0,
		"motion_rotation_degrees": 0.0,
		"motion_goal": initial_state,
		"state": initial_state,
		"return_tick": -1,
		"activator_id": -1,
		"movesnd": _int_property(properties, "movesnd", 0),
		"stopsnd": _int_property(properties, "stopsnd", 0),
		"button_sound": _int_property(properties, "sounds", 0),
	}


func _capabilities_for(record: Dictionary) -> int:
	var classname := str(record["classname"])
	if classname == KIND_BUTTON:
		return (
			EntityWorld.CAP_TOUCH
			if bool(record["touch_only"])
			else EntityWorld.CAP_USE_PRESSED
		)
	if bool(record["use_only"]):
		return EntityWorld.CAP_USE_PRESSED
	if str(record["properties"].get("targetname", "")).is_empty():
		return EntityWorld.CAP_TOUCH
	return 0


func _on_entity_use(event: Dictionary, entity_id: int) -> void:
	if not _brushes.has(entity_id):
		return
	var record: Dictionary = _brushes[entity_id]
	record["activator_id"] = int(event.get("activator_id", -1))
	if str(record["classname"]) == KIND_BUTTON:
		_activate_button(record)
	else:
		_activate_door(record)


func _activate_door(record: Dictionary) -> void:
	var state := str(record["state"])
	if state == STATE_OPENING or state == STATE_CLOSING:
		return
	var rest_state := STATE_OPEN if bool(record["start_open"]) else STATE_CLOSED
	var activated_state := STATE_CLOSED if bool(record["start_open"]) else STATE_OPEN
	if bool(record["no_auto_return"]):
		_start_motion(
			record,
			STATE_CLOSED if state == STATE_OPEN else STATE_OPEN,
		)
	elif state == rest_state:
		_start_motion(record, activated_state)


func _activate_button(record: Dictionary) -> void:
	var state := str(record["state"])
	if state == STATE_OPENING or state == STATE_CLOSING:
		return
	if state == STATE_CLOSED:
		_start_motion(record, STATE_OPEN)
	elif (
		state == STATE_OPEN
		and bool(record["toggle"])
		and int(record["wait_ticks"]) >= 0
	):
		record["return_tick"] = -1
		_start_motion(record, STATE_CLOSED)


func _start_motion(record: Dictionary, goal: String) -> void:
	var from_state := str(record["state"])
	var target: Transform3D = (
		record["open_transform"]
		if goal == STATE_OPEN
		else record["closed_transform"]
	)
	if (
		str(record["classname"]) == KIND_ROTATING_DOOR
		and goal == STATE_OPEN
		and from_state == STATE_CLOSED
		and not bool(record["start_open"])
	):
		var sign := _rotating_open_sign(record)
		var backwards := (
			-1.0
			if (int(record["spawnflags"]) & SF_DOOR_ROTATE_BACKWARDS) != 0
			else 1.0
		)
		target.basis = (
			Basis(
				record["move_axis"],
				deg_to_rad(float(record["distance"]) * sign * backwards),
			)
			* (record["closed_transform"] as Transform3D).basis
		)
		record["open_angle"] = float(record["distance"]) * sign * backwards
		record["open_transform"] = target

	record["motion_start_transform"] = record["current_transform"]
	record["motion_end_transform"] = target
	record["motion_progress"] = 0.0
	record["motion_goal"] = goal
	record["return_tick"] = -1
	record["state"] = STATE_OPENING if goal == STATE_OPEN else STATE_CLOSING
	if str(record["classname"]) == KIND_ROTATING_DOOR:
		record["motion_rotation_degrees"] = (
			float(record["open_angle"])
			if goal == STATE_OPEN
			else -float(record["open_angle"])
		)
		record["motion_total"] = absf(float(record["motion_rotation_degrees"]))
		record["motion_per_tick"] = float(record["speed"]) / float(TICK_RATE)
	else:
		record["motion_total"] = (
			(record["current_transform"] as Transform3D).origin
			.distance_to(target.origin)
		)
		record["motion_per_tick"] = (
			float(record["speed"])
			* GOLD_SRC_TO_GODOT
			/ float(TICK_RATE)
		)
	_emit_event("move", record, {
		"from_state": from_state,
		"to_state": str(record["state"]),
		"goal": goal,
		"speed": float(record["speed"]),
	})
	if is_zero_approx(float(record["motion_total"])):
		_apply_transform(record, target)
		_finish_motion(record)


func _process_due_returns() -> void:
	var ids: Array = _brushes.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = _brushes[int(raw_id)]
		var return_tick := int(record["return_tick"])
		if return_tick >= 0 and return_tick <= int(_entity_world.tick):
			record["return_tick"] = -1
			var goal := (
				STATE_OPEN
				if bool(record["start_open"])
				and str(record["classname"]) != KIND_BUTTON
				else STATE_CLOSED
			)
			_start_motion(record, goal)


func _advance_movers() -> void:
	var ids: Array = _brushes.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = _brushes[int(raw_id)]
		var state := str(record["state"])
		if state != STATE_OPENING and state != STATE_CLOSING:
			continue
		var total := float(record["motion_total"])
		if is_zero_approx(total):
			continue
		var progress := minf(
			total,
			float(record["motion_progress"]) + float(record["motion_per_tick"]),
		)
		record["motion_progress"] = progress
		var alpha := progress / total
		var start: Transform3D = record["motion_start_transform"]
		var finish: Transform3D = record["motion_end_transform"]
		var value: Transform3D
		if str(record["classname"]) == KIND_ROTATING_DOOR:
			value = start
			value.origin = start.origin.lerp(finish.origin, alpha)
			value.basis = (
				Basis(
					record["move_axis"],
					deg_to_rad(float(record["motion_rotation_degrees"]) * alpha),
				)
				* start.basis
			)
		else:
			value = start.interpolate_with(finish, alpha)
		_apply_transform(record, value)
		if is_equal_approx(progress, total):
			_apply_transform(record, finish)
			_finish_motion(record)


func _finish_motion(record: Dictionary) -> void:
	var goal := str(record["motion_goal"])
	record["state"] = goal
	record["motion_progress"] = float(record["motion_total"])
	_entity_world.set_entity_state(int(record["entity_id"]), goal == STATE_OPEN)
	_emit_event("stop", record, {"state": goal})

	var classname := str(record["classname"])
	if classname == KIND_BUTTON:
		if goal == STATE_OPEN:
			_entity_world.emit_outputs(
				int(record["entity_id"]),
				int(record["activator_id"]),
				EntityWorld.USE_TOGGLE,
			)
			if not bool(record["toggle"]) and int(record["wait_ticks"]) >= 0:
				record["return_tick"] = int(_entity_world.tick) + int(record["wait_ticks"])
		elif goal == STATE_CLOSED and bool(record["toggle"]):
			_entity_world.emit_outputs(
				int(record["entity_id"]),
				int(record["activator_id"]),
				EntityWorld.USE_TOGGLE,
			)
		return

	_entity_world.emit_outputs(
		int(record["entity_id"]),
		int(record["activator_id"]),
		EntityWorld.USE_TOGGLE,
	)
	var activated_state := STATE_CLOSED if bool(record["start_open"]) else STATE_OPEN
	if (
		goal == activated_state
		and not bool(record["no_auto_return"])
		and int(record["wait_ticks"]) >= 0
	):
		record["return_tick"] = int(_entity_world.tick) + int(record["wait_ticks"])


func _apply_transform(record: Dictionary, value: Transform3D) -> void:
	record["current_transform"] = value
	_bsp_map.set_model_runtime_transform(int(record["model_index"]), value)


func _emit_event(event_name: String, record: Dictionary, fields: Dictionary) -> void:
	var event: Dictionary = {
		"event": event_name,
		"tick": int(_entity_world.tick),
		"sequence": _event_sequence,
		"entity_id": int(record["entity_id"]),
		"model_index": int(record["model_index"]),
		"classname": str(record["classname"]),
		"movesnd": int(record["movesnd"]),
		"stopsnd": int(record["stopsnd"]),
		"button_sound": int(record["button_sound"]),
	}
	_event_sequence += 1
	event.merge(fields, true)
	events.append(event)
	runtime_event.emit(event.duplicate(true))


func _linear_travel(model_index: int, direction: Vector3, lip_units: float) -> float:
	var bounds: AABB = _bsp_map.model_bounds_for_index(model_index)
	var adjusted := Vector3(
		maxf(0.0, bounds.size.x - 2.0 * GOLD_SRC_TO_GODOT),
		maxf(0.0, bounds.size.y - 2.0 * GOLD_SRC_TO_GODOT),
		maxf(0.0, bounds.size.z - 2.0 * GOLD_SRC_TO_GODOT),
	)
	return maxf(
		0.0,
		absf(direction.x * adjusted.x)
		+ absf(direction.y * adjusted.y)
		+ absf(direction.z * adjusted.z)
		- lip_units * GOLD_SRC_TO_GODOT,
	)


func _linear_move_axis(properties: Dictionary) -> Vector3:
	var angles := _vector_property(properties, "angles", Vector3.ZERO)
	if not properties.has("angles"):
		angles.y = _float_property(properties, "angle", 0.0)
	if is_equal_approx(angles.y, -1.0) and is_zero_approx(angles.x) and is_zero_approx(angles.z):
		return Vector3.UP
	if is_equal_approx(angles.y, -2.0) and is_zero_approx(angles.x) and is_zero_approx(angles.z):
		return Vector3.DOWN
	var pitch := deg_to_rad(angles.x)
	var yaw := deg_to_rad(angles.y)
	var source_forward := Vector3(
		cos(pitch) * cos(yaw),
		cos(pitch) * sin(yaw),
		-sin(pitch),
	)
	return Vector3(
		source_forward.x,
		source_forward.z,
		-source_forward.y,
	).normalized()


func _rotation_axis(spawnflags: int) -> Vector3:
	if (spawnflags & SF_DOOR_ROTATE_Z) != 0:
		return Vector3.RIGHT
	if (spawnflags & SF_DOOR_ROTATE_X) != 0:
		return Vector3(0.0, 0.0, -1.0)
	return Vector3.UP


func _basis_from_goldsrc_angles(angles: Vector3) -> Basis:
	return (
		Basis(Vector3.UP, deg_to_rad(angles.y))
		* Basis(Vector3(0.0, 0.0, -1.0), deg_to_rad(angles.x))
		* Basis(Vector3.RIGHT, deg_to_rad(angles.z))
	)


func _rotating_open_sign(record: Dictionary) -> float:
	if (int(record["spawnflags"]) & SF_DOOR_ROTATE_ONEWAY) != 0:
		return 1.0
	var activator_id := int(record["activator_id"])
	if not _activator_positions.has(activator_id):
		return 1.0
	# GoldSrc only selects an away-from-player sign for the ordinary yaw axis.
	if (record["move_axis"] as Vector3).distance_to(Vector3.UP) > 0.001:
		return 1.0
	var closed: Transform3D = record["closed_transform"]
	var bounds: AABB = _bsp_map.model_bounds_for_index(int(record["model_index"]))
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner_index in range(8):
		var source_corner := _godot_to_goldsrc(closed * bounds.get_endpoint(corner_index))
		low.x = minf(low.x, source_corner.x)
		low.y = minf(low.y, source_corner.y)
		high.x = maxf(high.x, source_corner.x)
		high.y = maxf(high.y, source_corner.y)
	var origin := _godot_to_goldsrc(closed.origin)
	var actor := _godot_to_goldsrc(_activator_positions[activator_id])
	var moment_x := actor.x - origin.x
	var moment_y := actor.y - origin.y

	# Branch-for-branch translation of CBaseDoor::DoorGoUp's yaw-door
	# moment-arm test (ReGameDLL fixes use float absolute values).
	if low.x > actor.x:
		if actor.y < low.y:
			if absf(moment_y) > absf(moment_x):
				return 1.0 if moment_y < 0.0 else -1.0
			return 1.0 if moment_x > 0.0 else -1.0
		if actor.y > high.y:
			if absf(moment_y) > absf(moment_x):
				return 1.0 if moment_y < 0.0 else -1.0
			return 1.0 if moment_x < 0.0 else -1.0
		return 1.0 if moment_y < 0.0 else -1.0

	if actor.x <= high.x:
		if actor.y < low.y:
			return 1.0 if moment_x > 0.0 else -1.0
		if actor.y > high.y:
			return 1.0 if moment_x < 0.0 else -1.0
	elif actor.y < low.y:
		if absf(moment_y) > absf(moment_x):
			return 1.0 if moment_y > 0.0 else -1.0
		return 1.0 if moment_x > 0.0 else -1.0
	elif actor.y > high.y:
		if absf(moment_y) > absf(moment_x):
			return 1.0 if moment_y > 0.0 else -1.0
		return 1.0 if moment_x < 0.0 else -1.0
	else:
		return 1.0 if moment_y > 0.0 else -1.0
	return 1.0


func _godot_to_goldsrc(value: Vector3) -> Vector3:
	return Vector3(
		value.x / GOLD_SRC_TO_GODOT,
		-value.z / GOLD_SRC_TO_GODOT,
		value.y / GOLD_SRC_TO_GODOT,
	)


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


func _vector_property(
	properties: Dictionary,
	key: String,
	default_value: Vector3,
) -> Vector3:
	if not properties.has(key):
		return default_value
	var parts := str(properties[key]).split(" ", false)
	if parts.size() < 3:
		return default_value
	return Vector3(
		str(parts[0]).to_float(),
		str(parts[1]).to_float(),
		str(parts[2]).to_float(),
	)


func _seconds_to_ticks(seconds: float) -> int:
	if seconds < 0.0:
		return -1
	return maxi(0, roundi(seconds * float(TICK_RATE)))
