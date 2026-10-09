extends SceneTree

## A joined remote human can change team (M) on the dedicated server: the
## switch follows CS 1.6's rules (living switch is a suicide that drops the
## bomb, the new side waits for the next round, one switch per round while
## dead), and the host replaces a bot on the new side.
## Run with: -- --dedicated --port=<free port>

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("NETWORK TEAM SWITCH: " + message)


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	await process_frame
	var network := root.get_node("NetworkSession")
	_check(network.dedicated_server and network.is_host, "dedicated host is running")

	var peer_id := 4242
	network._register_input_peer(peer_id, Time.get_ticks_msec())
	game.remote_roster._on_peer_joined(peer_id)
	_check(bool(game.select_remote_join_team(peer_id, "T").get("accepted", false)), "remote human joins T")
	_check(bool(game.select_remote_join_class(peer_id, 1).get("accepted", false)), "remote human picks a class")
	var human: PlayerController = game._remote_join_actor(peer_id)
	var actor_id: String = game._round_id_for_actor(human)
	_check(human.team == "T" and game.round_state.team_counts() == {"T": 5, "CT": 5}, "joining replaced a T bot")

	var same: Dictionary = game.select_remote_join_team(peer_id, "T")
	_check(not same.accepted and same.reason == "already_joined", "choosing the current side is rejected")

	# Carry the bomb into a living switch.
	game.round_state.phase = "live"
	game.round_state.set_player_alive(actor_id, true, human.global_position)
	human.alive = true
	for id: String in game.round_state.players:
		var row: Dictionary = game.round_state.players[id]
		row.has_c4 = id == actor_id
		game.round_state.players[id] = row
	game.round_state.bomb_owner = actor_id
	game.round_state.bomb_state = "carried"
	var switched: Dictionary = game.select_remote_join_team(peer_id, "CT")
	_check(bool(switched.get("accepted", false)), "joined human can switch to CT (%s)" % switched)
	_check(human.team == "CT" and str(game.round_state.players[actor_id].team) == "CT", "switch updates actor and kernel team")
	_check(not human.alive and not bool(game.round_state.players[actor_id].alive), "a living switch is a suicide")
	_check(game.round_state.bomb_owner != actor_id and game.round_state.bomb_state == "dropped",
		"switching away from T drops the carried bomb")
	_check(bool(game.round_state.players[actor_id].choosing_appearance), "the new side asks for a class")
	_check(game.round_state.team_counts() == {"T": 4, "CT": 5}, "the human replaced a CT bot (T keeps its bots)")
	_check(bool(game.select_remote_join_class(peer_id, 2).get("accepted", false)), "class on the new side is accepted")

	var again: Dictionary = game.select_remote_join_team(peer_id, "T")
	_check(not again.accepted and again.reason == "already_changed", "a dead player switches once per round")

	network._remove_input_peer(peer_id)
	game.remote_roster._on_peer_left(peer_id)
	await process_frame
	await process_frame
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	await process_frame
	network.disconnect_session()
	if failures.is_empty():
		print("GAME_NETWORK_TEAM_SWITCH_PASS")
	quit(0 if failures.is_empty() else 1)
