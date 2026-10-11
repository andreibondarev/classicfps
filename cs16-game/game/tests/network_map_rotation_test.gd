extends SceneTree

## Two-process map rotation contract (run by scripts/test-network-transport.mjs
## --map-rotation). The dedicated host starts on de_inferno; the client starts
## on the default de_dust2, follows the host onto de_inferno without
## disconnecting, then follows again when the concluded match rotates the host
## to de_dust2. The host re-adopts the still-connected peer on each new map.

var network: Node
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _wait_for(predicate: Callable, description: String, seconds := 60.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
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
	if role == "host":
		await _host(port)
	elif role == "client":
		await _client(port)
	else:
		failures.append("map rotation fixture requires --role")
	network.disconnect_session()
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_MAP_ROTATION_", role.to_upper(), "_PASS")
	quit(0 if failures.is_empty() else 1)


func _load_game() -> Node:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	return game


func _host(port: int) -> void:
	network.dedicated_server = true
	if network.host_game(port, "127.0.0.1") != OK:
		failures.append("loopback host must start")
		return
	var game := _load_game()
	if not await _wait_for(func() -> bool: return game.using_imported_map, "host imports its map"):
		return
	if game.map_name != "de_inferno" or network.active_map != "de_inferno":
		failures.append("dedicated host starts on --map=de_inferno, got %s/%s" % [game.map_name, network.active_map])
	print("NETWORK_TRANSPORT_READY")
	if not await _wait_for(func() -> bool: return network.multiplayer.get_peers().size() == 1, "client connects"):
		return
	var peer: int = network.multiplayer.get_peers()[0]
	if not await _wait_for(func() -> bool: return is_instance_valid(game.remote_roster.actor_for_peer(peer)), "host adopts the client"):
		return
	# Give the client time to follow onto de_inferno before rotating.
	if not await _wait_for(func() -> bool: return network.peer_player_name(peer, "") == "Rotation Client", "client reports ready on de_inferno"):
		return
	game._match_concluded = true
	var old_scene_id := game.get_instance_id()
	game._change_to_next_map()
	# Compare instance ids: the old scene is freed by the reload.
	if not await _wait_for(func() -> bool:
			return is_instance_valid(current_scene) and current_scene.get_instance_id() != old_scene_id \
				and current_scene.get("using_imported_map") == true,
			"host rebuilds on the next map"):
		return
	game = current_scene
	if game.map_name != "de_dust2" or network.active_map != "de_dust2":
		failures.append("rotation moves de_inferno -> de_dust2, got %s" % game.map_name)
	if not await _wait_for(func() -> bool: return is_instance_valid(game.remote_roster.actor_for_peer(peer)), "new map re-adopts the connected peer"):
		return
	await _wait_for(func() -> bool: return network.multiplayer.get_peers().is_empty(), "client finishes and leaves", 90.0)


func _client(port: int) -> void:
	var game := _load_game()
	if not await _wait_for(func() -> bool: return game.using_imported_map, "client imports its default map"):
		return
	if game.map_name != "de_dust2":
		failures.append("client starts on the default map")
	if network.join_game("127.0.0.1", port) != OK:
		failures.append("client must start joining")
		return
	if not await _wait_for(func() -> bool: return _client_on_map("de_inferno"), "client follows the host onto de_inferno"):
		return
	root.get_node("GameSettings").player_name = "Rotation Client"
	if not await _wait_for(func() -> bool: return _client_on_map("de_dust2"), "client follows the rotation onto de_dust2", 90.0):
		return
	if not network.is_online():
		failures.append("client stays connected through both map changes")


func _client_on_map(map: String) -> bool:
	var game := current_scene
	if not is_instance_valid(game) or game.get("map_name") != map or game.get("using_imported_map") != true:
		return false
	var view: Variant = game.get("network_client_view")
	return network.is_online() and is_instance_valid(view) and not (view.snapshot as Dictionary).is_empty() \
		and str(view.snapshot.get("map", "")) == map
