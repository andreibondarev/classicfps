extends SceneTree

const CharacterModelScript := preload("res://scripts/mdl_character_model.gd")
const TargetScript := preload("res://scripts/target.gd")
const SKINS := ["terror", "leet", "arctic", "guerilla", "urban", "gsg9", "sas", "gign"]
const SOURCE_CONTRACT := {
	"idle": ["idle1", 15.0, 61, true, 1],
	"run": ["run", 60.0, 37, true, 1],
	"crouchidle": ["crouch_idle", 10.0, 31, true, 1],
	"crouchrun": ["crouchrun", 30.0, 31, true, 1],
	# The AK-47 samples the carbine activity family: the standing
	# ref_aim_ak47/ref_shoot_ak47 tapes in the stock player MDLs decode with
	# the torso 90 degrees off the gait facing (see WEAPON_FAMILIES).
	"crouchshoot": ["crouch_shoot_carbine", 15.0, 5, false, 9],
	"shoot": ["ref_shoot_carbine", 15.0, 5, false, 9],
	"crouchreload": ["crouch_reload_carbine", 30.0, 61, false, 1],
	"reload": ["ref_reload_carbine", 30.0, 61, false, 1],
	"die": ["death1", 30.0, 36, false, 1],
}
const SOURCE_QUANT_STEP := 0.0001
const FOOT_TOLERANCE := 2.0 * 0.01
# Upper-body action tapes composite their legs from the gait tape (GoldSrc
# gaitsequence split); their below-belt vertices render locomotion geometry.
const COMPOSITE_STATES := ["shoot", "reload", "crouchshoot", "crouchreload"]
# Locomotion states composite the other way: the aim layer (ref_shoot frame 0
# with the XR pitch blend) renders above the pelvis while the locomotion tape
# keeps the legs and the authoritative clock.
const AIM_LAYER_FOR := {
	"idle": "shoot",
	"run": "shoot",
	"crouchidle": "crouchshoot",
	"crouchrun": "crouchshoot",
}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	for skin: String in SKINS:
		var model: MdlCharacterModel = CharacterModelScript.new()
		stage.add_child(model)
		_check(model.load_character(skin, "ak47"), "%s model and attached AK load" % skin)
		if not model.model_loaded:
			continue
		_check(
			model.scale.is_equal_approx(CharacterModelScript.PRESENTATION_SCALE),
			"%s applies only the restrained horizontal silhouette correction" % skin,
		)
		_check(
			is_equal_approx(model.scale.y, CharacterModelScript.MODEL_SCALE)
				and model.scale.x > model.scale.y
				and is_equal_approx(model.scale.x, model.scale.z),
			"%s preserves source height and yaw-independent horizontal proportions" % skin,
		)
		_assert_metadata(model, skin)
		_assert_grounded_source_poses(model, skin)
		_assert_gait_motion(model, skin)
		model.queue_free()

	var model: MdlCharacterModel = CharacterModelScript.new()
	stage.add_child(model)
	_check(model.load_character("terror", "ak47"), "state-machine fixture loads")
	if model.model_loaded:
		_assert_pitch_blends(model)
		_assert_fractional_frame_interpolation(model)
		_assert_state_selection(model)
		_assert_100hz_transition_tape(model)
		_assert_death_freeze(model)
		_assert_offscreen_animation_clock(model, stage)
	_assert_target_facing(stage)

	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		print("GAME_CHARACTER_MODEL_ANIMATION_TEST_FAIL (%d)" % _failures.size())
		quit(1)
		return
	print("GAME_CHARACTER_MODEL_ANIMATION_TEST_PASS")
	quit()


func _assert_metadata(model: MdlCharacterModel, skin: String) -> void:
	for state: String in SOURCE_CONTRACT:
		var expected: Array = SOURCE_CONTRACT[state]
		var animation: Dictionary = model._body_template.animations.get(state, {})
		_check(not animation.is_empty(), "%s exposes %s" % [skin, state])
		if animation.is_empty():
			continue
		_check(
			str(animation.source_label) == str(expected[0]),
			"%s %s source label is %s" % [skin, state, expected[0]],
		)
		_check(
			is_equal_approx(float(animation.fps), float(expected[1])),
			"%s %s preserves %.1f FPS" % [skin, state, expected[1]],
		)
		_check(
			int(animation.frames) == _expected_frames(skin, state, int(expected[2])),
			"%s %s preserves %d source frames"
			% [skin, state, _expected_frames(skin, state, int(expected[2]))],
		)
		_check(
			bool(animation.looping) == bool(expected[3]),
			"%s %s looping flag matches source" % [skin, state],
		)
		_check(
			int(animation.blends) == int(expected[4]),
			"%s %s preserves %d authored blends" % [skin, state, expected[4]],
		)
		if int(expected[4]) == 9:
			_check(
				int(animation.blend_type[0]) == 8
				and is_equal_approx(float(animation.blend_start[0]), -90.0)
				and is_equal_approx(float(animation.blend_end[0]), 90.0),
				"%s %s preserves STUDIO_XR -90..90 controller metadata"
				% [skin, state],
			)


func _expected_frames(_skin: String, _state: String, default_frames: int) -> int:
	# The carbine family tapes are authored identically across all eight
	# original player MDLs (unlike the ak47 tapes' CT crouch extra frame).
	return default_frames


func _assert_grounded_source_poses(model: MdlCharacterModel, skin: String) -> void:
	for state: String in SOURCE_CONTRACT:
		for fraction: float in [0.0, 0.25, 0.5, 0.75]:
			model.reset_animation()
			model.set_locomotion(false, state.begins_with("crouch"), true)
			model.force_pose(state, fraction, 0.0)
			# ArrayMesh.get_aabb() retains its original allocation bounds after
			# vertex-region updates. Read back the actual positions independently
			# and also verify the custom culling bounds supplied by the animator.
			var bounds := _vertex_bounds(model.body_instance.mesh)
			var culling_bounds: AABB = model.body_instance.mesh.custom_aabb
			_check(culling_bounds.encloses(bounds), "animated culling bounds contain every uploaded vertex")
			var feet_above_hull_floor := model.position.y + bounds.position.y * model.scale.y
			_check(
				absf(feet_above_hull_floor) <= FOOT_TOLERANCE,
				"%s %s %.2f feet remain within 2 HU of hull floor"
				% [skin, state, fraction],
			)
			var source_bounds := _source_pose_bounds(model, state, fraction, 0.0)
			_check(
				(bounds.position - source_bounds.position).length() <= SOURCE_QUANT_STEP
				and (bounds.size - source_bounds.size).length() <= SOURCE_QUANT_STEP,
				"%s %s %.2f rendered bounds equal baked source bounds"
				% [skin, state, fraction],
			)


func _assert_gait_motion(model: MdlCharacterModel, skin: String) -> void:
	var reference: PackedFloat32Array = model._body_template.positions
	var mask: PackedByteArray = model._body_template.lower_mask
	var floor_y := INF
	for index in range(1, reference.size(), 3):
		floor_y = minf(floor_y, reference[index])
	var whole_thigh := false
	for vertex in mask.size():
		if mask[vertex] != 0 and reference[vertex * 3 + 1] > floor_y + 0.34:
			whole_thigh = true
	_check(whole_thigh, "%s gait mask includes the whole thigh, not a height cutoff" % skin)
	for state: String in ["run", "crouchrun"]:
		model.reset_animation()
		model.set_locomotion(true, state == "crouchrun", true)
		model.force_pose(state, 0.25)
		var first := _all_vertices(model.body_instance.mesh)
		model.force_pose(state, 0.75)
		var second := _all_vertices(model.body_instance.mesh)
		var foot_travel := 0.0
		for vertex in mask.size():
			if mask[vertex] == 0 or reference[vertex * 3 + 1] > floor_y + 0.20:
				continue
			var delta := second[vertex] - first[vertex]
			foot_travel = maxf(foot_travel, Vector2(delta.x, delta.z).length())
		_check(foot_travel > 0.08, "%s %s rendered feet take a stride (%.3f m)" % [skin, state, foot_travel])


func _all_vertices(mesh: ArrayMesh) -> PackedVector3Array:
	var result := PackedVector3Array()
	for surface in mesh.get_surface_count():
		result.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	return result


func _vertex_bounds(mesh: ArrayMesh) -> AABB:
	var minimum := Vector3.INF
	var maximum := -Vector3.INF
	for surface in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			minimum = minimum.min(vertex)
			maximum = maximum.max(vertex)
	return AABB(minimum, maximum - minimum)


func _source_pose_bounds(
	model: MdlCharacterModel,
	state: String,
	fraction: float,
	pitch_degrees: float,
) -> AABB:
	var animation: Dictionary = model._body_template.animations[state]
	model._aim_pitch_degrees = pitch_degrees
	var frame := mini(
		int(floor(fraction * float(animation.frames - 1))),
		int(animation.frames) - 1,
	)
	var blend_position := model._blend_position(animation)
	var blend_low := int(floor(blend_position))
	var blend_high := int(ceil(blend_position))
	var alpha := blend_position - float(blend_low)
	var low_offset := model._pose_float_offset(
		model._body_template,
		animation,
		frame,
		blend_low,
	)
	var high_offset := model._pose_float_offset(
		model._body_template,
		animation,
		frame,
		blend_high,
	)
	var positions: PackedFloat32Array = animation.positions
	# GoldSrc gaitsequence split: upper-body action tapes render locomotion
	# geometry below the belt. With the fixture reset (_animation_time == 0,
	# stationary) the expected gait sample is frame 0, blend 0.
	var composite := state in COMPOSITE_STATES
	var mask: PackedByteArray = model._body_template.get("lower_mask", PackedByteArray())
	var gait_positions := PackedFloat32Array()
	if composite:
		var gait_state := (
			"crouchidle" if state.begins_with("crouch") or model._crouched else "idle"
		)
		gait_positions = model._body_template.animations[gait_state].positions
	# Locomotion states hold the aim layer (ref_shoot frame 0, pitch blend)
	# above the pelvis; only masked (leg) vertices render the state tape.
	var aim_composite: bool = AIM_LAYER_FOR.has(state)
	var aim_positions := PackedFloat32Array()
	var aim_low_offset := 0
	var aim_high_offset := 0
	var aim_alpha := 0.0
	if aim_composite:
		var aim_animation: Dictionary = (
			model._body_template.animations[AIM_LAYER_FOR[state]]
		)
		aim_positions = aim_animation.positions
		var aim_blend := model._blend_position(aim_animation)
		var aim_blend_low := int(floor(aim_blend))
		var aim_blend_high := int(ceil(aim_blend))
		aim_alpha = aim_blend - float(aim_blend_low)
		aim_low_offset = model._pose_float_offset(
			model._body_template,
			aim_animation,
			0,
			aim_blend_low,
		)
		aim_high_offset = model._pose_float_offset(
			model._body_template,
			aim_animation,
			0,
			aim_blend_high,
		)
	var minimum := Vector3.INF
	var maximum := -Vector3.INF
	for offset in range(0, int(model._body_template.vertex_float_count), 3):
		var point := Vector3.ZERO
		if composite and mask[offset / 3] != 0:
			point = Vector3(
				gait_positions[offset],
				gait_positions[offset + 1],
				gait_positions[offset + 2],
			)
		elif aim_composite and mask[offset / 3] == 0:
			point = Vector3(
				lerpf(
					aim_positions[aim_low_offset + offset],
					aim_positions[aim_high_offset + offset],
					aim_alpha,
				),
				lerpf(
					aim_positions[aim_low_offset + offset + 1],
					aim_positions[aim_high_offset + offset + 1],
					aim_alpha,
				),
				lerpf(
					aim_positions[aim_low_offset + offset + 2],
					aim_positions[aim_high_offset + offset + 2],
					aim_alpha,
				),
			)
		else:
			point = Vector3(
				lerpf(positions[low_offset + offset], positions[high_offset + offset], alpha),
				lerpf(
					positions[low_offset + offset + 1],
					positions[high_offset + offset + 1],
					alpha,
				),
				lerpf(
					positions[low_offset + offset + 2],
					positions[high_offset + offset + 2],
					alpha,
				),
			)
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)


func _assert_pitch_blends(model: MdlCharacterModel) -> void:
	model.force_pose("shoot", 0.0, 0.0)
	_check(":4:4:" in model._body_frame_key, "level aim selects authored center blend 4")
	var level_vertex := _first_vertex(model.body_instance)
	model.force_pose("shoot", 0.0, 30.0)
	_check(":0:0:" in model._body_frame_key, "+30 degree aim selects -90 XR endpoint")
	var upper_vertex := _first_vertex(model.body_instance)
	model.force_pose("shoot", 0.0, -30.0)
	_check(":8:8:" in model._body_frame_key, "-30 degree aim selects +90 XR endpoint")
	_check(
		level_vertex.distance_to(upper_vertex) >= SOURCE_QUANT_STEP,
		"level and endpoint aim render distinct source geometry",
	)


func _assert_fractional_frame_interpolation(model: MdlCharacterModel) -> void:
	# +3.75 degrees maps to blend position 3.5, so these probes exercise both
	# GoldSrc controller blending and temporal frame interpolation together.
	for phase: float in [0.25, 0.5, 0.75]:
		model._aim_pitch_degrees = 3.75
		var animation: Dictionary = model._body_template.animations.shoot
		var sample_time := phase / float(animation.fps)
		model._body_frame_key = model._set_frame(
			model.body_instance,
			model._body_template,
			"shoot",
			sample_time,
			false,
			"",
		)
		model._weapon_frame_key = model._set_frame(
			model.weapon_instance,
			model._weapon_template,
			"shoot",
			sample_time,
			false,
			"",
		)
		_assert_every_vertex_matches_source_lerp(
			model,
			model.body_instance,
			model._body_template,
			"shoot",
			phase,
			"body",
		)
		_assert_every_vertex_matches_source_lerp(
			model,
			model.weapon_instance,
			model._weapon_template,
			"shoot",
			phase,
			"attached weapon",
		)
		var expected_phase_key := int(round(phase * model.FRAME_KEY_STEPS))
		_check(
			int(model._body_frame_key.split(":")[3]) == expected_phase_key
			and int(model._weapon_frame_key.split(":")[3]) == expected_phase_key,
			"%.2f phase uses one authoritative clock for body and weapon" % phase,
		)


func _assert_every_vertex_matches_source_lerp(
	model: MdlCharacterModel,
	instance: MeshInstance3D,
	template: Dictionary,
	state: String,
	frame_alpha: float,
	label: String,
) -> void:
	var animation: Dictionary = template.animations[state]
	var blend_position := model._blend_position(animation)
	var blend_low := int(floor(blend_position))
	var blend_high := int(ceil(blend_position))
	var blend_alpha := blend_position - float(blend_low)
	var current_low := model._pose_float_offset(template, animation, 0, blend_low)
	var current_high := model._pose_float_offset(template, animation, 0, blend_high)
	var next_low := model._pose_float_offset(template, animation, 1, blend_low)
	var next_high := model._pose_float_offset(template, animation, 1, blend_high)
	var positions: PackedFloat32Array = animation.positions
	# Body vertices below the belt render the gait tape during action states
	# (fixture is stationary with _animation_time 0 -> idle frame 0, blend 0).
	var composite := instance == model.body_instance and state in COMPOSITE_STATES
	var mask: PackedByteArray = template.get("lower_mask", PackedByteArray())
	var gait_positions := PackedFloat32Array()
	if composite:
		gait_positions = template.animations.idle.positions
	var mesh := instance.mesh as ArrayMesh
	var maximum_error := 0.0
	var rendered_count := 0
	for surface_index in range(mesh.get_surface_count()):
		var group: Dictionary = template.groups[surface_index]
		var vertices: PackedVector3Array = (
			mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
		)
		for local_index in range(vertices.size()):
			var vertex_index := int(group.start) + local_index
			var float_index := vertex_index * 3
			if composite and mask[vertex_index] != 0:
				var gait_expected := Vector3(
					gait_positions[float_index],
					gait_positions[float_index + 1],
					gait_positions[float_index + 2],
				)
				maximum_error = maxf(
					maximum_error,
					vertices[local_index].distance_to(gait_expected),
				)
				rendered_count += 1
				continue
			var expected := Vector3.ZERO
			for component in range(3):
				var current := lerpf(
					positions[current_low + float_index + component],
					positions[current_high + float_index + component],
					blend_alpha,
				)
				var next := lerpf(
					positions[next_low + float_index + component],
					positions[next_high + float_index + component],
					blend_alpha,
				)
				expected[component] = lerpf(current, next, frame_alpha)
			maximum_error = maxf(maximum_error, vertices[local_index].distance_to(expected))
			rendered_count += 1
	_check(
		rendered_count * 3 == int(template.vertex_float_count)
		and maximum_error <= SOURCE_QUANT_STEP,
		(
			"%s phase %.2f renders every vertex from the four-pose source lerp "
			+ "(max error %.7f)"
		) % [label, frame_alpha, maximum_error],
	)


func _assert_state_selection(model: MdlCharacterModel) -> void:
	model.reset_animation()
	model.set_locomotion(true, false, true)
	model._process(0.2)
	_check(model.animation_state == "run", "grounded motion selects run")
	model.set_locomotion(false, true, true)
	model._process(0.0)
	_check(model.animation_state == "crouchidle", "grounded duck selects crouch idle")
	model.play_action("shoot")
	_check(model._action_state == "crouchshoot", "duck fire selects crouched source action")
	model._process(0.0)
	_check(model.animation_state == "crouchshoot", "crouched shoot renders immediately")
	model.reset_animation()
	model._animation_time = 0.2
	model.set_locomotion(true, false, false)
	model._process(0.0)
	_check(
		model.animation_state == "run" and model._body_frame_key.begins_with("run:12:"),
		"airborne locomotion keeps source phase instead of flashing frame zero",
	)
	model.reset_animation()
	model.play_action("reload")
	model._process(0.0)
	_check(
		model.animation_state == "reload"
		and model._body_frame_key.begins_with("reload:")
		and model._weapon_frame_key.begins_with("reload:"),
		"reload selects matching body and attached-weapon source sequences",
	)


func _assert_100hz_transition_tape(model: MdlCharacterModel) -> void:
	var tape: Array[Dictionary] = []
	model.reset_animation()
	for tick in range(10):
		model.advance_animation(0.01)
		_record_tape(tape, tick, model)

	model.set_locomotion(true, false, true)
	model.advance_animation(0.01)
	_record_tape(tape, 10, model)
	var run_fields := model._body_frame_key.split(":")
	_check(
		model.animation_state == "run"
		and int(run_fields[1]) == 6
		and int(run_fields[2]) == 7
		and absf(float(run_fields[3]) / model.FRAME_KEY_STEPS - 0.6) < 0.001,
		"100 Hz idle-to-run transition preserves the authoritative gait clock",
	)

	model.set_locomotion(false, true, true)
	model.advance_animation(0.01)
	_record_tape(tape, 11, model)
	var crouch_fields := model._body_frame_key.split(":")
	_check(
		model.animation_state == "crouchidle"
		and int(crouch_fields[1]) == 1
		and int(crouch_fields[2]) == 2,
		"100 Hz run-to-crouch transition continues locomotion phase",
	)

	model.play_action("shoot")
	model.advance_animation(0.01)
	_record_tape(tape, 12, model)
	var shoot_fields := model._body_frame_key.split(":")
	_check(
		model.animation_state == "crouchshoot"
		and int(shoot_fields[1]) == 0
		and absf(float(shoot_fields[3]) / model.FRAME_KEY_STEPS - 0.15) < 0.001,
		"shoot transition resets its authored one-shot clock",
	)

	model.set_locomotion(false, false, true)
	model.play_action("reload")
	model.advance_animation(0.01)
	_record_tape(tape, 13, model)
	var reload_fields := model._body_frame_key.split(":")
	_check(
		model.animation_state == "reload"
		and int(reload_fields[1]) == 0
		and absf(float(reload_fields[3]) / model.FRAME_KEY_STEPS - 0.3) < 0.001,
		"reload transition independently resets its authored one-shot clock",
	)

	model.play_death()
	_record_tape(tape, 14, model)
	_check(
		model._body_frame_key.begins_with("die:0:1:0:"),
		"death transition begins on the exact authored first frame",
	)
	_check(
		not model.weapon_instance.visible
		and not is_instance_valid(model.dropped_weapon_instance),
		"gameplay death hides the held gun without duplicating the Game-owned pickup",
	)
	for tick in range(15, 150):
		model.advance_animation(0.01)
		_record_tape(tape, tick, model)
	var final_key := model._body_frame_key
	var final_vertex := _first_vertex(model.body_instance)
	for tick in range(150, 160):
		model.advance_animation(0.01)
		_record_tape(tape, tick, model)
	_check(
		final_key.begins_with("die:35:35:0:")
		and model._body_frame_key == final_key
		and _first_vertex(model.body_instance).is_equal_approx(final_vertex),
		"100 Hz death tape clamps and holds the authored final frame",
	)

	var tape_file := FileAccess.open(
		"/tmp/protocol47-character-100hz-transition-tape.json",
		FileAccess.WRITE,
	)
	_check(tape_file != null, "100 Hz transition tape artifact opens")
	if tape_file != null:
		tape_file.store_string(JSON.stringify({
			"tick_rate_hz": 100,
			"source": "deterministic production sampler",
			"ticks": tape,
		}, "\t"))


func _record_tape(tape: Array[Dictionary], tick: int, model: MdlCharacterModel) -> void:
	# The p_ model shares the body's source sample while attached; the trailing
	# key field is the body-only gait overlay and death detaches the weapon
	# entirely (CS 1.6 corpses are empty-handed).
	var clock_match := (
		_shared_clock_key(model._body_frame_key)
		== _shared_clock_key(model._weapon_frame_key)
	)
	tape.append({
		"tick": tick,
		"state": model.animation_state,
		"body_frame_key": model._body_frame_key,
		"weapon_frame_key": model._weapon_frame_key,
		"body_weapon_clock_match": clock_match or model._dead,
	})
	if model._dead:
		_check(
			not model.weapon_instance.visible,
			"100 Hz tick %d keeps the p_ model detached after death" % tick,
		)
		return
	_check(
		clock_match,
		"100 Hz tick %d keeps body and attached weapon on the same source sample" % tick,
	)


static func _shared_clock_key(frame_key: String) -> String:
	var fields := frame_key.split(":")
	return ":".join(fields.slice(0, mini(7, fields.size())))


func _assert_death_freeze(model: MdlCharacterModel) -> void:
	model.reset_animation()
	model.play_death()
	model._process(2.0)
	_check(model._body_frame_key.begins_with("die:35:"), "death reaches source final frame 35")
	var final_vertex := _first_vertex(model.body_instance)
	var final_key := model._body_frame_key
	model._process(10.0)
	_check(
		model._body_frame_key == final_key
		and _first_vertex(model.body_instance).is_equal_approx(final_vertex),
		"death freezes its final source pose until reset",
	)
	model.reset_animation()
	_check(model.animation_state == "idle", "round reset releases frozen death pose")


func _assert_offscreen_animation_clock(model: MdlCharacterModel, stage: Node3D) -> void:
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.make_current()
	var original_position := model.position
	model.position = Vector3(0, 0, -5)
	_check(model._pose_may_be_visible(), "in-frustum actor receives mesh updates")
	model.position = Vector3(0, 0, 10)
	_check(not model._pose_may_be_visible(), "actor behind camera skips mesh deformation")
	model.reset_animation()
	model.play_action("reload")
	var frame_key := model._body_frame_key
	model._process(0.25)
	_check(model._body_frame_key == frame_key, "offscreen mesh is not rebuilt")
	_check(is_equal_approx(model._action_time, 0.25), "offscreen action clock still advances")
	model.position = Vector3(0, 0, -5)
	model._process(0.0)
	_check(model._body_frame_key != frame_key and model.animation_state == "reload", "visible actor catches up to the current action frame")
	model.position = Vector3(0, 0, 10)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	stage.add_child(sun)
	_check(model._pose_may_be_visible(), "new light projecting an offscreen actor's shadow into view keeps its pose live")
	frame_key = model._body_frame_key
	model._process(0.25)
	_check(model._body_frame_key != frame_key, "offscreen shadow caster actually updates its animated mesh")
	_check(is_equal_approx(model._action_time, 0.5), "shadow-aware animation does not advance the action clock twice")
	sun.rotation.y = PI
	_check(not model._pose_may_be_visible(), "shadow projected away from the camera can skip deformation")
	sun.rotation.y = 0.0
	sun.shadow_enabled = false
	_check(not model._pose_may_be_visible(), "disabled shadows do not require offscreen deformation")
	sun.shadow_enabled = true
	sun.hide()
	_check(not model._pose_may_be_visible(), "hidden light does not require offscreen deformation")
	sun.show()
	sun.shadow_caster_mask = 2
	_check(not model._pose_may_be_visible(), "shadow caster mask excludes the actor's layer")
	sun.shadow_caster_mask = 1
	sun.light_cull_mask = 0
	_check(model._pose_may_be_visible(), "lighting cull mask must not be mistaken for shadow caster mask")
	model.body_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.weapon_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_check(not model._pose_may_be_visible(), "non-casting meshes need no shadow updates")
	model.weapon_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_check(model._pose_may_be_visible(), "attached shadow-only weapon keeps its pose live")
	model.body_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	model.weapon_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sun.free()
	_check(not model._pose_may_be_visible(), "removed lights leave the registry immediately")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	stage.add_child(viewport)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	viewport.add_child(sun)
	_check(not model._pose_may_be_visible(), "a warmup viewport's light cannot affect the gameplay world")
	viewport.free()
	for light: Light3D in [OmniLight3D.new(), SpotLight3D.new()]:
		light.shadow_enabled = true
		light.set_param(Light3D.PARAM_RANGE, 20.0)
		stage.add_child(light)
		_check(model._pose_may_be_visible(), "positional light touching actor and view conservatively updates shadows")
		light.position = Vector3(100, 0, 0)
		_check(not model._pose_may_be_visible(), "out-of-range positional light can skip deformation")
		light.free()
	# Independent geometric cases: behind, beside, above, and beyond far plane.
	var frustum := camera.get_frustum()
	for origin: Vector3 in [Vector3(0, 0, 10), Vector3(100, 0, -5), Vector3(0, 100, -5), Vector3(0, 0, -camera.far - 10)]:
		var direction := (Vector3(0, 0, -5) - origin).normalized()
		_check(CharacterModelScript._shadow_ray_intersects_frustum(origin, 2.0, direction, frustum), "ray from outside frustum toward visible receiver must remain animated")
		_check(not CharacterModelScript._shadow_ray_intersects_frustum(origin, 2.0, -direction, frustum), "ray leaving frustum can skip deformation")
	# Cache release/rebuild must reconnect once and rediscover existing lights.
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	stage.add_child(sun)
	CharacterModelScript._release_shadow_light_registry()
	_check(model._pose_may_be_visible(), "registry rebuild rediscovers existing shadow lights")
	sun.free()
	CharacterModelScript._release_shadow_light_registry()
	model.position = original_position
	camera.free()
	model.reset_animation()


func _assert_target_facing(stage: Node3D) -> void:
	var actor: TargetActor = TargetScript.new()
	actor.index = 0
	stage.add_child(actor)
	actor.global_position = Vector3(1.0, 0.0, 2.0)
	var aim_target := Vector3(4.0, 1.0, 6.0)
	actor.face_aim_target(aim_target)
	var planar_direction := aim_target - actor.global_position
	planar_direction.y = 0.0
	planar_direction = planar_direction.normalized()
	var actor_forward := -actor.global_basis.z.normalized()
	var mdl_source_forward := (
		actor.character_model.global_basis * Vector3.RIGHT
	).normalized()
	_check(
		actor_forward.dot(planar_direction) >= 0.999
		and mdl_source_forward.dot(planar_direction) >= 0.999,
		"target yaw and MDL +X source-forward axis face the aim target",
	)
	var expected_pitch := rad_to_deg(atan2(1.0, 5.0))
	_check(
		is_equal_approx(actor.character_model._aim_pitch_degrees, expected_pitch),
		"target vertical aim drives the authored XR pitch controller",
	)
	actor.queue_free()


func _first_vertex(instance: MeshInstance3D) -> Vector3:
	var arrays := (instance.mesh as ArrayMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return vertices[0]
