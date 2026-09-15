extends SceneTree

## Diagnostic only: normal combat, economy, spawns and freeze; no GPU claim.
## Snapshots are taken during play, not after intermission disables actors.
const MatchDriver = preload("res://tests/live_match_driver.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var target_ticks := 12000
	var team := "T"
	var report_path := "/tmp/protocol47-hostage-combat-probe.json"
	var require_door_progress := OS.get_cmdline_user_args().has("--require-door-progress")
	var require_driver_progress := OS.get_cmdline_user_args().has("--require-driver-progress")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--ticks="):
			target_ticks = clampi(int(argument.trim_prefix("--ticks=")), 1000, 140000)
		elif argument.begins_with("--team="):
			team = argument.trim_prefix("--team=")
		elif argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	if DisplayServer.get_name() != "headless" or team not in ["T", "CT"] or (require_door_progress and team != "T") or (require_driver_progress and (team != "CT" or target_ticks < 24000)):
		push_error("Hostage combat probe requires headless mode and team T or CT")
		quit(1)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	game.map_name = "cs_assault"
	root.add_child(game)
	current_scene = game
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	if game.player.team != team:
		game._on_team_selected(2 if team == "CT" else 1)
		game._on_class_selected(1)
		await process_frame
		await physics_frame
	var driver := MatchDriver.new()
	driver.game = game
	game.player.add_child(driver)
	game.player.combat_controller.queue_free()
	driver.possess(game.player)
	game.player.combat_controller = driver
	if not driver.prepare_navigation():
		push_error("Hostage combat probe cannot prepare local navigation")
		quit(1)
		return
	game.start_match()
	var initial := {"phase": game.phase, "weapon": game.player.active_weapon,
		"inventory": game.player.owned_weapons.duplicate(true), "team": game.player.team}
	var snapshots: Array[Dictionary] = []
	var door_bot: TargetActor
	for bot: TargetActor in game._all_bots():
		if bot.name == "CT_Bot_05":
			door_bot = bot
	var entered_tick := -1
	var wait_ticks := 0
	var wait_ticks_by_actor := {}
	var wait_streaks := {}
	var max_wait_streak := 0
	var all_bots: Array = game._all_bots()
	var previous_position := door_bot.global_position
	var max_round_one_displacement := 0.0
	var previous_local: Vector3 = game.player.global_position
	var previous_local_alive: bool = game.player.alive
	var previous_round: int = game.round_number
	var max_local_displacement := 0.0
	var idle_route_ticks := 0
	var max_idle_route_ticks := 0
	for tick in target_ticks:
		await physics_frame
		# Round-start spawns are not locomotion. Every live intra-round move is.
		if previous_round == game.round_number and previous_local_alive and game.player.alive:
			max_local_displacement = maxf(max_local_displacement, previous_local.distance_to(game.player.global_position))
		previous_local = game.player.global_position
		previous_local_alive = game.player.alive
		previous_round = game.round_number
		var local_command: Dictionary = game.player.last_command
		if (game.player.alive and game.player.controls_enabled and driver._route_target.is_finite()
			and game.player.global_position.distance_to(driver._route_target) > 0.5
			and (local_command.get("movement", Vector2.ZERO) as Vector2).is_zero_approx()
			and not bool(local_command.get("fire", false)) and not bool(local_command.get("reload", false))
			and not bool(local_command.get("use", false))):
			idle_route_ticks += 1
			max_idle_route_ticks = maxi(max_idle_route_ticks, idle_route_ticks)
		else:
			idle_route_ticks = 0
		for bot: TargetActor in all_bots:
			if bool(bot.last_command.get("waiting_for_door", false)):
				wait_ticks_by_actor[bot.name] = int(wait_ticks_by_actor.get(bot.name, 0)) + 1
				wait_streaks[bot.name] = int(wait_streaks.get(bot.name, 0)) + 1
				max_wait_streak = maxi(max_wait_streak, int(wait_streaks[bot.name]))
			else:
				wait_streaks[bot.name] = 0
		if game.round_number == 1:
			max_round_one_displacement = maxf(max_round_one_displacement, previous_position.distance_to(door_bot.global_position))
			if bool(door_bot.last_command.get("waiting_for_door", false)):
				wait_ticks += 1
			if entered_tick < 0 and door_bot.alive and door_bot.global_position.x < 6.8 and door_bot.global_position.z < -22.5 and door_bot.global_position.y > 0.2:
				entered_tick = game.round_state.tick
		previous_position = door_bot.global_position
		if tick % 1000 == 999:
			snapshots.append(_snapshot(game))
			print("HOSTAGE_COMBAT_PROGRESS tick=", game.round_state.tick, " round=", game.round_number,
				" phase=", game.phase, " effects=", game.combat_effects.total_effect_events)
		if game._match_concluded:
			break
	var passed := not require_door_progress or (entered_tick >= 0 and max_round_one_displacement < 0.25
		and not wait_ticks_by_actor.is_empty() and max_wait_streak <= BotCombatController.DOOR_WAIT_MAX_TICKS)
	if require_driver_progress:
		passed = passed and driver.max_blocked_ticks <= 1000 and max_idle_route_ticks <= 1000 and driver.recovery_commands > 0 and game.player._shot_sequence > 0 and max_local_displacement < 0.25
	var report := {"diagnostic_only": not (require_door_progress or require_driver_progress), "gameplay_assertions": require_door_progress or require_driver_progress,
		"driver_progress_required": require_driver_progress, "max_local_displacement": max_local_displacement,
		"door_progress_required": require_door_progress, "door_entered_tick": entered_tick,
		"door_wait_ticks": wait_ticks, "max_round_one_displacement": max_round_one_displacement,
		"door_wait_ticks_by_actor": wait_ticks_by_actor, "max_door_wait_streak": max_wait_streak,
		"gpu_measured": false, "audio_muted": true, "initial": initial,
		"driver_max_blocked_ticks": driver.max_blocked_ticks,
		"driver_max_idle_route_ticks": max_idle_route_ticks,
		"driver_jump_commands": driver.jump_commands,
		"driver_recovery_commands": driver.recovery_commands,
		"driver_solo_objective_commands": driver.solo_objective_commands, "driver_use_commands": driver.use_commands,
		"snapshots": snapshots, "round_trace": game.round_state.trace,
		"final_hostage_trace": game.hostage_state.trace}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write hostage combat diagnostic report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	game.queue_free()
	await process_frame
	MdlCharacterModel.release_cached_resources()
	MdlViewModel.release_cached_resources()
	CS16CombatEffects.release_cached_resources()
	await create_timer(0.2).timeout
	if not passed:
		push_error("Assault progress, bounded wait/recovery, local combat, or displacement check failed")
	print("GAME_HOSTAGE_COMBAT_PROBE_PASS" if passed else "GAME_HOSTAGE_COMBAT_PROBE_FAIL", " report=", report_path)
	quit(0 if passed else 1)


func _snapshot(game: Node) -> Dictionary:
	var bots: Array[Dictionary] = []
	for bot: TargetActor in game._all_bots():
		var controller := bot.combat_controller as BotCombatController
		var desired: Vector3 = bot.last_command.get("world_velocity", Vector3.ZERO)
		var blocker := ""
		var blocker_details := {}
		var motion := PhysicsTestMotionParameters3D.new()
		motion.from = bot.global_transform
		motion.motion = desired.normalized() * 0.12
		var collision := PhysicsTestMotionResult3D.new()
		if bot.alive and not desired.is_zero_approx() and PhysicsServer3D.body_test_motion(bot.get_rid(), motion, collision):
			var collider := collision.get_collider()
			blocker = str(collider.name) if collider is Node else str(collider)
			if collider is Node:
				blocker_details = {"path": str(collider.get_path()),
					"model": collider.get_meta("model_index", -1),
					"entity": collider.get_meta("entity_index", -1),
					"classname": collider.get_meta("classname", ""),
					"normal": _vec(collision.get_collision_normal())}
		var next_points: Array = []
		for index in range(maxi(0, controller._objective_route_index), mini(controller._objective_route.size(), controller._objective_route_index + 5)):
			next_points.append(_vec(controller._objective_route[index]))
		bots.append({"name": str(bot.name), "team": bot.team, "alive": bot.alive, "active": bot.active,
			"position": _vec(bot.global_position), "velocity": _vec(bot.velocity),
			"state": bot.combat_state, "weapon": bot.active_weapon_name, "clip": bot.weapon_clip,
			"reserve": bot.weapon_reserve, "reloading": bot.weapon_reloading,
			"desired": _vec(desired), "blocker": blocker, "blocker_details": blocker_details,
			"command": bot.last_command.duplicate(),
			"enemy": controller.perception.current_target_id, "enemy_visible": controller.perception.visible,
			"last_seen": _vec(controller.perception.last_seen_position),
			"assigned_hostage": game._hostage_bot_assignments.get(bot.name, ""),
			"route_target": _vec(controller._objective_route_target), "route_index": controller._objective_route_index,
			"route_size": controller._objective_route.size(), "next_route_points": next_points,
			"obstructed_ticks": bot._obstructed_ticks, "unwedge_ticks": controller._unwedge_blocked_ticks})
	var brushes := {}
	for entity: int in game.brush_runtime._brushes:
		var brush: Dictionary = game.brush_runtime.get_brush(entity)
		brushes[entity] = {"state": brush.get("state"), "progress": brush.get("motion_progress"),
			"total": brush.get("motion_total"), "classname": brush.get("classname")}
	var local_driver = game.player.combat_controller
	var local_planner: BotCombatController = local_driver.planner
	var local_route := []
	for index in range(maxi(0, local_planner._objective_route_index), mini(local_planner._objective_route.size(), local_planner._objective_route_index + 5)):
		local_route.append(_vec(local_planner._objective_route[index]))
	return {"tick": game.round_state.tick, "round": game.round_number, "phase": game.phase, "brushes": brushes,
		"player": {"position": _vec(game.player.global_position), "velocity": _vec(game.player.velocity),
			"alive": game.player.alive, "command": game.player.last_command.duplicate(),
			"blocked_ticks": local_driver._blocked_ticks, "next_route_points": local_route,
			"shot_sequence": game.player._shot_sequence},
		"bots": bots, "hostages": game.hostage_state.snapshot(), "hostage_trace": game.hostage_state.trace.duplicate(true)}


func _vec(value: Vector3) -> Variant:
	return [value.x, value.y, value.z] if value.is_finite() else null
