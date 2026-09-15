extends SceneTree

var failures: Array[String] = []
var network: Node
var received: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _wait_for(check: Callable, description: String, timeout_ms := 10000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if check.call():
			return true
		await process_frame
	failures.append("Timed out: " + description)
	return false


func _run() -> void:
	network = root.get_node("NetworkSession")
	network.chat_received.connect(func(message: Dictionary) -> void: received.append(message))
	var role := ""
	var port := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = argument.trim_prefix("--port=").to_int()
	if role not in ["host", "client"] or port < 1024 or port > 65535 \
			or AudioServer.get_driver_name() != "Dummy":
		failures.append("Chat transport fixture requires host/client role, unprivileged port and Dummy audio")
	elif role == "host":
		await _host(port)
	else:
		await _client(port)
	for failure in failures:
		push_error(failure)
	print("GAME_NETWORK_CHAT_TRANSPORT_%s_%s" % [role.to_upper(), "PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)


func _host(port: int) -> void:
	root.get_node("GameSettings").update_player_name("Chat Host")
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	if network.host_game(port, "127.0.0.1") != OK:
		failures.append("chat host starts")
		return
	print("NETWORK_TRANSPORT_READY")
	if not await _wait_for(func() -> bool: return game.remote_roster.size() == 1,
			"chat client receives an authoritative actor"):
		return
	var peer_id: int = game.remote_roster.peer_ids()[0]
	var remote: PlayerController = game.remote_roster.actor_for_peer(peer_id)
	remote.configure_identity("CT", remote.display_name)
	if not await _wait_for(func() -> bool: return remote.display_name == "Chat Client",
			"client display name reaches chat authority"):
		return
	if not await _wait_for(func() -> bool:
		return received.any(func(message: Dictionary) -> bool: return message.text == "Hello host")
	, "remote all-chat reaches host"):
		return
	_check(not received.any(func(message: Dictionary) -> bool: return message.text == "CT secret"),
		"remote CT team-chat is not delivered to the T host")
	var remote_message: Dictionary = received.filter(
		func(message: Dictionary) -> bool: return message.text == "Hello host"
	)[0]
	_check(remote_message.sender_name == "Chat Client" and remote_message.team == "CT",
		"remote sender name and team come from the host actor")
	_check(network.request_chat("Hello client", false), "host queues all-chat")
	await _wait_for(func() -> bool:
		return received.any(func(message: Dictionary) -> bool: return message.text == "Client ack")
	, "client acknowledges host chat")
	await _wait_for(func() -> bool: return network.multiplayer.get_peers().is_empty(),
		"chat client disconnects", 3000)
	network.disconnect_session()
	game.queue_free()


func _client(port: int) -> void:
	root.get_node("GameSettings").update_player_name("Chat Client")
	if network.join_game("127.0.0.1", port) != OK:
		failures.append("chat client starts")
		return
	if not await _wait_for(func() -> bool: return network.status.begins_with("CONNECTED"),
			"chat client connects"):
		return
	await create_timer(0.3).timeout
	_check(network.request_chat("CT secret", true), "client sends team-chat")
	if not await _wait_for(func() -> bool:
		return received.any(func(message: Dictionary) -> bool: return message.text == "CT secret")
	, "sender receives its own team-chat"):
		return
	_check(network.request_chat("Hello host", false), "client sends all-chat")
	if not await _wait_for(func() -> bool:
		return received.any(func(message: Dictionary) -> bool: return message.text == "Hello client")
	, "host all-chat reaches client"):
		return
	var host_message: Dictionary = received.filter(
		func(message: Dictionary) -> bool: return message.text == "Hello client"
	)[0]
	_check(host_message.sender_name == "Chat Host" and host_message.team == "T",
		"client receives authoritative host identity")
	_check(network.request_chat("Client ack", false), "client acknowledges host message")
	await create_timer(0.2).timeout
	network.disconnect_session()
