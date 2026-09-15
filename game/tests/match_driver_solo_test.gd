extends SceneTree

## Last-human objective coverage from the normal Assault CT spawn. Perception
## is blinded and driver attacks disabled to isolate navigation/use/rescue.
## Teammates die through the ordinary damage path; no pawn is repositioned.
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _blind(_actor: Combatant, _tick: int) -> bool:
	return true


func _run() -> void:
	var game := preload("res://scripts/game.gd").new()
	game.map_name = "cs_assault"
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	game._on_team_selected(2)
	game._on_class_selected(1)
	for bot in game._all_bots():
		bot.combat_controller.set_perception_predicates(Callable(self, "_blind"))
	var driver := preload("res://tests/live_match_driver.gd").new()
	driver.game = game
	driver.combat_enabled = false
	game.player.add_child(driver)
	game.player.combat_controller.queue_free()
	driver.possess(game.player)
	game.player.combat_controller = driver
	if not driver.prepare_navigation():
		failures.append("driver navigation must be available")
	# Test the narrow-link steering contract without relocating the pawn.
	driver.planner._objective_route = PackedVector3Array([game.player.global_position + Vector3(0.08, 0.04, 0.0)])
	driver.planner._objective_required_waypoints = {0: true}
	if driver.planner._objective_waypoint_reached(0):
		failures.append("eight-centimeter lateral error must not consume a narrow traversal endpoint")
	driver.planner._objective_route[0] = game.player.global_position + Vector3(0.01, 0.04, 0.0)
	if not driver.planner._objective_waypoint_reached(0):
		failures.append("aligned grounded traversal endpoint must be reachable")
	driver.planner._objective_route[0] = game.player.global_position + Vector3(0.0, 0.36, 0.0)
	if driver.planner._objective_waypoint_reached(0):
		failures.append("traversal exit cannot be consumed from the floor below")
	var test_target: Vector3 = game.player.global_position + Vector3(1.0, 0.04, 0.0)
	driver.planner._objective_route = PackedVector3Array([game.player.global_position + Vector3(0.03, 0.04, 0.0), test_target])
	driver.planner._objective_route_index = 0
	driver.planner._objective_route_target = test_target
	driver.planner._objective_visibility_next_tick = 1000
	if driver.planner._objective_navigation_velocity_to(test_target, 0.01).is_zero_approx():
		failures.append("three-centimeter endpoint error must still produce steering, not fall into the bot's five-centimeter stop radius")
	driver.planner.reset_tactics()
	game.start_match()
	var frozen_command := driver.gather_command(0.01)
	if not (frozen_command.movement as Vector2).is_zero_approx() or bool(frozen_command.use):
		failures.append("freeze must suppress objective movement and use")
	while game.phase != "live":
		await physics_frame
	for bot in game._all_bots():
		if bot.team == game.player.team:
			bot.receive_damage(10000.0)
	await physics_frame
	var first_command := driver.gather_command(0.01)
	if (first_command.movement as Vector2).is_zero_approx():
		failures.append("last CT must navigate toward an objective without an alive ally or visible enemy")
	if bool(first_command.fire):
		failures.append("objective fallback must not invent a visible enemy")
	var previous: Vector3 = game.player.global_position
	var max_displacement := 0.0
	var use_commands := 0
	var ticks := 0
	if failures.is_empty():
		for index in 29000:
			await physics_frame
			ticks = index + 1
			max_displacement = maxf(max_displacement, previous.distance_to(game.player.global_position))
			previous = game.player.global_position
			if bool(game.player.last_command.get("use", false)):
				use_commands += 1
			if game.hostage_state.rescued_count == 4 or game.phase == "post":
				break
			if ticks % 2000 == 0:
				print("MATCH_DRIVER_SOLO_PROGRESS tick=", ticks, " player=", previous,
					" rescued=", game.hostage_state.rescued_count, " use_commands=", use_commands,
					" jumps=", driver.jump_commands, " blocked=", driver._blocked_ticks,
					" wish=", driver._previous_wish)
		if game.hostage_state.rescued_count != 4:
			failures.append("last CT must use and rescue all four hostages through normal input")
		if use_commands == 0:
			failures.append("rescue must exercise the real world-use input path")
		if max_displacement >= 0.25:
			failures.append("driver cannot teleport or bypass player locomotion")
		var follows: Array = game.hostage_state.trace.filter(func(event: Dictionary) -> bool: return event.type == "hostage_follow")
		var rescues: Array = game.hostage_state.trace.filter(func(event: Dictionary) -> bool: return event.type == "hostage_rescued")
		if follows.size() != 4 or not follows.all(func(event: Dictionary) -> bool: return event.actor_id == "player"):
			failures.append("all four hostages must be acquired by the human's use input without repeated toggling")
		if rescues.size() != 4 or not rescues.all(func(event: Dictionary) -> bool: return event.rescuer_id == "player"):
			failures.append("all four rescues must credit the human escort")
		if game.player._shot_sequence != 0:
			failures.append("blinded objective traversal must not fire at hidden enemies")
		game.player.receive_damage(10000.0)
		var dead_command := driver.gather_command(0.01)
		if not (dead_command.movement as Vector2).is_zero_approx() or bool(dead_command.use):
			failures.append("death must suppress objective movement and use")
	print("MATCH_DRIVER_SOLO ", JSON.stringify({"ticks": ticks, "failures": failures,
		"rescued": game.hostage_state.rescued_count, "use_commands": use_commands,
		"max_displacement": max_displacement, "position": str(previous),
		"hostage_trace": game.hostage_state.trace, "audio_driver": AudioServer.get_driver_name(),
		"combat_blinded": true, "gpu_measured": false}))
	game.queue_free()
	await process_frame
	MdlCharacterModel.release_cached_resources()
	MdlViewModel.release_cached_resources()
	CS16CombatEffects.release_cached_resources()
	await create_timer(0.2).timeout
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_MATCH_DRIVER_SOLO_PASS")
	quit(0 if failures.is_empty() else 1)
