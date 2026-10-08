extends SceneTree

const PlayerScript = preload("res://scripts/player.gd")
const RouterScript = preload("res://scripts/cs16_audio_event_router.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	_check(AudioServer.get_driver_name() == "Dummy", "ownership fixture must remain muted")
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var router := RouterScript.new()
	router.name = RouterScript.NODE_NAME
	stage.add_child(router)
	router.set_process(false)
	var remote := PlayerScript.new()
	_check(not remote.configure_remote_human(1) and not remote.configure_remote_human(33),
		"remote slots exclude the local player and out-of-range IDs")
	_check(remote.configure_remote_human(2), "valid remote slot configures before tree entry")
	remote.configure_identity("T", "Remote Two")
	stage.add_child(remote)
	remote.set_physics_process(false)
	_check(root.get_camera_3d() == null, "a remote-only world does not acquire a viewport camera")
	var local := PlayerScript.new()
	local.configure_identity("CT", "Local Human")
	stage.add_child(local)
	local.set_physics_process(false)
	local.position = Vector3(3, 0, 0)
	var other := PlayerScript.new()
	_check(other.configure_remote_human(3), "second remote slot configures")
	other.configure_identity("CT", "Remote Three")
	stage.add_child(other)
	other.set_physics_process(false)
	other.position = Vector3(-3, 0, 0)
	_check(root.get_camera_3d() == local.camera, "remote insertion never steals the local camera")
	_check(local.combat_controller is HumanCombatController and local.is_processing_input(),
		"local controller and input processing remain intact")
	for pawn: PlayerController in [remote, other]:
		_check(not pawn.is_local_human() and not pawn.is_processing_input(), "remote never subscribes to device input")
		_check(pawn.combat_controller.get_script() == preload("res://scripts/network_human_controller.gd"),
			"remote starts with network input, not a temporary keyboard controller")
		_check(pawn.combat_controller.actor == pawn, "remote controller possesses its own actor")
		_check(pawn.viewmodel == null and pawn.weapon_anchor == null and pawn.muzzle_light == null,
			"remote does not allocate first-person models or lights")
		_check(pawn.character_model.model_loaded and pawn.character_model.weapon_instance != null,
			"remote has an authentic third-person body and carried weapon")
		_check(pawn.collision_layer == 2, "remote hull participates in normal bullet and movement queries")
		_check(not pawn.configure_remote_human(4), "live ownership changes are rejected")
	_check(local.is_in_group("player") and not remote.is_in_group("player")
		and get_nodes_in_group("human_players").size() == 3, "local-only and shared-human groups stay distinct")
	_check(local.audio_entity_id() == 1 and remote.audio_entity_id() != other.audio_entity_id()
		and remote.audio_entity_id() > 1000000, "stable remote audio namespace cannot collide with local or map IDs")
	for pawn: PlayerController in [local, remote, other]:
		_check(pawn._emit_audio("glock18.fire", RouterScript.CHAN_WEAPON) > 0, "each human emits its own weapon voice")
	_check(router.active_voice_count() == 3, "simultaneous human shots do not replace each other's channel")
	remote._emit_audio("glock18.fire", RouterScript.CHAN_WEAPON)
	_check(router.active_voice_count() == 3, "same actor still replaces its own weapon channel")
	var settings := root.get_node("GameSettings")
	var original_fov: float = settings.field_of_view
	var original_motion: bool = settings.reduced_motion
	settings.field_of_view = 100.0
	settings.reduced_motion = false
	settings.changed.emit()
	remote.velocity = Vector3(2.5, 0, 0)
	remote._step_distance = 0.1
	remote._apply_view_bob()
	_check(local.camera.fov == 100.0 and remote.camera.fov == 74.0,
		"host settings affect only the local camera")
	_check(is_equal_approx(remote.camera.position.y, PlayerScript.STAND_EYE),
		"host view bob does not alter remote authoritative eye height")
	remote._apply_command_look({"view_angles": Vector2(0.7, -0.2)})
	remote._apply_command_look({"look_delta": Vector2(100, 100)})
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(500, 500)
	remote.look_enabled = true
	remote._input(mouse)
	_check(remote.input_view_angles().is_equal_approx(Vector2(0.7, -0.2)),
		"local mouse paths cannot alter remote absolute look")
	remote._update_character_motion()
	_check(is_equal_approx(remote.character_model._aim_pitch_degrees, rad_to_deg(-0.2)),
		"remote model follows authoritative aim")
	settings.field_of_view = original_fov
	settings.reduced_motion = original_motion
	settings.changed.emit()
	remote.combat_effects.warm_up_presentation.call_deferred(local.camera)
	if not remote.combat_effects.presentation_is_ready:
		await remote.combat_effects.presentation_ready
	# Exercise simulation branches that used to dereference a first-person model.
	for weapon: String in ["glock18", "usp", "ak47", "knife", "hegrenade"]:
		remote.grant_item(weapon)
		remote.switch_weapon(weapon)
		remote.weapon_clock.reset(weapon)
		remote.reloading = false
		_check(remote.character_model.weapon_name == weapon, "third-person weapon tracks inventory: " + weapon)
		remote._try_fire()
		if weapon == "hegrenade":
			remote._spawn_thrown_grenade()
		elif weapon != "knife":
			_check(remote.clip < int(PlayerScript.WEAPONS[weapon].magazine), "remote firearm spends ammo: " + weapon)
			remote._start_reload()
			remote._complete_reload()
			remote.weapon_clock.reset(weapon)
			remote._try_secondary()
	remote.reset_player(Vector3.ZERO, false)
	var body := remote.character_model.body_instance
	remote.receive_damage(1000, Vector3.ZERO, false, other)
	_check(not remote.alive and remote.character_model._dead, "remote death drives the world model")
	remote.reset_player(Vector3.ZERO, false)
	_check(remote.alive and not remote.character_model._dead and remote.character_model.body_instance == body,
		"same-loadout respawn clears death without rebuilding shared meshes")
	remote.configure_identity("CT", "Remote Two")
	remote.reset_player(Vector3.ZERO, false)
	_check(remote.character_model.skin_name == TargetActor.skin_for_team("CT", 1)
		and remote.character_model.weapon_name == "usp", "side switch refreshes skin family and starting pistol")
	_check(root.get_camera_3d() == local.camera, "weapon/death/respawn paths preserve local camera ownership")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			await _capture_pair(stage, local, remote, other, argument.trim_prefix("--capture="))
	stage.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	for failure in failures:
		push_error(failure)
	print("GAME_NETWORK_HUMAN_OWNERSHIP_PASS" if failures.is_empty() else "GAME_NETWORK_HUMAN_OWNERSHIP_FAIL")
	quit(0 if failures.is_empty() else 1)


func _capture_pair(stage: Node3D, local: PlayerController, remote: PlayerController,
		other: PlayerController, path: String) -> void:
	if DisplayServer.get_name() == "headless" or not path.is_absolute_path():
		_check(false, "capture requires a rendered viewport and absolute output path")
		return
	# Visual inspection of the same production remote pawns, not proxy bot models.
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#25313d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	world_environment.environment = environment
	stage.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	remote.configure_identity("T", "Remote Two")
	remote.reset_player(Vector3(-0.6, 0, 0), false)
	other.reset_player(Vector3(0.6, 0, 0), false)
	local.weapon_anchor.hide()
	local.camera.global_position = Vector3(0, 0.9, 2.3)
	local.camera.look_at(Vector3(0, 0.35, 0))
	for pawn: PlayerController in [remote, other]:
		pawn.face_toward(local.camera.global_position)
		pawn._movement_grounded = true
		pawn._update_character_motion()
	for frame in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_camera_3d() == local.camera, "rendered view remains owned by local pawn")
	_check(root.get_texture().get_image().save_png(path) == OK, "remote pair capture is written")
	print("NETWORK_HUMAN_OWNERSHIP_CAPTURE ", path)
