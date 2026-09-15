extends SceneTree

var game: Node
var network: Node
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _click(button: Button) -> void:
	_check(button.is_visible_in_tree() and not button.disabled, "clicked control is visible and enabled: " + str(button.name))
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = point
		root.push_input(event, true)


func _escape() -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = down
		root.push_input(event, true)


func _ready_game() -> void:
	await process_frame
	await physics_frame
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready


func _wait_for_offline_scene(previous_id: int) -> void:
	while not is_instance_valid(current_scene) or current_scene.get_instance_id() == previous_id:
		await process_frame
	game = current_scene
	await _ready_game()
	_check(not game._network_client_mode and not game.player.network_read_only and not network.is_online()
		and not paused and game._all_bots().size() == 9 and game.hud.deploy_overlay.visible,
		"return offline rebuilds authority, AI, controls and team menu together")


func _run() -> void:
	create_timer(40.0, true).timeout.connect(func() -> void:
		push_error("Network menu fixture deadline")
		quit(1)
	)
	_check(AudioServer.get_driver_name() == "Dummy", "menu fixture is silent")
	network = root.get_node("NetworkSession")
	for address: String in ["127.0.0.1", "::1", "localhost", "game.example", "my-pc.local"]:
		_check(network.connection_endpoint(address, "27447").valid, "valid direct endpoint " + address)
	for address: String in ["", "http://localhost", "localhost:27447", "host name", "-host", "host-", "a..b", "x/../y", "a".repeat(254)]:
		_check(not network.connection_endpoint(address, "27447").valid, "reject malformed address " + address)
	for port: String in ["", "0", "1023", "65536", "123456", "-1234", "+1234", "12.34", " 27447", "27x47"]:
		_check(not network.connection_endpoint("127.0.0.1", port).valid, "reject malformed port " + port)
	_check(network.connection_endpoint(" 127.0.0.1 ", "65535").address == "127.0.0.1", "trim address without truncating content")
	var reservation := PacketPeerUDP.new()
	_check(reservation.bind(0, "127.0.0.1") == OK, "reserve an isolated local port")
	var port := reservation.get_local_port()
	reservation.close()
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await _ready_game()
	_escape()
	_check(paused and game._pause_menu_open(), "Escape reaches game menu before deployment")
	_click(game.hud.pause_main_menu.get_node("GameMenu_servers"))
	_check(game.hud.current_input_contract().state == "network" and game.player.combat_controller.menu_input_blocked,
		"direct connection form isolates gameplay input")
	game.hud.network_port.text = "0"
	_click(game.hud.network_connect_button)
	_check(not network.is_online() and game.hud.network_status.text.contains("1024"), "invalid form does not create a session")
	game.hud.network_port.text = str(port)
	for attempt in range(2):
		_click(game.hud.network_connect_button)
		_check(network.is_online() and game._network_client_mode and game.player.network_read_only
			and game._all_bots().is_empty() and not paused, "join/retry enters read-only client without offline AI")
		_check(not network._expire_connection(network._connection_deadline_ms - 1), "connection deadline cannot expire early")
		_check(network._expire_connection(network._connection_deadline_ms), "connection deadline closes stalled attempt")
		_check(not network.is_online() and game.hud.network_menu.is_visible_in_tree()
			and not game.hud.network_connect_button.disabled and game.hud.network_status.text == "CONNECTION TIMED OUT"
			and game.hud.network_port.text == str(port), "timeout preserves form for retry and reports failure")
	_click(game.hud.network_connect_button)
	network._connection_deadline_ms = 0  # Stage a transport that never supplies its world.
	game._network_menu_deadline_ms = 0
	game._physics_process(0.0)
	_check(network.status == "HOST WORLD TIMED OUT" and not network.is_online(), "missing world is bounded separately from ENet connect")
	game.hud.network_address.text = "localhost"
	_click(game.hud.network_connect_button)
	var query: int = network._resolver_id
	_check(query != IP.RESOLVER_INVALID_ID and network.is_connecting() and game.hud.network_connect_button.disabled,
		"hostname resolution is queued without blocking the form or permitting duplicate joins")
	_check(network._expire_connection(network._connection_deadline_ms) and network._resolver_id == IP.RESOLVER_INVALID_ID,
		"connection deadline also removes a pending DNS query")
	_click(game.hud.network_connect_button)
	_check(network._resolver_id != IP.RESOLVER_INVALID_ID, "hostname lookup can be retried")
	var old_id: int = game.get_instance_id()
	_click(game.hud.network_menu.get_node("Offline"))
	_check(network._resolver_id == IP.RESOLVER_INVALID_ID and not network.is_connecting(), "Return Offline cancels DNS and its deadline")
	await _wait_for_offline_scene(old_id)
	_escape()
	_click(game.hud.pause_main_menu.get_node("GameMenu_new_game"))
	game.hud.network_port.text = str(port)
	_click(game.hud.network_connect_button)
	_check(network.is_online() and network.is_host and not paused and game.hud.network_connect_button.disabled,
		"Host Dust2 starts actual ENet and disables duplicate starts")
	var peer: MultiplayerPeer = network.multiplayer.multiplayer_peer
	game._on_network_connection_requested("join", "127.0.0.1", str(port))
	_check(network.multiplayer.multiplayer_peer == peer and network.is_host, "repeated action cannot replace a live session")
	_click(game.hud.network_menu.get_node("Back"))
	_click(game.hud.pause_main_menu.get_node("GameMenu_resume"))
	_check(game.hud.current_input_contract().state == "team" and game.hud.deploy_overlay.visible,
		"resume before deployment restores team menu keyboard contract")
	_escape()
	old_id = game.get_instance_id()
	_click(game.hud.pause_main_menu.get_node("GameMenu_disconnect"))
	await _wait_for_offline_scene(old_id)
	game.queue_free()
	await process_frame
	network.disconnect_session()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_MENU_PASS")
	quit(0 if failures.is_empty() else 1)
