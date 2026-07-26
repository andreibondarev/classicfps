extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _capture(path: String) -> bool:
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save preview to %s: %s" % [path, error_string(error)])
		return false
	return true


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game
	for frame in range(8):
		await process_frame

	var output_root := ProjectSettings.globalize_path("res://artifacts")
	DirAccess.make_dir_recursive_absolute(output_root)
	var menu_ok := _capture(output_root.path_join("protocol47-deploy.png"))

	game.start_match()
	for frame in range(8):
		await process_frame
	var game_ok := _capture(output_root.path_join("protocol47-gameplay.png"))

	game.player.global_position = Vector3(0, 0.08, 13)
	game.player.face_toward(Vector3(0, 0.08, 0))
	if is_instance_valid(game.imported_map):
		game.imported_map.visible = false
	for child in game.get_children():
		if child.name.to_lower().begins_with("bombsite"):
			child.visible = false
	var rows := [game.allied_bots, game.targets]
	for row_index in range(rows.size()):
		var row: Array[TargetActor] = rows[row_index]
		var spacing := 2.4
		for bot_index in range(row.size()):
			var bot := row[bot_index]
			bot.active = false
			bot.global_position = Vector3(
				(float(bot_index) - (float(row.size()) - 1.0) * 0.5) * spacing,
				0.08,
				5.0 - row_index * 4.0,
			)
			bot.look_at(game.player.global_position, Vector3.UP)
	for frame in range(8):
		await process_frame
	var models_ok := _capture(output_root.path_join("protocol47-player-models.png"))

	for bot in game._all_bots():
		bot.character_model.visible = false
	var closeup: TargetActor = game.allied_bots[0]
	game.player.global_position = Vector3(0, 0.08, 11)
	game.player.face_toward(Vector3(0, 0.08, 8))
	closeup.character_model.visible = true
	closeup.global_position = Vector3(0, 0.08, 8)
	closeup.look_at(game.player.global_position, Vector3.UP)
	game.hud.visible = false
	game.player.viewmodel.visible = false
	for frame in range(4):
		await process_frame
	var closeup_ok := _capture(output_root.path_join("protocol47-player-model-closeup.png"))

	if menu_ok and game_ok and models_ok and closeup_ok:
		print("GAME_PREVIEW_CAPTURE_PASS")
		quit(0)
	else:
		quit(1)
