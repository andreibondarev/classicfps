extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("NAVIGATION CLEARANCE TEST: " + message)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var actor := Combatant.new()
	actor.collision_layer = 0
	world.add_child(actor)
	var controller := BotCombatController.new()
	world.add_child(controller)
	controller.possess(actor)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	# Floor and wall belong to one concave body, matching an imported BSP world.
	shape.set_faces(PackedVector3Array([
		Vector3(-5, 0, -5), Vector3(5, 0, -5), Vector3(5, 0, 5),
		Vector3(-5, 0, -5), Vector3(5, 0, 5), Vector3(-5, 0, 5),
		Vector3(1, 0, -1), Vector3(1, 2, -1), Vector3(1, 2, 1),
		Vector3(1, 0, -1), Vector3(1, 2, 1), Vector3(1, 0, 1),
	]))
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	await physics_frame
	await physics_frame
	var cases := [
		[Vector3(0, 0.1, 3), Vector3(3, 0.1, 3), true, "open corridor is clear"],
		[Vector3(0, 0.1, 0), Vector3(3, 0.1, 0), false, "full hull cannot cross the wall"],
		[Vector3(0, 0.1, 1.1), Vector3(3, 0.1, 1.1), false, "shoulder collision blocks a clear center ray"],
		[Vector3(0, 0.1, 1.17), Vector3(3, 0.1, 1.17), true, "hull clears the finite wall edge"],
		[Vector3(0, -0.03, 0), Vector3(3, -0.03, 0), false, "initial floor overlap cannot hide a later wall"],
		[Vector3(0, -0.03, 3), Vector3(0, -0.03, 3), false, "stationary penetrating hull is not clear"],
		[Vector3(1, 0.1, 0), Vector3(-1, 0.1, 0), false, "initial wall overlap is not a safe shortcut"],
		[Vector3(0, 0.1, 3), Vector3(0, 0.1, 3), true, "stationary empty hull is clear"],
	]
	for entry: Array in cases:
		_check(controller._objective_segment_is_bsp_clear(entry[0], entry[1]) == entry[2], entry[3])
	controller._objective_route = PackedVector3Array([
		Vector3(0, 0.04, 0), Vector3(0.8, 0.04, 1.2), Vector3(2, 0.04, 1.2),
	])
	actor.global_position = Vector3(0.8, 0.002, 0.9)
	_check(not controller._objective_waypoint_reached(1),
		"being inside a corner radius cannot skip a shoulder-blocked outgoing segment")
	actor.global_position = Vector3(0.8, 0.002, 1.18)
	_check(controller._objective_waypoint_reached(1),
		"planar steering deadzone consumes a reached waypoint despite navmesh floor offset")
	actor.global_position = Vector3(0.8, 0.002, 1.3)
	_check(controller._objective_waypoint_reached(1), "clear passed corners still advance")
	controller._objective_required_waypoints[1] = true
	actor.global_position = Vector3(0.8, 0.002, 1.4)
	_check(not controller._objective_waypoint_reached(1), "required traversal approach cannot be cut by ordinary steering radius")
	controller._objective_required_waypoints.clear()
	body.collision_layer = 2
	await physics_frame
	await physics_frame
	_check(controller._objective_segment_is_bsp_clear(Vector3(0, -0.03, 0), Vector3(3, -0.03, 0)),
		"both overlap and sweep respect the world collision mask")
	world.queue_free()
	await process_frame
	print("GAME_NAVIGATION_CLEARANCE_CONTRACT_TEST_PASS" if failures.is_empty() else "GAME_NAVIGATION_CLEARANCE_CONTRACT_TEST_FAIL")
	quit(0 if failures.is_empty() else 1)
