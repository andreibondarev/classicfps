class_name MdlCharacterModel
extends Node3D

# BSP geometry and converted MDL vertices both use 0.01 Godot units for one
# GoldSrc unit. Keeping this at 1.0 preserves the original player-to-map ratio.
const MODEL_SCALE := 1.0
const AIM_PITCH_SCALE := 3.0
const BLEND_KEY_STEPS := 1024.0
const FRAME_KEY_STEPS := 4096.0

static var _template_cache: Dictionary = {}


static func release_cached_resources() -> void:
	# The runtime shares immutable player/weapon meshes across every combatant.
	# Whole-scene teardown (tests and hot reload) owns the matching release.
	_template_cache.clear()


var skin_name := ""
var weapon_name := ""
var model_loaded := false
var animation_state := "idle"
var available_animations: Array[String] = []

var body_instance: MeshInstance3D
var weapon_instance: MeshInstance3D
var _body_template: Dictionary = {}
var _weapon_template: Dictionary = {}
var _animation_time := 0.0
var _action_state := ""
var _action_time := 0.0
var _dead := false
var _moving := false
var _crouched := false
var _grounded := true
var _aim_pitch_degrees := 0.0
var _death_ground_offset := NAN
var _body_frame_key := ""
var _weapon_frame_key := ""
var _flash_material: StandardMaterial3D


func _ready() -> void:
	rotation.y = PI * 0.5
	scale = Vector3.ONE * MODEL_SCALE


func load_character(requested_skin: String, requested_weapon := "ak47") -> bool:
	skin_name = requested_skin
	weapon_name = requested_weapon
	_body_template = _load_template("res://generated/players/%s/model.json" % skin_name)
	if _body_template.is_empty():
		return false
	body_instance = _create_instance("Authentic_%s" % skin_name, _body_template)
	add_child(body_instance)

	var weapon_path := "res://generated/player_weapons/%s/model.json" % weapon_name
	_weapon_template = _load_template(weapon_path)
	if not _weapon_template.is_empty():
		weapon_instance = _create_instance("Attached_%s" % weapon_name, _weapon_template)
		add_child(weapon_instance)

	available_animations.assign(_body_template.animations.keys())
	model_loaded = true
	reset_animation()
	return true


func set_locomotion(moving: bool, crouched := false, grounded := true) -> void:
	_moving = moving
	_crouched = crouched
	_grounded = grounded


func set_aim_pitch(pitch_radians: float) -> void:
	_aim_pitch_degrees = rad_to_deg(pitch_radians)


func play_action(action: String) -> void:
	if _dead:
		return
	var requested := action
	var crouched_action := "crouch%s" % action
	if _crouched and _body_template.animations.has(crouched_action):
		requested = crouched_action
	if not _body_template.animations.has(requested):
		return
	_action_state = requested
	_action_time = 0.0


func play_death() -> void:
	_dead = true
	_action_state = ""
	_animation_time = 0.0
	animation_state = "die"
	_death_ground_offset = NAN
	# Establish the source sequence's first grounded pose immediately. This also
	# freezes the death sequence's initial ground reference before root motion.
	_body_frame_key = _set_frame(
		body_instance,
		_body_template,
		animation_state,
		0.0,
		false,
		"",
	)
	_weapon_frame_key = _set_frame(
		weapon_instance,
		_weapon_template,
		animation_state,
		0.0,
		false,
		"",
	)


func reset_animation() -> void:
	_dead = false
	_moving = false
	_crouched = false
	_grounded = true
	_aim_pitch_degrees = 0.0
	_action_state = ""
	_animation_time = 0.0
	_action_time = 0.0
	_death_ground_offset = NAN
	animation_state = "idle"
	_body_frame_key = ""
	_weapon_frame_key = ""
	_body_frame_key = _set_frame(body_instance, _body_template, "idle", 0.0, true, "")
	_weapon_frame_key = _set_frame(
		weapon_instance,
		_weapon_template,
		"idle",
		0.0,
		true,
		"",
	)


func force_pose(state: String, frame_fraction := 0.0, aim_pitch_degrees := 0.0) -> void:
	## Deterministic source-pose hook for regression captures. It deliberately
	## bypasses transition timing while using the exact production sampler.
	if not model_loaded or not _body_template.animations.has(state):
		return
	_aim_pitch_degrees = aim_pitch_degrees
	animation_state = state
	var animation: Dictionary = _body_template.animations[state]
	var frame_index := mini(
		int(floor(clampf(frame_fraction, 0.0, 1.0) * float(animation.frames - 1))),
		int(animation.frames) - 1,
	)
	var pose_time := float(frame_index) / maxf(float(animation.fps), 1.0)
	_body_frame_key = _set_frame(
		body_instance,
		_body_template,
		state,
		pose_time,
		false,
		"",
	)
	_weapon_frame_key = _set_frame(
		weapon_instance,
		_weapon_template,
		state,
		pose_time,
		false,
		"",
	)


func flash_hit(headshot: bool) -> void:
	if not is_instance_valid(body_instance):
		return
	if not is_instance_valid(_flash_material):
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = (
		Color(1.0, 1.0, 1.0, 0.62)
		if headshot
		else Color(1.0, 0.48, 0.30, 0.48)
	)
	body_instance.material_overlay = _flash_material
	get_tree().create_timer(0.07).timeout.connect(func() -> void:
		if is_instance_valid(body_instance):
			body_instance.material_overlay = null
	)


func _process(delta: float) -> void:
	advance_animation(delta)


func advance_animation(delta: float) -> void:
	## Advances the authoritative animation clock. Tests and fixed-tick gameplay
	## can call this directly; rendering always samples the same continuous time.
	if not model_loaded:
		return
	_animation_time += delta
	var loop := true
	var state_time := _animation_time
	if _dead:
		animation_state = "die"
		loop = false
	elif not _action_state.is_empty():
		animation_state = _action_state
		_action_time += delta
		state_time = _action_time
		loop = false
		var action_meta: Dictionary = _body_template.animations.get(_action_state, {})
		var duration := (
			float(action_meta.frames) / maxf(1.0, float(action_meta.fps))
			if not action_meta.is_empty()
			else 0.0
		)
		if _action_time >= duration:
			_action_state = ""
			_action_time = 0.0
	else:
		animation_state = _locomotion_state()
	_body_frame_key = _set_frame(
		body_instance,
		_body_template,
		animation_state,
		state_time,
		loop,
		_body_frame_key,
	)
	_weapon_frame_key = _set_frame(
		weapon_instance,
		_weapon_template,
		animation_state,
		state_time,
		loop,
		_weapon_frame_key,
	)


func _set_frame(
	instance: MeshInstance3D,
	template: Dictionary,
	state: String,
	time: float,
	loop: bool,
	previous_key: String,
) -> String:
	if not is_instance_valid(instance) or template.is_empty():
		return ""
	var animations: Dictionary = template.animations
	var animation: Dictionary = animations.get(state, {})
	var resolved_state := state
	if animation.is_empty():
		resolved_state = _locomotion_state()
		animation = animations.get(resolved_state, {})
	if animation.is_empty():
		resolved_state = "idle"
		animation = animations.get(resolved_state, {})
	if animation.is_empty():
		return previous_key
	var frame_count := int(animation.frames)
	if frame_count <= 0:
		return previous_key
	var frame_sample := maxf(0.0, time * float(animation.fps))
	var frame_position := maxi(0, int(floor(frame_sample)))
	var frame_alpha := frame_sample - float(frame_position)
	# Accumulated 100 Hz time can land one float ULP below an exact source-frame
	# boundary. Canonicalize that sample so the key and source indices agree.
	if frame_alpha >= 1.0 - 0.5 / FRAME_KEY_STEPS:
		frame_position += 1
		frame_alpha = 0.0
	elif frame_alpha <= 0.5 / FRAME_KEY_STEPS:
		frame_alpha = 0.0
	var frame_index := 0
	var next_frame_index := 0
	if loop:
		frame_index = frame_position % frame_count
		next_frame_index = (frame_index + 1) % frame_count
	else:
		frame_index = mini(frame_position, frame_count - 1)
		next_frame_index = mini(frame_index + 1, frame_count - 1)
		if frame_index == frame_count - 1:
			frame_alpha = 0.0
	var blend_position := _blend_position(animation)
	var blend_low := int(floor(blend_position))
	var blend_high := int(ceil(blend_position))
	var blend_alpha := blend_position - float(blend_low)
	var frame_key := "%s:%d:%d:%d:%d:%d:%d" % [
		resolved_state,
		frame_index,
		next_frame_index,
		int(round(frame_alpha * FRAME_KEY_STEPS)),
		blend_low,
		blend_high,
		int(round(blend_alpha * BLEND_KEY_STEPS)),
	]
	if frame_key == previous_key:
		return previous_key
	_render_interpolated_frame(
		instance,
		template,
		animation.positions,
		_pose_float_offset(template, animation, frame_index, blend_low),
		_pose_float_offset(template, animation, frame_index, blend_high),
		_pose_float_offset(template, animation, next_frame_index, blend_low),
		_pose_float_offset(template, animation, next_frame_index, blend_high),
		frame_alpha,
		blend_alpha,
	)
	if instance == body_instance:
		_align_body_feet(
			animation,
			frame_index,
			next_frame_index,
			frame_alpha,
			blend_low,
			blend_high,
			blend_alpha,
		)
	return frame_key


func _locomotion_state() -> String:
	return (
		"crouchrun"
		if _crouched and _moving
		else "crouchidle"
		if _crouched
		else "run"
		if _moving
		else "idle"
	)


func _blend_position(animation: Dictionary) -> float:
	var blend_count := maxi(1, int(animation.get("blends", 1)))
	if blend_count <= 1 or int(animation.get("blend_type", [0, 0])[0]) != 8:
		return 0.0
	var blend_start := float(animation.get("blend_start", [0.0, 0.0])[0])
	var blend_end := float(animation.get("blend_end", [1.0, 0.0])[0])
	if is_equal_approx(blend_start, blend_end):
		return 0.5 * float(blend_count - 1)
	# GoldSrc StudioPlayerBlend feeds entity pitch * 3 into STUDIO_XR. Godot's
	# positive aim pitch points upward, opposite GoldSrc's positive PITCH.
	var controller := -_aim_pitch_degrees * AIM_PITCH_SCALE
	var normalized := clampf(
		(controller - blend_start) / (blend_end - blend_start),
		0.0,
		1.0,
	)
	return normalized * float(blend_count - 1)


static func _pose_float_offset(
	template: Dictionary,
	animation: Dictionary,
	frame_index: int,
	blend_index: int,
) -> int:
	return (
		(blend_index * int(animation.frames) + frame_index)
		* int(template.vertex_float_count)
	)


func _align_body_feet(
	animation: Dictionary,
	frame_index: int,
	next_frame_index: int,
	frame_alpha: float,
	blend_low: int,
	blend_high: int,
	blend_alpha: float,
) -> void:
	if not _grounded and not _dead:
		return
	var minimum_y := _blended_minimum_y(
		_body_template,
		animation,
		frame_index,
		next_frame_index,
		frame_alpha,
		blend_low,
		blend_high,
		blend_alpha,
	)
	var offset := -minimum_y * MODEL_SCALE
	if _dead:
		if is_nan(_death_ground_offset):
			_death_ground_offset = offset
		position.y = _death_ground_offset
	else:
		position.y = offset


static func _blended_minimum_y(
	template: Dictionary,
	animation: Dictionary,
	frame_index: int,
	next_frame_index: int,
	frame_alpha: float,
	blend_low: int,
	blend_high: int,
	blend_alpha: float,
) -> float:
	var positions: PackedFloat32Array = animation.positions
	var low_offset := _pose_float_offset(template, animation, frame_index, blend_low)
	var high_offset := _pose_float_offset(template, animation, frame_index, blend_high)
	var next_low_offset := _pose_float_offset(
		template,
		animation,
		next_frame_index,
		blend_low,
	)
	var next_high_offset := _pose_float_offset(
		template,
		animation,
		next_frame_index,
		blend_high,
	)
	var minimum_y := INF
	for vertex_float in range(1, int(template.vertex_float_count), 3):
		var current_y := lerpf(
			positions[low_offset + vertex_float],
			positions[high_offset + vertex_float],
			blend_alpha,
		)
		var next_y := lerpf(
			positions[next_low_offset + vertex_float],
			positions[next_high_offset + vertex_float],
			blend_alpha,
		)
		minimum_y = minf(minimum_y, lerpf(current_y, next_y, frame_alpha))
	return minimum_y


static func _create_instance(instance_name: String, template: Dictionary) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = instance_name
	instance.mesh = ArrayMesh.new()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_render_frame(instance, template, template.positions, 0)
	return instance


static func _load_template(path: String) -> Dictionary:
	if _template_cache.has(path):
		return _template_cache[path]
	if not FileAccess.file_exists(path):
		push_warning("Converted character model is unavailable: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if (
		not parsed is Dictionary
		or parsed.get("format", "") != "protocol47-mdl"
		or int(parsed.get("version", 0)) < 2
	):
		push_error("Invalid animated character export: %s" % path)
		return {}
	var template := _build_template(path, parsed)
	if not template.is_empty():
		_template_cache[path] = template
	return template


static func _build_template(path: String, parsed: Dictionary) -> Dictionary:
	var source_positions: Array = parsed.get("positions", [])
	var source_uvs: Array = parsed.get("uvs", [])
	if source_positions.is_empty() or source_positions.size() % 3 != 0:
		return {}
	var positions := PackedFloat32Array()
	positions.resize(source_positions.size())
	for index in range(source_positions.size()):
		positions[index] = float(source_positions[index])
	var uvs := PackedFloat32Array()
	uvs.resize(source_uvs.size())
	for index in range(source_uvs.size()):
		uvs[index] = float(source_uvs[index])

	var animation_map := {}
	for animation_data in parsed.get("animations", []):
		var animation_file := path.get_base_dir().path_join(str(animation_data.get("file", "")))
		var source := FileAccess.open(animation_file, FileAccess.READ)
		if source == null:
			push_error("Missing character animation: %s" % animation_file)
			return {}
		var animation_positions := source.get_buffer(source.get_length()).to_float32_array()
		var frame_count := int(animation_data.get("frames", 0))
		var blend_count := maxi(1, int(animation_data.get("blends", 1)))
		if animation_positions.size() != frame_count * blend_count * positions.size():
			push_error("Invalid character animation frame data: %s" % animation_file)
			return {}
		animation_map[str(animation_data.get("name", ""))] = {
			"source_label": str(
				animation_data.get("source_label", animation_data.get("name", ""))
			),
			"sequence_index": int(animation_data.get("sequence_index", -1)),
			"fps": float(animation_data.get("fps", 15.0)),
			"frames": frame_count,
			"looping": bool(animation_data.get("looping", false)),
			"blends": blend_count,
			"blend_type": animation_data.get("blend_type", [0, 0]),
			"blend_start": animation_data.get("blend_start", [0.0, 0.0]),
			"blend_end": animation_data.get("blend_end", [1.0, 0.0]),
			"positions": animation_positions,
		}

	var groups: Array[Dictionary] = []
	for group_data in parsed.get("groups", []):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		var texture_name := str(group_data.get("texture", ""))
		if not texture_name.is_empty():
			material.albedo_texture = load(path.get_base_dir().path_join(texture_name))
		groups.append({
			"start": int(group_data.get("vert_start", 0)),
			"count": int(group_data.get("vert_count", 0)),
			"material": material,
		})

	return {
		"positions": positions,
		"uvs": uvs,
		"vertex_float_count": positions.size(),
		"groups": groups,
		"animations": animation_map,
	}


static func _render_frame(
	instance: MeshInstance3D,
	template: Dictionary,
	positions: PackedFloat32Array,
	frame_float_offset: int,
) -> void:
	_render_blended_frame(
		instance,
		template,
		positions,
		frame_float_offset,
		frame_float_offset,
		0.0,
	)


static func _render_blended_frame(
	instance: MeshInstance3D,
	template: Dictionary,
	positions: PackedFloat32Array,
	low_float_offset: int,
	high_float_offset: int,
	blend_alpha: float,
) -> void:
	_render_interpolated_frame(
		instance,
		template,
		positions,
		low_float_offset,
		high_float_offset,
		low_float_offset,
		high_float_offset,
		0.0,
		blend_alpha,
	)


static func _render_interpolated_frame(
	instance: MeshInstance3D,
	template: Dictionary,
	positions: PackedFloat32Array,
	current_low_float_offset: int,
	current_high_float_offset: int,
	next_low_float_offset: int,
	next_high_float_offset: int,
	frame_alpha: float,
	blend_alpha: float,
) -> void:
	if not is_instance_valid(instance):
		return
	var mesh := instance.mesh as ArrayMesh
	mesh.clear_surfaces()
	var uvs: PackedFloat32Array = template.uvs
	for group: Dictionary in template.groups:
		var start := int(group.start)
		var count := int(group.count)
		if count <= 0:
			continue
		var vertices := PackedVector3Array()
		var texture_uvs := PackedVector2Array()
		vertices.resize(count)
		texture_uvs.resize(count)
		for local_index in range(count):
			var vertex_index := start + local_index
			var current_low_offset := current_low_float_offset + vertex_index * 3
			var current_high_offset := current_high_float_offset + vertex_index * 3
			var next_low_offset := next_low_float_offset + vertex_index * 3
			var next_high_offset := next_high_float_offset + vertex_index * 3
			vertices[local_index] = Vector3(
				lerpf(
					lerpf(
						positions[current_low_offset],
						positions[current_high_offset],
						blend_alpha,
					),
					lerpf(
						positions[next_low_offset],
						positions[next_high_offset],
						blend_alpha,
					),
					frame_alpha,
				),
				lerpf(
					lerpf(
						positions[current_low_offset + 1],
						positions[current_high_offset + 1],
						blend_alpha,
					),
					lerpf(
						positions[next_low_offset + 1],
						positions[next_high_offset + 1],
						blend_alpha,
					),
					frame_alpha,
				),
				lerpf(
					lerpf(
						positions[current_low_offset + 2],
						positions[current_high_offset + 2],
						blend_alpha,
					),
					lerpf(
						positions[next_low_offset + 2],
						positions[next_high_offset + 2],
						blend_alpha,
					),
					frame_alpha,
				),
			)
			texture_uvs[local_index] = Vector2(
				uvs[vertex_index * 2],
				uvs[vertex_index * 2 + 1],
			)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = texture_uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, group.material)
