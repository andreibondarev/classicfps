class_name HumanCombatController
extends CombatController

var _look_delta := Vector2.ZERO
var _fire_held := false
var _fire_pressed := false
var _control_click_fire := false
var _secondary_pressed := false


func ingest_input(event: InputEvent) -> void:
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
		var is_left_fire := mouse_event.button_index == MOUSE_BUTTON_LEFT
		var is_control_click := (
			mouse_event.button_index == MOUSE_BUTTON_RIGHT
			and (mouse_event.ctrl_pressed or _control_click_fire)
		)
		if is_left_fire or is_control_click:
			_fire_held = mouse_event.pressed
			if mouse_event.pressed:
				_fire_pressed = true
			if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				_control_click_fire = mouse_event.pressed
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_secondary_pressed = true


func gather_command(delta: float) -> Dictionary:
	var command := super.gather_command(delta)
	command.movement = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	command.look_delta = _look_delta
	_look_delta = Vector2.ZERO
	command.jump = Input.is_action_just_pressed("jump")
	command.crouch = Input.is_action_pressed("crouch")
	command.walk = Input.is_action_pressed("walk")
	command.fire = Input.is_action_pressed("fire") or _fire_held
	command.fire_pressed = Input.is_action_just_pressed("fire") or _fire_pressed
	command.secondary_pressed = _secondary_pressed
	_fire_pressed = false
	_secondary_pressed = false
	command.reload = Input.is_action_just_pressed("reload")
	command.use = Input.is_action_pressed("use")
	if Input.is_action_just_pressed("weapon_primary"):
		command.weapon = "ak47"
	elif Input.is_action_just_pressed("weapon_secondary"):
		command.weapon = "deagle"
	elif Input.is_action_just_pressed("weapon_melee"):
		command.weapon = "knife"
	elif Input.is_action_just_pressed("weapon_grenade"):
		command.weapon = "hegrenade"
	command.state = "human"
	return command
