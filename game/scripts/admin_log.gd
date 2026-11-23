extends Node

## Dedicated-server activity log for the admin service (deploy/admin).
## Enabled with --admin-log=<path>.jsonl. Appends one JSON object per line for
## connects, identities, names, team changes, disconnects (with the session's
## kills and deaths), round results and match ends, and rewrites status.json
## beside it every couple of seconds with who is online right now.

const STATUS_INTERVAL := 2.0

var game: Node
var network: Node
var _events_path := ""
var _status_path := ""
var _peers: Dictionary = {}
var _elapsed := 0.0
var _last_scores := Vector2i(-1, -1)
var _last_phase := ""
var _last_status_usec := 0
var _last_physics_frames := 0
var _last_bytes: Dictionary = {}


static func requested_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--admin-log="):
			return argument.trim_prefix("--admin-log=")
	return ""


func start(owner_game: Node, session: Node, events_path: String) -> bool:
	if events_path.is_empty() or not events_path.is_absolute_path() \
			or not DirAccess.dir_exists_absolute(events_path.get_base_dir()):
		push_error("Admin log needs an absolute path in an existing directory: %s" % events_path)
		return false
	game = owner_game
	network = session
	_events_path = events_path
	_status_path = events_path.get_base_dir().path_join("status.json")
	process_mode = Node.PROCESS_MODE_ALWAYS
	network.peer_joined.connect(_on_peer_joined)
	network.peer_left.connect(_on_peer_left)
	network.peer_name_changed.connect(_on_peer_name_changed)
	_append({"type": "game_start", "map": str(game.map_name)})
	_write_status()
	return true


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < STATUS_INTERVAL:
		return
	_elapsed = 0.0
	_poll()
	_write_status()


func _on_peer_joined(peer_id: int) -> void:
	var endpoint: Dictionary = network.peer_endpoint(peer_id)
	_peers[peer_id] = {"connected": Time.get_unix_time_from_system(), "tag": "", "name": "",
		"team": "", "actor": "", "kills": 0, "deaths": 0, "base_kills": -1, "base_deaths": -1,
		"transport": str(endpoint.transport), "address": str(endpoint.address), "port": int(endpoint.port)}
	_append({"type": "connect", "peer": peer_id, "transport": endpoint.transport,
		"address": endpoint.address, "port": endpoint.port})


func _on_peer_left(peer_id: int) -> void:
	var record: Dictionary = _peers.get(peer_id, {})
	if record.is_empty():
		return
	_refresh_peer(peer_id, record)
	_append({"type": "leave", "peer": peer_id, "tag": record.tag, "name": record.name, "team": record.team,
		"actor": record.actor, "transport": record.transport, "address": record.address,
		"kills": _session_kills(record), "deaths": _session_deaths(record),
		"seconds": roundf(Time.get_unix_time_from_system() - float(record.connected))})
	_peers.erase(peer_id)


func _on_peer_name_changed(peer_id: int, player_name: String) -> void:
	if _peers.has(peer_id) and _peers[peer_id].name != player_name:
		_peers[peer_id].name = player_name
		_append({"type": "name", "peer": peer_id, "name": player_name})


func _poll() -> void:
	for peer_id: int in _peers:
		var record: Dictionary = _peers[peer_id]
		var tag: String = network.client_tag(peer_id)
		if not tag.is_empty() and tag != record.tag:
			record.tag = tag
			_append({"type": "identify", "peer": peer_id, "tag": tag})
		var previous_team: String = record.team
		_refresh_peer(peer_id, record)
		if record.team != previous_team and record.team in ["T", "CT"]:
			_append({"type": "team", "peer": peer_id, "actor": record.actor, "team": record.team})
	var state = game.round_state
	if state == null:
		return
	var scores := Vector2i(int(state.terrorist_score), int(state.ct_score))
	if _last_scores.x >= 0 and scores != _last_scores and (scores.x > _last_scores.x or scores.y > _last_scores.y):
		_append({"type": "round_end", "t_score": scores.x, "ct_score": scores.y,
			"winner": "T" if scores.x > _last_scores.x else "CT"})
	_last_scores = scores
	var phase := str(state.phase)
	if phase == "intermission" and _last_phase != "intermission":
		_append({"type": "match_end", "t_score": scores.x, "ct_score": scores.y})
	_last_phase = phase


## Pull the actor's current identity and score; the round kernel counts kills
## and deaths for the whole match, so a session's share is the difference
## from what it had when first seen.
func _refresh_peer(peer_id: int, record: Dictionary) -> void:
	var actor: Node = game._remote_join_actor(peer_id)
	if not is_instance_valid(actor):
		return
	record.actor = str(game._round_id_for_actor(actor))
	record.team = str(actor.team)
	if str(actor.display_name) != "" and record.name == "":
		record.name = str(actor.display_name)
	var row: Dictionary = game.round_state.players.get(record.actor, {}) if game.round_state != null else {}
	if row.is_empty():
		return
	var kills := int(row.get("kills", 0))
	var deaths := int(row.get("deaths", 0))
	if int(record.base_kills) < 0 or kills < int(record.kills) or deaths < int(record.deaths):
		# First sighting, or the match reset its scoreboard: carry the session
		# total forward from here.
		record.base_kills = kills - _session_kills(record) if int(record.base_kills) >= 0 else kills
		record.base_deaths = deaths - _session_deaths(record) if int(record.base_deaths) >= 0 else deaths
	record.kills = kills
	record.deaths = deaths


func _session_kills(record: Dictionary) -> int:
	return maxi(0, int(record.kills) - maxi(0, int(record.base_kills)))


func _session_deaths(record: Dictionary) -> int:
	return maxi(0, int(record.deaths) - maxi(0, int(record.base_deaths)))


func _write_status() -> void:
	var players: Array = []
	for peer_id: int in _peers:
		var record: Dictionary = _peers[peer_id]
		var actor: Node = game._remote_join_actor(peer_id)
		players.append({"peer": peer_id, "tag": record.tag, "name": record.name, "team": record.team,
			"alive": is_instance_valid(actor) and bool(actor.alive),
			"kills": _session_kills(record), "deaths": _session_deaths(record),
			"transport": record.transport, "address": record.address,
			"connected": record.connected})
	var now_usec := Time.get_ticks_usec()
	var seconds := float(now_usec - _last_status_usec) / 1000000.0 if _last_status_usec > 0 else 0.0
	var physics_frames := Engine.get_physics_frames()
	var tick_rate := float(physics_frames - _last_physics_frames) / seconds if seconds > 0.0 else 0.0
	_last_status_usec = now_usec
	_last_physics_frames = physics_frames
	for player: Dictionary in players:
		var quality: Dictionary = network.peer_quality(int(player.peer))
		var previous: Dictionary = _last_bytes.get(player.peer, {})
		player["rtt_ms"] = quality.rtt_ms
		player["loss"] = quality.loss
		player["kbps_in"] = _kbps(int(quality.bytes_in) - int(previous.get("in", quality.bytes_in)), seconds)
		player["kbps_out"] = _kbps(int(quality.bytes_out) - int(previous.get("out", quality.bytes_out)), seconds)
		_last_bytes[player.peer] = {"in": quality.bytes_in, "out": quality.bytes_out}
	for peer_id: int in _last_bytes.keys():
		if not _peers.has(peer_id):
			_last_bytes.erase(peer_id)
	var server := {"tick_rate": snappedf(tick_rate, 0.1),
		"target_tick_rate": Engine.physics_ticks_per_second,
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"static_memory": Performance.get_monitor(Performance.MEMORY_STATIC),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	var state = game.round_state
	var status := {"ts": Time.get_unix_time_from_system(), "map": str(game.map_name), "players": players,
		"server": server,
		"bots": game._all_bots().size(),
		"round": int(state.round_number) if state != null else 0,
		"phase": str(state.phase) if state != null else "",
		"t_score": int(state.terrorist_score) if state != null else 0,
		"ct_score": int(state.ct_score) if state != null else 0}
	var temporary := _status_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(status))
	file.close()
	DirAccess.rename_absolute(temporary, _status_path)


static func _kbps(byte_delta: int, seconds: float) -> float:
	return snappedf(maxf(0.0, float(byte_delta)) * 8.0 / 1000.0 / seconds, 0.1) if seconds > 0.0 else 0.0


## Every chat line a player sends, including ones a mute blocked, for the
## admin's chat log.
func log_chat(peer_id: int, sender_name: String, team: String, team_only: bool, text: String, blocked: bool) -> void:
	_append({"type": "chat", "peer": peer_id, "tag": str(network.client_tag(peer_id)), "name": sender_name,
		"team": team, "team_only": team_only, "text": text, "blocked": blocked})


## Moderation outcomes (kicks and ban refusals) reported by moderation.gd.
func record(event: Dictionary) -> void:
	_append(event.duplicate())


func _append(event: Dictionary) -> void:
	event["ts"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(_events_path, FileAccess.READ_WRITE if FileAccess.file_exists(_events_path) else FileAccess.WRITE)
	if file == null:
		push_error("Admin log cannot write %s" % _events_path)
		return
	file.seek_end()
	file.store_line(JSON.stringify(event))
	file.close()
