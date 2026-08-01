extends SceneTree

const GameScript := preload("res://scripts/game.gd")
const BreakableProxy := preload("res://scripts/cs16_breakable_collision_proxy.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BREAKABLE GAME INTEGRATION TEST: " + message)


func _run() -> void:
	var game := GameScript.new()
	game.map_name = "cs_assault"
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame

	_check(
		game.breakable_runtime != null
		and game.breakable_runtime.breakable_count() == 12,
		"production Game binds all twelve stock Assault func_breakables",
	)
	var computer := game.breakable_runtime.get_breakable(79)
	_check(
		int(computer.model_index) == 54
		and int(computer.material) == 6
		and is_equal_approx(float(computer.health), 550.0)
		and int(computer.explosion_magnitude) == 40,
		"production runtime preserves the authored 550-health explosive computer",
	)
	var body := game.imported_map.model_collision_body(54)
	_check(
		body is BreakableProxy
		and int(body.get_meta("cs16_breakable_entity_id", -1)) == 79,
		"the real BSP collision body exposes the player/bot hitscan damage adapter",
	)
	body.call(
		"receive_bullet_damage",
		550,
		0,
		"ak47",
		game._model_world_aabb(54).get_center(),
		game.player,
	)
	_check(
		not bool(game.breakable_runtime.get_breakable(79).alive)
		and not game.imported_map.model_runtime_active(54),
		"fatal production hitscan hides and desolidifies the exact BSP computer",
	)
	var fallback_shards := game.breakable_debris.active_shard_count()
	_check(
		is_instance_valid(game.breakable_debris)
		and fallback_shards >= 8
		and fallback_shards <= 32,
		(
			"the source client shard-count fallback presents a size-derived"
			+ " authentic MDL debris burst (got %d)" % fallback_shards
		),
	)
	var break_audio := false
	for event: Dictionary in game.audio_router.trace():
		if (
			str(event.get("kind", "")) == "start"
			and str(event.get("event_name", "")).begins_with(
				"breakable.break.computer"
			)
		):
			break_audio = true
	_check(break_audio, "the authored computer break sound reaches live spatial audio")

	game.start_match()
	var tick_before := int(game.entity_world.tick)
	game._physics_process(0.01)
	_check(
		int(game.entity_world.tick) == tick_before + 1,
		"doors, breakables, and entity I/O share one production 100 Hz clock",
	)
	game._consume_round_events([{"type": "round_start", "round": 2}])
	_check(
		bool(game.breakable_runtime.get_breakable(79).alive)
		and game.imported_map.model_runtime_active(54)
		and game.breakable_debris.active_shard_count() == 0,
		"round start atomically restores BSP visibility/collision/health and clears debris",
	)

	if failures.is_empty():
		print("GAME_BREAKABLE_INTEGRATION_TEST_PASS")
		current_scene = null
		game.queue_free()
		await process_frame
		quit(0)
	else:
		print("GAME_BREAKABLE_INTEGRATION_TEST_FAIL (%d)" % failures.size())
		current_scene = null
		game.queue_free()
		await process_frame
		quit(1)
