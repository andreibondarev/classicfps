extends SceneTree

var failures: Array[String] = []
var player: PlayerController
var router: CS16AudioEventRouter


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _button(button: MouseButton, down: bool, crouched := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.ctrl_pressed = crouched
	player._input(event)


func _tap(button: MouseButton, crouched := false) -> void:
	_button(button, true, crouched)
	_button(button, false, crouched)


func _ticks(count: int) -> void:
	for ignored_tick in range(count):
		router.advance_ticks(1)
		player._physics_process(0.01)


func _sounds(event_name: String) -> Array[Dictionary]:
	var sounds: Array[Dictionary] = []
	for event: Dictionary in router.trace():
		if event.kind == "start" and event.event_name == event_name:
			sounds.append(event)
	return sounds


func _reset() -> void:
	router.reset(0xC516)
	player.combat_controller.set_menu_input_blocked(false)
	player.active_weapon = "glock18"
	player.weapon_modes.glock18 = false
	player.weapon_clock.reset("glock18")
	player.clip = 20
	player.reserve = 120
	player._burst_shots_remaining = 0
	player._glock_recorded_burst = false
	player._next_burst_tick = -1
	player._glock_trigger_consumed = false
	player.reloading = false
	player.alive = true
	player.controls_enabled = true
	player.velocity = Vector3.ZERO
	player.position = Vector3.ZERO


func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy":
		push_error("Glock input fixture requires Dummy audio")
		quit(1)
		return
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	router = CS16AudioEventRouter.new()
	router.name = CS16AudioEventRouter.NODE_NAME
	world.add_child(router)
	router.set_process(false)
	player = PlayerController.new()
	world.add_child(player)
	player.set_physics_process(false)
	await process_frame
	_reset()
	_tap(MOUSE_BUTTON_RIGHT)
	_ticks(1)
	_check(player.weapon_modes.glock18 and player.clip == 20, "right-click toggles burst without firing")
	_check(_sounds("weapon.mode_switch").size() == 1, "successful mode change gives one audible confirmation")
	_tap(MOUSE_BUTTON_LEFT)
	_ticks(1)
	_check(player.clip == 19, "left-click immediately after a burst toggle fires the first round")
	_ticks(20)
	_check(player.clip == 17 and player._burst_shots_remaining == 0, "one left-click finishes exactly three burst rounds")
	_check(_sounds("glock18.fire_burst").size() == 1 and _sounds("glock18.fire").is_empty(),
		"full burst plays its three-shot recording once, not once per bullet")
	_ticks(60)
	_check(player.clip == 17, "released left-click cannot start an extra burst")
	_tap(MOUSE_BUTTON_RIGHT)
	_ticks(1)
	_check(not player.weapon_modes.glock18, "right-click returns to semi-auto")
	_tap(MOUSE_BUTTON_LEFT)
	_ticks(1)
	_check(player.clip == 16, "left-click immediately after returning to semi-auto fires once")
	_ticks(30)
	_check(player.clip == 16, "semi-auto tap cannot repeat")

	_reset()
	_tap(MOUSE_BUTTON_RIGHT, true)
	_ticks(1)
	_check(player.weapon_modes.glock18 and player.clip == 20, "Ctrl plus right-click still toggles, never fires")
	_tap(MOUSE_BUTTON_RIGHT)
	_ticks(1)
	_check(player.weapon_modes.glock18, "rapid second right-click cannot bypass toggle cooldown")
	_check(_sounds("weapon.mode_switch").size() == 1, "rejected mode change produces no false confirmation")
	_ticks(28)
	_tap(MOUSE_BUTTON_RIGHT)
	_ticks(1)
	_check(not player.weapon_modes.glock18, "toggle becomes available at its 30-tick boundary")

	_reset()
	_tap(MOUSE_BUTTON_LEFT)
	_tap(MOUSE_BUTTON_RIGHT)
	_ticks(1)
	_check(player.weapon_modes.glock18 and player.clip == 20, "simultaneous clicks give the successful secondary action priority")

	_reset()
	_button(MOUSE_BUTTON_LEFT, true)
	_ticks(1)
	_check(player.clip == 19, "semi-auto press fires")
	_ticks(30)
	_check(player.clip == 19, "holding semi-auto cannot fire repeatedly")
	_button(MOUSE_BUTTON_LEFT, false)
	_ticks(1)
	_button(MOUSE_BUTTON_LEFT, true)
	_ticks(1)
	_check(player.clip == 18, "new semi-auto press fires again")
	_button(MOUSE_BUTTON_LEFT, false)
	_ticks(1)
	_button(MOUSE_BUTTON_LEFT, true)
	_ticks(1)
	_check(player.clip == 18, "early press still respects primary cooldown")
	_ticks(20)
	_check(player.clip == 17, "early held press fires when primary cooldown ends")
	_ticks(30)
	_check(player.clip == 17, "delayed semi-auto shot still consumes only one press")

	_reset()
	_button(MOUSE_BUTTON_LEFT, true)
	_tap(MOUSE_BUTTON_RIGHT)
	_ticks(1)
	_check(player.clip == 20 and player.weapon_modes.glock18, "simultaneous held primary gives toggle priority")
	_ticks(1)
	_check(player.clip == 19, "held primary starts burst on the tick after toggling")
	_ticks(20)
	_check(player.clip == 17, "held burst has exactly three initial rounds")
	_ticks(30)
	_check(player.clip == 16, "held burst starts the next burst only at its primary deadline")
	_button(MOUSE_BUTTON_LEFT, false)
	_ticks(20)
	_check(player.clip == 14, "releasing primary finishes only the in-flight burst")
	_ticks(60)
	_check(player.clip == 14, "release prevents any further bursts")
	_check(_sounds("glock18.fire_burst").size() == 2, "holding for two bursts plays exactly two burst recordings")

	_reset()
	_tap(MOUSE_BUTTON_LEFT)
	var command: Dictionary = player.combat_controller.gather_command(0.01)
	_check(command.fire_pressed and command.fire, "a complete between-ticks left click survives held-input network serialization")
	command = player.combat_controller.gather_command(0.01)
	_check(not command.fire and not command.fire_pressed, "the short-click pulse clears on the next tick")
	player.combat_controller.set_menu_input_blocked(true)
	_tap(MOUSE_BUTTON_LEFT)
	_tap(MOUSE_BUTTON_RIGHT)
	command = player.combat_controller.gather_command(0.01)
	_check(not command.fire and not command.secondary_pressed, "menus suppress both mouse buttons")

	_reset()
	for ignored_shot in range(12):
		_tap(MOUSE_BUTTON_LEFT)
		_ticks(16)
	_check(player.clip == 8 and _sounds("glock18.fire").size() == 12, "twelve semi-auto clicks produce twelve shot events")
	for sound: Dictionary in _sounds("glock18.fire"):
		_check(sound.sample == "weapons/glock18-2.wav", "semi-auto never randomly selects the burst recording")
	for remaining in [1, 2]:
		_reset()
		player.weapon_modes.glock18 = true
		player.clip = remaining
		_tap(MOUSE_BUTTON_LEFT)
		_ticks(21)
		_check(player.clip == 0 and _sounds("glock18.fire").size() == remaining and _sounds("glock18.fire_burst").is_empty(),
			"short magazine sounds only the rounds actually fired: %d" % remaining)
	_reset()
	_tap(MOUSE_BUTTON_RIGHT)
	_ticks(1)
	var cues := _sounds("weapon.mode_switch")
	if not cues.is_empty():
		_check(cues[0].sample == "common/wpn_select.wav" and cues[0].channel == CS16AudioEventRouter.CHAN_ITEM
			and cues[0].attenuation == CS16AudioEventRouter.ATTN_NONE and cues[0].volume < 1.0,
			"mode confirmation is quiet owner feedback on a separate channel")
	_reset()
	player.reloading = true
	_check(not player._try_secondary() and _sounds("weapon.mode_switch").is_empty(), "reload blocks mode change without sounding confirmation")
	player.reloading = false
	player.alive = false
	_check(not player._try_secondary() and _sounds("weapon.mode_switch").is_empty(), "dead player cannot sound mode confirmation")
	world.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_GLOCK_MOUSE_INPUT_PASS")
	quit(0 if failures.is_empty() else 1)
