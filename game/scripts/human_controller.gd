class_name HumanCombatController
extends CombatController

var _look_delta := Vector2.ZERO
var _fire_held := false
var _fire_pressed := false
var _secondary_pressed := false
# Presses are latched from ingest_input (which sees every event) instead of
# polled with is_action_just_pressed inside the 100 Hz physics tick: on frames
# that run zero physics ticks (e.g. 120 Hz display vs 100 Hz physics) the
# "just pressed" edge expires before any tick can observe it.
var _jump_pressed := false
var _reload_pressed := false
var _drop_pressed := false
var _slot_request := 0
var _last_weapon_request := false


func ingest_input(event: InputEvent) -> void:
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
		# Mouse2 is always the weapon's secondary action, exactly as in CS 1.6.
		# No ctrl+click fire alias: crouch is bound to Ctrl, so aliasing
		# ctrl+RMB to fire made every crouched mode-switch discharge the gun.
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_fire_held = mouse_event.pressed
			if mouse_event.pressed:
				_fire_pressed = true
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_secondary_pressed = true


func gather_command(delta: float) -> Dictionary:
	var command := super.gather_command(delta)
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
	command.fire = Input.is_action_pressed("fire") or _fire_held
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
