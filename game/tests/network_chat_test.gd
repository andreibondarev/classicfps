extends SceneTree

const SessionScript := preload("res://scripts/network_session.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _request(sequence: int, text: Variant, team_only := false) -> Dictionary:
	return {"version": 1, "sequence": sequence, "team_only": team_only, "text": text}


func _run() -> void:
	await _test_session_contract()
	await _test_authoritative_team_routing()
	_finish()


func _test_session_contract() -> void:
	var session := SessionScript.new()
	root.add_child(session)
	session.is_host = true
	session._world_epoch = 7
	_check(session._register_input_peer(1, 100), "host chat peer registers")
	_check(session._register_input_peer(2, 100), "remote chat peer registers")
	var requests: Array[Dictionary] = []
	var messages: Array[Dictionary] = []
	session.chat_received.connect(func(message: Dictionary) -> void: messages.append(message))
	_check(session.bind_chat(func(peer_id: int, team_only: bool, text: String) -> bool:
		requests.append({"peer": peer_id, "team_only": team_only, "text": text})
		return session.publish_chat("remote_human_1", "Remote André", "T", team_only, text, [1])
	), "one authoritative chat handler binds")

	_check(
		session.accept_peer_chat_request(2, _request(1, "Rush B!", true), 100),
		"registered remote chat request is accepted",
	)
	_check(requests.size() == 1 and requests[0] == {"peer": 2, "team_only": true, "text": "Rush B!"},
		"request carries only sender-owned text and channel choice")
	_check(messages.size() == 1 and messages[0].sender_name == "Remote André" \
		and messages[0].team == "T" and messages[0].team_only and messages[0].text == "Rush B!",
		"host publishes authoritative identity and team")
	_check(not session.accept_peer_chat_request(2, _request(1, "Replay"), 100),
		"duplicate chat sequence is rejected")
	for bad: Variant in [null, [], "chat", _request(2, ""), _request(2, " padded "),
			_request(2, "line\nbreak"), _request(2, "x".repeat(121)),
			{"version": 1, "sequence": 2, "team_only": false, "text": "Spoof", "sender_name": "Admin"}]:
		_check(session.validate_chat_request(bad).is_empty(), "malformed or spoofable chat request is rejected")
	_check(not session.accept_peer_chat_request(99, _request(1, "Unknown"), 100),
		"unknown sender cannot chat")

	# The first message used one of four burst tokens; three more are accepted,
	# then the peer waits for the one-message-per-second refill.
	for sequence in range(2, 5):
		_check(session.accept_peer_chat_request(2, _request(sequence, "Message %d" % sequence), 100),
			"bounded chat burst accepts message %d" % sequence)
	_check(not session.accept_peer_chat_request(2, _request(5, "Flood"), 100),
		"chat flood is rate limited")
	_check(session.accept_peer_chat_request(2, _request(6, "Recovered"), 1100),
		"chat budget refills after one second")

	var event := {"version": 1, "epoch": 8, "sequence": 1, "sender_id": "player",
		"sender_name": "[P47] André", "team": "CT", "team_only": false, "text": "Ready?"}
	_check(not session.validate_chat_event(event).is_empty(), "canonical authoritative chat event validates")
	_check(session.accept_chat_event(event), "new authoritative chat event is accepted")
	_check(not session.accept_chat_event(event), "duplicate authoritative chat event is rejected")
	var forged := event.duplicate()
	forged.sender_name = "Admin\nServer"
	_check(session.validate_chat_event(forged).is_empty(), "multi-line authoritative identity is rejected")
	session._remove_input_peer(2)
	_check(not session._chat_peers.has(2), "departed peer loses chat rate and sequence state")
	session.disconnect_session()
	_check(session._chat_request_sequence == 0 and session._last_chat_sequence == 0,
		"disconnect resets chat ordering")
	session.queue_free()
	await process_frame


func _test_authoritative_team_routing() -> void:
	var network := root.get_node("NetworkSession")
	network.disconnect_session()
	network.is_host = true
	network._world_epoch = 11
	for peer_id in [1, 2, 3]:
		_check(network._register_input_peer(peer_id, 100), "game chat peer %d registers" % peer_id)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.remote_roster._on_peer_joined(2)
	game.remote_roster._on_peer_joined(3)
	var teammate: PlayerController = game.remote_roster.actor_for_peer(2)
	var opponent: PlayerController = game.remote_roster.actor_for_peer(3)
	game.player.configure_identity("T", "Host")
	teammate.configure_identity("T", "Teammate")
	opponent.configure_identity("CT", "Opponent")
	var team_recipients: Array[int] = game._chat_recipient_peers(2, "T", true)
	_check(team_recipients.has(1) and team_recipients.has(2) and not team_recipients.has(3),
		"team chat reaches host teammate and sender but not the opposing player")
	var all_recipients: Array[int] = game._chat_recipient_peers(2, "T", false)
	_check(all_recipients.has(1) and all_recipients.has(2) and all_recipients.has(3),
		"all-chat reaches both teams")
	_check(game._handle_network_chat(2, true, "Hold this site"),
		"host turns a remote request into an authoritative HUD message")
	_check(game.hud.chat_feed_box.get_child_count() == 1 \
		and (game.hud.chat_feed_box.get_child(0) as RichTextLabel).get_parsed_text().contains("(TEAM) Teammate :  Hold this site"),
		"host sees routed team message with authoritative display name")
	game._broadcast_radio_message(teammate, "ct_coverme", 2)
	_check(is_instance_valid(game.hud._radio_line_label)
		and game.hud._radio_line_label.text == "Teammate (RADIO): Cover me!",
		"team radio uses authoritative sender identity and stock message text")
	# The radio line above starts a pooled voice clip; stop it and release the
	# shared model caches so the process exits without leaked resources.
	if is_instance_valid(game._radio_voice):
		game._radio_voice.stop()
		game._radio_voice.stream = null
	game.audio_router.stop_all("test_teardown")
	game.audio_playback.clear_pool()
	# The audio thread drops a stopped clip on its next mix, not immediately.
	await create_timer(0.5).timeout
	game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	CS16CombatEffects.release_cached_resources()
	MdlCharacterModel.release_cached_resources()
	network.disconnect_session()


func _finish() -> void:
	for failure in failures:
		push_error(failure)
	print("GAME_NETWORK_CHAT_PASS" if failures.is_empty() else "GAME_NETWORK_CHAT_FAIL")
	quit(0 if failures.is_empty() else 1)
