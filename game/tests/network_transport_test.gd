extends SceneTree

var network: Node
var failures: Array[String] = []
var departures: Array[int] = []
var human_mode := false
var human_world: Node3D
var human: PlayerController
var human_controller: CombatController
var local_human: PlayerController
var local_human_origin := Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	network = root.get_node("NetworkSession")
	var role := ""
	var port := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = argument.trim_prefix("--port=").to_int()
		elif argument == "--human-simulation":
			human_mode = true
	if role not in ["host", "client"] or port < 1024 or port > 65535 or AudioServer.get_driver_name() != "Dummy":
		push_error("Network fixture requires host/client role, unprivileged port and Dummy audio")
		quit(1)
		return
	network.peer_left.connect(func(id: int) -> void: departures.append(id))
	if human_mode and role == "host":
		await _human_host(port)
	elif human_mode:
		await _human_client(port)
	elif role == "host":
		await _host(port)
	else:
		await _client(port)
	network.disconnect_session()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_", "HUMAN_SIMULATION_" if human_mode else "TRANSPORT_", role.to_upper(), "_PASS")
	quit(0 if failures.is_empty() else 1)


func _wait_for(predicate: Callable, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	failures.append("Timed out: " + description)
	return false


func _host(port: int) -> void:
	if network.host_game(port, "127.0.0.1") != OK:
		failures.append("loopback host must start")
		return
	# The host's own catch-up input must use the same canonical storage without
	# being dropped by the remote-peer rate limiter.
	for index in 40:
		network.submit_local_input({"buttons": 32})
	if int(network.latest_inputs.get(1, {}).get("sequence", 0)) != 40 or network.latest_inputs[1].buttons != 32:
		failures.append("host-local input must be accepted under host ownership")
	print("NETWORK_TRANSPORT_READY")
	if not await _wait_for(func() -> bool: return network.multiplayer.get_peers().size() == 1, "first peer joins"):
		return
	var peer_id: int = network.multiplayer.get_peers()[0]
	if not await _wait_for(func() -> bool: return int(network.latest_inputs.get(peer_id, {}).get("sequence", 0)) == 2, "valid input follows malformed packets"):
		return
	var input: Dictionary = network.latest_inputs[peer_id]
	if input.buttons != 63 or not (input.movement as Vector2).is_equal_approx(Vector2(0.6, 0.8)) or not network.latest_inputs.keys().all(func(id: int) -> bool: return id == 1 or id == peer_id):
		failures.append("remote input must use transport ownership and canonical local normalization")
	if network.latest_inputs.has(1) and network.latest_inputs[1].buttons != 32:
		failures.append("remote claimed-owner packet must not overwrite host input")
	var snapshot := {"tick": 10, "position": Vector3(1, 2, 3), "velocity": Vector3(2, 0, 0), "health": 80, "phase": "live", "round_time": 30.0}
	network.tick_snapshot(0.05, snapshot)
	var malformed: Dictionary = network.sanitize_snapshot(snapshot)
	malformed.tick = 999
	malformed.round_time = INF
	network._receive_snapshot.rpc_id(peer_id, malformed)
	network._receive_snapshot.rpc_id(peer_id, network.sanitize_snapshot(snapshot))
	snapshot.tick = 9
	network._receive_snapshot.rpc_id(peer_id, network.sanitize_snapshot(snapshot))
	snapshot.tick = 11
	snapshot.health = 81
	network.tick_snapshot(0.05, snapshot)
	if not await _wait_for(func() -> bool: return int(network.latest_inputs.get(peer_id, {}).get("sequence", 0)) == 3, "client acknowledges snapshot with held-fire input"):
		return
	if not await _wait_for(func() -> bool: return not network.latest_inputs.has(peer_id), "physics polling expires silent held input"):
		return
	if network.multiplayer.get_peers().size() != 1:
		failures.append("input expiry must not require disconnecting the peer")
	snapshot.tick = 12
	network.tick_snapshot(0.05, snapshot)
	if not await _wait_for(func() -> bool: return departures.has(peer_id), "first connection departs"):
		return
	if network.latest_inputs.has(peer_id) or network._input_peers.has(peer_id):
		failures.append("peer departure must clear held input and replay history")
	if not await _wait_for(func() -> bool: return network.multiplayer.get_peers().size() == 1, "client reconnects"):
		return
	var rejoined: int = network.multiplayer.get_peers()[0]
	if not await _wait_for(func() -> bool: return int(network.latest_inputs.get(rejoined, {}).get("sequence", 0)) == 1, "fresh connection sequence starts at one"):
		return
	snapshot.tick = 1
	network.tick_snapshot(0.05, snapshot)
	if not await _wait_for(func() -> bool: return int(network.latest_inputs.get(rejoined, {}).get("sequence", 0)) == 2, "reconnected client acknowledges restarted snapshot sequence"):
		return
	# Confirm the final acknowledgement before the client closes its peer.
	snapshot.tick = 2
	network.tick_snapshot(0.05, snapshot)
	await _wait_for(func() -> bool: return network.multiplayer.get_peers().is_empty(), "reconnected peer departs")


func _client(port: int) -> void:
	if network.join_game("127.0.0.1", port) != OK:
		failures.append("loopback client must start")
		return
	if not await _wait_for(func() -> bool: return network.status.begins_with("CONNECTED"), "client connects"):
		return
	var command := {"movement": Vector2(3, 4), "yaw": 0.5, "pitch": -0.2, "buttons": 255}
	network._submit_input.rpc_id(1, [])
	var malformed: Dictionary = network.sanitize_input(command, 999)
	malformed.yaw = NAN
	network._submit_input.rpc_id(1, malformed)
	malformed = network.sanitize_input(command, 1000)
	malformed.owner = 1
	network._submit_input.rpc_id(1, malformed)
	network.submit_local_input(command)
	network._submit_input.rpc_id(1, network.sanitize_input(command, 1))
	network.submit_local_input(command)
	if not await _wait_for(func() -> bool: return int(network.latest_snapshot.get("tick", -1)) == 11, "ordered valid snapshot survives malformed and replayed packets"):
		return
	if network.latest_snapshot.health != 81:
		failures.append("client must retain the accepted authoritative snapshot")
	network.submit_local_input({"buttons": 1})
	if not await _wait_for(func() -> bool: return int(network.latest_snapshot.get("tick", -1)) == 12, "server confirms input expiry"):
		return
	network.disconnect_session()
	var reconnect_at := Time.get_ticks_msec() + 150
	await _wait_for(func() -> bool: return Time.get_ticks_msec() >= reconnect_at, "short reconnect separation")
	if network.join_game("127.0.0.1", port) != OK:
		failures.append("loopback client must reconnect")
		return
	if not await _wait_for(func() -> bool: return network.status.begins_with("CONNECTED"), "reconnected client handshake"):
		return
	network.submit_local_input({"buttons": 2})
	if not await _wait_for(func() -> bool: return int(network.latest_snapshot.get("tick", -1)) == 1, "client accepts new session snapshot tick one"):
		return
	network.submit_local_input({"buttons": 0})
	await _wait_for(func() -> bool: return int(network.latest_snapshot.get("tick", -1)) == 2, "final acknowledgement")


func _human_host(port: int) -> void:
	if network.host_game(port, "127.0.0.1") != OK:
		failures.append("human simulation loopback host must start")
		return
	human_world = Node3D.new()
	root.add_child(human_world)
	current_scene = human_world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.1, 20)
	floor_shape.shape = box
	floor_body.position.y = -0.05
	floor_body.add_child(floor_shape)
	human_world.add_child(floor_body)
	local_human = load("res://scripts/player.gd").new()
	local_human.configure_identity("CT", "Host Human")
	human_world.add_child(local_human)
	local_human.reset_player(Vector3(5, 0, 0), false)
	local_human_origin = local_human.global_position
	human = load("res://scripts/player.gd").new()
	if not human.configure_remote_human(2):
		failures.append("host-assigned remote slot must configure before spawn")
	human.configure_identity("T", "Remote Human")
	human_world.add_child(human)
	human.reset_player(Vector3.ZERO, false)
	human.controls_enabled = false
	human.look_enabled = true
	human_controller = human.combat_controller
	if root.get_camera_3d() != local_human.camera or human.viewmodel != null or not human.character_model.model_loaded:
		failures.append("remote spawns with world presentation while the host retains its camera")
	human.combat_effects.warm_up_presentation.call_deferred(local_human.camera)
	if not human.combat_effects.presentation_is_ready:
		await human.combat_effects.presentation_ready
	print("NETWORK_TRANSPORT_READY")
	if await _wait_for(func() -> bool: return network.multiplayer.get_peers().size() == 1, "human input peer joins"):
		var peer_id: int = network.multiplayer.get_peers()[0]
		if human_controller.bind_input(network, peer_id):
			await _human_scenario(peer_id)
		else:
			failures.append("human ownership binding must succeed")
	human_world.queue_free()
	await process_frame
	await create_timer(0.2).timeout


func _human_snapshot(tick: int, snapshot_phase := "live") -> void:
	network.tick_snapshot(0.05, {"tick": tick, "position": human.global_position,
		"velocity": human.velocity, "health": human.health, "phase": snapshot_phase, "round_time": 30.0})


func _human_scenario(peer_id: int) -> void:
	var origin := human.global_position
	var initial_clip := human.clip
	_human_snapshot(10, "freeze")
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(peer_id).get("buttons", 0)) == 1, "remote freeze input arrives"):
		return
	for tick in 20:
		await physics_frame
	if human.global_position != origin or human._shot_sequence != 0 or human.clip != initial_clip:
		failures.append("remote input must respect human freeze movement/attack locks")
	if not human.input_view_angles().is_equal_approx(Vector2(0.7, -0.2)):
		failures.append("remote look must still work during freeze")
	_human_snapshot(20, "freeze")
	if not await _wait_for(func() -> bool:
		var command: Dictionary = network.input_for_peer(peer_id)
		return command.has("buttons") and command.buttons == 0 and command.yaw == 0.0,
		"remote releases fire before unfreezing"):
		return
	human.controls_enabled = true
	_human_snapshot(30)
	if not await _wait_for(func() -> bool: return human.global_position.x - origin.x > 0.6, "remote input physically moves human pawn"):
		return
	var release_request_position := human.global_position
	var release_request_ms := Time.get_ticks_msec()
	_human_snapshot(40)
	if not await _wait_for(func() -> bool:
		return network.input_for_peer(peer_id).get("movement", Vector2.RIGHT) == Vector2.ZERO,
		"remote release packet reaches the host"):
		return
	var release_position := human.global_position
	var release_delay_ms := Time.get_ticks_msec() - release_request_ms
	if not await _wait_for(func() -> bool:
		return (network.input_for_peer(peer_id).get("movement", Vector2.RIGHT) == Vector2.ZERO
			and absf(human.velocity.x) < 0.01), "remote release stops through human friction"):
		return
	if human.global_position.distance_to(origin) > 1.5 or absf(human.global_position.y - origin.y) > 0.05:
		failures.append("remote movement must remain bounded and grounded")
	print("NETWORK_HUMAN_RELEASE requested_x=", release_request_position.x - origin.x,
		" received_x=", release_position.x - origin.x, " delay_ms=", release_delay_ms,
		" friction_distance=", human.global_position.distance_to(release_position),
		" final_distance=", human.global_position.distance_to(origin))
	_human_snapshot(50)
	# Only the target is staged. The human arrives here through the production
	# hull/movement kernel, not a received transform or a test teleport.
	var victim := Combatant.new()
	victim.configure_identity("CT", "Network Target")
	victim.position = human.global_position + Vector3(0, 0, -3)
	victim.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.32, 0.72, 0.32)
	shape.shape = box
	shape.position.y = 0.36
	victim.add_child(shape)
	human_world.add_child(victim)
	await physics_frame
	_human_snapshot(60)
	if not await _wait_for(func() -> bool: return human._shot_sequence > 0, "remote input fires the actual human weapon"):
		return
	for tick in 30:
		await physics_frame
	if human._shot_sequence != 1 or human.clip != initial_clip - 1:
		failures.append("held remote pistol input must spend one bullet, not auto-repeat edges")
	if victim.health >= 100 or victim.last_damage_attacker != human or human.combat_effects.total_effect_events == 0:
		failures.append("normal server bullet trace must damage the target and emit effects")
	_human_snapshot(70)
	if not await _wait_for(func() -> bool: return network.input_for_peer(peer_id).is_empty(), "remote silence expires held fire"):
		return
	await physics_frame
	if human.last_command.get("fire", true) or human._shot_sequence != 1:
		failures.append("expired input must not continue firing or repeat the pistol press")
	_human_snapshot(80, "post")
	await _wait_for(func() -> bool: return int(network.input_for_peer(peer_id).get("buttons", 0)) == 32, "client observes final authoritative movement")
	if local_human.global_position != local_human_origin or local_human._shot_sequence != 0 or root.get_camera_3d() != local_human.camera:
		failures.append("remote RPC commands must not move/fire the host pawn or steal its camera")
	print("NETWORK_HUMAN_SIMULATION movement=", human.global_position.distance_to(origin),
		" shots=", human._shot_sequence, " clip=", human.clip, " victim_health=", victim.health)


func _human_client(port: int) -> void:
	if network.join_game("127.0.0.1", port) != OK:
		failures.append("human simulation client must connect")
		return
	if not await _wait_for(func() -> bool: return network.status.begins_with("CONNECTED"), "human client connects"):
		return
	var initial_position := Vector3.INF
	var observed_movement := false
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		var snapshot: Dictionary = network.latest_snapshot
		var stage := int(snapshot.get("tick", 0))
		if stage == 10 and not initial_position.is_finite():
			initial_position = snapshot.position
		if stage >= 50 and initial_position.is_finite() and snapshot.position.distance_to(initial_position) > 0.6:
			observed_movement = true
		if stage == 80:
			if not observed_movement:
				failures.append("client must observe server-simulated movement through production snapshots")
			# This is held input over unreliable transport, not a reliable one-shot
			# completion RPC. Keep publishing until the host consumes it and leaves.
			var acknowledgement_deadline := Time.get_ticks_msec() + 8000
			while network.is_online() and Time.get_ticks_msec() < acknowledgement_deadline:
				network.submit_local_input({"buttons": 32})
				await physics_frame
			if network.is_online():
				failures.append("Timed out: host ends verified human simulation")
			return
		if stage > 0 and stage < 70:
			network.submit_local_input({"movement": Vector2.RIGHT if stage <= 30 else Vector2.ZERO,
				"yaw": 0.7 if stage == 10 else 0.0, "pitch": -0.2 if stage == 10 else 0.0,
				"buttons": 1 if stage in [10, 60] else 0})
		await physics_frame
	failures.append("Timed out: authoritative human simulation stages")
