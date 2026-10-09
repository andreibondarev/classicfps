extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("DEDICATED SERVER TEST: " + message)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	await process_frame

	var network := root.get_node("NetworkSession")
	_check(network.dedicated_server and network.is_host, "dedicated CLI starts the authoritative host")
	_check(network.listen_port == 27549, "dedicated CLI honors the requested UDP port")
	_check(game._dedicated_server_mode and game.map_name == "de_dust2", "dedicated server is locked to Dust2")
	_check(not game.match_started and game.player.team == Combatant.TEAM_UNASSIGNED,
		"empty headless server waits without consuming a local combatant")
	_check(not game.player.alive and not game.player.visible and game.player.collision_layer == 0,
		"server sentinel is invisible and non-solid")
	_check(game.allied_bots.size() == 5 and game.targets.size() == 5
		and game.round_state.team_counts() == {"T": 5, "CT": 5},
		"all ten remote combat slots begin as replaceable bots")

	for index in range(10):
		var peer_id := 100 + index
		network._register_input_peer(peer_id, Time.get_ticks_msec())
		game.remote_roster._on_peer_joined(peer_id)
		if index == 0:
			_check(game.match_started, "first remote peer starts a fresh match")
		var team := "T" if index % 2 == 0 else "CT"
		var selection: Dictionary = game.select_remote_join_team(peer_id, team)
		_check(bool(selection.get("accepted", false)), "remote slot %d can join %s" % [index + 1, team])
		if bool(selection.get("accepted", false)):
			var appearance: Dictionary = game.select_remote_join_class(peer_id, index % 4 + 1)
			_check(bool(appearance.get("accepted", false)) and bool(appearance.get("spawned", false)),
				"remote slot %d can finish appearance" % (index + 1))

	_check(game.remote_roster.size() == 10 and game._all_bots().is_empty(),
		"ten remote humans replace the complete bot roster")
	_check(game.round_state.team_counts() == {"T": 5, "CT": 5},
		"full dedicated roster remains five-versus-five")

	for index in range(10):
		var peer_id := 100 + index
		network._remove_input_peer(peer_id)
		game.remote_roster._on_peer_left(peer_id)
	await process_frame
	await process_frame
	var reset_game := current_scene
	_check(reset_game != game and is_instance_valid(reset_game),
		"last disconnect rebuilds the dedicated scene")
	if is_instance_valid(reset_game):
		_check(not reset_game.match_started and reset_game._all_bots().size() == 10
			and reset_game.round_state.team_counts() == {"T": 5, "CT": 5},
			"empty server restores its idle five-versus-five bot roster")
		reset_game.queue_free()
	await process_frame
	network.disconnect_session()
	if failures.is_empty():
		print("DEDICATED_SERVER_TEST_PASS")
		quit(0)
	else:
		push_error("DEDICATED SERVER TEST FAILED: %d assertion(s)" % failures.size())
		quit(1)
