extends SceneTree

## Host-side voice relay: routing follows CS 1.6 without alltalk (own team
## only; the living do not hear the dead), and frames are validated and rate
## limited per speaker before any relay. Run with: -- --dedicated --port=<port>

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("NETWORK VOICE: " + message)


func _join(game: Node, network: Node, peer_id: int, team: String) -> PlayerController:
	network._register_input_peer(peer_id, Time.get_ticks_msec())
	game.remote_roster._on_peer_joined(peer_id)
	game.select_remote_join_team(peer_id, team)
	game.select_remote_join_class(peer_id, 1)
	return game._remote_join_actor(peer_id)


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	await process_frame
	var network := root.get_node("NetworkSession")
	_check(network.dedicated_server and network.is_host, "dedicated host is running")

	var speaker := _join(game, network, 501, "T")
	var teammate := _join(game, network, 502, "T")
	var opponent := _join(game, network, 503, "CT")
	for actor: PlayerController in [speaker, teammate, opponent]:
		actor.alive = true
	var route: Dictionary = game._handle_network_voice(501)
	_check(route.get("sender_id") == game._round_id_for_actor(speaker), "route names the speaking actor")
	_check(route.get("recipients") == [502], "only the speaker's living teammates hear them (%s)" % [route.get("recipients")])

	speaker.alive = false
	route = game._handle_network_voice(501)
	_check(route.get("recipients") == [], "the living do not hear a dead speaker")
	teammate.alive = false
	route = game._handle_network_voice(501)
	_check(route.get("recipients") == [502], "dead teammates hear each other")
	speaker.alive = true
	route = game._handle_network_voice(501)
	_check(route.get("recipients") == [502], "a dead teammate still hears the living")
	_check(game._handle_network_voice(999).is_empty(), "unknown peers have no route")

	var frame := PackedByteArray()
	frame.resize(60)
	var now := Time.get_ticks_msec()
	var state: Dictionary = network._voice_peers[501]
	network.accept_peer_voice(501, 1, frame, now)
	_check(int(state.sequence) == 1, "a valid frame is accepted for relay")
	var oversized := PackedByteArray()
	oversized.resize(network.VOICE_MAX_FRAME_BYTES + 1)
	_check(not network.accept_peer_voice(501, 2, oversized, now) and int(state.sequence) == 1, "oversized frames are rejected")
	_check(not network.accept_peer_voice(501, 3, "not bytes", now) and int(state.sequence) == 1, "non-byte frames are rejected")
	_check(not network.accept_peer_voice(501, 1, frame, now) and int(state.sequence) == 1, "replayed sequences are dropped")
	_check(not network.accept_peer_voice(1, 5, frame, now), "the host's own peer cannot inject voice")
	for sequence in range(2, 200):
		network.accept_peer_voice(501, sequence, frame, now)
	_check(float(state.tokens) < 1.0, "a burst exhausts the speaker's voice budget")

	for peer_id in [501, 502, 503]:
		network._remove_input_peer(peer_id)
		game.remote_roster._on_peer_left(peer_id)
	_check(not network._voice_peers.has(501), "leaving clears voice state")
	await process_frame
	await process_frame
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	await process_frame
	network.disconnect_session()
	if failures.is_empty():
		print("GAME_NETWORK_VOICE_PASS")
	quit(0 if failures.is_empty() else 1)
