extends SceneTree

var network: Node
var game: Node
var failures: Array[String] = []
var map_name := "de_dust2"
var staged_hostage_id := ""


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _wait_for(predicate: Callable, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
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
		elif argument.begins_with("--map="):
			map_name = argument.trim_prefix("--map=")
	if role not in ["host", "client"] or port < 1024 or port > 65535 or AudioServer.get_driver_name() != "Dummy":
		failures.append("roster fixture requires role, unprivileged port and Dummy audio")
	elif role == "host":
		await _host(port)
	else:
		await _client(port)
	network.disconnect_session()
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
		await create_timer(0.2).timeout
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_GAME_ROSTER_", role.to_upper(), "_PASS map=", map_name)
	quit(0 if failures.is_empty() else 1)


func _host(port: int) -> void:
	if network.host_game(port, "127.0.0.1") != OK:
		failures.append("roster loopback host must start")
		return
	print("NETWORK_TRANSPORT_READY")
	if not await _wait_for(func() -> bool: return network.multiplayer.get_peers().size() == 1, "peer connects before Game exists"):
		return
	var first_peer: int = network.multiplayer.get_peers()[0]
	if not await _wait_for(func() -> bool: return network.peer_player_name(first_peer, "") == "Roster Name 1", "name arrives before Game exists"):
		return
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	if not await _wait_for(func() -> bool: return game.combat_effects.presentation_is_ready, "real Game presentation completes"):
		return
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.spectator_camera.set_physics_process(false)
	for bot in game._all_bots():
		bot.set_physics_process(false)
	_check(game.using_imported_map and game.map_name == map_name, "fixture loads the requested real map")
	var roster: Node = game.remote_roster
	var human: PlayerController = roster.actor_for_peer(first_peer)
	if not is_instance_valid(human):
		failures.append("Game must catch up a peer connected before its roster was built")
		return
	var first_id: String = roster.id_for_actor(human)
	_check(human.display_name == "Roster Name 1", "late-created roster adopts cached peer name")
	var first_audio: int = human.audio_entity_id()
	var weak_human: WeakRef = weakref(human)
	var human_origin := human.global_position
	var local_origin: Vector3 = game.player.global_position
	var local_camera := root.get_camera_3d()
	_check(first_id.begins_with("remote_human_") and first_id != str(first_peer), "actor identity is host-assigned, not transport identity")
	_check(roster.size() == 1 and game.round_state.players.size() == 11, "Game tracks one pending human in addition to the offline roster")
	_check(game.round_state.players[first_id].team == "UNASSIGNED"
		and not game.round_state.players[first_id].alive and game.round_state.players[first_id].money == 0,
		"connection alone grants neither a team, life nor spending money")
	_check(human.team == "UNASSIGNED" and not human.alive and not human.visible and human.collision_layer == 0,
		"pending human is hidden and non-solid, not a free extra combatant")
	_check(not human.controls_enabled and not human.look_enabled and not human.is_physics_processing()
		and human.viewmodel == null and not human.character_model.model_loaded,
		"pending human has no local input/presentation allocation or active simulation")
	_check(game.hud.scoreboard_rows.get_node("Team0Section").get_child(0).text.contains("1 player"),
		"pending human appears in the spectators section, not the T roster")
	_check(game.hud.scoreboard_rows.has_node("Player_" + first_id), "pending human is represented on the actual scoreboard")
	human.name = "RenamedPendingHuman"
	_check(game._round_id_for_actor(human) == first_id and game._actor_for_round_id(first_id) == human,
		"actor lookup survives scene-node renaming")
	_check(game._round_actor_positions().has(first_id), "world actor positions use the durable identity")
	roster._on_peer_joined(1)
	roster._on_peer_joined(999999)
	roster._on_peer_joined(first_peer)
	roster._on_peer_left(first_peer)
	_check(roster.size() == 1, "local, unknown and duplicate peer notifications cannot allocate another human")
	if not await _wait_for(func() -> bool: return not network.input_for_peer(first_peer).is_empty(), "real remote held input arrives"):
		return
	for tick in 10:
		await physics_frame
	_check(human.global_position == human_origin and human._shot_sequence == 0
		and game.player.global_position == local_origin and root.get_camera_3d() == local_camera,
		"pending movement/fire packets cannot move a pawn, shoot or steal the camera")
	game.start_match()
	game._reset_round()
	game._restart_match()
	_check(roster.id_for_actor(human) == first_id and game.round_state.players.has(first_id)
		and not game.round_state.players[first_id].alive and not human.is_physics_processing(),
		"pending connection survives round reset and rematch without being spawned into combat")
	_check(root.get_camera_3d() == game.player.camera, "normal match start retains local camera ownership")
	# Staged sound events let departure exercise the real Game's channel cleanup
	# without pretending that an unassigned human can fire a weapon.
	var remote_voice := human._emit_audio("glock18.fire", 2)
	var local_voice: int = game.player._emit_audio("glock18.fire", 2)
	_check(remote_voice > 0 and local_voice > 0, "independent staged voices exist before departure")
	_stage_departure_objective(first_id, human)
	_send_stage(1)
	if not await _wait_for(func() -> bool: return roster.size() == 0, "client departure clears the Game roster"):
		return
	await process_frame
	_check(weak_human.get_ref() == null and not game.round_state.players.has(first_id)
		and game._actor_for_round_id(first_id) == null and not game.bomb_knowledge._actors.has(first_id),
		"departed node, round row, identity lookup and knowledge entry are removed")
	var voices: Array = game.audio_router.active_voices()
	_check(not voices.any(func(voice: Dictionary) -> bool: return int(voice.voice_id) == remote_voice)
		and voices.any(func(voice: Dictionary) -> bool: return int(voice.voice_id) == local_voice),
		"departure stops only the remote actor's active channels")
	_check(not game.hud.scoreboard_rows.has_node("Player_" + first_id), "departed scoreboard row is removed")
	_check_departure_objective(first_id)
	_check(game.round_state.trace.filter(func(event: Dictionary) -> bool:
		return event.type == "player_death" and str(event.player_id) == first_id).is_empty(),
		"transport departure is not reported as a kill")
	if not await _wait_for(func() -> bool: return roster.size() == 1, "reconnected client is allocated a fresh human"):
		return
	var second_id: String = roster.actor_ids()[0]
	var replacement: PlayerController = roster.actor_for_id(second_id)
	if not await _wait_for(func() -> bool: return replacement.display_name == "Roster Name 2", "reconnection sends saved name to fresh actor"):
		return
	_check(second_id != first_id and replacement.audio_entity_id() == first_audio,
		"reconnect gets a new durable ID while safely reusing the released slot")
	_check(game.round_state.players.size() == 11 and game.round_state.players[second_id].money == 0,
		"reconnect cannot inherit departed account state or duplicate a roster row")
	_send_stage(2)
	if not await _wait_for(func() -> bool:
		var peers: PackedInt32Array = network.multiplayer.get_peers()
		return peers.size() == 1 and int(network.input_for_peer(peers[0]).get("buttons", 0)) == 32,
		"reconnected client acknowledges final roster stage"):
		return
	network.disconnect_session()
	_check(roster.size() == 0 and not game.round_state.players.has(second_id),
		"host shutdown clears humans without relying on per-peer departure callbacks")
	_check(network.host_game(port, "127.0.0.1") == OK, "host can restart its transport with the same Game")
	if not await _wait_for(func() -> bool: return roster.size() == 1, "third connection after host restart"):
		return
	var third_id: String = roster.actor_ids()[0]
	_check(third_id not in [first_id, second_id], "host restart does not recycle historical actor IDs")
	_send_stage(3)
	if not await _wait_for(func() -> bool:
		var peers: PackedInt32Array = network.multiplayer.get_peers()
		return peers.size() == 1 and int(network.input_for_peer(peers[0]).get("buttons", 0)) == 32,
		"client acknowledges scene-teardown stage"):
		return
	var weak_game: WeakRef = weakref(game)
	var weak_roster: WeakRef = weakref(roster)
	var weak_third: WeakRef = weakref(roster.actor_for_id(third_id))
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	_check(weak_game.get_ref() == null and weak_roster.get_ref() == null and weak_third.get_ref() == null,
		"scene teardown frees the roster and its connected human without orphan nodes")
	_check(network.is_host and network.multiplayer.get_peers().size() == 1,
		"scene-owned cleanup does not silently close the separately owned transport")
	network.disconnect_session()
	print("NETWORK_GAME_ROSTER map=", map_name, " old_id=", first_id, " new_id=", second_id,
		" restarted_id=", third_id, " slot_audio=", first_audio, " scene_teardown_verified=true")


func _send_stage(tick: int) -> void:
	network.tick_snapshot(0.05, {"tick": tick, "position": Vector3.ZERO,
		"velocity": Vector3.ZERO, "health": 100, "phase": "freeze", "round_time": 6.0})


func _stage_departure_objective(actor_id: String, human: PlayerController) -> void:
	# Deliberately staged objective ownership tests cleanup only. This is NOT
	# team admission, human traversal, a gameplay C4 pickup or hostage use proof.
	if map_name == "de_dust2":
		var prior_owner: String = game.round_state.bomb_owner
		_check(game.round_state.drop_bomb(prior_owner, game.player.global_position), "stage releases the original C4 owner")
		game.round_state.players[actor_id].team = "T"
		game.round_state.players[actor_id].alive = true
		human.configure_identity("T", human.display_name)
		_check(game.round_state.pickup_bomb(actor_id, human.global_position), "stage assigns C4 through round rules")
		game._consume_new_round_trace()
		game._sync_round_public_state()
	else:
		staged_hostage_id = str(game.hostage_state.hostages.keys()[0])
		_check(not game.hostage_state.use_hostage(staged_hostage_id, actor_id, "CT", true).is_empty(),
			"stage assigns a hostage leader through the hostage contract")
		game._hostage_paths[staged_hostage_id] = PackedVector3Array([Vector3.ONE])
		game._hostage_path_indices[staged_hostage_id] = 0
		game._hostage_path_targets[staged_hostage_id] = Vector3.ONE
		game._sync_hostage_actors()


func _check_departure_objective(actor_id: String) -> void:
	if map_name == "de_dust2":
		_check(game.round_state.bomb_owner.is_empty() and game.round_state.bomb_state == "dropped"
			and is_instance_valid(game.dropped_c4), "real peer departure creates the Game's dropped C4 world actor")
		_check(game.round_state.trace.filter(func(event: Dictionary) -> bool:
			return event.type == "bomb_dropped" and str(event.player_id) == actor_id).size() == 1,
			"departure consumes one C4 drop event without duplicate world drops")
	else:
		var hostage: Dictionary = game.hostage_state.hostages[staged_hostage_id]
		_check(not hostage.following and str(hostage.leader_id).is_empty()
			and not game._hostage_paths.has(staged_hostage_id)
			and not game._hostage_path_indices.has(staged_hostage_id)
			and not game._hostage_path_targets.has(staged_hostage_id)
			and game.hostage_actors[staged_hostage_id].leader_id.is_empty(),
			"real peer departure releases hostage leadership and stale navigation state")


func _client(port: int) -> void:
	var client_roster := preload("res://scripts/remote_human_roster.gd").new()
	root.add_child(client_roster)
	client_roster.bind_session(network)
	for stage in [1, 2, 3]:
		root.get_node("GameSettings").update_player_name("Roster Name %d" % stage)
		if network.join_game("127.0.0.1", port) != OK:
			failures.append("roster client must connect")
			return
		if not await _wait_for(func() -> bool: return network.status.begins_with("CONNECTED"), "client connects"):
			return
		client_roster._on_peer_joined(1)
		client_roster._on_peer_joined(1234)
		_check(client_roster.size() == 0, "a client cannot allocate authoritative humans")
		var deadline := Time.get_ticks_msec() + 20000
		while int(network.latest_snapshot.get("tick", 0)) != stage and Time.get_ticks_msec() < deadline:
			network.submit_local_input({"movement": Vector2.RIGHT, "yaw": 0.7, "pitch": -0.2, "buttons": 1})
			await physics_frame
		if int(network.latest_snapshot.get("tick", 0)) != stage:
			failures.append("Timed out: Game roster stage %d" % stage)
			return
		if stage == 1:
			network.disconnect_session()
			# Allow the first transport's reliable disconnect to be observed before
			# opening another connection. This is test control, not simulated latency.
			await create_timer(0.2).timeout
		else:
			deadline = Time.get_ticks_msec() + 12000
			while network.is_online() and Time.get_ticks_msec() < deadline:
				network.submit_local_input({"buttons": 32})
				await physics_frame
			_check(not network.is_online(), "host shutdown reaches the real client")
			if stage == 2:
				await create_timer(0.2).timeout
