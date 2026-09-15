extends SceneTree

const GameScript := preload("res://scripts/game.gd")
const ScenarioRules := preload("res://scripts/cs16_scenario_rules.gd")
const TICK_COUNT := 300
const TELEPORT_TO_RESCUE_TICK := 150

var failures: Array[String] = []
var canonical_chain := "protocol47-hostage-bot-v1"
var canonical_checkpoints: Array[Dictionary] = []
var logical_trace: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("HOSTAGE BOT DETERMINISM TEST: " + message)


func _always_blind(_actor: Combatant, _tick: int) -> bool:
	return true


func _run() -> void:
	_check(
		_sorted_text_keys({&"CT_Bot_04": true, &"CT_Bot_02": true, &"CT_Bot_01": true, &"CT_Bot_03": true})
		== ["CT_Bot_01", "CT_Bot_02", "CT_Bot_03", "CT_Bot_04"],
		"canonical actor order sorts name text rather than interned StringName identities",
	)
	var game := GameScript.new()
	game.map_name = "cs_assault"
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	_check(
		game.using_imported_map
		and game.scenario == ScenarioRules.SCENARIO_HOSTAGE,
		"production cs_assault hostage scenario loads",
	)
	if game.hostage_state == null:
		await _finish(game)
		return

	game.start_match()
	game._begin_live()
	# Drive the exact production objective methods at their authored 100 Hz
	# quantum. Rendering schedules still advance around this loop, but neither
	# Game nor the pawns get a second, host-FPS-dependent physics callback.
	game.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.health = 1000000
		bot.set_physics_process(false)
		bot.active = true
		(bot.combat_controller as BotCombatController).set_perception_predicates(
			Callable(self, "_always_blind")
		)

	game._refresh_hostage_bot_assignments()
	var initial_assignments: Dictionary = game._hostage_bot_assignments.duplicate()
	_check(
		initial_assignments.size() == 4,
		"four CT bots claim the four living hostages",
	)
	var claimed_ids: Array = initial_assignments.values()
	var unique_claims := {}
	for hostage_id: String in claimed_ids:
		unique_claims[hostage_id] = true
	_check(unique_claims.size() == 4, "CT hostage claims are one-to-one")

	var guard_ids := {}
	for bot: TargetActor in game._all_bots():
		if bot.team != Combatant.TEAM_TERRORIST:
			continue
		var guard_context: Dictionary = game.bot_objective_context(bot)
		_check(
			str(guard_context.get("action", "")) == "guard_hostage",
			"%s guards a hostage before an escape begins" % bot.name,
		)
		guard_ids[str(guard_context.get("objective_id", ""))] = true
	_check(guard_ids.size() == 4, "the four T bots distribute across all hostages")

	# Put each selected CT inside the exact 64 HU Source use sphere and orient
	# its view cone toward the hostage. The production bot command must carry
	# the use request; the test never calls the hostage use handler directly.
	var sorted_ct_names := _sorted_text_keys(initial_assignments)
	for assignment_index in sorted_ct_names.size():
		var bot_name := str(sorted_ct_names[assignment_index])
		var bot := game._actor_for_round_id(bot_name) as TargetActor
		var hostage_id := str(initial_assignments[bot_name])
		var hostage: CS16Hostage = game.hostage_actors[hostage_id]
		var angle := float(assignment_index) * TAU / 4.0
		bot.global_position = hostage.global_position + Vector3(
			cos(angle),
			0.0,
			sin(angle),
		) * 0.45
		bot.velocity = Vector3.ZERO
		bot.face_aim_target(hostage.source_use_origin())

	var following_checked := false
	var intercept_checked := false
	var rescue_checked := false
	for tick_index in TICK_COUNT:
		if tick_index == TELEPORT_TO_RESCUE_TICK:
			_stage_followers_inside_rescue_zones(game)
		await physics_frame
		_advance_canonical_hostage_tick(game)
		var tick_number := tick_index + 1

		if not following_checked and tick_number >= 20:
			following_checked = true
			var follower_count := 0
			for hostage_id: String in game.hostage_state.hostages:
				var contract: Dictionary = game.hostage_state.hostages[hostage_id]
				if bool(contract.following):
					follower_count += 1
					var leader := game._actor_for_round_id(
						str(contract.leader_id)
					) as TargetActor
					_check(
						is_instance_valid(leader)
						and str(
							leader.last_command.get(
								"objective_action",
								"",
							)
						) == "escort_hostage",
						"%s transitions from use to escort" % contract.leader_id,
					)
					var escort_context: Dictionary = game.bot_objective_context(
						leader
					)
					_check(
						_is_ct_rescue_spawn(
							game,
							escort_context.get("target", Vector3.INF),
						),
						"%s escorts toward a legacy CT-spawn rescue zone"
						% contract.leader_id,
					)
			_check(follower_count == 4, "all four CT use commands start following")

		if not intercept_checked and tick_number >= 30:
			intercept_checked = true
			for bot: TargetActor in game._all_bots():
				if bot.team != Combatant.TEAM_TERRORIST:
					continue
				_check(
					str(
						bot.last_command.get("objective_action", "")
					) == "intercept_hostage",
					"%s switches from guard to rescue-route interception"
					% bot.name,
				)

		if not rescue_checked and tick_number >= TELEPORT_TO_RESCUE_TICK + 20:
			rescue_checked = true
			_check(
				game.hostage_state.rescued_count == 4,
				"production escort flow rescues all four hostages",
			)
			_check(
				game.round_state.round_winner == "CT"
				and game.round_state.round_reason == "all_hostages_rescued",
				"all rescued hostages resolve the authoritative CT objective",
			)

		var logical := _logical_snapshot(game, tick_number)
		if OS.get_cmdline_user_args().has("--logical-trace"):
			logical_trace.append(logical)
		canonical_chain = (
			canonical_chain
			+ "|"
			+ JSON.stringify(logical)
		).sha256_text()
		if tick_number % 100 == 0:
			var physical := _physical_snapshot(game)
			canonical_checkpoints.append({
				"tick": tick_number,
				"logical_sha256": canonical_chain,
				"physical_sha256": JSON.stringify(physical).sha256_text(),
				"physical": physical,
			})

	_check(following_checked, "following transition checkpoint executes")
	_check(intercept_checked, "terrorist intercept checkpoint executes")
	_check(rescue_checked, "rescue completion checkpoint executes")
	_write_signature()
	await _finish(game)


func _advance_canonical_hostage_tick(game: Node) -> void:
	game.hostage_state.advance_tick()
	var bots: Array[TargetActor] = game._all_bots()
	bots.sort_custom(
		func(first: TargetActor, second: TargetActor) -> bool:
			return str(first.name) < str(second.name)
	)
	for bot in bots:
		var command: Dictionary = (
			bot.combat_controller as BotCombatController
		).gather_command(0.01)
		bot.last_command = command
		bot.combat_state = str(command.get("state", "idle"))
		var look_target: Vector3 = command.get("look_target", Vector3.INF)
		if look_target != Vector3.INF:
			bot.face_aim_target(look_target)
	game._process_hostage_bot_use_commands()
	if game.hostage_state.tick % 10 == 0:
		var hostage_ids := _sorted_text_keys(game.hostage_state.hostages)
		for hostage_id: String in hostage_ids:
			game._check_hostage_rescue(hostage_id)
	game._sync_hostage_actors()


func _stage_followers_inside_rescue_zones(game: Node) -> void:
	var follower_index := 0
	var hostage_ids := _sorted_text_keys(game.hostage_state.hostages)
	for hostage_id: String in hostage_ids:
		var contract: Dictionary = game.hostage_state.hostages[hostage_id]
		if not bool(contract.following):
			continue
		var leader := game._actor_for_round_id(str(contract.leader_id)) as TargetActor
		if not is_instance_valid(leader):
			continue
		var rescue_position: Vector3 = game.counter_terrorist_team_spawns[
			follower_index % game.counter_terrorist_team_spawns.size()
		]
		var hostage_position := rescue_position + Vector3(0.20, 0.0, 0.0)
		leader.global_position = rescue_position
		leader.velocity = Vector3.ZERO
		var hostage: CS16Hostage = game.hostage_actors[hostage_id]
		hostage.global_position = hostage_position
		hostage.velocity = Vector3.ZERO
		game.hostage_state.set_position(
			hostage_id,
			hostage_position / CS16Hostage.GOLDSRC_UNIT,
		)
		follower_index += 1


func _is_ct_rescue_spawn(game: Node, candidate: Vector3) -> bool:
	for spawn: Vector3 in game.counter_terrorist_team_spawns:
		if candidate.distance_to(spawn) <= 0.0001:
			return true
	return false


func _logical_snapshot(game: Node, tick_number: int) -> Dictionary:
	var assignments: Array[Dictionary] = []
	var bot_names := _sorted_text_keys(game._hostage_bot_assignments)
	for bot_name: String in bot_names:
		assignments.append({
			"bot": bot_name,
			"hostage": str(game._hostage_bot_assignments[bot_name]),
		})
	var hostages: Array[Dictionary] = []
	var hostage_ids := _sorted_text_keys(game.hostage_state.hostages)
	for hostage_id: String in hostage_ids:
		var contract: Dictionary = game.hostage_state.hostages[hostage_id]
		hostages.append({
			"id": hostage_id,
			"alive": bool(contract.alive),
			"following": bool(contract.following),
			"rescued": bool(contract.rescued),
			"leader": str(contract.leader_id),
		})
	var bots: Array[Dictionary] = []
	for bot: TargetActor in game._all_bots():
		var context: Dictionary = game.bot_objective_context(bot)
		bots.append({
			"id": str(bot.name),
			"team": str(bot.team),
			"state": str(context.get("state", "")),
			"action": str(context.get("action", "")),
			"objective_id": str(context.get("objective_id", "")),
		})
	bots.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return str(first.id) < str(second.id)
	)
	return {
		"tick": tick_number,
		"round_tick": int(game.round_state.tick),
		"phase": str(game.round_state.phase),
		"winner": str(game.round_state.round_winner),
		"assignments": assignments,
		"hostages": hostages,
		"bots": bots,
	}


func _sorted_text_keys(source: Dictionary) -> Array[String]:
	# Node.name keys may be StringName rather than String. Sorting the untyped
	# keys allowed script-load-dependent intern order to change fixture staging
	# angles and the first logical checkpoint despite identical assignments.
	var keys: Array[String] = []
	for key: Variant in source:
		keys.append(str(key))
	keys.sort()
	return keys


func _physical_snapshot(game: Node) -> Array[Dictionary]:
	var actors: Array[Dictionary] = []
	for bot: TargetActor in game._all_bots():
		actors.append({
			"id": str(bot.name),
			"position_q64_hu": _quantized_vector(bot.global_position),
		})
	for hostage_id: String in game.hostage_actors:
		var hostage: CS16Hostage = game.hostage_actors[hostage_id]
		actors.append({
			"id": hostage_id,
			"position_q64_hu": _quantized_vector(hostage.global_position),
		})
	actors.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return str(first.id) < str(second.id)
	)
	return actors


func _quantized_vector(value: Vector3) -> Array[int]:
	return [
		int(round(value.x / CS16Hostage.GOLDSRC_UNIT * 64.0)),
		int(round(value.y / CS16Hostage.GOLDSRC_UNIT * 64.0)),
		int(round(value.z / CS16Hostage.GOLDSRC_UNIT * 64.0)),
	]


func _signature_output_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--signature-output="):
			return argument.trim_prefix("--signature-output=")
	return ""


func _write_signature() -> void:
	var path := _signature_output_path()
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "signature output opens")
	if file != null:
		var report := {
			"quantum_hu": 1.0 / 64.0,
			"ticks": TICK_COUNT,
			"sha256": canonical_chain,
			"checkpoints": canonical_checkpoints,
		}
		if not logical_trace.is_empty():
			report.logical_trace = logical_trace
		file.store_string(JSON.stringify(report, "\t"))


func _finish(game: Node) -> void:
	if failures.is_empty():
		print(
			"GAME_HOSTAGE_BOT_DETERMINISM_TEST_PASS logical=%s checkpoints=%d"
			% [canonical_chain, canonical_checkpoints.size()]
		)
		current_scene = null
		game.queue_free()
		await process_frame
		quit(0)
	else:
		print(
			"GAME_HOSTAGE_BOT_DETERMINISM_TEST_FAIL (%d): %s"
			% [failures.size(), ", ".join(failures)]
		)
		current_scene = null
		game.queue_free()
		await process_frame
		quit(1)
