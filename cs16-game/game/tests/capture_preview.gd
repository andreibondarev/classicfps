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
	# CS 1.6 anchors v_ak47 in the lower-right screen corner: the silhouette
	# starts right of center, just below mid-screen, and is clipped by the
	# right and bottom screen edges.
	var framing_passes := (
		bounds.position.x >= 0.48
		and bounds.position.x <= 0.62
		and bounds.position.y >= 0.50
		and bounds.position.y <= 0.66
		and bounds.end.x >= 0.95
		and bounds.end.y >= 0.95
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


func _floor_height(game: Node, x: float, z: float, fallback_y: float) -> float:
	## Actual BSP floor height at (x, z), so staged models stand ON the ground
	## instead of floating at a guessed constant.
	var space: PhysicsDirectSpaceState3D = (
		game.player.get_world_3d().direct_space_state
	)
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, 20.0, z),
		Vector3(x, -20.0, z),
	)
	var excludes: Array[RID] = [game.player.get_rid()]
	for bot in game._all_bots():
		excludes.append(bot.get_rid())
	query.exclude = excludes
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return fallback_y
	return (hit["position"] as Vector3).y + 0.02


func _aim_player(game: Node, eye_position: Vector3, yaw_degrees: float) -> void:
	game.player.global_position = eye_position
	game.player.velocity = Vector3.ZERO
	var direction := Vector3(
		sin(deg_to_rad(yaw_degrees)),
		0.15,
		-cos(deg_to_rad(yaw_degrees)),
	)
	game.player.face_toward(game.player.global_position + direction * 10.0)
	game.player._pitch = 0.12
	game.player.camera.rotation.x = game.player._pitch


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

	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	game.start_match()
	for frame in range(8):
		await process_frame
	var player_spawn_position: Vector3 = game.player.global_position
	# Face the T-spawn mid exit so the primary gameplay capture shows a real
	# sightline (sky, depth, lightmap gradients) instead of a nose-to-wall frame.
	_aim_player(game, Vector3(-7.8, 2.1, 8.0), 90.0)
	for frame in range(3):
		await process_frame
	var game_ok := _capture_baked_map(output_root.path_join("protocol47-gameplay.png"))

	# HUD parity must exercise a DISTINCT frame from the gameplay capture:
	# different camera composition and non-default HUD state, so regressions
	# between the two scenarios stay visible instead of hiding behind a
	# byte-identical duplicate.
	_aim_player(game, Vector3(-4.6, 2.0, 8.0), 40.0)
	game.hud.update_health(72, 100)
	game.hud.update_ammo(17, 90, false)
	game.hud.update_match(3, "live", 47.0, 1, 1, 2350)
	for frame in range(3):
		await process_frame
	var hud_ok := _capture(output_root.path_join("protocol47-hud-parity.png"))
	# The classic UI capture harness overlays menu states on a real in-game
	# frame. A backdrop with the HUD baked in double-exposes stale HUD digits
	# under every menu, so export one HUD-free frame for it to use.
	game.hud.visible = false
	for frame in range(2):
		await process_frame
	var backdrop_ok := _capture(
		output_root.path_join("protocol47-menu-backdrop-1280x720.png")
	)
	game.hud.visible = true
	game.hud.update_health(100, 100)
	game.hud.update_ammo(30, 90, false)
	game.hud.update_match(1, "live", 84.0, 0, 0, 800)
	_aim_player(game, Vector3(-7.8, 2.1, 8.0), 90.0)

	# Canonical dust2 postcard vistas: wide compositions with sky in frame so
	# skybox, draw distance, and baked-shadow contrast stay reviewable.
	var vista_specs := [
		# csSandWallGH1a/b graffiti mural (the recognizable T-spawn wall art):
		# spans x -18.4..-14.08, y 2.08..3.04 on the wall plane z=-7.04 facing
		# spawn — frame it head-on so the landmark is provable in the capture.
		["protocol47-vista-tspawn-mural.png", Vector3(-16.2, 2.2, -3.2), 0.0],
		["protocol47-vista-tspawn-mid.png", Vector3(-4.6, 2.0, 8.0), 75.0],
		["protocol47-vista-mid-catwalk.png", Vector3(-2.0, 0.4, -6.0), 0.0],
		["protocol47-vista-mid-doors.png", Vector3(-2.0, 0.4, -6.0), 180.0],
	]
	var vistas_ok := true
	for raw_spec in vista_specs:
		var spec := raw_spec as Array
		_aim_player(game, spec[1] as Vector3, float(spec[2]))
		for frame in range(3):
			await process_frame
		vistas_ok = _capture(output_root.path_join(str(spec[0]))) and vistas_ok
	_aim_player(game, Vector3(-7.8, 2.1, 8.0), 90.0)

	var allied_center := Vector3.ZERO
	for ally in game.allied_bots:
		allied_center += ally.global_position
		ally.character_model.play_action("shoot")
		ally.character_model._process(0.02)
	allied_center /= game.allied_bots.size()
	# Shoot the squad from the player's own spawn point (the vista tour moved
	# the camera), aiming the pitch at chest height instead of a fixed angle.
	game.player.global_position = player_spawn_position
	game.player.velocity = Vector3.ZERO
	game.player.face_toward(allied_center + Vector3.UP * 0.4)
	var to_squad: Vector3 = (
		allied_center + Vector3.UP * 0.45 - game.player.global_position
	)
	game.player._pitch = clampf(
		atan2(to_squad.y, Vector2(to_squad.x, to_squad.z).length()),
		-0.5,
		0.3,
	)
	game.player.camera.rotation.x = game.player._pitch
	for frame in range(2):
		await process_frame
	var spawn_pose_ok := _capture(output_root.path_join("protocol47-bot-spawn-pose.png"))
	for ally in game.allied_bots:
		ally.character_model.reset_animation()

	game._begin_live()
	for frame in range(360):
		await physics_frame
	# Bots have wandered by now; bring the nearest live movers into the view
	# frustum mid-stride so the capture actually shows run/strafe animation.
	var moving_bots: Array[TargetActor] = []
	for bot in game._all_bots():
		if bot.alive:
			moving_bots.append(bot)
	var view_forward: Vector3 = -game.player.global_basis.z
	var view_right: Vector3 = game.player.global_basis.x
	var clearance: PhysicsDirectSpaceState3D = (
		game.player.get_world_3d().direct_space_state
	)
	for bot_index in range(mini(3, moving_bots.size())):
		var mover := moving_bots[bot_index]
		var target: Vector3 = (
			game.player.global_position
			+ view_forward * (1.9 + 0.45 * float(bot_index))
			+ view_right * (float(bot_index) - 1.0) * 0.62
		)
		# Skip placements that would bury the bot in level geometry.
		var clearance_query := PhysicsRayQueryParameters3D.create(
			game.player.global_position + Vector3.UP * 0.5,
			target + Vector3.UP * 0.5,
		)
		clearance_query.exclude = [game.player.get_rid(), mover.get_rid()]
		if clearance.intersect_ray(clearance_query).is_empty():
			mover.global_position = target
	game.player._pitch = -0.06
	game.player.camera.rotation.x = game.player._pitch
	for frame in range(3):
		await physics_frame
	var mobility_ok := _capture(output_root.path_join("protocol47-bot-mobility.png"))

	# Stage the lineup on the spawn plaza — known walkable, lit BSP ground —
	# keeping the camera at the player's own spawn point (leaving the plateau
	# puts the camera on skybox terrain or inside walls).
	var stage_forward: Vector3 = allied_center - player_spawn_position
	stage_forward.y = 0.0
	stage_forward = (
		stage_forward.normalized()
		if stage_forward.length() > 0.05
		else Vector3.FORWARD
	)
	var stage_right: Vector3 = stage_forward.cross(Vector3.UP).normalized()
	game.player.global_position = player_spawn_position
	game.player.velocity = Vector3.ZERO
	game.player.face_toward(
		player_spawn_position + stage_forward * 3.0 + Vector3.UP * 0.42
	)
	# Keep the imported map visible: the lineup needs lit BSP ground under the
	# models so feet contact and grounding stay reviewable. Hide the HUD and
	# viewmodel instead so nothing occludes the subjects.
	game.hud.visible = false
	game.player.viewmodel.visible = false
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
			var line_spot: Vector3 = (
				player_spawn_position
				+ stage_forward * (2.0 + float(row_index) * 0.8)
				+ stage_right
				* ((float(bot_index) - (float(row.size()) - 1.0) * 0.5) * spacing)
			)
			var line_query := PhysicsRayQueryParameters3D.create(
				game.player.global_position + Vector3.UP * 0.5,
				line_spot + Vector3.UP * 0.5,
			)
			var line_excludes: Array[RID] = [game.player.get_rid()]
			for other in game._all_bots():
				line_excludes.append(other.get_rid())
			line_query.exclude = line_excludes
			if not clearance.intersect_ray(line_query).is_empty():
				continue
			bot.global_position = Vector3(
				line_spot.x,
				_floor_height(game, line_spot.x, line_spot.z, allied_center.y),
				line_spot.z,
			)
			bot.look_at(game.player.global_position, Vector3.UP)
	for frame in range(8):
		await process_frame
	var models_ok := _capture(output_root.path_join("protocol47-player-models.png"))

	for bot in game._all_bots():
		bot.character_model.visible = false
	# Stage the closeup on the same open lineup floor so the subject stands on
	# lit BSP ground instead of placing the camera inside level geometry.
	var closeup: TargetActor = game.allied_bots[0]
	var closeup_spot: Vector3 = player_spawn_position + stage_forward * 1.1
	var closeup_floor := _floor_height(
		game,
		closeup_spot.x,
		closeup_spot.z,
		allied_center.y,
	)
	game.player.global_position = player_spawn_position
	game.player.velocity = Vector3.ZERO
	game.player.face_toward(
		Vector3(closeup_spot.x, closeup_floor + 0.5, closeup_spot.z)
	)
	game.player._pitch = -0.06
	game.player._sync_view_angles()
	closeup.character_model.visible = true
	closeup.global_position = Vector3(closeup_spot.x, closeup_floor, closeup_spot.z)
	closeup.look_at(game.player.global_position, Vector3.UP)
	game.hud.visible = false
	game.player.viewmodel.visible = false
	for frame in range(4):
		await process_frame
	var closeup_ok := _capture(output_root.path_join("protocol47-player-model-closeup.png"))

	closeup.character_model.visible = false
	# The silhouette gate needs a uniform backdrop; the GoldSrc skybox is not
	# one, so flatten the background for this capture only.
	var capture_environment := (
		game.get_node("WorldEnvironment") as WorldEnvironment
	).environment
	var previous_background := capture_environment.background_mode
	capture_environment.background_mode = Environment.BG_COLOR
	capture_environment.background_color = Color("#71828b")
	if is_instance_valid(game.imported_map):
		game.imported_map.visible = false
	game.player.viewmodel.visible = true
	game.player.grant_item("ak47")
	game.player.switch_weapon("ak47")
	game.player.viewmodel._start_animation("idle1", true)
	game.player._pitch = 0.0
	game.player._sync_view_angles()
	for frame in range(4):
		await process_frame
	# Silhouette-gate scratch capture only: the reviewable viewmodel artifacts
	# come from viewmodel_gameplay_capture.gd with map + HUD, so this gray-void
	# frame must not land beside them in artifacts/.
	var viewmodel_ok := _capture_classic_viewmodel(
		"/tmp/protocol47-viewmodel-ak-silhouette.png",
	)
	capture_environment.background_mode = previous_background
	if is_instance_valid(game.imported_map):
		game.imported_map.visible = true

	game.player.viewmodel.visible = false
	game.hud.visible = true
	game.hud.update_health(100, 100)
	game.hud.update_ammo(30, 90, false)
	game.hud.update_match(1, "live", 84.0, 0, 0, 800)
	game.hud.update_objective("")
	# Guarantee live radar contacts in the resolution HUD captures: stage the
	# allied squad alive at readable radar offsets around the player (combat
	# up to this point may have wiped them, which would show an empty radar).
	var radar_offsets := [
		Vector3(4.0, 0.0, -6.0),
		Vector3(-5.0, 0.0, -3.0),
		Vector3(2.5, 1.2, 5.0),
	]
	for ally_index in range(game.allied_bots.size()):
		var radar_ally: TargetActor = game.allied_bots[ally_index]
		radar_ally.alive = true
		radar_ally.active = true
		radar_ally.global_position = (
			game.player.global_position
			+ radar_offsets[ally_index % radar_offsets.size()]
		)
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
		and backdrop_ok
		and vistas_ok
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
