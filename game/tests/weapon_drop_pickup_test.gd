extends SceneTree

const CS16CombatEffects := preload("res://scripts/cs16_combat_effects.gd")
const MdlCharacterModel := preload("res://scripts/mdl_character_model.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("WEAPON DROP PICKUP TEST: " + message)


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
		"round_ticks": 1000,
		"restart_ticks": 2,
	})
	game.start_match()
	_advance_game_round(game, 1)
	_check(game.phase == "live", "fixture reaches the live phase")

	# 1. A bot death drops its carried gun with the live clip preserved.
	var target = game.targets[0]
	target.active_weapon_name = "ak47"
	target.weapon_clip = 17
	target.weapon_reserve = 60
	target.alive = false
	game._on_target_died(target, false)
	_check(game.dropped_weapons.size() == 1, "bot death spawns exactly one dropped gun")
	var bot_drop = game.dropped_weapons[0] if not game.dropped_weapons.is_empty() else null
	_check(
		bot_drop != null
		and bot_drop.weapon_name == "ak47"
		and bot_drop.clip_ammo == 17
		and bot_drop.reserve_ammo == 60,
		"bot drop preserves weapon identity and live clip/reserve",
	)
	await physics_frame

	# 2. Touching a drop whose slot is occupied changes nothing.
	game.player.grant_item("galil")
	game.player.switch_weapon("galil")
	game.player.clip = 21
	_check(game.player.active_weapon == "galil", "fixture equips a slot-1 gun")
	game.player.global_position = bot_drop.global_position
	game._process_weapon_pickups()
	_check(
		game.player.owns_weapon("galil")
		and not game.player.owns_weapon("ak47")
		and game.dropped_weapons.size() == 1,
		"touch with an occupied slot leaves the drop and inventory untouched",
	)

	# 3. G drop tosses the active gun forward and swaps to the next weapon.
	game.player.global_position = bot_drop.global_position + Vector3(5.0, 0.0, 0.0)
	game.player.controls_enabled = true
	var drop_event := InputEventAction.new()
	drop_event.action = "drop"
	drop_event.pressed = true
	game.player.combat_controller.ingest_input(drop_event)
	game.player._physics_process(0.01)
	_check(
		not game.player.owns_weapon("galil")
		and game.player.active_weapon == "glock18",
		"G drop removes the active gun and auto-switches to the next best weapon",
	)
	_check(game.dropped_weapons.size() == 2, "G drop spawns a world item")
	var manual_drop = game.dropped_weapons[1] if game.dropped_weapons.size() > 1 else null
	_check(
		manual_drop != null
		and manual_drop.weapon_name == "galil"
		and manual_drop.clip_ammo == 21,
		"G drop preserves the current clip on the world item",
	)
	_check(
		manual_drop != null
		and manual_drop.global_position.distance_to(game.player.global_position) > 0.25,
		"G drop tosses the item forward of the dropper",
	)
	game._process_weapon_pickups()
	_check(
		not game.player.owns_weapon("galil"),
		"a just-dropped gun is not vacuumed straight back by its dropper",
	)

	# 4. Touching a drop with an empty slot picks it up and deploys it.
	game.player.global_position = bot_drop.global_position
	game._process_weapon_pickups()
	_check(
		game.player.owns_weapon("ak47")
		and int(game.player.ammunition.ak47.clip) == 17
		and int(game.player.ammunition.ak47.reserve) == 60,
		"empty-slot touch grants the gun with the dropped clip and reserve",
	)
	_check(
		game.player.active_weapon == "ak47",
		"pickup immediately deploys the picked-up weapon",
	)
	_check(
		game.dropped_weapons.size() == 1,
		"claimed drop leaves the live drop list",
	)

	# 5. A round reset clears every remaining ground weapon.
	game._reset_combatants_for_round()
	_check(game.dropped_weapons.is_empty(), "round reset clears all dropped guns")

	if failures.is_empty():
		print("GAME_WEAPON_DROP_PICKUP_TEST_PASS")
		await _teardown(game)
		quit(0)
	else:
		print("GAME_WEAPON_DROP_PICKUP_TEST_FAIL (%d)" % failures.size())
		await _teardown(game)
		quit(1)


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
