extends SceneTree

const EntityWorld := preload("res://scripts/cs16_entity_world.gd")
const BrushRuntime := preload("res://scripts/cs16_brush_runtime.gd")
const BspMapScript := preload("res://scripts/bsp_map.gd")
const ASSAULT_MAP := "res://generated/cs_assault/map.json"
const EPSILON := 0.0001

var failures: Array[String] = []
var observed: Array[Dictionary] = []


class FakeBrushMap:
	extends RefCounted

	var entities: Array = []
	var entity_models: Dictionary = {}
	var bounds: Dictionary = {}
	var initial_transforms: Dictionary = {}
	var transforms: Dictionary = {}

	func add_model(entity_id: int, model_index: int, model_bounds: AABB) -> void:
		entity_models[entity_id] = model_index
		bounds[model_index] = model_bounds
		initial_transforms[model_index] = Transform3D.IDENTITY
		transforms[model_index] = Transform3D.IDENTITY

	func model_index_for_entity(entity_id: int) -> int:
		return int(entity_models.get(entity_id, -1))

	func model_root(model_index: int) -> Variant:
		return self if bounds.has(model_index) else null

	func initial_transform_for_model(model_index: int) -> Transform3D:
		return initial_transforms.get(model_index, Transform3D.IDENTITY)

	func model_bounds_for_index(model_index: int) -> AABB:
		return bounds.get(model_index, AABB())

	func set_model_runtime_transform(model_index: int, value: Transform3D) -> bool:
		if not bounds.has(model_index):
			return false
		transforms[model_index] = value
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert_linear_door_timing_and_outputs()
	_assert_door_spawnflags_and_round_reset()
	_assert_button_defaults_and_toggle()
	_assert_rotating_door_angles()
	await _assert_assault_real_map()
	if failures.is_empty():
		print("DOOR_BUTTON_RUNTIME_TEST_PASS")
		quit(0)
	else:
		print("DOOR_BUTTON_RUNTIME_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("DOOR/BUTTON RUNTIME TEST: " + message)


func _check_close(actual: float, expected: float, message: String) -> void:
	_check(
		absf(actual - expected) <= EPSILON,
		"%s (actual=%.6f expected=%.6f)" % [message, actual, expected],
	)


func _capture(event: Dictionary) -> void:
	observed.append(event)


func _raw_entity(
	entity_index: int,
	classname: String,
	properties: Array = [],
) -> Dictionary:
	var ordered := [["classname", classname]]
	ordered.append_array(properties)
	return {
		"entity_index": entity_index,
		"classname": classname,
		"properties": ordered,
	}


func _make_runtime(fake_map: FakeBrushMap) -> Array:
	var world := EntityWorld.new()
	world.load_entities(fake_map.entities)
	var runtime := BrushRuntime.new()
	runtime.configure(fake_map, world)
	return [world, runtime]


func _assert_linear_door_timing_and_outputs() -> void:
	observed.clear()
	var fake := FakeBrushMap.new()
	fake.entities = [
		_raw_entity(
			0,
			"func_door",
			[
				["model", "*1"],
				["target", "door_done"],
				["angle", "0"],
				["speed", "100"],
				["wait", "0.02"],
				["lip", "8"],
				["movesnd", "2"],
				["stopsnd", "4"],
			],
		),
		_raw_entity(1, "info_target", [["targetname", "door_done"]]),
	]
	fake.add_model(0, 1, AABB(Vector3.ZERO, Vector3(1.0, 0.2, 0.2)))
	var pair := _make_runtime(fake)
	var world = pair[0]
	var runtime = pair[1]
	world.bind_handler(1, Callable(self, "_capture"))

	_check(
		world.queue_touch(0, 44, EntityWorld.TOUCH_ENTER),
		"ordinary untargeted doors accept touch activation",
	)
	runtime.advance_ticks(89)
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPENING,
		"linear door remains opening before its exact endpoint tick",
	)
	_check_close(
		(fake.transforms[1] as Transform3D).origin.x,
		0.89,
		"100 HU/s advances exactly one HU per 100 Hz tick",
	)
	runtime.advance_tick()
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPEN,
		"90-HU travel at 100 HU/s finishes on tick 90",
	)
	_check_close(
		(fake.transforms[1] as Transform3D).origin.x,
		0.90,
		"door travel is brush extent minus two engine hull units and eight-HU lip",
	)
	_check(
		observed.size() == 1 and int(observed[0].tick) == 90,
		"door output fires when the endpoint is reached, not when movement starts",
	)
	_check(
		runtime.events.size() == 2
		and runtime.events[0].event == "move"
		and runtime.events[1].event == "stop"
		and int(runtime.events[0].movesnd) == 2
		and int(runtime.events[1].stopsnd) == 4,
		"door emits stable move/stop events carrying later audio ordinals",
	)

	runtime.advance_tick()
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPEN,
		"wait keeps the door open through the first 10 ms quantum",
	)
	runtime.advance_tick()
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_CLOSING,
		"0.02-second wait starts return exactly two ticks after arrival",
	)
	runtime.advance_ticks(89)
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_CLOSED
		and observed.size() == 2,
		"door closes at source speed and emits its bottom endpoint output",
	)


func _assert_door_spawnflags_and_round_reset() -> void:
	var fake := FakeBrushMap.new()
	fake.entities = [
		_raw_entity(
			0,
			"func_door",
			[
				["model", "*1"],
				["angle", "0"],
				["speed", "100"],
				["wait", "4"],
				["lip", "0"],
				["spawnflags", "289"],
			],
		),
	]
	fake.add_model(0, 1, AABB(Vector3.ZERO, Vector3(0.5, 0.2, 0.2)))
	var pair := _make_runtime(fake)
	var world = pair[0]
	var runtime = pair[1]
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPEN,
		"START_OPEN spawns at the displaced endpoint",
	)
	_check_close(
		(fake.transforms[1] as Transform3D).origin.x,
		0.48,
		"START_OPEN applies the complete source travel at spawn",
	)
	_check(
		not world.queue_touch(0, 5, EntityWorld.TOUCH_ENTER)
		and world.queue_use(0, 5, EntityWorld.INPUT_PRESSED),
		"USE_ONLY removes touch capability and exposes impulse use",
	)
	runtime.advance_ticks(48)
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_CLOSED,
		"START_OPEN toggle door closes on its first use",
	)
	world.queue_use(0, 5, EntityWorld.INPUT_PRESSED)
	runtime.advance_ticks(12)
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPENING,
		"NO_AUTO_RETURN toggles an endpoint instead of scheduling itself",
	)
	runtime.reset_round()
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPEN
		and world.tick == 0,
		"round reset restores source start-open state and fixed-step clock",
	)
	_check_close(
		(fake.transforms[1] as Transform3D).origin.x,
		0.48,
		"round reset restores the shared visual/collision transform",
	)
	_check(
		world.queue_use(0, 5, EntityWorld.INPUT_PRESSED),
		"round snapshot retains brush capability bindings",
	)


func _assert_button_defaults_and_toggle() -> void:
	observed.clear()
	var fake := FakeBrushMap.new()
	fake.entities = [
		_raw_entity(
			0,
			"func_button",
			[["model", "*1"], ["target", "button_done"], ["angle", "0"]],
		),
		_raw_entity(1, "info_target", [["targetname", "button_done"]]),
		_raw_entity(
			2,
			"func_button",
			[
				["model", "*2"],
				["target", "button_done"],
				["spawnflags", "33"],
				["angle", "180"],
			],
		),
	]
	fake.add_model(0, 1, AABB(Vector3.ZERO, Vector3(0.5, 0.2, 0.2)))
	fake.add_model(2, 2, AABB(Vector3.ZERO, Vector3(0.5, 0.2, 0.2)))
	var pair := _make_runtime(fake)
	var world = pair[0]
	var runtime = pair[1]
	world.bind_handler(1, Callable(self, "_capture"))

	var moving: Dictionary = runtime.get_brush(0)
	_check(
		is_equal_approx(float(moving.speed), 40.0)
		and is_equal_approx(float(moving.wait_seconds), 1.0)
		and is_equal_approx(float(moving.lip), 4.0)
		and int(moving.wait_ticks) == 100,
		"button defaults are source speed 40, wait 1, and lip 4",
	)
	world.queue_use(0, 8, EntityWorld.INPUT_PRESSED)
	runtime.advance_ticks(109)
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPENING,
		"default 44-HU button travel has not rounded down at tick 109",
	)
	runtime.advance_tick()
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPEN
		and observed.size() == 1,
		"default button reaches its target and fires after exactly 110 ticks",
	)
	runtime.advance_ticks(99)
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPEN,
		"default button waits the full source second",
	)
	runtime.advance_tick()
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_CLOSING,
		"default wait expires on the exact 100th fixed tick",
	)

	var toggle_origin: Vector3 = (fake.transforms[2] as Transform3D).origin
	world.queue_use(2, 8, EntityWorld.INPUT_PRESSED)
	runtime.advance_tick()
	_check(
		runtime.get_brush(2).state == BrushRuntime.STATE_OPEN
		and (fake.transforms[2] as Transform3D).origin.is_equal_approx(toggle_origin),
		"DONT_MOVE toggle button activates immediately without transform drift",
	)
	world.queue_use(2, 8, EntityWorld.INPUT_PRESSED)
	runtime.advance_tick()
	_check(
		runtime.get_brush(2).state == BrushRuntime.STATE_CLOSED
		and observed.size() == 3,
		"toggle button fires once at each pushed/released endpoint",
	)


func _assert_rotating_door_angles() -> void:
	var fake := FakeBrushMap.new()
	fake.entities = [
		_raw_entity(
			0,
			"func_door_rotating",
			[
				["model", "*1"],
				["angles", "0 0 0"],
				["distance", "90"],
				["speed", "100"],
				["wait", "-1"],
			],
		),
	]
	fake.add_model(
		0,
		1,
		AABB(Vector3(-0.04, -0.48, -0.04), Vector3(0.08, 0.96, 0.64)),
	)
	var pair := _make_runtime(fake)
	var world = pair[0]
	var runtime = pair[1]
	world.queue_touch(0, 12, EntityWorld.TOUCH_ENTER)
	runtime.advance_ticks(89)
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPENING,
		"90-degree rotating door at 100 degrees/s remains moving through tick 89",
	)
	runtime.advance_tick()
	var opened: Transform3D = fake.transforms[1]
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPEN,
		"rotating door reaches its exact authored angle on tick 90",
	)
	_check_close(
		rad_to_deg(opened.basis.get_rotation_quaternion().get_angle()),
		90.0,
		"default rotating-door axis applies the authored 90-degree yaw",
	)
	runtime.advance_ticks(500)
	_check(
		runtime.get_brush(0).state == BrushRuntime.STATE_OPEN,
		"wait -1 suppresses automatic rotating-door return",
	)

	var long_fake := FakeBrushMap.new()
	long_fake.entities = [
		_raw_entity(
			0,
			"func_door_rotating",
			[
				["model", "*1"],
				["distance", "270"],
				["speed", "90"],
				["wait", "-1"],
				["spawnflags", "16"],
			],
		),
	]
	long_fake.add_model(0, 1, AABB(Vector3.ZERO, Vector3.ONE))
	var long_pair := _make_runtime(long_fake)
	var long_world = long_pair[0]
	var long_runtime = long_pair[1]
	long_world.queue_touch(0, 13, EntityWorld.TOUCH_ENTER)
	long_runtime.advance_ticks(299)
	_check(
		long_runtime.get_brush(0).state == BrushRuntime.STATE_OPENING,
		"rotating movement preserves authored arcs above 180 degrees",
	)
	long_runtime.advance_tick()
	_check(
		long_runtime.get_brush(0).state == BrushRuntime.STATE_OPEN
		and (long_fake.transforms[1] as Transform3D).basis.is_equal_approx(
			Basis(Vector3.UP, deg_to_rad(270.0))
		),
		"270-degree one-way door takes three seconds and reaches the exact basis",
	)


func _assert_assault_real_map() -> void:
	var assault := BspMapScript.new()
	assault.name = "AssaultDoorButtonRuntimeTest"
	root.add_child(assault)
	_check(assault.load_map(ASSAULT_MAP), "converted stock cs_assault loads")
	if assault.entities.is_empty():
		assault.queue_free()
		await process_frame
		return
	var world := EntityWorld.new()
	world.load_entities(assault.entities)
	var runtime := BrushRuntime.new()
	_check(
		runtime.configure(assault, world) == 9,
		"Assault binds one rotating door, two linear doors, and six buttons",
	)

	var rotating: Dictionary = runtime.get_brush(11)
	_check(
		rotating.model_index == 11
		and is_equal_approx(float(rotating.distance), 90.0)
		and is_equal_approx(float(rotating.speed), 100.0)
		and int(rotating.wait_ticks) == 400,
		"Assault rotating entrance preserves model, distance, speed, and wait keys",
	)
	var rotating_body := assault.model_collision_body(11)
	var rotating_root := assault.model_root_for_entity(11)
	_check(
		rotating_body is AnimatableBody3D
		and rotating_body.get_parent() == rotating_root,
		"Assault rotating visual and collision remain under one mover root",
	)
	world.queue_touch(11, 200, EntityWorld.TOUCH_ENTER)
	runtime.advance_ticks(90)
	_check(
		runtime.get_brush(11).state == BrushRuntime.STATE_OPEN,
		"Assault rotating entrance completes its source 90-degree sweep in 0.9 seconds",
	)
	_check_close(
		rad_to_deg(rotating_root.basis.get_rotation_quaternion().get_angle()),
		90.0,
		"Assault rotating entrance applies the authored angle to its BSP root",
	)
	_check(
		rotating_body.transform.is_equal_approx(Transform3D.IDENTITY),
		"Assault collision remains locally registered while its parent rotates",
	)

	var left_start := assault.initial_transform_for_model(71).origin
	var right_start := assault.initial_transform_for_model(72).origin
	world.queue_touch(124, 201, EntityWorld.TOUCH_ENTER)
	world.queue_touch(125, 201, EntityWorld.TOUCH_ENTER)
	runtime.advance_ticks(62)
	_check(
		runtime.get_brush(124).state == BrushRuntime.STATE_OPEN
		and runtime.get_brush(125).state == BrushRuntime.STATE_OPEN,
		"Assault paired linear doors finish together after their exact 62-HU travel",
	)
	_check_close(
		assault.model_root(71).position.z,
		left_start.z + 0.62,
		"Assault model 71 opens in its authored 270-degree direction",
	)
	_check_close(
		assault.model_root(72).position.z,
		right_start.z - 0.62,
		"Assault model 72 opens in its authored 90-degree direction",
	)
	_check(
		assault.model_collision_body(71).get_parent() == assault.model_root(71)
		and assault.model_collision_body(72).get_parent() == assault.model_root(72),
		"paired Assault door collision follows the exact visual transforms",
	)

	var button_start := assault.initial_transform_for_model(42)
	world.queue_use(51, 202, EntityWorld.INPUT_PRESSED)
	runtime.advance_tick()
	_check(
		runtime.get_brush(51).state == BrushRuntime.STATE_OPEN
		and assault.model_root(42).transform.is_equal_approx(button_start),
		"Assault camera button spawnflags 33 produce a non-moving pushed toggle",
	)
	var cam_uses := 0
	for event: Dictionary in world.trace:
		if event.event == "use" and int(event.entity_id) == 110:
			cam_uses += 1
	_check(cam_uses == 1, "Assault camera button fires its real cam4 target at the endpoint")
	world.queue_use(51, 202, EntityWorld.INPUT_PRESSED)
	runtime.advance_tick()
	_check(
		runtime.get_brush(51).state == BrushRuntime.STATE_CLOSED,
		"Assault toggle camera button releases on its next use",
	)

	runtime.reset_round()
	_check(
		runtime.get_brush(11).state == BrushRuntime.STATE_CLOSED
		and runtime.get_brush(124).state == BrushRuntime.STATE_CLOSED
		and runtime.get_brush(125).state == BrushRuntime.STATE_CLOSED
		and assault.model_root(11).transform.is_equal_approx(
			assault.initial_transform_for_model(11)
		),
		"Assault round reset atomically restores every brush mover",
	)
	assault.queue_free()
	await process_frame
