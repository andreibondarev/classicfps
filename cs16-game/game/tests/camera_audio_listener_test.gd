extends SceneTree

## Silent integration check: distance attenuation follows the camera owning
## the viewport, including spectator handoffs. This is not PCM/panning parity.
var failures: Array[String] = []
var observations: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _probe(game: Node, label: String) -> void:
	var camera: Camera3D = game.get_viewport().get_camera_3d()
	_check(is_instance_valid(camera), label + ": viewport has a camera")
	if not is_instance_valid(camera):
		return
	var expected := CS16AudioEventRouter.meters_to_hu(camera.global_position)
	var emitter := expected + Vector3(0, 0, 50)
	game.audio_router.stop_all("camera_probe")
	# Start before the tick to check gain refresh on an already active voice.
	var voice: int = game.audio_router.emit_catalog_event("ak47.fire", 991,
		CS16AudioEventRouter.CHAN_WEAPON, emitter)
	game._physics_process(0.01)
	var actual: Vector3 = game.audio_playback.listener_origin_hu
	_check(actual.is_equal_approx(expected), label + ": listener follows the active camera in HU")
	var states: Array[Dictionary] = game.audio_playback.active_playbacks()
	var found := false
	for state: Dictionary in states:
		if int(state.voice_id) == voice:
			found = true
			_check(absf(float(state.distance_hu) - 50.0) < 0.001, label + ": existing voice distance refreshes")
			_check(is_equal_approx(float(state.gain), CS16AudioPlaybackAdapter.attenuation_gain(50.0,
				CS16AudioEventRouter.ATTN_NORM)), label + ": voice gain uses the active camera")
	_check(found, label + ": test voice remains active")
	observations.append({"case": label, "camera": str(camera.name),
		"listener_error_hu": actual.distance_to(expected)})


func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	game.audio_playback.playback_enabled = false
	await process_frame
	await physics_frame
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.spectator_camera.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	_probe(game, "deployment")
	game.start_match()
	game._begin_live()
	_probe(game, "first_person")
	game.trigger_camera.global_position = game.player.camera.global_position + Vector3(5, 1, 0)
	game.trigger_camera.make_current()
	_probe(game, "alternate_camera")
	game.player.camera.make_current()
	game.player.apply_damage(10000.0, Vector3.ZERO, false, null)
	game.spectator_camera._physics_process(CS16SpectatorCamera.ACTIVATION_DELAY + 0.01)
	game.spectator_camera._physics_process(1.0)
	_check(game.spectator_camera.active, "death activates the chase camera")
	_check(game.spectator_camera.camera.global_position.distance_to(game.player.camera.global_position) > 0.5,
		"negative control: chase camera differs from the dead player's view")
	_probe(game, "death_chase")
	game.spectator_camera.cycle(1)
	game.spectator_camera._physics_process(1.0)
	_probe(game, "cycled_chase")
	game._on_team_selected(6)
	game.spectator_camera._physics_process(0.01)
	game.spectator_camera._physics_process(1.0)
	_check(game.player.team == Combatant.TEAM_UNASSIGNED, "intentional observer has no combat team")
	_probe(game, "intentional_observer")
	for bot: TargetActor in game._all_bots():
		bot.apply_damage(10000.0, Vector3.ZERO, false, null)
	game.spectator_camera._physics_process(0.01)
	_check(game.spectator_camera.target == null, "no-target spectator holds its camera")
	_probe(game, "no_target")
	# Exercise the existing join/reset path to restore the participant camera.
	game._on_team_selected(1)
	var reset_events: Array[Dictionary] = [{"type": "round_start", "round": 2}, {"type": "phase", "phase": "freeze"}]
	game._consume_round_events(reset_events)
	_probe(game, "respawn")
	game.audio_router.stop_all("test_teardown")
	game.audio_playback.clear_pool()
	var tested_map: String = game.map_name
	game.queue_free()
	await process_frame
	MdlCharacterModel.release_cached_resources()
	MdlViewModel.release_cached_resources()
	CS16CombatEffects.release_cached_resources()
	await create_timer(0.2).timeout
	print("CAMERA_AUDIO_LISTENER ", JSON.stringify({"audio_muted": true, "map": tested_map,
		"renderer": RenderingServer.get_current_rendering_method(), "gpu_measured": false,
		"pcm_parity_test": false, "observations": observations, "failures": failures}))
	for failure in failures:
		push_error(failure)
	print("GAME_CAMERA_AUDIO_LISTENER_PASS" if failures.is_empty() else "GAME_CAMERA_AUDIO_LISTENER_FAIL")
	quit(0 if failures.is_empty() else 1)
