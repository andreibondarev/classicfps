extends SceneTree

var failures: Array[String] = []
var calls: Array[Dictionary] = []
var network: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _command(sequence: int, action := "join_team", value: Variant = "T") -> Dictionary:
	return {"version": network.PROTOCOL_VERSION, "sequence": sequence, "action": action, "value": value}


func _handle(peer_id: int, command: Dictionary) -> Dictionary:
	calls.append({"peer": peer_id, "command": command.duplicate()})
	return {"accepted": true, "actor_id": "remote_human_1", "team": "T",
		"class_id": int(command.value) if command.action == "join_class" else 0,
		"spawned": command.action == "join_class"}


func _run() -> void:
	network = root.get_node("NetworkSession")
	network.disconnect_session()
	_check(network.request_join_team("T") == 0 and network._action_sequence == 0,
		"offline submissions do not reserve requests")
	var valid := _command(1)
	_check(network.validate_action(valid) == valid and network.validate_action(_command(2, "join_class", 4)).size() == 4,
		"canonical team/class requests round-trip")
	for bad in [null, [], "action", true, 1]:
		_check(network.validate_action(bad).is_empty(), "wrong top-level request rejected")
	for field: String in valid:
		var missing := valid.duplicate()
		missing.erase(field)
		_check(network.validate_action(missing).is_empty(), "missing request field rejected: " + field)
	for pair: Array in [["version", 2], ["version", true], ["sequence", 0], ["sequence", 1.0],
		["sequence", network.MAX_COUNTER + 1], ["action", "buy"], ["action", []], ["value", "UNASSIGNED"],
		["value", true], ["value", NAN], ["owner", 1], ["actor_id", "player"]]:
		var bad := valid.duplicate()
		bad[pair[0]] = pair[1]
		_check(network.validate_action(bad).is_empty(), "bad request field rejected: " + str(pair[0]))
	for value in [0, 5, 1.0, true, "1", NAN, {}]:
		_check(network.validate_action(_command(1, "join_class", value)).is_empty(), "bad class value rejected")
	for item: String in ["ak47", "vest", "primammo", "defuser"]:
		_check(not network.validate_action(_command(1, "buy_item", item)).is_empty(), "bounded buy identifier accepted")
	for value in ["", "../ak47", "a".repeat(33), "ak47;quit", 1, true, {}, ["ak47"]]:
		_check(network.validate_action(_command(1, "buy_item", value)).is_empty(), "invalid buy payload rejected")
	_check(not network.validate_action(_command(1, "radio", "ct_coverme")).is_empty(),
		"stock radio sample is an allowed bounded action")
	for value in ["", "../radio/ct_coverme", "invented", 1, true, {}]:
		_check(network.validate_action(_command(1, "radio", value)).is_empty(),
			"unlisted radio payload rejected")
	var forged := _command(1, "buy_item", "ak47")
	forged.price = 0
	_check(network.validate_action(forged).is_empty(), "client cannot supply purchase price")
	for action: String in ["select_weapon", "secondary", "drop_weapon"]:
		for weapon: String in network.WorldState.Weapons.WEAPONS:
			_check(not network.validate_action(_command(1, action, weapon)).is_empty(), "known weapon action accepted: " + action + ":" + weapon)
		for value in ["", "invented", "AK47", "weapon_ak47", 1, true, {}, ["knife"]]:
			_check(network.validate_action(_command(1, action, value)).is_empty(), "invalid weapon identifier rejected")
	network.is_host = true
	network._register_input_peer(7, 1000)
	network._register_input_peer(1, 1000)
	_check(network.accept_peer_action(99, valid, 1000).is_empty()
		and network.accept_peer_action(1, valid, 1000).is_empty(), "unknown/local peer cannot use remote action path")
	_check(network.accept_peer_action(7, valid, 1000).reason == "no_game", "unbound game returns explicit failure")
	_check(network.bind_game_actions(_handle), "host action handler binds")
	_check(not network.bind_game_actions(func(_peer: int, _command: Dictionary) -> Dictionary: return {}),
		"another game cannot steal a live handler")
	var malformed := _command(999)
	malformed.owner = 1
	_check(network.accept_peer_action(7, malformed, 1000).is_empty(), "spoofed owner is inert")
	var result: Dictionary = network.accept_peer_action(7, _command(2), 1000)
	_check(result.accepted and result.actor_id == "remote_human_1" and calls.size() == 1 and calls[0].peer == 7,
		"handler receives only registered sender and validated detached command")
	_check(network.accept_peer_action(7, _command(2), 1000).is_empty()
		and network.accept_peer_action(7, _command(1), 1000).is_empty() and calls.size() == 1,
		"replayed/out-of-order requests cannot repeat side effects")
	var accepted := 2  # no_game and successful request already consumed two tokens.
	for sequence in range(3, 30):
		var response: Dictionary = network.accept_peer_action(7, _command(sequence), 1000)
		if response.accepted:
			accepted += 1
		else:
			_check(response.reason == "rate_limited", "valid excess requests receive explicit rate limit replies")
	_check(accepted == network.ACTION_BURST and calls.size() == network.ACTION_BURST - 1,
		"host gameplay dispatch stays within accepted-action burst")
	_check(network.accept_peer_action(7, _command(30), 999).is_empty(), "backward clock cannot reopen acceptance")
	network._register_input_peer(8, 1000)
	_check(network.accept_peer_action(8, valid, 1000).accepted, "peers have independent action allowances")
	_check(network.accept_peer_action(7, _command(30, "join_class", 4), 1125).spawned, "one token refills at rate boundary")
	_check(network.accept_peer_input(7, network.sanitize_input({}, 1), 1125), "action bursts do not consume movement allowance")
	var before_switches := calls.size()
	var selected := _command(31, "select_weapon", "knife")
	_check(network.accept_peer_action(7, selected, 1250).accepted and calls.size() == before_switches + 1,
		"weapon selection uses registered sender and reliable dispatch")
	_check(network.accept_peer_action(7, selected, 1250).is_empty() and calls.size() == before_switches + 1,
		"replayed weapon selection never resets deploy again")
	network._remove_input_peer(7)
	_check(not network._action_peers.has(7) and network.accept_peer_action(7, _command(31), 1200).is_empty(),
		"departure clears action replay history and ownership")
	network._register_input_peer(7, 1200)
	_check(network.accept_peer_action(7, valid, 1200).accepted, "fresh connection starts with sequence one")
	network.unbind_game_actions(_handle)
	_check(network.accept_peer_action(7, _command(2), 1200).reason == "no_game", "teardown removes gameplay handler")

	# Result validation never lets an unsolicited/malformed reply consume a
	# pending request or claim a different selection than the caller made.
	network.disconnect_session()
	var reply := {"version": 1, "sequence": 1, "action": "join_team", "accepted": true,
		"reason": "", "actor_id": "remote_human_1", "team": "T", "class_id": 0, "spawned": false}
	_check(network.validate_action_result(reply) == reply, "canonical result round-trips")
	for bad in [null, [], "reply", true, 1]:
		_check(network.validate_action_result(bad).is_empty(), "wrong top-level reply rejected")
	for field: String in reply:
		var missing := reply.duplicate()
		missing.erase(field)
		_check(network.validate_action_result(missing).is_empty(), "missing result field rejected: " + field)
	for pair: Array in [["version", 2], ["sequence", 0], ["action", "buy"], ["accepted", 1],
		["reason", "invented"], ["reason", "team_full"], ["actor_id", "player"], ["actor_id", "remote_human_01"],
		["actor_id", "remote_human_0"], ["actor_id", ""], ["team", "UNASSIGNED"], ["class_id", true],
		["class_id", 1], ["spawned", true], ["owner", 7]]:
		var bad := reply.duplicate()
		bad[pair[0]] = pair[1]
		_check(network.validate_action_result(bad).is_empty(), "bad result rejected: " + str(pair[0]))
	_check(not network.accept_action_result(reply), "unsolicited result ignored")
	network._pending_actions[1] = {"action": "join_class", "value": 1, "sent_ms": 0}
	_check(not network.accept_action_result(reply) and network._pending_actions.has(1), "wrong action cannot consume request")
	network._pending_actions[1] = {"action": "join_team", "value": "CT", "sent_ms": 0}
	_check(not network.accept_action_result(reply), "wrong successful team cannot consume request")
	network._pending_actions[1].value = "T"
	_check(network.accept_action_result(reply) and not network._pending_actions.has(1), "matching result completes once")
	reply.team = "CT"
	_check(network.latest_action_result.team == "T" and not network.accept_action_result(reply), "retained result detached; duplicate inert")
	network._pending_actions[2] = {"action": "join_class", "value": 2, "sent_ms": 1000}
	network.expire_actions(1000 + network.ACTION_TIMEOUT_MS - 1)
	_check(network._pending_actions.has(2), "request stays pending before timeout")
	network.expire_actions(1000 + network.ACTION_TIMEOUT_MS)
	_check(network._pending_actions.is_empty() and network.latest_action_result.reason == "timeout",
		"unanswered action expires with explicit unknown-outcome failure")
	network._pending_actions[3] = {"action": "join_team", "value": "T", "sent_ms": 0}
	network._pending_actions[4] = {"action": "join_team", "value": "T", "sent_ms": 0}
	network.action_result_received.connect(func(_result: Dictionary) -> void: network.disconnect_session(), CONNECT_ONE_SHOT)
	network.expire_actions(network.ACTION_TIMEOUT_MS)
	_check(network._pending_actions.is_empty() and network._action_peers.is_empty()
		and network.latest_action_result.is_empty() and network._action_sequence == 0,
		"timeout callback may disconnect safely and clear all request state")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_ACTION_PASS")
	quit(0 if failures.is_empty() else 1)
