extends SceneTree

const GameScript := preload("res://scripts/game.gd")
const ScenarioRules := preload("res://scripts/cs16_scenario_rules.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("HOSTAGE GAME INTEGRATION TEST: " + message)


func _run() -> void:
	var game := GameScript.new()
	game.map_name = "cs_assault"
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	_check(
		game.using_imported_map
		and game.map_name == "cs_assault"
		and game.scenario == ScenarioRules.SCENARIO_HOSTAGE,
		"production Game loads and classifies stock cs_assault",
	)
	_check(
		game.hostage_state != null
		and game.hostage_actors.size() == 4
		and game.hostage_state.original_count == 4,
		"all four authored hostage entities become runtime actors",
	)
	_check(
		game.round_state.config.scenario == ScenarioRules.SCENARIO_HOSTAGE,
		"scenario classification reaches the authoritative round kernel",
	)
	for hostage_id: String in game.hostage_actors:
		var actor: CS16Hostage = game.hostage_actors[hostage_id]
		var contract: Dictionary = game.hostage_state.hostages[hostage_id]
		_check(
			actor.global_position.distance_to(
				Vector3(contract.position_hu) * CS16Hostage.GOLDSRC_UNIT
			) <= 0.0001,
			"%s spawns at its exact BSP entity origin" % hostage_id,
		)
		_check(
			actor.skin_index == int(contract.skin),
			"%s preserves its authored skin family" % hostage_id,
		)

	game.start_match()
	_check(
		game.round_state.bomb_owner.is_empty()
		and game.round_state.bomb_state == "none",
		"hostage rounds never assign or display a C4",
	)
	var hostage_id: String = game.hostage_actors.keys()[0]
	var hostage: CS16Hostage = game.hostage_actors[hostage_id]
	var rescuer: TargetActor = game.targets[0]
	var before_money := int(game.round_state.players[rescuer.name].money)
	game._on_hostage_use_requested(hostage, rescuer)
	_check(
		bool(game.hostage_state.hostages[hostage_id].following)
		and str(game.hostage_state.hostages[hostage_id].leader_id) == rescuer.name,
		"production CT use starts authoritative hostage following",
	)
	_check(
		int(game.round_state.players[rescuer.name].money) == before_money + 150
		and int(game.round_state.pending_team_accounts.CT) == 100,
		"first production use applies exact player and CT account rewards",
	)

	var rescue_position: Vector3 = game.counter_terrorist_team_spawns[0]
	game.hostage_state.set_position(
		hostage_id,
		rescue_position / CS16Hostage.GOLDSRC_UNIT,
	)
	game._check_hostage_rescue(hostage_id)
	_check(
		bool(game.hostage_state.hostages[hostage_id].rescued)
		and not hostage.hostage_model.visible
		and hostage.collision_shape.disabled,
		"legacy CT-spawn rescue hides and desolidifies the hostage",
	)
	_check(
		int(game.round_state.players[rescuer.name].money) == before_money + 1150
		and int(game.round_state.pending_team_accounts.CT) == 850,
		"production rescue applies $1000 rescuer and pending $750 CT supplements",
	)

	game.hostage_state.start_round()
	game._sync_hostage_actors()
	_check(
		not bool(game.hostage_state.hostages[hostage_id].rescued)
		and hostage.hostage_model.visible
		and not hostage.collision_shape.disabled,
		"round reset restores rescued hostage visibility and collision",
	)
	var damage_money_before := int(game.round_state.players[rescuer.name].money)
	hostage.receive_bullet_damage(
		10,
		4,
		"ak47",
		hostage.global_position + Vector3.UP * 0.40,
		rescuer,
	)
	_check(
		is_equal_approx(float(game.hostage_state.hostages[hostage_id].health), 92.5)
		and int(game.round_state.players[rescuer.name].money)
			== maxi(0, damage_money_before - 150),
		"production bullet damage uses hostage hitgroup multiplier and cash penalty",
	)
	hostage.receive_bullet_damage(
		100,
		1,
		"ak47",
		hostage.global_position + Vector3.UP * 0.55,
		rescuer,
	)
	_check(
		not bool(game.hostage_state.hostages[hostage_id].alive)
		and hostage.collision_shape.disabled
		and hostage.hostage_model.visible
		and hostage.hostage_model.animation_state == "die",
		"lethal production damage leaves a visible nonsolid source death pose",
	)

	if failures.is_empty():
		print("GAME_HOSTAGE_GAME_INTEGRATION_TEST_PASS")
		current_scene = null
		game.queue_free()
		await process_frame
		quit(0)
	else:
		print("GAME_HOSTAGE_GAME_INTEGRATION_TEST_FAIL (%d)" % failures.size())
		current_scene = null
		game.queue_free()
		await process_frame
		quit(1)
