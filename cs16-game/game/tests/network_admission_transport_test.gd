extends SceneTree

## Real ENet admission into the host Game. The client exercises production
## requests/replies, not a replicated or independently presented match yet.
var network: Node
var game: Node
var failures: Array[String] = []
var departures: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)


func _wait_for(predicate: Callable, description: String, signal_tick := -1) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	var next_signal := 0
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		if signal_tick >= 0 and Time.get_ticks_msec() >= next_signal:
			# Repeat test milestones over the existing lossy snapshot channel.
			# Action requests and authoritative replies use reliable channel 2.
			network.tick_snapshot(0.05, {"tick": signal_tick, "phase": "freeze", "health": 100})
			next_signal = Time.get_ticks_msec() + 100
		await process_frame
	failures.append("Timed out: " + description)
	return false


func _run() -> void:
	network = root.get_node("NetworkSession")
	var role := ""
	var port := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = argument.trim_prefix("--port=").to_int()
	if role not in ["host", "client"] or port < 1024 or port > 65535 or AudioServer.get_driver_name() != "Dummy":
		push_error("Admission transport fixture requires role, unprivileged port and Dummy audio")
		quit(1)
		return
	network.peer_left.connect(func(peer: int) -> void: departures.append(peer))
	if role == "host":
		await _host(port)
	else:
		await _client(port)
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
		_check(not network._game_action_handler.is_valid(), "Game teardown unbinds action dispatch")
	network.disconnect_session()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_GAME_ADMISSION_", role.to_upper(), "_PASS")
	quit(0 if failures.is_empty() else 1)


func _host(port: int) -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	game.start_match()
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	var host_position: Vector3 = game.player.global_position
	var host_skin: String = game.selected_player_skin
	if network.host_game(port, "127.0.0.1") != OK:
		failures.append("loopback host must start")
		return
	print("NETWORK_TRANSPORT_READY")
	if not await _wait_for(func() -> bool: return network.multiplayer.get_peers().size() == 1, "real peer connects"):
		return
	var peer_id: int = network.multiplayer.get_peers()[0]
	if not await _wait_for(func() -> bool: return int(network._action_peers.get(peer_id, {}).get("sequence", 0)) == 5,
		"client finishes reliable first-admission requests"):
		return
	var human: PlayerController = game.remote_roster.actor_for_peer(peer_id)
	var actor_id: String = game._round_id_for_actor(human)
	var audio_id := human.audio_entity_id()
	_check(human.team == "T" and human.alive and human.visible and human.collision_layer == 2
		and human.character_model.skin_name == "guerilla" and human.active_weapon == "glock18"
		and human.spawn_serial == 1, "real remote requests spawn the selected class once")
	_check(game._all_bots().size() == 8 and game.round_state.team_counts() == {"T": 5, "CT": 5}
		and game.round_state.players[actor_id].money == 800, "wire admission replaces one bot with normal money and capacity")
	_check(game.player.global_position == host_position and game.selected_player_skin == host_skin
		and root.get_camera_3d() == game.player.camera, "spoofed owner and remote class requests leave host identity/view unchanged")
	_check(not human.controls_enabled and human.look_enabled, "spawn during freeze preserves input locks")
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(peer_id).get("buttons", 0)) == 16,
		"admitted peer can still deliver ordinary held input", 10):
		return
	if not await _wait_for(func() -> bool: return departures.has(peer_id), "first admitted peer leaves", 11):
		return
	_check(game.remote_roster.size() == 0 and not game.round_state.players.has(actor_id)
		and not network._action_peers.has(peer_id) and game.player.collision_layer == 4,
		"departure clears admission/action state and restores offline host hit layer")
	if not await _wait_for(func() -> bool: return network.multiplayer.get_peers().size() == 1, "client reconnects"):
		return
	var new_peer: int = network.multiplayer.get_peers()[0]
	if not await _wait_for(func() -> bool: return int(network._action_peers.get(new_peer, {}).get("sequence", 0)) == 2,
		"fresh connection completes a second reliable admission"):
		return
	var replacement: PlayerController = game.remote_roster.actor_for_peer(new_peer)
	_check(game._round_id_for_actor(replacement) != actor_id and replacement.audio_entity_id() == audio_id,
		"reconnect gets a fresh actor identity while reusing the freed slot")
	_check(replacement.alive and replacement.team == "CT" and replacement.character_model.skin_name == "gsg9"
		and replacement.active_weapon == "usp" and replacement.spawn_serial == 1
		and game._all_bots().size() == 7, "reconnect sequence one/two admits a fresh selected class")
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(new_peer).get("buttons", 0)) == 32,
		"reconnected client confirms its authoritative reply", 20):
		return
	print("NETWORK_GAME_ADMISSION map=", game.map_name, " first=", actor_id,
		" second=", game._round_id_for_actor(replacement), " bots=", game._all_bots().size())
	await _wait_for(func() -> bool: return departures.has(new_peer), "second peer leaves", 21)


func _request(action: String, value: Variant, accepted: bool, reason := "") -> Dictionary:
	var sequence: int = network.submit_action(action, value)
	if sequence <= 0 or not await _wait_for(func() -> bool:
		return int(network.latest_action_result.get("sequence", 0)) == sequence, "reply for " + action):
		failures.append("request failed to complete: " + action)
		return {}
	var result: Dictionary = network.latest_action_result.duplicate()
	_check(result.accepted == accepted and result.reason == reason, "authoritative action outcome: " + action + " " + str(value))
	return result


func _client(port: int) -> void:
	if network.join_game("127.0.0.1", port) != OK:
		failures.append("client starts")
		return
	if not await _wait_for(func() -> bool: return network.status.begins_with("CONNECTED"), "first handshake"):
		return
	_check(network.request_join_team("invalid") == 0 and network.request_join_class(0) == 0
		and network._action_sequence == 0 and network._pending_actions.is_empty(),
		"invalid local selections do not reserve or send requests")
	for sequence in network.MAX_PENDING_ACTIONS:
		network._pending_actions[100 + sequence] = {"action": "join_team", "value": "T", "sent_ms": Time.get_ticks_msec()}
	_check(network.request_join_team("T") == 0 and network._action_sequence == 0,
		"bounded pending queue applies local backpressure before allocating another request")
	network._pending_actions.clear()
	network._submit_action.rpc_id(1, [])
	network._submit_action.rpc_id(1, {"version": 1, "sequence": 999, "action": "join_team", "value": "CT", "owner": 1})
	network._submit_action.rpc_id(1, {"version": 1, "sequence": 999, "action": "join_class", "value": true})
	await _request("join_class", 1, false, "invalid_class")
	var joined: Dictionary = await _request("join_team", "T", true)
	if joined.is_empty():
		return
	_check(joined.team == "T" and joined.class_id == 0 and not joined.spawned, "team reply reserves appearance, not a life")
	# Replay does not have a new pending request and must not remove another bot.
	network._submit_action.rpc_id(1, {"version": 1, "sequence": 2, "action": "join_team", "value": "T"})
	# Re-picking the joined side is rejected; switching sides is a separate,
	# allowed request (network_team_switch_test.gd).
	await _request("join_team", "T", false, "already_joined")
	var spawned: Dictionary = await _request("join_class", 4, true)
	_check(spawned.get("actor_id") == joined.actor_id and spawned.get("spawned", false)
		and spawned.get("class_id", 0) == 4, "class reply confirms the same owned actor actually spawned")
	await _request("join_class", 1, false, "not_choosing_class")
	if not await _wait_for(func() -> bool: return int(network.latest_snapshot.get("tick", 0)) == 10, "host validates first body"):
		return
	network.submit_local_input({"buttons": 16})
	if not await _wait_for(func() -> bool: return int(network.latest_snapshot.get("tick", 0)) == 11, "host confirms normal input"):
		return
	network.disconnect_session()
	_check(network._pending_actions.is_empty() and network.latest_action_result.is_empty()
		and network._action_sequence == 0, "disconnect clears client replies, pending requests and sequence")
	await create_timer(0.2).timeout
	if network.join_game("127.0.0.1", port) != OK:
		failures.append("client reconnect starts")
		return
	if not await _wait_for(func() -> bool: return network.status.begins_with("CONNECTED"), "second handshake"):
		return
	var rejoined: Dictionary = await _request("join_team", "CT", true)
	_check(rejoined.get("sequence", 0) == 1 and rejoined.get("actor_id") != joined.actor_id, "new connection replies use fresh identity and counter")
	var respawned: Dictionary = await _request("join_class", 2, true)
	_check(respawned.get("sequence", 0) == 2 and respawned.get("spawned", false), "reconnected class is accepted once")
	if not await _wait_for(func() -> bool: return int(network.latest_snapshot.get("tick", 0)) == 20, "host validates reconnected body"):
		return
	network.submit_local_input({"buttons": 32})
	await _wait_for(func() -> bool: return int(network.latest_snapshot.get("tick", 0)) == 21, "final host acknowledgement")
