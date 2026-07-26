extends Node

signal status_changed(status: String)
signal snapshot_received(snapshot: Dictionary)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const DEFAULT_PORT := 27447
const MAX_CLIENTS := 10
const SNAPSHOT_HZ := 20.0
const MAX_INPUT_DISTANCE := 12.0
const ALLOWED_INPUT_BUTTONS := 0x3F

var status := "OFFLINE"
var is_host := false
var latest_inputs: Dictionary = {}
var latest_snapshot: Dictionary = {}
var _input_sequence := 0
var _snapshot_accumulator := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(func(peer_id: int) -> void:
		peer_joined.emit(peer_id)
	)
	multiplayer.peer_disconnected.connect(func(peer_id: int) -> void:
		latest_inputs.erase(peer_id)
		peer_left.emit(peer_id)
	)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _set_status("CONNECTION FAILED"))
	multiplayer.server_disconnected.connect(func() -> void:
		disconnect_session()
		_set_status("SERVER DISCONNECTED")
	)
	_start_from_command_line()


func _start_from_command_line() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--host":
			host_game()
		elif argument.begins_with("--join="):
			join_game(argument.trim_prefix("--join="))


func host_game(port := DEFAULT_PORT) -> Error:
	disconnect_session()
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port, MAX_CLIENTS, 3)
	if result != OK:
		_set_status("HOST FAILED")
		return result
	multiplayer.multiplayer_peer = peer
	is_host = true
	_set_status("HOST  :%d" % port)
	return OK


func join_game(address := "127.0.0.1", port := DEFAULT_PORT) -> Error:
	disconnect_session()
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address, port, 3)
	if result != OK:
		_set_status("JOIN FAILED")
		return result
	multiplayer.multiplayer_peer = peer
	is_host = false
	_set_status("CONNECTING  %s:%d" % [address, port])
	return OK


func disconnect_session() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	latest_inputs.clear()
	latest_snapshot.clear()
	_set_status("OFFLINE")


func _on_connected() -> void:
	_set_status("CONNECTED  #%d" % multiplayer.get_unique_id())


func _set_status(value: String) -> void:
	status = value
	status_changed.emit(status)


func is_online() -> bool:
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func submit_local_input(command: Dictionary) -> void:
	_input_sequence += 1
	var sanitized := sanitize_input(command, _input_sequence)
	if is_host:
		latest_inputs[1] = sanitized
	elif is_online():
		_submit_input.rpc_id(1, sanitized)


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _submit_input(command: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	latest_inputs[sender] = sanitize_input(command, int(command.get("sequence", 0)))


func sanitize_input(command: Dictionary, sequence: int) -> Dictionary:
	var movement: Vector2 = command.get("movement", Vector2.ZERO)
	if not movement.is_finite():
		movement = Vector2.ZERO
	return {
		"sequence": maxi(0, sequence),
		"movement": movement.limit_length(1.0),
		"yaw": wrapf(float(command.get("yaw", 0.0)), -PI, PI),
		"pitch": clampf(float(command.get("pitch", 0.0)), -PI * 0.495, PI * 0.495),
		"buttons": int(command.get("buttons", 0)) & ALLOWED_INPUT_BUTTONS,
	}


func tick_snapshot(delta: float, authoritative_state: Dictionary) -> void:
	if not is_host:
		return
	_snapshot_accumulator += delta
	if _snapshot_accumulator < 1.0 / SNAPSHOT_HZ:
		return
	_snapshot_accumulator = fmod(_snapshot_accumulator, 1.0 / SNAPSHOT_HZ)
	var snapshot := sanitize_snapshot(authoritative_state)
	latest_snapshot = snapshot
	_receive_snapshot.rpc(snapshot)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_snapshot(snapshot: Dictionary) -> void:
	latest_snapshot = sanitize_snapshot(snapshot)
	snapshot_received.emit(latest_snapshot)


func sanitize_snapshot(snapshot: Dictionary) -> Dictionary:
	var position: Vector3 = snapshot.get("position", Vector3.ZERO)
	var velocity: Vector3 = snapshot.get("velocity", Vector3.ZERO)
	if not position.is_finite():
		position = Vector3.ZERO
	if not velocity.is_finite():
		velocity = Vector3.ZERO
	return {
		"tick": maxi(0, int(snapshot.get("tick", 0))),
		"position": position,
		"velocity": velocity.limit_length(MAX_INPUT_DISTANCE),
		"health": clampi(int(snapshot.get("health", 100)), 0, 100),
		"phase": str(snapshot.get("phase", "live")),
		"round_time": maxf(0.0, float(snapshot.get("round_time", 0.0))),
	}
