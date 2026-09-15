extends SceneTree

const Model := preload("res://scripts/mdl_character_model.gd")
const Sampler := preload("res://scripts/mdl_pose_sampler.gd")
# One micrometre: 100 times tighter than the existing source-quantization
# tolerance. Vector math rounds at real_t precision rather than double scalars.
const MAX_ERROR_M := 0.000001
var failures: Array[String] = []
var vertices_checked := 0
var max_error := 0.0
var samples := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var paths: Array[String] = []
	for skin in ["terror", "leet", "arctic", "guerilla", "urban", "gsg9", "sas", "gign"]:
		paths.append("res://generated/players/%s/model.json" % skin)
	for weapon in DirAccess.get_directories_at("res://generated/player_weapons"):
		paths.append("res://generated/player_weapons/%s/model.json" % weapon)
	paths.append("res://generated/hostages/hostage/model.json")
	for path in paths:
		_check_template(path)
	_check_subranges_and_overlay()
	_profile_composition()
	_profile_bounds()
	if DisplayServer.get_name() != "headless":
		await _check_rendered_reference()
	print("ANIMATION_POSE_SAMPLER ", JSON.stringify({"templates": paths.size(), "samples": samples,
		"vertices_checked": vertices_checked, "max_error_m": max_error}))
	Model.release_cached_resources()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("GAME_ANIMATION_POSE_SAMPLER_PASS" if failures.is_empty() else "GAME_ANIMATION_POSE_SAMPLER_FAIL")
	quit(0 if failures.is_empty() else 1)


func _profile_bounds() -> void:
	var template := Model._load_template("res://generated/players/terror/model.json")
	var animation: Dictionary = template.animations.shoot
	var vertices := Sampler.sample(animation.positions, 0, int(template.vertex_float_count) / 3,
		0, 0, int(template.vertex_float_count), int(template.vertex_float_count), 0.37, 0.0)
	var started := Time.get_ticks_usec()
	var exact := AABB()
	for query in 200:
		exact = AABB(vertices[0], Vector3.ZERO)
		for vertex in vertices:
			exact = exact.expand(vertex)
	var scan_us := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var cached := AABB()
	for query in 200:
		cached = Sampler.interpolated_bounds(animation.pose_bounds, 0, 0, 1, 1, 0.37, 0.0)
	var cached_us := Time.get_ticks_usec() - started
	_check(cached.encloses(exact), "profiled source bounds enclose the independently scanned pose")
	print("ANIMATION_CULLING_BOUNDS_CPU ", JSON.stringify({"queries": 200,
		"vertex_scan_us": scan_us, "source_bounds_us": cached_us,
		"source_pose_count": animation.pose_bounds.size()}))


func _check_template(path: String) -> void:
	var template := Model._load_template(path)
	_check(not template.is_empty(), "source template loads: " + path)
	if template.is_empty():
		return
	for state: String in template.animations:
		var animation: Dictionary = template.animations[state]
		var count := int(animation.frames)
		for frame: int in [0, count / 2, count - 1]:
			var a := Model._pose_float_offset(template, animation, frame, 0)
			var b := Model._pose_float_offset(template, animation, frame, int(animation.blends) - 1)
			var c := Model._pose_float_offset(template, animation, (frame + 1) % count, 0)
			var d := Model._pose_float_offset(template, animation, (frame + 1) % count, int(animation.blends) - 1)
			for alpha: float in [0.0, 0.37, 1.0]:
				for pitch: float in [0.0, 0.61, 1.0]:
					var culling := Sampler.interpolated_bounds(animation.pose_bounds,
						a / int(template.vertex_float_count), b / int(template.vertex_float_count),
						c / int(template.vertex_float_count), d / int(template.vertex_float_count), alpha, pitch)
					for group: Dictionary in template.groups:
						_compare(animation.positions, int(group.start), int(group.count), a, b, c, d, alpha, pitch, {}, culling)
	if template.has("lower_mask"):
		_check_source_overlays(template)


func _check_source_overlays(template: Dictionary) -> void:
	for state: String in ["shoot", "crouchshoot"]:
		if not template.animations.has(state):
			continue
		var animation: Dictionary = template.animations[state]
		var frames := int(animation.frames)
		var a := Model._pose_float_offset(template, animation, 0, 0)
		var b := Model._pose_float_offset(template, animation, 0, int(animation.blends) - 1)
		var c := Model._pose_float_offset(template, animation, frames - 1, 0)
		var d := Model._pose_float_offset(template, animation, frames - 1, int(animation.blends) - 1)
		for gait_state: String in ["idle", "run", "crouchidle", "crouchrun"]:
			if not template.animations.has(gait_state):
				continue
			var gait: Dictionary = template.animations[gait_state]
			for alpha: float in [0.0, 0.37, 1.0]:
				var overlay := {"mask": template.lower_mask, "positions": gait.positions,
					"current_offset": Model._pose_float_offset(template, gait, 0, 0),
					"next_offset": Model._pose_float_offset(template, gait, int(gait.frames) - 1, 0),
					"frame_alpha": alpha}
				for pitch: float in [0.0, 0.61, 1.0]:
					var culling := Sampler.interpolated_bounds(animation.pose_bounds,
						a / int(template.vertex_float_count), b / int(template.vertex_float_count),
						c / int(template.vertex_float_count), d / int(template.vertex_float_count), alpha, pitch)
					culling = culling.merge(Sampler.interpolated_bounds(gait.pose_bounds,
						0, 0, int(gait.frames) - 1, int(gait.frames) - 1, alpha, 0.0))
					for group: Dictionary in template.groups:
						_compare(animation.positions, int(group.start), int(group.count), a, b, c, d, alpha, pitch, overlay, culling)


func _compare(p: PackedFloat32Array, start: int, count: int, a: int, b: int, c: int, d: int,
		alpha: float, pitch: float, overlay: Dictionary = {}, culling_bounds: Variant = null) -> void:
	var actual := Sampler.sample(p, start, count, a, b, c, d, alpha, pitch, overlay)
	_check(actual.size() == count, "surface vertex count stays exact")
	if not overlay.is_empty():
		_check(actual == _two_pass_sample(p, start, count, a, b, c, d, alpha, pitch, overlay),
			"fused composition is bit-identical to the previous two-pass vector sampler")
	samples += 1
	for index in count:
		if culling_bounds != null:
			_check((culling_bounds as AABB).has_point(actual[index]), "conservative source bounds contain every interpolated/composited vertex")
		var source := (start + index) * 3
		var expected := Vector3(
			lerpf(lerpf(p[a + source], p[b + source], pitch), lerpf(p[c + source], p[d + source], pitch), alpha),
			lerpf(lerpf(p[a + source + 1], p[b + source + 1], pitch), lerpf(p[c + source + 1], p[d + source + 1], pitch), alpha),
			lerpf(lerpf(p[a + source + 2], p[b + source + 2], pitch), lerpf(p[c + source + 2], p[d + source + 2], pitch), alpha))
		if not overlay.is_empty() and overlay.mask[start + index] != 0:
			var op: PackedFloat32Array = overlay.positions
			var oa := int(overlay.current_offset) + source
			var ob := int(overlay.next_offset) + source
			expected = Vector3(lerpf(op[oa], op[ob], overlay.frame_alpha),
				lerpf(op[oa + 1], op[ob + 1], overlay.frame_alpha), lerpf(op[oa + 2], op[ob + 2], overlay.frame_alpha))
		max_error = maxf(max_error, actual[index].distance_to(expected))
		vertices_checked += 1
	_check(max_error <= MAX_ERROR_M, "source interpolation stays within one micrometre")


static func _two_pass_sample(p: PackedFloat32Array, start: int, count: int, a: int, b: int, c: int, d: int,
		alpha: float, pitch: float, overlay: Dictionary) -> PackedVector3Array:
	var base := Sampler.sample(p, start, count, a, b, c, d, alpha, pitch)
	var lower := Sampler.sample(overlay.positions, start, count,
		int(overlay.current_offset), int(overlay.current_offset),
		int(overlay.next_offset), int(overlay.next_offset), float(overlay.frame_alpha), 0.0)
	for index in count:
		if overlay.mask[start + index] != 0:
			base[index] = lower[index]
	return base


func _profile_composition() -> void:
	var template := Model._load_template("res://generated/players/terror/model.json")
	var animation: Dictionary = template.animations.shoot
	var gait: Dictionary = template.animations.run
	var overlay := {"mask": template.lower_mask, "positions": gait.positions,
		"current_offset": Model._pose_float_offset(template, gait, 3, 0),
		"next_offset": Model._pose_float_offset(template, gait, 4, 0), "frame_alpha": 0.29}
	var args := [animation.positions, 0, int(template.vertex_float_count) / 3,
		Model._pose_float_offset(template, animation, 0, 0),
		Model._pose_float_offset(template, animation, 0, int(animation.blends) - 1),
		Model._pose_float_offset(template, animation, 1, 0),
		Model._pose_float_offset(template, animation, 1, int(animation.blends) - 1), 0.37, 0.61, overlay]
	var measurements := {}
	# Diagnostic only: no noisy wall-clock timing assertion in the correctness gate.
	for candidate: Callable in [Sampler.sample, _two_pass_sample]:
		candidate.callv(args)
		var started := Time.get_ticks_usec()
		for query in 200:
			candidate.callv(args)
		measurements[str(candidate.get_method()) + "_us"] = Time.get_ticks_usec() - started
	print("POSE_COMPOSITION_CPU ", JSON.stringify(measurements))


func _check_subranges_and_overlay() -> void:
	var p := PackedFloat32Array()
	for index in 72:
		p.append(sin(float(index)) * 0.8)
	var overlay := {"mask": PackedByteArray([0, 1, 0, 1, 1, 0]), "positions": p,
		"current_offset": 36, "next_offset": 54, "frame_alpha": 0.29}
	for start in 6:
		_compare(p, start, 6 - start, 0, 18, 36, 54, 0.37, 0.61, overlay)
	for mask in [PackedByteArray([0, 0, 0, 0, 0, 0]), PackedByteArray([1, 1, 1, 1, 1, 1]), overlay.mask]:
		overlay.mask = mask
		for alpha: float in [0.0, 0.37, 1.0]:
			for pitch: float in [0.0, 0.61, 1.0]:
				for overlay_alpha: float in [0.0, 0.29, 1.0]:
					overlay.frame_alpha = overlay_alpha
					_compare(p, 1, 4, 0, 18, 36, 54, alpha, pitch, overlay)
		overlay.next_offset = overlay.current_offset
		_compare(p, 1, 4, 0, 0, 0, 0, 0.37, 0.61, overlay)
		overlay.next_offset = 54
	_compare(p, 0, 0, 0, 18, 36, 54, 0.37, 0.61, overlay)
	_compare(p, 0, 0, 0, 18, 36, 54, 0.37, 0.61)
	var original_stride := Sampler._vector3_byte_stride
	Sampler._vector3_byte_stride = 24
	_compare(p, 1, 4, 0, 18, 36, 54, 0.37, 0.61, overlay)
	Sampler._vector3_byte_stride = original_stride
	var saved := Sampler.sample(p, 0, 6, 0, 18, 36, 54, 0.37, 0.61)
	var copy := saved.duplicate()
	var other := Sampler.sample(p, 0, 6, 18, 0, 54, 36, 0.71, 0.2)
	other[0] = Vector3.INF
	_check(saved == copy and p[0] == 0.0, "later samples cannot mutate earlier poses or source storage")


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)


func _check_rendered_reference() -> void:
	root.size = Vector2i(320, 320)
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.make_current()
	var cases := [
		["res://generated/players/terror/model.json", "shoot", 0.61, true],
		["res://generated/player_weapons/ak47/model.json", "shoot", 0.61, false],
		["res://generated/hostages/hostage/model.json", "run", 0.0, false],
	]
	for entry: Array in cases:
		var template := Model._load_template(entry[0])
		var animation: Dictionary = template.animations[entry[1]]
		var a := Model._pose_float_offset(template, animation, 1, 0)
		var b := Model._pose_float_offset(template, animation, 1, int(animation.blends) - 1)
		var c := Model._pose_float_offset(template, animation, 2, 0)
		var d := Model._pose_float_offset(template, animation, 2, int(animation.blends) - 1)
		var overlay := {}
		var culling := Model._animation_culling_bounds(animation, 1, 2, 0.37, 0, int(animation.blends) - 1, float(entry[2]))
		if entry[3]:
			var gait: Dictionary = template.animations.run
			culling = culling.merge(Sampler.interpolated_bounds(gait.pose_bounds, 3, 3, 4, 4, 0.29, 0.0))
			overlay = {"mask": template.lower_mask, "positions": gait.positions,
				"current_offset": Model._pose_float_offset(template, gait, 3, 0),
				"next_offset": Model._pose_float_offset(template, gait, 4, 0), "frame_alpha": 0.29}
		var candidate := MeshInstance3D.new()
		var reference := MeshInstance3D.new()
		var stale := MeshInstance3D.new()
		for actor in [candidate, reference, stale]:
			actor.mesh = ArrayMesh.new()
			stage.add_child(actor)
			actor.hide()
		# Exercise both surface creation and in-place GPU vertex-region updates
		# through the production renderer, not just the standalone sampler.
		Model._render_interpolated_frame(candidate, template, animation.positions, a, b, c, d, 0.0, float(entry[2]), overlay)
		Model._render_interpolated_frame(candidate, template, animation.positions, a, b, c, d, 0.37, float(entry[2]), overlay, culling)
		for group: Dictionary in template.groups:
			var args := [animation.positions, int(group.start), int(group.count), a, b, c, d, 0.37, float(entry[2]), overlay]
			_add_surface(reference.mesh, template, group, _reference_vertices.callv(args))
			args[7] = 0.0
			args[8] = 0.0
			args[9] = {}
			_add_surface(stale.mesh, template, group, _reference_vertices.callv(args))
		var bounds: AABB = reference.mesh.get_aabb()
		var center := bounds.get_center()
		camera.size = maxf(bounds.size.x, bounds.size.y) * 1.3
		camera.position = center + Vector3(0, 0, bounds.size.length() + 1.0)
		camera.look_at(center)
		var background := await _capture()
		candidate.show()
		var actual := await _capture()
		candidate.hide()
		reference.show()
		var expected := await _capture()
		reference.hide()
		stale.show()
		var negative := await _capture()
		var pixels := _different_pixels(actual, expected)
		var visible_pixels := _different_pixels(expected, background)
		var stale_pixels := _different_pixels(expected, negative)
		print("POSE_SAMPLER_RENDER ", JSON.stringify({"path": entry[0], "mismatch_pixels": pixels,
			"visible_pixels": visible_pixels, "stale_pixels": stale_pixels}))
		_check(pixels == 0, "vector pose matches scalar-reference pixels: " + str(entry[0]))
		_check(visible_pixels > 100 and stale_pixels > 20, "rendered pose comparison has visible geometry and a working negative control")
		for actor in [candidate, reference, stale]:
			stage.remove_child(actor)
			actor.queue_free()
	stage.queue_free()
	await process_frame


static func _reference_vertices(p: PackedFloat32Array, start: int, count: int, a: int, b: int, c: int, d: int,
		alpha: float, pitch: float, overlay: Dictionary) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(count)
	for index in count:
		var source := (start + index) * 3
		if not overlay.is_empty() and overlay.mask[start + index] != 0:
			var op: PackedFloat32Array = overlay.positions
			var oa := int(overlay.current_offset) + source
			var ob := int(overlay.next_offset) + source
			result[index] = Vector3(lerpf(op[oa], op[ob], overlay.frame_alpha),
				lerpf(op[oa + 1], op[ob + 1], overlay.frame_alpha), lerpf(op[oa + 2], op[ob + 2], overlay.frame_alpha))
		else:
			result[index] = Vector3(
				lerpf(lerpf(p[a + source], p[b + source], pitch), lerpf(p[c + source], p[d + source], pitch), alpha),
				lerpf(lerpf(p[a + source + 1], p[b + source + 1], pitch), lerpf(p[c + source + 1], p[d + source + 1], pitch), alpha),
				lerpf(lerpf(p[a + source + 2], p[b + source + 2], pitch), lerpf(p[c + source + 2], p[d + source + 2], pitch), alpha))
	return result


static func _add_surface(mesh: ArrayMesh, template: Dictionary, group: Dictionary, vertices: PackedVector3Array) -> void:
	var uv := PackedVector2Array()
	for index in int(group.count):
		var source := (int(group.start) + index) * 2
		uv.append(Vector2(template.uvs[source], template.uvs[source + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, group.material)


func _capture() -> Image:
	for frame in 4:
		await process_frame
	return root.get_texture().get_image()


static func _different_pixels(first: Image, second: Image) -> int:
	var count := 0
	for y in first.get_height():
		for x in first.get_width():
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 2.0 / 255.0:
				count += 1
	return count
