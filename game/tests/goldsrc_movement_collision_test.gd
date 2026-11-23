extends SceneTree

const KernelScript = preload("res://scripts/goldsrc_movement.gd")
const HULL_SIZE := Vector3(0.32, 0.72, 0.32)

var failures: Array[String] = []
var world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("GOLDSRC COLLISION TEST: " + message)


func _near(actual: float, expected: float, message: String, epsilon := 0.002) -> void:
	_check(
		absf(actual - expected) <= epsilon,
		"%s (expected %.5f, got %.5f)" % [message, expected, actual],
	)


func _make_static(
	body_name: String,
	position: Vector3,
	size: Vector3,
	rotation := Vector3.ZERO,
) -> StaticBody3D:
	var obstacle := StaticBody3D.new()
	obstacle.name = body_name
	obstacle.position = position
	obstacle.rotation = rotation
	obstacle.collision_layer = 1
	obstacle.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	obstacle.add_child(collider)
	world.add_child(obstacle)
	return obstacle


func _make_actor(actor_name: String, position: Vector3, size := HULL_SIZE) -> CharacterBody3D:
	var actor := CharacterBody3D.new()
	actor.name = actor_name
	actor.position = position
	actor.collision_layer = 4
	actor.collision_mask = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position.y = size.y * 0.5
	actor.add_child(collider)
	world.add_child(actor)
	return actor


func _run() -> void:
	world = Node3D.new()
	world.name = "GoldSrcMovementFixtures"
	root.add_child(world)
	current_scene = world

	# Shared ground plus isolated fixtures.
	_make_static("Ground", Vector3(0.0, -0.5, 0.0), Vector3(50.0, 1.0, 30.0))
	_make_static("Wall", Vector3(-3.0, 1.0, 0.0), Vector3(0.10, 2.0, 3.0))
	_make_static("CornerX", Vector3(1.0, 1.0, 5.0), Vector3(0.10, 2.0, 3.0))
	_make_static("CornerZ", Vector3(0.0, 1.0, 6.0), Vector3(3.0, 2.0, 0.10))
	_make_static("Step18", Vector3(5.70, 0.09, 0.0), Vector3(0.50, 0.18, 2.0))
	_make_static("Step19", Vector3(7.70, 0.095, 0.0), Vector3(0.50, 0.19, 2.0))
	# Dust2's ordinary stair brushes rise 16 HU per 32-HU tread. Exercise a
	# consecutive flight, since a single isolated step misses seam regressions.
	for stair_index in range(4):
		var top := float(stair_index + 1) * 0.16
		_make_static(
			"Dust2Step%02d" % (stair_index + 1),
			Vector3(-10.3 + float(stair_index) * 0.4, top * 0.5, 10.0),
			Vector3(0.4, top, 2.0),
		)
	_make_static(
		"Slope",
		Vector3(10.9, 0.12, 0.0),
		Vector3(2.0, 0.20, 2.0),
		Vector3(0.0, 0.0, deg_to_rad(12.0)),
	)
	_make_static("Ceiling", Vector3(15.0, 0.85, 0.0), Vector3(2.0, 0.10, 2.0))
	_make_static("DuckCeiling", Vector3(18.0, 0.65, 0.0), Vector3(2.0, 0.10, 2.0))
	_make_static("EdgePlatform", Vector3(21.0, 4.9, 0.0), Vector3(1.0, 0.20, 2.0))

	var wall_actor := _make_actor("WallActor", Vector3(-4.0, 0.0, 0.0))
	var corner_actor := _make_actor("CornerActor", Vector3(0.0, 0.0, 5.0))
	var stair_actor := _make_actor("StairActor", Vector3(5.0, 0.0, 0.0))
	var tall_stair_actor := _make_actor("TallStairActor", Vector3(7.0, 0.0, 0.0))
	var dust2_stair_actor := _make_actor("Dust2StairActor", Vector3(-11.0, 0.0, 10.0))
	var slope_actor := _make_actor("SlopeActor", Vector3(9.8, 0.0, 0.0))
	var ceiling_actor := _make_actor("CeilingActor", Vector3(15.0, 0.0, 0.0))
	var duck_actor := _make_actor("DuckActor", Vector3(18.0, 0.0, 0.0), Vector3(0.32, 0.50, 0.32))
	var edge_actor := _make_actor("EdgeActor", Vector3(21.40, 5.0, 0.0))
	await physics_frame

	# PM_ClipVelocity removes only the component entering a plane.
	var clipped_wall: Vector3 = KernelScript.clip_velocity(Vector3(2.0, 0.0, 1.0), Vector3.LEFT)
	_near(clipped_wall.x, 0.0, "wall plane removes normal velocity")
	_near(clipped_wall.z, 1.0, "wall plane preserves tangential velocity")
	var slope_normal := Vector3(-0.5, 0.8660254, 0.0)
	var clipped_slope: Vector3 = KernelScript.clip_velocity(Vector3(1.0, -1.0, 0.0), slope_normal)
	_check(clipped_slope.y > -1.0, "slope plane redirects velocity along its face")

	var wall_kernel = KernelScript.new(wall_actor)
	_check(wall_kernel.categorize_ground(Vector3.ZERO), "wall fixture actor categorizes ground")
	var wall_result: Dictionary = wall_kernel.move(Vector3(4.0, 0.0, 1.0), 0.5, true)
	_check(wall_actor.position.x <= -3.209, "swept hull cannot tunnel through a wall")
	_check(wall_actor.position.z > 0.20, "fly move slides along a wall")
	_near((wall_result.velocity as Vector3).x, 0.0, "wall collision clips x velocity", 0.01)
	# Regression: a hull already flush against the wall must keep sliding on
	# later ticks while the player still pushes into it, never welding stuck.
	var flush_z := wall_actor.position.z
	for _tick in range(10):
		wall_kernel.move(Vector3(4.0, 0.0, 1.0), 0.01, true)
	_check(
		wall_actor.position.z > flush_z + 0.09,
		"flush wall contact still slides tangentially on repeated ticks",
	)

	var corner_kernel = KernelScript.new(corner_actor)
	_check(corner_kernel.categorize_ground(Vector3.ZERO), "corner fixture actor categorizes ground")
	var corner_result: Dictionary = corner_kernel.move(Vector3(3.0, 0.0, 3.0), 0.5, true)
	_check(corner_actor.position.x <= 0.79 and corner_actor.position.z <= 5.79, "corner blocks both axes")
	_check(
		Vector2(corner_result.velocity.x, corner_result.velocity.z).length() < 0.02,
		"two-plane corner resolution stops motion into the crease",
	)

	var stair_kernel = KernelScript.new(stair_actor)
	_check(stair_kernel.categorize_ground(Vector3.ZERO), "stair fixture actor categorizes ground")
	var stair_result: Dictionary = stair_kernel.move(Vector3(2.0, 0.0, 0.0), 0.5, true)
	_check(bool(stair_result.used_step), "PM_WalkMove selects the 18-HU step trial")
	_near(stair_actor.position.y, 0.18, "actor lands on an exact 18-HU stair", 0.012)
	_check(stair_actor.position.x > 5.50, "step trial travels farther than direct collision")
	_check(bool(stair_result.grounded), "step landing retains the ground trace")

	var tall_stair_kernel = KernelScript.new(tall_stair_actor)
	_check(tall_stair_kernel.categorize_ground(Vector3.ZERO), "tall-stair actor categorizes ground")
	var tall_stair_result: Dictionary = tall_stair_kernel.move(
		Vector3(2.0, 0.0, 0.0),
		0.5,
		true,
	)
	_check(
		tall_stair_actor.position.y < 0.02,
		"19-HU obstacle cannot be climbed by the 18-HU step trial",
	)
	_check(
		not bool(tall_stair_result.used_step),
		"direct collision wins when the raised path is blocked",
	)

	var dust2_stair_kernel = KernelScript.new(dust2_stair_actor)
	_check(dust2_stair_kernel.categorize_ground(Vector3.ZERO), "Dust2 stair-flight actor starts grounded")
	var dust2_step_count := 0
	for _tick in range(130):
		var dust2_result: Dictionary = dust2_stair_kernel.move(Vector3(2.0, 0.0, 0.0), 0.01, true)
		if bool(dust2_result.used_step):
			dust2_step_count += 1
	_check(dust2_step_count >= 4, "consecutive 16-HU Dust2 treads all select the step path")
	_near(dust2_stair_actor.position.y, 0.64, "actor reaches the top of a four-tread Dust2 stair flight", 0.012)
	_check(dust2_stair_actor.position.x > -8.7, "stair flight preserves forward progress without snagging")

	var slope_kernel = KernelScript.new(slope_actor)
	_check(slope_kernel.categorize_ground(Vector3.ZERO), "slope fixture actor starts grounded")
	var slope_result: Dictionary = slope_kernel.move(Vector3(2.0, 0.0, 0.0), 0.5, true)
	_check(slope_actor.position.y > 0.01, "walk solver climbs a walkable slope")
	_check(
		(slope_result.ground_normal as Vector3).y >= KernelScript.FLOOR_NORMAL_MINIMUM,
		"slope remains categorized as walkable ground",
	)

	var ceiling_kernel = KernelScript.new(ceiling_actor)
	ceiling_kernel.categorize_ground(Vector3.ZERO)
	var ceiling_result: Dictionary = ceiling_kernel.move(Vector3(0.0, 3.0, 0.0), 0.2, false)
	print("COLLISION_CEILING_PROFILE ", JSON.stringify({
		"backend": world.get_world_3d().direct_space_state.get_class(),
		"feet_y": ceiling_actor.position.y,
		"source_endpoint_y": 0.85 - 0.10 * 0.5 - HULL_SIZE.y - 0.03125 * 0.01,
		"velocity_y": (ceiling_result.velocity as Vector3).y}))
	# Analytic axis-aligned clip hull: ceiling bottom minus the standing hull
	# height, backed off by ReHLDS PM_RecursiveHullCheck's 0.03125 HU epsilon.
	# A one-sided arbitrary maximum accepted stopping far short of the source
	# endpoint. Check both sides within the canonical 1/64 HU position quantum.
	# https://github.com/rehlds/ReHLDS/blob/0124d56c3d888d922eb045775f71c6682ad1226f/rehlds/engine/pmovetst.cpp#L625
	var source_ceiling_endpoint := 0.85 - 0.10 * 0.5 - HULL_SIZE.y - 0.03125 * 0.01
	_near(ceiling_actor.position.y, source_ceiling_endpoint,
		"ceiling sweep endpoint matches the source clip-hull plane", 0.01 / 64.0)
	_check((ceiling_result.velocity as Vector3).y <= 0.001, "ceiling plane clips upward velocity")

	var duck_kernel = KernelScript.new(duck_actor)
	_check(
		not duck_kernel.can_fit_box(HULL_SIZE),
		"standing hull is rejected below a low ceiling",
	)
	_check(
		duck_kernel.can_fit_box(Vector3(0.32, 0.36, 0.32)),
		"duck hull remains valid below the same ceiling",
	)

	var edge_kernel = KernelScript.new(edge_actor)
	_check(edge_kernel.categorize_ground(Vector3.ZERO), "edge fixture actor stands on its platform")
	_near(
		edge_kernel.edge_friction_multiplier(Vector3.RIGHT),
		KernelScript.EDGE_FRICTION,
		"edge trace applies sv_edgefriction when ground ends ahead",
	)

	current_scene = null
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_GOLDSRC_COLLISION_TEST_PASS")
		quit(0)
	else:
		print("GAME_GOLDSRC_COLLISION_TEST_FAIL: %s" % ", ".join(failures))
		quit(1)
