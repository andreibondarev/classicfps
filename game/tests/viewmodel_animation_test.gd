extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var viewmodel := MdlViewModel.new()
	stage.add_child(viewmodel)

	_check(viewmodel.load_weapon("ak47"), "animated AK-47 viewmodel loads")
	_check(
		viewmodel.base_position == MdlViewModel.CLASSIC_BASE_POSITION,
		"AK-47 uses the calibrated classic camera-space placement",
	)
	_check(
		viewmodel.model_root.scale == MdlViewModel.CLASSIC_MODEL_SCALE,
		"AK-47 uses the calibrated mirrored horizontal framing",
	)
	_check(viewmodel._template.animations.has("idle1"), "AK-47 idle sequence is available")
	_check(viewmodel._template.animations.has("reload"), "AK-47 reload sequence is available")
	_check(viewmodel._template.animations.has("shoot1"), "AK-47 fire sequence is available")
	_check(
		is_instance_valid(viewmodel._model_instance)
		and viewmodel._model_instance.mesh.get_surface_count() == 11,
		"AK-47 renders all original MDL texture groups",
	)
	for group: Dictionary in viewmodel._template.groups:
		var material := group.material as StandardMaterial3D
		_check(
			material != null and not material.no_depth_test,
			"AK-47 texture groups retain self-depth instead of material-order overpaint",
		)

	viewmodel.play_action("fire")
	_check(viewmodel._animation_name.begins_with("shoot"), "fire selects an MDL shoot sequence")
	viewmodel._process(0.1)
	_check(viewmodel._frame_key.begins_with("shoot"), "fire advances an animated MDL frame")
	viewmodel._process(2.0)
	_check(viewmodel._animation_name == "idle1", "completed fire returns to looping idle")

	viewmodel.play_action("reload")
	_check(viewmodel._animation_name == "reload", "reload selects the original MDL sequence")
	viewmodel._process(0.25)
	_check(viewmodel._frame_key.begins_with("reload"), "reload advances original MDL frames")

	_check(viewmodel.load_weapon("knife"), "animated knife viewmodel loads")
	for group: Dictionary in viewmodel._template.groups:
		var material := group.material as StandardMaterial3D
		_check(
			material != null and not material.no_depth_test,
			"knife texture groups retain self-depth",
		)
	viewmodel.play_action("knife")
	_check(
		viewmodel._animation_name in ["slash1", "slash2", "stab", "midslash1", "midslash2"],
		"knife attack selects an original knife sequence",
	)

	_check(viewmodel.load_weapon("glock18"), "animated Glock viewmodel loads")
	_check(
		viewmodel.base_position == MdlViewModel.GLOCK_BASE_POSITION,
		"Glock uses its measured bottom-edge camera-space placement",
	)
	_check(
		is_instance_valid(viewmodel._model_instance)
		and viewmodel._model_instance.mesh.get_surface_count() == 7,
		"Glock renders all original MDL texture groups",
	)
	for group: Dictionary in viewmodel._template.groups:
		var material := group.material as StandardMaterial3D
		_check(
			material != null and not material.no_depth_test,
			"Glock texture groups retain self-depth",
		)

	_check(viewmodel.load_weapon("c4"), "animated C4 viewmodel loads")
	_check(
		viewmodel.base_position == MdlViewModel.C4_BASE_POSITION
		and viewmodel.model_root.scale == MdlViewModel.C4_MODEL_SCALE,
		"C4 uses its source-model-specific full-frame calibration",
	)
	_check(
		viewmodel._template.animations.has("draw")
		and viewmodel._template.animations.has("pressbutton")
		and viewmodel._template.animations.has("drop"),
		"C4 exposes the original deploy/arming/final-drop sequence strip",
	)
	_check(
		is_instance_valid(viewmodel._model_instance)
		and viewmodel._model_instance.mesh.get_surface_count() == 8,
		"C4 renders every original v_c4 texture group",
	)

	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		print("GAME_VIEWMODEL_ANIMATION_TEST_FAIL (%d)" % _failures.size())
		quit(1)
		return

	print("GAME_VIEWMODEL_ANIMATION_TEST_PASS")
	quit()
