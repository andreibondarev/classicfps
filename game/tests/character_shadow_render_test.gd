extends SceneTree

## Rendered regression: the actor is beside the camera view but its moving shadow
## falls on a visible receiver. Compare the optimized pose with forced sampling.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _capture() -> Image:
	# Allow transform and shadow-atlas updates to reach the rendered frame.
	for frame in range(4):
		await process_frame
	return root.get_texture().get_image()


func _different_pixels(first: Image, second: Image) -> int:
	var count := 0
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 2.0 / 255.0:
				count += 1
	return count


func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	if DisplayServer.get_name() == "headless":
		push_error("Shadow pixel regression requires a rendered window")
		quit(1)
		return
	root.size = Vector2i(640, 480)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.2, 0.2, 0.2)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.25
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.far = 50.0
	stage.add_child(camera)
	camera.position = Vector3(0, 2, 0)
	camera.look_at(Vector3(0, 0, -8))
	camera.make_current()
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.7, 0.7)
	material.roughness = 1.0
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	floor_mesh.position.z = -8
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_bias = 0.01
	sun.shadow_normal_bias = 0.0
	sun.directional_shadow_max_distance = 50.0
	stage.add_child(sun)
	sun.look_at(Vector3(-1, -0.25, 0))
	var actor := Node3D.new()
	stage.add_child(actor)
	actor.position = Vector3(12, 3, -5)
	var model := MdlCharacterModel.new()
	actor.add_child(model)
	model.set_process(false)
	_check(model.load_character("terror", "ak47"), "shadow fixture model loads")
	model.set_locomotion(true)
	_check(not MdlCharacterModel._sphere_intersects_frustum(model.global_position + Vector3.UP * 0.4, 2.0, camera.get_frustum()), "actor bounds must be outside the camera")
	_check(model._pose_may_be_visible(), "visible projected shadow must keep animation active")
	model._process(0.0)
	var draws_before := Engine.get_frames_drawn()
	var initial := await _capture()
	model._process(0.25)
	var animated := await _capture()
	# Independent unconditional mesh submission at the same authoritative time.
	model._body_frame_key = ""
	model._weapon_frame_key = ""
	model.advance_animation(0.0, true)
	var reference := await _capture()
	# Exercise the in-place load used by team/class changes, including a corpse
	# and detached gun that would remain visible if old owners were retained.
	_check(model.load_character("urban", "mp5"), "replacement shadow model loads")
	model.play_death()
	model.advance_animation(0.75, true)
	var replaced := await _capture()
	_check(model.load_character("terror", "ak47"), "original shadow model reloads")
	model.set_locomotion(true)
	model._process(0.25)
	var reloaded := await _capture()
	# Negative control reproduces the old frustum-only behavior: the clock
	# advances but neither body nor attached weapon submits the new pose.
	model.reset_animation()
	model.set_locomotion(true)
	model._process(0.0)
	model.advance_animation(0.25, false)
	var stale := await _capture()
	model.hide()
	var without_caster := await _capture()
	var shadow_pixels := _different_pixels(reference, without_caster)
	var moving_pixels := _different_pixels(initial, animated)
	var mismatch_pixels := _different_pixels(animated, reference)
	var stale_mismatch_pixels := _different_pixels(stale, reference)
	var replacement_pixels := _different_pixels(replaced, reference)
	var reload_mismatch_pixels := _different_pixels(reloaded, reference)
	var rendered_frames := Engine.get_frames_drawn() - draws_before
	_check(rendered_frames >= 26, "capture must draw frames, not run occluded simulation")
	_check(shadow_pixels > 20, "offscreen actor must cast a measurable visible shadow")
	_check(moving_pixels > 20, "visible shadow must change with the offscreen animation")
	_check(mismatch_pixels == 0, "optimized shadow must match unconditional pose rendering")
	_check(stale_mismatch_pixels > 20, "negative control must detect the former frozen-shadow behavior")
	_check(replacement_pixels > 20, "replacement corpse must visibly change the shadow")
	_check(reload_mismatch_pixels == 0, "reloaded character shadow must match fresh presentation")
	_check(initial.save_png("/tmp/protocol47-shadow-before.png") == OK, "save initial shadow capture")
	_check(animated.save_png("/tmp/protocol47-shadow-after.png") == OK, "save animated shadow capture")
	var report := {
		"ok": failures.is_empty(), "renderer": RenderingServer.get_current_rendering_method(),
		"shadow_pixels": shadow_pixels, "moving_pixels": moving_pixels,
		"mismatch_pixels": mismatch_pixels, "stale_mismatch_pixels": stale_mismatch_pixels,
		"replacement_pixels": replacement_pixels, "reload_mismatch_pixels": reload_mismatch_pixels,
		"rendered_frames": rendered_frames, "audio_muted": true,
		"finished_at_utc": Time.get_datetime_string_from_system(true),
	}
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var report_file := FileAccess.open("res://artifacts/shadow-render-test-report.json", FileAccess.WRITE)
	_check(report_file != null, "open rendered shadow report")
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "  "))
		report_file.close()
	print("CHARACTER_SHADOW_RENDER ", JSON.stringify(report))
	stage.queue_free()
	await process_frame
	MdlCharacterModel.release_cached_resources()
	for failure: String in failures:
		push_error(failure)
	print("GAME_CHARACTER_SHADOW_RENDER_PASS" if failures.is_empty() else "GAME_CHARACTER_SHADOW_RENDER_FAIL")
	quit(0 if failures.is_empty() else 1)
