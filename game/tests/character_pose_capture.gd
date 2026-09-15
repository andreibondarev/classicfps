extends SceneTree

const CharacterModelScript := preload("res://scripts/mdl_character_model.gd")
const SKINS := ["terror", "leet", "arctic", "guerilla", "urban", "gsg9", "sas", "gign"]
const POSES := [
	["idle", 0.50],
	["run", 0.50],
	["crouchidle", 0.00],
	["crouchrun", 0.50],
	["shoot", 0.50],
	["reload", 0.50],
	["die", 1.00],
]
const BACKGROUND := Color("#9aacaf")
const FLOOR_COLOR := Color("#37434a")
const BAR_COLOR := Color("#efb84f")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_root := ProjectSettings.globalize_path("res://artifacts")
	DirAccess.make_dir_recursive_absolute(output_root)
	if "--gait-only" in OS.get_cmdline_user_args():
		var gait_ok := await _capture_gait_grid(output_root.path_join("protocol47-character-gait-grid.png"))
		if gait_ok:
			print("GAME_CHARACTER_GAIT_CAPTURE_PASS")
		quit(0 if gait_ok else 1)
		return
	var pose_ok := await _capture_pose_grid(
		output_root.path_join("protocol47-character-pose-grid.png")
	)
	var scale_ok := await _capture_scale_grid(
		output_root.path_join("protocol47-character-scale-grid.png")
	)
	var phase_ok := await _capture_interpolation_grid(
		output_root.path_join("protocol47-character-interpolation-grid.png")
	)
	var family_ok := await _capture_family_grid(
		output_root.path_join("protocol47-character-weapon-families.png")
	)
	var crouch_death_ok := await _capture_crouch_death_grid(
		output_root.path_join("protocol47-character-crouch-death.png")
	)
	if pose_ok and scale_ok and phase_ok and family_ok and crouch_death_ok:
		print(
			"GAME_CHARACTER_POSE_CAPTURE_PASS %s %s %s %s %s"
			% [
				output_root.path_join("protocol47-character-pose-grid.png"),
				output_root.path_join("protocol47-character-scale-grid.png"),
				output_root.path_join("protocol47-character-interpolation-grid.png"),
				output_root.path_join("protocol47-character-weapon-families.png"),
				output_root.path_join("protocol47-character-crouch-death.png"),
			]
		)
		quit()
	else:
		quit(1)


func _capture_gait_grid(output_path: String) -> bool:
	var scene := _make_scene("Source gait cycle · 0 / 25 / 50 / 75% · run above, crouch-walk below")
	root.add_child(scene)
	for row in 2:
		for column in 4:
			var cell := Node3D.new()
			cell.position = Vector3((1.5 - float(column)) * 0.88, 0.90 if row == 0 else 0.0, 0.0)
			scene.add_child(cell)
			var model := _make_model("terror", "ak47")
			cell.add_child(model)
			model.process_mode = Node.PROCESS_MODE_DISABLED
			model.rotation.y += 0.38 * PI
			model.set_locomotion(true, row == 1, true)
			model.force_pose("run" if row == 0 else "crouchrun", float(column) * 0.25)
			_add_projected_label(scene, "%d%%" % (column * 25), cell.global_position + Vector3(0, -0.12, 0), 20)
	_add_floor(scene, 3.8, 0.0)
	_add_floor(scene, 3.8, 0.90)
	var captured := await _settle_and_capture(output_path)
	scene.queue_free()
	await process_frame
	return captured


func _capture_family_grid(output_path: String) -> bool:
	# Three-quarter framing on purpose: the barrel line and grip-in-palm
	# alignment of the bone-merged p_ model stay visible side-on, exactly
	# where a detached weapon family would show.
	var scene := _make_scene(
		"Weapon activity families · three-quarter view · barrel + grip alignment"
	)
	root.add_child(scene)
	var loadouts := [
		["terror", "ak47", "idle", 0.50],
		["gsg9", "m4a1", "idle", 0.50],
		["arctic", "awp", "idle", 0.50],
		["leet", "mp5", "run", 0.50],
		["urban", "m3", "idle", 0.50],
		["guerilla", "m249", "idle", 0.50],
		["sas", "knife", "idle", 0.50],
		# Keep the front-facing one-handed silhouette in the standard visual
		# regression sheet: this was the stance that exposed the overly narrow
		# widescreen presentation in live spectating.
		["gign", "usp", "idle", 0.50],
	]
	for index in loadouts.size():
		var loadout: Array = loadouts[index]
		var cell := Node3D.new()
		cell.position = Vector3(
			(float(index % 4) - 1.5) * 0.88,
			0.90 if index < 4 else 0.0,
			0.0,
		)
		scene.add_child(cell)
		var model := _make_model(str(loadout[0]), str(loadout[1]))
		cell.add_child(model)
		model.process_mode = Node.PROCESS_MODE_DISABLED
		# Rotate away from the camera-facing default so the weapon reads in
		# profile instead of foreshortening into the chest.
		model.rotation.y += 0.30 * PI
		model.force_pose(str(loadout[2]), float(loadout[3]), 0.0)
		_add_projected_label(
			scene,
			"%s · %s" % [str(loadout[0]), str(loadout[1])],
			cell.global_position + Vector3(0.0, -0.12, 0.0),
			20,
		)
	_add_floor(scene, 3.8, 0.0)
	_add_floor(scene, 3.8, 0.90)
	var captured := await _settle_and_capture(output_path)
	scene.queue_free()
	await process_frame
	return captured


func _capture_crouch_death_grid(output_path: String) -> bool:
	var scene := _make_scene(
		"Crouch + death source tapes · settled idle · mid-fall · settled corpse"
	)
	root.add_child(scene)
	var stages := [
		["idle", 0.00, "idle (settled)"],
		["crouchidle", 0.25, "crouchidle"],
		["crouchrun", 0.50, "crouchrun"],
		["crouchshoot", 0.50, "crouchshoot"],
		["die", 0.35, "die (mid-fall)"],
		["die", 1.00, "die (corpse)"],
	]
	for index in stages.size():
		var stage: Array = stages[index]
		var row := index / 3
		var cell := Node3D.new()
		cell.position = Vector3(
			(float(index % 3) - 1.0) * 1.16,
			0.90 if row == 0 else 0.0,
			0.0,
		)
		scene.add_child(cell)
		var model := _make_model("terror", "ak47")
		cell.add_child(model)
		model.process_mode = Node.PROCESS_MODE_DISABLED
		model.rotation.y += 0.22 * PI
		if str(stage[0]) == "die":
			model.play_death()
			var animation: Dictionary = model._body_template.animations.die
			var frame_index := mini(
				int(floor(float(stage[1]) * float(animation.frames - 1))),
				int(animation.frames) - 1,
			)
			model.advance_animation(float(frame_index) / float(animation.fps))
		else:
			model.set_locomotion(false, str(stage[0]).begins_with("crouch"), true)
			model.force_pose(str(stage[0]), float(stage[1]), 0.0)
		_add_projected_label(
			scene,
			str(stage[2]),
			cell.global_position + Vector3(0.0, -0.12, 0.0),
			20,
		)
	_add_floor(scene, 3.8, 0.0)
	_add_floor(scene, 3.8, 0.90)
	var captured := await _settle_and_capture(output_path)
	scene.queue_free()
	await process_frame
	return captured


func _capture_pose_grid(output_path: String) -> bool:
	var scene := _make_scene(
		"AK-47 source poses · center aim blend · amber bar = 72 HU standing hull"
	)
	root.add_child(scene)
	for index in POSES.size():
		var pose: Array = POSES[index]
		var row := index / 4
		var column := index % 4
		var row_count := 4 if row == 0 else 3
		var cell := Node3D.new()
		cell.position = Vector3(
			(float(column) - (float(row_count) - 1.0) * 0.5) * 0.88,
			0.90 if row == 0 else 0.0,
			0.0,
		)
		scene.add_child(cell)
		var model := _make_model("terror")
		cell.add_child(model)
		model.process_mode = Node.PROCESS_MODE_DISABLED
		model.force_pose(str(pose[0]), float(pose[1]), 0.0)
		_add_projected_label(
			scene,
			str(pose[0]),
			cell.global_position + Vector3(0.0, -0.12, 0.0),
		)
		if index == 0:
			_add_height_bar(cell, Vector3(-0.27, 0.0, 0.0))
	_add_floor(scene, 3.8, 0.0)
	_add_floor(scene, 3.8, 0.90)
	var captured := await _settle_and_capture(output_path)
	scene.queue_free()
	await process_frame
	return captured


func _capture_scale_grid(output_path: String) -> bool:
	var scene := _make_scene(
		"Eight original playable MDLs · amber bars = 72 HU standing collision hull"
	)
	root.add_child(scene)
	for index in SKINS.size():
		var skin: String = SKINS[index]
		var cell := Node3D.new()
		cell.position = Vector3(
			(float(index % 4) - 1.5) * 0.88,
			0.90 if index < 4 else 0.0,
			0.0,
		)
		scene.add_child(cell)
		var model := _make_model(skin)
		cell.add_child(model)
		model.process_mode = Node.PROCESS_MODE_DISABLED
		model.force_pose("idle", 0.5, 0.0)
		_add_projected_label(
			scene,
			skin,
			cell.global_position + Vector3(0.0, -0.12, 0.0),
		)
		_add_height_bar(cell, Vector3(0.27, 0.0, 0.0))
	_add_floor(scene, 3.8, 0.0)
	_add_floor(scene, 3.8, 0.90)
	var captured := await _settle_and_capture(output_path)
	scene.queue_free()
	await process_frame
	return captured


func _capture_interpolation_grid(output_path: String) -> bool:
	var scene := _make_scene(
		"Adjacent authored shoot frames · temporal + XR blend · one production clock"
	)
	root.add_child(scene)
	# Single-row grid: tighten the ortho framing so the three phase characters
	# fill the canvas and the temporal blend differences stay judgeable.
	var camera := scene.get_node("CaptureCamera") as Camera3D
	camera.size = 1.02
	camera.position.y = 0.42
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.40, 0.0), Vector3.UP)
	for index in 3:
		var phase: float = [0.25, 0.50, 0.75][index]
		var cell := Node3D.new()
		cell.position = Vector3((float(index) - 1.0) * 0.60, 0.0, 0.0)
		scene.add_child(cell)
		var model := _make_model("terror")
		cell.add_child(model)
		model.process_mode = Node.PROCESS_MODE_DISABLED
		model._aim_pitch_degrees = 3.75
		var animation: Dictionary = model._body_template.animations.shoot
		var sample_time := phase / float(animation.fps)
		model._body_frame_key = model._set_frame(
			model.body_instance,
			model._body_template,
			"shoot",
			sample_time,
			false,
			"",
		)
		model._weapon_frame_key = model._set_frame(
			model.weapon_instance,
			model._weapon_template,
			"shoot",
			sample_time,
			false,
			"",
		)
		_add_projected_label(
			scene,
			"phase %.2f" % phase,
			cell.global_position + Vector3(0.0, -0.06, 0.0),
		)
	_add_floor(scene, 3.8, 0.0)
	var captured := await _settle_and_capture(output_path)
	scene.queue_free()
	await process_frame
	return captured


func _make_scene(title: String) -> Node3D:
	var scene := Node3D.new()
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment_node.environment = environment
	scene.add_child(environment_node)
	var camera := Camera3D.new()
	camera.name = "CaptureCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.08
	camera.position = Vector3(0.0, 0.78, -4.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.72, 0.0), Vector3.UP)
	scene.add_child(camera)
	camera.current = true
	_add_label(scene, title, 28.0, 20.0, 24)
	return scene


func _make_model(skin: String, weapon := "ak47") -> MdlCharacterModel:
	var model: MdlCharacterModel = CharacterModelScript.new()
	if not model.load_character(skin, weapon):
		push_error("Could not load capture model %s (%s)" % [skin, weapon])
	model.set_process(false)
	return model


func _add_floor(scene: Node3D, width: float, height: float) -> void:
	var floor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.018, 0.8)
	mesh.material = _unshaded_material(FLOOR_COLOR)
	floor.mesh = mesh
	floor.position = Vector3(0.0, height - 0.012, 0.0)
	scene.add_child(floor)


func _add_height_bar(scene: Node3D, origin: Vector3, labeled := false) -> void:
	var bar := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.72, 0.018)
	mesh.material = _unshaded_material(BAR_COLOR)
	bar.mesh = mesh
	bar.position = origin + Vector3(0.0, 0.36, 0.01)
	scene.add_child(bar)
	if labeled:
		_add_projected_label(scene, "72 HU", origin + Vector3(0.0, 0.76, 0.0), 18)


func _add_projected_label(
	scene: Node3D,
	text: String,
	world_position: Vector3,
	font_size := 24,
) -> void:
	var camera := scene.get_node("CaptureCamera") as Camera3D
	var screen_position := camera.unproject_position(world_position)
	var label := Label.new()
	label.text = text
	label.position = screen_position - Vector2(90.0, 0.0)
	label.size = Vector2(180.0, 28.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#172127"))
	scene.add_child(label)


func _add_label(
	scene: Node3D,
	text: String,
	x: float,
	y: float,
	font_size := 17,
) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(x, y)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#172127"))
	scene.add_child(label)


func _unshaded_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func _settle_and_capture(output_path: String) -> bool:
	for frame in range(4):
		await process_frame
		RenderingServer.force_draw()
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save %s: %s" % [output_path, error_string(error)])
		return false
	return true
