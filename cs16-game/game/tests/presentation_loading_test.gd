extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() != "Dummy":
		push_error("Loading fixture requires a rendered window and Dummy audio")
		quit(1)
		return
	create_timer(20.0).timeout.connect(func() -> void:
		push_error("Presentation failed to complete with ordinary rendering disabled")
		quit(1))
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	print("GAME_PRESENTATION_LOADING_PASS")
	game.queue_free()
	await process_frame
	quit(0)
