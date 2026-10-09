extends SceneTree

## Client half of scripts/test-join-leave-notices.mjs. Joins a dedicated
## server, records join/leave notices and what the HUD shows for them, and
## either leaves after --leave-after-ms or waits until it has seen
## --expect=<kind>:<name>,... (in order), then prints NOTICE_PROBE_PASS.

var _notices: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _option(name: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name):
			return argument.trim_prefix("--%s=" % name)
	return fallback


func _run() -> void:
	var network := root.get_node("NetworkSession")
	if OS.get_cmdline_user_args().has("--with-game"):
		# The real client scene, so notices travel the player's path to the HUD.
		var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(game)
		current_scene = game
		root.gui_disable_input = true
	network.notice_received.connect(func(message: Dictionary) -> void:
		_notices.append("%s:%s" % [message.kind, message.name])
		print("NOTICE %s:%s" % [message.kind, message.name])
	)
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and not network.is_online():
		await create_timer(0.05).timeout
	if not network.is_online():
		push_error("NOTICE PROBE: never connected (%s)" % network.status)
		quit(1)
		return
	print("NOTICE_PROBE_ONLINE")
	var leave_after := int(_option("leave-after-ms", "0"))
	if leave_after > 0:
		await create_timer(leave_after / 1000.0).timeout
		print("NOTICE_PROBE_PASS left notices=%s" % ",".join(_notices))
		network.disconnect_session()
		quit(0)
		return
	var expected := _option("expect", "").split(",", false)
	deadline = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline and not _contains_in_order(expected):
		await create_timer(0.05).timeout
	if not _contains_in_order(expected):
		push_error("NOTICE PROBE: expected %s, saw %s" % [expected, _notices])
		quit(1)
		return
	if not OS.get_cmdline_user_args().has("--with-game"):
		print("NOTICE_PROBE_PASS notices=%s" % ",".join(_notices))
		network.disconnect_session()
		quit(0)
		return
	# The HUD renders them in the chat area with CS 1.6's wording.
	var texts: Array = []
	for row in root.find_children("*NoticeRow*", "RichTextLabel", true, false):
		texts.append((row as RichTextLabel).get_parsed_text())
	for entry: String in expected:
		var parts := entry.split(":", true, 1)
		var wording := " has joined the game" if parts[0] == "joined" else " has left the game"
		if not texts.has(parts[1] + wording):
			push_error("NOTICE PROBE: HUD lacks '%s' in %s" % [parts[1] + wording, texts])
			quit(1)
			return
	print("NOTICE_PROBE_PASS notices=%s" % ",".join(_notices))
	network.disconnect_session()
	quit(0)


func _contains_in_order(expected: Array) -> bool:
	var index := 0
	for notice: String in _notices:
		if index < expected.size() and notice == expected[index]:
			index += 1
	return index == expected.size()
