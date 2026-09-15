extends SceneTree

## Export exact geometry and fractions for independent backend diagnostics.
## No production behavior is replaced, and completion is not a fidelity pass.
func _initialize() -> void:
	call_deferred("_run")


func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _run() -> void:
	var path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			path = argument.trim_prefix("--report=")
	if path.is_empty():
		push_error("Collision backend probe requires --report=...")
		quit(1)
		return
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	await physics_frame
	await physics_frame
	var controller: BotCombatController = game._all_bots()[0].combat_controller
	controller._ensure_objective_graph()
	var polygons := controller._objective_polygon_centers
	var indices := [173, 176, 456, 592, 824] if game.map_name == "de_dust2" else [689, 691, 804]
	var queries: Array[Dictionary] = []
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for index: int in indices:
		var start := polygons[(index * 13) % polygons.size()]
		var finish := polygons[(index * 997 + 43) % polygons.size()]
		controller._objective_segment_is_bsp_clear(start, finish)
		var query := controller._objective_hull_query
		var fractions := space.cast_motion(query)
		var initial_hits: Array[int] = []
		query.motion = Vector3.ZERO
		for hit: Dictionary in space.intersect_shape(query, 32):
			initial_hits.append(int(hit.collider.get_meta("model_index", -1)))
		queries.append({"index": index, "origin": _vector(query.transform.origin),
			"motion": _vector(finish - start), "half_size": _vector(query.shape.size * 0.5),
			"fractions": Array(fractions), "initial_models": initial_hits})
	var geometry: Array[Dictionary] = []
	for model: int in game.imported_map._model_collision_bodies:
		var body: CollisionObject3D = game.imported_map.model_collision_body(model)
		if (body.collision_layer & 1) == 0:
			continue
		for child in body.get_children():
			if not child is CollisionShape3D or child.disabled or not child.shape is ConcavePolygonShape3D:
				continue
			var vertices: Array = []
			for vertex: Vector3 in child.shape.get_faces():
				vertices.append(_vector(child.global_transform * vertex))
			geometry.append({"model": model, "backface_collision": child.shape.backface_collision,
				"vertices": vertices})
	var report := {"map": game.map_name, "physics_space_class": space.get_class(),
		"queries": queries, "geometry": geometry}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write collision backend probe")
		quit(1)
		return
	file.store_string(JSON.stringify(report))
	file.close()
	print("COLLISION_BACKEND_QUERIES ", JSON.stringify({"map": game.map_name,
		"physics_space_class": space.get_class(), "queries": queries}))
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	MdlViewModel.release_cached_resources()
	MdlCharacterModel.release_cached_resources()
	CS16CombatEffects.release_cached_resources()
	print("GAME_COLLISION_BACKEND_DIAGNOSTIC_PASS")
	quit()
