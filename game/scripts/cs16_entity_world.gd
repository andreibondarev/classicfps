class_name CS16EntityWorld
extends RefCounted

## Deterministic, renderer-independent GoldSrc entity dispatch.
##
## Entity ids are zero-based BSP order and never change.  BSP key/value pairs are
## retained in their original order (including duplicates); keyvalue() returns the
## last occurrence, matching GoldSrc's parse-time overwrite behavior.

const TICK_RATE := 100

const USE_OFF := 0
const USE_ON := 1
const USE_SET := 2
const USE_TOGGLE := 3

const INPUT_PRESSED := "pressed"
const INPUT_HELD := "held"
const INPUT_RELEASED := "released"

const TOUCH_ENTER := "enter"
const TOUCH_STAY := "stay"
const TOUCH_EXIT := "exit"

const CAP_USE_PRESSED := 1 << 0
const CAP_USE_HELD := 1 << 1
const CAP_USE_RELEASED := 1 << 2
const CAP_TOUCH := 1 << 3
const CAP_FIRE_OUTPUTS := 1 << 4
const CAP_STATEFUL := 1 << 5
const CAP_MASTER := 1 << 6

const DEFAULT_CAPABILITIES := CAP_USE_PRESSED | CAP_FIRE_OUTPUTS
const MAX_RECURSION_DEPTH := 128

var tick: int = 0
var trace: Array[Dictionary] = []

var _entities: Array[Dictionary] = []
var _targetname_index: Dictionary = {}
var _handlers: Dictionary = {}
var _input_queue: Array[Dictionary] = []
var _scheduled: Array[Dictionary] = []
var _round_snapshot: Array[Dictionary] = []
var _round_snapshot_valid := false
var _input_sequence := 0
var _scheduled_sequence := 0
var _trace_sequence := 0
var _dispatch_depth := 0


func load_entities(raw_entities: Array) -> void:
	_entities.clear()
	_targetname_index.clear()
	_handlers.clear()
	_input_queue.clear()
	_scheduled.clear()
	trace.clear()
	tick = 0
	_input_sequence = 0
	_scheduled_sequence = 0
	_trace_sequence = 0
	_dispatch_depth = 0

	for bsp_order in range(raw_entities.size()):
		var raw: Dictionary = raw_entities[bsp_order]
		var properties := _normalize_properties(raw.get("properties", []))
		var classname := _last_property(properties, "classname", str(raw.get("classname", "")))
		var delay_seconds := _property_float(properties, "delay", 0.0)
		var wait_seconds := _property_float(properties, "wait", 0.0)
		var has_triggerstate := _has_property(properties, "triggerstate")
		var triggerstate := _parse_triggerstate(_last_property(properties, "triggerstate", "1"))
		var capabilities := int(raw.get("capabilities", DEFAULT_CAPABILITIES))
		var entity_state := bool(raw.get("state", false))
		var record: Dictionary = {
			"id": bsp_order,
			"bsp_order": bsp_order,
			"classname": classname,
			"keyvalues": properties,
			"targetname": _last_property(properties, "targetname", ""),
			"target": _last_property(properties, "target", ""),
			"killtarget": _last_property(properties, "killtarget", ""),
			"master": _last_property(properties, "master", ""),
			"delay_ticks": _seconds_to_ticks(delay_seconds),
			"wait_ticks": _wait_to_ticks(wait_seconds),
			"has_triggerstate": has_triggerstate,
			"trigger_use": triggerstate,
			"capabilities": capabilities,
			"alive": true,
			"enabled": true,
			"state": entity_state,
			"value": float(raw.get("value", 1.0 if entity_state else 0.0)),
			"next_ready_tick": 0,
			"runtime": {},
		}
		_entities.append(record)

	_rebuild_targetname_index()
	capture_round_start()


func entity_count() -> int:
	return _entities.size()


func is_valid_entity(entity_id: int) -> bool:
	return entity_id >= 0 and entity_id < _entities.size()


func get_entity(entity_id: int) -> Dictionary:
	if not is_valid_entity(entity_id):
		return {}
	return _entities[entity_id].duplicate(true)


func keyvalue(entity_id: int, key: String, default_value: String = "") -> String:
	if not is_valid_entity(entity_id):
		return default_value
	return _last_property(_entities[entity_id]["keyvalues"], key, default_value)


func find_by_targetname(targetname: String, include_killed := false) -> Array[int]:
	var result: Array[int] = []
	for entity_id: int in _targetname_index.get(targetname, []):
		if include_killed or bool(_entities[entity_id]["alive"]):
			result.append(entity_id)
	return result


func bind_handler(entity_id: int, handler: Callable) -> void:
	assert(is_valid_entity(entity_id), "Invalid entity id %d" % entity_id)
	if handler.is_valid():
		_handlers[entity_id] = handler
	else:
		_handlers.erase(entity_id)


func set_capabilities(entity_id: int, capabilities: int) -> void:
	assert(is_valid_entity(entity_id), "Invalid entity id %d" % entity_id)
	_entities[entity_id]["capabilities"] = capabilities


func has_capability(entity_id: int, capability: int) -> bool:
	return (
		is_valid_entity(entity_id)
		and (int(_entities[entity_id]["capabilities"]) & capability) != 0
	)


func set_entity_state(entity_id: int, state: bool, value: float = NAN) -> void:
	assert(is_valid_entity(entity_id), "Invalid entity id %d" % entity_id)
	_entities[entity_id]["state"] = state
	_entities[entity_id]["value"] = (1.0 if state else 0.0) if is_nan(value) else value


func set_runtime_value(entity_id: int, key: String, value: Variant) -> void:
	assert(is_valid_entity(entity_id), "Invalid entity id %d" % entity_id)
	_entities[entity_id]["runtime"][key] = value


func runtime_value(entity_id: int, key: String, default_value: Variant = null) -> Variant:
	if not is_valid_entity(entity_id):
		return default_value
	return _entities[entity_id]["runtime"].get(key, default_value)


## Capture the canonical state restored by reset_round(). Handler bindings are
## intentionally external and survive resets.
func capture_round_start() -> void:
	_round_snapshot = _entities.duplicate(true)
	_round_snapshot_valid = true


## Restores entity life/state/cooldowns/runtime data and clears all pending work.
## Round simulation time returns to tick zero.
func reset_round() -> void:
	if _round_snapshot_valid:
		_entities = _round_snapshot.duplicate(true)
	_rebuild_targetname_index()
	_input_queue.clear()
	_scheduled.clear()
	trace.clear()
	tick = 0
	_input_sequence = 0
	_scheduled_sequence = 0
	_trace_sequence = 0
	_dispatch_depth = 0


## Player-use input is sampled at 100 Hz. The default contracts mirror GoldSrc:
## pressed/held dispatch USE_SET(1), released dispatches USE_SET(0).
func queue_use(
	entity_id: int,
	activator_id: int,
	phase: String,
	value_override: Variant = null,
) -> bool:
	var required_capability := _use_phase_capability(phase)
	if required_capability == 0 or not has_capability(entity_id, required_capability):
		return false
	var value := 0.0 if phase == INPUT_RELEASED else 1.0
	if value_override != null:
		value = float(value_override)
	_enqueue_input({
		"kind": "use_input",
		"phase": phase,
		"entity_id": entity_id,
		"activator_id": activator_id,
		"caller_id": activator_id,
		"use_type": USE_SET,
		"value": value,
	})
	return true


## Touches share the same ordered per-tick queue as use input. Inputs are
## processed strictly by enqueue sequence, independent of kind.
func queue_touch(entity_id: int, activator_id: int, phase := TOUCH_ENTER) -> bool:
	if not has_capability(entity_id, CAP_TOUCH):
		return false
	if phase != TOUCH_ENTER and phase != TOUCH_STAY and phase != TOUCH_EXIT:
		return false
	_enqueue_input({
		"kind": "touch_input",
		"phase": phase,
		"entity_id": entity_id,
		"activator_id": activator_id,
		"caller_id": activator_id,
		"use_type": USE_SET,
		"value": 0.0 if phase == TOUCH_EXIT else 1.0,
	})
	return true


## Direct explicit-use entry point for entity implementations and tests.
func use_entity(
	entity_id: int,
	activator_id: int,
	caller_id: int,
	use_type: int,
	value := 0.0,
	source_kind := "direct",
	phase := "",
) -> bool:
	if not _valid_use_type(use_type):
		return false
	return _invoke_entity(
		entity_id,
		activator_id,
		caller_id,
		use_type,
		value,
		source_kind,
		phase,
	)


## Fire every live matching target in stable BSP order.
func fire_targets(
	targetname: String,
	activator_id: int,
	caller_id: int,
	use_type: int,
	value := 0.0,
	source_kind := "target",
) -> int:
	if targetname.is_empty() or not _valid_use_type(use_type):
		return 0
	var fired := 0
	for entity_id: int in find_by_targetname(targetname):
		if _dispatch_depth >= MAX_RECURSION_DEPTH:
			_record_trace({
				"event": "recursion_blocked",
				"targetname": targetname,
				"entity_id": entity_id,
				"depth": _dispatch_depth,
			})
			break
		_dispatch_depth += 1
		if _invoke_entity(
			entity_id,
			activator_id,
			caller_id,
			use_type,
			value,
			source_kind,
			"",
		):
			fired += 1
		_dispatch_depth -= 1
	return fired


## Let a bound runtime complete a CBaseDelay-style action at the correct point
## in its lifecycle. This preserves this world's triggerstate, delay,
## killtarget-before-target, and deterministic recursion contracts without
## forcing movers to duplicate output dispatch.
func emit_outputs(
	entity_id: int,
	activator_id: int,
	use_type := USE_TOGGLE,
	value := 0.0,
	delay_override_ticks := -1,
) -> bool:
	if not is_valid_entity(entity_id) or not bool(_entities[entity_id]["alive"]):
		return false
	if not _valid_use_type(use_type):
		return false
	_emit_entity_outputs(
		entity_id,
		activator_id,
		use_type,
		value,
		delay_override_ticks,
	)
	return true


## Advance one fixed 10 ms quantum. Delayed fires due on this tick execute first,
## then use/touch inputs in their global enqueue order. Inputs queued by a handler
## are intentionally deferred until the next tick.
func advance_tick() -> Array[Dictionary]:
	tick += 1
	var trace_start := trace.size()
	_process_due_fires()
	var ready_inputs := _input_queue
	_input_queue = []
	ready_inputs.sort_custom(_input_before)
	for event: Dictionary in ready_inputs:
		_invoke_entity(
			int(event["entity_id"]),
			int(event["activator_id"]),
			int(event["caller_id"]),
			int(event["use_type"]),
			float(event["value"]),
			str(event["kind"]),
			str(event["phase"]),
		)
	return trace.slice(trace_start)


func advance_ticks(count: int) -> void:
	for _step in range(maxi(0, count)):
		advance_tick()


func _invoke_entity(
	entity_id: int,
	activator_id: int,
	caller_id: int,
	use_type: int,
	value: float,
	source_kind: String,
	phase: String,
) -> bool:
	if not is_valid_entity(entity_id):
		return false
	var record: Dictionary = _entities[entity_id]
	if not bool(record["alive"]) or not bool(record["enabled"]):
		return false
	if not _master_is_triggered(str(record["master"]), activator_id):
		_record_trace({
			"event": "master_blocked",
			"entity_id": entity_id,
			"master": str(record["master"]),
			"activator_id": activator_id,
		})
		return false
	if tick < int(record["next_ready_tick"]):
		_record_trace({
			"event": "wait_blocked",
			"entity_id": entity_id,
			"ready_tick": int(record["next_ready_tick"]),
		})
		return false

	if has_capability(entity_id, CAP_STATEFUL):
		if not _apply_use_state(record, use_type, value):
			_record_trace({
				"event": "use_ignored",
				"entity_id": entity_id,
				"use_type": use_type,
				"value": value,
			})
			return false

	var event: Dictionary = {
		"event": "use",
		"tick": tick,
		"entity_id": entity_id,
		"activator_id": activator_id,
		"caller_id": caller_id,
		"use_type": use_type,
		"value": value,
		"source_kind": source_kind,
		"phase": phase,
		"state": bool(record["state"]),
	}
	_record_trace(event)
	if _handlers.has(entity_id):
		var handler: Callable = _handlers[entity_id]
		if handler.is_valid():
			handler.call(event.duplicate(true))

	if has_capability(entity_id, CAP_FIRE_OUTPUTS):
		var wait_ticks := int(record["wait_ticks"])
		if wait_ticks > 0:
			record["next_ready_tick"] = tick + wait_ticks
		elif wait_ticks < 0:
			record["enabled"] = false
		_emit_entity_outputs(entity_id, activator_id, use_type, value)
	return true


func _emit_entity_outputs(
	entity_id: int,
	activator_id: int,
	incoming_use_type: int,
	value: float,
	delay_override_ticks := -1,
) -> void:
	var record: Dictionary = _entities[entity_id]
	var output_use_type := (
		int(record["trigger_use"])
		if bool(record["has_triggerstate"])
		else incoming_use_type
	)
	var output: Dictionary = {
		"target": str(record["target"]),
		"killtarget": str(record["killtarget"]),
		"activator_id": activator_id,
		"caller_id": entity_id,
		"use_type": output_use_type,
		"value": value,
	}
	var delay_ticks := (
		delay_override_ticks
		if delay_override_ticks >= 0
		else int(record["delay_ticks"])
	)
	if delay_ticks > 0:
		output["due_tick"] = tick + delay_ticks
		output["sequence"] = _scheduled_sequence
		_scheduled_sequence += 1
		_scheduled.append(output)
		_record_trace({
			"event": "scheduled",
			"entity_id": entity_id,
			"due_tick": int(output["due_tick"]),
			"sequence": int(output["sequence"]),
		})
	else:
		_execute_output(output, "target")


func _execute_output(output: Dictionary, source_kind: String) -> void:
	var killtarget := str(output["killtarget"])
	if not killtarget.is_empty():
		for entity_id: int in find_by_targetname(killtarget):
			_entities[entity_id]["alive"] = false
			_record_trace({
				"event": "killed",
				"entity_id": entity_id,
				"killtarget": killtarget,
				"caller_id": int(output["caller_id"]),
			})
	var target := str(output["target"])
	if not target.is_empty():
		fire_targets(
			target,
			int(output["activator_id"]),
			int(output["caller_id"]),
			int(output["use_type"]),
			float(output["value"]),
			source_kind,
		)


func _process_due_fires() -> void:
	_scheduled.sort_custom(_scheduled_before)
	while not _scheduled.is_empty() and int(_scheduled[0]["due_tick"]) <= tick:
		var output: Dictionary = _scheduled.pop_front()
		_execute_output(output, "delayed")


func _master_is_triggered(master: String, activator_id: int) -> bool:
	if master.is_empty():
		return true
	for entity_id: int in find_by_targetname(master):
		if has_capability(entity_id, CAP_MASTER):
			return bool(_entities[entity_id]["state"])
	# GoldSrc warns but treats a missing/non-master target as unlocked.
	return true


func _apply_use_state(record: Dictionary, use_type: int, value: float) -> bool:
	var current := bool(record["state"])
	match use_type:
		USE_OFF:
			if not current:
				return false
			record["state"] = false
			record["value"] = 0.0
		USE_ON:
			if current:
				return false
			record["state"] = true
			record["value"] = 1.0
		USE_SET:
			record["state"] = not is_zero_approx(value)
			record["value"] = value
		USE_TOGGLE:
			record["state"] = not current
			record["value"] = 1.0 if not current else 0.0
	return true


func _enqueue_input(event: Dictionary) -> void:
	event["sequence"] = _input_sequence
	_input_sequence += 1
	_input_queue.append(event)


func _record_trace(event: Dictionary) -> void:
	event["tick"] = tick
	event["sequence"] = _trace_sequence
	_trace_sequence += 1
	trace.append(event)


func _rebuild_targetname_index() -> void:
	_targetname_index.clear()
	for entity_id in range(_entities.size()):
		var targetname := str(_entities[entity_id]["targetname"])
		if targetname.is_empty():
			continue
		if not _targetname_index.has(targetname):
			_targetname_index[targetname] = []
		_targetname_index[targetname].append(entity_id)


func _normalize_properties(raw_properties: Variant) -> Array:
	var properties: Array = []
	if raw_properties is Array:
		for raw_pair: Variant in raw_properties:
			if raw_pair is Array and raw_pair.size() >= 2:
				properties.append([str(raw_pair[0]), str(raw_pair[1])])
	return properties


func _last_property(
	properties: Array,
	key: String,
	default_value: String,
) -> String:
	var result := default_value
	for pair: Array in properties:
		if str(pair[0]) == key:
			result = str(pair[1])
	return result


func _has_property(properties: Array, key: String) -> bool:
	for pair: Array in properties:
		if str(pair[0]) == key:
			return true
	return false


func _property_float(properties: Array, key: String, default_value: float) -> float:
	var text := _last_property(properties, key, "")
	return default_value if text.is_empty() else text.to_float()


func _seconds_to_ticks(seconds: float) -> int:
	return maxi(0, roundi(seconds * float(TICK_RATE)))


func _wait_to_ticks(seconds: float) -> int:
	if seconds < 0.0:
		return -1
	return _seconds_to_ticks(seconds)


func _parse_triggerstate(text: String) -> int:
	match text.to_int():
		0:
			return USE_OFF
		2:
			return USE_TOGGLE
		_:
			return USE_ON


func _use_phase_capability(phase: String) -> int:
	match phase:
		INPUT_PRESSED:
			return CAP_USE_PRESSED
		INPUT_HELD:
			return CAP_USE_HELD
		INPUT_RELEASED:
			return CAP_USE_RELEASED
	return 0


func _valid_use_type(use_type: int) -> bool:
	return (
		use_type == USE_OFF
		or use_type == USE_ON
		or use_type == USE_SET
		or use_type == USE_TOGGLE
	)


func _input_before(a: Dictionary, b: Dictionary) -> bool:
	return int(a["sequence"]) < int(b["sequence"])


func _scheduled_before(a: Dictionary, b: Dictionary) -> bool:
	var due_a := int(a["due_tick"])
	var due_b := int(b["due_tick"])
	if due_a == due_b:
		return int(a["sequence"]) < int(b["sequence"])
	return due_a < due_b
