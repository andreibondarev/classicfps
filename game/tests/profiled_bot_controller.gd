extends BotCombatController

## Diagnostic-only subclass: all decisions and collision queries use super.
## Keep only slow decisions so a long run cannot grow an unbounded trace.
var cpu_events: Array[Dictionary] = []
var _sweep_us := 0
var _sweep_count := 0
var _route_us := 0
var _sweep_max_us := 0
var _sweep_max_distance := 0.0
var _swept_distance := 0.0
static var _seen_tick := -1
static var _seen_space := RID()
static var _seen_queries: Dictionary = {}
static var _seen_count := 0
var _repeated_sweeps := 0
var _repeated_sweep_us := 0
var _changed_results := 0


func gather_command(delta: float) -> Dictionary:
	_sweep_us = 0
	_sweep_count = 0
	_route_us = 0
	_sweep_max_us = 0
	_sweep_max_distance = 0.0
	_swept_distance = 0.0
	_repeated_sweeps = 0
	_repeated_sweep_us = 0
	_changed_results = 0
	var started := Time.get_ticks_usec()
	var command := super.gather_command(delta)
	var elapsed := Time.get_ticks_usec() - started
	if elapsed >= 2000 and cpu_events.size() < 256:
		cpu_events.append({"engine_physics_tick": Engine.get_physics_frames(),
			"actor": str(actor.name), "command_ms": float(elapsed) / 1000.0,
			"route_ms": float(_route_us) / 1000.0,
			"sweep_ms": float(_sweep_us) / 1000.0, "sweeps": _sweep_count,
			"slowest_sweep_ms": float(_sweep_max_us) / 1000.0,
			"slowest_sweep_meters": _sweep_max_distance, "swept_meters": _swept_distance,
			"repeated_sweeps": _repeated_sweeps, "repeated_sweep_ms": float(_repeated_sweep_us) / 1000.0,
			"repeated_result_changes": _changed_results,
			"state": command.get("state", "")})
	return command


func _objective_navigation_velocity_to(target_position: Vector3, delta: float) -> Vector3:
	var started := Time.get_ticks_usec()
	var result := super._objective_navigation_velocity_to(target_position, delta)
	_route_us += Time.get_ticks_usec() - started
	return result


func _objective_segment_is_bsp_clear(start: Vector3, finish: Vector3) -> bool:
	var started := Time.get_ticks_usec()
	var result := super._objective_segment_is_bsp_clear(start, finish)
	var elapsed := Time.get_ticks_usec() - started
	_sweep_us += elapsed
	var distance := start.distance_to(finish)
	_swept_distance += distance
	if elapsed > _sweep_max_us:
		_sweep_max_us = elapsed
		_sweep_max_distance = distance
	_sweep_count += 1
	# Observe exact directed endpoint repeats across bots, but ALWAYS perform
	# the production cast. Same-tick reuse is not assumed safe: a preceding
	# bot may have changed breakable collision before another bot's decision.
	var tick := Engine.get_physics_frames()
	var space := actor.get_world_3d().space
	if tick != _seen_tick or space != _seen_space:
		_seen_tick = tick
		_seen_space = space
		_seen_queries = {}
		_seen_count = 0
	if _seen_queries.has(start) and _seen_queries[start].has(finish):
		_repeated_sweeps += 1
		_repeated_sweep_us += elapsed
		if bool(_seen_queries[start][finish]) != result:
			_changed_results += 1
	elif _seen_count < 4096:
		if not _seen_queries.has(start):
			_seen_queries[start] = {}
		_seen_queries[start][finish] = result
		_seen_count += 1
	return result
