extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SMOKE TEST: " + message)


func _uses_authentic_model(target: TargetActor) -> bool:
	return (
		target.character_model != null
		and target.character_model.model_loaded
		and not target._fallback_visual.visible
	)


func _has_body_and_weapon(target: TargetActor) -> bool:
	return (
		target.character_model.body_instance.mesh.get_surface_count() > 0
		and target.character_model.weapon_instance.mesh.get_surface_count() > 0
	)


func _model_feet_height(model: MdlCharacterModel) -> float:
	var bounds := model.body_instance.mesh.get_aabb()
	return model.position.y + bounds.position.y * model.scale.y


func _uses_goldsrc_hull(target: TargetActor) -> bool:
	var shape_node := target.get_node_or_null("PlayerCollider") as CollisionShape3D
	return (
		shape_node != null
		and shape_node.shape is BoxShape3D
		and (shape_node.shape as BoxShape3D).size.is_equal_approx(
			Vector3(0.32, 0.72, 0.32),
		)
	)


func _uses_world_model_scale(target: TargetActor) -> bool:
	return target.character_model.scale.is_equal_approx(Vector3.ONE)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame

	_check(game.player != null, "player spawned")
	_check(game.player.camera != null, "first-person camera exists")
	_check(game.player.armor == 100, "player starts with the original armor loadout")
	_check(game.targets.size() == 5, "five hostile targets spawned")
	_check(game.allied_bots.size() == 4, "four allied bots spawned")
	_check(
		game.get_tree().get_nodes_in_group("combatants").size() == 10,
		"offline match has ten shared combatants",
	)
	_check(
		game.player.combat_controller is HumanCombatController,
		"human pawn is driven by HumanCombatController",
	)
	_check(
		game._all_bots().all(
			func(target: TargetActor) -> bool: return target.combat_controller is BotCombatController
		),
		"all nine bot pawns are driven by BotCombatController",
	)
	_check(
		game.allied_bots.all(
			func(target: TargetActor) -> bool: return target.team == Combatant.TEAM_TERRORIST
		),
		"allied bots have terrorist team identity",
	)
	_check(
		game.targets.all(
			func(target: TargetActor) -> bool: return target.team == Combatant.TEAM_COUNTER_TERRORIST
		),
		"hostile bots have counter-terrorist team identity",
	)
	_check(
		game._all_bots().all(
			func(target: TargetActor) -> bool: return _uses_authentic_model(target)
		),
		"every bot uses an authentic player model instead of fallback geometry",
	)
	var represented_skins := {}
	for bot in game._all_bots():
		represented_skins[bot.player_skin] = true
	_check(
		represented_skins.size() == 8,
		"all four T and all four CT player skins are represented",
	)
	var required_animations := ["idle", "run", "crouchidle", "crouchrun", "shoot", "die"]
	var has_required_animations := true
	for animation in required_animations:
		if not game.allied_bots[0].character_model.available_animations.has(animation):
			has_required_animations = false
	_check(
		has_required_animations,
		"player models provide the original locomotion, firing, and death states",
	)
	_check(
		game._all_bots().all(
			func(target: TargetActor) -> bool: return _has_body_and_weapon(target)
		),
		"all player skins render with an attached third-person weapon",
	)
	_check(
		game._all_bots().all(
			func(target: TargetActor) -> bool: return _uses_goldsrc_hull(target)
		),
		"bots use the scaled 32 by 32 by 72 GoldSrc box hull",
	)
	_check(
		game._all_bots().all(
			func(target: TargetActor) -> bool: return _uses_world_model_scale(target)
		),
		"player MDLs use the same 0.01 world scale as BSP geometry",
	)
	_check(game.hud != null, "HUD instantiated")
	var hud_root := game.hud.get_node("HUDRoot") as Control
	_check(hud_root.get_node_or_null("MatchBar") == null, "modern persistent match card is absent")
	_check(hud_root.get_node_or_null("ClassicRadar") != null, "classic upper-left radar is present")
	_check(hud_root.get_node_or_null("ClassicVitals") != null, "classic sparse vitals are present")
	_check(hud_root.get_node_or_null("ClassicTimer") != null, "classic lower-center timer is present")
	_check(hud_root.get_node_or_null("ClassicAmmo") != null, "classic sparse ammo counter is present")
	_check(game.hud.hitmarker.get_child_count() == 0, "CS 1.6 HUD has no hit-confirm marker")
	_check(Engine.physics_ticks_per_second == 100, "classic 100 Hz fixed physics configured")
	_check(not game.using_imported_map, "procedural test arena selected")

	game.start_match()
	await physics_frame
	_check(game.match_started, "match deploys")
	_check(game.phase == "freeze", "round starts in freeze time")
	_check(not game.player.controls_enabled, "movement is locked during freeze time")
	game._begin_live()
	await physics_frame
	_check(game.player.controls_enabled, "player controls enable when live")
	_check(game.targets.all(func(target: TargetActor) -> bool: return target.active), "targets activate when live")
	_check(game.allied_bots.all(func(target: TargetActor) -> bool: return target.active), "allies activate when live")
	_check(not Input.use_accumulated_input, "raw mouse input is not frame-accumulated")
	_check(InputMap.has_action("walk"), "Shift walk input is registered")
	_check(
		game.player._movement_speed(false, true) < game.player._movement_speed(false, false),
		"walking has a lower maximum speed than running",
	)
	Input.action_press("walk")
	var walking_command: Dictionary = game.player.combat_controller.gather_command(1.0 / 100.0)
	_check(walking_command.walk, "holding Shift reaches the human controller")
	Input.action_release("walk")

	Input.action_press("crouch")
	var control_click := InputEventMouseButton.new()
	control_click.button_index = MOUSE_BUTTON_RIGHT
	control_click.ctrl_pressed = true
	control_click.pressed = true
	game.player.combat_controller.ingest_input(control_click)
	var crouch_fire_command: Dictionary = game.player.combat_controller.gather_command(1.0 / 100.0)
	_check(crouch_fire_command.crouch, "holding Control requests crouch")
	_check(crouch_fire_command.fire, "macOS Control-click still requests fire")
	_check(crouch_fire_command.fire_pressed, "macOS Control-click preserves the fire edge")
	control_click.ctrl_pressed = false
	control_click.pressed = false
	game.player.combat_controller.ingest_input(control_click)
	Input.action_release("crouch")
	var released_command: Dictionary = game.player.combat_controller.gather_command(1.0 / 100.0)
	_check(not released_command.fire, "Control-click fire releases cleanly")

	game.player._walking = true
	game.player._standing = true
	game.player.velocity = Vector3(2.0, 0.0, 0.0)
	game.player._next_footstep_tick = game.player.weapon_clock.tick
	var audio_trace_size := int(game.audio_router.trace().size())
	game.player._apply_view_bob()
	_check(
		game.audio_router.trace().size() == audio_trace_size,
		"Shift walking does not emit footsteps",
	)
	game.player._walking = false
	for bot in game._all_bots():
		bot.active = false
	var animated_model: MdlCharacterModel = game.allied_bots[0].character_model
	var idle_feet_height := _model_feet_height(animated_model)
	_check(
		absf(idle_feet_height) < 0.05,
		(
			"standing player-model feet align with the collision-body floor "
			+ "(feet=%.3f m, offset=%.3f m, bounds=%.3f m)"
		)
		% [
			idle_feet_height,
			animated_model.position.y,
			animated_model.body_instance.mesh.get_aabb().position.y,
		],
	)
	animated_model.set_locomotion(true)
	animated_model._process(0.1)
	_check(animated_model.animation_state == "run", "moving bots select the run animation")
	animated_model.play_action("shoot")
	animated_model._process(0.02)
	_check(animated_model.animation_state == "shoot", "bot firing selects the shoot animation")
	_check(
		absf(_model_feet_height(animated_model) - idle_feet_height) < 0.08,
		"standing AK fire does not select a half-buried crouch pose",
	)
	animated_model.play_death()
	animated_model._process(0.02)
	_check(
		absf(_model_feet_height(animated_model) - idle_feet_height) < 0.08,
		"death animation begins from a grounded standing pose",
	)
	animated_model.reset_animation()
	var duel_ally: TargetActor = game.allied_bots[0]
	var duel_enemy: TargetActor = game.targets[0]
	duel_ally.reset_target(Vector3(-6, 0.08, 6))
	duel_enemy.reset_target(Vector3(-6, 0.08, 1))
	await physics_frame
	var bot_command: Dictionary = duel_ally.combat_controller.gather_command(1.0 / 100.0)
	_check(bot_command.enemy == duel_enemy, "bot perception selects the nearest opposing combatant")
	_check(bot_command.state == "react", "visible opposing bots honor acquisition reaction time")
	for reaction_tick in range(18):
		bot_command = duel_ally.combat_controller.gather_command(1.0 / 100.0)
	_check(bot_command.state == "engage", "visible opposing bots engage after expert reaction time")
	var duel_enemy_health: int = duel_enemy.health
	duel_ally._try_fire(duel_enemy)
	_check(duel_enemy.health < duel_enemy_health, "bot fire damages an opposing combatant")
	duel_ally.active = false
	duel_enemy.active = false
	var network := root.get_node("NetworkSession")
	var sanitized_input: Dictionary = network.sanitize_input({
		"movement": Vector2(3, 4), "pitch": 99.0, "buttons": 255,
	}, 7)
	_check(sanitized_input.movement.length() <= 1.001, "network input magnitude is server-clamped")
	_check(sanitized_input.pitch < PI * 0.5, "network pitch is server-clamped")
	_check(sanitized_input.buttons == 63, "network action bitfield includes allow-listed walking")

	var initial_yaw: float = game.player.rotation.y
	var initial_pitch: float = game.player.camera.rotation.x
	game.player._apply_mouse_look(Vector2(80, -40))
	_check(game.player.rotation.y < initial_yaw, "horizontal mouse motion changes yaw")
	_check(game.player.camera.rotation.x > initial_pitch, "vertical mouse motion changes pitch")
	_check(game.hud.hitmarker.mouse_filter == Control.MOUSE_FILTER_IGNORE, "center HUD cannot intercept aiming")
	game.player.face_toward(Vector3(0, 0.08, 8))

	var first_ally: TargetActor = game.allied_bots[0]
	var ally_health: int = first_ally.health
	first_ally.apply_damage(80.0, first_ally.aim_point(), true, game.player)
	_check(first_ally.health == ally_health, "friendly fire is rejected by shared combat rules")
	for bot in game._all_bots():
		bot.active = false
	# The production player now starts with the team-authentic pistol + knife.
	# Grant the legacy smoke-test loadout explicitly through the public buy API.
	_check(game.player.grant_item("ak47"), "buy API grants a primary weapon")
	_check(game.player.grant_item("ammo_762nato", 3), "buy API grants rifle ammo boxes")
	_check(game.player.grant_item("deagle"), "buy API grants a secondary weapon")
	_check(game.player.grant_item("ammo_50ae", 5), "buy API grants pistol ammo boxes")
	_check(game.player.grant_item("hegrenade"), "buy API grants a grenade")
	game.player.switch_weapon("ak47")
	game.player._advance_weapon_simulation_tick(75)

	var first_target: TargetActor = game.targets[0]
	first_target.reset_target(Vector3(0, 0.08, 8))
	# At 400 GoldSrc units the AK's 36 base damage truncates to 35 after
	# FireBullets3 range falloff. Make that exact body shot lethal.
	first_target.health = 35
	first_target.active = false
	await physics_frame
	game.player._try_fire()
	await process_frame
	_check(game.player.clip == 29, "firing consumes one round")
	_check(not first_target.alive, "camera ray and weapon damage eliminate a target")
	_check(game.kills == 1, "elimination advances the objective")
	_check(
		first_target.character_model.animation_state == "die",
		"eliminated bots select the original death animation",
	)

	var previous_health: int = game.player.health
	game.player.apply_damage(10.0)
	await process_frame
	_check(game.player.health < previous_health, "incoming damage reaches the player")
	_check(game.player.reserve == 90, "reserve ammunition initialized")
	game.player._advance_weapon_simulation_tick(10)
	game.player._start_reload()
	_check(game.player.reloading, "AK reload enters authoritative timed state")
	game.player._advance_weapon_simulation_tick(244)
	_check(game.player.reloading, "AK reload remains active through tick 244")
	_check(game.player.clip == 29, "AK ammunition does not transfer before reload completion")
	game.player._advance_weapon_simulation_tick()
	_check(not game.player.reloading, "AK reload completes exactly on tick 245")
	_check(game.player.clip == 30 and game.player.reserve == 89, "AK reload transfers ammunition on completion")
	_check(game.player.viewmodel.loaded_weapon == "ak47", "authentic AK-47 viewmodel loads")
	game.player.switch_weapon("deagle")
	_check(game.player.active_weapon == "deagle", "number-slot weapon switching works")
	_check(game.player.clip == 7, "Deagle maintains independent ammunition")
	game.player.switch_weapon("knife")
	_check(game.player.clip == -1, "knife correctly has no ammunition")
	game.player.switch_weapon("hegrenade")
	game.player._advance_weapon_simulation_tick(75)
	game.player._try_fire()
	_check(
		game.player.weapon_clock.state == game.player.WeaponClockScript.STATE_GRENADE_PINNED,
		"HE primary enters the pin-held state",
	)
	_check(game.player.ammunition.hegrenade.clip == 1, "HE is not consumed while its pin is held")
	game.player.weapon_clock.release_grenade(true)
	game.player._advance_weapon_simulation_tick(49)
	_check(game.player.ammunition.hegrenade.clip == 1, "early HE release waits through pin tick 49")
	game.player._advance_weapon_simulation_tick()
	await process_frame
	_check(game.player.ammunition.hegrenade.clip == 0, "HE grenade is consumed on throw")
	_check(game.get_node_or_null("HEGrenade") != null, "HE grenade projectile spawns")

	game._plant_bomb(game.bomb_sites[0])
	_check(game.phase == "bomb", "planting transitions to the bomb phase")
	_check(game.bomb_planted, "planted bomb state is authoritative")

	for target in game.targets:
		if target.alive:
			target.apply_damage(1000.0, target.aim_point(), false, game.player)
	_check(game.round_ending, "eliminating the CT team ends the round")
	_check(game.terrorist_score == 1, "team elimination awards the terrorist round")
	for bot in game._all_bots():
		bot.active = false
	await create_timer(1.65).timeout

	if failures.is_empty():
		print("GAME_SMOKE_TEST_PASS")
		game.process_mode = Node.PROCESS_MODE_DISABLED
		game.audio_router.stop_all("test_teardown")
		await process_frame
		game.audio_playback.clear_pool()
		current_scene = null
		game.queue_free()
		await process_frame
		await process_frame
		CS16CombatEffects.release_cached_resources()
		MdlCharacterModel.release_cached_resources()
		quit(0)
	else:
		print("GAME_SMOKE_TEST_FAIL: %s" % ", ".join(failures))
		game.process_mode = Node.PROCESS_MODE_DISABLED
		game.audio_router.stop_all("test_teardown")
		await process_frame
		game.audio_playback.clear_pool()
		current_scene = null
		game.queue_free()
		await process_frame
		await process_frame
		CS16CombatEffects.release_cached_resources()
		MdlCharacterModel.release_cached_resources()
		quit(1)
