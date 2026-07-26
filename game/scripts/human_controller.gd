class_name HumanCombatController
extends CombatController

var _look_delta := Vector2.ZERO


func ingest_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_delta += event.relative


func gather_command(delta: float) -> Dictionary:
	var command := super.gather_command(delta)
	command.movement = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	command.look_delta = _look_delta
	_look_delta = Vector2.ZERO
	command.jump = Input.is_action_just_pressed("jump")
	command.crouch = Input.is_action_pressed("crouch")
	command.fire = Input.is_action_pressed("fire")
	command.fire_pressed = Input.is_action_just_pressed("fire")
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
