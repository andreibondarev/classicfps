extends SceneTree

var failures: Array[String] = []

class CorridorDriver extends BotCombatController:
	var destination := Vector3(4.68, 0.04, -4.24)
	func _objective_context() -> Dictionary:
		return {"target": destination, "action": "use_hostage", "state": "corridor_probe", "stop_radius": 0.05}
	func blind(_actor: Combatant, _tick: int) -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var game := preload("res://scripts/game.gd").new()
	game.map_name = "cs_assault"
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.start_match()
	game._begin_live()
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
		bot.collision_layer = 0
	var actor: TargetActor = game._all_bots()[4]
	actor.collision_mask = 1
	var old := actor.combat_controller
	actor.remove_child(old)
	old.queue_free()
	var driver := CorridorDriver.new()
	actor.add_child(driver)
	driver.configure(actor, actor.navigation_agent, actor.index)
	driver.set_perception_predicates(Callable(driver, "blind"))
	actor.combat_controller = driver
	_check(is_zero_approx(actor.wall_min_slide_angle), "production bot retains low-angle wall sliding")
	var production := await _cross(actor, driver, game)
	_check(Vector3(production.position).distance_to(driver.destination) < 0.06,
		"normal bot routing and unwedge physically clear Assault's narrow func_wall corridor")
	_check(int(production.tangent_contacts) > 0, "the run exercises real low-angle tangential wall movement")
	_check(float(production.max_displacement) < 0.06, "corridor traversal never teleports")
	# Same map, hull, speed, route, approach and duration. Restoring only the
	# engine's default angle guard must reproduce the original stall.
	actor.wall_min_slide_angle = deg_to_rad(15.0)
	var legacy := await _cross(actor, driver, game)
	_check(Vector3(legacy.position).x > 4.95, "legacy angle-guard negative control reproduces the blocked corridor")
	actor.wall_min_slide_angle = 0.0
	print("BOT_WALL_SLIDE ", JSON.stringify({"production": production, "legacy_angle_guard": legacy}))
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	for failure: String in failures:
		push_error(failure)
	print("GAME_BOT_WALL_SLIDE_PASS" if failures.is_empty() else "GAME_BOT_WALL_SLIDE_FAIL")
	quit(0 if failures.is_empty() else 1)


func _cross(actor: TargetActor, driver: CorridorDriver, game: Node) -> Dictionary:
	actor.reset_target(Vector3(5.6, 0.04, -4.22))
	var max_displacement := 0.0
	var tangent_contacts := 0
	for tick in 400:
		await physics_frame
		game._physics_process(0.01)
		var before := actor.global_position
		actor._physics_process(0.01)
		max_displacement = maxf(max_displacement, before.distance_to(actor.global_position))
		if actor.is_on_wall() and absf(actor.velocity.z) > 0.001 and absf(actor.velocity.z) < 0.10:
			tangent_contacts += 1
	return {"position": actor.global_position, "max_displacement": max_displacement, "tangent_contacts": tangent_contacts}
