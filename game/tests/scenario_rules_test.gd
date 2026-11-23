extends SceneTree

const ScenarioRules := preload("res://scripts/cs16_scenario_rules.gd")
const RoundState := preload("res://scripts/cs16_round_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_assert_scenario_classification()
	_assert_timeout_routes()
	_assert_round_kernel_routes_scenario()
	_assert_round_objective_bridge()
	_assert_hostage_resolution()
	_assert_vip_resolution()
	_assert_escape_resolution()
	if failures.is_empty():
		print("GAME_SCENARIO_RULES_TEST_PASS")
		quit(0)
	else:
		print("GAME_SCENARIO_RULES_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SCENARIO RULES TEST: " + message)


func _entity(classname: String) -> Dictionary:
	return {"classname": classname, "properties": [["classname", classname]]}


func _assert_scenario_classification() -> void:
	var assault_file := FileAccess.open("res://generated/cs_assault/map.json", FileAccess.READ)
	_check(assault_file != null, "stock cs_assault conversion is packaged")
	if assault_file != null:
		var assault: Variant = JSON.parse_string(assault_file.get_as_text())
		var result: Dictionary = ScenarioRules.classify_entities(assault.get("entities", []))
		_check(
			result.scenario == ScenarioRules.SCENARIO_HOSTAGE
			and int(result.hostage_count) == 4,
			"stock cs_assault classifies as a four-hostage rescue map",
		)
		_check(
			not bool(result.has_brush_rescue)
			and int(result.legacy_rescue_points) == 0,
			"stock cs_assault uses the source CT-spawn rescue fallback",
		)

	var mixed := [
		_entity("hostage_entity"),
		_entity("func_bomb_target"),
		_entity("func_escapezone"),
		_entity("info_vip_start"),
	]
	_check(
		ScenarioRules.classify_entities(mixed).scenario == ScenarioRules.SCENARIO_VIP,
		"malformed mixed maps preserve VIP→escape→bomb→hostage precedence",
	)
	_check(
		ScenarioRules.classify_entities([_entity("func_escapezone")]).scenario
		== ScenarioRules.SCENARIO_ESCAPE,
		"func_escapezone selects the prison-escape scenario",
	)
	_check(
		ScenarioRules.classify_entities([_entity("func_bomb_target")]).scenario
		== ScenarioRules.SCENARIO_BOMB,
		"func_bomb_target selects the bomb scenario",
	)


func _assert_timeout_routes() -> void:
	var expected := {
		ScenarioRules.SCENARIO_BOMB: ["CT", "target_saved", 3250],
		ScenarioRules.SCENARIO_HOSTAGE: ["T", "hostages_not_rescued", 3250],
		ScenarioRules.SCENARIO_VIP: ["T", "vip_not_escaped", 3250],
		ScenarioRules.SCENARIO_ESCAPE: ["CT", "terrorists_not_escaped", 0],
	}
	for scenario: String in expected:
		var result: Dictionary = ScenarioRules.timeout_result(scenario)
		var contract: Array = expected[scenario]
		_check(
			result.winner == contract[0]
			and result.reason == contract[1]
			and int(result.team_reward) == contract[2],
			"%s timeout matches the source winner/reason/reward" % scenario,
		)


func _assert_round_kernel_routes_scenario() -> void:
	for scenario: String in [
		ScenarioRules.SCENARIO_HOSTAGE,
		ScenarioRules.SCENARIO_VIP,
		ScenarioRules.SCENARIO_ESCAPE,
	]:
		var state: RefCounted = RoundState.new()
		state.configure({
			"scenario": scenario,
			"freeze_ticks": 1,
			"round_ticks": 2,
			"restart_ticks": 1,
		})
		state.register_player("t1", "T")
		state.register_player("ct1", "CT")
		state.start_match()
		_check(
			state.bomb_owner.is_empty() and state.bomb_state == "none",
			"%s rounds do not invent a C4 owner" % scenario,
		)
		state.advance_tick()
		state.advance_tick()
		state.advance_tick()
		var expected: Dictionary = ScenarioRules.timeout_result(scenario)
		_check(
			state.round_winner == expected.winner
			and state.round_reason == expected.reason,
			"%s live timeout is routed through the scenario kernel" % scenario,
		)


func _assert_round_objective_bridge() -> void:
	var state: RefCounted = RoundState.new()
	state.configure({
		"scenario": ScenarioRules.SCENARIO_HOSTAGE,
		"freeze_ticks": 1,
		"round_ticks": 1000,
	})
	state.register_player("t1", "T", 800)
	state.register_player("ct1", "CT", 800)
	state.start_match()
	_check(
		not state.resolve_scenario_objective("CT", "all_hostages_rescued", 2500),
		"scenario objectives cannot resolve during freeze time",
	)
	state.advance_tick()
	_check(
		state.adjust_player_money("ct1", 150, "hostage_touched") == 150
		and int(state.players.ct1.money) == 950,
		"scenario bridge applies bounded individual rewards",
	)
	_check(
		state.adjust_player_money("ct1", -2000, "hostage_injured") == -950
		and int(state.players.ct1.money) == 0,
		"scenario bridge clamps penalties at zero cash",
	)
	_check(
		state.add_pending_team_account("CT", 100, "hostage_touched")
		and int(state.pending_team_accounts.CT) == 100,
		"scenario bridge records deterministic pending team supplements",
	)
	_check(
		state.resolve_scenario_objective("CT", "all_hostages_rescued", 2500)
		and state.phase == "post"
		and state.round_winner == "CT"
		and state.round_reason == "all_hostages_rescued",
		"scenario objective bridge ends a live hostage round",
	)


func _assert_hostage_resolution() -> void:
	_check(
		ScenarioRules.hostage_result(4, 1, 3).is_empty(),
		"a living hostage prevents the all-hostages resolution",
	)
	_check(
		ScenarioRules.hostage_result(4, 0, 1).is_empty(),
		"fewer than half rescued does not award the CT hostage objective",
	)
	var half: Dictionary = ScenarioRules.hostage_result(4, 0, 2)
	_check(
		half.winner == "CT"
		and half.reason == "all_hostages_rescued"
		and int(half.team_reward) == 2500,
		"exactly half rescued meets the classic hostage win threshold",
	)


func _assert_vip_resolution() -> void:
	_check(
		ScenarioRules.vip_result(true, false).is_empty(),
		"a living unescaped VIP leaves the round active",
	)
	_check(
		ScenarioRules.vip_result(true, true).winner == "CT"
		and int(ScenarioRules.vip_result(true, true).team_reward) == 3500,
		"VIP safety-zone touch awards the CT objective",
	)
	_check(
		ScenarioRules.vip_result(false, false).winner == "T"
		and int(ScenarioRules.vip_result(false, false).team_reward) == 3250,
		"VIP assassination awards the Terrorist objective",
	)


func _assert_escape_resolution() -> void:
	for starting in range(1, 11):
		var required := ScenarioRules.required_escape_count(starting)
		_check(
			required == ceili(float(starting) * 0.5),
			"%d starting Ts require the source ceiling-half escape count" % starting,
		)
		if required > 0:
			_check(
				ScenarioRules.escape_result(starting, required - 1, 1).is_empty(),
				"%d-player escape stays live one escape below threshold" % starting,
			)
			var escaped: Dictionary = ScenarioRules.escape_result(starting, required, 1)
			_check(
				escaped.winner == "T" and int(escaped.team_reward) == 3150,
				"%d-player escape resolves exactly at threshold" % starting,
			)
	var prevented: Dictionary = ScenarioRules.escape_result(4, 1, 0)
	_check(
		prevented.winner == "CT"
		and int(prevented.team_reward) == 2625,
		"escape elimination scales the CT reward by the unescaped ratio",
	)
