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
	if (
		transform_ok
		and viewmodel_ok
		and world_front_ok
		and world_side_ok
		and world_top_ok
		and planter_ok
	):
		print(
			"GAME_C4_VISUAL_CAPTURE_PASS "
			+ "/tmp/protocol47-c4-viewmodel-grid.png "
			+ "/tmp/protocol47-c4-world-front.png "
			+ "/tmp/protocol47-c4-world-side.png "
			+ "/tmp/protocol47-c4-world-top.png "
			+ "/tmp/protocol47-c4-planter-pose-grid.png "
			+ "/tmp/protocol47-c4-transform-grid.png"
		)
		quit(0)
	else:
		quit(1)


func _capture_transform_grid() -> bool:
	var candidates := [
		{
			"label": "A  p(.36,.18,-.52)  s(-2.2,3.5,-3.5)",
			"position": Vector3(0.36, 0.18, -0.52),
			"scale": Vector3(-2.2, 3.5, -3.5),
		},
		{
			"label": "B  p(.39,.18,-.56)  s(-2.4,3.8,-3.8)",
			"position": Vector3(0.39, 0.18, -0.56),
			"scale": Vector3(-2.4, 3.8, -3.8),
		},
		{
			"label": "C  p(.42,.18,-.60)  s(-2.6,4.1,-4.1)",
			"position": Vector3(0.42, 0.18, -0.60),
			"scale": Vector3(-2.6, 4.1, -4.1),
		},
		{
			"label": "D  p(.36,.22,-.52)  s(-2.2,3.5,-3.5)",
			"position": Vector3(0.36, 0.22, -0.52),
			"scale": Vector3(-2.2, 3.5, -3.5),
		},
		{
			"label": "E  p(.39,.22,-.56)  s(-2.4,3.8,-3.8)",
			"position": Vector3(0.39, 0.22, -0.56),
			"scale": Vector3(-2.4, 3.8, -3.8),
		},
		{
			"label": "F  p(.42,.22,-.60)  s(-2.6,4.1,-4.1)",
			"position": Vector3(0.42, 0.22, -0.60),
			"scale": Vector3(-2.6, 4.1, -4.1),
		},
		{
			"label": "G  p(.36,.26,-.52)  s(-2.2,3.5,-3.5)",
			"position": Vector3(0.36, 0.26, -0.52),
			"scale": Vector3(-2.2, 3.5, -3.5),
		},
		{
			"label": "H  p(.39,.26,-.56)  s(-2.4,3.8,-3.8)",
			"position": Vector3(0.39, 0.26, -0.56),
			"scale": Vector3(-2.4, 3.8, -3.8),
		},
		{
			"label": "I  p(.42,.26,-.60)  s(-2.6,4.1,-4.1)",
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
		["arm start", "pressbutton", 0.0],
		["arm keypad", "pressbutton", 0.50],
		["arm late", "pressbutton", 0.86],
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
	var views := [
		["Terrorist planter · front", Vector3(0.0, 0.55, -2.1)],
		["Terrorist planter · side", Vector3(2.1, 0.55, 0.0)],
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
		model.force_pose("crouchshoot", 0.52, 0.0)
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
	environment.ambient_light_energy = 1.15
	environment_node.environment = environment
	parent.add_child(environment_node)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
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


func _settle_and_capture(path: String) -> bool:
	for frame in 8:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		return false
	return true
