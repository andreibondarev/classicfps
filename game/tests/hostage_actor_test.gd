extends SceneTree

const HostageScript := preload("res://scripts/cs16_hostage.gd")
const HostageModelScript := preload("res://scripts/mdl_hostage_model.gd")
const CombatantScript := preload("res://scripts/combatant.gd")

const POSITION_TOLERANCE := 0.0001
const FOOT_TOLERANCE := 1.0 * 0.01

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	stage.name = "HostageActorStage"
	root.add_child(stage)
	current_scene = stage

	var hostage: CS16Hostage = HostageScript.new()
	hostage.configure("hostage_01", 0)
	hostage.auto_advance_animation = false
	stage.add_child(hostage)
	_check(hostage.hostage_model.model_loaded, "source hostage model loads")
	_assert_source_hull(hostage)
	_assert_source_model(hostage.hostage_model)
	_assert_authentic_skins(hostage.hostage_model)
	_assert_animation_tape(hostage)
	_assert_presence_states(hostage)
	_assert_use_contract(hostage, stage)
	_assert_contract_snapshot(hostage)

	if failures.is_empty():
		print("GAME_HOSTAGE_ACTOR_TEST_PASS")
		current_scene = null
		stage.queue_free()
		await process_frame
		quit(0)
	else:
		for failure: String in failures:
			push_error("HOSTAGE ACTOR TEST: " + failure)
		print("GAME_HOSTAGE_ACTOR_TEST_FAIL (%d)" % failures.size())
		current_scene = null
		stage.queue_free()
		await process_frame
		quit(1)


func _assert_source_hull(hostage: CS16Hostage) -> void:
	var shape := hostage.collision_shape.shape as BoxShape3D
	_check(
		shape.size.is_equal_approx(Vector3(0.20, 0.62, 0.20)),
		"collision hull is exact 20x20x62 GoldSrc HU",
	)
	_check(
		hostage.collision_shape.position.is_equal_approx(Vector3(0.0, 0.31, 0.0)),
		"feet-space hull center is exact 31 HU",
	)


func _assert_source_model(model: MdlHostageModel) -> void:
	_check(
		model.scale.is_equal_approx(Vector3.ONE),
		"hostage preserves converted 0.01-HU source scale",
	)
	for state: String in [
		"idle",
		"acknowledge",
		"cower",
		"walk",
		"run",
		"flinch",
		"die",
	]:
		model.force_state(state, 1)
		var bounds := model.mesh_instance.mesh.get_aabb()
		var floor_height := model.mesh_instance.position.y + bounds.position.y
		_check(
			absf(floor_height) <= FOOT_TOLERANCE,
			"%s source pose stays grounded within 1 HU" % state,
		)


func _assert_authentic_skins(model: MdlHostageModel) -> void:
	model.set_skin(0)
	var skin_zero := _surface_texture_paths(model)
	model.set_skin(1)
	var skin_one := _surface_texture_paths(model)
	_check(
		skin_zero == [
			"res://generated/hostages/hostage/textures/000_hostage_template1_bmp.tga",
			"res://generated/hostages/hostage/textures/001_face-unwrap1_bmp.tga",
		],
		"skin 0 uses the authored Template1/Face1 pair",
	)
	_check(
		skin_one == [
			"res://generated/hostages/hostage/textures/000_skin1_hostage_template2_bmp.tga",
			"res://generated/hostages/hostage/textures/001_skin1_face-unwrap2_bmp.tga",
		],
		"skin 1 uses the authored Template2/Face2 pair",
	)
	_check(skin_zero != skin_one, "the two source skin families remain distinct")
	model.set_skin(0)


func _assert_animation_tape(hostage: CS16Hostage) -> void:
	var model := hostage.hostage_model
	hostage.reset_actor(0)
	hostage.set_motion_velocity_hu(Vector3.ZERO)
	hostage.advance_hostage_tick()
	_check(
		model.animation_state == "idle"
		# The idle loop starts at a per-hostage random phase (GoldSrc random
		# sequence frame), so only the selected state is exact here.
		and model.current_frame_key.begins_with("idle:"),
		"100 Hz still hostage selects source idle",
	)

	hostage.acknowledge()
	_check(
		model.animation_state == "acknowledge"
		and model.current_frame_key == "acknowledge:0:1:0",
		"acknowledgment starts on exact source frame zero",
	)
	hostage.advance_hostage_tick()
	_check(
		model.current_frame_key == "acknowledge:0:1:655",
		"acknowledgment advances deterministically at 16 FPS on 100 Hz tick",
	)

	hostage.cower(true)
	hostage.advance_hostage_tick()
	_check(
		model.animation_state == "cower"
		and model.current_frame_key == "cower:0:1:737",
		"cower selects the external 18 FPS source tape",
	)

	hostage.cower(false)
	hostage.set_motion_velocity_hu(
		Vector3(HostageModelScript.WALK_SOURCE_SPEED_HU, 0.0, 0.0)
	)
	hostage.advance_hostage_tick()
	_check(
		model.animation_state == "walk"
		and is_equal_approx(model.playback_rate, 1.0)
		and model.current_frame_key == "walk:0:1:819",
		"authored walk speed advances the 20 FPS gait without resampling drift",
	)

	var follow_speed_hu := 250.0
	hostage.set_motion_velocity_hu(Vector3(follow_speed_hu, 0.0, 0.0))
	hostage.advance_hostage_tick()
	_check(model.animation_state == "run", "normal hostage follow speed selects run")
	var cycle_seconds := 19.0 / 25.0 / model.playback_rate
	var traveled_per_cycle := follow_speed_hu * cycle_seconds
	_check(
		absf(traveled_per_cycle - HostageModelScript.RUN_CYCLE_DISTANCE_HU) <= 0.001,
		"follow gait rate matches authored root distance without visible foot skating",
	)

	var tape_a: Array[String] = []
	hostage.reset_actor(0)
	hostage.set_motion_velocity_hu(Vector3(follow_speed_hu, 0.0, 0.0))
	for tick in 40:
		hostage.advance_hostage_tick()
		tape_a.append(model.current_frame_key)
	var tape_b: Array[String] = []
	hostage.reset_actor(0)
	hostage.set_motion_velocity_hu(Vector3(follow_speed_hu, 0.0, 0.0))
	for tick in 40:
		hostage.advance_hostage_tick()
		tape_b.append(model.current_frame_key)
	_check(tape_a == tape_b, "100 Hz hostage animation tape is deterministic")

	hostage.hurt()
	_check(
		model.animation_state == "flinch"
		and model.current_frame_key == "flinch:0:1:0",
		"damage selects source flinch from frame zero",
	)


func _assert_presence_states(hostage: CS16Hostage) -> void:
	hostage.reset_actor(1)
	_check(
		hostage.alive
		and not hostage.rescued
		and hostage.hostage_model.visible
		and not hostage.collision_shape.disabled,
		"alive hostage is visible and solid",
	)
	hostage.die()
	for tick in 200:
		hostage.advance_hostage_tick()
	var death_key := hostage.hostage_model.current_frame_key
	hostage.advance_hostage_tick()
	_check(
		not hostage.alive
		and hostage.hostage_model.visible
		and hostage.collision_shape.disabled
		and death_key == "die:30:30:0"
		and hostage.hostage_model.current_frame_key == death_key,
		"dead hostage is a visible nonsolid corpse frozen on final source frame",
	)
	hostage.reset_actor(0)
	hostage.mark_rescued()
	_check(
		hostage.alive
		and hostage.rescued
		and not hostage.hostage_model.visible
		and hostage.collision_shape.disabled,
		"rescued hostage is hidden and nonsolid",
	)
	hostage.reset_actor(0)


func _assert_use_contract(hostage: CS16Hostage, stage: Node3D) -> void:
	hostage.global_position = Vector3(2.0, 0.0, -3.0)
	_check(
		hostage.source_use_origin().is_equal_approx(Vector3(2.0, 0.31, -3.0)),
		"use candidate origin targets the center of the 62-HU hull",
	)
	var capabilities := hostage.source_use_capabilities()
	_check(
		is_equal_approx(float(capabilities.radius_hu), 64.0)
		and is_equal_approx(float(capabilities.view_dot), 0.7),
		"use capability advertises source 64-HU/narrow-FOV contract",
	)
	var ct: Combatant = CombatantScript.new()
	ct.team = CombatantScript.TEAM_COUNTER_TERRORIST
	stage.add_child(ct)
	var terrorist: Combatant = CombatantScript.new()
	terrorist.team = CombatantScript.TEAM_TERRORIST
	stage.add_child(terrorist)
	var requests := [0]
	hostage.use_requested.connect(
		func(_hostage: CS16Hostage, _actor: Node) -> void:
			requests[0] += 1
	)
	_check(
		hostage.source_use_usable(ct)
		and not hostage.source_use_usable(terrorist)
		and hostage.request_source_use(ct)
		and requests[0] == 1,
		"only a live CT can request hostage use",
	)
	hostage.mark_rescued()
	_check(
		not hostage.source_use_usable(ct) and not hostage.request_source_use(ct),
		"rescued hostage is removed from use resolution",
	)
	hostage.reset_actor(0)


func _assert_contract_snapshot(hostage: CS16Hostage) -> void:
	hostage.apply_contract_state({
		"id": "hostage_snapshot",
		"skin": 1,
		"alive": true,
		"rescued": false,
		"following": true,
		"leader_id": "ct_01",
		"position_hu": Vector3(128.0, 4.0, -64.0),
		"yaw_degrees": 90.0,
	})
	_check(
		hostage.hostage_id == "hostage_snapshot"
		and hostage.skin_index == 1
		and hostage.following
		and hostage.leader_id == "ct_01"
		and hostage.global_position.distance_to(Vector3(1.28, 0.04, -0.64))
			<= POSITION_TOLERANCE
		and absf(hostage.rotation.y - PI * 0.5) <= POSITION_TOLERANCE,
		"actor consumes authoritative hostage-state position/yaw/skin/follow snapshot",
	)


func _surface_texture_paths(model: MdlHostageModel) -> Array[String]:
	var paths: Array[String] = []
	var mesh := model.mesh_instance.mesh as ArrayMesh
	for surface_index in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface_index) as StandardMaterial3D
		paths.append(material.albedo_texture.resource_path)
	return paths


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
