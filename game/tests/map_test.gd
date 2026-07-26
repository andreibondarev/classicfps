extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MAP TEST: " + message)


func _has_bot_path(targets: Array[TargetActor]) -> bool:
	for target in targets:
		if target.navigation_agent.get_current_navigation_path().size() > 1:
			return true
	return false


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return

	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame

	_check(game.using_imported_map, "converted Dust2 is the default level")
	_check(game.imported_map != null, "Dust2 map node exists")
	if game.imported_map != null:
		_check(game.imported_map.surface_count >= 70, "all Dust2 material surfaces loaded")
		_check(game.imported_map.collision_face_count >= 9500, "solid Dust2 collision mesh loaded")
		_check(game.imported_map.navigation_region != null, "Dust2 navigation region created")
		_check(
			game.imported_map.navigation_region.navigation_mesh.get_vertices().size() > 100,
			"Dust2 navigation mesh baked",
		)
		_check(
			game.imported_map.spawn_points("info_player_start").size() == 20,
			"all CT spawn entities imported",
		)
		_check(
			game.imported_map.spawn_points("info_player_deathmatch").size() == 20,
			"all terrorist spawn entities imported",
		)
	_check(game.targets.size() == 5, "combat encounter populated from map spawns")
	_check(game.allied_bots.size() == 4, "four allied bots populated from T spawns")
	_check(game.player.global_position.distance_to(game.player_spawn) < 0.1, "player uses a map spawn")
	game.start_match()
	game._begin_live()
	# The finer CS-sized navigation raster is synchronized with NavigationServer
	# on a later physics iteration than the previous oversized mesh.
	for frame in range(40):
		await physics_frame
	_check(game.targets.all(func(target: TargetActor) -> bool: return target.navigation_agent != null), "all bots have navigation agents")
	_check(
		game._all_bots().all(
			func(target: TargetActor) -> bool: return target.combat_controller is BotCombatController
		),
		"both teams use the shared bot controller",
	)
	_check(game.targets.all(func(target: TargetActor) -> bool: return target.combat_state == "hunt"), "distant bots enter hunt state")
	_check(_has_bot_path(game._all_bots()), "Dust2 produces at least one team bot path")

	if failures.is_empty():
		print("GAME_MAP_TEST_PASS")
		current_scene = null
		game.queue_free()
		await process_frame
		quit(0)
	else:
		print("GAME_MAP_TEST_FAIL: %s" % ", ".join(failures))
		current_scene = null
		game.queue_free()
		await process_frame
		quit(1)
