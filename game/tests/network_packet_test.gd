extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var network := root.get_node("NetworkSession")
	var input: Dictionary = network.sanitize_input({"yaw": NAN, "pitch": INF}, 1)
	_check(is_finite(input.yaw) and is_finite(input.pitch), "non-finite local look must normalize to finite values")
	var snapshot: Dictionary = network.sanitize_snapshot({"round_time": INF})
	_check(is_finite(snapshot.round_time), "non-finite snapshot time must normalize to a finite value")
	network._input_sequence = 42
	network._snapshot_accumulator = 0.04
	network.disconnect_session()
	_check(network._input_sequence == 0 and network._snapshot_accumulator == 0.0, "disconnect must reset session counters")
	if not network.has_method("validate_input") or not network.has_method("accept_peer_input"):
		failures.append("strict packet validation and peer input acceptance must exist")
		_finish()
		return
	# Local normalization must not throw on malformed variants.
	input = network.sanitize_input({"movement": "bad", "yaw": {}, "pitch": [], "buttons": "63"}, -1)
	_check(input.movement == Vector2.ZERO and input.buttons == 0, "wrong local types normalize without coercing strings")
	snapshot = network.sanitize_snapshot({"position": [], "velocity": {}, "health": "99", "phase": []})
	_check(snapshot.position == Vector3.ZERO and snapshot.velocity == Vector3.ZERO, "wrong snapshot vector types normalize safely")
	var valid: Dictionary = network.sanitize_input({"movement": Vector2(0.6, 0.8), "yaw": 0.5, "pitch": -0.2, "buttons": 17}, 1)
	_check(not network.validate_input(valid).is_empty(), "canonical input round-trips")
	for bad in [null, [], "input", 7, true]:
		_check(network.validate_input(bad).is_empty(), "wrong top-level input type is rejected")
	for field: String in valid:
		var missing := valid.duplicate()
		missing.erase(field)
		_check(network.validate_input(missing).is_empty(), "missing input field rejected: " + field)
	for pair: Array in [["version", 999], ["sequence", 0], ["sequence", "2"], ["sequence", 1.5],
		["movement", []], ["movement", Vector2(INF, 0.0)], ["yaw", NAN], ["yaw", "1.0"],
		["pitch", INF], ["buttons", -1], ["buttons", 128], ["buttons", true], ["owner", 7]]:
		var invalid := valid.duplicate()
		invalid[pair[0]] = pair[1]
		_check(network.validate_input(invalid).is_empty(), "invalid input field rejected: " + str(pair[0]))
	_check(not network.accept_peer_input(7, valid, 1000), "unknown transport sender cannot create input state")
	_check(network._register_input_peer(7, 1000), "connected peer registers")
	_check(not network._register_input_peer(7, 1000), "duplicate registration cannot reset replay protection")
	_check(network.accept_peer_input(7, valid, 1000), "registered peer input accepted")
	_check(not network.accept_peer_input(7, valid, 1100), "duplicate input rejected")
	var malformed := valid.duplicate()
	malformed.sequence = 999
	malformed.yaw = NAN
	_check(not network.accept_peer_input(7, malformed, 1100), "malformed packet cannot poison sequence history")
	var next := valid.duplicate()
	next.sequence = 2
	_check(network.accept_peer_input(7, next, 1110), "valid input after malformed packet accepted")
	next.buttons = 0
	_check(network.latest_inputs[7].buttons == 17, "stored input is detached from caller dictionary")
	network.expire_inputs(1110 + network.INPUT_TIMEOUT_MS - 1)
	_check(network.latest_inputs.has(7), "input remains available before timeout")
	network.expire_inputs(1110 + network.INPUT_TIMEOUT_MS)
	_check(not network.latest_inputs.has(7), "held input expires at timeout")
	_check(not network.accept_peer_input(7, valid, 2000), "expiry does not reset replay protection")
	var accepted := 0
	for sequence in range(3, 103):
		var burst := valid.duplicate()
		burst.sequence = sequence
		if network.accept_peer_input(7, burst, 2000):
			accepted += 1
	_check(accepted == network.INPUT_BURST, "accepted input burst is bounded")
	_check(network._register_input_peer(8, 2000) and network.accept_peer_input(8, valid, 2000), "one peer's burst cannot consume another peer's allowance")
	var recovered := valid.duplicate()
	recovered.sequence = 103
	_check(network.accept_peer_input(7, recovered, 2100), "rate limit refills after elapsed time")
	_check(not network.accept_peer_input(7, recovered, 2000), "backward clock cannot reopen acceptance")
	network._remove_input_peer(7)
	_check(not network.latest_inputs.has(7), "departure removes held input")
	_check(network._register_input_peer(7, 3000) and network.accept_peer_input(7, valid, 3000), "fresh connection starts new sequence history")
	var state: Dictionary = network.sanitize_snapshot({"tick": 10, "position": Vector3(1, 2, 3), "velocity": Vector3(2, 0, 0), "health": 80, "phase": "live", "round_time": 30.0})
	_check(not network.validate_snapshot(state).is_empty(), "canonical snapshot round-trips")
	for bad in [null, [], "snapshot", 7, true]:
		_check(network.validate_snapshot(bad).is_empty(), "wrong top-level snapshot type is rejected")
	for field: String in state:
		var missing := state.duplicate()
		missing.erase(field)
		_check(network.validate_snapshot(missing).is_empty(), "missing snapshot field rejected: " + field)
	for pair: Array in [["version", 999], ["tick", -1], ["tick", "10"], ["position", []],
		["position", Vector3(NAN, 0, 0)], ["velocity", Vector3(1000, 0, 0)],
		["health", 200], ["health", "80"], ["phase", "invented"], ["round_time", INF], ["owner", 7]]:
		var invalid := state.duplicate()
		invalid[pair[0]] = pair[1]
		_check(network.validate_snapshot(invalid).is_empty(), "invalid snapshot field rejected: " + str(pair[0]))
	_check(network.accept_snapshot(state), "new snapshot accepted")
	_check(not network.accept_snapshot(state), "duplicate snapshot rejected")
	state.tick = 9
	_check(not network.accept_snapshot(state), "out-of-order snapshot rejected")
	state.tick = 11
	_check(network.accept_snapshot(state), "later snapshot accepted")
	network.disconnect_session()
	_check(network.latest_inputs.is_empty() and network.latest_snapshot.is_empty(), "disconnect clears input and snapshot state")
	state.tick = 0
	_check(network.accept_snapshot(state), "disconnect resets snapshot history")
	network.disconnect_session()
	for peer in range(1, network.MAX_CLIENTS + 2):
		_check(network._register_input_peer(peer, 0), "configured peer capacity can register")
	_check(not network._register_input_peer(999, 0), "unknown peers cannot grow storage beyond configured capacity")
	_check(not network._register_input_peer(0, 0), "invalid transport identity is rejected")
	network.disconnect_session()
	_check(network._register_input_peer(7, 0), "steady-rate peer registers")
	for sequence in range(1, 201):
		var steady := valid.duplicate()
		steady.sequence = sequence
		_check(network.accept_peer_input(7, steady, sequence * 10), "normal 100-Hz input must not be throttled")
	network.disconnect_session()
	network.submit_local_input({"buttons": 1})
	_check(network._input_sequence == 0 and network.latest_inputs.is_empty(), "offline input does not advance network state")
	_finish()


func _finish() -> void:
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_PACKET_PASS")
	quit(0 if failures.is_empty() else 1)
