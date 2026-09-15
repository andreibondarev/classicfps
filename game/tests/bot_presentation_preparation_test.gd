extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BOT PRESENTATION PREPARATION TEST: " + message)


func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	game.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	var requests: Array[Dictionary] = game._bot_presentation_requests()
	var expected_paths := {}
	for request: Dictionary in requests:
		expected_paths[MdlCharacterModel.body_asset_path(request.skin, request.weapon)] = true
		expected_paths["res://generated/player_weapons/%s/model.json" % request.weapon] = true
	var bomb_map: bool = game.scenario == CS16ScenarioRules.SCENARIO_BOMB
	_check(requests.size() == (38 if bomb_map else 34), "5v5 purchase/starting/C4 matrix is finite and deduplicated")
	_check(requests.any(func(request: Dictionary) -> bool: return request.weapon == "c4") == bomb_map,
		"only bomb maps prepare bomb-carrier poses")
	_check(not requests.any(func(request: Dictionary) -> bool:
		return request.weapon == "awp" and request.skin not in ["urban", "terror"]),
		"only actual sniper-role skins prepare rifle-family animations")
	var initial_paths := MdlCharacterModel._template_cache.keys()
	var nodes_before := get_node_count()
	var accounts_before := JSON.stringify(game.round_state.players)
	var actor_snapshots := {}
	for bot: TargetActor in game._all_bots():
		actor_snapshots[bot.name] = [bot.character_model, bot.character_model.body_instance,
			bot.character_model.body_instance.mesh, bot.active_weapon_name, bot.weapon_clip,
			bot.global_position, bot.combat_controller._objective_tick]
	_check(await game._prepare_bot_presentation_assets(), "required body/attached assets prepare successfully")
	print("BOT_PRESENTATION_PREPARATION ", JSON.stringify(game.bot_asset_preparation))
	for request: Dictionary in requests:
		_check(MdlCharacterModel.character_assets_prepared(request.skin, request.weapon),
			"each planned presentation is resident")
	for path: String in MdlCharacterModel._template_cache:
		_check(initial_paths.has(path) or expected_paths.has(path), "preparation loads only the requested finite matrix")
	_check(get_node_count() == nodes_before, "preparation creates no actor/mesh nodes")
	_check(JSON.stringify(game.round_state.players) == accounts_before, "preparation does not purchase or change accounts")
	for bot: TargetActor in game._all_bots():
		_check(actor_snapshots[bot.name] == [bot.character_model, bot.character_model.body_instance,
			bot.character_model.body_instance.mesh, bot.active_weapon_name, bot.weapon_clip,
			bot.global_position, bot.combat_controller._objective_tick],
			"preparation preserves live presentation, inventory, position, and AI clock")
	var cache_count := MdlCharacterModel._template_cache.size()
	_check(await game._prepare_bot_presentation_assets(), "repeated preparation succeeds")
	_check(game.bot_asset_preparation.loading_slices == 0
		and game.bot_asset_preparation.new_templates == 0
		and MdlCharacterModel._template_cache.size() == cache_count,
		"repeated preparation performs no new loading")
	# Exercise the exact load path that a later round buy uses, after preparation.
	var model := MdlCharacterModel.new()
	game.add_child(model)
	_check(model.load_character("gsg9", "mp5"), "prepared MP5 presentation instantiates")
	_check(MdlCharacterModel._template_cache.size() == cache_count,
		"prepared round-buy model does not load additional templates")
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	MdlViewModel.release_cached_resources()
	MdlCharacterModel.release_cached_resources()
	CS16CombatEffects.release_cached_resources()
	_check(MdlCharacterModel._template_cache.is_empty(), "scene cache release retires prepared sources")
	print("GAME_BOT_PRESENTATION_PREPARATION_TEST_PASS" if failures.is_empty() else "GAME_BOT_PRESENTATION_PREPARATION_TEST_FAIL")
	quit(0 if failures.is_empty() else 1)
