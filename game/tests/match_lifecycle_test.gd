extends SceneTree

## Full MR15 state/actor lifecycle via real damage, kernel-generated events,
## and the normal Enter rematch handler. Actors do not navigate/fire here;
## shortened freeze/post delays make this a correctness test, not a match soak.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("MATCH LIFECYCLE: " + message)


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
	for bot in game._all_bots():
		bot.set_physics_process(false)
	var team := "T"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--team="):
			team = argument.trim_prefix("--team=")
	_check(team in ["T", "CT"], "valid local team")
	game._on_team_selected(2 if team == "CT" else 1)
	game._on_class_selected(4)
	game.round_state.configure({"freeze_ticks": 1, "restart_ticks": 1})
	game.start_match()
	var tied_match := OS.get_cmdline_user_args().has("--tie")
	var round_count := 30 if tied_match else 16
	var halftime_count := 0
	for round_index in round_count:
		_check(game.phase == "freeze", "round %d starts frozen" % (round_index + 1))
		game._physics_process(0.01)
		_check(game.phase == "live", "round %d becomes live through the kernel" % (round_index + 1))
		# Surviving expensive gear must not cross the halftime economy reset.
		if round_index in [0, 14]:
			game.player.grant_item("ak47")
			game.player.switch_weapon("ak47")
			game.player.armor = 100
			game.player.has_helmet = true
			game.player.grant_item("nvgs")
			if game.player.team == "CT":
				game.player.grant_item("defuser")
				game.round_state.set_defuser("player", true)
			for bot in game.allied_bots:
				bot.configure_weapon("ak47")
				bot.armor = 100
				bot.has_helmet = true
				if bot.team == "CT":
					game.round_state.set_defuser(bot.name, true)
		var local_wins := not tied_match or round_index % 2 == 0
		if round_index == round_count - 1:
			_check(game._handle_radio_key(KEY_Z) and game.player.radio_menu_open, "fixture opens radio before match end")
		if tied_match and round_index >= 28:
			local_wins = round_index == 29
		# The win-limit case ends with a dead local player; the 15-15 case
		# ends with a survivor. Both must get a fresh rematch loadout.
		if not local_wins or (not tied_match and round_index == 15):
			game.player.receive_damage(10000.0, game.player.global_position, false, game.targets[0])
		var losers: Array = game.targets if local_wins else game.allied_bots
		var attacker: Combatant = game.allied_bots[0] if local_wins else game.targets[0]
		for bot in losers:
			bot.receive_damage(10000.0, bot.global_position, false, attacker)
		_check(game.phase == "post", "eliminating the opposing team ends the round")
		game._physics_process(0.01)
		await process_frame
		if round_index == 0:
			_check(game.player.owns_weapon("ak47") and game.player.armor == 100 and game.player.has_helmet
				and bool(game.player.equipment.nvgs), "ordinary round preserves surviving loadout")
		if round_index == 14:
			halftime_count = game.round_state.trace.filter(func(event: Dictionary) -> bool: return event.type == "halftime").size()
			_check(halftime_count == 1 and game.player.team != team, "halftime swaps sides exactly once")
			_check(game.money == 800, "halftime resets local money")
			_check(not game.player.owns_weapon("ak47") and game.player.armor == 0 and not game.player.has_helmet,
				"halftime removes surviving local equipment")
			_check(not game.player.equipment.values().has(true) and not bool(game.round_state.players.player.has_defuser),
				"halftime clears equipment flags and the authoritative local kit")
			for bot in game.allied_bots:
				_check(bot.active_weapon_name in ["glock18", "usp"] and not bot.has_helmet,
					"halftime removes surviving bot rifle/helmet before the pistol-round buy")
				if bot.team == "T":
					_check(not bool(game.round_state.players[bot.name].has_defuser), "halftime cannot carry a CT kit onto T")
			await _capture_boundary(game, "halftime")
		for bot in game._all_bots():
			_check(bot.team == str(game.round_state.players[bot.name].team), "live bot side matches authoritative roster")
	_check(game.phase == "intermission" and game._match_concluded and not game.match_started, "match limit reaches intermission")
	_check(game.round_state.rounds_played == round_count, "match ends after the expected number of rounds")
	_check((game.ct_score == 15 and game.terrorist_score == 15) if tied_match else maxi(game.ct_score, game.terrorist_score) == 16,
		"MR15 reaches the tie or first-to-16 result")
	_check(game.player.alive == tied_match, "test covers the intended survivor/dead rematch path")
	_check(game._radio_menu_key == 0 and not game.player.radio_menu_open, "match end releases radio input ownership")
	await _capture_boundary(game, "match-end")
	if tied_match:
		game.player.grant_item("ak47")
		game.player.grant_item("nvgs")
		game.player.armor = 100
	var preserved_team: String = game.player.team
	var old_state: WeakRef = weakref(game.round_state)
	# A surviving bot also carries end-of-match gear into the rematch boundary.
	game.allied_bots[0].configure_weapon("ak47")
	game.allied_bots[0].has_helmet = true
	game.player.apply_flash_blind(10.0)
	game.hud.show_flash_blind(10.0)
	game.hud.show_radio_line("OLD MATCH RADIO")
	for bot in game._all_bots():
		bot.apply_flash_blind(10.0)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	game._unhandled_input(enter)
	await process_frame
	_check(old_state.get_ref() == null, "rematch releases the prior round state")
	_check(game.match_started and not game._match_concluded and game.phase == "freeze", "Enter starts a fresh match")
	_check(game.round_number == 1 and game.ct_score == 0 and game.terrorist_score == 0 and game.money == 800,
		"rematch resets scores, round, and local account")
	_check(game.player.alive and game.player.health == 100 and game.player.global_position.distance_to(game.player_spawn) < 0.001,
		"rematch respawns the dead local player at the current side's start")
	_check(game.player.team == preserved_team and game.selected_class_id == 4,
		"rematch preserves the post-halftime team and chosen class")
	_check(game.player.active_weapon == ("usp" if preserved_team == "CT" else "glock18") and game.player.armor == 0,
		"rematch gives the local player a fresh pistol-round loadout")
	_check(not game.player.equipment.values().has(true), "rematch clears local equipment flags")
	_check(not game.player.is_flash_blinded(), "rematch clears local blindness")
	_check(game._radio_menu_key == 0 and not game.player.radio_menu_open, "rematch cannot retain invisible radio input capture")
	_check(game.hud.banner_label.text.is_empty() and game.hud.status_label.text.is_empty()
		and game.hud.kill_feed_box.get_child_count() == 0 and game.hud._radio_line_label.text.is_empty(),
		"rematch clears old announcements, objective, kill feed, and radio text")
	_check(game.hud.damage_flash.color.a == 0.0 and game.hud.flash_blind_overlay.color.a == 0.0,
		"rematch clears damage and flash overlays")
	_check(not game.spectator_camera.is_engaged() and root.get_camera_3d() == game.player.camera,
		"rematch returns from death spectating to the player camera")
	_check(game.dropped_weapons.is_empty() and game.dropped_c4 == null and game.bomb == null,
		"rematch clears prior weapons and bomb presentation")
	for bot in game._all_bots():
		_check(not bot.is_flash_blinded(), "rematch clears bot blindness")
		_check(bot.alive and bot.health == 100 and not bot.active and bot.collision_layer == 2,
			"rematch respawns and freezes bot " + bot.name)
		_check(bot.active_weapon_name in ["glock18", "usp"] and not bot.has_helmet,
			"rematch discards bot gear before normal starting-budget purchases")
	await _capture_boundary(game, "rematch")
	# Exercise an already-running fade, not just a pending timer: resetting
	# generations alone would let this old tween hide the new announcement.
	game.hud.show_banner("OLD FADE", Color.WHITE, 0.01)
	await create_timer(0.06).timeout
	game.hud.reset_match_presentation()
	game.hud.show_banner("NEW ANNOUNCEMENT", Color.WHITE, 0.8)
	await create_timer(0.35).timeout
	_check(game.hud.banner_label.text == "NEW ANNOUNCEMENT" and game.hud.banner_label.modulate.a > 0.99,
		"old match's active fade cannot hide a new announcement")
	game.hud.reset_match_presentation()
	# The new match's already scheduled freeze is the normal six seconds.
	for tick in 600:
		game._physics_process(0.01)
	_check(game.phase == "live" and game.player.controls_enabled, "new match becomes playable after its real freeze")
	var report := {"map": game.map_name, "starting_team": team, "ending_team": preserved_team,
		"rounds_completed": round_count, "tied_match": tied_match, "halftime_events": halftime_count, "failures": failures,
		"audio_muted": true, "full_match_soak": false}
	print("MATCH_LIFECYCLE ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	MdlCharacterModel.release_cached_resources()
	MdlViewModel.release_cached_resources()
	CS16CombatEffects.release_cached_resources()
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("GAME_MATCH_LIFECYCLE_PASS")
	quit(0 if failures.is_empty() else 1)


func _capture_boundary(game: Node, boundary: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var before := Engine.get_frames_drawn()
	for frame in 4:
		await process_frame
	_check(Engine.get_frames_drawn() - before >= 3, "rendered lifecycle boundary must actually draw: " + boundary)
	var path := "/tmp/protocol47-lifecycle-%s-%s-%s.png" % [game.map_name, RenderingServer.get_current_rendering_method(), boundary]
	_check(root.get_texture().get_image().save_png(path) == OK, "save lifecycle capture: " + boundary)
