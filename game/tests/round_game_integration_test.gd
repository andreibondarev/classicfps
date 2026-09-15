extends SceneTree

const CS16CombatEffects := preload("res://scripts/cs16_combat_effects.gd")
const MdlCharacterModel := preload("res://scripts/mdl_character_model.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ROUND GAME INTEGRATION TEST: " + message)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game = packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.set_physics_process(false)

	_check(game.using_imported_map, "integration fixture loads imported de_dust2")
	_check(
		not game.audio_playback.playback_enabled,
		"headless match simulations route audio without device playback",
	)
	_check(
		game.bomb_regions.size() == 2,
		"both func_bomb_target BSP submodels become plant regions",
	)
	_check(
		game.buy_regions.size() == 2,
		"both func_buyzone BSP submodels become buy regions",
	)
	_check(
		game.get_node_or_null("Bombsite_A") == null
		and game.get_node_or_null("Bombsite_B") == null,
		"imported BSP keeps its classic site markings without debug cylinders",
	)
	var buy_teams: Array[int] = []
	for region: Dictionary in game.buy_regions:
		buy_teams.append(int(region.team))
		var bounds: AABB = region.bounds
		_check(
			bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.size.z > 0.0,
			"buy brush %d has non-empty imported bounds" % int(region.model_index),
		)
		_check(
			str(region.touch_mode) == "player_hull",
			"buy brush declares source trigger-hull touch semantics",
		)
	buy_teams.sort()
	_check(buy_teams == [1, 2], "BSP buy zones preserve T/CT team properties")
	for region: Dictionary in game.bomb_regions:
		var bounds: AABB = region.bounds
		_check(
			bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.size.z > 0.0,
			"bomb brush %d has non-empty imported bounds" % int(region.model_index),
		)
		_check(
			bool(region.horizontal_hull_containment),
			"bomb target declares ReGameDLL horizontal hull containment",
		)
	_assert_exact_dust2_objective_bounds(game)
	_assert_trigger_geometry(game)
	_assert_c4_use_geometry(game)
	_assert_team_class_authority(game)

	game.round_state.configure({
		"freeze_ticks": 1,
		"round_ticks": 1000,
		"restart_ticks": 2,
	})
	game.start_match()
	_assert_c4_inventory_boundary(game)
	_check(
		game.BUY_PRICES.has("elite") and not game.BUY_PRICES.has("elites"),
		"buy catalog uses the canonical dual-Elites registry ID",
	)
	_check(bool(game._buy_eligibility().allowed), "T spawn lies inside its BSP buy zone")
	var money_before_unsupported: int = int(game.money)
	game._on_buy_item_requested("knife")
	_check(
		game.money == money_before_unsupported,
		"non-purchasable roster items are rejected before charging money",
	)
	game._on_buy_item_requested("elites")
	_check(
		game.money == money_before_unsupported - 800,
		"classic VGUI Elites alias grants the canonical T-only weapon",
	)
	_check(
		game.player.owns_weapon("elite")
		and not game.player.owns_weapon("glock18")
		and game.player.active_weapon == "elite",
		"Elites purchase replaces and equips the starting pistol slot",
	)
	_advance_game_round(game, 1)
	_check(game.phase == "live", "game phase follows authoritative freeze deadline")
	game.phase = "bomb"
	game.player.controls_enabled = true
	var defuse_start_events: Array[Dictionary] = [
		{"type": "defuse_start", "player_id": "player"},
	]
	game._consume_round_events(defuse_start_events)
	_check(
		game.player.controls_enabled
		and game.player.objective_movement_locked,
		"human defuse start locks translation while preserving source view/+use controls",
	)
	var locked_position: Vector3 = game.player.global_position
	var locked_yaw: float = game.player.rotation.y
	var locked_pitch: float = game.player.camera.rotation.x
	var look_event := InputEventMouseMotion.new()
	look_event.relative = Vector2(24.0, -12.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.player._input(look_event)
	game.player._physics_process(0.01)
	var locked_distance: float = game.player.global_position.distance_to(locked_position)
	var yaw_changed: bool = not is_equal_approx(game.player.rotation.y, locked_yaw)
	var pitch_changed: bool = not is_equal_approx(
		game.player.camera.rotation.x,
		locked_pitch,
	)
	_check(
		locked_distance <= 0.01
		and Vector2(game.player.velocity.x, game.player.velocity.z).length() <= 0.01
		and is_equal_approx(game.player._movement_speed(false, false), 0.01)
		and yaw_changed
		and pitch_changed,
		(
			"active defuse accepts mouse yaw/pitch under the source 1-HU/s cap "
			+ "(distance=%.6f yaw=%s pitch=%s)"
			% [locked_distance, yaw_changed, pitch_changed]
		),
	)
	var defuse_abort_events: Array[Dictionary] = [
		{"type": "defuse_abort", "player_id": "player"},
	]
	game._consume_round_events(defuse_abort_events)
	_check(
		game.player.controls_enabled
		and not game.player.objective_movement_locked,
		"human defuse abort immediately restores live movement",
	)
	game.phase = "live"

	game.hud.reset_money_presentation()
	game._update_round_hud(true)
	var kill_balance: int = game.money
	game.round_state.grant_kill("player")
	game._consume_new_round_trace()
	game._sync_round_public_state()
	game._update_round_hud()
	_check(game.hud.money_delta_amount == game.money - kill_balance
		and game.hud.money_delta_amount == 300,
		"real kill reward updates the HUD without waiting for the next clock second")
	game.hud._money_delta_tween.custom_step(3.0)
	var pre_round_balance: int = game.money
	# Reproduce the former stale-dead HUD bug, then cross a real round restart.
	for target in game.targets:
		target.alive = false
		game.round_state.set_player_alive(
			target.name,
			false,
			target.global_position,
			"player",
		)
	game._consume_new_round_trace()
	game._sync_round_public_state()
	game._update_round_hud(true)
	_check(game.phase == "post", "CT elimination enters post-round phase")
	_check(game.money > pre_round_balance
		and game.hud.money_delta_amount == game.money - pre_round_balance,
		"round payout displays the actual credited money")
	_check(game.player.can_simulate_movement() and not game.player.controls_enabled,
		"local survivor keeps movement during post countdown without reopening attacks")
	_check(
		not _scoreboard_has_dead_icon(game.hud),
		"scoreboard never shows skull glyphs (CS 1.6 rows carry no dead icons)",
	)
	_check(
		_scoreboard_max_deaths(game.hud) >= 1,
		"post-round scoreboard increments eliminated combatants' deaths column",
	)
	_check(
		_scoreboard_has_dead_text(game.hud),
		"post-round scoreboard marks eliminated players in the status column",
	)

	# Also cover a human who was dead when the preceding freeze event arrived.
	game.player.alive = false
	game.player.look_enabled = false
	_advance_game_round(game, 2)
	_check(
		game.phase == "freeze" and game.round_number == 2,
		"authoritative post deadline begins round two",
	)
	for target in game.targets:
		_check(target.alive, "%s is alive after round reset" % target.name)
	for ally in game.allied_bots:
		_check(ally.alive, "%s is alive after round reset" % ally.name)
	_check(game.player.alive, "player is alive after round reset")
	_assert_freeze_controls(game)
	_check(
		not _scoreboard_has_dead_icon(game.hud),
		"round-start HUD rebuild removes every stale dead-player icon",
	)
	_check(
		game.hud.health_label.text == "100",
		"round-start HUD health state is reset immediately",
	)

	_advance_game_round(game, 1)
	_check(game.player.controls_enabled, "live deadline restores human controls after reset")
	for bot: TargetActor in game._all_bots():
		_check(bot.active, "%s resumes decisions at the live deadline" % bot.name)
	_assert_match_structure(game)

	if failures.is_empty():
		print("GAME_ROUND_INTEGRATION_TEST_PASS")
		await _teardown(game)
		quit(0)
	else:
		print("GAME_ROUND_INTEGRATION_TEST_FAIL (%d)" % failures.size())
		await _teardown(game)
		quit(1)


func _assert_freeze_controls(game: Node) -> void:
	_check(not game.player.controls_enabled, "round reset preserves the human freeze lock")
	_check(not game.player.can_simulate_movement(), "post-round movement does not leak into the next freeze")
	_check(game.player.look_enabled, "respawned human can look around during freeze")
	for bot: TargetActor in game._all_bots():
		_check(not bot.active, "%s stays inactive after round reset" % bot.name)
		var spawn := bot.global_position
		var clip := bot.weapon_clip
		# Exercise the actual actor callback, not just its public phase label.
		# The game's round clock is held by this fixture until explicitly advanced.
		for tick in range(3):
			bot._physics_process(0.01)
		_check(bot.global_position == spawn and bot.velocity == Vector3.ZERO,
			"%s cannot move during freeze" % bot.name)
		_check(bot.last_command.is_empty() and bot.weapon_clip == clip
			and bot.combat_controller._objective_tick == 0,
			"%s cannot advance AI or fire during freeze" % bot.name)


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


func _advance_game_round(game: Node, ticks: int) -> void:
	for ignored in range(ticks):
		var events: Array[Dictionary] = game.round_state.advance_tick()
		game._consume_round_events(events)
		game._consumed_round_events = game.round_state.trace.size()
		game._sync_round_public_state()
		game._update_round_hud(true)


func _assert_exact_dust2_objective_bounds(game: Node) -> void:
	var expected := {
		16: AABB(Vector3(-17.279999, 0.0, -28.8), Vector3(3.839999, 0.96, 3.84)),
		42: AABB(Vector3(10.24, 0.96, -26.24), Vector3(2.559999, 0.96, 3.200001)),
		29: AABB(Vector3(-1.92, -1.28, -25.599998), Vector3(7.84, 0.96, 5.759998)),
		30: AABB(Vector3(-10.88, 0.0, 5.7599998), Vector3(7.04, 2.8799999, 3.8400002)),
	}
	for region: Dictionary in game.bomb_regions + game.buy_regions:
		var model_index := int(region.model_index)
		var bounds: AABB = region.bounds
		var oracle: AABB = expected[model_index]
		_check(
			bounds.position.distance_to(oracle.position) < 0.00001
			and bounds.end.distance_to(oracle.end) < 0.00001,
			"Dust2 BSP model *%d keeps exact exported brush bounds" % model_index,
		)


func _assert_trigger_geometry(game: Node) -> void:
	var original_buy: Array[Dictionary] = game.buy_regions.duplicate(true)
	game.buy_regions.clear()
	game.buy_regions.append({
		"bounds": AABB(Vector3.ZERO, Vector3(2.0, 1.0, 2.0)),
		"team": 1,
	})
	var stand_hull := Vector3(0.32, 0.72, 0.32)
	var duck_hull := Vector3(0.32, 0.50, 0.32)
	_check(
		game._is_in_team_buy_zone(
			Vector3(-0.10, 0.0, 1.0),
			"T",
			stand_hull,
		),
		"buy trigger accepts hull touch when the player's center is outside",
	)
	_check(
		not game._is_in_team_buy_zone(
			Vector3(-0.17, 0.0, 1.0),
			"T",
			stand_hull,
		),
		"buy trigger rejects a hull separated by one GoldSrc unit",
	)
	_check(
		not game._is_in_team_buy_zone(
			Vector3(1.0, 0.0, 1.0),
			"CT",
			stand_hull,
		),
		"buy trigger preserves its team restriction after hull contact",
	)
	game.buy_regions[0].bounds = AABB(
		Vector3(0.0, 0.60, 0.0),
		Vector3(2.0, 0.20, 2.0),
	)
	_check(
		game._is_in_team_buy_zone(Vector3(1.0, 0.0, 1.0), "T", stand_hull)
		and not game._is_in_team_buy_zone(
			Vector3(1.0, 0.0, 1.0),
			"T",
			duck_hull,
		),
		"buy trigger distinguishes standing and ducking hull contact",
	)
	game.buy_regions.assign(original_buy)

	var original_bomb: Array[Dictionary] = game.bomb_regions.duplicate(true)
	game.bomb_regions.clear()
	game.bomb_regions.append({
		"bounds": AABB(Vector3.ZERO, Vector3(2.0, 1.0, 2.0)),
		"target": "fixture",
	})
	_check(
		game._bomb_region_at(Vector3(1.0, 0.80, 1.0), stand_hull).target
		== "fixture",
		"bomb target allows vertical hull overhang after a valid trigger touch",
	)
	_check(
		game._bomb_region_at(Vector3(0.10, 0.0, 1.0), stand_hull).is_empty(),
		"bomb target rejects center-inside placement when horizontal hull protrudes",
	)
	_check(
		not game._bomb_region_at(
			Vector3(0.16, 0.0, 1.0),
			stand_hull,
		).is_empty(),
		"bomb target accepts exact horizontal hull containment at its boundary",
	)
	game.bomb_regions[0].bounds = AABB(
		Vector3(0.0, 0.60, 0.0),
		Vector3(2.0, 0.20, 2.0),
	)
	_check(
		not game._bomb_region_at(
			Vector3(1.0, 0.0, 1.0),
			stand_hull,
		).is_empty()
		and game._bomb_region_at(
			Vector3(1.0, 0.0, 1.0),
			duck_hull,
		).is_empty(),
		"bomb target requires a real trigger touch for each active hull height",
	)
	game.bomb_regions.assign(original_bomb)


func _assert_c4_use_geometry(game: Node) -> void:
	var user := Vector3.ZERO
	var eye := Vector3(0.0, 0.53, 0.0)
	var c4_in_range := Vector3(0.63, 0.0, 0.0)
	var forward := (c4_in_range - eye).normalized()
	var valid: Dictionary = game._c4_use_geometry(
		user,
		eye,
		forward,
		c4_in_range,
	)
	_check(
		bool(valid.in_range) and bool(valid.facing),
		"forward +use selects a C4 inside the exact 64-HU search radius",
	)
	var too_far: Dictionary = game._c4_use_geometry(
		user,
		eye,
		(Vector3(0.65, 0.0, 0.0) - eye).normalized(),
		Vector3(0.65, 0.0, 0.0),
	)
	_check(
		not bool(too_far.in_range),
		"C4 at 65 HU is outside PlayerUse's source search sphere",
	)
	var behind: Dictionary = game._c4_use_geometry(
		user,
		eye,
		-forward,
		c4_in_range,
	)
	_check(
		not bool(behind.facing) and float(behind.dot) < 0.7,
		"C4 behind the view fails VIEW_FIELD_NARROW",
	)


func _assert_team_class_authority(game: Node) -> void:
	game.hud.team_selected.emit(2)
	game.hud.class_selected.emit(4)
	_check(
		game.player.team == "CT"
		and str(game.round_state.players.player.team) == "CT",
		"typed CT selection updates Player and authoritative round registration",
	)
	_check(
		game.player.global_position.distance_to(
			game.counter_terrorist_team_spawns[0]
		) < 0.001
		and game.player.active_weapon == "usp",
		"CT selection respawns at CT start with the CT default pistol",
	)
	_check(
		game.selected_class_id == 4
		and game.selected_player_skin == "gign"
		and str(game.player.get_meta("cs16_player_skin")) == "gign",
		"typed class selection reaches the authoritative CS player-skin choice",
	)
	for ally in game.allied_bots:
		_check(ally.team == "CT", "CT selection assigns allied bots to CT")
	for ally_index in range(game.allied_bots.size()):
		_check(
			game.allied_bots[ally_index].global_position.distance_to(
				game.counter_terrorist_team_spawns[ally_index + 1]
			) < 0.001,
			"CT ally %d respawns at the correct CT start" % ally_index,
		)
	for target_index in range(game.targets.size()):
		_check(game.targets[target_index].team == "T", "CT selection assigns enemy bots to T")
		_check(
			game.targets[target_index].global_position.distance_to(
				game.terrorist_team_spawns[target_index]
			) < 0.001,
			"T enemy %d respawns at the correct T start" % target_index,
		)

	# Restore the default scenario used by the remainder of this fixture.
	game.hud.team_selected.emit(1)
	game.hud.class_selected.emit(1)
	_check(
		game.player.team == "T"
		and str(game.round_state.players.player.team) == "T"
		and game.player.active_weapon == "glock18",
		"typed T selection restores T registration, spawn flow, and pistol",
	)


func _assert_match_structure(game: Node) -> void:
	_check(
		int(game.round_state.config.max_rounds) == 30
		and int(game.round_state.config.win_limit) == 16
		and bool(game.round_state.config.halftime),
		"the live match runs MR15: 30 rounds, 16-win limit, half-time swap",
	)
	var team_before := str(game.player.team)
	var spawn_before: Vector3 = game.player_spawn
	# CS16RoundState swaps its own roster before emitting halftime; reproduce that
	# ordering so the consumer sees the same state the kernel would hand it.
	for player_id: String in game.round_state.players:
		var row: Dictionary = game.round_state.players[player_id]
		if str(row.team) in ["T", "CT"]:
			row.team = "CT" if str(row.team) == "T" else "T"
			game.round_state.players[player_id] = row
	var halftime_events: Array[Dictionary] = [{
		"tick": 0,
		"type": "halftime",
		"round": 15,
		"ct_score": 8,
		"terrorist_score": 7,
		"start_money": 800,
	}]
	game._consume_round_events(halftime_events)
	_check(
		game.player.team != team_before
		and game.player.team == str(game.round_state.players.player.team),
		"half-time switches the live player onto the kernel's new side",
	)
	_check(
		game.player_spawn != spawn_before,
		"half-time re-assigns the spawn side",
	)
	var bots_in_sync := true
	for bot in game._all_bots():
		if str(game.round_state.players[bot.name].team) != bot.team:
			bots_in_sync = false
		_check(bot.character_model.get_child_count() == 2,
			"%s halftime replaces, rather than stacks, character meshes" % bot.name)
		_check(bot.character_model.skin_name == bot.player_skin,
			"%s halftime presentation uses its new team skin" % bot.name)
	_check(bots_in_sync, "half-time keeps every bot actor on its kernel team")

	var match_end_events: Array[Dictionary] = [{
		"tick": 0,
		"type": "match_end",
		"ct_score": 16,
		"terrorist_score": 7,
	}]
	game._consume_round_events(match_end_events)
	_check(
		not game.match_started
		and not game.player.controls_enabled
		and not game.player.look_enabled,
		"match end stops the match and releases player control",
	)


func _assert_c4_inventory_boundary(game: Node) -> void:
	for player_id: String in game.round_state.players:
		var state_player: Dictionary = game.round_state.players[player_id]
		state_player.has_c4 = player_id == "player"
		game.round_state.players[player_id] = state_player
	game.round_state.bomb_owner = "player"
	game.round_state.bomb_state = "carried"
	game._sync_round_public_state()
	_check(
		game.player.owns_weapon("c4")
		and int(game.player.ammunition.c4.clip) == 1,
		"authoritative C4 ownership reaches Player inventory",
	)
	game.round_state.players.player.has_c4 = false
	game.round_state.bomb_state = "planted"
	game._sync_round_public_state()
	_check(
		not game.player.owns_weapon("c4")
		and not game.player.ammunition.has("c4"),
		"planted/dropped C4 is removed from Player inventory",
	)


func _scoreboard_has_dead_text(hud: Node) -> bool:
	for row in hud.scoreboard_rows.get_children():
		if row.get_child_count() < 4:
			continue
		var status_label := row.get_node_or_null("Status") as Label
		if status_label != null and status_label.text == "Dead":
			return true
	return false


func _scoreboard_max_deaths(hud: Node) -> int:
	var max_deaths := 0
	for row in hud.scoreboard_rows.get_children():
		var deaths_label := row.get_node_or_null("Deaths") as Label
		if deaths_label != null and deaths_label.text.is_valid_int():
			max_deaths = maxi(max_deaths, int(deaths_label.text))
	return max_deaths


func _scoreboard_has_dead_icon(hud: Node) -> bool:
	for row in hud.scoreboard_rows.get_children():
		if row.find_child("Status_smallskull", true, false) != null:
			return true
	return false
