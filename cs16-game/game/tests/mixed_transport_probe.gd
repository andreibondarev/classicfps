extends SceneTree

## Joins a dedicated server (UDP host or ws:// URL via --join) and waits until
## the authoritative world contains --expect-actors actors, i.e. every probe
## sharing the match over either transport is visible. Lingers so the other
## probes observe this one too.

var _latest := {}


func _initialize() -> void:
	_run.call_deferred()


func _option(name: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name):
			return argument.trim_prefix("--%s=" % name)
	return fallback


func _run() -> void:
	var expected := int(_option("expect-actors", "13"))
	var linger_ms := int(_option("linger-ms", "3000"))
	var network := root.get_node("NetworkSession")
	network.world_snapshot_received.connect(func(snapshot: Dictionary) -> void: _latest = snapshot)
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and (_latest.get("actors", []) as Array).size() != expected:
		await create_timer(0.05).timeout
	var actors: Array = _latest.get("actors", [])
	if not network.is_online() or actors.size() != expected or str(_latest.get("map", "")) != "de_dust2":
		push_error("MIXED TRANSPORT PROBE: status=%s actors=%d expected=%d" % [network.status, actors.size(), expected])
		quit(1)
		return
	var linger_until := Time.get_ticks_msec() + linger_ms
	while Time.get_ticks_msec() < linger_until and network.is_online():
		await create_timer(0.05).timeout
	if not network.is_online():
		push_error("MIXED TRANSPORT PROBE: lost the session while lingering")
		quit(1)
		return
	# The host pings every 2 s, so after lingering this probe's own row carries a
	# measured round trip for the scoreboard; bots never do.
	var own_ping := -1
	for row: Dictionary in _latest.get("actors", []):
		if row.kind == "bot" and int(row.ping) != -1:
			push_error("MIXED TRANSPORT PROBE: bot %s reports ping %d" % [row.id, row.ping])
			quit(1)
			return
		if row.id == _latest.get("owner_id", ""):
			own_ping = int(row.ping)
	if linger_ms >= 3000 and own_ping < 0:
		push_error("MIXED TRANSPORT PROBE: own ping was never measured")
		quit(1)
		return
	print("MIXED_TRANSPORT_PROBE_PASS status=%s actors=%d ping=%d" % [network.status, actors.size(), own_ping])
	network.disconnect_session()
	quit(0)
