extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _capture() -> Image:
	var draws_before := Engine.get_frames_drawn()
	for frame in range(4):
		await process_frame
	_check(Engine.get_frames_drawn() - draws_before >= 3, "each capture must render rather than run occluded")
	return root.get_texture().get_image()


func _different_pixels(first: Image, second: Image) -> int:
	var count := 0
	for y in first.get_height():
		for x in first.get_width():
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 2.0 / 255.0:
				count += 1
	return count


func _viewmodel(camera: Camera3D) -> MdlViewModel:
	var result := MdlViewModel.new()
	camera.add_child(result)
	result.set_process(false)
	return result


func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	if DisplayServer.get_name() == "headless":
		push_error("Viewmodel pixel regression requires a rendered window")
		quit(1)
		return
	root.size = Vector2i(640, 480)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.12, 0.14, 0.16)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.7
	stage.add_child(world)
	var camera := Camera3D.new()
	camera.fov = 90.0
	camera.near = 0.02
	stage.add_child(camera)
	camera.make_current()
	var draws_before := Engine.get_frames_drawn()
	var background := await _capture()
	var model := _viewmodel(camera)
	_check(model.load_weapon("ak47"), "initial AK loads")
	model._process(0.01)
	var original := await _capture()
	model.load_weapon("knife")
	model._process(0.01)
	var knife := await _capture()
	model.load_weapon("ak47")
	_check(bool(model.last_load_timings.reused_model), "pixel comparison exercises model restoration")
	model._process(0.01)
	var restored := await _capture()
	model.load_weapon("knife")
	model._process(0.01)
	world.environment.ambient_light_color = Color(0.4, 0.65, 1.0)
	model.load_weapon("ak47")
	# Negative control: returning a cached material without refreshing its
	# location-dependent tint would leave it shaded for the previous scene.
	model._light_timer = 0.0
	model._light_snap = false
	model._process(0.01)
	var stale_tint := await _capture()
	model._light_timer = INF
	model._light_snap = true
	model._start_animation(model._idle_animation(), true)
	model._process(0.01)
	var relit := await _capture()
	model.hide()
	var fresh := _viewmodel(camera)
	fresh.load_weapon("ak47")
	fresh._process(0.01)
	var reference := await _capture()
	var drawn := Engine.get_frames_drawn() - draws_before
	var weapon_pixels := _different_pixels(original, background)
	var switched_pixels := _different_pixels(original, knife)
	var restore_mismatch := _different_pixels(original, restored)
	var tint_mismatch := _different_pixels(relit, reference)
	var stale_mismatch := _different_pixels(stale_tint, reference)
	_check(drawn >= 26, "captures must draw frames, not run occluded simulation")
	_check(weapon_pixels > 100 and switched_pixels > 100, "weapon and switch must be visibly measurable")
	_check(restore_mismatch == 0, "restored weapon pixels match its original presentation")
	_check(tint_mismatch == 0, "restored weapon matches fresh construction under changed lighting")
	_check(stale_mismatch > 100, "negative control detects stale cached lighting")
	_check(restored.save_png("/tmp/protocol47-viewmodel-restored.png") == OK, "save restored weapon capture")
	_check(reference.save_png("/tmp/protocol47-viewmodel-relit-reference.png") == OK, "save relit reference capture")
	var report := {"ok": failures.is_empty(), "audio_muted": true, "rendered_frames": drawn,
		"weapon_pixels": weapon_pixels, "switched_pixels": switched_pixels,
		"restore_mismatch_pixels": restore_mismatch, "tint_mismatch_pixels": tint_mismatch,
		"stale_tint_mismatch_pixels": stale_mismatch,
		"renderer": RenderingServer.get_current_rendering_method(),
		"finished_at_utc": Time.get_datetime_string_from_system(true)}
	fresh.hide()
	report.prepared_geometry_cases = await _check_prepared_geometry(camera)
	report.ok = failures.is_empty()
	report.rendered_frames = Engine.get_frames_drawn() - draws_before
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var file := FileAccess.open("res://artifacts/viewmodel-residency-render-report.json", FileAccess.WRITE)
	_check(file != null, "open rendered residency report")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("VIEWMODEL_RESIDENCY_RENDER ", JSON.stringify(report))
	stage.queue_free()
	await process_frame
	MdlViewModel.release_cached_resources()
	MdlCharacterModel.release_cached_resources()
	for failure: String in failures:
		push_error(failure)
	print("GAME_VIEWMODEL_RESIDENCY_RENDER_PASS" if failures.is_empty() else "GAME_VIEWMODEL_RESIDENCY_RENDER_FAIL")
	quit(0 if failures.is_empty() else 1)


func _check_prepared_geometry(camera: Camera3D) -> Array:
	var results: Array = []
	for weapon: String in ["m4a1", "knife", "ak47"]:
		_check(not MdlViewModel._prepared_weapon_assets.has(weapon), "reference precedes catalog preparation")
		var background := await _capture()
		var reference := _viewmodel(camera)
		_check(reference.load_weapon(weapon), "unprepared reference loads")
		var animation := "shoot1" if reference._template.animations.has("shoot1") else reference._idle_animation()
		reference._start_animation(animation, false)
		reference._process(0.01)
		_check(not bool(reference._cached_frame(animation, 0).prepared_geometry), "reference exercises uncached geometry construction")
		var expected := await _capture()
		var before_mesh := reference._model_instance.mesh
		_check(await reference.prepare_weapon_assets([weapon]), "first-frame geometry preparation succeeds")
		_check(reference._model_instance.mesh == before_mesh, "preparation leaves visible mesh unchanged")
		reference.hide()
		var candidate := _viewmodel(camera)
		_check(candidate.load_weapon(weapon), "prepared candidate loads")
		candidate._start_animation(animation, false)
		candidate._process(0.01)
		_check(bool(candidate._cached_frame(animation, 0).prepared_geometry), "pixel candidate uses prepared geometry")
		var actual := await _capture()
		# Wrong handedness must be visible to this capture. This also checks the
		# right-hand-authored knife separately from normally mirrored firearms.
		candidate._model_instance.basis = candidate._model_instance.basis.scaled(Vector3(1, 1, -1))
		var negative := await _capture()
		var mismatch := _different_pixels(actual, expected)
		var visible_pixels := _different_pixels(expected, background)
		var negative_pixels := _different_pixels(expected, negative)
		_check(mismatch == 0, "prepared geometry matches unprepared pixels: " + weapon)
		_check(visible_pixels > 100 and negative_pixels > 100, "prepared pose comparison has visible geometry and handedness negative control")
		results.append({"weapon": weapon, "mismatch_pixels": mismatch, "visible_pixels": visible_pixels,
			"wrong_hand_pixels": negative_pixels})
		candidate.free()
		reference.free()
	return results
