extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BOT MOBILITY TEST: " + message)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return

	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.start_match()
	game._begin_live()

	var starting_positions: Dictionary = {}
	for bot in game._all_bots():
		starting_positions[bot] = bot.global_position

	for frame in range(360):
		await physics_frame

	var stalled_bots: Array[String] = []
	for bot in game._all_bots():
		var distance: float = bot.global_position.distance_to(starting_positions[bot])
		if distance < 1.0:
			stalled_bots.append("%s (%.2f world units)" % [bot.name, distance])
	_check(
		stalled_bots.is_empty(),
		"every bot leaves its first navmesh waypoint: %s" % ", ".join(stalled_bots),
	)

	if failures.is_empty():
		print("GAME_BOT_MOBILITY_TEST_PASS")
		current_scene = null
		game.queue_free()
		await process_frame
		quit(0)
	else:
		print("GAME_BOT_MOBILITY_TEST_FAIL: %s" % ", ".join(failures))
		current_scene = null
		game.queue_free()
		await process_frame
		quit(1)
