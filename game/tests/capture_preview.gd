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

	if menu_ok and game_ok:
		print("GAME_PREVIEW_CAPTURE_PASS")
		quit(0)
	else:
		quit(1)

