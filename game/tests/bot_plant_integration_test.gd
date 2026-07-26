extends SceneTree

const RoundStateScript := preload("res://scripts/cs16_round_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("BOT PLANT INTEGRATION TEST: " + message)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game = packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.start_match()
	game._begin_live()

	var planter = game.allied_bots[0]
	_force_bomb_owner(game, planter.name)
	# Remove visual enemies without changing RoundState's living roster; the
	# objective remains a valid live round while perception returns no target.
	game.player.alive = false
	game.player.controls_enabled = false
	for teammate in game.allied_bots:
		if teammate != planter:
			teammate.alive = false
			teammate.active = false
	for enemy in game.targets:
		enemy.alive = false
		enemy.active = false
	var plant_bounds: AABB = game.bomb_regions[0].bounds
	var plant_position: Vector3 = await _grounded_site_position(game, plant_bounds)
	planter.reset_target(plant_position)
	planter.active = true
	game.round_state.phase = RoundStateScript.PHASE_LIVE
	game.round_state.deadline_tick = (
		game.round_state.tick + int(game.round_state.config.round_ticks) - 4000
	)
	game.phase = RoundStateScript.PHASE_LIVE
	game._sync_round_public_state()

	var planted := false
	var max_weapon_tick := 0
	for tick in 450:
		await physics_frame
		max_weapon_tick = maxi(max_weapon_tick, planter.weapon_tick)
		if game.round_state.bomb_state == RoundStateScript.BOMB_PLANTED:
			planted = true
			break
	_check(
		max_weapon_tick >= 75,
		"the authoritative weapon clock advances with no enemy present",
	)
	_check(
		planted
		and is_instance_valid(game.bomb)
		and game.round_state.bomb_planter_id == planter.name,
		"an uncontested production bot passes 75-tick deploy and completes the "
		+ "300-tick live plant",
	)

	# The source PlantBomb task owns a maximum 500-tick attempt even if the
	# round-side state machine is deliberately held in planting.
	var controller: BotCombatController = planter.combat_controller
	controller._objective_round = 77
	controller._objective_tick = 100
	controller._plant_task_started_tick = -1
	var plant_task := {
		"round_number": 77,
		"action": "plant",
		"plant_in_progress": true,
	}
	controller._apply_plant_patience(plant_task, false)
	controller._objective_tick += 500
	var timed_out: Dictionary = controller._apply_plant_patience(plant_task, false)
	_check(
		str(timed_out.get("action", "")) == "hold_site"
		and str(timed_out.get("state", "")) == "plant_timeout",
		"PlantBomb drops attack on the exact 500-tick task timeout",
	)

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_BOT_PLANT_INTEGRATION_TEST_PASS")
		quit(0)
	else:
		print("GAME_BOT_PLANT_INTEGRATION_TEST_FAIL: " + ", ".join(failures))
		quit(1)


func _force_bomb_owner(game: Node, owner_id: String) -> void:
	for actor_id: String in game.round_state.players:
		var state: Dictionary = game.round_state.players[actor_id]
		state.has_c4 = actor_id == owner_id
		state.alive = true
		game.round_state.players[actor_id] = state
	game.round_state.bomb_owner = owner_id
	game.round_state.bomb_state = RoundStateScript.BOMB_CARRIED
	game._sync_round_public_state()


func _grounded_site_position(game: Node, bounds: AABB) -> Vector3:
	for x_fraction: float in [0.50, 0.30, 0.70, 0.20, 0.80]:
		for z_fraction: float in [0.50, 0.30, 0.70, 0.20, 0.80]:
			var x := bounds.position.x + bounds.size.x * x_fraction
			var z := bounds.position.z + bounds.size.z * z_fraction
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(x, bounds.end.y + 3.0, z),
				Vector3(x, bounds.position.y - 3.0, z),
				1,
			)
			query.collide_with_areas = false
			var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(
				query,
			)
			if hit.is_empty():
				continue
			var candidate := Vector3(x, float(hit.position.y) + 0.002, z)
			if not game._bomb_region_at(
				candidate,
				TargetActor.STANDING_HULL_SIZE,
			).is_empty():
				return candidate
	return bounds.get_center()
