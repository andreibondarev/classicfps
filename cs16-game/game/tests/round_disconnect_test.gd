extends SceneTree

const RoundScript = preload("res://scripts/cs16_round_state.gd")
const ScenarioScript = preload("res://scripts/cs16_scenario_rules.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _fixture(scenario := ScenarioScript.SCENARIO_BOMB) -> RefCounted:
	var state: RefCounted = RoundScript.new()
	state.configure({"scenario": scenario, "freeze_ticks": 1, "plant_ticks": 2,
		"c4_ticks": 100, "defuse_ticks": 20, "defuse_kit_ticks": 10})
	for id: String in ["t1", "t2", "ct1", "ct2"]:
		state.register_player(id, "CT" if id.begins_with("ct") else "T")
	state.start_match()
	return state


func _events(state: RefCounted, type: String) -> Array:
	return state.trace.filter(func(event: Dictionary) -> bool: return event.type == type)


func _plant(state: RefCounted) -> void:
	state.advance_tick()
	var owner: String = state.bomb_owner
	for tick in 3:
		state.advance_tick({"plant": {"player_id": owner, "attack": true,
			"equipped_c4": true, "grounded": true, "in_bomb_site": true,
			"site_id": "A", "position": Vector3(1, 0, 2)}})
	_check(state.bomb_state == "planted", "fixture plants through the real round command")


func _run() -> void:
	# TeamExterminationCheck requires populated, spawnable sides. An empty team
	# is not a team of dead players, and must not give the remaining side a win.
	for scenario: String in [ScenarioScript.SCENARIO_BOMB, ScenarioScript.SCENARIO_HOSTAGE]:
		var empty := _fixture(scenario)
		empty.players.erase("t1")
		empty.players.erase("t2")
		empty.advance_tick()
		empty._check_elimination()
		_check(empty.phase == "live" and empty.ct_score == 0,
			"empty team does not synthesize an elimination win: " + scenario)
		var choosing := _fixture(scenario)
		for id: String in ["t1", "t2"]:
			choosing.players[id].alive = false
			choosing.players[id].choosing_appearance = true
		choosing.advance_tick()
		choosing._check_elimination()
		_check(choosing.phase == "live" and choosing.ct_score == 0,
			"only appearance-pending opponents cannot award an elimination: " + scenario)
	var probe := _fixture()
	if not probe.has_method("disconnect_player"):
		_check(false, "round state must provide explicit player disconnection")
	else:
		_assert_disconnects()
		_assert_elimination_matrix()
	for failure in failures:
		push_error(failure)
	print("GAME_ROUND_DISCONNECT_PASS" if failures.is_empty() else "GAME_ROUND_DISCONNECT_FAIL")
	quit(0 if failures.is_empty() else 1)


func _assert_disconnects() -> void:
	for planting in [false, true]:
		var state := _fixture()
		state.advance_tick()
		var owner: String = state.bomb_owner
		if planting:
			state.advance_tick({"plant": {"player_id": owner, "attack": true,
				"equipped_c4": true, "grounded": true, "in_bomb_site": true}})
			_check(state.plant_actor == owner, "disconnect fixture starts plant")
		state.plant_retry_deadline_by_actor[owner] = state.tick + 75
		var before: Dictionary = state.players.ct1.duplicate(true)
		_check(state.disconnect_player(owner, Vector3.ONE), "known player disconnects")
		_check(not state.players.has(owner) and not state.plant_retry_deadline_by_actor.has(owner),
			"departure removes roster state and retry history")
		_check(state.bomb_owner.is_empty() and state.plant_actor.is_empty()
			and state.bomb_state == "dropped" and state.bomb_position == Vector3.ONE,
			"departure releases carried/planting C4 at authoritative actor position")
		_check(_events(state, "bomb_dropped").size() == 1 and _events(state, "player_death").is_empty(),
			"departure drops C4 once without pretending it was a kill")
		_check(_events(state, "plant_abort").size() == int(planting), "only an active plant aborts")
		_check(state.players.ct1 == before, "departure gives no opponent frag or kill money")
		var trace_size: int = state.trace.size()
		_check(not state.disconnect_player(owner) and state.trace.size() == trace_size,
			"duplicate and stale departures are inert")
		state.register_player("replacement", "UNASSIGNED")
		_check(state.players.replacement.money == 0 and not state.players.replacement.has_c4,
			"new identity cannot inherit departed account or C4")
	var defusing := _fixture()
	_plant(defusing)
	defusing.set_defuser("ct1", true)
	defusing.advance_tick({"defuse": {"player_id": "ct1", "use": true,
		"grounded": true, "in_range": true, "facing": true}})
	_check(defusing.defuse_actor == "ct1", "fixture starts defuse")
	var bomb_deadline: int = defusing.bomb_deadline_tick
	defusing.disconnect_player("ct1", Vector3.ONE)
	_check(defusing.defuse_actor.is_empty() and defusing.defuse_started_tick == -1
		and defusing.defuse_refresh_deadline_tick == -1 and defusing.defuse_duration_ticks == 0,
		"defuser departure cancels the full action state")
	_check(defusing.bomb_state == "planted" and defusing.bomb_deadline_tick == bomb_deadline,
		"defuser departure neither removes the bomb nor changes its fuse")
	_check(_events(defusing, "defuse_abort").size() == 1, "defuse abort is emitted exactly once")
	defusing.advance_tick({"defuse": {"player_id": "ct1", "use": true,
		"grounded": true, "in_range": true, "facing": true}})
	_check(defusing.defuse_actor.is_empty(), "departed defuser cannot restart via stale input")
	var planted := _fixture()
	_plant(planted)
	var planter: String = planted.bomb_planter_id
	planted.disconnect_player(planter)
	_check(planted.bomb_state == "planted" and planted.bomb_planter_id == planter
		and planted.bomb_owner.is_empty(), "planted C4 survives with historical planter identity but no live owner")
	while planted.phase == "bomb":
		planted.advance_tick()
	_check(planted.bomb_state == "exploded" and not planted.players.has(planter),
		"planted C4 resolves after planter departure without recreating an account")
	for scenario: String in [ScenarioScript.SCENARIO_BOMB, ScenarioScript.SCENARIO_HOSTAGE]:
		var last_alive := _fixture(scenario)
		last_alive.advance_tick()
		last_alive.set_player_alive("t2", false)
		last_alive.disconnect_player("t1")
		_check(last_alive.phase == "post" and last_alive.round_winner == "CT",
			"last survivor leaving checks elimination when dead teammates still populate side")
		_check(_events(last_alive, "player_death").size() == 1 and last_alive.players.ct1.kills == 0,
			"disconnect does not add a second death or kill")
	var frozen := _fixture()
	frozen.disconnect_player("ct1")
	_check(frozen.phase == "freeze" and frozen.rounds_played == 0, "freeze departure does not end a round")
	var invalid := _fixture()
	var invalid_trace: int = invalid.trace.size()
	_check(not invalid.disconnect_player("unknown") and not invalid.disconnect_player("t1", Vector3(NAN, 0, 0))
		and invalid.players.has("t1") and invalid.trace.size() == invalid_trace, "invalid departure is atomic and inert")


func _assert_elimination_matrix() -> void:
	var cases := [[], ["alive"], ["dead"], ["choosing"], ["alive", "choosing"], ["dead", "choosing"]]
	var checked := 0
	for planted in [false, true]:
		for terrorists: Array in cases:
			for cts: Array in cases:
				var state: RefCounted = RoundScript.new()
				for team: String in ["T", "CT"]:
					var rows: Array = terrorists if team == "T" else cts
					for index in rows.size():
						var id := "%s%d" % [team, index]
						state.register_player(id, team)
						state.players[id].alive = rows[index] == "alive"
						state.players[id].choosing_appearance = rows[index] == "choosing"
				state.phase = "bomb" if planted else "live"
				state.bomb_state = "planted" if planted else "none"
				var expected := "ongoing"
				var t_spawnable: bool = terrorists.has("alive") or terrorists.has("dead")
				var ct_spawnable: bool = cts.has("alive") or cts.has("dead")
				if t_spawnable and ct_spawnable:
					if not terrorists.has("alive") and cts.has("alive") and not planted:
						expected = "CT"
					elif not cts.has("alive"):
						expected = "T"
				elif not terrorists.has("alive") and not cts.has("alive"):
					expected = ""
				state._check_elimination()
				var actual: String = state.round_winner if state.phase == "post" else "ongoing"
				_check(actual == expected, "elimination matrix T=%s CT=%s planted=%s expected=%s actual=%s"
					% [terrorists, cts, planted, expected, actual])
				checked += 1
	print("ROUND_DISCONNECT_ELIMINATION_MATRIX cases=", checked)
