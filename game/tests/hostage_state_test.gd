extends SceneTree

const HostageState := preload("res://scripts/cs16_hostage_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_assert_use_and_follow()
	_assert_damage_contract()
	_assert_rescue_and_reset()
	if failures.is_empty():
		print("GAME_HOSTAGE_STATE_TEST_PASS")
		quit(0)
	else:
		print("GAME_HOSTAGE_STATE_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("HOSTAGE STATE TEST: " + message)


func _fixture(count := 1) -> RefCounted:
	var state: RefCounted = HostageState.new()
	for index in count:
		state.register_hostage(
			"h%d" % index,
			Vector3(float(index * 64), 0.0, 0.0),
			index % 2,
			270.0,
		)
	state.start_round()
	return state


func _advance(state: RefCounted, ticks: int) -> void:
	for ignored in ticks:
		state.advance_tick()


func _assert_use_and_follow() -> void:
	var state := _fixture()
	_check(
		state.use_hostage("h0", "t1", "T").is_empty(),
		"Terrorists cannot command a hostage",
	)
	var first: Dictionary = state.use_hostage("h0", "ct1", "CT")
	_check(
		first.following
		and first.first_use
		and int(first.player_reward) == 150
		and int(first.team_reward) == 100,
		"first CT use starts following and emits exact first-touch rewards",
	)
	_check(
		state.use_hostage("h0", "ct1", "CT").is_empty(),
		"hostage use is locked for the exact one-second cooldown",
	)
	_advance(state, 100)
	var stopped: Dictionary = state.use_hostage("h0", "ct1", "CT")
	_check(
		not stopped.following
		and not stopped.first_use
		and int(stopped.player_reward) == 0,
		"same leader toggles following off after cooldown without duplicate reward",
	)
	_advance(state, 100)
	state.use_hostage("h0", "ct2", "CT")
	_check(
		state.release_invalid_leader("h0", false)
		and not bool(state.hostages.h0.following),
		"leader death releases the hostage",
	)
	_advance(state, 100)
	state.use_hostage("h0", "ct2", "CT")
	state.update_stuck("h0", true)
	_advance(state, 500)
	_check(
		not state.update_stuck("h0", true),
		"stuck recovery does not fire at exactly five seconds",
	)
	state.advance_tick()
	_check(
		state.update_stuck("h0", true)
		and not bool(state.hostages.h0.following),
		"stuck recovery releases after more than five seconds",
	)


func _assert_damage_contract() -> void:
	var state := _fixture()
	var arm: Dictionary = state.apply_damage("h0", 10.0, "left_arm", "ct1")
	_check(
		is_equal_approx(float(arm.actual_damage), 7.5)
		and int(arm.money_penalty) == -150,
		"arm damage uses the 0.75 multiplier and -$20 per actual point",
	)
	var lethal: Dictionary = state.apply_damage("h0", 100.0, "head", "ct1")
	_check(
		lethal.killed
		and is_equal_approx(float(lethal.actual_damage), 92.5)
		and int(lethal.money_penalty) == -2350,
		"lethal head damage clamps actual health loss and applies source kill penalty",
	)
	_check(
		state.apply_damage("h0", 1.0, "generic", "ct1").is_empty(),
		"dead hostages reject further damage",
	)


func _assert_rescue_and_reset() -> void:
	var state := _fixture(4)
	for index in 2:
		var rescued: Dictionary = state.rescue("h%d" % index, "ct1")
		_check(
			int(rescued.player_reward) == 1000
			and int(rescued.next_round_ct_reward) == 750,
			"each rescue emits exact player and next-round CT supplements",
		)
	state.apply_damage("h2", 1000.0, "generic", "t1")
	state.apply_damage("h3", 1000.0, "generic", "t1")
	var result: Dictionary = state.round_result()
	_check(
		result.winner == "CT"
		and result.reason == "all_hostages_rescued"
		and int(result.team_reward) == 2500,
		"two rescued of four with no living hostage meets the 50% CT win rule",
	)
	state.start_round()
	var snapshot: Dictionary = state.snapshot()
	_check(
		int(snapshot.rescued_count) == 0
		and int(snapshot.alive_unrescued_count) == 4,
		"round reset restores every hostage alive and unrescued",
	)
	for hostage: Dictionary in snapshot.hostages.values():
		_check(
			is_equal_approx(float(hostage.health), 100.0)
			and not bool(hostage.following)
			and not bool(hostage.ever_used),
			"round reset restores health, use, and follow state",
		)
