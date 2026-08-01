extends SceneTree

const GameScript := preload("res://scripts/game.gd")

const EPSILON := 0.012

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("HOSTAGE FLOOR/CAMERA TEST: " + message)


func _run() -> void:
	var game := GameScript.new()
	game.map_name = "cs_assault"
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	await physics_frame

	_check(game.hostage_actors.size() == 4, "production Assault spawns four hostages")
	for hostage_id: String in game.hostage_actors:
		var actor: CS16Hostage = game.hostage_actors[hostage_id]
		var hit := _floor_hit(actor)
		_check(not hit.is_empty(), "%s has BSP floor below it" % hostage_id)
		if not hit.is_empty():
			_check(
				absf(actor.global_position.y - float((hit.position as Vector3).y))
					<= EPSILON,
				"%s DROP_TO_FLOOR places feet on BSP collision" % hostage_id,
			)

	var hostage_id: String = game.hostage_actors.keys()[0]
	var hostage: CS16Hostage = game.hostage_actors[hostage_id]
	hostage.hostage_model.force_state("die", 72)
	var bounds := hostage.hostage_model.mesh_instance.mesh.get_aabb()
	var corpse_lowest := (
		hostage.global_position.y
		+ hostage.hostage_model.mesh_instance.position.y
		+ bounds.position.y
	)
	var corpse_floor := _floor_hit(hostage)
	_check(
		not corpse_floor.is_empty()
		and absf(corpse_lowest - float((corpse_floor.position as Vector3).y))
			<= EPSILON,
		"death pose lowest rendered vertex remains registered to BSP floor",
	)

	var button_id := 51
	var queued := game.entity_world.queue_use(
		button_id,
		game.entity_world.entity_count() + 900,
		"pressed",
	)
	game.brush_runtime.advance_tick()
	_check(queued, "Assault camera selector accepts source +use")
	_check(
		game.trigger_camera_entity_id == 110
		and game.trigger_camera.current,
		"cam4 trigger_camera becomes the active production camera",
	)
	_check(
		game.trigger_camera.global_position.distance_to(
			Vector3(-6.88, 3.68, -15.84)
		) <= EPSILON,
		"cam4 uses its exact BSP origin",
	)
	var expected_target := Vector3(-1.68, 2.24, -12.72)
	var camera_forward := -game.trigger_camera.global_transform.basis.z
	var expected_forward := (
		expected_target - game.trigger_camera.global_position
	).normalized()
	_check(
		camera_forward.dot(expected_forward) >= 0.999,
		"cam4 looks at the authored cam4_targ entity",
	)
	game.entity_world.advance_ticks(1000)
	game._advance_trigger_camera()
	_check(
		game.trigger_camera_entity_id == -1
		and game.player.camera.current,
		"trigger_camera wait restores the Player camera",
	)

	current_scene = null
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("HOSTAGE_FLOOR_CAMERA_INTEGRATION_TEST_PASS")
		quit(0)
	else:
		print(
			"HOSTAGE_FLOOR_CAMERA_INTEGRATION_TEST_FAIL (%d)"
			% failures.size()
		)
		quit(1)


func _floor_hit(actor: CS16Hostage) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		actor.global_position + Vector3.UP * 0.08,
		actor.global_position + Vector3.DOWN * 0.20,
		1,
		[actor.get_rid()],
	)
	query.collide_with_areas = false
	query.hit_from_inside = true
	return actor.get_world_3d().direct_space_state.intersect_ray(query)
