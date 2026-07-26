class_name MdlViewModel
extends Node3D

const CharacterModelScript := preload("res://scripts/mdl_character_model.gd")
const MAX_VISUAL_FPS := 60.0
const CLASSIC_BASE_POSITION := Vector3(0.16, -0.075, -0.36)
const CLASSIC_MODEL_SCALE := Vector3(-0.63, 1.0, -1.0)

var loaded_weapon := ""
var model_root: Node3D
# Animated MDL frames use their authored camera-space origin, unlike the old
# static bind pose. This placement keeps the hands and receiver inside a
# classic 4:3 safe frame while still reading correctly at widescreen ratios.
var base_position := CLASSIC_BASE_POSITION

var _template: Dictionary = {}
var _model_instance: MeshInstance3D
var _animation_name := ""
var _animation_time := 0.0
var _animation_loop := true
var _frame_key := ""
var _action_serial := 0


func _ready() -> void:
	position = base_position


func load_weapon(weapon: String) -> bool:
	if loaded_weapon == weapon:
		return true
	var path := "res://generated/weapons/%s/model.json" % weapon
	var source_template: Dictionary = CharacterModelScript._load_template(path)
	if source_template.is_empty():
		push_warning("Converted animated viewmodel is unavailable: %s" % path)
		return false
	_template = _first_person_template(source_template)
	if is_instance_valid(model_root):
		model_root.queue_free()

	model_root = Node3D.new()
	model_root.name = "Authentic_%s" % weapon
	# Animated viewmodel frames are already emitted in camera/view space. The
	# static bind pose required a +90° yaw, but applying that legacy correction
	# to sequence frames turns their full horizontal span into depth and leaves
	# only a sliver of the gun visible.
	model_root.rotation.y = 0.0
	# GoldSrc viewmodels are authored for a left-handed model coordinate basis
	# and mirrored by the client into the conventional right-hand view.
	model_root.scale = CLASSIC_MODEL_SCALE
	add_child(model_root)

	_model_instance = CharacterModelScript._create_instance(
		"Animated_%s" % weapon,
		_template,
	)
	_model_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model_root.add_child(_model_instance)

	loaded_weapon = weapon
	visible = true
	_action_serial = 0
	_start_animation(_idle_animation(), true)
	return true


func _first_person_template(source_template: Dictionary) -> Dictionary:
	var view_template := source_template.duplicate()
	var view_groups: Array[Dictionary] = []
	for source_group: Dictionary in source_template.groups:
		var group := source_group.duplicate()
		var source := group.material as StandardMaterial3D
		if source == null:
			view_groups.append(group)
			continue
		var material := source.duplicate() as StandardMaterial3D
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.no_depth_test = true
		material.render_priority = 10
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		group.material = material
		view_groups.append(group)
	view_template.groups = view_groups
	return view_template


func _process(delta: float) -> void:
	if _template.is_empty() or not is_instance_valid(_model_instance):
		return
	var animation: Dictionary = _template.animations.get(_animation_name, {})
	if animation.is_empty():
		return
	_animation_time += delta
	var frame_count := int(animation.frames)
	var fps := maxf(1.0, float(animation.fps))
	var duration := float(frame_count) / fps
	if not _animation_loop and _animation_time >= duration:
		_start_animation(_idle_animation(), true)
		animation = _template.animations.get(_animation_name, {})
		frame_count = int(animation.get("frames", 0))
		fps = maxf(1.0, float(animation.get("fps", 1.0)))
	if frame_count <= 0:
		return

	var sampled_time: float = floor(_animation_time * MAX_VISUAL_FPS) / MAX_VISUAL_FPS
	var frame_position := maxi(0, int(floor(sampled_time * fps)))
	var frame_index := (
		frame_position % frame_count
		if _animation_loop
		else mini(frame_position, frame_count - 1)
	)
	var next_key := "%s:%d" % [_animation_name, frame_index]
	if next_key == _frame_key:
		return
	CharacterModelScript._render_frame(
		_model_instance,
		_template,
		animation.positions,
		frame_index * int(_template.vertex_float_count),
	)
	_frame_key = next_key


func play_action(kind: String) -> void:
	if _template.is_empty():
		return
	var animation := _action_animation(kind)
	if animation.is_empty():
		_play_fallback_action(kind)
		return
	_start_animation(animation, false)


func _play_fallback_action(kind: String) -> void:
	var tween := create_tween()
	match kind:
		"fire":
			tween.tween_property(self, "position:z", base_position.z + 0.075, 0.035)
			tween.tween_property(self, "position:z", base_position.z, 0.075)
		"reload":
			tween.tween_property(self, "rotation:z", deg_to_rad(24.0), 0.25)
			tween.tween_property(self, "rotation:z", 0.0, 0.42).set_delay(1.15)
		"switch":
			position.y = base_position.y - 0.14
			tween.tween_property(self, "position:y", base_position.y, 0.22)
		"knife":
			tween.tween_property(self, "rotation:y", deg_to_rad(-32.0), 0.07)
			tween.tween_property(self, "rotation:y", 0.0, 0.15)
		"pullpin":
			tween.tween_property(self, "rotation:x", deg_to_rad(9.0), 0.14)
			tween.tween_property(self, "rotation:z", deg_to_rad(-7.0), 0.10)
		"throw":
			tween.tween_property(self, "rotation:x", deg_to_rad(-35.0), 0.12)
			tween.parallel().tween_property(self, "rotation:z", 0.0, 0.12)
			tween.tween_property(self, "rotation:x", 0.0, 0.2)


func _start_animation(animation: String, loop: bool) -> void:
	if animation.is_empty() or not _template.animations.has(animation):
		return
	_animation_name = animation
	_animation_time = 0.0
	_animation_loop = loop
	_frame_key = ""


func _idle_animation() -> String:
	for candidate in ["idle", "idle1", "idle2", "idle3"]:
		if _template.animations.has(candidate):
			return candidate
	var names: Array = _template.animations.keys()
	return str(names[0]) if not names.is_empty() else ""


func _action_animation(kind: String) -> String:
	var candidates: Array[String] = []
	match kind:
		"fire":
			candidates.assign(["shoot1", "shoot2", "shoot3", "shoot", "fire"])
			var available_fire: Array[String] = []
			for candidate: String in candidates:
				if _template.animations.has(candidate):
					available_fire.append(candidate)
			if not available_fire.is_empty():
				var selected := available_fire[_action_serial % available_fire.size()]
				_action_serial += 1
				return selected
		"reload":
			candidates.assign(["reload", "reload1", "start_reload", "insert"])
		"switch":
			candidates.assign(["draw", "deploy", "up"])
		"knife":
			candidates.assign(["slash1", "slash2", "stab", "midslash1", "midslash2"])
		"throw":
			candidates.assign(["throw", "throw1", "release"])
		_:
			candidates.assign([kind])
	for candidate: String in candidates:
		if _template.animations.has(candidate):
			return candidate
	# Sequence naming differs between a few stock weapons. A prefix fallback
	# preserves original MDL content without hardcoding model-specific indices.
	for animation_variant: Variant in _template.animations.keys():
		var animation := str(animation_variant)
		for candidate: String in candidates:
			if animation.begins_with(candidate):
				return animation
	return ""


func set_bob(offset_y: float, sway_x: float) -> void:
	position.y = base_position.y + offset_y
	position.x = base_position.x + sway_x
