extends SceneTree

## Intentional Spectator selection, distinct from a participant's death camera.
## Scripted eliminations exercise the real MR15 kernel, not a full AI soak.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("OBSERVER MATCH: " + message)


func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.spectator_camera.set_physics_process(false)
	for bot in game._all_bots():
		bot.set_physics_process(false)
	game.round_state.configure({"freeze_ticks": 1, "restart_ticks": 1})
	# Use the menu's signal path, including its absence of class selection.
	game.hud._select_team(6)
	_check(game.match_started, "selecting Spectator starts the match without class/deploy input")
	if not game.match_started:
		# Keep probing the independently broken halftime path after recording
		# the entry failure. This fallback must never make the test pass.
		game.start_match()
	var original_sides := {}
	for bot in game._all_bots():
		original_sides[bot.name] = bot.team
	_check_observer(game, "entry")
	var watchable: Array = game._living_spectate_teammates()
	_check(watchable.size() == game._all_bots().size(), "observer can watch both teams")
	var watched_sides := {}
	for index in watchable.size():
		if is_instance_valid(game.spectator_camera.target):
			watched_sides[game.spectator_camera.target.team] = true
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		game.spectator_camera._unhandled_input(click)
	_check(watched_sides.has("T") and watched_sides.has("CT"), "mouse cycling reaches both sides")
	await _capture(game, "entry")
	for round_index in 16:
		game._physics_process(0.01)
		_check(game.phase == "live", "round becomes live")
		_check_observer(game, "live %d" % (round_index + 1))
		var attacker: Combatant = game.allied_bots[0]
		for bot in game.targets:
			bot.receive_damage(10000.0, bot.global_position, false, attacker)
		_check(game.phase == "post", "bot elimination ends observer round")
		game._physics_process(0.01)
		await process_frame
		_check_observer(game, "round boundary %d" % (round_index + 1))
		for bot in game._all_bots():
			_check(bot.team == str(game.round_state.players[bot.name].team), "actor side matches authoritative roster")
		if round_index == 14:
			for bot in game._all_bots():
				_check(bot.team != original_sides[bot.name], "halftime swaps every bot while local player observes")
				var spawns: Array = game.counter_terrorist_team_spawns if bot.team == "CT" else game.terrorist_team_spawns
				_check(spawns.has(bot._anchor) and Vector2(bot.global_position.x, bot.global_position.z).distance_to(
					Vector2(bot._anchor.x, bot._anchor.z)) < 0.001,
					"halftime respawns bots on their new side (with normal floor drop)")
			await _capture(game, "halftime")
	_check(game._match_concluded and game.phase == "intermission" and game.round_state.rounds_played == 16,
		"observed match reaches the actual win limit")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	game._unhandled_input(enter)
	_check_observer(game, "rematch")
	_check(game.round_number == 1 and game.ct_score == 0 and game.terrorist_score == 0, "observer rematch resets scores")
	await _capture(game, "rematch")
	# Joining from observer mode returns input, rendering, and collision to
	# the existing participant path; it must not retain chase-camera ownership.
	game.hud.set_deploy_visible(true)
	game.hud._select_team(2)
	game.hud._select_class(3)
	_check(game.player.alive and game.player.visible and game.player.collision_layer == 4,
		"joining restores the participant body")
	_check(not game.spectator_camera.is_engaged() and root.get_camera_3d() == game.player.camera,
		"joining returns the first-person camera")
	_check(game.round_state.players.player.team == "CT" and game.round_state.players.player.alive,
		"joining restores authoritative participation")
	for tick in 600:
		game._physics_process(0.01)
	_check(game.phase == "live" and game.player.controls_enabled, "joined player becomes playable")
	# Source rules reject alive spectator entry outside freeze. Death permits
	# it, but selection must not count an additional death.
	var deaths: int = game.round_state.players.player.deaths
	game.hud._select_team(6)
	_check(game.player.team == "CT" and game.player.alive and not game.spectator_camera.is_engaged(),
		"alive live player cannot enter observation")
	game.player.receive_damage(100000.0, game.player.global_position, false, game.targets[0])
	game.hud._select_team(6)
	_check_observer(game, "leave dead team")
	_check(game.round_state.players.player.deaths == deaths + 1, "observer selection does not duplicate the combat death")
	_check(game.round_state.bomb_owner != "player", "observer cannot retain C4 ownership")
	# Freeze-time entry follows the normal actor death/drop path as well.
	game._restart_match()
	game.hud.set_deploy_visible(true)
	game.hud._select_team(1)
	game.hud._select_class(1)
	game.player.grant_item("ak47")
	game.player.switch_weapon("ak47")
	deaths = game.round_state.players.player.deaths
	game.hud._select_team(6)
	_check_observer(game, "leave freeze team")
	_check(game.round_state.players.player.deaths == deaths + 1
		and game.round_state.players.player.kills == 0 and not game.dropped_weapons.is_empty(),
		"freeze observation counts one death, preserves frags, and drops the equipped weapon")
	for bot in game._all_bots():
		bot.receive_damage(100000.0, bot.global_position)
	_check_observer(game, "no living target")
	_check(game.spectator_camera.target == null and game.spectator_camera.is_free_fly()
		and game.hud.spectate_label.text == "Spectating: Free Look",
		"no-target observation enters free fly without restoring the participant HUD")
	await _capture(game, "no-target")
	var closing_playbacks: Array[WeakRef] = []
	var closing_audio_trace = game.audio_playback._trace
	if DisplayServer.get_name() != "headless":
		for state: Dictionary in game.audio_playback._active.values():
			var audio_player: Node = state.player
			if audio_player.has_stream_playback():
				closing_playbacks.append(weakref(audio_player.get_stream_playback()))
		_check(not closing_playbacks.is_empty(), "rendered teardown exercises live death-sound playbacks")
	print("OBSERVER_MATCH ", JSON.stringify({"map": game.map_name, "failures": failures,
		"rounds_completed": 16, "full_match_soak": false, "audio_muted": true}))
	game.queue_free()
	await process_frame
	MdlCharacterModel.release_cached_resources()
	MdlViewModel.release_cached_resources()
	CS16CombatEffects.release_cached_resources()
	var drain_started := Time.get_ticks_usec()
	# SceneTreeTimer consumes frame delta, including earlier work in a long
	# teardown frame; its nominal 200 ms wait could finish in ~6 ms. The audio
	# mixer releases stopped voices asynchronously. Wait for actual ownership
	# release with a monotonic deadline, never by inflating the apparent delay.
	await process_frame
	while Time.get_ticks_usec() - drain_started < 2_000_000:
		var retained := false
		for playback: WeakRef in closing_playbacks:
			retained = retained or playback.get_ref() != null
		if not retained:
			break
		await process_frame
	var closing_stops: Array = []
	for event: Dictionary in closing_audio_trace.snapshot():
		if str(event.get("reason", "")) == "adapter_exit_tree":
			closing_stops.append(event)
	print("AUDIO_SCENE_TEARDOWN ", JSON.stringify({"playbacks": closing_playbacks.size(), "stops": closing_stops,
		"drain_elapsed_ms": float(Time.get_ticks_usec() - drain_started) / 1000.0,
		"mix_rate": AudioServer.get_mix_rate()}))
	for playback: WeakRef in closing_playbacks:
		_check(playback.get_ref() == null, "scene destruction releases death-sound playback ownership")
	if failures.is_empty():
		print("GAME_OBSERVER_MATCH_PASS")
	quit(0 if failures.is_empty() else 1)


func _check_observer(game: Node, boundary: String) -> void:
	game.spectator_camera._physics_process(0.01)
	_check(game.player.team == Combatant.TEAM_UNASSIGNED and not game.player.alive,
		boundary + ": observer is not a living combatant")
	_check(not game.player.controls_enabled and not game.player.look_enabled and not game.player.visible
		and game.player.collision_layer == 0 and game.player.velocity == Vector3.ZERO,
		boundary + ": observer cannot move, fire, render a weapon, or block actors")
	_check(not game.round_state.players.player.alive and not game.round_state.players.player.has_c4,
		boundary + ": authoritative observer remains non-participating")
	_check(game.money == 0 and not game.player.viewmodel.is_visible_in_tree(),
		boundary + ": observer has no account or visible local viewmodel")
	_check(game.spectator_camera.active and root.get_camera_3d() == game.spectator_camera.camera,
		boundary + ": chase camera owns the view")
	_check(game.bomb_knowledge.state_for("player").team == Combatant.TEAM_UNASSIGNED,
		boundary + ": observer is not registered as a Terrorist")
	for control_name in ["ClassicVitals", "ClassicAmmo", "ClassicMoney", "ClassicRadar", "ClassicRadarContacts",
		"ClassicHostageStatus", "Crosshair", "ClassicBuyZone"]:
		_check(not game.hud.get_node("HUDRoot/" + control_name).is_visible_in_tree(),
			boundary + ": hides inactive local HUD " + control_name)
	_check(game.hud.spectate_label.is_visible_in_tree(), boundary + ": spectator identity remains visible")
	_check(game.hud.get_node("HUDRoot").get_global_rect().encloses(game.hud.spectate_label.get_global_rect()),
		boundary + ": spectator identity is actually inside the viewport")


func _capture(game: Node, boundary: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.spectator_camera._physics_process(0.1)
	var before := Engine.get_frames_drawn()
	for frame in 4:
		await process_frame
	_check(Engine.get_frames_drawn() - before >= 3, "capture actually rendered")
	var path := "/tmp/protocol47-observer-%s-%s-%s.png" % [game.map_name, RenderingServer.get_current_rendering_method(), boundary]
	_check(root.get_texture().get_image().save_png(path) == OK, "save observer capture")
