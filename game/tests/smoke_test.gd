extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SMOKE TEST: " + message)


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
	_check(game.hud != null, "HUD instantiated")
	_check(Engine.physics_ticks_per_second == 128, "128 Hz fixed physics configured")
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
	var walking_command: Dictionary = game.player.combat_controller.gather_command(1.0 / 128.0)
	_check(walking_command.walk, "holding Shift reaches the human controller")
	Input.action_release("walk")

	Input.action_press("crouch")
	var control_click := InputEventMouseButton.new()
	control_click.button_index = MOUSE_BUTTON_RIGHT
	control_click.ctrl_pressed = true
	control_click.pressed = true
	game.player.combat_controller.ingest_input(control_click)
	var crouch_fire_command: Dictionary = game.player.combat_controller.gather_command(1.0 / 128.0)
	_check(crouch_fire_command.crouch, "holding Control requests crouch")
	_check(crouch_fire_command.fire, "macOS Control-click still requests fire")
	_check(crouch_fire_command.fire_pressed, "macOS Control-click preserves the fire edge")
	control_click.ctrl_pressed = false
	control_click.pressed = false
	game.player.combat_controller.ingest_input(control_click)
	Input.action_release("crouch")
	var released_command: Dictionary = game.player.combat_controller.gather_command(1.0 / 128.0)
	_check(not released_command.fire, "Control-click fire releases cleanly")

	game.player._walking = true
	game.player._standing = true
	game.player._step_distance = game.player._next_step_at
	game.player.footstep_audio.stop()
	game.player._apply_view_bob()
	_check(not game.player.footstep_audio.playing, "Shift walking does not emit footsteps")
	game.player._walking = false
	for bot in game._all_bots():
		bot.active = false
	var duel_ally: TargetActor = game.allied_bots[0]
	var duel_enemy: TargetActor = game.targets[0]
	duel_ally.reset_target(Vector3(-6, 0.08, 6))
	duel_enemy.reset_target(Vector3(-6, 0.08, 1))
	await physics_frame
	var bot_command: Dictionary = duel_ally.combat_controller.gather_command(1.0 / 128.0)
	_check(bot_command.enemy == duel_enemy, "bot perception selects the nearest opposing combatant")
	_check(bot_command.state == "engage", "visible opposing bots enter the engage state")
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

	var first_target: TargetActor = game.targets[0]
	first_target.reset_target(Vector3(0, 0.08, 8))
	first_target.active = false
	await physics_frame
	game.player._try_fire()
	await process_frame
	_check(game.player.clip == 29, "firing consumes one round")
	_check(not first_target.alive, "camera ray and weapon damage eliminate a target")
	_check(game.kills == 1, "elimination advances the objective")

	var previous_health: int = game.player.health
	game.player.apply_damage(10.0)
	await process_frame
	_check(game.player.health < previous_health, "incoming damage reaches the player")
	_check(game.player.reserve == 90, "reserve ammunition initialized")
	_check(game.player.viewmodel.loaded_weapon == "ak47", "authentic AK-47 viewmodel loads")
	game.player.switch_weapon("deagle")
	_check(game.player.active_weapon == "deagle", "number-slot weapon switching works")
	_check(game.player.clip == 7, "Deagle maintains independent ammunition")
	game.player.switch_weapon("knife")
	_check(game.player.clip == -1, "knife correctly has no ammunition")
	game.player.switch_weapon("hegrenade")
	game.player._next_fire_at = 0.0
	game.player._try_fire()
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
		current_scene = null
		game.queue_free()
		await process_frame
		quit(0)
	else:
		print("GAME_SMOKE_TEST_FAIL: %s" % ", ".join(failures))
		current_scene = null
		game.queue_free()
		await process_frame
		quit(1)
