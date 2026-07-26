extends SceneTree

const CombatantScript := preload("res://scripts/combatant.gd")
const C4WorldScript := preload("res://scripts/cs16_c4_world.gd")
const RoundStateScript := preload("res://scripts/cs16_round_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("C4 OBJECTIVE INTEGRATION TEST: " + message)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game = packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.start_match()
	game._begin_live()

	_force_bomb_owner(game, "player")
	game._sync_round_public_state()
	_check(game._equip_player_c4(), "human carrier can equip its real C4 item")
	_check(
		game.player.active_weapon == "c4"
		and game.player.viewmodel.loaded_weapon == "c4"
		and game.player.weapon_clock.deploy_complete_tick - game.player.weapon_clock.tick == 75,
		"real v_c4 deploys with the source 0.75 s draw lock",
	)
	_check(
		is_equal_approx(game.player._maximum_speed(false), 2.5),
		"equipped C4 caps the carrier at 250 HU/s",
	)
	var clip_before: int = game.player.clip
	var shot_sequence_before: int = game.player._shot_sequence
	game.player._try_fire()
	_check(
		game.player.clip == clip_before
		and game.player._shot_sequence == shot_sequence_before,
		"C4 primary never emits a firearm bullet or consumes its objective clip",
	)

	var drop_origin: Vector3 = game.player.global_position
	var drop_forward: Vector3 = -game.player.global_transform.basis.z
	drop_forward.y = 0.0
	drop_forward = drop_forward.normalized()
	game.round_state.set_player_alive("player", false, drop_origin)
	game._consume_new_round_trace()
	_check(
		is_instance_valid(game.dropped_c4)
		and game.round_state.bomb_state == RoundStateScript.BOMB_DROPPED,
		"carrier death creates one live dropped-C4 weaponbox",
	)
	var dropped = game.dropped_c4
	_check(
		dropped.global_position.distance_to(
			drop_origin + drop_forward * 10.0 * CombatantScript.GOLDSRC_UNIT
		) < 0.0001
		and dropped.linear_velocity.distance_to(
			drop_forward * 400.0 * CombatantScript.GOLDSRC_UNIT
		) < 0.0001,
		"weaponbox spawns +10 HU and tosses forward at 400 HU/s",
	)
	_check(
		_surface_count(dropped) == 1
		and dropped.world_shape_node.shape is SphereShape3D
		and is_equal_approx(
			(dropped.world_shape_node.shape as SphereShape3D).radius,
			CombatantScript.GOLDSRC_UNIT,
		),
		"dropped weaponbox renders source w_backpack and uses a point-like fall hull",
	)

	var ct = game.targets[0]
	dropped._on_pickup_body_entered(ct)
	_check(not dropped.claimed, "airborne C4 cannot be picked up")
	dropped._materialize()
	dropped._on_pickup_body_entered(ct)
	_check(not dropped.claimed, "Counter-Terrorists cannot pick up a landed C4")
	var recovering_t = game.allied_bots[0]
	recovering_t.alive = false
	dropped._on_pickup_body_entered(recovering_t)
	_check(not dropped.claimed, "dead Terrorists cannot pick up a landed C4")
	recovering_t.alive = true
	dropped._on_pickup_body_entered(recovering_t)
	_check(
		dropped.claimed
		and game.round_state.bomb_owner == recovering_t.name
		and bool(game.round_state.players[recovering_t.name].has_c4),
		"live Terrorist touch transfers authoritative C4 ownership human-to-bot",
	)
	await process_frame
	_check(not is_instance_valid(game.dropped_c4), "successful pickup removes the weaponbox")

	# Drive a real 300-tick plant through Game's production command builder and
	# the authoritative round state. This is deliberately not a direct visual
	# spawn: crouch/look/equip/attack must produce the event that creates w_c4.
	_force_bomb_owner(game, "player")
	game.round_state.phase = RoundStateScript.PHASE_LIVE
	game.round_state.deadline_tick = game.round_state.tick + 5000
	game.phase = RoundStateScript.PHASE_LIVE
	var plant_bounds: AABB = game.bomb_regions[0].bounds
	var planted_feet := _grounded_bombsite_position(game, plant_bounds)
	game.player.reset_player(planted_feet, true)
	game.player.controls_enabled = true
	game.player._yaw = 0.72
	game.player._sync_view_angles()
	game._sync_round_public_state()
	_check(game._equip_player_c4(), "live planter equips C4 before entering attack")
	for settle_frame in 12:
		game.player._physics_process(0.01)
		await physics_frame
	_check(
		not game._bomb_region_at(
			game.player.global_position,
			game._player_hull_size(),
		).is_empty()
		and game._player_objective_grounded(),
		"live planter is grounded inside the imported func_bomb_target "
		+ "(position=%s velocity=%s site=%s floor=%s)"
		% [
			game.player.global_position,
			game.player.velocity,
			not game._bomb_region_at(
				game.player.global_position,
				game._player_hull_size(),
			).is_empty(),
			game._player_objective_grounded(),
		],
	)
	Input.action_press("fire")
	var first_plant_command: Dictionary = game._round_tick_command()
	_check(
		not bool(first_plant_command.plant.attack)
		and bool(first_plant_command.plant.equipped_c4)
		and bool(first_plant_command.plant.grounded)
		and bool(first_plant_command.plant.in_bomb_site),
		"held attack is rejected while the real v_c4 deploy lock is active "
		+ "(request=%s)" % first_plant_command.get("plant", {}),
	)
	var deploy_wait_ticks := 0
	while not game.player.weapon_clock.can_primary_attack():
		var deploy_command: Dictionary = game._round_tick_command()
		_check(
			not bool(deploy_command.plant.attack),
			"plant remains blocked for every pre-deploy tick",
		)
		var deploy_events: Array[Dictionary] = game.round_state.advance_tick(
			deploy_command,
		)
		game._consume_round_events(deploy_events)
		game.player._advance_weapon_simulation_tick()
		deploy_wait_ticks += 1
		_check(deploy_wait_ticks <= 75, "C4 deploy lock terminates by tick 75")
	_check(
		bool(game._round_tick_command().plant.attack),
		"held attack becomes plant-authoritative on the exact deploy deadline",
	)
	var plant_start_position: Vector3 = game.player.global_position
	for plant_tick in 301:
		var command: Dictionary = game._round_tick_command()
		var events: Array[Dictionary] = game.round_state.advance_tick(command)
		game._consume_round_events(events)
		game._consumed_round_events = game.round_state.trace.size()
		game._sync_round_public_state()
		game._update_round_hud(true)
		game.player._physics_process(0.01)
		game.player.viewmodel._process(0.01)
	Input.action_release("fire")
	_check(
		game.round_state.bomb_state == RoundStateScript.BOMB_PLANTED
		and game.phase == RoundStateScript.PHASE_BOMB
		and is_instance_valid(game.bomb),
		"301 production ticks complete the exact 300-tick plant and spawn w_c4",
	)
	if not is_instance_valid(game.bomb):
		Input.action_release("fire")
		await _finish(game)
		return
	_check(
		game.player.global_position.distance_to(plant_start_position)
		<= 3.0 * CombatantScript.GOLDSRC_UNIT
		and not game.player.objective_movement_locked,
		"plant actor stays within the 1-HU/s source cap and unlocks on bomb phase",
	)
	var plant_position: Vector3 = game.round_state.bomb_position
	var planter_yaw := 0.72
	_check(
		is_instance_valid(game.bomb)
		and game.bomb.global_position.distance_to(plant_position) < 0.00001
		and is_equal_approx(
			game.bomb.rotation.y,
			planter_yaw - deg_to_rad(90.0),
		),
		"planted w_c4 keeps exact planter origin and source yaw-minus-90",
	)
	_check(
		_surface_count(game.bomb) == 3,
		"planted C4 renders all three source w_c4 MDL surfaces",
	)
	var use_shape := _first_collision_shape(game.bomb)
	_check(
		is_instance_valid(use_shape)
		and use_shape.shape is BoxShape3D
		and (use_shape.shape as BoxShape3D).size.distance_to(
			Vector3(6.0, 8.0, 12.0) * CombatantScript.GOLDSRC_UNIT
		) < 0.00001,
		"planted C4 exposes the exact source (-3,-6,0)..(3,6,8) HU use body",
	)

	# Let the production bot task move the assigned CT from outside the 100-HU
	# use range. Clear the surviving T actors so this scenario isolates the
	# post-retake objective instead of letting line-of-sight combat correctly
	# interrupt a defuser. The planted bomb remains live after T elimination,
	# matching Counter-Strike round rules. Other CTs must visibly move toward
	# distinct guard cover.
	game.player.alive = false
	game.player.controls_enabled = false
	game.round_state.set_player_alive("player", false, game.player.global_position)
	for terrorist in game.allied_bots:
		terrorist.alive = false
		terrorist.active = false
		game.round_state.set_player_alive(
			terrorist.name,
			false,
			terrorist.global_position,
		)
	var defuser = game._active_bot_defuser()
	if not is_instance_valid(defuser):
		_check(false, "production task assigns a living CT defuser")
		await _finish(game)
		return
	for bot in game.targets:
		bot.active = true
		bot.set_objective_lock(false)
	var guard_start_positions := {}
	for bot in game.targets:
		guard_start_positions[bot] = bot.global_position
	for navigation_wait in 300:
		var map: RID = defuser.navigation_agent.get_navigation_map()
		if (
			map.is_valid()
			and NavigationServer3D.map_get_iteration_id(map) > 0
		):
			break
		await physics_frame
	var initial_defuser = defuser
	initial_defuser.set_physics_process(false)
	for stall_frame in game.BOT_DEFUSER_STALL_FRAMES + 2:
		await physics_frame
	defuser = game._active_bot_defuser()
	initial_defuser.set_physics_process(true)
	_check(
		is_instance_valid(defuser) and defuser != initial_defuser,
		"zero-progress assigned defuser is deterministically released and "
		+ "reassigned instead of freezing the retake",
	)
	# This scenario audits the five-second kit path even if the deterministic
	# stall watchdog hands the role to another moving CT mid-retake.
	for ct_bot in game.targets:
		game.round_state.set_defuser(ct_bot.name, true)
	var approached := false
	var consumed_runtime_waypoints := {}
	for approach_tick in 3500:
		await physics_frame
		var current_defuser = game._active_bot_defuser()
		if is_instance_valid(current_defuser):
			defuser = current_defuser
			consumed_runtime_waypoints[
				"%s:%d" % [
					defuser.name,
					defuser.combat_controller._objective_route_index,
				]
			] = true
		if (
			defuser.global_position.distance_to(plant_position)
			<= game.MAX_PLAYER_USE_RADIUS
			and defuser.is_on_floor()
			):
				approached = true
				break
	if approached:
		# The approach threshold is observed immediately after pawn physics.
		# Give the production round command and teammates one authoritative
		# frame to start the use interaction and switch into guard roles.
		await physics_frame
	print(
		"GAME_C4_RETAKE_ROUTE_METRIC consumed=%d backing=%d"
		% [
			consumed_runtime_waypoints.size(),
			defuser.combat_controller._objective_route.size(),
		],
	)
	_check(
		approached
		and str(defuser.last_command.get("objective_action", "")) == "defuse",
		"assigned CT follows the live retake task into the source 64-HU use radius "
		+ "(bot=%s position=%s bomb=%s distance_hu=%.1f command=%s)"
		% [
			defuser.name,
			defuser.global_position,
			plant_position,
			defuser.global_position.distance_to(plant_position)
				/ CombatantScript.GOLDSRC_UNIT,
			defuser.last_command,
		],
	)
	var moving_guards := 0
	var guard_targets: Array[Vector3] = []
	var guarding_bots := 0
	for bot in game.targets:
		if bot == defuser:
			continue
		var guard_action := str(bot.last_command.get("objective_action", ""))
		_check(
			guard_action in ["guard", "search_site"],
			"%s searches the planted site or guards the live defuse" % bot.name,
		)
		if guard_action == "guard":
			guarding_bots += 1
			guard_targets.append(
				bot.last_command.get("objective_target", Vector3.ZERO)
			)
		if bot.global_position.distance_to(guard_start_positions[bot]) > 0.10:
			moving_guards += 1
	_check(
		guarding_bots > 0
		and
		_unique_vector_count(guard_targets) == guard_targets.size()
		and moving_guards > 0,
		"defuse guards hold distinct live cover assignments",
	)
	defuser.face_aim_target(plant_position)
	var first_defuse_command: Dictionary = game._round_tick_command()
	_check(
		str(first_defuse_command.defuse.player_id) == defuser.name
		and bool(first_defuse_command.defuse.use)
		and bool(first_defuse_command.defuse.grounded)
		and bool(first_defuse_command.defuse.in_range)
		and bool(first_defuse_command.defuse.facing),
		"production +use request accepts the approached/facing assigned defuser",
	)
	for defuse_tick in 501:
		var command: Dictionary = game._round_tick_command()
		var events: Array[Dictionary] = game.round_state.advance_tick(command)
		game._consume_round_events(events)
		game._consumed_round_events = game.round_state.trace.size()
		game._sync_round_public_state()
		if defuse_tick == 0:
			defuser._physics_process(0.01)
			_check(
				defuser.objective_movement_locked
				and defuser.objective_crouch
				and defuser.objective_look_target.distance_to(plant_position) < 0.001,
				"live defuse start locks, crouches, and looks at the bomb",
			)
	_check(
		game.round_state.bomb_state == RoundStateScript.BOMB_DEFUSED
		and game.round_state.round_winner == RoundStateScript.TEAM_CT,
		"continuous live +use completes the source 5-second kit defuse "
		+ "(state=%s tick=%d deadline=%d defuse_actor=%s)"
		% [
			game.round_state.bomb_state,
			game.round_state.tick,
			game.round_state.bomb_deadline_tick,
			game.round_state.defuse_actor,
		],
	)

	await _finish(game)


func _force_bomb_owner(game: Node, player_id: String) -> void:
	for actor_id: String in game.round_state.players:
		var actor_state: Dictionary = game.round_state.players[actor_id]
		actor_state.has_c4 = actor_id == player_id
		actor_state.alive = true
		game.round_state.players[actor_id] = actor_state
	game.player.alive = true
	game.round_state.bomb_owner = player_id
	game.round_state.bomb_state = RoundStateScript.BOMB_CARRIED


func _grounded_bombsite_position(game: Node, bounds: AABB) -> Vector3:
	var fractions := [0.50, 0.30, 0.70, 0.20, 0.80]
	for x_fraction: float in fractions:
		for z_fraction: float in fractions:
			var x: float = bounds.position.x + bounds.size.x * x_fraction
			var z: float = bounds.position.z + bounds.size.z * z_fraction
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
			if game._bomb_region_at(
				candidate,
				game._player_hull_size(),
			).is_empty():
				continue
			var hull_shape := BoxShape3D.new()
			hull_shape.size = game._player_hull_size()
			var hull_query := PhysicsShapeQueryParameters3D.new()
			hull_query.shape = hull_shape
			hull_query.transform = Transform3D(
				Basis.IDENTITY,
				candidate + Vector3.UP * (
					game._player_hull_size().y * 0.5 + 0.001
				),
			)
			hull_query.collision_mask = 1
			hull_query.exclude = [game.player.get_rid()]
			hull_query.collide_with_areas = false
			if game.get_world_3d().direct_space_state.intersect_shape(
				hull_query,
				1,
			).is_empty():
				return candidate
	return Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)


func _surface_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if is_instance_valid(mesh_instance.mesh):
			count += mesh_instance.mesh.get_surface_count()
	for child in node.get_children():
		count += _surface_count(child)
	return count


func _first_collision_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node as CollisionShape3D
	for child in node.get_children():
		var found := _first_collision_shape(child)
		if is_instance_valid(found):
			return found
	return null


func _unique_vector_count(vectors: Array[Vector3]) -> int:
	var unique: Array[Vector3] = []
	for value in vectors:
		if not unique.has(value):
			unique.append(value)
	return unique.size()


func _teardown(game: Node) -> void:
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.audio_router.stop_all("test_teardown")
	await process_frame
	current_scene = null
	game.queue_free()
	await process_frame


func _finish(game: Node) -> void:
	if failures.is_empty():
		print("GAME_C4_OBJECTIVE_INTEGRATION_TEST_PASS")
		await _teardown(game)
		quit(0)
	else:
		print("GAME_C4_OBJECTIVE_INTEGRATION_TEST_FAIL (%d)" % failures.size())
		await _teardown(game)
		quit(1)
