extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("DUST2 BOT OBJECTIVE TEST: " + message)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game = packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.start_match()
	game._begin_live()
	for ignored in 40:
		await physics_frame

	_check(
		game.map_name == "de_dust2"
		and game.using_imported_map
		and game.bomb_sites.size() == 2,
		"contract runs on the imported two-site Dust2 level",
	)
	_assert_pistol_round_buy(game)
	_assert_site_execute_roles(game)

	current_scene = null
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_DUST2_BOT_OBJECTIVE_TEST_PASS")
		quit(0)
	else:
		print("GAME_DUST2_BOT_OBJECTIVE_TEST_FAIL: " + ", ".join(failures))
		quit(1)


func _assert_pistol_round_buy(game: Node) -> void:
	for bot: TargetActor in game._all_bots():
		var expected_weapon := (
			"usp"
			if bot.team == Combatant.TEAM_COUNTER_TERRORIST
			else "glock18"
		)
		var state: Dictionary = game.round_state.players[bot.name]
		var tactics = (bot.combat_controller as BotCombatController).tactics
		_check(
			bot.active_weapon_name == expected_weapon
			and str(tactics.weapon_name) == expected_weapon,
			"%s uses its team pistol in gameplay, tactics, and the player model"
			% bot.name,
		)
		_check(
			bot.armor == 100 and int(state.money) == 150,
			"%s spends the $800 pistol-round budget on exact $650 kevlar"
			% bot.name,
		)


func _assert_site_execute_roles(game: Node) -> void:
	var carrier: Combatant = game._actor_for_round_id(str(game.round_state.bomb_owner))
	_check(
		carrier is TargetActor,
		"first deterministic Dust2 C4 assignment is owned by a T bot",
	)
	if not carrier is TargetActor:
		return
	var carrier_bot := carrier as TargetActor

	var first_site: Vector3 = game._assigned_bomb_site(carrier_bot)
	var carrier_context: Dictionary = game.bot_objective_context(carrier_bot)
	_check(
		first_site == game.bomb_sites[0]
		and carrier_context.get("site_candidates", []).size() == 1
		and carrier_context.get("site_candidates", [Vector3.INF])[0] == first_site,
		"round-one carrier owns one stable authored site plan",
	)

	var support_count := 0
	var hunt_count := 0
	for bot: TargetActor in game.allied_bots:
		if bot == carrier_bot:
			continue
		var context: Dictionary = game.bot_objective_context(bot)
		if str(context.get("action", "")) == "support_site":
			support_count += 1
			_check(
				context.look_target == first_site,
				"%s supports the carrier's selected site" % bot.name,
			)
		elif context.is_empty():
			hunt_count += 1
	_check(
		support_count >= 1 and hunt_count >= 1,
		"T roles include both spaced execute support and independent hunters",
	)

	var ct_zero: Dictionary = game.bot_objective_context(game.targets[0])
	var ct_two: Dictionary = game.bot_objective_context(game.targets[2])
	var ct_one: Dictionary = game.bot_objective_context(game.targets[1])
	_check(
		str(ct_zero.get("action", "")) == "guard"
		and str(ct_two.get("action", "")) == "guard"
		and ct_zero.look_target != ct_two.look_target,
		"static CT anchors split across both Dust2 bombsites",
	)
	_check(
		ct_one.is_empty(),
		"alternating CT remains free to patrol and rotate",
	)

	game.round_state.round_number = 2
	game._bot_site_assignments.clear()
	var second_site: Vector3 = game._assigned_bomb_site(carrier_bot)
	_check(
		second_site == game.bomb_sites[1] and second_site != first_site,
		"the next round deterministically alternates to the other Dust2 site",
	)
