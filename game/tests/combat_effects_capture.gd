extends SceneTree

const CombatEffects := preload("res://scripts/cs16_combat_effects.gd")

var manager: CS16CombatEffects
var output_root := ""


func _initialize() -> void:
	call_deferred("_run")


func _material(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _box(
	parent: Node3D,
	name: String,
	size: Vector3,
	position: Vector3,
	color: Color,
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	parent.add_child(instance)
	instance.global_position = position
	return instance


func _capture(name: String) -> bool:
	for frame in range(3):
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var path := output_root.path_join(name)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save combat VFX capture to %s: %s" % [path, error_string(error)])
		return false
	print("COMBAT_VFX_CAPTURE %s" % path)
	return true


func _reset_manager(stage: Node3D) -> CS16CombatEffects:
	if is_instance_valid(manager):
		manager.free()
	manager = CombatEffects.new()
	manager.name = CombatEffects.NODE_NAME
	manager.set_physics_process(false)
	stage.add_child(manager)
	return manager


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)

	var stage := Node3D.new()
	stage.name = "CombatEffectsCapture"
	root.add_child(stage)
	current_scene = stage

	var environment := WorldEnvironment.new()
	var world := Environment.new()
	world.background_mode = Environment.BG_COLOR
	world.background_color = Color("#26303a")
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color("#9aa5a8")
	world.ambient_light_energy = 0.22
	world.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = world
	stage.add_child(environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	key.light_color = Color("#ffe1b4")
	key.light_energy = 0.75
	key.shadow_enabled = true
	stage.add_child(key)

	_box(stage, "Floor", Vector3(8.0, 0.12, 7.0), Vector3(0.0, -0.06, -0.1), Color("#665940"))
	_box(stage, "ImpactWall", Vector3(4.6, 2.8, 0.12), Vector3(0.0, 1.4, -1.0), Color("#806e53"))

	var camera := Camera3D.new()
	camera.fov = 58.0
	stage.add_child(camera)
	camera.current = true

	# Fixture 1: a close, perpendicular plane makes the authored 16-HU bullet
	# decals and their alignment inspectable. Blood is isolated to the right;
	# no muzzle, shell, or explosion nodes exist in this fixture.
	_reset_manager(stage)
	camera.global_position = Vector3(0.0, 1.42, 1.55)
	camera.look_at_from_position(camera.global_position, Vector3(0.0, 1.35, -1.0), Vector3.UP)
	for index in range(5):
		manager.spawn_world_impact(
			Vector3(-0.86 + float(index) * 0.23, 1.42 + float(index % 2) * 0.21, -0.935),
			Vector3.BACK,
			index,
		)
	manager.spawn_blood_impact(Vector3(0.72, 1.54, -0.76), Vector3.FORWARD, 3)
	for index in range(3):
		manager.spawn_blood_decal(
			Vector3(0.57 + float(index) * 0.17, 1.48 - float(index) * 0.13, -0.935),
			Vector3.BACK,
			index,
		)
	manager.spawn_decal(
		"scorch1",
		Vector3(0.0, 0.62, -0.935),
		Vector3.BACK,
		"scorch",
		0,
	)
	manager.advance_tick(3)

	output_root = ProjectSettings.globalize_path("res://artifacts")
	DirAccess.make_dir_recursive_absolute(output_root)
	var impacts_ok := await _capture("protocol47-combat-vfx-impacts.png")

	# Fixture 2: a fresh manager contains only the HE event. The event is raised
	# enough above the capture floor to inspect the complete authored sprite
	# silhouette; production placement still uses the authoritative trace point.
	_reset_manager(stage)
	camera.global_position = Vector3(0.0, 1.85, 3.1)
	camera.look_at_from_position(camera.global_position, Vector3(0.0, 1.62, -0.25), Vector3.UP)
	manager.spawn_he_explosion(Vector3(0.0, 1.45, -0.25), Vector3.UP)
	for child in manager.get_children():
		if child.name.begins_with("GoldSrcDecal_"):
			child.visible = false
	manager.advance_tick(8)
	var explosion_ok := await _capture("protocol47-combat-vfx-explosion.png")

	# Fixture 3: render the exact delayed HE smoke temp entity in isolation,
	# without persistent decals, blood, impact particles, or fireballs.
	_reset_manager(stage)
	camera.global_position = Vector3(0.0, 1.62, 3.1)
	camera.look_at_from_position(camera.global_position, Vector3(0.0, 1.38, -0.25), Vector3.UP)
	manager._spawn_sprite(
		"steam1",
		Vector3(0.0, 1.38, -0.25),
		3.5,
		5.0,
		CombatEffects.EVENT_HE_SMOKE,
	)
	# Frame 9 (1.8 seconds into the 5 fps source animation) exposes the soft,
	# dissipating index-alpha structure rather than only its dense white birth.
	manager.advance_tick(180)
	var smoke_ok := await _capture("protocol47-combat-vfx-smoke.png")

	if impacts_ok and explosion_ok and smoke_ok:
		print("GAME_COMBAT_EFFECTS_CAPTURE_PASS")
		stage.free()
		quit(0)
	else:
		stage.free()
		quit(1)
