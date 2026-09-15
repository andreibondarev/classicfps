extends SceneTree

const Model := preload("res://scripts/mdl_character_model.gd")
const SKINS := ["terror", "leet", "arctic", "guerilla", "urban", "gsg9", "sas", "gign"]
var failures: Array[String] = []
var comparisons := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for skin: String in SKINS:
		_check_template("res://generated/players/%s/model.json" % skin)
	_check_template("res://generated/hostages/hostage/model.json")
	# The lowest vertex changes halfway through the interpolation: interpolating
	# cached endpoint minima would return zero instead of the correct five.
	var synthetic := {"vertex_float_count": 6}
	var animation := {"frames": 2, "blends": 1,
		"positions": PackedFloat32Array([0, 0, 0, 0, 10, 0, 0, 10, 0, 0, 0, 0])}
	_check(Model._blended_minimum_y(synthetic, animation, 0, 1, 0.5, 0, 0, 0.0) == 5.0,
		"interpolated minimum must follow the actual vertices, not endpoint minima")
	_compare(synthetic, animation, 0, 1, 0.5, 0, 0, 0.0, "crossing minimum")
	var template := Model._load_template("res://generated/players/terror/model.json")
	var gait: Dictionary = template.animations.run
	var started := Time.get_ticks_usec()
	var actual_sum := 0.0
	for index in 200:
		actual_sum += Model._blended_minimum_y(template, gait, 0, 1, float(index % 100) / 100.0, 0, 0, 0.0)
	var actual_us := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var reference_sum := 0.0
	for index in 200:
		reference_sum += _reference(template, gait, 0, 1, float(index % 100) / 100.0, 0, 0, 0.0)
	var reference_us := Time.get_ticks_usec() - started
	_check(actual_sum == reference_sum, "benchmark inputs have identical grounding results")
	print("ANIMATION_GROUNDING_METRICS ", JSON.stringify({"comparisons": comparisons,
		"queries": 200, "production_us": actual_us, "reference_us": reference_us}))
	Model.release_cached_resources()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	print("GAME_ANIMATION_GROUNDING_PASS" if failures.is_empty() else "GAME_ANIMATION_GROUNDING_FAIL")
	quit(0 if failures.is_empty() else 1)


func _check_template(path: String) -> void:
	var template := Model._load_template(path)
	_check(not template.is_empty(), "source template loads: " + path)
	if template.is_empty():
		return
	for state: String in template.animations:
		var animation: Dictionary = template.animations[state]
		var count := int(animation.frames)
		var last_blend := int(animation.blends) - 1
		for frame: int in [0, count / 2, count - 1]:
			var next_frame := (frame + 1) % count
			for alpha: float in [0.0, 0.37, 1.0]:
				for pitch: float in [0.0, 0.61, 1.0]:
					_compare(template, animation, frame, next_frame, alpha, 0, last_blend, pitch, path + ":" + state)
			# Coincident pitch/frame offsets with a nonzero interpolation weight.
			_compare(template, animation, frame, frame, 0.37, last_blend, last_blend, 0.61, path + ":" + state)


func _compare(template: Dictionary, animation: Dictionary, frame: int, next_frame: int,
		alpha: float, low: int, high: int, pitch: float, label: String) -> void:
	var actual := Model._blended_minimum_y(template, animation, frame, next_frame, alpha, low, high, pitch)
	var expected := _reference(template, animation, frame, next_frame, alpha, low, high, pitch)
	comparisons += 1
	_check(actual == expected, "exact source grounding parity: " + label)


static func _reference(template: Dictionary, animation: Dictionary, frame: int, next_frame: int,
		alpha: float, low: int, high: int, pitch: float) -> float:
	# Deliberately retain the unoptimized four-source-sample implementation.
	var positions: PackedFloat32Array = animation.positions
	var a := Model._pose_float_offset(template, animation, frame, low)
	var b := Model._pose_float_offset(template, animation, frame, high)
	var c := Model._pose_float_offset(template, animation, next_frame, low)
	var d := Model._pose_float_offset(template, animation, next_frame, high)
	var minimum := INF
	for y in range(1, int(template.vertex_float_count), 3):
		minimum = minf(minimum, lerpf(lerpf(positions[a + y], positions[b + y], pitch),
			lerpf(positions[c + y], positions[d + y], pitch), alpha))
	return minimum


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
