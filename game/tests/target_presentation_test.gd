extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("TARGET PRESENTATION TEST: " + message)


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var actor := TargetActor.new()
	stage.add_child(actor)
	actor.set_physics_process(false)
	actor.character_model.set_process(false)
	actor.configure_weapon("ak47")
	var original := actor.character_model
	var original_body := original.body_instance
	var original_weapon := original.weapon_instance
	var original_body_mesh := original_body.mesh
	var original_weapon_mesh := original_weapon.mesh
	original.force_pose("crouchshoot", 0.4, 20.0)
	original.play_death()
	actor.weapon_clip = 0
	actor.weapon_reloading = true
	_check(actor.configure_weapon("ak47"), "same weapon configuration succeeds")
	_check(actor.character_model == original and original.body_instance == original_body
		and original.weapon_instance == original_weapon, "same weapon reuses character and GPU mesh instances")
	_check(original_body.mesh == original_body_mesh and original_weapon.mesh == original_weapon_mesh,
		"same weapon retains the existing mesh resources")
	_check(not original._dead and original._action_state.is_empty()
		and original._animation_time == 0.0 and original._aim_pitch_degrees == 0.0
		and original.dropped_weapon_instance == null, "reused model clears death, actions, pitch, and dropped visual")
	_check(actor.weapon_clip == 30 and not actor.weapon_reloading, "inventory and weapon reset are not skipped")
	_assert_fresh_pose(stage, actor, "ak47")

	actor.configure_weapon("glock18", false)
	actor.configure_weapon("mp5", false)
	actor.configure_weapon("hegrenade", false)
	_check(actor.character_model == original and original.weapon_name == "ak47", "intermediate buys do not rebuild presentation")
	_check(actor.active_weapon_name == "mp5" and actor.weapon_clip == 30
		and actor.grenade_count("hegrenade") == 1, "batched inventory updates remain synchronous")
	actor.refresh_weapon_presentation()
	_check(actor.character_model != original and actor.character_model.weapon_name == "mp5",
		"final presentation uses the actual purchased weapon and its action family")
	_assert_fresh_pose(stage, actor, "mp5")
	var final_model := actor.character_model
	actor.refresh_weapon_presentation()
	_check(actor.character_model == final_model, "repeated finalization does not allocate another model")
	actor.set_c4_state(true, true)
	var c4_model := actor.character_model
	actor.configure_weapon("ak47", false)
	actor.refresh_weapon_presentation()
	_check(actor.character_model == c4_model and c4_model.weapon_name == "c4", "buy finalization preserves equipped C4")
	actor.set_c4_state(false, false)
	_check(actor.character_model.weapon_name == "ak47", "unequipping C4 restores the authoritative carried gun")
	var prior_skin_model := actor.character_model
	actor.player_skin = "urban" if actor.player_skin != "urban" else "terror"
	actor.refresh_weapon_presentation()
	_check(actor.character_model != prior_skin_model and actor.character_model.skin_name == actor.player_skin,
		"same gun does not suppress a requested character-skin change")
	_assert_fresh_pose(stage, actor, "ak47")
	await _assert_character_reload(stage)
	stage.queue_free()
	await process_frame
	print("GAME_TARGET_PRESENTATION_TEST_PASS" if failures.is_empty() else "GAME_TARGET_PRESENTATION_TEST_FAIL")
	quit(0 if failures.is_empty() else 1)


func _assert_character_reload(stage: Node3D) -> void:
	var model := MdlCharacterModel.new()
	stage.add_child(model)
	model.set_process(false)
	_check(model.load_character("terror", "ak47"), "reload fixture loads")
	model.play_death()
	var retired := [weakref(model.body_instance), weakref(model.weapon_instance),
		weakref(model.dropped_weapon_instance)]
	model._environment_tint = Color(0.2, 0.3, 0.4)
	model._tint_timer = 0.0
	for index in range(6):
		var skin := "urban" if index % 2 == 0 else "terror"
		var weapon := "mp5" if index % 2 == 0 else "glock18"
		_check(model.load_character(skin, weapon), "repeated skin/weapon load succeeds")
		_check(model.get_child_count() == 2, "reload leaves exactly one body and attached weapon immediately")
		_check(model.skin_name == skin and model.weapon_name == weapon
			and not model._dead and model.dropped_weapon_instance == null,
			"reload replaces identity and clears corpse/drop state")
		_check(model._environment_tint == Color.WHITE and is_inf(model._tint_timer),
			"replacement materials receive a fresh lighting sample")
		await process_frame
		_check(model.get_child_count() == 2, "repeated reload does not accumulate mesh children")
	for ref: WeakRef in retired:
		_check(ref.get_ref() == null, "reload releases the previous body, gun, and dropped-gun nodes")
	var body := model.body_instance
	var weapon := model.weapon_instance
	var skin := model.skin_name
	var weapon_name := model.weapon_name
	_check(not model.load_character("missing_reload_test_skin", "ak47"), "invalid replacement fails")
	_check(model.body_instance == body and model.weapon_instance == weapon
		and model.skin_name == skin and model.weapon_name == weapon_name
		and model.model_loaded and model.get_child_count() == 2,
		"failed load preserves the last usable presentation and identity")


func _assert_fresh_pose(stage: Node3D, actor: TargetActor, weapon: String) -> void:
	var fresh := MdlCharacterModel.new()
	stage.add_child(fresh)
	fresh.set_process(false)
	_check(fresh.load_character(actor.player_skin, weapon), "reference model loads")
	_check(actor.character_model.position == fresh.position, "reset preserves exact fresh-model foot alignment")
	for pair: Array in [[actor.character_model.body_instance, fresh.body_instance],
		[actor.character_model.weapon_instance, fresh.weapon_instance]]:
		var actual: ArrayMesh = pair[0].mesh
		var expected: ArrayMesh = pair[1].mesh
		_check(actual.get_surface_count() == expected.get_surface_count(), "reset preserves source surfaces")
		for surface in expected.get_surface_count():
			var actual_arrays := actual.surface_get_arrays(surface)
			var expected_arrays := expected.surface_get_arrays(surface)
			_check(actual_arrays[Mesh.ARRAY_VERTEX] == expected_arrays[Mesh.ARRAY_VERTEX], "reset pose vertices exactly match fresh construction")
			_check(actual_arrays[Mesh.ARRAY_TEX_UV] == expected_arrays[Mesh.ARRAY_TEX_UV], "reset preserves source UVs")
	fresh.queue_free()
