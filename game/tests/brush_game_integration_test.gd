extends SceneTree

const GameScript := preload("res://scripts/game.gd")
const BrushRuntime := preload("res://scripts/cs16_brush_runtime.gd")
const EntityWorld := preload("res://scripts/cs16_entity_world.gd")

var failures: Array[String] = []


class DoorDriver extends CombatController:
	var destination := Vector3.ZERO
	func gather_command(delta: float) -> Dictionary:
		var command := super.gather_command(delta)
		var offset := destination - actor.global_position
		offset.y = 0.0
		command.world_velocity = offset.normalized() * 2.21 if offset.length() > 0.05 else Vector3.ZERO
		command.look_target = destination
		return command


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BRUSH GAME INTEGRATION TEST: " + message)


func _run() -> void:
	var game := GameScript.new()
	game.map_name = "cs_assault"
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame

	_check(
		game.brush_runtime != null
		and game.brush_runtime.brush_count() == 9,
		"production Game binds all nine stock Assault doors and buttons",
	)
	_check(
		game._brush_world_aabb(11).size.length_squared() > 0.0,
		"production interaction derives a live world-space AABB from the rotating BSP model",
	)

	game.start_match()
	var tick_before := int(game.entity_world.tick)
	game._physics_process(0.01)
	_check(
		int(game.entity_world.tick) == tick_before + 1,
		"Game advances the shared entity/brush clock exactly once per 100 Hz frame",
	)

	game.brush_runtime.set_activator_position(9001, Vector3.ZERO)
	_check(
		game.entity_world.queue_touch(11, 9001, EntityWorld.TOUCH_ENTER),
		"stock Assault entrance accepts production touch input",
	)
	for ignored_tick in range(90):
		game._physics_process(0.01)
	_check(
		game.brush_runtime.get_brush(11).state == BrushRuntime.STATE_OPEN,
		"production Game completes the Assault entrance's exact 0.9-second sweep",
	)
	var rotating_root := game.imported_map.model_root(11)
	_check(
		is_instance_valid(rotating_root)
		and absf(
			rad_to_deg(rotating_root.basis.get_rotation_quaternion().get_angle())
			- 90.0
		) <= 0.001,
		"production visual and collision root reaches the authored 90-degree endpoint",
	)
	var audio_events: Array[String] = []
	for event: Dictionary in game.audio_router.trace():
		if str(event.get("kind", "")) == "start":
			audio_events.append(str(event.get("event_name", "")))
	_check(
		"door.move9" in audio_events and "door.stop4" in audio_events,
		"production Assault entrance routes its authored move9 and stop4 samples",
	)

	game._consume_round_events([{"type": "round_start", "round": 2}])
	_check(
		game.entity_world.tick == 0
		and game.brush_runtime.get_brush(11).state == BrushRuntime.STATE_CLOSED
		and rotating_root.transform.is_equal_approx(
			game.imported_map.initial_transform_for_model(11)
		),
		"production round start atomically resets entity time, door state, transform, and collision",
	)
	await _check_physical_door_crossing(game)
	await _check_hostage_door_crossing(game)

	if failures.is_empty():
		print("GAME_BRUSH_INTEGRATION_TEST_PASS")
		current_scene = null
		game.queue_free()
		await process_frame
		await create_timer(0.2).timeout
		quit(0)
	else:
		print("GAME_BRUSH_INTEGRATION_TEST_FAIL (%d)" % failures.size())
		current_scene = null
		game.queue_free()
		await process_frame
		await create_timer(0.2).timeout
		quit(1)


func _door_ray(game: Node, start: Vector3, finish: Vector3) -> Dictionary:
	return game.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(start, finish, 1)
	)


func _check_physical_door_crossing(game: Node) -> void:
	game._begin_live()
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
		bot.collision_layer = 0
	var actor: TargetActor = game._all_bots()[0]
	actor.reset_target(Vector3(7.6, 0.04, -22.08))
	actor.collision_mask = 1
	var previous_controller := actor.combat_controller
	actor.remove_child(previous_controller)
	previous_controller.queue_free()
	var driver := DoorDriver.new()
	actor.add_child(driver)
	driver.possess(actor)
	actor.combat_controller = driver
	driver.destination = actor.global_position
	await physics_frame
	await physics_frame
	var door: CollisionObject3D = game.imported_map.model_collision_body(11)
	var ray_start := Vector3(7.6, 0.5, -22.08)
	var ray_end := Vector3(6.5, 0.5, -22.08)
	_check(_door_ray(game, ray_start, ray_end).get("collider") == door,
		"closed door really blocks the entrance ray")
	for tick in 12:
		await physics_frame
		game._physics_process(0.01)
		actor._physics_process(0.01)
	_check(game.brush_runtime.get_brush(11).state == BrushRuntime.STATE_CLOSED,
		"standing near the entrance without contact does not trigger the door")
	driver.destination = Vector3(6.44, 0.04, -22.08)
	var saw_contact := false
	var max_displacement := 0.0
	for tick in 180:
		await physics_frame
		game._physics_process(0.01)
		var before := actor.global_position
		actor._physics_process(0.01)
		saw_contact = saw_contact or actor._brush_contacts.has(11)
		max_displacement = maxf(max_displacement, before.distance_to(actor.global_position))
	_check(saw_contact, "normal movement reports an actual door collision")
	_check(game.brush_runtime.get_brush(11).state == BrushRuntime.STATE_OPEN,
		"actual pawn contact, without injected Touch or Use, opens the door")
	_check(actor.global_position.x < 6.8 and max_displacement < 0.06,
		"the full standing hull physically crosses the opened door without teleporting")
	_check(_door_ray(game, ray_start, ray_end).is_empty(),
		"the open door leaves no invisible collider in the closed entrance")
	_check(_door_ray(game, Vector3(6.7, 0.5, -21.9), Vector3(6.7, 0.5, -22.5)).get("collider") == door,
		"the rotated door remains solid at its new location")
	actor._brush_contacts.append(11)
	_check(actor.take_brush_contacts().has(11) and actor.take_brush_contacts().is_empty(),
		"movement contacts are consumed only once, including while an actor is frozen")
	actor._brush_contacts.append(11)
	actor.remove_child(driver)
	driver.queue_free()
	var reset_controller := BotCombatController.new()
	actor.add_child(reset_controller)
	reset_controller.configure(actor, actor.navigation_agent, actor.index)
	actor.combat_controller = reset_controller
	actor.reset_target(Vector3(7.6, 0.04, -22.08))
	_check(actor.take_brush_contacts().is_empty(), "reset clears stale movement contacts")
	game.imported_map.reset_model_runtime_transform(11)
	await physics_frame
	await physics_frame
	_check(_door_ray(game, ray_start, ray_end).get("collider") == door,
		"reset restores the closed collider, not just the visual transform")


func _check_hostage_door_crossing(game: Node) -> void:
	game.brush_runtime.reset_round()
	game._brush_touch_pairs.clear()
	var hostage: CS16Hostage = game.hostage_actors["hostage_153"]
	var contract: Dictionary = game.hostage_state.hostages[hostage.hostage_id].duplicate(true)
	contract.position_hu = Vector3(644, 4, -2204)
	hostage.apply_contract_state(contract)
	hostage.set_motion_velocity_hu(Vector3.ZERO)
	_check(game._brush_activator_id(hostage) == 153,
		"hostage door activators preserve their real BSP entity identity")
	await physics_frame
	await physics_frame
	var saw_contact := false
	var max_displacement := 0.0
	for tick in 260:
		await physics_frame
		# Exercise real Game touch dispatch and source brush time. Only intent
		# is staged here; the separate full-rescue gate owns from-spawn following.
		game._queue_brush_touches()
		game.entity_world.advance_tick()
		game.brush_runtime.advance_tick(false)
		var before := hostage.global_position
		var offset := Vector3(7.6, 0, -22.04) - before
		offset.y = 0.0
		hostage.move_source_tick(offset.normalized() * 200.0 if offset.length() > 0.04 else Vector3.ZERO)
		saw_contact = saw_contact or hostage._brush_contacts.has(11)
		max_displacement = maxf(max_displacement, before.distance_to(hostage.global_position))
	_check(saw_contact, "the source hostage hull really collides with the closed entrance")
	_check(game.brush_runtime.get_brush(11).state == BrushRuntime.STATE_OPEN,
		"hostage contact opens the door without a player or injected Touch/Use")
	_check(hostage.global_position.x > 7.4 and max_displacement < 0.20,
		"the hostage physically exits through the door without teleporting")
	hostage._brush_contacts.append(11)
	_check(hostage.take_brush_contacts().has(11) and hostage.take_brush_contacts().is_empty(),
		"hostage movement contacts are consumed once")
	hostage._brush_contacts.append(11)
	hostage.apply_contract_state(contract)
	_check(hostage.take_brush_contacts().is_empty(), "contract reposition clears stale hostage contacts")
	for status: String in ["alive", "rescued"]:
		game.brush_runtime.reset_round()
		game._brush_touch_pairs.clear()
		hostage.alive = status != "alive"
		hostage.rescued = status == "rescued"
		hostage.global_position = Vector3(6.96, 0.04, -22.04)
		hostage._brush_contacts.append(11)
		game._queue_brush_touches()
		game.entity_world.advance_tick()
		game.brush_runtime.advance_tick(false)
		_check(game.brush_runtime.get_brush(11).state == BrushRuntime.STATE_CLOSED,
			"dead or rescued hostages cannot activate doors")
