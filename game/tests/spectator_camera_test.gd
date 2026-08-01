extends SceneTree
## Death spectate camera integration test: player death mid-live-phase enters
## chase-cam on a living teammate, auto-advances when that teammate dies, and
## a round reset restores the first-person player camera.

const CS16CombatEffects := preload("res://scripts/cs16_combat_effects.gd")
const MdlCharacterModel := preload("res://scripts/mdl_character_model.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SPECTATOR CAMERA TEST: " + message)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game = packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.set_physics_process(false)

	game.round_state.configure({
		"freeze_ticks": 1,
		"round_ticks": 100000,
		"restart_ticks": 2,
	})
	game.start_match()
	_advance_game_round(game, 1)
	_check(game.phase == "live", "fixture reaches the live phase")
	_check(
		is_instance_valid(game.spectator_camera),
		"game builds the death spectator camera node",
	)
	_check(
		game.player.camera.current,
		"player first-person camera is current while alive",
	)

	# Kill the human player mid-live.
	game.player.apply_damage(10000.0, Vector3.ZERO, false, null)
	_check(not game.player.alive, "lethal damage kills the player")
	_check(
		game.spectator_camera.pending and not game.spectator_camera.active,
		"death schedules spectating after the CS 1.6 corpse-view delay",
	)
	_check(
		game.player.camera.current,
		"corpse view keeps the player camera during the delay",
	)

	# ~3 s of physics frames crosses the 2 s activation delay.
	await _advance_seconds(3.0)
	_check(game.spectator_camera.active, "spectating activates after ~2 s")
	_check(
		game.spectator_camera.camera.current,
		"spectator chase camera becomes the current camera",
	)
	var spectated = game.spectator_camera.target
	_check(
		is_instance_valid(spectated)
		and spectated.alive
		and spectated.team == game.player.team,
		"spectate target is a living teammate",
	)
	_check(
		game.hud.spectate_label.text == "Spectating: %s" % spectated.display_name,
		"HUD shows the classic Spectating label with the target name",
	)

	# Chase framing: behind and above the target, looking at it.
	await _advance_seconds(1.0)
	var head: Vector3 = spectated.global_position + Vector3.UP * 0.53
	var cam_pos: Vector3 = game.spectator_camera.camera.global_position
	_check(
		cam_pos.distance_to(head) > 0.3 and cam_pos.y > spectated.global_position.y,
		"chase camera sits away from and above the target",
	)
	var to_head := (head - cam_pos).normalized()
	var cam_forward: Vector3 = -game.spectator_camera.camera.global_transform.basis.z
	_check(
		cam_forward.dot(to_head) > 0.9,
		"chase camera looks toward the spectated teammate",
	)

	# Manual cycle mirrors fire/secondary clicks.
	var before_cycle = game.spectator_camera.target
	game.spectator_camera.cycle(1)
	var after_cycle = game.spectator_camera.target
	_check(
		is_instance_valid(after_cycle) and after_cycle.alive,
		"cycling selects a living teammate",
	)
	_check(
		after_cycle != before_cycle
		or game._living_spectate_teammates().size() == 1,
		"cycling advances to the next teammate when several are alive",
	)

	# Kill the spectated teammate: the camera must auto-advance.
	var victim = game.spectator_camera.target
	victim.apply_damage(10000.0, Vector3.ZERO, false, null)
	_check(not victim.alive, "lethal damage kills the spectated teammate")
	await _advance_seconds(0.5)
	var advanced = game.spectator_camera.target
	_check(
		is_instance_valid(advanced) and advanced != victim and advanced.alive,
		"spectator auto-advances off a dead teammate",
	)
	_check(
		game.spectator_camera.camera.current,
		"spectator camera stays current across the auto-advance",
	)

	# Round reset restores the first-person view.
	var reset_events: Array[Dictionary] = [
		{"type": "round_start", "round": 2},
		{"type": "phase", "phase": "freeze"},
	]
	game._consume_round_events(reset_events)
	_check(game.player.alive, "round reset revives the player")
	_check(
		not game.spectator_camera.active and not game.spectator_camera.pending,
		"round reset ends spectating",
	)
	_check(
		game.player.camera.current,
		"round reset restores the first-person player camera",
	)
	_check(
		game.hud.spectate_label.text.is_empty(),
		"round reset clears the Spectating HUD label",
	)

	if failures.is_empty():
		print("GAME_SPECTATOR_CAMERA_TEST_PASS")
		await _teardown(game)
		quit(0)
	else:
		print("GAME_SPECTATOR_CAMERA_TEST_FAIL (%d)" % failures.size())
		await _teardown(game)
		quit(1)


func _advance_seconds(seconds: float) -> void:
	var frames := int(ceil(seconds * Engine.physics_ticks_per_second))
	for ignored in range(frames):
		await physics_frame


func _advance_game_round(game: Node, ticks: int) -> void:
	for ignored in range(ticks):
		var events: Array[Dictionary] = game.round_state.advance_tick()
		game._consume_round_events(events)
		game._consumed_round_events = game.round_state.trace.size()
		game._sync_round_public_state()
		game._update_round_hud(true)


func _teardown(game: Node) -> void:
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.audio_router.stop_all("test_teardown")
	await process_frame
	game.audio_playback.clear_pool()
	await create_timer(0.05).timeout
	current_scene = null
	game.queue_free()
	await process_frame
	await process_frame
	CS16CombatEffects.release_cached_resources()
	MdlCharacterModel.release_cached_resources()
