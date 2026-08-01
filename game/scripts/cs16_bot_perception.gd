class_name CS16BotPerception
extends RefCounted

## Deterministic 100 Hz bot vision and visual-memory boundary.
##
## The provider may inspect live world state only on a scheduled scan. Consumers
## receive either a currently visible sample or the frozen last-seen sample, so
## navigation and aim never accidentally follow an occluded actor transform.

const TICK_RATE := 100
const SCAN_INTERVAL_TICKS := 10
const SEARCH_TICKS := 180
const HALF_FOV_DEGREES := 45.0
const HALF_FOV_DOT := 0.7071067811865476
const DEFAULT_MAX_RANGE := 8192.0 * 0.01
const DISTANCE_EPSILON := 0.000001
## A hit from outside the vision cone is a stimulus, not an acquisition: the bot
## needs this long before it starts turning toward the damage source.
const DAMAGE_REACTION_TICKS := 22
## How long the stimulus keeps steering the bot when nothing is acquired.
const DAMAGE_MEMORY_TICKS := 400

var tick := 0
var current_target: Object
var current_target_id := ""
var visible := false
var last_seen_position := Vector3.ZERO
var last_seen_velocity := Vector3.ZERO
var last_seen_tick := -1
var occluded_tick := -1
var scan_count := 0
var damage_source_position := Vector3.ZERO
var damage_source_tick := -1
var damage_source_id := ""
var damage_reaction_ticks := DAMAGE_REACTION_TICKS

var _second_accumulator := 0.0
var _next_scan_tick := SCAN_INTERVAL_TICKS
var _candidate_provider := Callable()
var _visibility_predicate := Callable()
var _blind_predicate := Callable()
var _smoke_predicate := Callable()
var _events: Array[Dictionary] = []
var _tick_samples: Array[Dictionary] = []
var _max_range := DEFAULT_MAX_RANGE
var _damage_source: Object


func configure(
	candidate_provider: Callable,
	visibility_predicate: Callable,
	blind_predicate := Callable(),
	smoke_predicate := Callable(),
	max_range := DEFAULT_MAX_RANGE,
) -> void:
	_candidate_provider = candidate_provider
	_visibility_predicate = visibility_predicate
	_blind_predicate = blind_predicate
	_smoke_predicate = smoke_predicate
	_max_range = maxf(0.0, float(max_range))


func reset() -> void:
	tick = 0
	current_target = null
	current_target_id = ""
	visible = false
	last_seen_position = Vector3.ZERO
	last_seen_velocity = Vector3.ZERO
	last_seen_tick = -1
	occluded_tick = -1
	scan_count = 0
	damage_source_position = Vector3.ZERO
	damage_source_tick = -1
	damage_source_id = ""
	_damage_source = null
	_second_accumulator = 0.0
	_next_scan_tick = SCAN_INTERVAL_TICKS
	_events.clear()
	_tick_samples.clear()


func note_damage(
	attacker: Object,
	attacker_position: Vector3,
	attacker_id := "",
) -> void:
	## Records where a hit came from on the perception clock. The stimulus never
	## reads the attacker's live transform again: this frozen sample is what the
	## bot turns toward until it sees something for itself.
	if not is_instance_valid(attacker):
		return
	_damage_source = attacker
	damage_source_id = attacker_id
	damage_source_position = attacker_position
	damage_source_tick = tick


func damage_stimulus_active() -> bool:
	return (
		is_instance_valid(_damage_source)
		and damage_source_tick >= 0
		and tick - damage_source_tick >= damage_reaction_ticks
		and tick - damage_source_tick <= DAMAGE_MEMORY_TICKS
	)


func is_investigating() -> bool:
	return damage_stimulus_active() and not is_instance_valid(current_target)


func advance_seconds(
	delta: float,
	observer_origin: Vector3,
	observer_forward: Vector3,
) -> Dictionary:
	_second_accumulator += maxf(0.0, delta) * float(TICK_RATE)
	var elapsed_ticks := int(floor(_second_accumulator + 0.000001))
	if elapsed_ticks > 0:
		_second_accumulator -= float(elapsed_ticks)
	return advance_ticks(elapsed_ticks, observer_origin, observer_forward)


func advance_ticks(
	count: int,
	observer_origin: Vector3,
	observer_forward: Vector3,
) -> Dictionary:
	_events.clear()
	_tick_samples.clear()
	for ignored in range(maxi(0, count)):
		_advance_tick(observer_origin, observer_forward)
		_tick_samples.append(_sample())
	var result := snapshot()
	result.events = _events.duplicate(true)
	result.tick_samples = _tick_samples.duplicate(true)
	return result


func snapshot() -> Dictionary:
	var investigating := is_investigating()
	var state := "investigate" if investigating else "patrol"
	if is_instance_valid(current_target):
		state = "visible" if visible else "search"
	return {
		"tick": tick,
		"state": state,
		"investigating": investigating,
		"damage_position": damage_source_position,
		"damage_tick": damage_source_tick,
		"target": current_target,
		"target_id": current_target_id,
		"visible": visible,
		"position": last_seen_position,
		"velocity": last_seen_velocity,
		"last_seen_tick": last_seen_tick,
		"occluded_tick": occluded_tick,
		"scan_count": scan_count,
		"events": [],
		"tick_samples": [],
	}


func _advance_tick(observer_origin: Vector3, observer_forward: Vector3) -> void:
	tick += 1
	if tick >= _next_scan_tick:
		_next_scan_tick += SCAN_INTERVAL_TICKS
		_scan(observer_origin, observer_forward)
	if (
		is_instance_valid(current_target)
		and not visible
		and occluded_tick >= 0
		and tick - occluded_tick >= SEARCH_TICKS
	):
		_clear_target("memory_expired")


func _scan(observer_origin: Vector3, observer_forward: Vector3) -> void:
	scan_count += 1
	var candidates: Array = []
	if _candidate_provider.is_valid():
		var provided: Variant = _candidate_provider.call(tick)
		if provided is Array:
			candidates = provided
	var blind := (
		bool(_blind_predicate.call(tick))
		if _blind_predicate.is_valid()
		else false
	)

	if is_instance_valid(current_target):
		var tracked := _candidate_for_current_target(candidates)
		if tracked.is_empty() or not bool(tracked.get("alive", true)):
			_clear_target("target_invalid")
		else:
			var tracked_visible := (
				not blind
				and _candidate_is_visible(
					tracked,
					observer_origin,
					observer_forward,
					false,
				)
			)
			if tracked_visible:
				_record_visible(tracked, "tracked")
			elif visible:
				visible = false
				occluded_tick = tick
				_emit("occluded", current_target_id)

	if is_instance_valid(current_target) or blind:
		return

	var stimulus_active := damage_stimulus_active()
	var best: Dictionary = {}
	var best_distance := INF
	var best_id := ""
	for raw_candidate: Variant in candidates:
		if not raw_candidate is Dictionary:
			continue
		var candidate: Dictionary = raw_candidate
		if not bool(candidate.get("alive", true)):
			continue
		var candidate_target: Object = candidate.get("target")
		if not is_instance_valid(candidate_target):
			continue
		# A bot that has just been shot may acquire its attacker outside the
		# vision cone — it is turning toward the hit — but line of sight is
		# still required, so cover keeps working.
		var require_fov := not (
			stimulus_active and candidate_target == _damage_source
		)
		if not _candidate_is_visible(
			candidate,
			observer_origin,
			observer_forward,
			require_fov,
		):
			continue
		var position: Vector3 = candidate.get("position", Vector3.ZERO)
		var distance := observer_origin.distance_squared_to(position)
		var candidate_id := str(candidate.get("id", ""))
		if (
			distance < best_distance - DISTANCE_EPSILON
			or (
				absf(distance - best_distance) <= DISTANCE_EPSILON
				and (
					best.is_empty()
					or candidate_id.naturalnocasecmp_to(best_id) < 0
				)
			)
		):
			best = candidate
			best_distance = distance
			best_id = candidate_id
	if not best.is_empty():
		current_target = best.get("target")
		current_target_id = str(best.get("id", ""))
		_record_visible(best, "acquired")


func _candidate_for_current_target(candidates: Array) -> Dictionary:
	for raw_candidate: Variant in candidates:
		if not raw_candidate is Dictionary:
			continue
		var candidate: Dictionary = raw_candidate
		if candidate.get("target") == current_target:
			return candidate
	return {}


func _candidate_is_visible(
	candidate: Dictionary,
	observer_origin: Vector3,
	observer_forward: Vector3,
	require_fov: bool,
) -> bool:
	var position: Vector3 = candidate.get("position", Vector3.ZERO)
	if observer_origin.distance_squared_to(position) > _max_range * _max_range:
		return false
	if require_fov and not horizontal_fov_contains(
		observer_origin,
		observer_forward,
		position,
	):
		return false
	var probes: Variant = candidate.get("probes", PackedVector3Array())
	var visible_probe_count := 0
	for raw_probe: Variant in probes:
		var probe: Vector3 = raw_probe
		var smoked := (
			bool(
				_smoke_predicate.call(
					observer_origin,
					probe,
					candidate,
					tick,
				)
			)
			if _smoke_predicate.is_valid()
			else false
		)
		var has_los := (
			bool(_visibility_predicate.call(candidate, probe, tick))
			if _visibility_predicate.is_valid()
			else false
		)
		if has_los and not smoked:
			visible_probe_count += 1
	return visible_probe_count > 0


func _record_visible(candidate: Dictionary, reason: String) -> void:
	var was_visible := visible
	current_target = candidate.get("target")
	current_target_id = str(candidate.get("id", current_target_id))
	visible = true
	last_seen_position = candidate.get("position", last_seen_position)
	last_seen_velocity = candidate.get("velocity", Vector3.ZERO)
	last_seen_tick = tick
	occluded_tick = -1
	if reason == "acquired" or not was_visible:
		_emit(reason, current_target_id)


func _clear_target(reason: String) -> void:
	var cleared_id := current_target_id
	current_target = null
	current_target_id = ""
	visible = false
	occluded_tick = -1
	_emit(reason, cleared_id)


func _sample() -> Dictionary:
	var result := snapshot()
	result.erase("events")
	result.erase("tick_samples")
	return result


func _emit(event_type: String, target_id: String) -> void:
	_events.append({
		"tick": tick,
		"type": event_type,
		"target_id": target_id,
		"position": last_seen_position,
		"velocity": last_seen_velocity,
	})


static func horizontal_fov_contains(
	observer_origin: Vector3,
	observer_forward: Vector3,
	target_position: Vector3,
) -> bool:
	var forward := Vector2(observer_forward.x, observer_forward.z)
	var to_target := Vector2(
		target_position.x - observer_origin.x,
		target_position.z - observer_origin.z,
	)
	if to_target.is_zero_approx():
		return true
	if forward.is_zero_approx():
		return false
	return forward.normalized().dot(to_target.normalized()) >= HALF_FOV_DOT
