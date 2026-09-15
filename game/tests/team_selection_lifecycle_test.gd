extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("TEAM SELECTION: " + message)

func _key(game: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)

func _bots(game: Node) -> Array:
	var snapshot := []
	for bot in game._all_bots():
		snapshot.append([str(bot.name), bot.team, bot.global_position, bot.alive,
			bot.health, bot.armor, bot.active, bot.active_weapon_name, bot.weapon_clip, bot.weapon_reserve])
	return snapshot

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
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
	game.hud.team_menu.get_node("TeamCancel").pressed.emit()
	_check(game.hud.deploy_overlay.visible and not game.match_started, "initial lobby cancel cannot bypass deployment")
	_check(game._pause_menu_open() and paused, "initial lobby Cancel opens the game menu without starting play")
	_key(game, KEY_ESCAPE)
	_check(not game._pause_menu_open() and not paused and game.hud.current_input_contract().state == "team",
		"Resume returns initial lobby keyboard ownership to team selection")
	_key(game, KEY_1)
	_key(game, KEY_1)
	_check(game.match_started and game.phase == "freeze", "initial keyboard team/class path starts the match")
	game._physics_process(0.01)
	for bot in game.targets:
		bot.receive_damage(10000.0, bot.global_position, false, game.allied_bots[0])
	game._physics_process(0.01)
	game._physics_process(0.01)
	game.targets[0].receive_damage(10000.0, game.targets[0].global_position, false, game.allied_bots[0])
	var before_bots := _bots(game)
	var before_tick: int = game.round_state.tick
	var before_trace: Array = game.round_state.trace.duplicate(true)
	_key(game, KEY_M)
	_check(game.hud.deploy_overlay.visible and game.hud.current_input_contract().state == "team",
		"M opens the actual team menu without pausing the match")
	var human = game.player.combat_controller
	_check(human.menu_input_blocked and not paused, "menu owns local input, not the world clock")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	human.ingest_input(click)
	_check(not human.gather_command(0.01).fire, "team-menu click cannot fire a weapon")
	var before_guns: int = game.dropped_weapons.size()
	var death_gun: String = game.player.death_drop_weapon()
	_key(game, KEY_1)
	_key(game, KEY_3)
	_check(game.round_number == 2 and game.terrorist_score == 1 and game.ct_score == 0 and game.phase == "live",
		"same-team appearance selection preserves match score, round and phase")
	_check(game.round_state.tick == before_tick and game.round_state.trace.slice(0, before_trace.size()) == before_trace,
		"selection retains the authoritative clock and history")
	_check(_bots(game) == before_bots, "no unrelated bot identity, body, ammo or activity changes")
	_check(not game.player.alive and game.round_state.players.player.deaths == 1 and game.round_state.players.player.kills == -1,
		"accepted same-team choice counts one suicide and grants no extra life")
	_check(game.dropped_weapons.size() == before_guns + 1
		and game.dropped_weapons.back().weapon_name == death_gun and game.dropped_weapons.back().dropper_id == "player",
		"kernel-first selection death still drops physical gun exactly once")
	_check(game.selected_player_skin == "arctic" and not game.hud.deploy_overlay.visible and not human.menu_input_blocked,
		"class selection commits appearance and returns menu input ownership")
	_check(not human.gather_command(0.01).fire, "closing the menu does not replay its click")
	game.spectator_camera._physics_process(0.01)
	_check(game.spectator_camera.active and game.spectator_camera.target.team == "T", "waiting participant watches only its selected team")
	_key(game, KEY_M)
	_key(game, KEY_2)
	_check(game.player.team == "T" and game.hud.current_input_contract().state == "team", "second same-round dead switch is rejected without opening wrong class menu")
	_key(game, KEY_0)
	_check(not game.hud.deploy_overlay.visible and not human.menu_input_blocked, "0 cancels the running team menu")
	_key(game, KEY_M)
	game.hud.team_menu.get_node("TeamCancel").pressed.emit()
	_check(not game.hud.deploy_overlay.visible and not human.menu_input_blocked, "mouse Cancel closes the running team menu")
	_check(game.round_number == 2 and game.terrorist_score == 1 and game.round_state.tick == before_tick,
		"mouse Cancel leaves the running match unchanged")
	game._reset_round()
	_check(game.player.alive and game.player.visible and game.player.collision_layer == 4 and not game.spectator_camera.is_engaged(),
		"next round restores the waiting participant body, collision and camera")
	game._begin_live()
	before_bots = _bots(game)
	_key(game, KEY_M)
	_key(game, KEY_2)
	_key(game, KEY_4)
	_check(game.player.team == "CT" and game.selected_player_skin == "gign" and not game.player.alive,
		"permitted cross-team selection enrolls without immediate respawn")
	_check(_bots(game) == before_bots, "cross-team selection never switches or resets the other nine actors")
	game._reset_round()
	_check(game.player.alive and game.player.active_weapon == "usp", "next-round CT spawn uses its actual pistol")
	var positions := {}
	for actor in [game.player] + game._all_bots():
		var key := str(Vector2(actor.global_position.x, actor.global_position.z))
		_check(not positions.has(key), "changed roster receives distinct spawn slots")
		positions[key] = true

	# A genuine observer has no spawn in this new round, unlike a dead member.
	game.hud._select_team(6)
	game._reset_round()
	before_bots = _bots(game)
	game.hud.set_deploy_visible(true)
	game.hud._select_team(1)
	_check(not game.player.alive, "early observer enrollment waits for appearance")
	game.hud._select_class(2)
	_check(game.player.alive and game.player.team == "T" and game.player.active_weapon == "glock18"
		and game.money == 800 and game.player.collision_layer == 4, "early observer gets one normal starting spawn/account")
	_check(_bots(game) == before_bots, "early observer spawn leaves all bot state intact")
	game.hud._select_team(6)
	game._reset_round()
	game._begin_live()
	game.round_state.tick = game.round_state.round_started_tick + int(game.round_state.config.freeze_ticks) + 2001
	game.hud.set_deploy_visible(true)
	game.hud._select_team(2)
	game.hud._select_class(1)
	_check(not game.player.alive and game.player.team == "CT" and not game.round_state.players.player.alive,
		"late observer remains enrolled but dead until next round")
	game._reset_round()
	_check(game.player.alive and game.player.visible and game.player.collision_layer == 4, "late observer gets a real next-round body")

	game.hud._select_team(6)
	game._reset_round()
	game.hud.set_deploy_visible(true)
	game.hud._select_team(1)
	_key(game, KEY_ESCAPE)
	_key(game, KEY_0)
	_key(game, KEY_M)
	_check(game.hud.current_input_contract().state == "class" and not game.player.alive,
		"reopening an unfinished join resumes appearance without another team change")
	game._reset_round()
	_check(not game.player.alive and game.hud.current_input_contract().state == "class", "round boundary cannot spawn through an unfinished appearance menu")
	game.hud._select_class(1)
	_check(game.player.alive, "finishing appearance in the new round permits its first spawn")

	# Equal rosters/scores are not required to pick a deterministic random side:
	# force a score tie-break and check the HUD shows authority's CT classes.
	game._reset_round()
	game.round_state.ct_score = 0
	game.round_state.terrorist_score = 2
	game._sync_round_public_state()
	game.hud.set_deploy_visible(true)
	game.hud._select_team(5)
	_check(game.player.team == "CT" and game.hud._selected_team == 2, "auto assignment reaches authority and selects the losing tied-roster side")
	game.hud._select_class(3)
	_check(game.selected_player_skin == "sas", "auto-assigned class uses the accepted team family")
	game.hud._select_team(6)
	game._reset_round()
	game.hud.set_deploy_visible(true)
	game.hud._select_team(1)
	game.round_state.rounds_played = 15
	game.round_state.round_number = 15
	game.round_state._apply_halftime_if_needed()
	_check(game.round_state.halftime_done, "pending-join fixture reaches the real halftime transition")
	game._consume_new_round_trace()
	game._reset_round()
	_check(game.player.team == "CT" and game.hud._selected_team == 2 and not game.player.alive,
		"halftime updates a pending class family without bypassing appearance")
	game.hud._select_class(4)
	_check(game.player.alive and game.selected_player_skin == "gign", "pending halftime join spawns with the new side's selected appearance")
	await _capture(game)
	print("TEAM_SELECTION_LIFECYCLE ", JSON.stringify({"map": game.map_name, "audio_muted": true, "failures": failures}))
	var closing_playbacks: Array[WeakRef] = []
	for voice: Dictionary in game.audio_playback._active.values():
		if voice.player.has_stream_playback():
			closing_playbacks.append(weakref(voice.player.get_stream_playback()))
	game.queue_free()
	await process_frame
	MdlCharacterModel.release_cached_resources()
	MdlViewModel.release_cached_resources()
	CS16CombatEffects.release_cached_resources()
	# Wait for actual asynchronous playback release with a monotonic deadline.
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < 2000000:
		await process_frame
		if closing_playbacks.all(func(handle: WeakRef) -> bool: return handle.get_ref() == null):
			break
	_check(closing_playbacks.all(func(handle: WeakRef) -> bool: return handle.get_ref() == null), "scene teardown releases audio ownership")
	print("GAME_TEAM_SELECTION_LIFECYCLE_PASS" if failures.is_empty() else "GAME_TEAM_SELECTION_LIFECYCLE_FAIL")
	quit(0 if failures.is_empty() else 1)

func _capture(game: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.hud.set_deploy_visible(true)
	var draws := Engine.get_frames_drawn()
	for frame in 4:
		await process_frame
	_check(Engine.get_frames_drawn() - draws >= 3, "menu capture renders")
	_check(root.get_texture().get_image().save_png("/tmp/protocol47-team-menu-%s-%s.png" % [game.map_name, RenderingServer.get_current_rendering_method()]) == OK, "save live menu capture")
