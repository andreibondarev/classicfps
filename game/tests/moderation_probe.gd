extends SceneTree

## Client half of scripts/test-moderation.mjs. Joins a dedicated server
## (--join/--port), optionally picks a team and sends chat lines (--chat=a|b),
## prints MODERATION_PROBE_READY, then waits for the host to drop it and checks
## the status it shows (--expect-status=<prefix>). --expect-refused waits for
## the drop without requiring the world to load first (banned players).

var _latest := {}


func _initialize() -> void:
	_run.call_deferred()


func _option(name: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name):
			return argument.trim_prefix("--%s=" % name)
	return fallback


func _fail(message: String) -> void:
	push_error("MODERATION PROBE: " + message)
	quit(1)


func _run() -> void:
	var network := root.get_node("NetworkSession")
	var expected := _option("expect-status", "")
	network.world_snapshot_received.connect(func(snapshot: Dictionary) -> void: _latest = snapshot)
	if OS.get_cmdline_user_args().has("--expect-refused"):
		await _await_drop(network, expected, 20000)
		return
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and _latest.is_empty():
		await create_timer(0.05).timeout
	if _latest.is_empty():
		_fail("no world snapshot (status=%s)" % network.status)
		return
	var team := _option("team", "")
	if not team.is_empty():
		network.request_join_team(team)
		await create_timer(1.0).timeout
		network.request_join_class(1)
		await create_timer(1.0).timeout
	for line in _option("chat", "").split("|", false):
		if not network.request_chat(line, false):
			_fail("chat request refused locally: " + line)
			return
		await create_timer(0.6).timeout
	print("MODERATION_PROBE_READY")
	await _await_drop(network, expected, 60000)


func _await_drop(network: Node, expected: String, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline and (network.is_online() or network.is_connecting()):
		await create_timer(0.05).timeout
	if network.is_online() or network.is_connecting():
		_fail("still connected (status=%s)" % network.status)
		return
	if not str(network.status).begins_with(expected):
		_fail("status %s does not start with %s" % [network.status, expected])
		return
	print("MODERATION_PROBE_PASS status=%s" % network.status)
	quit(0)
