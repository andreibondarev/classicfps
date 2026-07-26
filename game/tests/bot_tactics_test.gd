extends SceneTree

const BotTactics = preload("res://scripts/cs16_bot_tactics.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_reaction_and_memory()
	_test_bursts_and_reload()
	_test_determinism()
	_test_continuous_aim()
	_test_render_schedule_equivalence()
	if failures.is_empty():
		print("GAME_BOT_TACTICS_TEST_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _visible_observation(distance_hu := 900.0) -> Dictionary:
	return {
		"visible": true,
		"enemy_alive": true,
		"enemy_position": Vector3(4.0, 0.53, -9.0),
		"enemy_velocity": Vector3(0.8, 0.0, 0.0),
		"distance_hu": distance_hu,
	}


func _test_reaction_and_memory() -> void:
	var tactics := BotTactics.new()
	tactics.reset(47, 1.0)
	var observation := _visible_observation()
	var first := tactics.advance_ticks(1, observation)
	_check(first.state == BotTactics.STATE_REACT, "newly seen enemy enters reaction state")
	_check(not first.fire, "bot cannot fire on the acquisition tick")
	var reacted := tactics.advance_ticks(16, observation)
	_check(reacted.state == BotTactics.STATE_ENGAGE, "expert reaction completes in 160 ms")
	_check(reacted.fire, "first shot is emitted when reaction completes")
	observation["visible"] = false
	var search := tactics.advance_ticks(120, observation)
	_check(search.state == BotTactics.STATE_SEARCH, "bot searches recent last-seen position")
	var hunt := tactics.advance_ticks(61, observation)
	_check(
		hunt.state == BotTactics.STATE_HUNT,
		"visual memory expires after 1.8 seconds (got %s at tick %d, last seen %d)"
		% [hunt.state, hunt.tick, hunt.last_seen_tick],
	)


func _test_bursts_and_reload() -> void:
	var tactics := BotTactics.new()
	tactics.reset(901, 1.0)
	var observation := _visible_observation(300.0)
	var fire_ticks: Array[int] = []
	var reload_tick := -1
	for ignored in range(1200):
		var output := tactics.advance_ticks(1, observation)
		if output.fire:
			fire_ticks.append(int(output.tick))
		if output.reload and reload_tick < 0:
			reload_tick = int(output.tick)
	_check(fire_ticks.size() > 30, "bot resumes fire after a source-timed reload")
	_check(reload_tick > 0, "empty magazine emits reload command")
	_check(
		tactics.reserve == 60,
		"one completed AK reload consumes exactly 30 reserve rounds",
	)
	var has_burst_pause := false
	for index in range(1, fire_ticks.size()):
		var gap := fire_ticks[index] - fire_ticks[index - 1]
		if gap >= 28:
			has_burst_pause = true
			break
	_check(has_burst_pause, "automatic fire contains deterministic inter-burst pauses")


func _test_determinism() -> void:
	var a := BotTactics.new()
	var b := BotTactics.new()
	a.reset(1337, 0.82)
	b.reset(1337, 0.82)
	var observation := _visible_observation(1800.0)
	var trace_a: Array[Dictionary] = []
	var trace_b: Array[Dictionary] = []
	for ignored in range(600):
		var output_a := a.advance_ticks(1, observation)
		var output_b := b.advance_ticks(1, observation)
		if output_a.fire or output_a.reload:
			trace_a.append(output_a)
		if output_b.fire or output_b.reload:
			trace_b.append(output_b)
	_check(trace_a == trace_b, "same seed and observations produce byte-equivalent event traces")


func _test_continuous_aim() -> void:
	var tactics := BotTactics.new()
	tactics.reset(47, 1.0)
	var first_observation := _visible_observation(900.0)
	var first := tactics.advance_ticks(1, first_observation)
	var moved_observation := first_observation.duplicate(true)
	moved_observation.enemy_position = (
		first_observation.enemy_position + Vector3(1.25, 0.0, -0.5)
	)
	var moved := tactics.advance_ticks(1, moved_observation)
	_check(
		moved.last_seen_position == moved_observation.enemy_position,
		"visible target position is sampled on every 100 Hz perception tick",
	)
	_check(
		not (moved.aim_target as Vector3).is_equal_approx(first.aim_target),
		"bot aim follows a moving target instead of freezing at acquisition",
	)


func _render_trace(fps: int) -> Dictionary:
	var tactics := BotTactics.new()
	tactics.reset(901, 1.0)
	var observation := _visible_observation(300.0)
	var events: Array[Dictionary] = []
	for ignored in range(fps * 12):
		var output := tactics.advance_seconds(1.0 / float(fps), observation)
		for event: Dictionary in output.fire_events:
			events.append(event)
		for reload_tick: int in output.reload_ticks:
			events.append({
				"tick": reload_tick,
				"reload": true,
			})
	return {
		"events": events,
		"tick": tactics.tick,
		"clip": tactics.clip,
		"reserve": tactics.reserve,
		"shots": tactics.shots_fired,
	}


func _test_render_schedule_equivalence() -> void:
	var at_30 := _render_trace(30)
	var at_60 := _render_trace(60)
	var at_144 := _render_trace(144)
	_check(
		at_30 == at_60 and at_30 == at_144,
		"30/60/144 Hz callers preserve identical actor fire/reload/ammo traces",
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
