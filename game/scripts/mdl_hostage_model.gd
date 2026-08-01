class_name MdlHostageModel
extends Node3D

const CharacterModelScript := preload("res://scripts/mdl_character_model.gd")
const MODEL_PATH := "res://generated/hostages/hostage/model.json"
const TICK_SECONDS := 0.01
const SOURCE_SCALE := 1.0
const WALK_CYCLE_DISTANCE_HU := 46.99994659423828
const RUN_CYCLE_DISTANCE_HU := 198.25286865234375
const WALK_SOURCE_SPEED_HU := WALK_CYCLE_DISTANCE_HU / (17.0 / 20.0)
const RUN_SOURCE_SPEED_HU := RUN_CYCLE_DISTANCE_HU / (19.0 / 25.0)
const RUN_SELECTION_SPEED_HU := 120.0
const FRAME_KEY_STEPS := 4096.0

var model_loaded := false
var skin_index := 0
## CS 1.6 hostages enter their idle sequence at a random start frame, so two
## hostages standing together are never in visible lockstep. Owners assign a
## stable per-instance phase (0..1 of the idle cycle); zero keeps the exact
## authored frame-zero start for deterministic harnesses. Owners assign it
## after the model may already be idling (configure()/contract replays), so
## the setter re-seeds the running idle clock — otherwise co-located hostages
## stay in the frame-zero lockstep the phase exists to break.
var idle_phase_unit := 0.0:
	set(value):
		if is_equal_approx(idle_phase_unit, value):
			idle_phase_unit = value
			return
		idle_phase_unit = value
		if model_loaded and animation_state == "idle" and not _dead:
			_state_time = _idle_phase_seconds("idle")
			current_frame_key = ""
			_render_current_pose()
var light_color := Color(1.0, 1.0, 1.0)
var animation_state := "idle"
var current_frame_key := ""
var playback_rate := 1.0
var motion_speed_hu := 0.0

var mesh_instance: MeshInstance3D
var _template := {}
var _source_groups: Array = []
var _state_time := 0.0
var _action_state := ""
var _cowering := false
var _dead := false


func _ready() -> void:
	rotation.y = PI * 0.5
	scale = Vector3.ONE * SOURCE_SCALE
	if not model_loaded:
		load_hostage(skin_index)


func load_hostage(requested_skin := 0) -> bool:
	var file := FileAccess.open(MODEL_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing source hostage model export: %s" % MODEL_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if (
		not parsed is Dictionary
		or str(parsed.get("format", "")) != "protocol47-mdl"
		or int(parsed.get("version", 0)) < 3
	):
		push_error("Invalid source hostage model export: %s" % MODEL_PATH)
		return false
	var base_template := CharacterModelScript._load_template(MODEL_PATH)
	if base_template.is_empty():
		return false
	_source_groups = parsed.get("groups", [])
	_template = _instance_template(base_template)
	if is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	mesh_instance = CharacterModelScript._create_instance("AuthenticHostage", _template)
	# Stock CS 1.6 draws no shadows under studio models (the cl_shadows stencil
	# blob was a rarely-enabled option); real-time shadow casting instantly
	# reads as non-GoldSrc, so the hostage model never casts one.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	model_loaded = true
	set_skin(requested_skin)
	reset_animation()
	return true


func _instance_template(base_template: Dictionary) -> Dictionary:
	var local_groups: Array[Dictionary] = []
	for source_group: Dictionary in base_template.groups:
		var local_group := source_group.duplicate()
		var source_material: StandardMaterial3D = source_group.material
		local_group.material = source_material.duplicate()
		# GoldSrc lights studio models in software: the renderer samples the
		# lightmap under the model origin and modulates the whole model by
		# that color. Keep the material unshaded (matching the lightmapped
		# world surfaces) and reproduce the modulation through albedo_color
		# via set_light_color(), so a hostage in a dark room reads dark.
		local_group.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		local_group.material.albedo_color = light_color
		local_groups.append(local_group)
	return {
		"positions": base_template.positions,
		"uvs": base_template.uvs,
		"vertex_float_count": base_template.vertex_float_count,
		"groups": local_groups,
		"animations": base_template.animations,
	}


func set_skin(requested_skin: int) -> void:
	skin_index = posmod(requested_skin, 2)
	if not model_loaded:
		return
	var model_root := MODEL_PATH.get_base_dir()
	var instance_materials: Array = (
		mesh_instance.get_meta("group_materials", [])
		if is_instance_valid(mesh_instance)
		else []
	)
	for group_index in range(mini(_source_groups.size(), _template.groups.size())):
		var source_group: Dictionary = _source_groups[group_index]
		var skins: Array = source_group.get("skins", [])
		if skins.size() < 2:
			continue
		var texture_path := model_root.path_join(str(skins[skin_index]))
		var skin_texture: Texture2D = load(texture_path)
		var material: StandardMaterial3D = _template.groups[group_index].material
		material.albedo_texture = skin_texture
		if group_index < instance_materials.size():
			(
				instance_materials[group_index] as StandardMaterial3D
			).albedo_texture = skin_texture
	_render_current_pose()


## GoldSrc-style studio model lighting: modulate every body material by the
## lightmap color sampled beneath the actor (already converted to the map
## shader's gamma-space light factor). The 12% floor mirrors the world
## shader's ambient floor, so a hostage in a black room scales toward dark
## gray like GoldSrc lightgamma instead of going chromatic.
func set_light_color(sampled: Color) -> void:
	light_color = Color(
		clampf(sampled.r, 0.12, 1.0),
		clampf(sampled.g, 0.12, 1.0),
		clampf(sampled.b, 0.12, 1.0),
	)
	if not model_loaded or not is_instance_valid(mesh_instance):
		return
	# CharacterModel gives every mesh instance its own material copies (meta
	# "group_materials") and rebuilds surfaces from them; tint those.
	for material: StandardMaterial3D in mesh_instance.get_meta(
		"group_materials",
		[],
	):
		material.albedo_color = light_color
	for group: Dictionary in _template.groups:
		var material: StandardMaterial3D = group.material
		material.albedo_color = light_color


func reset_animation() -> void:
	_dead = false
	_cowering = false
	_action_state = ""
	motion_speed_hu = 0.0
	playback_rate = 1.0
	_set_state("idle")


func set_motion_speed_hu(speed_hu: float) -> void:
	motion_speed_hu = maxf(0.0, speed_hu)


func set_cowering(cowering: bool) -> void:
	_cowering = cowering
	if cowering:
		_action_state = ""


func play_action(action: String) -> void:
	if _dead or action not in ["acknowledge", "flinch", "panic"]:
		return
	if not _template.animations.has(action):
		return
	_action_state = action
	_set_state(action)


func play_death() -> void:
	if _dead:
		return
	_dead = true
	_action_state = ""
	_cowering = false
	_set_state("die")


func advance_tick() -> void:
	if not model_loaded:
		return
	var selected := _selected_state()
	_set_state(selected)
	playback_rate = _playback_rate_for_state(animation_state, motion_speed_hu)
	_state_time += TICK_SECONDS * playback_rate
	_render_current_pose()
	if not _action_state.is_empty():
		var action: Dictionary = _template.animations.get(_action_state, {})
		var duration := (
			float(action.frames) / maxf(1.0, float(action.fps))
			if not action.is_empty()
			else 0.0
		)
		if _state_time >= duration:
			_action_state = ""


func force_state(state: String, tick := 0) -> void:
	if not _template.animations.has(state):
		return
	_dead = state == "die"
	_action_state = ""
	_cowering = state == "cower"
	animation_state = state
	_state_time = maxf(0.0, float(tick) * TICK_SECONDS) + _idle_phase_seconds(state)
	playback_rate = 1.0
	current_frame_key = ""
	_render_current_pose()


func authored_cycle_distance_hu(state := "") -> float:
	var resolved := animation_state if state.is_empty() else state
	return (
		WALK_CYCLE_DISTANCE_HU
		if resolved == "walk"
		else RUN_CYCLE_DISTANCE_HU
		if resolved == "run"
		else 0.0
	)


func _selected_state() -> String:
	if _dead:
		return "die"
	if not _action_state.is_empty():
		return _action_state
	if _cowering:
		return "cower"
	if motion_speed_hu >= RUN_SELECTION_SPEED_HU:
		return "run"
	if motion_speed_hu > 0.01:
		return "walk"
	return "idle"


func _playback_rate_for_state(state: String, speed_hu: float) -> float:
	if state == "walk":
		return clampf(speed_hu / WALK_SOURCE_SPEED_HU, 0.05, 4.0)
	if state == "run":
		return clampf(speed_hu / RUN_SOURCE_SPEED_HU, 0.05, 4.0)
	return 1.0


func _set_state(state: String) -> void:
	if animation_state == state and not current_frame_key.is_empty():
		return
	animation_state = state
	_state_time = _idle_phase_seconds(state)
	current_frame_key = ""
	_render_current_pose()


## Per-instance random start frame for the looping idle, matching GoldSrc's
## randomized sequence phase; every other state keeps its exact authored start.
func _idle_phase_seconds(state: String) -> float:
	if state != "idle" or idle_phase_unit <= 0.0:
		return 0.0
	var animations: Dictionary = _template.get("animations", {})
	var animation: Dictionary = animations.get("idle", {})
	if animation.is_empty():
		return 0.0
	var cycle := float(animation.frames) / maxf(1.0, float(animation.fps))
	return fposmod(idle_phase_unit, 1.0) * cycle


func _render_current_pose() -> void:
	if not model_loaded or not is_instance_valid(mesh_instance):
		return
	var animation: Dictionary = _template.animations.get(animation_state, {})
	if animation.is_empty():
		return
	var frame_count := int(animation.frames)
	var frame_sample := maxf(0.0, _state_time * float(animation.fps))
	var frame_position := maxi(0, int(floor(frame_sample)))
	var frame_alpha := frame_sample - float(frame_position)
	if frame_alpha >= 1.0 - 0.5 / FRAME_KEY_STEPS:
		frame_position += 1
		frame_alpha = 0.0
	elif frame_alpha <= 0.5 / FRAME_KEY_STEPS:
		frame_alpha = 0.0
	var looping := bool(animation.looping) and not _dead
	var frame_index := 0
	var next_frame_index := 0
	if looping:
		frame_index = frame_position % frame_count
		next_frame_index = (frame_index + 1) % frame_count
	else:
		frame_index = mini(frame_position, frame_count - 1)
		next_frame_index = mini(frame_index + 1, frame_count - 1)
		if frame_index == frame_count - 1:
			frame_alpha = 0.0
	var key := "%s:%d:%d:%d" % [
		animation_state,
		frame_index,
		next_frame_index,
		int(round(frame_alpha * FRAME_KEY_STEPS)),
	]
	if key == current_frame_key:
		return
	var current_offset := CharacterModelScript._pose_float_offset(
		_template,
		animation,
		frame_index,
		0,
	)
	var next_offset := CharacterModelScript._pose_float_offset(
		_template,
		animation,
		next_frame_index,
		0,
	)
	CharacterModelScript._render_interpolated_frame(
		mesh_instance,
		_template,
		animation.positions,
		current_offset,
		current_offset,
		next_offset,
		next_offset,
		frame_alpha,
		0.0,
	)
	var minimum_y := CharacterModelScript._blended_minimum_y(
		_template,
		animation,
		frame_index,
		next_frame_index,
		frame_alpha,
		0,
		0,
		0.0,
	)
	mesh_instance.position.y = -minimum_y
	current_frame_key = key
