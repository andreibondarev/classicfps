extends SceneTree

var failures: Array[String] = []
var controller := HumanCombatController.new()

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _event(button: MouseButton, pressed: bool, mask: int, ctrl := true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.button_mask = mask
	event.ctrl_pressed = ctrl
	return event

func _button(pressed: bool, mask: int, ctrl := true) -> int:
	return controller._physical_mouse_button(_event(MOUSE_BUTTON_RIGHT, pressed, mask, ctrl), true)

func _run() -> void:
	_check(AudioServer.get_driver_name() == "Dummy", "fixture must be muted")
	_check(_button(true, 1) == MOUSE_BUTTON_LEFT, "macOS Ctrl-left recovers primary")
	_check(_button(false, 0, false) == MOUSE_BUTTON_LEFT, "Ctrl release before mouse still releases primary")
	_check(_button(true, 2) == MOUSE_BUTTON_RIGHT, "genuine Ctrl-right stays secondary")
	_check(_button(true, 3) == MOUSE_BUTTON_LEFT, "Ctrl-left while right is held stays primary")
	_check(_button(false, 1) == MOUSE_BUTTON_RIGHT, "releasing right while translated left is held stays secondary")
	_check(_button(false, 0) == MOUSE_BUTTON_LEFT, "translated primary releases independently")
	_check(_button(true, 1) == MOUSE_BUTTON_LEFT and _button(true, 3) == MOUSE_BUTTON_RIGHT,
		"right while translated left is held stays secondary")
	controller.set_menu_input_blocked(true)
	_check(not controller._mac_control_left_down, "menu clears translated held state")
	controller.set_menu_input_blocked(false)
	_check(controller._physical_mouse_button(_event(MOUSE_BUTTON_RIGHT, true, 1), false) == MOUSE_BUTTON_RIGHT,
		"other platforms never remap right-click")
	# Exercise the actual controller and weapon, including held automatic fire.
	if OS.get_name() == "macOS":
		var world := Node3D.new()
		root.add_child(world)
		current_scene = world
		var player := PlayerController.new()
		world.add_child(player)
		player.set_physics_process(false)
		await process_frame
		player.controls_enabled = true
		player.alive = true
		player.grant_item("ak47")
		player.switch_weapon("ak47")
		player._advance_weapon_simulation_tick(100)
		var clip := player.clip
		Input.action_press("crouch")
		player._input(_event(MOUSE_BUTTON_RIGHT, true, 1))
		for tick in 25:
			player._physics_process(0.01)
		_check(player.clip < clip - 1 and bool(player.last_command.crouch), "crouched automatic fire holds across weapon ticks")
		player._input(_event(MOUSE_BUTTON_RIGHT, false, 0, false))
		clip = player.clip
		for tick in 25:
			player._physics_process(0.01)
		_check(player.clip == clip, "release stops firing even if Ctrl was released first")
		Input.action_release("crouch")
		world.queue_free()
		await process_frame
	controller.free()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_CROUCH_MOUSE_INPUT_PASS")
	quit(0 if failures.is_empty() else 1)
