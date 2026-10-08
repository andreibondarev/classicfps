extends SceneTree

const BspClearanceIndex = preload("res://tests/bsp_clearance_index_probe.gd")

class ClearanceProbe extends BotCombatController:
	var index: BspClearanceIndex
	var world_rid := RID()
	var checks := 0
	var certified := 0
	var failures := 0
	var blocked := 0
	var original_us := 0
	var accelerated_us := 0
	var certified_original_us := 0
	var initial_world_overlaps := 0
	var initial_world_overlap_blocked := 0
	var initial_overlap_original_us := 0

	func _objective_segment_is_bsp_clear(start: Vector3, finish: Vector3) -> bool:
		var started := Time.get_ticks_usec()
		var original := super._objective_segment_is_bsp_clear(start, finish)
		var original_elapsed := Time.get_ticks_usec() - started
		original_us += original_elapsed
		if not original:
			blocked += 1
		var original_motion := _objective_hull_query.motion
		_objective_hull_query.motion = Vector3.ZERO
		for hit: Dictionary in actor.get_world_3d().direct_space_state.intersect_shape(_objective_hull_query, 32):
			if hit.get("rid") == world_rid:
				initial_world_overlaps += 1
				initial_overlap_original_us += original_elapsed
				if not original:
					initial_world_overlap_blocked += 1
		_objective_hull_query.motion = original_motion
		started = Time.get_ticks_usec()
		var query := _objective_hull_query
		var accelerated := original
		# The production clearance contract also rejects starting overlaps.
		# Keep the experimental broad phase subject to that same safety rule.
		accelerated = false
		if actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			if not index.may_hit(query.transform.origin, query.transform.origin + query.motion):
				certified += 1
				certified_original_us += original_elapsed
				query.exclude = [world_rid]
			var cast := actor.get_world_3d().direct_space_state.cast_motion(query)
			accelerated = not cast.is_empty() and float(cast[0]) >= 0.995
		query.exclude = []
		accelerated_us += Time.get_ticks_usec() - started
		checks += 1
		if original != accelerated:
			failures += 1
			push_error("Conservative BSP broad phase changed clearance: %s -> %s" % [start, finish])
		return original


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	# Disabling process_mode also removes inherited CollisionObject3D bodies
	# from physics. Stop callbacks individually so the collision world stays live.
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	await process_frame
	await physics_frame
	var index := BspClearanceIndex.new()
	var started := Time.get_ticks_usec()
	index.build(game.imported_map._collision_faces, Vector3(0.16, 0.36, 0.16))
	var build_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var totals := {"checks": 0, "certified": 0, "blocked": 0, "failures": 0, "original_us": 0, "accelerated_us": 0, "certified_original_us": 0,
		"initial_world_overlaps": 0, "initial_world_overlap_blocked": 0, "initial_overlap_original_us": 0}
	var route_validations: Array[Dictionary] = []
	for bot: TargetActor in game._all_bots():
		var probe := ClearanceProbe.new()
		game.add_child(probe)
		probe.index = index
		probe.world_rid = game.imported_map.model_collision_body(0).get_rid()
		probe.configure(bot, bot.navigation_agent, bot.index)
		probe._ensure_objective_graph()
		# Initial patrol routes exercise the costly long-prefix smoothing work.
		for generation in range(3):
			probe._patrol_generation = generation
			probe._objective_route = PackedVector3Array()
			probe._objective_navigation_velocity_to(probe._choose_patrol_target(), 0.01)
			route_validations.append({"bot": str(bot.name), "generation": generation,
				"points": probe._objective_route.size(),
				"all_segments_clear": probe._objective_route_is_bsp_clear(probe._objective_route)})
		var polygons := probe._objective_polygon_centers
		for sample in range(200):
			var from := polygons[(sample * 97 + bot.index) % polygons.size()]
			var to := polygons[(sample * 997 + 43) % polygons.size()]
			if sample % 10 == 0:
				from.y -= 0.1
			if sample % 17 == 0:
				to = from
			probe._objective_segment_is_bsp_clear(from, to)
		for key: String in totals:
			totals[key] += int(probe.get(key))
		probe.queue_free()
	print("BSP_CLEARANCE_INDEX_PROFILE ", JSON.stringify({"map": game.map_name,
		"physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"direct_space_class": game.get_world_3d().direct_space_state.get_class(),
		"build_ms": build_ms, "nodes": index.nodes.size(), "totals": totals,
		"route_validations": route_validations}))
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	MdlViewModel.release_cached_resources()
	MdlCharacterModel.release_cached_resources()
	CS16CombatEffects.release_cached_resources()
	var passed: bool = totals.failures == 0 and totals.certified > 0 and totals.blocked > 100
	print("GAME_BSP_CLEARANCE_INDEX_TEST_PASS" if passed else "GAME_BSP_CLEARANCE_INDEX_TEST_FAIL")
	quit(0 if passed else 1)
