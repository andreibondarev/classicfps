extends SceneTree

const GameScript := preload("res://scripts/game.gd")
const BrushRuntime := preload("res://scripts/cs16_brush_runtime.gd")
const EntityWorld := preload("res://scripts/cs16_entity_world.gd")

var failures: Array[String] = []


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

	if failures.is_empty():
		print("GAME_BRUSH_INTEGRATION_TEST_PASS")
		current_scene = null
		game.queue_free()
		await process_frame
		quit(0)
	else:
		print("GAME_BRUSH_INTEGRATION_TEST_FAIL (%d)" % failures.size())
		current_scene = null
		game.queue_free()
		await process_frame
		quit(1)
