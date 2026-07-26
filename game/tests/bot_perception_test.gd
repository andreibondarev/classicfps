extends SceneTree

const PerceptionScript := preload("res://scripts/cs16_bot_perception.gd")
const TacticsScript := preload("res://scripts/cs16_bot_tactics.gd")

const ORIGIN := Vector3.ZERO
const FORWARD := Vector3(0.0, 0.0, -1.0)

var failures: Array[String] = []


func _init() -> void:
	_test_horizontal_fov_and_tracking()
	_test_visible_candidate_selection()
	_test_probe_occlusion_and_exact_memory()
	_test_blind_and_smoke_hooks()
	_test_reacquisition_reaction()
	_test_render_schedule_equivalence()
	if failures.is_empty():
		print("GAME_BOT_PERCEPTION_TEST_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _target_at_angle(degrees: float, distance := 10.0) -> Vector3:
	var radians := deg_to_rad(degrees)
	return Vector3(
		sin(radians) * distance,
		0.4,
		-cos(radians) * distance,
	)


func _candidate(
	target: Object,
	target_id: String,
	position: Vector3,
	probe_visibility: Array,
	velocity := Vector3.ZERO,
) -> Dictionary:
	return {
		"target": target,
		"id": target_id,
		"alive": true,
		"position": position,
		"velocity": velocity,
		# Probe coordinates are stable indices for this pure perception test.
		"probes": PackedVector3Array([
			Vector3(0, 0, 0),
			Vector3(1, 0, 0),
			Vector3(2, 0, 0),
			Vector3(3, 0, 0),
			Vector3(4, 0, 0),
		]),
		"probe_visibility": probe_visibility,
		"probe_smoke": [false, false, false, false, false],
	}


func _make_perception(world: Dictionary) -> RefCounted:
	var perception := PerceptionScript.new()
	perception.configure(
		func(_tick: int) -> Array:
			return world.candidates,
		func(candidate: Dictionary, probe: Vector3, _tick: int) -> bool:
			world.probe_calls = int(world.get("probe_calls", 0)) + 1
			return bool(candidate.probe_visibility[int(probe.x)]),
		func(_tick: int) -> bool:
			return bool(world.get("blind", false)),
		func(
			_origin: Vector3,
			probe: Vector3,
			candidate: Dictionary,
			_tick: int,
		) -> bool:
			return bool(candidate.probe_smoke[int(probe.x)]),
	)
	return perception


func _new_world(candidates: Array) -> Dictionary:
	return {
		"candidates": candidates,
		"blind": false,
		"probe_calls": 0,
	}


func _test_horizontal_fov_and_tracking() -> void:
	for case: Dictionary in [
		{"angle": 44.0, "expected": true, "label": "44 degrees"},
		{"angle": 46.0, "expected": false, "label": "46 degrees"},
		{"angle": 180.0, "expected": false, "label": "behind"},
	]:
		var token := RefCounted.new()
		var candidate := _candidate(
			token,
			"target",
			_target_at_angle(float(case.angle)),
			[true, true, true, true, true],
		)
		var perception := _make_perception(_new_world([candidate]))
		var output: Dictionary = perception.advance_ticks(10, ORIGIN, FORWARD)
		_check(
			is_instance_valid(output.target) == bool(case.expected),
			"initial 90-degree horizontal FOV classifies %s" % case.label,
		)

	var tracked_token := RefCounted.new()
	var tracked_candidate := _candidate(
		tracked_token,
		"tracked",
		_target_at_angle(0.0),
		[true, true, true, true, true],
	)
	var tracked_world := _new_world([tracked_candidate])
	var tracked_perception := _make_perception(tracked_world)
	tracked_perception.advance_ticks(10, ORIGIN, FORWARD)
	tracked_candidate.position = _target_at_angle(100.0)
	var outside_fov: Dictionary = tracked_perception.advance_ticks(
		10,
		ORIGIN,
		FORWARD,
	)
	_check(
		outside_fov.target == tracked_token and bool(outside_fov.visible),
		"acquired target remains tracked outside FOV while LOS-visible",
	)


func _test_visible_candidate_selection() -> void:
	var hidden_token := RefCounted.new()
	var visible_token := RefCounted.new()
	var hidden_near := _candidate(
		hidden_token,
		"hidden_near",
		_target_at_angle(-10.0, 3.0),
		[false, false, false, false, false],
	)
	var visible_far := _candidate(
		visible_token,
		"visible_far",
		_target_at_angle(10.0, 7.0),
		[false, true, false, false, false],
	)
	var perception := _make_perception(_new_world([hidden_near, visible_far]))
	var output: Dictionary = perception.advance_ticks(10, ORIGIN, FORWARD)
	_check(
		output.target == visible_token,
		"farther visible enemy wins over nearer fully occluded enemy",
	)


func _test_probe_occlusion_and_exact_memory() -> void:
	var token := RefCounted.new()
	var candidate := _candidate(
		token,
		"partial",
		_target_at_angle(0.0),
		[false, false, true, false, false],
		Vector3(0.5, 0.0, 0.0),
	)
	var world := _new_world([candidate])
	var perception := _make_perception(world)
	var partial: Dictionary = perception.advance_ticks(10, ORIGIN, FORWARD)
	_check(
		partial.target == token and bool(partial.visible),
		"one visible body probe is sufficient for acquisition",
	)
	var frozen_position: Vector3 = partial.position
	var frozen_velocity: Vector3 = partial.velocity

	world.probe_calls = 0
	candidate.probe_visibility = [false, false, false, false, false]
	var occluded: Dictionary = perception.advance_ticks(10, ORIGIN, FORWARD)
	_check(
		occluded.state == "search"
		and int(world.probe_calls) == 5,
		"full occlusion checks all five probes and enters search",
	)
	candidate.position += Vector3(8.0, 0.0, 0.0)
	candidate.velocity = Vector3(8.0, 0.0, 0.0)
	var moved_hidden: Dictionary = perception.advance_ticks(10, ORIGIN, FORWARD)
	_check(
		moved_hidden.position == frozen_position
		and moved_hidden.velocity == frozen_velocity,
		"enemy moving 800 HU behind cover cannot change remembered route/look data",
	)

	var tick_180: Dictionary = perception.advance_ticks(169, ORIGIN, FORWARD)
	_check(
		tick_180.state == "search" and int(tick_180.tick) == 199,
		"search memory remains valid for exactly 180 occluded ticks",
	)
	var tick_181: Dictionary = perception.advance_ticks(1, ORIGIN, FORWARD)
	_check(
		tick_181.state == "patrol"
		and not is_instance_valid(tick_181.target)
		and int(tick_181.tick) == 200,
		"the 181st occluded tick clears target memory to patrol/objective",
	)


func _test_blind_and_smoke_hooks() -> void:
	var token := RefCounted.new()
	var candidate := _candidate(
		token,
		"hooks",
		_target_at_angle(0.0),
		[true, true, true, true, true],
	)
	var world := _new_world([candidate])
	world.blind = true
	var perception := _make_perception(world)
	var blinded: Dictionary = perception.advance_ticks(10, ORIGIN, FORWARD)
	_check(
		not is_instance_valid(blinded.target),
		"blind predicate blocks acquisition",
	)
	world.blind = false
	candidate.probe_smoke = [true, true, true, true, true]
	var smoked: Dictionary = perception.advance_ticks(10, ORIGIN, FORWARD)
	_check(
		not is_instance_valid(smoked.target),
		"smoke predicate blocks all five sight rays",
	)
	candidate.probe_smoke = [true, true, false, true, true]
	var smoke_gap: Dictionary = perception.advance_ticks(10, ORIGIN, FORWARD)
	_check(
		smoke_gap.target == token,
		"an unobscured visible body probe remains acquirable",
	)


func _test_reacquisition_reaction() -> void:
	var token := RefCounted.new()
	var candidate := _candidate(
		token,
		"reacquire",
		_target_at_angle(0.0),
		[true, true, true, true, true],
	)
	var world := _new_world([candidate])
	var perception := _make_perception(world)
	var tactics := TacticsScript.new()
	tactics.reset(47, 1.0)
	var acquired: Dictionary = perception.advance_ticks(10, ORIGIN, FORWARD)
	var reacted: Dictionary = tactics.advance_ticks(1, {
		"visible": acquired.visible,
		"enemy_alive": true,
		"enemy_position": acquired.position,
		"enemy_velocity": acquired.velocity,
		"distance_hu": 1000.0,
	})
	_check(
		reacted.state == TacticsScript.STATE_REACT and not reacted.fire,
		"initial acquisition enters reaction without firing",
	)
	tactics.advance_ticks(16, {
		"visible": true,
		"enemy_alive": true,
		"enemy_position": acquired.position,
		"enemy_velocity": acquired.velocity,
		"distance_hu": 1000.0,
	})
	candidate.probe_visibility = [false, false, false, false, false]
	var hidden: Dictionary = perception.advance_ticks(10, ORIGIN, FORWARD)
	var hidden_tactics: Dictionary = tactics.advance_ticks(1, {
		"visible": hidden.visible,
		"enemy_alive": true,
		"enemy_position": hidden.position,
		"enemy_velocity": hidden.velocity,
		"distance_hu": 1000.0,
	})
	_check(
		hidden_tactics.state == TacticsScript.STATE_SEARCH
		and not hidden_tactics.fire,
		"occluded target is searched without firing",
	)
	candidate.probe_visibility = [false, true, false, false, false]
	var reacquired: Dictionary = perception.advance_ticks(10, ORIGIN, FORWARD)
	var reacquired_tactics: Dictionary = tactics.advance_ticks(1, {
		"visible": reacquired.visible,
		"enemy_alive": true,
		"enemy_position": reacquired.position,
		"enemy_velocity": reacquired.velocity,
		"distance_hu": 1000.0,
	})
	_check(
		reacquired_tactics.state == TacticsScript.STATE_REACT
		and not reacquired_tactics.fire,
		"reacquisition pays the reaction delay again",
	)


func _perception_trace(fps: int) -> Dictionary:
	var token := RefCounted.new()
	var perception := PerceptionScript.new()
	perception.configure(
		func(scan_tick: int) -> Array:
			var candidate := _candidate(
				token,
				"trace",
				_target_at_angle(0.0) + Vector3(float(scan_tick) * 0.001, 0, 0),
				[true, true, true, true, true],
				Vector3(0.1, 0.0, 0.0),
			)
			candidate.probe_visibility = [
				scan_tick <= 50 or scan_tick >= 120,
				false,
				false,
				false,
				false,
			]
			return [candidate],
		func(candidate: Dictionary, probe: Vector3, _tick: int) -> bool:
			return bool(candidate.probe_visibility[int(probe.x)]),
	)
	var events: Array[Dictionary] = []
	for ignored in range(fps * 4):
		var output: Dictionary = perception.advance_seconds(
			1.0 / float(fps),
			ORIGIN,
			FORWARD,
		)
		events.append_array(output.events)
	var final := perception.snapshot()
	return {
		"tick": final.tick,
		"state": final.state,
		"target_id": final.target_id,
		"last_seen_tick": final.last_seen_tick,
		"position": final.position,
		"events": events,
	}


func _test_render_schedule_equivalence() -> void:
	var at_30 := _perception_trace(30)
	var at_60 := _perception_trace(60)
	var at_144 := _perception_trace(144)
	_check(
		at_30 == at_60 and at_30 == at_144,
		"30/60/144 Hz callers preserve identical 100 Hz perception traces",
	)
