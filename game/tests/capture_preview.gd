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


func _capture_baked_map(path: String) -> bool:
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save baked-map preview to %s: %s" % [path, error_string(error)])
		return false
	var clipped_pixels := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.r > 250.0 / 255.0 and color.g > 250.0 / 255.0 and color.b > 250.0 / 255.0:
				clipped_pixels += 1
	var clipped_fraction := float(clipped_pixels) / float(image.get_width() * image.get_height())
	print("BAKED_MAP_CLIPPED_FRACTION %.6f" % clipped_fraction)
	if clipped_fraction >= 0.005:
		push_error("Baked map clips %.3f%% of capture pixels" % (clipped_fraction * 100.0))
		return false
	return true


func _capture_classic_viewmodel(path: String) -> bool:
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save viewmodel preview to %s: %s" % [path, error_string(error)])
		return false
	var background := image.get_pixel(0, 0)
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			var difference := maxf(
				maxf(absf(color.r - background.r), absf(color.g - background.g)),
				absf(color.b - background.b),
			)
			if difference <= 0.05:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		push_error("Viewmodel capture contains no foreground silhouette")
		return false
	var width := float(image.get_width())
	var height := float(image.get_height())
	var bounds := Rect2(
		float(min_x) / width,
		float(min_y) / height,
		float(max_x - min_x + 1) / width,
		float(max_y - min_y + 1) / height,
	)
	print("CLASSIC_VIEWMODEL_BOUNDS %s" % bounds)
	var framing_passes := (
		bounds.position.x >= 0.45
		and bounds.position.x <= 0.50
		and bounds.end.x >= 0.78
		and bounds.end.x <= 0.82
		and bounds.position.y >= 0.75
		and bounds.position.y <= 0.80
		and bounds.end.y >= 0.98
	)
	if not framing_passes:
		push_error("AK-47 falls outside the classic camera-space framing gate: %s" % bounds)
	return framing_passes


func _capture_resolution(path: String, expected_size: Vector2i) -> bool:
	var image := root.get_viewport().get_texture().get_image()
	if image.get_size() != expected_size:
		push_error("HUD capture is %s, expected %s" % [image.get_size(), expected_size])
		return false
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save resolution preview to %s: %s" % [path, error_string(error)])
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
	var game_ok := _capture_baked_map(output_root.path_join("protocol47-gameplay.png"))
	var hud_ok := _capture(output_root.path_join("protocol47-hud-parity.png"))

	var allied_center := Vector3.ZERO
	for ally in game.allied_bots:
		allied_center += ally.global_position
		ally.character_model.play_action("shoot")
		ally.character_model._process(0.02)
	allied_center /= game.allied_bots.size()
	game.player.face_toward(allied_center)
	game.player._pitch = -0.28
	game.player.camera.rotation.x = game.player._pitch
	for frame in range(2):
		await process_frame
	var spawn_pose_ok := _capture(output_root.path_join("protocol47-bot-spawn-pose.png"))
	for ally in game.allied_bots:
		ally.character_model.reset_animation()

	game._begin_live()
	for frame in range(360):
		await physics_frame
	var mobility_ok := _capture(output_root.path_join("protocol47-bot-mobility.png"))

	game.player.global_position = Vector3(0, 0.08, 4.2)
	game.player.face_toward(Vector3(0, 0.08, 0.5))
	if is_instance_valid(game.imported_map):
		game.imported_map.visible = false
	for child in game.get_children():
		if child.name.to_lower().begins_with("bombsite"):
			child.visible = false
	var rows := [game.allied_bots, game.targets]
	for row_index in range(rows.size()):
		var row: Array[TargetActor] = rows[row_index]
		var spacing := 0.62
		for bot_index in range(row.size()):
			var bot := row[bot_index]
			bot.active = false
			bot.global_position = Vector3(
				(float(bot_index) - (float(row.size()) - 1.0) * 0.5) * spacing,
				0.08,
				1.0 - row_index * 0.9,
			)
			bot.look_at(game.player.global_position, Vector3.UP)
	for frame in range(8):
		await process_frame
	var models_ok := _capture(output_root.path_join("protocol47-player-models.png"))

	for bot in game._all_bots():
		bot.character_model.visible = false
	var closeup: TargetActor = game.allied_bots[0]
	game.player.global_position = Vector3(0, 0.08, 9.1)
	game.player.face_toward(Vector3(0, 0.08, 8))
	game.player._pitch = 0.05
	game.player._sync_view_angles()
	closeup.character_model.visible = true
	closeup.global_position = Vector3(0, 0.08, 8)
	closeup.look_at(game.player.global_position, Vector3.UP)
	game.hud.visible = false
	game.player.viewmodel.visible = false
	for frame in range(4):
		await process_frame
	var closeup_ok := _capture(output_root.path_join("protocol47-player-model-closeup.png"))

	closeup.character_model.visible = false
	game.player.viewmodel.visible = true
	game.player._pitch = 0.0
	game.player._sync_view_angles()
	for frame in range(4):
		await process_frame
	var viewmodel_ok := _capture_classic_viewmodel(
		output_root.path_join("protocol47-viewmodel-ak.png"),
	)

	game.player.viewmodel.visible = false
	game.hud.visible = true
	game.hud.update_health(100, 100)
	game.hud.update_ammo(30, 90, false)
	game.hud.update_match(1, "live", 84.0, 0, 0, 800)
	game.hud.update_objective("")
	var hud_root := game.hud.get_node("HUDRoot") as Control
	var resolution_captures_ok := true
	for resolution in [
		Vector2i(640, 480),
		Vector2i(1024, 768),
		Vector2i(1280, 720),
	]:
		root.content_scale_size = resolution
		root.size = resolution
		hud_root.size = Vector2(resolution)
		for frame in range(4):
			await process_frame
		resolution_captures_ok = (
			_capture_resolution(
				output_root.path_join(
					"protocol47-hud-%dx%d.png" % [resolution.x, resolution.y],
				),
				resolution,
			)
			and resolution_captures_ok
		)

	if (
		menu_ok
		and game_ok
		and hud_ok
		and spawn_pose_ok
		and mobility_ok
		and models_ok
		and closeup_ok
		and viewmodel_ok
		and resolution_captures_ok
	):
		print("GAME_PREVIEW_CAPTURE_PASS")
		quit(0)
	else:
		quit(1)
