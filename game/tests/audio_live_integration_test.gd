extends SceneTree

const AudioCatalog := preload("res://scripts/cs16_audio_catalog.gd")
const AudioRouter := preload("res://scripts/cs16_audio_event_router.gd")
const GrenadeScript := preload("res://scripts/grenade.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("LIVE AUDIO INTEGRATION: " + message)


func _starts(router: CS16AudioEventRouter) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for event: Dictionary in router.trace():
		if str(event.kind) == "start":
			output.append(event)
	return output


func _event(router: CS16AudioEventRouter, event_name: String) -> Dictionary:
	for event: Dictionary in _starts(router):
		if str(event.event_name) == event_name:
			return event
	return {}


func _advance_player(
	router: CS16AudioEventRouter,
	player: PlayerController,
	ticks: int,
) -> void:
	for ignored_tick in range(ticks):
		router.advance_ticks(1)
		player._advance_weapon_simulation_tick(1)


func _check_catalog_files() -> void:
	for event_name: String in AudioCatalog.EVENT_SAMPLES:
		for sample: Variant in AudioCatalog.EVENT_SAMPLES[event_name]:
			_check(
				FileAccess.file_exists(AudioRouter.SOUND_ROOT.path_join(str(sample))),
				"%s resolves missing App 90 sample %s" % [event_name, sample],
			)
	for family: Dictionary in AudioCatalog.FOOTSTEP_FAMILIES.values():
		for sample_index in range(1, int(family.count) + 1):
			var sample := "player/%s%d.wav" % [str(family.prefix), sample_index]
			_check(
				FileAccess.file_exists(AudioRouter.SOUND_ROOT.path_join(sample)),
				"footstep family resolves missing App 90 sample %s" % sample,
			)


func _run() -> void:
	_check_catalog_files()
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main game scene loads")
	if packed == null:
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game
	# Playback allocation is covered by audio_playback_adapter_test.gd. This
	# live integration gate verifies authoritative routing and must not leave
	# device-backed WAV playbacks alive when its SceneTree exits.
	game.audio_playback.playback_enabled = false
	await process_frame
	await physics_frame

	var router: CS16AudioEventRouter = game.audio_router
	_check(is_instance_valid(router), "game owns the live audio router")
	_check(not router.is_processing(), "router render _process clock is disabled")
	var authoritative_tick := router.current_tick
	await physics_frame
	_check(
		router.current_tick == authoritative_tick + 1,
		"one authoritative physics frame advances the router exactly once",
	)
	_check(
		game.audio_playback.listener_origin_hu.is_equal_approx(
			AudioRouter.meters_to_hu(game.player.camera.global_position)
		),
		"listener follows the live camera in HU each authoritative tick",
	)

	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)

	var player: PlayerController = game.player
	player.audio_router = router
	player.global_position = Vector3(10.0, 0.0, 0.0)
	player.active_weapon = "ak47"
	player.clip = 30
	player.reserve = 90
	player.reloading = false
	player.weapon_clock.reset("ak47")
	router.reset(0xC516)
	player._try_fire()
	var ak_event := _event(router, "ak47.fire")
	_check(not ak_event.is_empty(), "live Player AK fire reaches the router")
	_check(int(ak_event.channel) == AudioRouter.CHAN_WEAPON, "AK uses CHAN_WEAPON")
	_check(int(ak_event.tick) == 0, "AK fire keeps the authoritative tick")
	_check(
		ak_event.origin == [1000.0, 0.0, 0.0],
		"10 metre emitter origin is traced as 1000 HU exactly once",
	)

	router.reset(0xC516)
	player.active_weapon = "ak47"
	player.clip = 1
	player.reserve = 90
	player.reloading = false
	player.weapon_clock.reset("ak47")
	player._start_reload()
	_advance_player(router, player, 154)
	var clip_out := _event(router, "ak47.clip_out")
	var clip_in := _event(router, "ak47.clip_in")
	_check(int(clip_out.get("tick", -1)) == 35, "AK clip-out uses MDL event tick 35")
	_check(int(clip_in.get("tick", -1)) == 154, "AK clip-in uses MDL event tick 154")
	_check(
		int(clip_out.get("channel", -1)) == AudioRouter.CHAN_WEAPON,
		"AK reload stages use CHAN_WEAPON",
	)

	router.reset(0xC516)
	player.active_weapon = "deagle"
	player.clip = 1
	player.reserve = 35
	player.reloading = false
	player.weapon_clock.reset("deagle")
	player._start_reload()
	_advance_player(router, player, 113)
	_check(
		int(_event(router, "deagle.clip_out").get("tick", -1)) == 47,
		"Deagle clip-out uses MDL event tick 47",
	)
	_check(
		int(_event(router, "deagle.clip_in").get("tick", -1)) == 113,
		"Deagle clip-in uses MDL event tick 113",
	)

	router.reset(0xC516)
	player.active_weapon = "hegrenade"
	player.clip = 1
	player.reserve = 0
	player.reloading = false
	player.weapon_clock.reset("hegrenade")
	player._audio_schedule.clear()
	player._try_fire()
	_advance_player(router, player, 66)
	var pin := _event(router, "he.pull_pin")
	_check(int(pin.get("tick", -1)) == 66, "HE pin uses MDL event tick 66")
	_check(
		str(pin.get("sample", "")) == "weapons/pinpull.wav",
		"HE pin uses the App 90 model-event sample",
	)

	router.reset(0xC516)
	player.active_weapon = "ak47"
	player.clip = 0
	player.reserve = 0
	player.reloading = false
	player.weapon_clock.reset("ak47")
	player._try_fire()
	_check(
		int(_event(router, "weapon.empty_rifle").get("channel", -1))
			== AudioRouter.CHAN_WEAPON,
		"Player dry rifle fire reaches CHAN_WEAPON",
	)

	var target: TargetActor = game.targets[0]
	target.audio_router = router
	target.global_position = Vector3(9.0, 0.0, 0.0)
	target.reset_target(target.global_position)
	# Bots spawn on the classic pistol-round loadout, so the rifle fire event
	# under test has to be equipped explicitly rather than assumed.
	target.configure_weapon("ak47")
	router.reset(0xC516)
	target._try_fire(player)
	_check(
		int(_event(router, "ak47.fire").get("entity_id", -1))
			== target.audio_entity_id(),
		"TargetActor fire uses its stable audio entity",
	)
	target.apply_damage(5.0, target.global_position, false)
	_check(
		int(_event(router, "player.pain").get("channel", -1))
			== AudioRouter.CHAN_VOICE,
		"TargetActor pain uses CHAN_VOICE",
	)
	target.apply_damage(500.0, target.global_position, true)
	_check(
		int(_event(router, "player.headshot_death").get("channel", -1))
			== AudioRouter.CHAN_VOICE,
		"TargetActor headshot death uses CHAN_VOICE",
	)

	router.reset(0xC516)
	var metal_step := AudioCatalog.footstep_descriptor(
		"metal",
		false,
		AudioCatalog.footstep_volume("metal"),
	)
	target._emit_audio_descriptor("player.step.M", metal_step)
	var step_event := _event(router, "player.step.M")
	_check(int(step_event.get("channel", -1)) == AudioRouter.CHAN_BODY, "steps use CHAN_BODY")
	_check(
		str(step_event.get("sample", "")).begins_with("player/pl_metal"),
		"material footstep data selects the metal App 90 family",
	)

	router.reset(0xC516)
	var grenade: HEGrenade = GrenadeScript.new()
	game.add_child(grenade)
	grenade.launch(Vector3(10.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0), player)
	grenade._on_body_entered(null)
	grenade.explode()
	var bounce := _event(router, "he.bounce")
	var explosion := _event(router, "he.explode")
	var debris := _event(router, "he.debris")
	_check(str(bounce.get("sample", "")) == "weapons/he_bounce-1.wav", "HE bounce path")
	_check(is_equal_approx(float(bounce.get("volume", -1.0)), 0.25), "HE bounce volume")
	_check(int(explosion.get("channel", -1)) == AudioRouter.CHAN_WEAPON, "HE explosion channel")
	_check(str(explosion.get("sample", "")) == "weapons/explode3.wav", "HE source explosion path")
	_check(int(debris.get("channel", -1)) == AudioRouter.CHAN_VOICE, "HE debris channel")

	router.reset(0xC516)
	game.bomb_planted = false
	game.round_ending = false
	game._plant_bomb(Vector3(10.0, 0.0, 0.0))
	game._update_c4_audio()
	_check(int(_event(router, "c4.plant").get("channel", -1)) == AudioRouter.CHAN_WEAPON, "C4 plant channel")
	_check(
		int(_event(router, "radio.bomb_planted").get("channel", -1))
			== AudioRouter.CHAN_STREAM,
		"bomb-planted announcer channel",
	)
	_check(int(_event(router, "c4.beep1").get("tick", -1)) == 0, "first C4 beep tick")
	game._explode_bomb()
	_check(str(_event(router, "c4.explode").get("sample", "")) == "weapons/c4_explode1.wav", "C4 explosion path")
	_check(int(_event(router, "round.t_win").get("channel", -1)) == AudioRouter.CHAN_STREAM, "round announcer channel")

	var passed := _failures.is_empty()
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
	if passed:
		print(
			"CS16_LIVE_AUDIO_INTEGRATION_TEST_PASS "
			+ "(authoritative tick, HU boundary, Player/Target/HE/C4 paths)",
		)
		quit(0)
	else:
		for failure: String in _failures:
			print("FAIL: ", failure)
		quit(1)
