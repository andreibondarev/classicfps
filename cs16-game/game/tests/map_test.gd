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
		if (
			target.combat_controller is BotCombatController
			and (target.combat_controller as BotCombatController)._objective_route.size() > 1
		):
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
		_check(
			game.imported_map.world_collision_face_count == 9476,
			"Dust2 WorldCollision contains only immutable model 0 faces",
		)
		_check(
			game.imported_map.submodel_collision_face_count == 120,
			"Dust2 solid brush models use independent collision proxies",
		)
		_check(
			game.imported_map.collision_face_count == 9596,
			"all solid Dust2 collision faces loaded without WorldCollision duplication",
		)
		_check(
			game.imported_map.runtime_model_indices().size() == 42,
			"Dust2 creates one transform root for every nonzero BSP model",
		)
		_check(
			game.imported_map.collision_body_for_model(1) is AnimatableBody3D,
			"Dust2 breakable model 1 has an independently movable collision proxy",
		)
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
	var ct_states: Array[String] = []
	var ct_states_are_active := true
	for target: TargetActor in game.targets:
		ct_states.append(target.combat_state)
		ct_states_are_active = (
			ct_states_are_active
				and target.combat_state in ["patrol", "defend_site"]
		)
	_check(
		ct_states_are_active,
		"distant CT bots enter an active hunt or bombsite-defense state: %s"
		% [ct_states],
	)
	_check(
		ct_states.has("patrol") and ct_states.has("defend_site"),
		"Dust2 CTs split between patrol and bombsite defense roles: %s"
		% [ct_states],
	)
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
