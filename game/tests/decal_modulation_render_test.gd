extends SceneTree

## A multiply decal operates on the already-lit destination. Its white surround
## must be identity, regardless of incident light. No frame-time claim here.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _capture() -> Image:
	var before := Engine.get_frames_drawn()
	for frame in 4:
		await process_frame
	_check(Engine.get_frames_drawn() - before >= 3, "capture requires actual drawn frames")
	return root.get_texture().get_image()


func _texture(color: Color) -> ImageTexture:
	var pixels := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	pixels.fill(color)
	return ImageTexture.create_from_image(pixels)


func _changed_pixels(first: Image, second: Image) -> int:
	if first.get_size() != second.get_size():
		_check(false, "capture dimensions must remain stable")
		return -1
	var count := 0
	# Interior of the 2 m decal under the 3 m-high orthographic view.
	# Use actual texture dimensions: project stretch can letterbox the window.
	var center := first.get_size() / 2
	var half_extent := int(first.get_height() / 3.0) - 5
	_check(half_extent > 20, "decal capture must have usable resolution")
	for y in range(center.y - half_extent, center.y + half_extent):
		for x in range(center.x - half_extent, center.x + half_extent):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 1.0 / 255.0:
				count += 1
	return count


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Decal modulation regression requires real rendering")
		quit(1)
		return
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	root.size = Vector2i(320, 240)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.2, 0.2, 0.2)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	world.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stage.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 3.0
	camera.position.z = 3.0
	stage.add_child(camera)
	camera.make_current()
	var wall := MeshInstance3D.new()
	wall.mesh = QuadMesh.new()
	wall.mesh.size = Vector2(4.0, 3.0)
	var wall_material := StandardMaterial3D.new()
	wall_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_material.albedo_color = Color(0.55, 0.4, 0.3)
	wall.mesh.material = wall_material
	stage.add_child(wall)
	var effects := CS16CombatEffects.new()
	stage.add_child(effects)
	var white := _texture(Color.WHITE)
	var samples: Array[Dictionary] = []
	var renderer := RenderingServer.get_current_rendering_method()
	for case_index in 6:
		var family: String = ["shot", "blood", "scorch"][case_index % 3]
		root.use_hdr_2d = case_index >= 3
		var decal := effects.spawn_decal(family + "1", Vector3.ZERO, Vector3.BACK, family) as MeshInstance3D
		_check(decal != null, "production decal must exist: " + family)
		if decal == null:
			continue
		# Only enlarge/orient the test stamp for pixel inspection. Keep production
		# material, texture, blend and filtering until the explicit white control.
		decal.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.02))
		(decal.mesh as QuadMesh).size = Vector2(2.0, 2.0)
		var material := decal.mesh.surface_get_material(0) as StandardMaterial3D
		var source := material.albedo_texture
		for energy in [0.0, 0.25, 1.0]:
			world.environment.ambient_light_energy = energy
			decal.hide()
			var baseline := await _capture()
			decal.show()
			material.albedo_texture = white
			var identity := await _capture()
			var white_changes := _changed_pixels(baseline, identity)
			_check(white_changes == 0, "%s white mask must preserve the lit destination at energy=%s (pixels=%d)" % [family, energy, white_changes])
			material.albedo_texture = source
			var actual := await _capture()
			var authored_changes := _changed_pixels(baseline, actual)
			_check(authored_changes > 15, "%s authored marks must remain visible" % family)
			# Negative control: a separately lit multiply mask must be detected.
			var negative := material.duplicate() as StandardMaterial3D
			negative.albedo_texture = white
			negative.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			decal.material_override = negative
			var legacy := await _capture()
			decal.material_override = null
			var negative_changes := _changed_pixels(baseline, legacy)
			if energy == 0.0:
				_check(negative_changes > 1000, "negative control must detect double lighting")
			if family == "blood" and energy == 0.25:
				_check(actual.save_png("/tmp/protocol47-decal-%s-hdr-%s.png" % [renderer, root.use_hdr_2d]) == OK, "save decal capture")
			samples.append({"family": family, "ambient_energy": energy, "hdr_2d": root.use_hdr_2d,
				"baseline_center": str(baseline.get_pixelv(baseline.get_size() / 2)),
				"white_center": str(identity.get_pixelv(identity.get_size() / 2)),
				"white_changed_pixels": white_changes, "authored_changed_pixels": authored_changes,
				"negative_changed_pixels": negative_changes})
		decal.queue_free()
		await process_frame
	var report := {"ok": failures.is_empty(), "audio_muted": true, "renderer": renderer,
		"performance_measured": false, "samples": samples, "failures": failures}
	var path := "res://artifacts/decal-modulation-%s-report.json" % renderer
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "open decal report")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("DECAL_MODULATION ", JSON.stringify(report))
	stage.queue_free()
	await process_frame
	CS16CombatEffects.release_cached_resources()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_DECAL_MODULATION_PASS")
	quit(0 if failures.is_empty() else 1)
