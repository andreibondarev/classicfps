extends SceneTree

const Drop = preload("res://scripts/cs16_dropped_weapon.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _box(size: Vector3, origin: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = origin
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _run() -> void:
	_check(AudioServer.get_driver_name() == "Dummy", "drop fixture must be muted")
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	stage.add_child(_box(Vector3(20, 0.2, 20), Vector3(0, -0.1, 0)))
	stage.add_child(_box(Vector3(0.05, 4, 4), Vector3(3, 2, 0)))
	await physics_frame
	await physics_frame
	var gun := Drop.new()
	var landings: Array[Vector3] = []
	gun.landed.connect(func(drop_position: Vector3) -> void: landings.append(drop_position))
	gun.setup("ak47", 7, 29)
	gun.position = Vector3(0, 0.45, 0)
	stage.add_child(gun)
	gun.start_toss(Vector3.RIGHT)
	gun.set_physics_process(false) # Explicit fixed ticks, real map-space queries.
	var origin := gun.position
	gun._advance_toss(0.01)
	_check(gun.position.x > origin.x and gun.position.y > origin.y and gun.tossing,
		"drop visibly travels forward/up instead of snapping to the floor")
	for tick in 150:
		if gun.tossing:
			gun._advance_toss(0.01)
	_check(not gun.tossing and absf(gun.position.y) < 0.02 and gun.position.x > 1.0,
		"toss falls and settles on the floor")
	_check(landings.size() == 1 and landings[0].is_equal_approx(gun.global_position),
		"a settled toss publishes exactly one landing cue position")
	_check(gun.clip_ammo == 7 and gun.reserve_ammo == 29, "presentation never changes ammunition")
	gun.position = Vector3(2.5, 1, 0)
	gun.start_toss(Vector3.RIGHT)
	gun.set_physics_process(false)
	gun.toss_velocity = Vector3(100, 0, 0)
	gun._advance_toss(0.01)
	_check(gun.position.x < 2.975 and gun.tossing and landings.size() == 1,
		"thin wall stops fast flight without pretending to be a floor or landing")
	for tick in 150:
		if gun.tossing:
			gun._advance_toss(0.01)
	_check(not gun.tossing and absf(gun.position.y) < 0.02 and gun.position.x < 2.975,
		"wall contact slides down and lands on the near side")
	_check(landings.size() == 2, "each actual floor landing emits one drop cue")
	stage.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_WEAPON_DROP_MOTION_PASS")
	quit(0 if failures.is_empty() else 1)
