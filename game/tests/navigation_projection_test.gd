extends SceneTree

class CorridorProbe extends BotCombatController:
	var calls := 0
	func _objective_segment_is_bsp_clear(start: Vector3, finish: Vector3) -> bool:
		calls += 1
		return finish.distance_to(start) <= 8.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var probe := CorridorProbe.new()
	var route := PackedVector3Array()
	for index in range(100):
		route.append(Vector3(index, 0, 0))
	var compact := probe._compact_objective_route(route)
	if probe.calls > route.size() * 2 or compact[0] != route[0] or compact[-1] != route[-1]:
		push_error("Route compaction exceeds linear sweep budget or loses endpoints")
		quit(1)
		return
	for index in range(1, compact.size()):
		if compact[index].distance_to(compact[index - 1]) > 8.0:
			push_error("Route compaction accepts an obstructed shortcut")
			quit(1)
			return
	probe.free()
	if not _check_synthetic_projection():
		quit(1)
		return
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	var setup: Array[float] = []
	for bot: TargetActor in game._all_bots():
		var started := Time.get_ticks_usec()
		if not bot.combat_controller._ensure_objective_graph():
			push_error("Cannot initialize imported navigation graph")
			quit(1)
			return
		setup.append(float(Time.get_ticks_usec() - started) / 1000.0)
	var controller: BotCombatController = game._all_bots()[0].combat_controller
	var timing_points := PackedVector3Array()
	for index in range(100):
		timing_points.append(Vector3(float(index % 10) * 7.0 - 35.0, 0.5, float(index / 10) * 7.0 - 35.0))
	var started := Time.get_ticks_usec()
	for point: Vector3 in timing_points:
		controller._nearest_objective_polygon(point)
	var indexed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	for point: Vector3 in timing_points:
		_reference_nearest_polygon(controller, point)
	var exhaustive_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("NAVIGATION_PROFILE ", JSON.stringify({"setup_ms": setup, "queries_100_ms": indexed_ms,
		"reference_queries_100_ms": exhaustive_ms, "bvh_nodes": controller._objective_bvh.size(),
		"polygons": controller._objective_polygon_centers.size()}))
	var projection_points := controller._objective_polygon_centers.duplicate()
	var random := RandomNumberGenerator.new()
	random.seed = 0xB47
	for index in range(1000):
		var polygon := controller._objective_polygon_vertices[(index * 997) % controller._objective_polygon_vertices.size()]
		# Authored vertices, shared-edge midpoints, floor offsets, and points
		# outside the map stress exact ties and conservative bounding-box pruning.
		projection_points.append(polygon[0])
		projection_points.append((polygon[0] + polygon[1]) * 0.5)
		projection_points.append(polygon[0] + Vector3(0, random.randf_range(-10, 10), 0))
		projection_points.append(Vector3(random.randf_range(-100, 100), random.randf_range(-20, 30), random.randf_range(-100, 100)))
	if not _check_projection_parity(controller, projection_points, game.map_name):
		quit(1)
		return
	var polygons := controller._objective_polygon_centers
	var checked := 0
	var blocked_queries := 0
	var clear_queries := 0
	var clearance_results := PackedByteArray()
	var clearance_endpoints := PackedVector3Array()
	var clearance_us := 0
	for index in range(1000):
		var start := polygons[(index * 13) % polygons.size()]
		var finish := polygons[(index * 997 + 43) % polygons.size()]
		# Include initially penetrating and zero-motion queries: a shortcut must
		# reject overlaps before casting, or the world body can be ignored.
		if index % 10 == 0:
			start.y -= 0.1
		if index % 17 == 0:
			finish = start
		started = Time.get_ticks_usec()
		var accelerated := controller._objective_segment_is_bsp_clear(start, finish)
		clearance_us += Time.get_ticks_usec() - started
		var reference := _reference_cast(game.get_world_3d().direct_space_state, start, finish)
		clearance_results.append(1 if reference else 0)
		clearance_endpoints.append(start)
		clearance_endpoints.append(finish)
		if reference:
			clear_queries += 1
		else:
			blocked_queries += 1
		if accelerated != reference:
			push_error("Navigation clearance differs from overlap plus full hull reference: %s -> %s" % [start, finish])
			quit(1)
			return
		checked += 1
	# An inactive/empty physics world makes two always-clear implementations
	# agree vacuously. The imported-map gate must exercise both outcomes.
	if blocked_queries == 0 or clear_queries == 0:
		push_error("Navigation clearance fixture must observe both blocked and clear full-hull queries")
		quit(1)
		return
	print("NAVIGATION_CAST_PARITY map=", game.map_name, " segments=", checked,
		" blocked=", blocked_queries, " clear=", clear_queries)
	# Optional cross-backend diagnostic. Identical endpoints and boolean results
	# distinguish an equal-workload comparison from a faster but different route.
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--clearance-report="):
			continue
		var report_file := FileAccess.open(argument.trim_prefix("--clearance-report="), FileAccess.WRITE)
		if report_file == null:
			push_error("Cannot write navigation clearance report")
			quit(1)
			return
		report_file.store_string(JSON.stringify({"map": game.map_name,
			"physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"),
			"physics_space_class": game.get_world_3d().direct_space_state.get_class(),
			"segments": checked, "blocked": blocked_queries, "clear": clear_queries,
			"clearance_cpu_ms": float(clearance_us) / 1000.0,
			"endpoints_sha256": clearance_endpoints.to_byte_array().hex_encode().sha256_text(),
			"results_hex": clearance_results.hex_encode()}, "  "))
		report_file.close()
	game.queue_free()
	await process_frame
	print("GAME_NAVIGATION_PROJECTION_TEST_PASS")
	quit()


func _check_synthetic_projection() -> bool:
	var controller := BotCombatController.new()
	# Large triangle 0 and small triangle 1 share the origin. A nearest-centroid
	# approximation picks 1, and near-first traversal may visit it first; the
	# required exact-distance tie winner is still polygon 0.
	controller._objective_polygon_vertices = [
		PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0), Vector3(0, 0, 100)]),
		PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 1)]),
	]
	for index in range(20):
		var offset := Vector3(float(index - 10) * 7.0, float(index % 3) * 4.0, 0)
		controller._objective_polygon_vertices.append(PackedVector3Array([
			offset, offset + Vector3(1, 0, 0), offset + Vector3(0, 0, 1),
		]))
	for polygon: PackedVector3Array in controller._objective_polygon_vertices:
		controller._objective_polygon_centers.append((polygon[0] + polygon[1] + polygon[2]) / 3.0)
	controller._objective_polygon_components.resize(controller._objective_polygon_vertices.size())
	controller._objective_polygon_components.fill(0)
	controller._build_objective_spatial_index()
	var points := PackedVector3Array([Vector3.ZERO, Vector3(0.2, 0, 0.2), Vector3.INF])
	for x in range(-12, 13):
		for y in range(-2, 12):
			points.append(Vector3(x * 7, y, 0.25))
	var passed := _check_projection_parity(controller, points, "synthetic_all")
	passed = passed and controller._nearest_objective_polygon(Vector3.ZERO) == 0
	controller._objective_polygon_components[0] = 1
	controller._objective_main_component = 0
	controller._build_objective_spatial_index()
	passed = _check_projection_parity(controller, points, "synthetic_component") and passed
	passed = passed and controller._nearest_objective_polygon(Vector3.ZERO) == 1
	controller._objective_polygon_vertices.clear()
	controller._build_objective_spatial_index()
	passed = passed and controller._nearest_objective_polygon(Vector3.ZERO) == -1
	controller.free()
	if not passed:
		push_error("Synthetic indexed projection changes ties, components, or empty-mesh behavior")
	return passed


func _check_projection_parity(controller: BotCombatController, points: PackedVector3Array, label: String) -> bool:
	for point: Vector3 in points:
		var actual := controller._nearest_objective_polygon(point)
		var expected := _reference_nearest_polygon(controller, point)
		if actual != expected:
			push_error("Indexed projection changes polygon ID at %s: indexed=%d reference=%d (%s)" % [point, actual, expected, label])
			return false
	print("NAVIGATION_PROJECTION_PARITY map=", label, " points=", points.size())
	return true


func _reference_nearest_polygon(controller: BotCombatController, point: Vector3) -> int:
	# Original ascending exhaustive implementation, independent of the index.
	var nearest := -1
	var nearest_distance := INF
	for polygon_index in controller._objective_polygon_vertices.size():
		if controller._objective_main_component >= 0 and controller._objective_polygon_components[polygon_index] != controller._objective_main_component:
			continue
		var polygon := controller._objective_polygon_vertices[polygon_index]
		if polygon.size() < 3:
			continue
		for triangle_index in range(1, polygon.size() - 1):
			var closest := controller._closest_point_on_triangle(point, polygon[0], polygon[triangle_index], polygon[triangle_index + 1])
			var distance := point.distance_squared_to(closest)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = polygon_index
	return nearest


func _reference_cast(space: PhysicsDirectSpaceState3D, start: Vector3, finish: Vector3) -> bool:
	var hull := BoxShape3D.new()
	hull.size = Vector3(32.0, 72.0, 32.0) * Combatant.GOLDSRC_UNIT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull
	query.collision_mask = 1
	query.collide_with_areas = false
	query.transform = Transform3D(Basis.IDENTITY, start + Vector3.UP * (36.0 * Combatant.GOLDSRC_UNIT + 0.02))
	query.motion = finish - start
	if not space.intersect_shape(query, 1).is_empty():
		return false
	var cast := space.cast_motion(query)
	return not cast.is_empty() and float(cast[0]) >= 0.995
