extends SceneTree

## Locomotion coverage for the benchmark's human-intent driver. Production
## player physics, bot navigation, door contacts and map spawns stay intact.
## Blind bot perception and disabled driver attacks isolate traversal; this is
## not a combat/GPU result. A normal round reset is not driver locomotion.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _blind(_actor: Combatant, _tick: int) -> bool:
	return true


func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
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
		failures.append("driver navigation could not be prepared")
	game.start_match()
	# Let the normal freeze separate team selection from movement, just as
	# the UI does. Bypassing it in the same frame can query the old bot-slot
	# collision transforms before the physics server has synchronized them.
	while game.phase != "live":
		await physics_frame
	var previous: Vector3 = game.player.global_position
	var max_displacement := 0.0
	var entered := false
	var jumps := 0
	var large_moves: Array[Dictionary] = []
	var ticks := 0
	var link: NavigationLink3D = game.imported_map.navigation_links[0]
	var link_center := (link.get_global_start_position() + link.get_global_end_position()) * 0.5
	for tick in 7000:
		await physics_frame
		ticks = tick + 1
		if game.phase == "post":
			break
		var displacement: float = game.player.global_position.distance_to(previous)
		max_displacement = maxf(max_displacement, displacement)
		if displacement >= 0.20 and large_moves.size() < 12:
			large_moves.append({"tick": ticks, "from": str(previous), "to": str(game.player.global_position),
				"velocity": str(game.player.velocity), "grounded": game.player._movement_grounded,
				"jump": bool(game.player.last_command.get("jump", false)), "distance": displacement})
		previous = game.player.global_position
		if game.player.velocity.y > 1.5 and previous.distance_to(link_center) < 1.5:
			jumps += 1
		if previous.z < link_center.z - 1.0 and previous.y > 0.15:
			entered = true
			break
		if ticks % 2000 == 0:
			print("MATCH_DRIVER_TRAVERSAL_PROGRESS tick=", ticks, " player=", previous)
	if not entered:
		failures.append("automated local CT never enters the warehouse from its real spawn")
	if jumps == 0:
		failures.append("local CT never uses the normal jump impulse at the entrance")
	if max_displacement >= 0.25:
		failures.append("driver must not teleport or bypass player movement")
	print("MATCH_DRIVER_TRAVERSAL ", JSON.stringify({"failures": failures, "ticks": ticks,
		"position": str(previous), "entered": entered, "jump_frames": jumps,
		"max_tick_displacement_m": max_displacement, "audio_muted": true,
		"large_moves": large_moves,
		"combat_test": false, "gpu_measured": false}))
	game.queue_free()
	await process_frame
	MdlCharacterModel.release_cached_resources()
	MdlViewModel.release_cached_resources()
	CS16CombatEffects.release_cached_resources()
	await create_timer(0.2).timeout
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_MATCH_DRIVER_TRAVERSAL_PASS")
	quit(0 if failures.is_empty() else 1)
