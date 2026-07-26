class_name MdlCharacterModel
extends Node3D

# BSP geometry and converted MDL vertices both use 0.01 Godot units for one
# GoldSrc unit. Keeping this at 1.0 preserves the original player-to-map ratio.
const MODEL_SCALE := 1.0
const MAX_VISUAL_FPS := 24.0

static var _template_cache: Dictionary = {}

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
	# Animated GoldSrc player vertices are centered around the entity origin,
	# while the CharacterBody3D origin is at the bottom of its standing hull.
	position.y = -body_instance.mesh.get_aabb().position.y * MODEL_SCALE
	return true


func set_locomotion(moving: bool, crouched := false) -> void:
	_moving = moving
	_crouched = crouched


func play_action(action: String) -> void:
	if _dead or not _body_template.animations.has(action):
		return
	_action_state = action
	_action_time = 0.0


func play_death() -> void:
	_dead = true
	_action_state = ""
	_animation_time = 0.0
	animation_state = "die"


func reset_animation() -> void:
	_dead = false
	_moving = false
	_crouched = false
	_action_state = ""
	_animation_time = 0.0
	_action_time = 0.0
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
		animation_state = (
			"crouchrun"
			if _crouched and _moving
			else "crouchidle"
			if _crouched
			else "run"
			if _moving
			else "idle"
		)
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
	if animation.is_empty():
		animation = animations.get("run" if _moving else "idle", {})
	if animation.is_empty():
		return previous_key
	var frame_count := int(animation.frames)
	if frame_count <= 0:
		return previous_key
	var sampled_time: float = floor(time * MAX_VISUAL_FPS) / MAX_VISUAL_FPS
	var frame_position := maxi(0, int(floor(sampled_time * float(animation.fps))))
	var frame_index := (
		frame_position % frame_count
		if loop
		else mini(frame_position, frame_count - 1)
	)
	var frame_key := "%s:%d" % [state, frame_index]
	if frame_key == previous_key:
		return previous_key
	_render_frame(
		instance,
		template,
		animation.positions,
		frame_index * int(template.vertex_float_count),
	)
	return frame_key


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
		if animation_positions.size() != frame_count * positions.size():
			push_error("Invalid character animation frame data: %s" % animation_file)
			return {}
		animation_map[str(animation_data.get("name", ""))] = {
			"fps": float(animation_data.get("fps", 15.0)),
			"frames": frame_count,
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
			var position_offset := frame_float_offset + vertex_index * 3
			vertices[local_index] = Vector3(
				positions[position_offset],
				positions[position_offset + 1],
				positions[position_offset + 2],
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
