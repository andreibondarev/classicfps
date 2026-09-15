class_name HumanCombatController
extends CombatController

var _look_delta := Vector2.ZERO
var _fire_held := false
var _fire_pressed := false
var _secondary_pressed := false
var _mac_mouse_mask := 0
var _mac_control_left_down := false
# Presses are latched from ingest_input (which sees every event) instead of
# polled with is_action_just_pressed inside the 100 Hz physics tick: on frames
# that run zero physics ticks (e.g. 120 Hz display vs 100 Hz physics) the
# "just pressed" edge expires before any tick can observe it.
var _jump_pressed := false
var _reload_pressed := false
var _drop_pressed := false
var _slot_request := 0
var _last_weapon_request := false
var menu_input_blocked := false


func set_menu_input_blocked(blocked: bool) -> void:
	menu_input_blocked = blocked
	_look_delta = Vector2.ZERO
	_fire_held = false
	_fire_pressed = false
	_secondary_pressed = false
	_mac_mouse_mask = 0
	_mac_control_left_down = false
	_jump_pressed = false
	_reload_pressed = false
	_drop_pressed = false
	_slot_request = 0
	_last_weapon_request = false


func ingest_input(event: InputEvent) -> void:
	if menu_input_blocked:
		return
	if event.is_action_pressed("jump"):
		_jump_pressed = true
	elif event.is_action_pressed("reload"):
		_reload_pressed = true
	elif event.is_action_pressed("drop"):
		_drop_pressed = true
	elif event.is_action_pressed("weapon_primary"):
		_slot_request = 1
	elif event.is_action_pressed("weapon_secondary"):
		_slot_request = 2
	elif event.is_action_pressed("weapon_melee"):
		_slot_request = 3
	elif event.is_action_pressed("weapon_grenade"):
		_slot_request = 4
	elif event.is_action_pressed("weapon_last"):
		_last_weapon_request = true
	if (
		event is InputEventMouseMotion
		and (
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			or (
				is_instance_valid(actor)
				and bool(actor.get("objective_movement_locked"))
			)
		)
	):
		_look_delta += event.relative
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		var button := _physical_mouse_button(mouse_event)
		if button == MOUSE_BUTTON_LEFT:
			_fire_held = mouse_event.pressed
			if mouse_event.pressed:
				_fire_pressed = true
		elif button == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_secondary_pressed = true


func _physical_mouse_button(event: InputEventMouseButton, macos := OS.get_name() == "macOS") -> int:
	var button := int(event.button_index)
	if not macos:
		return button
	# Godot 4.7.1 macOS maps Control-left to RIGHT but keeps NSEvent's physical
	# pressedMouseButtons in button_mask. Do not alias genuine Ctrl-right to fire.
	# Track the press so releasing Ctrl before the mouse cannot leave fire held.
	var mask := int(event.button_mask)
	if button == MOUSE_BUTTON_RIGHT:
		if event.pressed and event.ctrl_pressed and (mask & MOUSE_BUTTON_MASK_LEFT) != 0 \
			and ((mask & MOUSE_BUTTON_MASK_RIGHT) == 0 or (_mac_mouse_mask & MOUSE_BUTTON_MASK_LEFT) == 0):
			button = MOUSE_BUTTON_LEFT
			_mac_control_left_down = true
		elif not event.pressed and _mac_control_left_down and (mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			button = MOUSE_BUTTON_LEFT
			_mac_control_left_down = false
	_mac_mouse_mask = mask
	return button


func gather_command(delta: float) -> Dictionary:
	var command := super.gather_command(delta)
	if menu_input_blocked:
		return command
	command.movement = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	command.look_delta = _look_delta
	_look_delta = Vector2.ZERO
	# Held state plus the event latch; the pawn edge-detects, so holding jump
	# never re-jumps (1.6 +jump behavior) while a tap between physics ticks
	# still lands.
	command.jump = Input.is_action_pressed("jump") or _jump_pressed
	_jump_pressed = false
	command.crouch = Input.is_action_pressed("crouch")
	command.walk = Input.is_action_pressed("walk")
	# A press and release can both arrive between physics ticks. Carry that tap
	# for one tick in held input too, otherwise the network packet loses it.
	command.fire = Input.is_action_pressed("fire") or _fire_held or _fire_pressed
	command.fire_pressed = Input.is_action_just_pressed("fire") or _fire_pressed
	command.secondary_pressed = _secondary_pressed
	_fire_pressed = false
	_secondary_pressed = false
	command.reload = Input.is_action_just_pressed("reload") or _reload_pressed
	_reload_pressed = false
	command.drop = Input.is_action_just_pressed("drop") or _drop_pressed
	_drop_pressed = false
	command.use = Input.is_action_pressed("use")
	var slot := _slot_request
	_slot_request = 0
	if slot == 0:
		if Input.is_action_just_pressed("weapon_primary"):
			slot = 1
		elif Input.is_action_just_pressed("weapon_secondary"):
			slot = 2
		elif Input.is_action_just_pressed("weapon_melee"):
			slot = 3
		elif Input.is_action_just_pressed("weapon_grenade"):
			slot = 4
	if slot > 0 and is_instance_valid(actor) and actor.has_method("best_owned_weapon_in_slot"):
		command.weapon = str(actor.call("best_owned_weapon_in_slot", slot))
	elif _last_weapon_request or Input.is_action_just_pressed("weapon_last"):
		# CS 1.6 lastinv: Q recalls the weapon held before the current one.
		var previous: Variant = actor.get("previous_weapon") if is_instance_valid(actor) else ""
		if previous is String:
			command.weapon = previous
	_last_weapon_request = false
	command.state = "human"
	return command
