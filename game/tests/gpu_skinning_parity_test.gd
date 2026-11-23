extends SceneTree

## GPU skinning must pose actors exactly like the CPU fallback that
## character_model_animation_test pins down. Drives one model per path through
## the same states (idle, run and crouch with aim pitch, shoot, reload over a
## gait, airborne, death) and compares every posed vertex of the body and the
## attached weapon, the foot grounding offset and the frame keys. Also checks
## that GPU loading never bakes vertex frames and that actors share meshes.

const Model := preload("res://scripts/mdl_character_model.gd")
const SKINS := ["terror", "leet", "arctic", "guerilla", "urban", "gsg9", "sas", "gign"]
const WEAPONS := ["ak47", "deagle", "knife", "awp", "m3", "hegrenade", "c4", "elite", "mp5"]
const TOLERANCE := 1e-4

var _failures: Array[String] = []
var _comparisons := 0
var _worst := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition and _failures.size() < 40:
		_failures.append(message)


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var started := Time.get_ticks_usec()
	for index in SKINS.size():
		Model.gpu_skinning = true
		_check(Model.prepare_character_assets(SKINS[index], WEAPONS[index % WEAPONS.size()]),
			"%s prepares" % SKINS[index])
	var gpu_prepare_ms := (Time.get_ticks_usec() - started) / 1000.0
	for path: String in Model._template_cache:
		_check(not Model._template_cache[path].get("baked", false), "GPU preparation bakes no vertex frames: " + path)

	for index in SKINS.size():
		var skin: String = SKINS[index]
		for weapon_index in range(index % 3, WEAPONS.size(), 3):
			_compare_scenario(stage, skin, WEAPONS[weapon_index])

	var shared_a := _load(stage, true, "sas", "ak47")
	var shared_b := _load(stage, true, "sas", "ak47")
	_check(shared_a.body_instance.mesh == shared_b.body_instance.mesh
		and shared_a.weapon_instance.mesh == shared_b.weapon_instance.mesh, "GPU actors share one mesh per model")
	_check(shared_a.body_instance.get_surface_override_material(0)
		!= shared_b.body_instance.get_surface_override_material(0), "each actor keeps its own tint materials")

	print("GPU_SKINNING_PARITY_METRICS ", JSON.stringify({"comparisons": _comparisons,
		"worst_vertex_error": _worst, "gpu_prepare_ms": gpu_prepare_ms}))
	Model.release_cached_resources()
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		print("GPU_SKINNING_PARITY_TEST_FAIL (%d)" % _failures.size())
		quit(1)
		return
	print("GPU_SKINNING_PARITY_TEST_PASS")
	quit()


func _load(stage: Node3D, gpu: bool, skin: String, weapon: String) -> MdlCharacterModel:
	Model.gpu_skinning = gpu
	var model: MdlCharacterModel = Model.new()
	stage.add_child(model)
	_check(model.load_character(skin, weapon), "%s/%s loads (gpu=%s)" % [skin, weapon, gpu])
	return model


func _compare_scenario(stage: Node3D, skin: String, weapon: String) -> void:
	var gpu := _load(stage, true, skin, weapon)
	var cpu := _load(stage, false, skin, weapon)
	if not gpu.model_loaded or not cpu.model_loaded:
		return
	_check(gpu._gpu_template(gpu._body_template) and not cpu._gpu_template(cpu._body_template),
		"%s: one model per skinning path" % skin)
	var label := "%s/%s" % [skin, weapon]
	_both(gpu, cpu, func(m: MdlCharacterModel) -> void: m.reset_animation())
	_same(gpu, cpu, label + " reset")
	var steps: Array[Array] = [
		["idle", func(m: MdlCharacterModel) -> void: m.set_locomotion(false)],
		["run up", func(m: MdlCharacterModel) -> void:
			m.set_locomotion(true)
			m.set_aim_pitch(deg_to_rad(23.0))],
		["crouch run down", func(m: MdlCharacterModel) -> void:
			m.set_locomotion(true, true)
			m.set_aim_pitch(deg_to_rad(-31.0))],
		["shoot", func(m: MdlCharacterModel) -> void:
			m.set_locomotion(false)
			m.play_action("shoot")],
		["reload running", func(m: MdlCharacterModel) -> void:
			m.set_locomotion(true)
			m.set_aim_pitch(deg_to_rad(7.0))
			m.play_action("reload")],
		["airborne", func(m: MdlCharacterModel) -> void: m.set_locomotion(true, false, false)],
		["death", func(m: MdlCharacterModel) -> void:
			m.set_locomotion(false)
			m.play_death()],
	]
	for step in steps:
		_both(gpu, cpu, step[1])
		for tick in 9:
			_both(gpu, cpu, func(m: MdlCharacterModel) -> void: m.advance_animation(0.037))
			_same(gpu, cpu, "%s %s tick %d" % [label, step[0], tick])
	for fraction in [0.0, 0.31, 1.0]:
		_both(gpu, cpu, func(m: MdlCharacterModel) -> void: m.force_pose("crouchidle", fraction, 40.0))
		_same(gpu, cpu, "%s forced crouchidle %.2f" % [label, fraction])
	gpu.queue_free()
	cpu.queue_free()


func _both(gpu: MdlCharacterModel, cpu: MdlCharacterModel, step: Callable) -> void:
	step.call(gpu)
	step.call(cpu)


func _same(gpu: MdlCharacterModel, cpu: MdlCharacterModel, label: String) -> void:
	_check(gpu._body_frame_key == cpu._body_frame_key and gpu._weapon_frame_key == cpu._weapon_frame_key,
		"%s: frame keys %s/%s vs %s/%s" % [label, gpu._body_frame_key, gpu._weapon_frame_key,
			cpu._body_frame_key, cpu._weapon_frame_key])
	_check(absf(gpu.position.y - cpu.position.y) <= TOLERANCE,
		"%s: grounding %f vs %f" % [label, gpu.position.y, cpu.position.y])
	_compare_instance(gpu.body_instance, cpu.body_instance, label + " body")
	if is_instance_valid(cpu.weapon_instance) and cpu.weapon_instance.visible:
		_check(gpu.weapon_instance.visible, label + ": weapon visible on both")
		_compare_instance(gpu.weapon_instance, cpu.weapon_instance, label + " weapon")


func _compare_instance(gpu: MeshInstance3D, cpu: MeshInstance3D, label: String) -> void:
	var posed := Model.skinned_vertices(gpu)
	var expected := PackedVector3Array()
	var mesh := cpu.mesh as ArrayMesh
	for surface in mesh.get_surface_count():
		expected.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	_comparisons += 1
	if posed.size() != expected.size():
		_check(false, "%s: %d vs %d vertices" % [label, posed.size(), expected.size()])
		return
	var worst := 0.0
	for index in posed.size():
		var error := posed[index] - expected[index]
		worst = maxf(worst, maxf(absf(error.x), maxf(absf(error.y), absf(error.z))))
	_worst = maxf(_worst, worst)
	_check(worst <= TOLERANCE, "%s: worst vertex error %f" % [label, worst])
