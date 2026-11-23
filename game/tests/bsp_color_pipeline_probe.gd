extends SceneTree

## Rendered material color-contract regression, not original-engine fidelity.
## CPU values are independent of the production shader. A legacy shader checks
## unchanged Compatibility pixels and detects the former linear-backend bug.
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
	_check(Engine.get_frames_drawn() - before >= 3, "each capture must draw frames")
	return root.get_texture().get_image()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("BSP color regression requires real rendering")
		quit(1)
		return
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	root.size = Vector2i(320, 240)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.2, 0.05, 0.3)
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position.z = 3.0
	stage.add_child(camera)
	camera.make_current()
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.mesh.size = Vector2(2.0, 2.0)
	stage.add_child(quad)
	quad.hide()
	var background := await _capture()
	quad.show()
	var inputs := [
		[Color8(120, 100, 80), Color8(40, 60, 25)],
		[Color8(180, 140, 90), Color8(110, 110, 64)],
		[Color8(240, 230, 210), Color8(240, 240, 128)],
		[Color.RED, Color8(0, 120, 255)],
		[Color.GREEN, Color8(255, 0, 120)],
		[Color.BLUE, Color8(120, 255, 0)],
	]
	for value in [0, 1, 10, 32, 128, 254, 255]:
		inputs.append([Color8(value, value, value), Color8(value, value, value)])
	var linear_backend := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var draws_before := Engine.get_frames_drawn()
	var samples := []
	var negative_pixels := 0
	for masked in [false, true]:
		var code := BspMap.LIGHTMAP_CUTOUT_SHADER_SOURCE if masked else BspMap.LIGHTMAP_SHADER_SOURCE
		var shader := Shader.new()
		shader.code = code
		var expression := "bsp_output_color(goldsrc_texture_wash(albedo.rgb) * goldsrc_light(UV2))"
		_check(code.count(expression) == 1, "test must replace exactly one output expression")
		var reference_shader := Shader.new()
		# Retain the unchanged alpha mask, but bypass color math/RGB sampling
		# with an independently calculated CPU uniform.
		reference_shader.code = code.replace("void fragment()", "uniform vec3 reference_color;\nvoid fragment()").replace(expression, "reference_color")
		var legacy_shader := Shader.new()
		legacy_shader.code = code.replace("albedo_tex : filter", "albedo_tex : source_color, filter").replace(expression, "goldsrc_texture_wash(albedo.rgb) * goldsrc_light(UV2)")
		for index in inputs.size():
			var albedo: Color = inputs[index][0]
			var luxel: Color = inputs[index][1]
			var encoded := _encoded_product(albedo, luxel)
			var shader_value := encoded.srgb_to_linear() if linear_backend else encoded
			var texture := _texture(albedo, masked)
			var lightmap := _texture(luxel, false)
			quad.material_override = _material(shader, texture, lightmap)
			var actual := await _capture()
			var reference_material := _material(reference_shader, texture, lightmap)
			reference_material.set_shader_parameter("reference_color", Vector3(shader_value.r, shader_value.g, shader_value.b))
			quad.material_override = reference_material
			var reference := await _capture()
			quad.material_override = _material(legacy_shader, texture, lightmap)
			var legacy := await _capture()
			var mismatch := _different_pixels(actual, reference)
			var legacy_mismatch := _different_pixels(actual, legacy)
			var visible := _different_pixels(actual, background)
			_check(mismatch == 0, "case %d masked=%s must match independent numerical color" % [index, masked])
			_check(visible > 1000, "case %d masked=%s must be visible" % [index, masked])
			if not linear_backend:
				_check(legacy_mismatch == 0, "Compatibility pixels must match the original shader")
			elif index < 3:
				_check(legacy_mismatch > 1000, "negative control must detect the previous Metal color pipeline")
			negative_pixels += legacy_mismatch
			samples.append({"case": index, "masked": masked, "albedo": _channels(albedo),
				"luxel": _channels(luxel), "encoded_product": _channels(encoded),
				"reference_mismatch_pixels": mismatch, "legacy_mismatch_pixels": legacy_mismatch,
				"visible_pixels": visible})
			if index == 1:
				var capture_path := "/tmp/protocol47-bsp-color-%s-%s.png" % [RenderingServer.get_current_rendering_method(), "masked" if masked else "opaque"]
				_check(actual.save_png(capture_path) == OK, "save representative color capture")
	var report := {"ok": failures.is_empty(), "renderer": RenderingServer.get_current_rendering_method(),
		"samples": samples, "legacy_mismatch_pixels": negative_pixels,
		"rendered_frames": Engine.get_frames_drawn() - draws_before,
		"original_engine_fidelity_verified": false, "audio_muted": true,
		"finished_at_utc": Time.get_datetime_string_from_system(true)}
	var report_path := "res://artifacts/bsp-color-%s-report.json" % RenderingServer.get_current_rendering_method()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	_check(file != null, "open color regression report")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("BSP_COLOR_PIPELINE ", JSON.stringify(report))
	stage.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_BSP_COLOR_PIPELINE_PROBE_PASS")
	quit(0 if failures.is_empty() else 1)


static func _material(shader: Shader, albedo: Texture2D, lightmap: Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_tex", albedo)
	material.set_shader_parameter("lightmap_tex", lightmap)
	return material


static func _texture(color: Color, masked: bool) -> ImageTexture:
	var pixels := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	pixels.fill(color)
	if masked:
		var transparent := color
		transparent.a = 0.0
		pixels.set_pixel(0, 0, transparent)
		pixels.set_pixel(0, 1, transparent)
	return ImageTexture.create_from_image(pixels)


static func _encoded_product(albedo: Color, luxel: Color) -> Color:
	var values := [pow(luxel.r, 0.92) * 1.72, pow(luxel.g, 0.92) * 1.72, pow(luxel.b, 0.92) * 1.72]
	var luma: float = values[0] * 0.299 + values[1] * 0.587 + values[2] * 0.114
	var tint := [1.03, 0.985, 0.965]
	var floor_tint := [0.30, 0.24, 0.175]
	var channels := [albedo.r, albedo.g, albedo.b]
	for channel in 3:
		var light: float = lerpf(values[channel], luma, 0.42) * tint[channel]
		light = minf(light, 0.82) + (1.0 - exp(-maxf(light - 0.82, 0.0) / 0.15)) * 0.13
		light += floor_tint[channel] * exp(-light / 0.16)
		channels[channel] = pow(channels[channel], 0.90) * pow(light, 2.2)
	return Color(channels[0], channels[1], channels[2])


static func _channels(color: Color) -> Array:
	return [color.r, color.g, color.b]


static func _different_pixels(first: Image, second: Image) -> int:
	var count := 0
	for y in first.get_height():
		for x in first.get_width():
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 2.0 / 255.0:
				count += 1
	return count
