extends CombatController

## Server-side input adapter for a human pawn, never bot movement/aim logic.
## Version-one held input only: reliable discrete actions and roster lifecycle
## are separate work. Binding is an explicit host ownership decision.
var _session: Node
var _peer_id := 0
var _last_sequence := 0
var _last_buttons := 0


func bind_input(session: Node, peer_id: int) -> bool:
	unbind_input()
	if not is_instance_valid(session) or not session.is_host or peer_id <= 1 or not session.has_input_peer(peer_id):
		return false
	_session = session
	_peer_id = peer_id
	_session.peer_left.connect(_on_peer_left)
	_session.status_changed.connect(_on_status_changed)
	return true


func unbind_input() -> void:
	if is_instance_valid(_session):
		if _session.peer_left.is_connected(_on_peer_left):
			_session.peer_left.disconnect(_on_peer_left)
		if _session.status_changed.is_connected(_on_status_changed):
			_session.status_changed.disconnect(_on_status_changed)
	_session = null
	_peer_id = 0
	_last_sequence = 0
	_last_buttons = 0


func _exit_tree() -> void:
	unbind_input()


func _on_peer_left(peer_id: int) -> void:
	if peer_id == _peer_id:
		unbind_input()


func _on_status_changed(_status: String) -> void:
	if not is_instance_valid(_session) or not _session.is_host:
		unbind_input()


func gather_command(delta: float) -> Dictionary:
	var command := super.gather_command(delta)
	if not is_instance_valid(_session) or not _session.is_host:
		return command
	var packet: Dictionary = _session.input_for_peer(_peer_id)
	if packet.is_empty() or int(packet.sequence) < _last_sequence:
		_last_buttons = 0
		return command
	var buttons := int(packet.buttons)
	command.movement = packet.movement
	# Base yaw/pitch radians, without local sensitivity, inversion or recoil.
	command["view_angles"] = Vector2(packet.yaw, packet.pitch)
	command.fire = (buttons & 1) != 0
	command.fire_pressed = command.fire and (_last_buttons & 1) == 0
	command.jump = (buttons & 2) != 0
	command.crouch = (buttons & 4) != 0
	command.reload = (buttons & 8) != 0 and int(packet.sequence) > _last_sequence
	command.use = (buttons & 16) != 0
	command.walk = (buttons & 32) != 0
	command.state = "network_human"
	_last_sequence = int(packet.sequence)
	_last_buttons = buttons
	return command
