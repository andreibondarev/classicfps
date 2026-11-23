extends SceneTree

const CharacterModelScript := preload("res://scripts/mdl_character_model.gd")
const C4WorldScript := preload("res://scripts/cs16_c4_world.gd")
const ViewModelScript := preload("res://scripts/mdl_viewmodel.gd")

const BACKGROUND := Color("#78868b")
const FLOOR_COLOR := Color("#526168")
const LABEL_COLOR := Color("#eef4f5")
const OUTPUT_ROOT := "/tmp"
const CELL_SIZE := Vector2i(640, 480)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1440)
	root.content_scale_size = Vector2i(1920, 1440)
	var transform_ok := await _capture_transform_grid()
	var viewmodel_ok := await _capture_viewmodel_grid()
	var world_front_ok := await _capture_world(
		"protocol47-c4-world-front.png",
		Vector3(0.0, 0.26, -0.78),
		Vector3(0.0, 0.035, 0.0),
	)
	var world_side_ok := await _capture_world(
		"protocol47-c4-world-side.png",
		Vector3(0.78, 0.26, 0.0),
		Vector3(0.0, 0.035, 0.0),
	)
	var world_top_ok := await _capture_world(
		"protocol47-c4-world-top.png",
		Vector3(0.0, 0.82, 0.02),
		Vector3.ZERO,
	)
	var planter_ok := await _capture_planter_grid()
	var planted_ok := await _capture_planted_artifact()
	var explosion_ok := await _capture_c4_explosion_artifact()
	if (
		transform_ok
		and viewmodel_ok
		and world_front_ok
		and world_side_ok
		and world_top_ok
		and planter_ok
		and planted_ok
		and explosion_ok
	):
		print(
			"GAME_C4_VISUAL_CAPTURE_PASS "
			+ "/tmp/protocol47-c4-viewmodel-grid.png "
			+ "/tmp/protocol47-c4-world-front.png "
			+ "/tmp/protocol47-c4-world-side.png "
			+ "/tmp/protocol47-c4-world-top.png "
			+ "/tmp/protocol47-c4-planter-pose-grid.png "
			+ "/tmp/protocol47-c4-transform-grid.png "
			+ ProjectSettings.globalize_path("res://artifacts/protocol47-c4-planted.png")
			+ " "
			+ ProjectSettings.globalize_path("res://artifacts/protocol47-c4-explosion.png")
		)
		quit(0)
	else:
		quit(1)


func _capture_transform_grid() -> bool:
	var candidates := [
		{
			"label": (
				"SELECTED A  p(.36,.18,-.52) s(-2.2,3.5,-3.5) "
				+ "· ref device 12–22% frame · hands exit lower-right"
			),
			"position": Vector3(0.36, 0.18, -0.52),
			"scale": Vector3(-2.2, 3.5, -3.5),
		},
		{
			"label": "B · upper scale bound",
			"position": Vector3(0.39, 0.18, -0.56),
			"scale": Vector3(-2.4, 3.8, -3.8),
		},
		{
			"label": "C · rejected clipped/overlarge",
			"position": Vector3(0.42, 0.18, -0.60),
			"scale": Vector3(-2.6, 4.1, -4.1),
		},
		{
			"label": "D · high framing bound",
			"position": Vector3(0.36, 0.22, -0.52),
			"scale": Vector3(-2.2, 3.5, -3.5),
		},
		{
			"label": "E · high/large reference",
			"position": Vector3(0.39, 0.22, -0.56),
			"scale": Vector3(-2.4, 3.8, -3.8),
		},
		{
			"label": "F · rejected high/overlarge",
			"position": Vector3(0.42, 0.22, -0.60),
			"scale": Vector3(-2.6, 4.1, -4.1),
		},
		{
			"label": "G · upper framing rejection",
			"position": Vector3(0.36, 0.26, -0.52),
			"scale": Vector3(-2.2, 3.5, -3.5),
		},
		{
			"label": "H · upper/large rejection",
			"position": Vector3(0.39, 0.26, -0.56),
			"scale": Vector3(-2.4, 3.8, -3.8),
		},
		{
			"label": "I · upper clipping rejection",
			"position": Vector3(0.42, 0.26, -0.60),
			"scale": Vector3(-2.6, 4.1, -4.1),
		},
	]
	var images: Array[Image] = []
	for index in candidates.size():
		var candidate: Dictionary = candidates[index]
		images.append(await _render_viewmodel_image(
			str(candidate.label),
			"idle1",
			0.0,
			candidate.position,
			candidate.scale,
		))
	return _save_montage(
		images,
		3,
		CELL_SIZE,
		OUTPUT_ROOT.path_join("protocol47-c4-transform-grid.png"),
	)


func _capture_viewmodel_grid() -> bool:
	var samples := [
		["draw start", "draw", 0.0],
		["draw mid", "draw", 0.53],
		["idle", "idle1", 0.0],
		["arm acquire · 18%", "pressbutton", 0.18],
		["arm keypad · 48%", "pressbutton", 0.48],
		["arm confirm · 78%", "pressbutton", 0.78],
		["drop start", "drop", 0.0],
		["drop mid", "drop", 0.50],
		["drop end", "drop", 0.98],
	]
	var images: Array[Image] = []
	for index in samples.size():
		var sample: Array = samples[index]
		images.append(await _render_viewmodel_image(
			str(sample[0]),
			str(sample[1]),
			float(sample[2]),
			ViewModelScript.C4_BASE_POSITION,
			ViewModelScript.C4_MODEL_SCALE,
		))
	return _save_montage(
		images,
		3,
		CELL_SIZE,
		OUTPUT_ROOT.path_join("protocol47-c4-viewmodel-grid.png"),
	)


func _make_grid() -> Control:
	var grid := Control.new()
	grid.size = Vector2(1920, 1440)
	var background := ColorRect.new()
	background.color = Color("#1c2428")
	background.size = grid.size
	grid.add_child(background)
	return grid


func _make_viewmodel_panel(
	label_text: String,
	animation_name: String,
	fraction: float,
	view_position: Vector3,
	view_scale: Vector3,
) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.size = Vector2(CELL_SIZE)
	var viewport := SubViewport.new()
	viewport.size = CELL_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	_add_environment(viewport)
	var camera := Camera3D.new()
	camera.fov = 74.0
	camera.near = 0.01
	camera.current = true
	viewport.add_child(camera)
	var viewmodel: MdlViewModel = ViewModelScript.new()
	camera.add_child(viewmodel)
	viewmodel.load_weapon("c4")
	viewmodel.position = view_position
	viewmodel.model_root.scale = view_scale
	viewmodel._start_animation(animation_name, false)
	var animation: Dictionary = viewmodel._template.animations[animation_name]
	viewmodel._animation_time = (
		float(animation.frames) / maxf(float(animation.fps), 1.0)
		* fraction
	)
	viewmodel._frame_key = ""
	viewmodel._process(0.0)
	var label := Label.new()
	label.text = label_text
	label.position = Vector2(18.0, 435.0)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", LABEL_COLOR)
	container.add_child(label)
	return container


func _render_viewmodel_image(
	label_text: String,
	animation_name: String,
	fraction: float,
	view_position: Vector3,
	view_scale: Vector3,
) -> Image:
	root.size = CELL_SIZE
	root.content_scale_size = CELL_SIZE
	var scene := Node3D.new()
	root.add_child(scene)
	_add_environment(scene)
	var camera := Camera3D.new()
	camera.fov = 74.0
	camera.near = 0.01
	camera.current = true
	scene.add_child(camera)
	var viewmodel: MdlViewModel = ViewModelScript.new()
	camera.add_child(viewmodel)
	viewmodel.load_weapon("c4")
	viewmodel.position = view_position
	viewmodel.model_root.scale = view_scale
	viewmodel._start_animation(animation_name, false)
	var animation: Dictionary = viewmodel._template.animations[animation_name]
	viewmodel._animation_time = (
		float(animation.frames) / maxf(float(animation.fps), 1.0)
		* fraction
	)
	viewmodel._frame_key = ""
	viewmodel._process(0.0)
	var label := Label.new()
	label.text = label_text
	label.position = Vector2(18.0, 438.0)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", LABEL_COLOR)
	root.add_child(label)
	for frame in 6:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	label.queue_free()
	scene.queue_free()
	await process_frame
	return image


func _capture_world(
	file_name: String,
	camera_position: Vector3,
	camera_target: Vector3,
) -> bool:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var scene := Node3D.new()
	root.add_child(scene)
	_add_environment(scene)
	_add_floor(scene, Vector3(1.1, 0.018, 0.70))
	var separation_axis := (
		Vector3(0.0, 0.0, 1.0)
		if absf(camera_position.x) > absf(camera_position.z)
		else Vector3(1.0, 0.0, 0.0)
	)
	var planted := C4WorldScript.create_planted_visual()
	planted.position = separation_axis * -0.18
	planted.rotation.y = -PI * 0.5
	scene.add_child(planted)
	var backpack := C4WorldScript.create_source_model(
		C4WorldScript.BACKPACK_MODEL,
		"BackpackModel",
	)
	backpack.position = separation_axis * 0.18
	scene.add_child(backpack)
	var camera := Camera3D.new()
	camera.fov = 46.0
	camera.current = true
	scene.add_child(camera)
	camera.look_at_from_position(camera_position, camera_target, Vector3.UP)
	var ok := await _settle_and_capture(OUTPUT_ROOT.path_join(file_name))
	scene.queue_free()
	await process_frame
	return ok


func _capture_planter_grid() -> bool:
	# Sample the exact production action clock. The previous force_pose call
	# derived time from the base player's very short generic attack sequence,
	# leaving the much longer original p_c4 plant strip near frame zero.
	var views := [
		["T planter · early 0.75 s · front", Vector3(0.0, 0.55, -2.1), 0.75],
		["T planter · early 0.75 s · side", Vector3(2.1, 0.55, 0.0), 0.75],
		["T planter · keypad 2.00 s · front", Vector3(0.0, 0.55, -2.1), 2.00],
		["T planter · keypad 2.00 s · side", Vector3(2.1, 0.55, 0.0), 2.00],
		["T planter · release 3.25 s · front", Vector3(0.0, 0.55, -2.1), 3.25],
		["T planter · release 3.25 s · side", Vector3(2.1, 0.55, 0.0), 3.25],
	]
	var images: Array[Image] = []
	for index in views.size():
		var view: Array = views[index]
		root.size = Vector2i(960, 720)
		root.content_scale_size = Vector2i(960, 720)
		var scene := Node3D.new()
		root.add_child(scene)
		_add_environment(scene)
		_add_floor(scene, Vector3(1.2, 0.018, 0.9))
		var model: MdlCharacterModel = CharacterModelScript.new()
		scene.add_child(model)
		model.load_character("terror", "c4")
		model.process_mode = Node.PROCESS_MODE_DISABLED
		model.set_locomotion(false, true, true)
		model.play_action("shoot")
		model.advance_animation(float(view[2]))
		var camera := Camera3D.new()
		camera.fov = 36.0
		camera.current = true
		scene.add_child(camera)
		camera.look_at_from_position(
			view[1],
			Vector3(0.0, 0.38, 0.0),
			Vector3.UP,
		)
		var label := Label.new()
		label.text = str(view[0])
		label.position = Vector2(22.0, 675.0)
		label.add_theme_font_size_override("font_size", 26)
		label.add_theme_color_override("font_color", LABEL_COLOR)
		root.add_child(label)
		for frame in 6:
			await process_frame
		images.append(root.get_viewport().get_texture().get_image())
		label.queue_free()
		scene.queue_free()
		await process_frame
	return _save_montage(
		images,
		2,
		Vector2i(960, 720),
		OUTPUT_ROOT.path_join("protocol47-c4-planter-pose-grid.png"),
	)


func _save_montage(
	images: Array[Image],
	columns: int,
	cell_size: Vector2i,
	path: String,
) -> bool:
	var rows := int(ceil(float(images.size()) / float(columns)))
	var montage := Image.create(
		cell_size.x * columns,
		cell_size.y * rows,
		false,
		Image.FORMAT_RGBA8,
	)
	montage.fill(Color("#1c2428"))
	for index in images.size():
		montage.blit_rect(
			images[index],
			Rect2i(Vector2i.ZERO, cell_size),
			Vector2i(
				(index % columns) * cell_size.x,
				(index / columns) * cell_size.y,
			),
		)
	var error := montage.save_png(path)
	if error != OK:
		push_error("Could not save montage %s: %s" % [path, error_string(error)])
		return false
	return true


func _add_environment(parent: Node) -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.58
	environment_node.environment = environment
	parent.add_child(environment_node)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	key_light.light_energy = 1.65
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 8.0
	parent.add_child(key_light)


func _add_floor(parent: Node, size: Vector3) -> void:
	var floor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = FLOOR_COLOR
	material.roughness = 0.82
	mesh.material = material
	floor.mesh = mesh
	floor.position.y = -size.y * 0.5
	parent.add_child(floor)


func _make_bombsite_scene() -> Dictionary:
	## Stages the real de_dust2 map and returns {scene, site} where site is a
	## floor point inside the first func_bomb_target region.
	const BspMapScript := preload("res://scripts/bsp_map.gd")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#26303a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c8d0ce")
	environment.ambient_light_energy = 0.78
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	scene.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.1
	scene.add_child(sun)
	var map: BspMap = BspMapScript.new()
	scene.add_child(map)
	if not map.load_map("res://generated/de_dust2/map.json"):
		push_error("C4 capture could not load de_dust2")
		return {}
	var regions := map.brush_entity_regions("func_bomb_target")
	if regions.is_empty():
		push_error("de_dust2 exposes no func_bomb_target region")
		return {}
	var bounds: AABB = regions[0].bounds
	var site := Vector3(
		bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y + 0.005,
		bounds.position.z + bounds.size.z * 0.5,
	)
	return {"scene": scene, "site": site}


func _capture_planted_artifact() -> bool:
	## Required review artifact: the planted C4 in-world with its red blinking
	## LED lit, on the real dust2 bombsite floor.
	var staged := _make_bombsite_scene()
	if staged.is_empty():
		return false
	var scene: Node3D = staged.scene
	var site: Vector3 = staged.site
	var planted := C4WorldScript.create_planted_visual()
	scene.add_child(planted)
	planted.global_position = site
	planted.rotation.y = -PI * 0.35
	# Freeze the blink cycle at its lit phase for a deterministic capture; the
	# LED starts on and _process is what advances the pulse.
	planted.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.01
	scene.add_child(camera)
	camera.current = true
	camera.look_at_from_position(
		site + Vector3(0.26, 0.17, 0.34),
		site + Vector3.UP * 0.05,
		Vector3.UP,
	)
	var artifact_root := ProjectSettings.globalize_path("res://artifacts")
	DirAccess.make_dir_recursive_absolute(artifact_root)
	var ok := await _settle_and_capture(
		artifact_root.path_join("protocol47-c4-planted.png")
	)
	scene.queue_free()
	await process_frame
	return ok


func _capture_c4_explosion_artifact() -> bool:
	## Required review artifact: the C4 detonation multi-sprite fireball chain
	## with its scorch decal, on the real dust2 bombsite.
	const CombatEffectsScript := preload("res://scripts/cs16_combat_effects.gd")
	var staged := _make_bombsite_scene()
	if staged.is_empty():
		return false
	var scene: Node3D = staged.scene
	var site: Vector3 = staged.site
	var effects: CS16CombatEffects = CombatEffectsScript.new()
	effects.set_physics_process(false)
	scene.add_child(effects)
	# Entering the tree re-enables physics processing; freeze the clock so the
	# advance_tick(105) below selects the exact mid-detonation frame.
	effects.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.02
	scene.add_child(camera)
	camera.current = true
	# Keep the camera inside the (enclosed) bombsite: clamp the desired offset
	# against world geometry so the fireball chain is not shot through a wall.
	for frame in range(4):
		await physics_frame
	var desired_offset := Vector3(5.8, 2.2, 6.6)
	var space := scene.get_world_3d().direct_space_state
	var occluder := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		site + Vector3.UP * 1.2,
		site + Vector3.UP * 1.2 + desired_offset,
		1,
	))
	var camera_position := site + Vector3.UP * 1.2 + desired_offset
	if not occluder.is_empty():
		var free_span: float = (
			Vector3(occluder.position).distance_to(site + Vector3.UP * 1.2)
		)
		camera_position = (
			site + Vector3.UP * 1.2
			+ desired_offset.normalized() * maxf(free_span - 0.3, 1.2)
		)
	camera.look_at_from_position(
		camera_position,
		site + Vector3.UP * 1.3,
		Vector3.UP,
	)
	effects.spawn_c4_explosion(site + Vector3.UP * 0.04, Vector3.UP)
	# Mid-animation: developed flame tongues (fexplo frames 6-8 at 15 fps),
	# past the white birth flash but before the sparse ember/noise tail that
	# read as speckle over the background.
	effects.advance_tick(50)
	var artifact_root := ProjectSettings.globalize_path("res://artifacts")
	DirAccess.make_dir_recursive_absolute(artifact_root)
	var ok := await _settle_and_capture(
		artifact_root.path_join("protocol47-c4-explosion.png")
	)
	scene.queue_free()
	await process_frame
	return ok


func _settle_and_capture(path: String) -> bool:
	for frame in 8:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		return false
	return true
