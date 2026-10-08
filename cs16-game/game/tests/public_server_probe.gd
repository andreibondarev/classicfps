extends SceneTree

var _world_received := false
var _world := {}


func _initialize() -> void:
	_run.call_deferred()


func _on_world(snapshot: Dictionary) -> void:
	_world_received = true
	_world = snapshot


func _run() -> void:
	var network := root.get_node("NetworkSession")
	network.world_snapshot_received.connect(_on_world)
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and not _world_received:
		await create_timer(0.05).timeout
	if not network.is_online():
		push_error("PUBLIC SERVER PROBE: transport did not connect (%s)" % network.status)
		quit(1)
		return
	if not _world_received:
		push_error("PUBLIC SERVER PROBE: connected but received no authoritative world")
		quit(1)
		return
	if str(_world.get("map", "")) != "de_dust2" or not bool(_world.get("started", false)):
		push_error("PUBLIC SERVER PROBE: invalid world metadata")
		quit(1)
		return
	var actors: Array = _world.get("actors", [])
	if actors.size() != 12:
		push_error("PUBLIC SERVER PROBE: expected server sentinel, ten combatants, and probe human; got %d actors" % actors.size())
		quit(1)
		return
	print("PUBLIC SERVER PROBE PASSED address=%s actors=%d map=%s" % [
		str(network.status).trim_prefix("CONNECTED  "), actors.size(), _world.map,
	])
	network.disconnect_session()
	quit(0)
