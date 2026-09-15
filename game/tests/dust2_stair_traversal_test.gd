extends SceneTree

const MapScript = preload("res://scripts/bsp_map.gd")
const KernelScript = preload("res://scripts/goldsrc_movement.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("DUST2 STAIR TRAVERSAL TEST: " + message)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var map := MapScript.new()
	world.add_child(map)
	_check(map.load_map("res://generated/de_dust2/map.json"), "real Dust2 BSP loads")
	if not failures.is_empty():
		quit(1)
		return

	# The eastern four-tread flight is authored as 16-HU rises and 32-HU
	# treads. Drive the actual imported triangle collision, not reconstructed
	# boxes, to catch BSP seams and conversion-scale regressions.
	var actor := CharacterBody3D.new()
	actor.collision_layer = 4
	actor.collision_mask = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.32, 0.72, 0.32)
	collider.shape = shape
	collider.position.y = 0.36
	actor.add_child(collider)
	world.add_child(actor)
	actor.global_position = Vector3(15.0, 0.0, -8.96)
	await physics_frame

	var kernel = KernelScript.new(actor)
	_check(kernel.categorize_ground(Vector3.ZERO), "actor begins grounded below the flight")
	var steps := 0
	for _tick in range(180):
		var result: Dictionary = kernel.move(Vector3(2.0, 0.0, 0.0), 0.01, true)
		if bool(result.used_step):
			steps += 1
	_check(steps == 4, "all four real Dust2 treads use exactly one step-up each")
	_check(absf(actor.global_position.y - 0.64) < 0.012, "actor reaches the 64-HU landing")
	_check(actor.global_position.x > 17.7, "actor crosses the flight without losing forward progress")
	_check(kernel.grounded, "actor remains grounded on the landing")

	if failures.is_empty():
		print("GAME_DUST2_STAIR_TRAVERSAL_TEST_PASS")
		quit(0)
	else:
		print("GAME_DUST2_STAIR_TRAVERSAL_TEST_FAIL: %s" % ", ".join(failures))
		quit(1)
